import LedgerTargetCore
import PowerSync

/// Reads existing source facts in one SQLite snapshot. This is the accounting
/// read, not yet the Budget screen's allocation/Additional Requests projection.
struct ProjectBudgetPowerSyncQuery: Sendable {
    let database: any PowerSyncDatabaseProtocol

    typealias Read = ProjectBudgetRead

    private struct StreamIdentity: SyncStreamDescription, Sendable {
        let name: String
        let parameters: JsonParam?
    }

    private func streams(accountId: AccountID, projectId: ProjectID) -> [StreamIdentity] {
        let project: JsonParam = ["account_id": .string(accountId.rawValue), "project_id": .string(projectId.rawValue)]
        return [StreamIdentity(name: "spike_projects", parameters: nil),
            StreamIdentity(name: "physical_account_items", parameters: ["account_id": .string(accountId.rawValue)]),
            StreamIdentity(name: "project_live_invoices", parameters: project),
            StreamIdentity(name: "project_expenses", parameters: project),
            StreamIdentity(name: "project_invoicing_item_charges", parameters: project),
            StreamIdentity(name: "transaction_receipts", parameters: ["account_id": .string(accountId.rawValue),
                "project_id": .string(projectId.rawValue), "scope_kind": .string("project")])]
    }

    func run(accountId: AccountID, principalId: PrincipalID, projectId: ProjectID,
             currency: CurrencyCode, receive: @Sendable @escaping (Read?) async -> Bool) async throws {
        let streams = streams(accountId: accountId, projectId: projectId)
        try await watchWithSubscriptions(streams: streams[...]) {
            let changes = try database.watch(sql: """
                SELECT EXISTS(SELECT 1 FROM spike_account_memberships)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_projects)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_clients)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_budget_categories)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_project_category_allocations)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_local_operations)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_operation_results)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_transactions)
                UNION ALL SELECT EXISTS(SELECT 1 FROM transaction_receipt_items)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_items)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_item_placements)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_item_project_categories)
                UNION ALL SELECT EXISTS(SELECT 1 FROM item_client_payment_connections)
                UNION ALL SELECT EXISTS(SELECT 1 FROM item_image_sets)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_spaces)
                UNION ALL SELECT EXISTS(SELECT 1 FROM item_charge_occurrences)
                UNION ALL SELECT EXISTS(SELECT 1 FROM paid_item_return_credits)
                UNION ALL SELECT EXISTS(SELECT 1 FROM expenses)
                UNION ALL SELECT EXISTS(SELECT 1 FROM fee_installments)
                UNION ALL SELECT EXISTS(SELECT 1 FROM live_invoices)
                UNION ALL SELECT EXISTS(SELECT 1 FROM live_invoice_memberships)
                UNION ALL SELECT EXISTS(SELECT 1 FROM collected_invoices)
                UNION ALL SELECT EXISTS(SELECT 1 FROM collected_invoice_lines)
                UNION ALL SELECT EXISTS(SELECT 1 FROM ps_stream_subscriptions)
                """, parameters: nil) { try $0.getInt(index: 0) }
            for try await _ in changes {
                try Task.checkCancellation()
                let read: Read?
                do { read = try await readImplementedSources(accountId: accountId, principalId: principalId,
                    projectId: projectId, currency: currency) }
                catch PropertyManagementReportFailure.incompleteReadiness { read = nil }
                guard await receive(read) else { return }
            }
        }
    }

    private func watchWithSubscriptions(streams: ArraySlice<StreamIdentity>,
        observe: @Sendable @escaping () async throws -> Void) async throws {
        guard let stream = streams.first else { try await observe(); return }
        try await withOwnedSyncStreamWatch(subscribe: {
            try await database.syncStream(name: stream.name, params: stream.parameters).subscribe()
        }, observe: {
            try await watchWithSubscriptions(streams: streams.dropFirst(), observe: observe)
        })
    }

