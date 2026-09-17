import Foundation
import LedgerTargetCore
import PowerSync

enum CurrentItemPlacementReadFailure: Error, Equatable {
    case accountUnavailable
    case incompleteOrConflictingPlacement
}

/// Downloaded physical facts and scoped current accounting evidence.
/// Not a complete inventory/accounting snapshot
/// or an assignment precondition: movement commands must first share a proven
/// revision contract. No subscription or new server access is granted here.
struct CurrentItemPlacementLocalReader: Sendable {
    let database: any PowerSyncDatabaseProtocol

    struct HistoryRow: Sendable {
        let description: String
        let interval: PhysicalItemPlacementHistoryInterval?
        var details: DownloadedItemDescriptiveDetails? = nil
        var currentBudgetCategoryName: String? = nil
    }

    func readHistory(accountId: AccountID, principalId: PrincipalID, itemId: ItemID) async throws -> DownloadedItemPlacementHistory {
        try await database.readTransaction { transaction in
            let rows = try transaction.getAll(sql: Self.historySQL,
                parameters: [accountId.rawValue, principalId.rawValue, accountId.rawValue, itemId.rawValue, principalId.rawValue],
                mapper: Self.historyRow)
            let physical = try Self.history(accountId: accountId, itemId: itemId, rows: rows)
            var accounting: ProjectItemAccountingResolution?
            var purchases: [DownloadedItemClientPurchase] = []
            if let current = physical.intervals.first(where: { $0.endedAt == nil }),
               case .project(let projectId) = current.scope {
                do {
                    let row = try ItemClientPaymentConnectionLocalReader.read(transaction: transaction,
                        accountId: accountId, principalId: principalId, projectId: projectId,
                        placementId: current.placementId)[current.placementId]
                    accounting = row?.resolution ?? .relationshipEvidenceIncomplete
                    if let row {
                        purchases = try Self.purchases(transaction: transaction, row: row,
                            placementId: current.placementId)
                    }
                } catch PropertyManagementReportLocalReadFailure.malformedEvidence {
                    accounting = .relationshipEvidenceIncomplete
                } catch is ProjectItemAccountingSectionFailure {
                    accounting = .relationshipEvidenceIncomplete
                } catch is DomainPrimitiveFailure {
                    accounting = .relationshipEvidenceIncomplete
                }
            }
            return try .init(accountId: accountId, itemId: itemId, description: physical.description,
                intervals: physical.intervals, details: physical.details,
                currentBudgetCategoryName: physical.currentBudgetCategoryName,
                currentAccountingResolution: accounting, currentClientPaidPurchases: purchases,
                pendingSale: Self.pendingSalePlacements(transaction: transaction,accountId: accountId,principalId: principalId)
                    .first(where: { $0.itemId == itemId })?.pendingSale,
                returnLinks: transaction.getAll(sql: """
                    SELECT h.* FROM item_return_history h
                    JOIN spike_budget_categories c ON c.account_id=h.account_id AND c.id=h.category_id
                    JOIN spike_account_memberships m ON m.account_id=h.account_id AND m.principal_id=? AND m.state='active'
                    WHERE h.account_id=? AND h.item_id=? AND (c.visibility_class='ordinary' OR m.financial_access='full')
                    ORDER BY h.id
                    """, parameters: [principalId.rawValue,accountId.rawValue,itemId.rawValue]) { row in
                        try DownloadedItemReturnLink(id: .init(validating: row.getString(name: "id")),
                            chargeId: .init(validating: row.getString(name: "charge_id")),
                            projectId: .init(validating: row.getString(name: "project_id")),
                            projectPlacementId: .init(validating: row.getString(name: "placement_id")),
                            inventoryPlacementId: .init(validating: row.getString(name: "inventory_placement_id")))
                    }, invoiceLines: Self.invoiceHistory(transaction: transaction, accountId: accountId,
                        principalId: principalId, itemId: itemId))
        }
    }

