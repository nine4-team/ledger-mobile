import LedgerTargetCore
import PowerSync

struct LiveInvoiceStreamIdentity: SyncStreamDescription, Sendable {
    let name = "project_live_invoices"
    let parameters: JsonParam?
    init(accountId: AccountID, projectId: ProjectID) {
        parameters = ["account_id": .string(accountId.rawValue), "project_id": .string(projectId.rawValue)]
    }
}

struct LiveInvoicePowerSyncQuery: Sendable {
    let database: any PowerSyncDatabaseProtocol
    private struct PhysicalIdentity: SyncStreamDescription {
        let name = "physical_account_items"
        let parameters: JsonParam?
        init(accountId: AccountID) { parameters = ["account_id": .string(accountId.rawValue)] }
    }

    func run(accountId: AccountID, principalId: PrincipalID, projectId: ProjectID,
             receive: @Sendable @escaping ([LiveInvoiceContents]?) async -> Bool) async throws {
        let live = LiveInvoiceStreamIdentity(accountId: accountId, projectId: projectId)
        let expenses = ProjectExpenseStreamIdentity(accountId: accountId, projectId: projectId)
        let charges = ProjectInvoicingChargeStreamIdentity(accountId: accountId, projectId: projectId)
        let physical = PhysicalIdentity(accountId: accountId)
        try await withOwnedSyncStreamWatch(subscribe: {
            try await database.syncStream(name: live.name, params: live.parameters).subscribe()
        }, observe: {
            try await withOwnedSyncStreamWatch(subscribe: {
                try await database.syncStream(name: expenses.name, params: expenses.parameters).subscribe()
            }, observe: {
                try await withOwnedSyncStreamWatch(subscribe: {
                    try await database.syncStream(name: charges.name, params: charges.parameters).subscribe()
                }, observe: {
                    try await withOwnedSyncStreamWatch(subscribe: {
                        try await database.syncStream(name: physical.name, params: physical.parameters).subscribe()
                    }, observe: {
                        let updates = try database.watch(sql: """
                            SELECT EXISTS(SELECT 1 FROM spike_account_memberships)
                            UNION ALL SELECT EXISTS(SELECT 1 FROM spike_projects)
                            UNION ALL SELECT EXISTS(SELECT 1 FROM live_invoices)
                            UNION ALL SELECT EXISTS(SELECT 1 FROM live_invoice_memberships)
                            UNION ALL SELECT EXISTS(SELECT 1 FROM expenses)
                            UNION ALL SELECT EXISTS(SELECT 1 FROM fee_installments)
                            UNION ALL SELECT EXISTS(SELECT 1 FROM item_charge_occurrences)
                            UNION ALL SELECT EXISTS(SELECT 1 FROM spike_items)
                            UNION ALL SELECT EXISTS(SELECT 1 FROM collected_invoice_lines)
                            UNION ALL SELECT EXISTS(SELECT 1 FROM ps_stream_subscriptions)
                            """, parameters: nil) { try $0.getInt(index: 0) }
                        for try await _ in updates {
                            try Task.checkCancellation()
                            let value: [LiveInvoiceContents]?
                            do { value = try await read(accountId: accountId, principalId: principalId, projectId: projectId) }
                            catch PropertyManagementReportFailure.incompleteReadiness { value = nil }
                            guard await receive(value) else { return }
                        }
                    })
                })
            })
        })
    }

    func read(accountId: AccountID, principalId: PrincipalID, projectId: ProjectID) async throws -> [LiveInvoiceContents] {
        try await database.readTransaction { local in
            try ProjectInvoicingItemLocalReader.requireAccess(transaction: local,
                accountId: accountId, principalId: principalId, projectId: projectId)
            for identity: any SyncStreamDescription in [
                LiveInvoiceStreamIdentity(accountId: accountId, projectId: projectId),
                ProjectExpenseStreamIdentity(accountId: accountId, projectId: projectId),
                ProjectInvoicingChargeStreamIdentity(accountId: accountId, projectId: projectId),
                PhysicalIdentity(accountId: accountId)
            ] {
                _ = try PropertyManagementReportPowerSyncQuery.completedStreamCheckpoint(transaction: local, identity: identity)
            }
            return try Self.readAuthorized(transaction: local, accountId: accountId, projectId: projectId)
        }
    }

