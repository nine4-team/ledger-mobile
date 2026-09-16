import Foundation
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
                            UNION ALL SELECT EXISTS(SELECT 1 FROM spike_local_operations)
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
            try Self.requireReady(local, accountId: accountId, principalId: principalId, projectId: projectId)
            return try Self.readAuthorized(transaction: local, accountId: accountId, projectId: projectId)
        }
    }

    private static func requireReady(_ local: any Transaction, accountId: AccountID, principalId: PrincipalID, projectId: ProjectID) throws {
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
    }

    func readCreationReview(accountId: AccountID, principalId: PrincipalID, projectId: ProjectID) async throws -> InvoiceCreationReview {
        try await database.readTransaction { local in
            try Self.requireReady(local, accountId: accountId, principalId: principalId, projectId: projectId)
            guard let project = try ClientProjectDirectoryPowerSyncQuery.readProject(projectId,
                account: accountId, principal: principalId, in: local), project.lifecycle == .active,
                project.client.lifecycle == .active else { throw Failure.incomplete }
            return try InvoiceCreationReview(scope: .project(accountId: accountId, projectId: projectId, clientId: project.clientId),
                candidates: Self.creationCandidatesAuthorized(transaction: local, accountId: accountId, projectId: projectId))
        }
    }

    // Caller establishes financial authorization, active scope and complete downloads.
    static func creationCandidatesAuthorized(transaction: any Transaction, accountId: AccountID, projectId: ProjectID) throws -> [LiveInvoiceContents.Line] {
        try transaction.getAll(sql: """
            WITH candidates AS (
              SELECT 'item' AS kind,i.id,i.account_id,i.project_id,i.category_id,i.amount_minor_units AS amount,
                i.currency,CAST(i.revision AS TEXT) AS revision,item.description AS description
                FROM item_charge_occurrences i LEFT JOIN spike_items item ON item.account_id=i.account_id AND item.id=i.item_id
                WHERE i.withdrawn_at IS NULL
              UNION ALL SELECT 'expense',id,account_id,project_id,category_id,final_amount_minor_units,currency,CAST(revision AS TEXT),vendor FROM expenses
              UNION ALL SELECT 'fee_installment',id,account_id,project_id,category_id,amount_minor_units,currency,CAST(revision AS TEXT),label FROM fee_installments
            )
            SELECT * FROM candidates c WHERE c.account_id=? AND c.project_id=?
              AND NOT EXISTS(SELECT 1 FROM live_invoice_memberships m WHERE m.account_id=c.account_id AND m.source_kind=c.kind AND m.source_id=c.id)
              AND NOT EXISTS(SELECT 1 FROM collected_invoice_lines p WHERE p.account_id=c.account_id AND p.source_kind=c.kind AND p.source_id=c.id)
            ORDER BY kind,id
            """, parameters: [accountId.rawValue, projectId.rawValue]) { row in
                let source: LiveInvoiceSource
                let id = try row.getString(name: "id")
                switch try row.getString(name: "kind") {
                case "item": source = .itemOccurrence(try .init(validating: id))
                case "expense": source = .expense(try .init(validating: id))
                case "fee_installment": source = .feeInstallment(try .init(validating: id))
                default: throw Failure.incomplete
                }
                return try .init(selection: .init(source: source, expectedRevision: integer(row.getString(name: "revision")),
                    reviewedAmount: .init(minorUnits: integer(row.getString(name: "amount")), currency: .init(validating: row.getString(name: "currency")))),
                    categoryId: .init(validating: row.getString(name: "category_id")), description: row.getString(name: "description"))
            }
    }

    func readPendingCreations(accountId: AccountID, principalId: PrincipalID, projectId: ProjectID) async throws -> [PendingInvoiceCreation] {
        try await database.readTransaction { local in
            try ProjectInvoicingItemLocalReader.requireAccess(transaction: local,
                accountId: accountId, principalId: principalId, projectId: projectId)
            return try local.getAll(sql: """
                SELECT id,subject_id,local_state,fingerprint,command_envelope_json FROM spike_local_operations o
                WHERE account_id=? AND actor_principal_id=? AND command_type='create_invoice'
                  AND local_state IN ('queued','applying','applied','rejected')
                  AND NOT (local_state='applied' AND (
                    EXISTS(SELECT 1 FROM live_invoices h WHERE h.account_id=o.account_id AND h.id=o.subject_id)
                    OR EXISTS(SELECT 1 FROM collected_invoices h WHERE h.account_id=o.account_id AND h.id=o.subject_id AND h.sealed=1)))
                ORDER BY accepted_at_ms,id
                """, parameters: [accountId.rawValue, principalId.rawValue]) { row -> PendingInvoiceCreation in
                    let json = try row.getString(name: "command_envelope_json")
                    let command = try OperationContractCodec.decode(CreateInvoiceCommand.self, from: Data("{\"envelope\":\(json)}".utf8))
                    let e = command.envelope
                    guard e.accountId == accountId, e.actorPrincipalId == principalId,
                          e.operationId.rawValue == (try row.getString(name: "id")),
                          e.payload.invoiceId.rawValue == (try row.getString(name: "subject_id")),
                          AccountBoundOperationIdentity.isValid(e.operationId, family: .invoiceCreation, accountId: accountId),
                          try CreateInvoiceUploadRequest(command).fingerprint == row.getString(name: "fingerprint"),
                          let state = LocalOperationState(rawValue: try row.getString(name: "local_state")) else {
                        throw LocalOperationIdentityGuardFailure.malformedEvidence
                    }
                    return PendingInvoiceCreation(id: e.operationId, payload: e.payload, state: state)
                }.filter { $0.payload.selection.scope.projectId == projectId }
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