    private static func invoiceHistory(transaction: any Transaction, accountId: AccountID,
        principalId: PrincipalID, itemId: ItemID) throws -> [DownloadedItemInvoiceLine] {
        let parents = try transaction.getAll(sql: """
            SELECT DISTINCT h.id,h.project_id FROM collected_invoices h
            JOIN collected_invoice_lines l ON l.account_id=h.account_id AND l.invoice_id=h.id
            JOIN spike_account_memberships m ON m.account_id=h.account_id
            WHERE h.account_id=? AND l.item_id=? AND l.source_kind='item' AND h.sealed=1
              AND m.principal_id=? AND m.state='active' AND m.financial_access='full'
            ORDER BY h.id
            """, parameters: [accountId.rawValue,itemId.rawValue,principalId.rawValue]) {
                (try InvoiceID(validating: $0.getString(name: "id")),
                 try ProjectID(validating: $0.getString(name: "project_id")))
            }
        return try parents.flatMap { invoiceId, projectId -> [DownloadedItemInvoiceLine] in
            let records: [FrozenInvoiceContents]
            do {
                records = try ProjectExpensePowerSyncQuery.collectedRecords(transaction: transaction, accountId: accountId,
                    projectId: projectId, invoiceId: invoiceId)
            } catch is DecodingError { return [] }
              catch is FrozenInvoiceStorageFailure { return [] }
              catch is FrozenInvoiceContentsFailure { return [] }
              catch is DomainPrimitiveFailure { return [] }
            // An incomplete download is not proof of no billing history. The
            // containing history remains explicitly partial; SQL errors propagate.
            return records.flatMap { invoice in
                    invoice.lines.compactMap { line in
                        guard case .item(let linkedItem, _, _) = line.source, linkedItem == itemId else { return nil }
                        return DownloadedItemInvoiceLine(invoiceId: invoice.invoiceId, purchaseId: invoice.purchaseId,
                            line: line, invoiceNumber: invoice.displayMetadata?.invoiceNumber)
                    }
                }
        }
    }

    private static func purchases(transaction: any Transaction, row: ProjectItemAccountingRow,
                                  placementId: EntityID) throws -> [DownloadedItemClientPurchase] {
        let evidence = row.evidence
        let ids = Set(evidence.clientPaidPurchases.map(\.transactionId))
        guard !ids.isEmpty else { return [] }
        return try transaction.getAll(sql: """
            SELECT DISTINCT payment.* FROM spike_transactions payment
            JOIN item_client_payment_connections link ON link.transaction_id=payment.id
            WHERE link.placement_id=? AND link.ended_at IS NULL
            ORDER BY payment.id
            """, parameters: [placementId.rawValue]) { cursor in
                guard let rawId = try cursor.getStringOptional(name: "id"),
                      let text = try cursor.getStringOptional(name: "amount_minor_units"),
                      let currency = try cursor.getStringOptional(name: "currency") else {
                    throw PropertyManagementReportLocalReadFailure.malformedEvidence
                }
                let id = try TransactionID(validating: rawId)
                guard ids.contains(id),
                      try cursor.getStringOptional(name: "account_id") == evidence.accountId.rawValue,
                      try cursor.getStringOptional(name: "project_id") == evidence.projectId.rawValue,
                      try cursor.getStringOptional(name: "client_id") == evidence.clientId.rawValue,
                      try cursor.getStringOptional(name: "type") == "purchase",
                      try cursor.getStringOptional(name: "role") == "standalone",
                      try cursor.getStringOptional(name: "origin") == "firebase_client_payment",
                      let minorUnits = Int64(text), minorUnits > 0, String(minorUnits) == text else {
                    throw PropertyManagementReportLocalReadFailure.malformedEvidence
                }
                return try DownloadedItemClientPurchase(id: id, accountId: evidence.accountId,
                    projectId: evidence.projectId, clientId: evidence.clientId, itemId: evidence.itemId,
                    placementId: placementId, amount: Money(minorUnits: minorUnits,
                        currency: CurrencyCode(validating: currency)))
            }
    }