    // Existing streams cover vendor/client payments, not every Transfer source.
    // Do not expose this as a complete Budget snapshot until that coverage and
    // pending-operation readiness are integrated by the workflow owner.
    func readImplementedSources(accountId: AccountID, principalId: PrincipalID, projectId: ProjectID,
              currency: CurrencyCode) async throws -> Read {
        try await database.readTransaction { local in
            try ProjectInvoicingItemLocalReader.requireAccess(transaction: local, accountId: accountId,
                principalId: principalId, projectId: projectId)
            let checkpoints = try streams(accountId: accountId, projectId: projectId).map {
                try PropertyManagementReportPowerSyncQuery.completedStreamCheckpointMicroseconds(transaction: local, identity: $0)
            }
            // Directory/permissions are priority one. An earlier completed
            // financial download cannot establish coverage of that newer scope.
            // Match the existing Transaction export readiness rule, retaining
            // microsecond precision and applying it to every consumed stream.
            guard let directory = checkpoints.first, checkpoints.dropFirst().allSatisfy({ $0 >= directory }) else {
                throw PropertyManagementReportFailure.incompleteReadiness
            }
            guard let project = try ClientProjectDirectoryPowerSyncQuery.readProject(projectId,
                account: accountId, principal: principalId, in: local) else {
                throw PropertyManagementReportFailure.incompleteReadiness
            }
            let scope = try TransactionScope.project(accountId: accountId,
                projectId: projectId, clientId: project.clientId)
            let categories = try CategoryManagementLocalProjection.read(local,
                account: accountId, principal: principalId, fullFinancialAccess: true)
            let categoryIds = Set(categories.map(\.id))
            let allocations = try local.getAll(sql: """
                SELECT category_id,CAST(allocation_minor_units AS TEXT) AS amount,allocation_currency
                FROM spike_project_category_allocations WHERE account_id=? AND project_id=? ORDER BY category_id
                """, parameters: [accountId.rawValue, projectId.rawValue]) { row in
                    let category = try BudgetCategoryID(validating: row.getString(name: "category_id"))
                    guard categoryIds.contains(category) else { throw ProjectBudgetCalculation.Failure.missingEvidence }
                    let amount = try row.getStringOptional(name: "amount")
                    let code = try row.getStringOptional(name: "allocation_currency")
                    let allocation: Money?
                    switch (amount, code) {
                    case (nil, nil): allocation = nil
                    case (let amount?, let code?):
                        guard let units = Int64(amount) else { throw ProjectBudgetCalculation.Failure.missingEvidence }
                        let allocationCurrency = try CurrencyCode(validating: code)
                        guard allocationCurrency == currency else { throw ProjectBudgetSegmentFailure.currencyMismatch }
                        allocation = Money(minorUnits: units, currency: allocationCurrency)
                    default: throw ProjectBudgetCalculation.Failure.missingEvidence
                    }
                    return try NullableCategoryAllocation(categoryId: category, allocation: allocation)
                }
            guard Set(allocations.map(\.categoryId)).count == allocations.count else {
                throw ProjectBudgetCalculation.Failure.duplicateSource
            }
            let review = try InvoiceCreationReview(scope: scope,
                candidates: LiveInvoicePowerSyncQuery.creationCandidatesAuthorized(
                    transaction: local, accountId: accountId, projectId: projectId))
            let live = try LiveInvoicePowerSyncQuery.readAuthorized(transaction: local,
                accountId: accountId, projectId: projectId)
            let paid = try ProjectExpensePowerSyncQuery.collectedRecords(transaction: local,
                accountId: accountId, projectId: projectId)
            let items = try ProjectInvoicingItems(accountId: accountId, projectId: projectId,
                rows: ProjectInvoicingItemLocalReader.readAuthorizedCharges(transaction: local,
                    accountId: accountId, principalId: principalId, projectId: projectId))
            // This reader rejects unknown origins/types instead of filtering them
            // out. Transfers therefore remain unavailable until supported.
            let payments = try TransactionDetailPowerSyncQuery(database: database,
                principalId: principalId, scope: scope).readRows(transaction: local,
                    transactionId: nil, requireCompleteCategories: true)
            let segments = try ProjectBudgetCalculation.calculate(categories: categories, currency: currency,
                review: review, live: live, paid: paid, itemRows: items, transactions: payments)
            let operations = try local.getAll(sql: """
                SELECT o.id,o.local_state FROM spike_local_operations o
                WHERE o.account_id=? AND o.actor_principal_id=?
                  AND o.local_state IN ('queued','applying','applied','rejected')
                  AND (o.command_type='manage_categories' OR (
                    o.command_type IN ('create_expense','edit_expense','create_fee_installment',
                      'create_invoice','revise_created_invoice','sell_inventory_items',
                      'return_uninvoiced_items','return_paid_items','edit_uncollected_item_price',
                      'edit_transaction_details','edit_transaction_receipt_lines')
                    AND COALESCE(json_extract(o.command_envelope_json,'$.payload.projectId'),
                      json_extract(o.command_envelope_json,'$.payload.entry.projectId'),
                      json_extract(o.command_envelope_json,'$.payload.scope.projectId'),
                      json_extract(o.command_envelope_json,'$.payload.selection.scope.projectId'),
                      json_extract(o.command_envelope_json,'$.payload.invoice.selection.scope.projectId'))=?))
                  AND NOT (o.local_state='applied' AND EXISTS(
                    SELECT 1 FROM spike_operation_results r WHERE r.id=o.id AND r.account_id=o.account_id
                      AND r.actor_principal_id=o.actor_principal_id AND r.command_type=o.command_type
                      AND r.contract_version=o.contract_version AND r.command_fingerprint=o.fingerprint
                      AND r.envelope_sha256=o.fingerprint AND r.phase='applied'))
                ORDER BY o.accepted_at_ms,o.id
                """, parameters: [accountId.rawValue,principalId.rawValue,projectId.rawValue]) { row in
                    guard let state = LocalOperationState(rawValue: try row.getString(name: "local_state")) else {
                        throw LocalOperationIdentityGuardFailure.malformedEvidence
                    }
                    return try OperationReceipt(operationId: .init(validating: row.getString(name: "id")), localState: state)
                }
            return try Read(scope: scope, currency: currency, segments: segments,
                allocations: allocations, localOperations: operations)
        }
    }
}
