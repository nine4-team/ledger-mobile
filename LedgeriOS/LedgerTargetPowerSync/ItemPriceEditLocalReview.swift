import LedgerTargetCore
import PowerSync

/// Reuses the existing charge/paid-membership and physical-Item streams.
/// Read inside the accepting write transaction too, so admission cannot use a
/// review contradicted by downloaded changes between display and Save.
enum ItemPriceEditLocalReview {
    enum Failure: Error { case unavailable }
    private struct PhysicalIdentity: SyncStreamDescription {
        let name = "physical_account_items"
        let parameters: JsonParam?
        init(_ account: AccountID) { parameters = ["account_id": .string(account.rawValue)] }
    }

    static func read(_ local: any Transaction, account: AccountID, principal: PrincipalID,
                     project: ProjectID, item: ItemID, requested: Money) throws -> EditUncollectedItemPriceCommand.Payload {
        try snapshot(local, account: account, principal: principal, project: project, item: item).payload(requested: requested)
    }

    static func snapshot(_ local: any Transaction, account: AccountID, principal: PrincipalID,
                         project: ProjectID, item: ItemID) throws -> ItemPriceEditReview {
        guard try CategoryManagementLocalProjection.requireMembership(local, account: account, principal: principal) else {
            throw Failure.unavailable
        }
        _ = try PropertyManagementReportPowerSyncQuery.completedStreamCheckpoint(transaction: local,
            identity: PhysicalIdentity(account))
        _ = try PropertyManagementReportPowerSyncQuery.completedStreamCheckpoint(transaction: local,
            identity: ItemReturnReviewStreamIdentity(accountId: account, projectId: project))
        guard let destination = try ClientProjectDirectoryPowerSyncQuery.readProject(project,
            account: account, principal: principal, in: local), destination.lifecycle == .active,
            destination.client.lifecycle == .active else { throw Failure.unavailable }
        let archived = try local.get(sql: """
            SELECT count(*) FROM spike_local_operations WHERE account_id=? AND local_state IN ('queued','applying')
              AND ((command_type='archive_project' AND subject_id=?) OR (command_type='archive_client' AND subject_id=?))
            """, parameters: [account.rawValue,project.rawValue,destination.clientId.rawValue]) { try $0.getInt(index: 0) }
        guard archived == 0 else { throw Failure.unavailable }
        let charges = try local.getAll(sql: """
            SELECT c.id,c.placement_id,c.revision FROM return_charge_sources c
            JOIN spike_item_placements p ON p.account_id=c.account_id AND p.id=c.placement_id AND p.item_id=c.item_id
            WHERE c.account_id=? AND c.project_id=? AND c.item_id=? AND p.project_id=c.project_id
              AND p.scope_kind='project' AND p.ended_at IS NULL
              AND NOT EXISTS(SELECT 1 FROM return_paid_memberships paid WHERE paid.account_id=c.account_id AND paid.source_id=c.id)
            """, parameters: [account.rawValue,project.rawValue,item.rawValue]) {
                (try $0.getString(index: 0),try $0.getString(index: 1),try $0.getString(index: 2))
            }
        guard charges.count == 1 else { throw Failure.unavailable }
        let charge = charges[0]
        let price = try local.getOptional(sql: "SELECT revision,currency,amount_minor_units FROM item_project_prices WHERE account_id=? AND item_id=?",
            parameters: [account.rawValue,item.rawValue]) {
                (try $0.getString(index: 0),try $0.getString(index: 1),try $0.getString(index: 2))
            }
        let current: Money?
        if let price {
            guard let amount = Int64(price.2), String(amount) == price.2 else { throw Failure.unavailable }
            current = Money(minorUnits: amount, currency: try .init(validating: price.1))
        } else { current = nil }
        let acquisition = try local.getOptional(sql: "SELECT state,amount_minor_units,currency FROM item_acquisition_reviews WHERE account_id=? AND id=?",
            parameters: [account.rawValue,item.rawValue]) {
                (try $0.getString(index: 0),try $0.getStringOptional(index: 1),try $0.getStringOptional(index: 2))
            }
        guard let acquisition else { throw Failure.unavailable }
        let cost: InventorySalePrice.Evidence
        switch acquisition.0 {
        case "absent":
            guard acquisition.1 == nil, acquisition.2 == nil else { throw Failure.unavailable }
            cost = .confirmedAbsent
        case "known":
            guard let text = acquisition.1, let value = Int64(text), String(value) == text,
                  value >= 0, let currency = acquisition.2 else { throw Failure.unavailable }
            cost = .known(Money(minorUnits: value, currency: try .init(validating: currency)))
        default: throw Failure.unavailable
        }
        guard let priceRevision = Int64(price?.0 ?? "0"), String(priceRevision) == (price?.0 ?? "0"),
              let chargeRevision = Int64(charge.2), String(chargeRevision) == charge.2 else { throw Failure.unavailable }
        return try .init(projectId: project, itemId: item, placementId: .init(validating: charge.1),
            occurrenceId: .init(validating: charge.0), priceRevision: priceRevision,
            chargeRevision: chargeRevision, currentPrice: current, purchaseCost: cost)
    }
}
