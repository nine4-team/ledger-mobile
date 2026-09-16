import LedgerTargetCore
import PowerSync

struct ProjectInvoicingChargeStreamIdentity: SyncStreamDescription, Sendable {
    let name = "project_invoicing_item_charges"
    let parameters: JsonParam?
    init(accountId: AccountID, projectId: ProjectID) {
        parameters = ["account_id": .string(accountId.rawValue), "project_id": .string(projectId.rawValue)]
    }
}

struct ProjectInvoicingChargePowerSyncQuery: Sendable {
    let database: any PowerSyncDatabaseProtocol

    private struct PhysicalIdentity: SyncStreamDescription {
        let name = "physical_account_items"
        let parameters: JsonParam?
        init(accountId: AccountID) { parameters = ["account_id": .string(accountId.rawValue)] }
    }

    /// This snapshot covers Item charges, not the other Invoicing source kinds.
    /// Both download markers and the authorized rows are read atomically.
    func read(accountId: AccountID, principalId: PrincipalID, projectId: ProjectID) async throws -> ProjectInvoicingItems {
        try await database.readTransaction { transaction in
            try ProjectInvoicingItemLocalReader.requireAccess(transaction: transaction,
                accountId: accountId, principalId: principalId, projectId: projectId)
            _ = try PropertyManagementReportPowerSyncQuery.completedStreamCheckpoint(transaction: transaction,
                identity: ProjectInvoicingChargeStreamIdentity(accountId: accountId, projectId: projectId))
            _ = try PropertyManagementReportPowerSyncQuery.completedStreamCheckpoint(transaction: transaction,
                identity: PhysicalIdentity(accountId: accountId))
            _ = try PropertyManagementReportPowerSyncQuery.completedStreamCheckpoint(transaction: transaction,
                identity: LiveInvoiceStreamIdentity(accountId: accountId, projectId: projectId))
            let rows = try ProjectInvoicingItemLocalReader.readAuthorizedCharges(transaction: transaction,
                accountId: accountId, principalId: principalId, projectId: projectId)
            return try ProjectInvoicingItems(accountId: accountId, projectId: projectId, rows: rows)
        }
    }

    func run(accountId: AccountID, principalId: PrincipalID, projectId: ProjectID,
             receive: @Sendable @escaping (ProjectInvoicingItems?) async -> Bool) async throws {
        let live = LiveInvoiceStreamIdentity(accountId: accountId, projectId: projectId)
        try await withOwnedSyncStreamWatch(subscribe: {
            try await database.syncStream(name: live.name, params: live.parameters).subscribe()
        }, observe: {
            try await runCharges(accountId: accountId, principalId: principalId, projectId: projectId, receive: receive)
        })
    }

    private func runCharges(accountId: AccountID, principalId: PrincipalID, projectId: ProjectID,
             receive: @Sendable @escaping (ProjectInvoicingItems?) async -> Bool) async throws {
        let financial = ProjectInvoicingChargeStreamIdentity(accountId: accountId, projectId: projectId)
        let physical = PhysicalIdentity(accountId: accountId)
        try await withOwnedSyncStreamWatch(subscribe: {
            try await database.syncStream(name: financial.name, params: financial.parameters).subscribe()
        }, observe: {
            try await withOwnedSyncStreamWatch(subscribe: {
                try await database.syncStream(name: physical.name, params: physical.parameters).subscribe()
            }, observe: {
                let changes = try database.watch(sql: """
                    SELECT EXISTS(SELECT 1 FROM spike_account_memberships WHERE account_id=?)
                    UNION ALL SELECT EXISTS(SELECT 1 FROM spike_projects WHERE account_id=?)
                    UNION ALL SELECT EXISTS(SELECT 1 FROM spike_item_placements WHERE account_id=?)
                    UNION ALL SELECT EXISTS(SELECT 1 FROM spike_items WHERE account_id=?)
                    UNION ALL SELECT EXISTS(SELECT 1 FROM item_charge_occurrences WHERE account_id=?)
                    UNION ALL SELECT EXISTS(SELECT 1 FROM collected_invoice_lines WHERE account_id=?)
                    UNION ALL SELECT EXISTS(SELECT 1 FROM collected_invoices WHERE account_id=?)
                    UNION ALL SELECT EXISTS(SELECT 1 FROM spike_budget_categories WHERE account_id=?)
                    UNION ALL SELECT EXISTS(SELECT 1 FROM item_client_payment_connections WHERE account_id=?)
                    UNION ALL SELECT EXISTS(SELECT 1 FROM ps_stream_subscriptions)
                    UNION ALL SELECT EXISTS(SELECT 1 FROM live_invoice_memberships)
                    UNION ALL SELECT EXISTS(SELECT 1 FROM live_invoices)
                    """, parameters: Array(repeating: accountId.rawValue, count: 9)) { try $0.getInt(index: 0) }
                for try await _ in changes {
                    try Task.checkCancellation()
                    let snapshot: ProjectInvoicingItems?
                    do { snapshot = try await read(accountId: accountId, principalId: principalId, projectId: projectId) }
                    catch PropertyManagementReportFailure.incompleteReadiness { snapshot = nil }
                    guard await receive(snapshot) else { return }
                }
            })
        })
    }
}
