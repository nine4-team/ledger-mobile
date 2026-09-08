import LedgerTargetCore
import PowerSync

enum PropertyManagementReportLocalReadFailure: Error, Equatable {
    case accountUnavailable, missingProject, malformedEvidence
}

/// Coherent downloaded inputs, not completeness, authorization to export, or a
/// deliverable report. The owning provider supplies verified stream readiness.
struct PropertyManagementReportLocalInputs: Encodable, Sendable {
    let project: PropertyManagementReportProject
    let spaces: [PropertyManagementReportSpace]
    let items: [PropertyManagementReportItem]
}

struct PropertyManagementReportLocalReader: Sendable {
    let database: any PowerSyncDatabaseProtocol

    func read(accountId: AccountID, principalId: PrincipalID, projectId: ProjectID) async throws -> PropertyManagementReportLocalInputs {
        try await database.readTransaction { transaction in
            try Self.read(transaction: transaction, accountId: accountId, principalId: principalId, projectId: projectId)
        }
    }

    /// All SELECTs and the caller's retained-checkpoint read share this exact
    /// transaction; never independently check membership before opening it.
    static func read(transaction: any Transaction, accountId: AccountID, principalId: PrincipalID,
                     projectId: ProjectID) throws -> PropertyManagementReportLocalInputs {
        let project = try transaction.get(sql: """
          WITH access AS (SELECT EXISTS(SELECT 1 FROM spike_account_memberships
            WHERE account_id=? AND principal_id=? AND state='active') AS allowed)
          SELECT access.allowed,p.id,p.display_name,p.property_address,p.revision,
            typeof(p.revision) AS revision_type,p.lifecycle
          FROM access LEFT JOIN spike_projects p ON access.allowed AND p.account_id=? AND p.id=?
          """, parameters: [accountId.rawValue, principalId.rawValue, accountId.rawValue, projectId.rawValue]) { cursor in
            guard try cursor.getInt(name: "allowed") == 1 else { throw PropertyManagementReportLocalReadFailure.accountUnavailable }
            guard try cursor.getStringOptional(name: "id") != nil else { throw PropertyManagementReportLocalReadFailure.missingProject }
            guard let name = try cursor.getStringOptional(name: "display_name"),
                  let revision = try cursor.getIntOptional(name: "revision"), revision > 0,
                  try cursor.getString(name: "revision_type") == "integer",
                  ["active", "archived"].contains(try cursor.getString(name: "lifecycle")) else {
                throw PropertyManagementReportLocalReadFailure.malformedEvidence
            }
            return PropertyManagementReportProject(accountId: accountId, projectId: projectId, name: name,
                address: try cursor.getStringOptional(name: "property_address"), revision: UInt64(revision))
        }
        let spaces = try transaction.getAll(sql: """
          SELECT s.id,s.account_id,s.project_id,s.scope_kind,s.display_name,s.revision,
            typeof(s.revision) AS revision_type,s.lifecycle
          FROM spike_spaces s WHERE s.project_id=? AND (s.lifecycle='active' OR s.id IN (
            SELECT p.space_id FROM spike_item_placements p WHERE p.project_id=? AND p.ended_at IS NULL
          )) ORDER BY s.id
          """, parameters: [projectId.rawValue, projectId.rawValue]) { cursor in
            guard try cursor.getString(name: "account_id") == accountId.rawValue,
                  try cursor.getString(name: "scope_kind") == "project",
                  ["active", "archived"].contains(try cursor.getString(name: "lifecycle")),
                  let revision = try cursor.getIntOptional(name: "revision"), revision > 0,
                  try cursor.getString(name: "revision_type") == "integer" else {
                throw PropertyManagementReportLocalReadFailure.malformedEvidence
            }
            return try PropertyManagementReportSpace(accountId: accountId, projectId: projectId,
                spaceId: SpaceID(validating: cursor.getString(name: "id")),
                name: cursor.getString(name: "display_name"), revision: UInt64(revision))
        }
        let spaceIDs = Set(spaces.map(\.spaceId))
        let items = try transaction.getAll(sql: """
          SELECT p.id AS placement_id,p.account_id,p.scope_kind,p.space_id,
            i.id AS item_id,i.name,i.description,i.sku,i.market_value_minor_units,i.market_value_currency,i.revision,
            typeof(i.revision) AS revision_type,
            (SELECT count(*) FROM spike_item_placements other WHERE other.item_id=p.item_id AND other.ended_at IS NULL) AS active_count
          FROM spike_item_placements p LEFT JOIN spike_items i ON i.id=p.item_id AND i.account_id=p.account_id
          WHERE p.project_id=? AND p.ended_at IS NULL ORDER BY p.item_id,p.id
          """, parameters: [projectId.rawValue]) { cursor in
            guard try cursor.getString(name: "account_id") == accountId.rawValue,
                  try cursor.getString(name: "scope_kind") == "project",
                  let itemID = try cursor.getStringOptional(name: "item_id"),
                  try cursor.getInt(name: "active_count") == 1,
                  let revision = try cursor.getIntOptional(name: "revision"), revision > 0,
                  try cursor.getString(name: "revision_type") == "integer" else {
                throw PropertyManagementReportLocalReadFailure.malformedEvidence
            }
            let space = try cursor.getStringOptional(name: "space_id").map { try SpaceID(validating: $0) }
            guard space == nil || spaceIDs.contains(space!) else { throw PropertyManagementReportLocalReadFailure.malformedEvidence }
            let amountText = try cursor.getStringOptional(name: "market_value_minor_units")
            let currency = try cursor.getStringOptional(name: "market_value_currency")
            guard (amountText == nil && currency == nil) || (amountText != nil && currency != nil) else {
                throw PropertyManagementReportLocalReadFailure.malformedEvidence
            }
            let money: Money?
            if let amountText, let currency {
                // Text projection avoids SQLite's INTEGER view silently
                // coercing fractional or overflowing local values.
                guard let amount = Int64(amountText), String(amount) == amountText else {
                    throw PropertyManagementReportLocalReadFailure.malformedEvidence
                }
                money = try Money(minorUnits: amount, currency: CurrencyCode(validating: currency))
            }
            else { money = nil }
            // Shipped Item.displayName: presentation fallback, not a mutation
            // or assertion that description was the stored Item name.
            let display = try cursor.getStringOptional(name: "name") ?? cursor.getStringOptional(name: "description") ?? ""
            return try PropertyManagementReportItem(accountId: accountId, projectId: projectId,
                itemId: ItemID(validating: itemID), placementId: EntityID(validating: cursor.getString(name: "placement_id")),
                spaceId: space, name: display, sku: cursor.getStringOptional(name: "sku"), marketValue: money,
                itemRevision: UInt64(revision))
        }
        return .init(project: project, spaces: spaces, items: items)
    }
}
