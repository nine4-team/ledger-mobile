import Foundation
import LedgerTargetCore
import PowerSync

enum CurrentItemPlacementReadFailure: Error, Equatable {
    case accountUnavailable
    case incompleteOrConflictingPlacement
}

/// Downloaded physical facts only. Not a complete inventory/accounting snapshot
/// or an assignment precondition: movement commands must first share a proven
/// revision contract. No subscription or new server access is granted here.
struct CurrentItemPlacementLocalReader: Sendable {
    let database: any PowerSyncDatabaseProtocol

    struct HistoryRow: Sendable {
        let description: String
        let interval: PhysicalItemPlacementHistoryInterval?
    }

    func readHistory(accountId: AccountID, principalId: PrincipalID, itemId: ItemID) async throws -> DownloadedItemPlacementHistory {
        let rows = try await database.getAll(sql: Self.historySQL,
            parameters: [accountId.rawValue, principalId.rawValue, accountId.rawValue, itemId.rawValue],
            mapper: Self.historyRow)
        return try Self.history(accountId: accountId, itemId: itemId, rows: rows)
    }

    func watchHistory(accountId: AccountID, principalId: PrincipalID, itemId: ItemID) throws -> AsyncThrowingStream<[HistoryRow], Error> {
        try database.watch(sql: Self.historySQL,
            parameters: [accountId.rawValue, principalId.rawValue, accountId.rawValue, itemId.rawValue],
            mapper: Self.historyRow)
    }

    static func history(accountId: AccountID, itemId: ItemID, rows: [HistoryRow]) throws -> DownloadedItemPlacementHistory {
        guard let description = rows.first?.description, rows.allSatisfy({ $0.description == description }) else {
            throw CurrentItemPlacementReadFailure.incompleteOrConflictingPlacement
        }
        let intervals = try rows.compactMap(\.interval).map { interval in
            (interval: interval, start: try HistoryInstant(interval.startedAt),
             end: try interval.endedAt.map(HistoryInstant.init))
        }.sorted { left, right in
            if left.start != right.start { return left.start < right.start }
            return left.interval.placementId.rawValue.utf8.lexicographicallyPrecedes(right.interval.placementId.rawValue.utf8)
        }
        var previousEnd: HistoryInstant?
        var hasOpenInterval = false
        for value in intervals {
            guard value.end.map({ $0 >= value.start }) ?? true else {
                throw CurrentItemPlacementReadFailure.incompleteOrConflictingPlacement
            }
            // Empty intervals carry historical evidence but occupy no time.
            if value.end == value.start { continue }
            guard !hasOpenInterval, previousEnd.map({ $0 <= value.start }) ?? true else {
                throw CurrentItemPlacementReadFailure.incompleteOrConflictingPlacement
            }
            previousEnd = value.end; hasOpenInterval = value.end == nil
        }
        return try DownloadedItemPlacementHistory(accountId: accountId, itemId: itemId,
            description: description, intervals: intervals.reversed().map(\.interval))
    }