    func watchHistory(accountId: AccountID, principalId: PrincipalID, itemId: ItemID) throws -> AsyncThrowingStream<[HistoryRow], Error> {
        try database.watch(sql: Self.historySQL,
            parameters: [accountId.rawValue, principalId.rawValue, accountId.rawValue, itemId.rawValue, principalId.rawValue],
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
            description: description, intervals: intervals.reversed().map(\.interval), details: rows.first?.details,
            currentBudgetCategoryName: rows.first(where: { $0.interval?.endedAt == nil && $0.interval != nil })?.currentBudgetCategoryName)
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
        let bookmark = try cursor.getIntOptional(name: "bookmark")
        guard bookmark == nil || bookmark == 0 || bookmark == 1 else {
            throw CurrentItemPlacementReadFailure.incompleteOrConflictingPlacement
        }
        let amountText = try cursor.getStringOptional(name: "market_value_minor_units")
        let currency = try cursor.getStringOptional(name: "market_value_currency")
        let marketValue: Money?
        if let amountText, let currency {
            guard let amount = Int64(amountText), String(amount) == amountText else {
                throw CurrentItemPlacementReadFailure.incompleteOrConflictingPlacement
            }
            marketValue = try Money(minorUnits: amount, currency: .init(validating: currency))
        } else {
            guard amountText == nil && currency == nil else {
                throw CurrentItemPlacementReadFailure.incompleteOrConflictingPlacement
            }
            marketValue = nil
        }
        let details = try DownloadedItemDescriptiveDetails(name: cursor.getStringOptional(name: "name"),
            description: cursor.getString(name: "raw_description"), sku: cursor.getStringOptional(name: "sku"),
            source: cursor.getStringOptional(name: "source"), currentSource: cursor.getStringOptional(name: "current_source"),
            notes: cursor.getStringOptional(name: "notes"), workflowStatusRaw: cursor.getStringOptional(name: "workflow_status"),
            isBookmarked: bookmark.map { $0 == 1 }, createdAt: cursor.getStringOptional(name: "created_at"),
            itemRevision: cursor.getInt64(name: "revision"), marketValue: marketValue)
        guard let id = try cursor.getStringOptional(name: "placement_id") else {
            return HistoryRow(description: description, interval: nil, details: details)
        }
        let scope: ItemPlacementScope
        switch try cursor.getString(name: "scope_kind") {
        case "business_inventory": scope = .businessInventory
        case "project": scope = .project(try ProjectID(validating: cursor.getString(name: "project_id")))
        default: throw CurrentItemPlacementReadFailure.incompleteOrConflictingPlacement
        }
        var categoryName: String?
        if try cursor.getStringOptional(name: "category_assignment_id") != nil {
            guard try cursor.getStringOptional(name: "category_account") == cursor.getString(name: "item_account"),
                  try cursor.getStringOptional(name: "category_project") == cursor.getStringOptional(name: "project_id"),
                  try cursor.getStringOptional(name: "category_item") == cursor.getString(name: "history_item_id") else {
                throw CurrentItemPlacementReadFailure.incompleteOrConflictingPlacement
            }
            if let categoryId = try cursor.getStringOptional(name: "category_id"),
               let name = try cursor.getStringOptional(name: "category_name"),
               !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                _ = try BudgetCategoryID(validating: categoryId)
                categoryName = name
            }
        }
        guard let startEvidence = PhysicalItemPlacementHistoryInterval.StartEvidence(rawValue: try cursor.getStringOptional(name: "start_evidence") ?? "unknown") else {
            throw CurrentItemPlacementReadFailure.incompleteOrConflictingPlacement
        }
        return try HistoryRow(description: description, interval: PhysicalItemPlacementHistoryInterval(
            placementId: EntityID(validating: id), scope: scope,
            spaceId: cursor.getStringOptional(name: "space_id").map { try SpaceID(validating: $0) },
            projectDisplayName: cursor.getStringOptional(name: "project_name"),
            spaceDisplayName: cursor.getStringOptional(name: "space_name"),
            startedAt: cursor.getString(name: "started_at"), endedAt: cursor.getStringOptional(name: "ended_at"), startEvidence: startEvidence),
            details: details, currentBudgetCategoryName: categoryName)
    }

    private static let historySQL = """
      WITH access AS (
        SELECT EXISTS(SELECT 1 FROM spike_account_memberships
          WHERE account_id=? AND principal_id=? AND state='active') AS is_active
      ), selected_item AS (
        SELECT id,account_id,name,description,revision,sku,source,current_source,notes,workflow_status,bookmark,created_at,
          market_value_minor_units,market_value_currency
        FROM spike_items WHERE account_id=? AND id=?
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
      SELECT access.is_active,COALESCE(i.name,i.description) AS description,i.revision,validity.invalid_count,
        (SELECT count(*) FROM spike_local_operations) AS pending_change_signal,
        i.name,i.description AS raw_description,i.sku,i.source,i.current_source,i.notes,i.workflow_status,i.bookmark,i.created_at,
        i.market_value_minor_units,i.market_value_currency,
        p.id AS placement_id,p.scope_kind,p.project_id,p.space_id,p.started_at,p.ended_at,p.start_evidence,
        project.display_name AS project_name,space.display_name AS space_name,
        i.account_id AS item_account,i.id AS history_item_id,
        assignment.id AS category_assignment_id,assignment.account_id AS category_account,
        assignment.project_id AS category_project,assignment.item_id AS category_item,
        category.id AS category_id,category.display_name AS category_name,
        -- PowerSync observes source-table notifications, not value changes.
        -- These dependencies invalidate even when an update keeps row counts.
        EXISTS(SELECT 1 FROM item_client_payment_connections WHERE account_id=i.account_id) AS payment_changes,
        EXISTS(SELECT 1 FROM item_charge_occurrences WHERE account_id=i.account_id) AS charge_changes,
        EXISTS(SELECT 1 FROM collected_invoice_lines WHERE account_id=i.account_id) AS line_changes,
        EXISTS(SELECT 1 FROM collected_invoices WHERE account_id=i.account_id) AS invoice_changes,
        EXISTS(SELECT 1 FROM spike_transactions WHERE account_id=i.account_id) AS purchase_changes,
        EXISTS(SELECT 1 FROM item_return_history WHERE account_id=i.account_id) AS return_changes
      FROM access CROSS JOIN validity LEFT JOIN selected_item i ON access.is_active
      LEFT JOIN placements p ON access.is_active
      LEFT JOIN spike_projects project ON project.id=p.project_id AND project.account_id=p.account_id
      LEFT JOIN spike_spaces space ON space.id=p.space_id AND space.account_id=p.account_id
        AND space.scope_kind=p.scope_kind AND space.project_id IS p.project_id
      LEFT JOIN spike_item_project_categories assignment ON assignment.id=p.id
        AND p.ended_at IS NULL AND p.scope_kind='project'
      LEFT JOIN spike_budget_categories category ON category.id=assignment.category_id
        AND category.account_id=assignment.account_id
        AND (category.visibility_class='ordinary' OR EXISTS(
          SELECT 1 FROM spike_account_memberships membership
          WHERE membership.account_id=assignment.account_id AND membership.principal_id=?
            AND membership.state='active' AND membership.financial_access='full'))
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

    func readSnapshot(accountId: AccountID, principalId: PrincipalID,
                      scope: ItemPlacementScope) async throws -> DownloadedItemPlacements {
        try await database.readTransaction { transaction in
            try Self.readSnapshot(transaction: transaction, accountId: accountId,
                principalId: principalId, scope: scope)
        }
    }

    static func readSnapshot(transaction: any Transaction, accountId: AccountID,
                             principalId: PrincipalID, scope: ItemPlacementScope) throws -> DownloadedItemPlacements {
        // This read checks active membership even when there are no Items.
        var rows = try read(transaction: transaction, accountId: accountId, principalId: principalId, scope: scope)
        let pending = try pendingSalePlacements(transaction: transaction, accountId: accountId, principalId: principalId)
        let pendingIds = Set(pending.map(\.itemId))
        rows.removeAll { pendingIds.contains($0.itemId) }
        rows.append(contentsOf: pending.filter { $0.scope == scope })
        let kind: String
        let project: String?
        switch scope {
        case .businessInventory: kind = "business_inventory"; project = nil
        case .project(let id): kind = "project"; project = id.rawValue
        }
        let spaces = try transaction.getAll(sql: """
            SELECT space.id,space.display_name,space.lifecycle
            FROM spike_spaces space
            WHERE space.account_id=? AND space.scope_kind=? AND space.project_id IS ?
              AND (space.lifecycle='active' OR (space.lifecycle='archived' AND EXISTS (
                SELECT 1 FROM spike_item_placements placement
                WHERE placement.account_id=space.account_id AND placement.space_id=space.id
                  AND placement.scope_kind=space.scope_kind AND placement.project_id IS space.project_id
                  AND placement.ended_at IS NULL)))
            ORDER BY space.id
            """, parameters: [accountId.rawValue, kind, project]) { cursor in
                try DownloadedItemSpace(id: SpaceID(validating: cursor.getString(name: "id")),
                    accountId: accountId, scope: scope,
                    displayName: cursor.getStringOptional(name: "display_name"),
                    isArchived: cursor.getString(name: "lifecycle") == "archived")
            }
        return try .init(accountId: accountId, scope: scope, rows: rows, spaces: spaces)
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
        return [accountId.rawValue, principalId.rawValue, accountId.rawValue, kind, project, nil, nil]
    }

    private static func row(cursor: any SqlCursor, scope: ItemPlacementScope, requireCurrent: Bool = true) throws -> PhysicalItemPlacement? {
            guard try cursor.getInt(name: "is_active") == 1 else {
                throw CurrentItemPlacementReadFailure.accountUnavailable
            }
            guard let placement = try cursor.getStringOptional(name: "placement_id") else { return nil }
            guard let item = try cursor.getStringOptional(name: "item_id"),
                  let description = try cursor.getStringOptional(name: "description"),
                  let revision = try cursor.getIntOptional(name: "revision"), revision > 0,
                  (try cursor.getInt(name: "active_count") == 1 || !requireCurrent),
                  try cursor.getInt(name: "space_valid") == 1,
                  try cursor.getInt(name: "project_valid") == 1 else {
                throw CurrentItemPlacementReadFailure.incompleteOrConflictingPlacement
            }
            let bookmark = try cursor.getIntOptional(name: "bookmark")
            let bookmarkType = try cursor.getString(name: "bookmark_type")
            guard (bookmark == nil && bookmarkType == "null")
                || (bookmarkType == "integer" && (bookmark == 0 || bookmark == 1)) else {
                throw CurrentItemPlacementReadFailure.incompleteOrConflictingPlacement
            }
            return try PhysicalItemPlacement(itemId: ItemID(validating: item),
                description: description, itemRevision: Int64(revision),
                placementId: EntityID(validating: placement), scope: scope,
                spaceId: cursor.getStringOptional(name: "space_id").map { try SpaceID(validating: $0) },
                name: cursor.getStringOptional(name: "name"), sku: cursor.getStringOptional(name: "sku"),
                createdAt: Self.creationDate(cursor.getStringOptional(name: "created_at")),
                workflowStatusRaw: cursor.getStringOptional(name: "workflow_status"),
                isBookmarked: bookmark.map { $0 == 1 },
                source: cursor.getStringOptional(name: "source"),
                currentSource: cursor.getStringOptional(name: "current_source"),
                imageCount: cursor.getIntOptional(name: "image_count").map(Int64.init))
    }

    static func pendingSalePlacements(transaction: any Transaction, accountId: AccountID,
                                      principalId: PrincipalID) throws -> [PhysicalItemPlacement] {
        let membership = try transaction.get(sql: "SELECT count(*) AS n FROM spike_account_memberships WHERE account_id=? AND principal_id=? AND state='active'",
            parameters: [accountId.rawValue,principalId.rawValue]) { try $0.getInt(name: "n") }
        guard membership == 1 else { throw CurrentItemPlacementReadFailure.accountUnavailable }
        let commands = try transaction.getAll(sql: """
            SELECT id,command_envelope_json,local_state FROM spike_local_operations
            WHERE account_id=? AND actor_principal_id=? AND command_type='sell_inventory_items'
              AND local_state IN ('queued','applying','applied') ORDER BY accepted_at_ms,id
            """, parameters: [accountId.rawValue,principalId.rawValue]) { cursor in
                (try cursor.getString(name: "id"),try cursor.getString(name: "command_envelope_json"),
                 try cursor.getString(name: "local_state"))
            }
        var pending: [ItemID: PhysicalItemPlacement] = [:]
        for record in commands {
            let command = try OperationContractCodec.decode(InventorySaleCommand.self,
                from: Data("{\"envelope\":\(record.1)}".utf8))
            let envelope = command.envelope
            guard envelope.accountId == accountId, envelope.actorPrincipalId == principalId,
                  envelope.operationId.rawValue == record.0, let state = LocalOperationState(rawValue: record.2),
                  try LocalOperationIdentityGuard.inspect(transaction: transaction, operationId: envelope.operationId,
                    expectedFamily: .sellInventoryItems, expectedFingerprint: InventorySaleUploadRequest(command).fingerprint) == .matchingOwner else {
                throw LocalOperationIdentityGuardFailure.malformedEvidence
            }
            guard let project = try ClientProjectDirectoryPowerSyncQuery.readProject(envelope.payload.projectId,
                account: accountId,principal: principalId,in: transaction) else { continue }
            for item in envelope.payload.items {
                let facts = try transaction.getAll(sql: """
                    SELECT id,scope_kind,project_id,ended_at FROM spike_item_placements
                    WHERE account_id=? AND item_id=? AND (ended_at IS NULL OR id=?)
                    """, parameters: [accountId.rawValue,item.itemId.rawValue,item.newPlacementId.rawValue]) { cursor in
                        (try cursor.getString(name: "id"),try cursor.getString(name: "scope_kind"),
                         try cursor.getStringOptional(name: "project_id"),try cursor.getStringOptional(name: "ended_at"))
                    }
                guard facts.filter({ $0.3 == nil }).count <= 1 else {
                    throw CurrentItemPlacementReadFailure.incompleteOrConflictingPlacement
                }
                if let downloaded = facts.first(where: { $0.0 == item.newPlacementId.rawValue }) {
                    guard downloaded.1 == "project", downloaded.2 == envelope.payload.projectId.rawValue else {
                        throw CurrentItemPlacementReadFailure.incompleteOrConflictingPlacement
                    }
                    continue // This sale's placement has downloaded, possibly already ended in a later cycle.
                }
                if facts.contains(where: { $0.3 == nil && $0.0 != item.placementId.rawValue }) { continue }
                var args = parameters(accountId: accountId,principalId: principalId,scope: .businessInventory)
                args[5] = item.placementId.rawValue; args[6] = item.placementId.rawValue
                let sources = try transaction.getAll(sql: sql, parameters: args) {
                    try row(cursor: $0,scope: .businessInventory,requireCurrent: false)
                }.compactMap { $0 }
                guard let source = sources.first, sources.count == 1, source.itemId == item.itemId else { continue }
                let intent = try InventorySalePendingPlacement(command: command,projectName: project.displayName.rawValue,
                    itemId: item.itemId,state: state)
                guard pending[item.itemId] == nil else { throw LocalOperationIdentityGuardFailure.malformedEvidence }
                pending[item.itemId] = try intent.resolve(source: source,current: facts.isEmpty ? nil : source)
            }
        }
        return pending.values.sorted { $0.itemId.rawValue < $1.itemId.rawValue }
    }

    private static func creationDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    private static let sql = """
      -- Membership, parents and cross-scope duplicate checks share one snapshot.
      WITH access AS (
        SELECT EXISTS (SELECT 1 FROM spike_account_memberships
          WHERE account_id = ? AND principal_id = ? AND state = 'active') AS is_active
      ), selected AS (
        SELECT p.id AS placement_id, i.id AS item_id, i.name, i.description, i.sku, i.created_at, i.revision, p.space_id,
          i.workflow_status, i.bookmark, typeof(i.bookmark) AS bookmark_type,
          i.source,i.current_source,
          CASE WHEN CAST(image_set.revision AS INTEGER)>0
            AND image_set.revision=CAST(CAST(image_set.revision AS INTEGER) AS TEXT)
            AND typeof(image_set.expected_count)='integer' AND image_set.expected_count>=0
            THEN image_set.expected_count END AS image_count,
          (SELECT count(*) FROM spike_item_placements other
            WHERE other.account_id = p.account_id AND other.item_id = p.item_id
              AND other.ended_at IS NULL) AS active_count,
          (p.space_id IS NULL OR s.id IS NOT NULL) AS space_valid,
          (p.scope_kind = 'business_inventory' OR project.id IS NOT NULL) AS project_valid
        FROM spike_item_placements p
        LEFT JOIN spike_items i ON i.account_id = p.account_id AND i.id = p.item_id
        LEFT JOIN item_image_sets image_set ON image_set.account_id=i.account_id
          AND image_set.item_id=i.id AND image_set.id=i.id
        LEFT JOIN spike_projects project ON project.id = p.project_id AND project.account_id = p.account_id
        LEFT JOIN spike_spaces s ON s.id = p.space_id AND s.account_id = p.account_id
          AND s.scope_kind = p.scope_kind AND s.project_id IS p.project_id
        WHERE p.account_id = ? AND p.scope_kind = ? AND p.project_id IS ?
          AND ((? IS NULL AND p.ended_at IS NULL) OR p.id=?)
      )
      SELECT access.is_active, selected.*,
        (SELECT count(*) FROM spike_local_operations) AS pending_change_signal FROM access
      LEFT JOIN selected ON access.is_active
      ORDER BY selected.item_id, selected.placement_id
      """
}
