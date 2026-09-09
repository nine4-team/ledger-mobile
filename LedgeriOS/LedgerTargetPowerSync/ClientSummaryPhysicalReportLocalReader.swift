import LedgerTargetCore
import PowerSync

enum ClientSummaryPhysicalReportLocalReadFailure: Error, Equatable {
    case accountUnavailable, missingClientRelationship, malformedClient, malformedItem, missingSpace
}

struct ClientSummaryPhysicalReportLocalInputs: Encodable, Sendable {
    let project: PropertyManagementReportProject
    let client: ClientSummaryPhysicalReportClient
    let spaces: [PropertyManagementReportSpace]
    let items: [ClientSummaryPhysicalReportItem]
}

/// Read inside the same transaction as the report's physical rows and retained
/// stream checkpoint. This is metadata, not permission or download completeness.
enum ClientSummaryPhysicalReportLocalReader {
    static func read(transaction: any Transaction, accountId: AccountID,
                     principalId: PrincipalID, projectId: ProjectID) throws -> ClientSummaryPhysicalReportLocalInputs {
        let client = try readClient(transaction: transaction, accountId: accountId,
                                    principalId: principalId, projectId: projectId)
        let project = try PropertyManagementReportLocalReader.readProject(transaction: transaction,
            accountId: accountId, principalId: principalId, projectId: projectId)
        let spaces = try PropertyManagementReportLocalReader.readSpaces(transaction: transaction,
            accountId: accountId, projectId: projectId)
        let items = try readItems(transaction: transaction, accountId: accountId,
                                  principalId: principalId, projectId: projectId)
        let spaceIDs = Set(spaces.map(\.spaceId))
        guard items.allSatisfy({ $0.spaceId.map(spaceIDs.contains) ?? true }) else {
            throw ClientSummaryPhysicalReportLocalReadFailure.missingSpace
        }
        return .init(project: project, client: client, spaces: spaces, items: items)
    }

    /// No prices, budget allocations or Invoice rows participate in this read.
    /// Category evidence stays unavailable until its canonical association is
    /// downloaded; a physical placement alone does not establish that evidence.
    static func readItems(transaction: any Transaction, accountId: AccountID,
                          principalId: PrincipalID, projectId: ProjectID) throws
        -> [ClientSummaryPhysicalReportItem] {
        // Validate even an empty result, rather than equating denied with empty.
        _ = try readClient(transaction: transaction, accountId: accountId,
                           principalId: principalId, projectId: projectId)
        let accounting = try ItemClientPaymentConnectionLocalReader.read(transaction: transaction,
            accountId: accountId, principalId: principalId, projectId: projectId)
        return try transaction.getAll(sql: """
            SELECT placement.id AS placement_id, placement.account_id,
              placement.scope_kind, placement.space_id,
              item.id AS item_id, item.name, item.description, item.sku,
              item.revision, typeof(item.revision) AS revision_type,
              (SELECT count(*) FROM spike_item_placements other
                WHERE other.item_id=placement.item_id AND other.ended_at IS NULL) AS active_count
            FROM spike_item_placements placement
            LEFT JOIN spike_items item
              ON item.id=placement.item_id AND item.account_id=placement.account_id
            WHERE placement.project_id=? AND placement.ended_at IS NULL
            ORDER BY placement.item_id, placement.id
            """, parameters: [projectId.rawValue]) { cursor in
                guard try cursor.getString(name: "account_id") == accountId.rawValue,
                      try cursor.getString(name: "scope_kind") == "project",
                      try cursor.getInt(name: "active_count") == 1,
                      let itemId = try cursor.getStringOptional(name: "item_id"),
                      let revision = try cursor.getInt64Optional(name: "revision"), revision > 0,
                      try cursor.getString(name: "revision_type") == "integer" else {
                    throw ClientSummaryPhysicalReportLocalReadFailure.malformedItem
                }
                return try ClientSummaryPhysicalReportItem(accountId: accountId, projectId: projectId,
                    itemId: ItemID(validating: itemId),
                    placementId: EntityID(validating: cursor.getString(name: "placement_id")),
                    spaceId: cursor.getStringOptional(name: "space_id").map { try SpaceID(validating: $0) },
                    name: cursor.getStringOptional(name: "name") ?? cursor.getStringOptional(name: "description") ?? "",
                    sku: cursor.getStringOptional(name: "sku"), category: .unavailable,
                    itemRevision: UInt64(revision),
                    accounting: accounting[EntityID(validating: cursor.getString(name: "placement_id"))])
            }
    }

    static func readClient(transaction: any Transaction, accountId: AccountID,
                           principalId: PrincipalID, projectId: ProjectID) throws
        -> ClientSummaryPhysicalReportClient {
        try transaction.get(sql: """
            WITH access AS (
              SELECT EXISTS(SELECT 1 FROM spike_account_memberships
                WHERE account_id=? AND principal_id=? AND state='active') AS allowed
            )
            SELECT access.allowed, project.client_id AS expected_client_id,
              client.id, client.display_name, client.lifecycle, client.revision,
              typeof(client.revision) AS revision_type
            FROM access
            LEFT JOIN spike_projects project
              ON access.allowed AND project.account_id=? AND project.id=?
            LEFT JOIN spike_clients client
              ON client.account_id=project.account_id AND client.id=project.client_id
            """, parameters: [accountId.rawValue, principalId.rawValue,
                                accountId.rawValue, projectId.rawValue]) { cursor in
                guard try cursor.getInt(name: "allowed") == 1 else {
                    throw ClientSummaryPhysicalReportLocalReadFailure.accountUnavailable
                }
                guard let expected = try cursor.getStringOptional(name: "expected_client_id"),
                      let identifier = try cursor.getStringOptional(name: "id"),
                      expected.utf8.elementsEqual(identifier.utf8) else {
                    throw ClientSummaryPhysicalReportLocalReadFailure.missingClientRelationship
                }
                guard let name = try cursor.getStringOptional(name: "display_name"),
                      let revision = try cursor.getInt64Optional(name: "revision"), revision > 0,
                      try cursor.getString(name: "revision_type") == "integer",
                      ["active", "archived"].contains(try cursor.getString(name: "lifecycle")) else {
                    throw ClientSummaryPhysicalReportLocalReadFailure.malformedClient
                }
                // Apply the same canonical name validation used by Client details.
                let displayName = try ClientDisplayName(validating: name)
                return .known(clientId: try ClientID(validating: identifier),
                              name: displayName.rawValue, revision: UInt64(revision))
            }
    }
}