    /// Comparison key only; raw downloaded timestamps remain the displayed
    /// evidence. Stripping fractions before Date parsing avoids SQLite/Double
    /// millisecond rounding at adjacent interval boundaries.
    private struct HistoryInstant: Comparable {
        let seconds: Int64
        let nanoseconds: Int
        init(_ raw: String) throws {
            let pattern = #"^[0-9]{4}-[0-9]{2}-[0-9]{2}(?:[T ][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,9})?(?:Z|[+-][0-9]{2}(?::?[0-9]{2})?))?$"#
            let regex = try NSRegularExpression(pattern: pattern)
            guard let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
                  match.range.length == raw.utf16.count else {
                throw CurrentItemPlacementReadFailure.incompleteOrConflictingPlacement
            }
            var whole = raw
            if let range = Range(match.range(at: 1), in: raw) {
                let fraction = String(raw[range].dropFirst())
                guard let nanos = Int(fraction + String(repeating: "0", count: 9 - fraction.count)) else {
                    throw CurrentItemPlacementReadFailure.incompleteOrConflictingPlacement
                }
                nanoseconds = nanos
                whole.removeSubrange(range)
            } else { nanoseconds = 0 }
            if whole.count == 10 { whole += "T00:00:00Z" }
            let fields = whole.prefix(19).split(whereSeparator: { "-T :".contains($0) }).compactMap { Int($0) }
            guard fields.count == 6, fields[0] > 0, (1...12).contains(fields[1]),
                  (1...31).contains(fields[2]), (0...23).contains(fields[3]),
                  (0...59).contains(fields[4]), (0...59).contains(fields[5]),
                  let utc = TimeZone(secondsFromGMT: 0) else {
                throw CurrentItemPlacementReadFailure.incompleteOrConflictingPlacement
            }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = utc
            let components = DateComponents(year: fields[0], month: fields[1], day: fields[2],
                hour: fields[3], minute: fields[4], second: fields[5])
            guard let date = calendar.date(from: components),
                  calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date) == components else {
                throw CurrentItemPlacementReadFailure.incompleteOrConflictingPlacement
            }
            let zone = String(whole.dropFirst(19))
            var offsetSeconds = 0
            if zone != "Z" {
                let digits = zone.dropFirst().filter { $0 != ":" }
                guard let hours = Int(digits.prefix(2)), let minutes = Int(digits.count == 2 ? "0" : String(digits.suffix(2))),
                      hours <= 23, minutes <= 59 else {
                    throw CurrentItemPlacementReadFailure.incompleteOrConflictingPlacement
                }
                offsetSeconds = (hours * 3600 + minutes * 60) * (zone.first == "-" ? -1 : 1)
            }
            seconds = Int64(date.timeIntervalSince1970.rounded()) - Int64(offsetSeconds)
        }
        static func < (left: Self, right: Self) -> Bool {
            left.seconds == right.seconds ? left.nanoseconds < right.nanoseconds : left.seconds < right.seconds
        }
    }

    private static func historyRow(cursor: any SqlCursor) throws -> HistoryRow {
        guard try cursor.getInt(name: "is_active") == 1 else { throw CurrentItemPlacementReadFailure.accountUnavailable }
        guard let description = try cursor.getStringOptional(name: "description"),
              try cursor.getIntOptional(name: "revision").map({ $0 > 0 }) == true,
              try cursor.getInt(name: "invalid_count") == 0 else {
            throw CurrentItemPlacementReadFailure.incompleteOrConflictingPlacement
        }
        guard let id = try cursor.getStringOptional(name: "placement_id") else {
            return HistoryRow(description: description, interval: nil)
        }
        let scope: ItemPlacementScope
        switch try cursor.getString(name: "scope_kind") {
        case "business_inventory": scope = .businessInventory
        case "project": scope = .project(try ProjectID(validating: cursor.getString(name: "project_id")))
        default: throw CurrentItemPlacementReadFailure.incompleteOrConflictingPlacement
        }
        return try HistoryRow(description: description, interval: PhysicalItemPlacementHistoryInterval(
            placementId: EntityID(validating: id), scope: scope,
            spaceId: cursor.getStringOptional(name: "space_id").map { try SpaceID(validating: $0) },
            projectDisplayName: cursor.getStringOptional(name: "project_name"),
            spaceDisplayName: cursor.getStringOptional(name: "space_name"),
            startedAt: cursor.getString(name: "started_at"), endedAt: cursor.getStringOptional(name: "ended_at")))
    }

    private static let historySQL = """
      WITH access AS (
        SELECT EXISTS(SELECT 1 FROM spike_account_memberships
          WHERE account_id=? AND principal_id=? AND state='active') AS is_active
      ), selected_item AS (
        SELECT id,account_id,description,revision FROM spike_items WHERE account_id=? AND id=?
      ), placements AS (
        SELECT p.* FROM spike_item_placements p JOIN selected_item i
          ON p.account_id=i.account_id AND p.item_id=i.id
      ), validity AS (
        SELECT count(*) AS invalid_count FROM placements p
        WHERE p.scope_kind IS NULL OR p.scope_kind NOT IN ('business_inventory','project')
          OR (p.scope_kind='project' AND p.project_id IS NULL)
          OR (p.scope_kind='business_inventory' AND p.project_id IS NOT NULL)
          OR p.started_at IS NULL
          OR EXISTS(SELECT 1 FROM spike_spaces s WHERE s.id=p.space_id AND s.account_id=p.account_id
            AND (s.scope_kind IS NOT p.scope_kind OR s.project_id IS NOT p.project_id))
      )
      SELECT access.is_active,i.description,i.revision,validity.invalid_count,
        p.id AS placement_id,p.scope_kind,p.project_id,p.space_id,p.started_at,p.ended_at,
        project.display_name AS project_name,space.display_name AS space_name
      FROM access CROSS JOIN validity LEFT JOIN selected_item i ON access.is_active
      LEFT JOIN placements p ON access.is_active
      LEFT JOIN spike_projects project ON project.id=p.project_id AND project.account_id=p.account_id
      LEFT JOIN spike_spaces space ON space.id=p.space_id AND space.account_id=p.account_id
        AND space.scope_kind=p.scope_kind AND space.project_id IS p.project_id
      ORDER BY p.id
      """

    func read(accountId: AccountID, principalId: PrincipalID, scope: ItemPlacementScope) async throws -> [PhysicalItemPlacement] {
        let rows: [PhysicalItemPlacement?] = try await database.getAll(sql: Self.sql,
            parameters: Self.parameters(accountId: accountId, principalId: principalId, scope: scope)) {
                try Self.row(cursor: $0, scope: scope)
            }
        return rows.compactMap { $0 }
    }

    static func read(transaction: any Transaction, accountId: AccountID,
                     principalId: PrincipalID, scope: ItemPlacementScope) throws -> [PhysicalItemPlacement] {
        try transaction.getAll(sql: sql,
            parameters: parameters(accountId: accountId, principalId: principalId, scope: scope)) {
                try row(cursor: $0, scope: scope)
            }.compactMap { $0 }
    }

    func watch(accountId: AccountID, principalId: PrincipalID, scope: ItemPlacementScope) throws -> AsyncThrowingStream<[PhysicalItemPlacement?], Error> {
        try database.watch(sql: Self.sql,
            parameters: Self.parameters(accountId: accountId, principalId: principalId, scope: scope)) {
                try Self.row(cursor: $0, scope: scope)
            }
    }

    private static func parameters(accountId: AccountID, principalId: PrincipalID, scope: ItemPlacementScope) -> [Sendable?] {
        let kind: String
        let project: String?
        switch scope {
        case .businessInventory: kind = "business_inventory"; project = nil
        case .project(let id): kind = "project"; project = id.rawValue
        }
        return [accountId.rawValue, principalId.rawValue, accountId.rawValue, kind, project]
    }

    private static func row(cursor: any SqlCursor, scope: ItemPlacementScope) throws -> PhysicalItemPlacement? {
            guard try cursor.getInt(name: "is_active") == 1 else {
                throw CurrentItemPlacementReadFailure.accountUnavailable
            }
            guard let placement = try cursor.getStringOptional(name: "placement_id") else { return nil }
            guard let item = try cursor.getStringOptional(name: "item_id"),
                  let description = try cursor.getStringOptional(name: "description"),
                  let revision = try cursor.getIntOptional(name: "revision"), revision > 0,
                  try cursor.getInt(name: "active_count") == 1,
                  try cursor.getInt(name: "space_valid") == 1,
                  try cursor.getInt(name: "project_valid") == 1 else {
                throw CurrentItemPlacementReadFailure.incompleteOrConflictingPlacement
            }
            return try PhysicalItemPlacement(itemId: ItemID(validating: item),
                description: description, itemRevision: Int64(revision),
                placementId: EntityID(validating: placement), scope: scope,
                spaceId: cursor.getStringOptional(name: "space_id").map { try SpaceID(validating: $0) })
    }

    private static let sql = """
      -- Membership, parents and cross-scope duplicate checks share one snapshot.
      WITH access AS (
        SELECT EXISTS (SELECT 1 FROM spike_account_memberships
          WHERE account_id = ? AND principal_id = ? AND state = 'active') AS is_active
      ), selected AS (
        SELECT p.id AS placement_id, i.id AS item_id, i.description, i.revision, p.space_id,
          (SELECT count(*) FROM spike_item_placements other
            WHERE other.account_id = p.account_id AND other.item_id = p.item_id
              AND other.ended_at IS NULL) AS active_count,
          (p.space_id IS NULL OR s.id IS NOT NULL) AS space_valid,
          (p.scope_kind = 'business_inventory' OR project.id IS NOT NULL) AS project_valid
        FROM spike_item_placements p
        LEFT JOIN spike_items i ON i.account_id = p.account_id AND i.id = p.item_id
        LEFT JOIN spike_projects project ON project.id = p.project_id AND project.account_id = p.account_id
        LEFT JOIN spike_spaces s ON s.id = p.space_id AND s.account_id = p.account_id
          AND s.scope_kind = p.scope_kind AND s.project_id IS p.project_id
        WHERE p.account_id = ? AND p.scope_kind = ? AND p.project_id IS ? AND p.ended_at IS NULL
      )
      SELECT access.is_active, selected.* FROM access
      LEFT JOIN selected ON access.is_active
      ORDER BY selected.item_id, selected.placement_id
      """
}