    // Caller establishes authorization and complete downloads in the same read transaction.
    static func readAuthorized(transaction: any Transaction, accountId: AccountID,
                               projectId: ProjectID) throws -> [LiveInvoiceContents] {
        let headers = try transaction.getAll(sql: """
            SELECT h.id,h.revision,h.status,h.name,h.notes,p.client_id FROM live_invoices h
            JOIN spike_projects p ON p.account_id=h.account_id AND p.id=h.project_id
            WHERE h.account_id=? AND h.project_id=? AND h.status IN ('created','sent') ORDER BY h.id
            """, parameters: [accountId.rawValue, projectId.rawValue]) { row in
                (try row.getString(name: "id"), try row.getString(name: "revision"),
                 try row.getString(name: "status"), try row.getString(name: "name"),
                 try row.getString(name: "notes"), try row.getString(name: "client_id"))
            }
        return try headers.map { header in
            let scope = try TransactionScope.project(accountId: accountId, projectId: projectId,
                clientId: .init(validating: header.5))
            guard let status = LiveInvoiceContents.Status(rawValue: header.2) else { throw Failure.incomplete }
            let positionedLines: [(Int, LiveInvoiceContents.Line)] = try transaction.getAll(sql: """
                SELECT m.source_kind,m.source_id,m.position,
                  CAST(COALESCE(i.revision,e.revision,f.revision) AS TEXT) AS revision,
                  COALESCE(i.amount_minor_units,e.final_amount_minor_units,f.amount_minor_units) AS amount,
                  COALESCE(i.currency,e.currency,f.currency) AS currency,
                  COALESCE(i.category_id,e.category_id,f.category_id) AS category,
                  CASE m.source_kind WHEN 'item' THEN item.description WHEN 'expense' THEN e.vendor ELSE f.label END AS description,
                  EXISTS(SELECT 1 FROM collected_invoice_lines paid WHERE paid.account_id=m.account_id
                    AND paid.source_kind=m.source_kind AND paid.source_id=m.source_id) AS collected
                FROM live_invoice_memberships m
                LEFT JOIN item_charge_occurrences i ON m.source_kind='item' AND i.account_id=m.account_id
                  AND i.id=m.source_id AND i.project_id=? AND i.withdrawn_at IS NULL
                LEFT JOIN spike_items item ON item.account_id=i.account_id AND item.id=i.item_id
                LEFT JOIN expenses e ON m.source_kind='expense' AND e.account_id=m.account_id AND e.id=m.source_id AND e.project_id=?
                LEFT JOIN fee_installments f ON m.source_kind='fee_installment' AND f.account_id=m.account_id AND f.id=m.source_id AND f.project_id=?
                WHERE m.account_id=? AND m.invoice_id=? ORDER BY m.position
                """, parameters: [projectId.rawValue, projectId.rawValue, projectId.rawValue, accountId.rawValue, header.0]) { row in
                    guard try row.getInt(name: "collected") == 0 else {
                        throw Failure.incomplete
                    }
                    let source: LiveInvoiceSource
                    let id = try row.getString(name: "source_id")
                    switch try row.getString(name: "source_kind") {
                    case "item": source = .itemOccurrence(try .init(validating: id))
                    case "expense": source = .expense(try .init(validating: id))
                    case "fee_installment": source = .feeInstallment(try .init(validating: id))
                    default: throw Failure.incomplete
                    }
                    return try (row.getInt(name: "position"), .init(selection: .init(source: source, expectedRevision: integer(row.getString(name: "revision")),
                        reviewedAmount: .init(minorUnits: integer(row.getString(name: "amount")),
                            currency: .init(validating: row.getString(name: "currency")))),
                        categoryId: .init(validating: row.getString(name: "category")), description: row.getString(name: "description")))
                }
            guard positionedLines.enumerated().allSatisfy({ $0.offset == $0.element.0 }) else { throw Failure.incomplete }
            let lines = positionedLines.map(\.1)
            let selection = try LiveInvoiceSelection(scope: scope, lines: lines.map(\.selection))
            return try .init(invoiceId: .init(validating: header.0), revision: integer(header.1), status: status,
                name: header.3, notes: header.4, scope: scope, lines: lines, reportedTotal: selection.reviewedTotal)
        }
    }
    private static func integer(_ text: String) throws -> Int64 {
        guard let value = Int64(text), String(value) == text else { throw Failure.incomplete }
        return value
    }
    enum Failure: Error { case incomplete }
}
