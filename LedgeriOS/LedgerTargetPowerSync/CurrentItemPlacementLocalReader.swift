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

    func read(accountId: AccountID, principalId: PrincipalID, scope: ItemPlacementScope) async throws -> [PhysicalItemPlacement] {
        let rows: [PhysicalItemPlacement?] = try await database.getAll(sql: Self.sql,
            parameters: Self.parameters(accountId: accountId, principalId: principalId, scope: scope)) {
                try Self.row(cursor: $0, scope: scope)
            }
        return rows.compactMap { $0 }
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
