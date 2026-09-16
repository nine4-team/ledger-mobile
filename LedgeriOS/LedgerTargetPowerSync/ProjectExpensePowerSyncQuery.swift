import Foundation
import LedgerTargetCore
import PowerSync

struct ProjectExpenseStreamIdentity: SyncStreamDescription, Sendable {
    let name = "project_expenses"
    let parameters: JsonParam?
    init(accountId: AccountID, projectId: ProjectID) {
        parameters = ["account_id": .string(accountId.rawValue), "project_id": .string(projectId.rawValue)]
    }
}

struct ProjectExpensePowerSyncQuery: Sendable {
    let database: any PowerSyncDatabaseProtocol

    func readCollectedInvoiceReport(accountId: AccountID, principalId: PrincipalID,
        projectId: ProjectID, invoiceId: InvoiceID, asOf: ProtectedArtifactEpochMilliseconds) async throws
        -> CollectedInvoiceReportSnapshot {
        try await database.readTransaction { local in
            try ProjectInvoicingItemLocalReader.requireAccess(transaction: local,
                accountId: accountId, principalId: principalId, projectId: projectId)
            let checkpoint = try PropertyManagementReportPowerSyncQuery.completedStreamCheckpoint(transaction: local,
                identity: ProjectExpenseStreamIdentity(accountId: accountId, projectId: projectId))
            guard let invoice = try Self.collectedRecords(transaction: local, accountId: accountId,
                projectId: projectId, invoiceId: invoiceId).first else {
                throw ProjectInvoicingItemLocalReader.Failure.unavailable
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let version = try ProtectedArtifactSHA256.make(bytes: encoder.encode(invoice))
            let visibility = try ProtectedArtifactSHA256.make(bytes: encoder.encode(
                [accountId.rawValue, principalId.rawValue, projectId.rawValue, "collected-invoice-v1"]))
            return try CollectedInvoiceReportSnapshot(invoice: invoice, provenance: .init(
                accountId: accountId, projectId: projectId, principalId: principalId,
                visibilityScopeID: .init(validating: visibility.rawValue),
                localDataVersion: .init(validating: "invoice-report-\(version.rawValue)"),
                authorityVersion: .init(validating: "collected-invoice-v1"), asOf: asOf,
                readiness: .ready, lastSyncedAt: checkpoint))
        }
    }

    // The existing Expense stream already downloads complete sealed Project
    // Invoices. Browse those same facts, independent of whether an Invoice has
    // an Expense line; do not rebuild its history from current source rows.
    func readCollectedInvoices(accountId: AccountID, principalId: PrincipalID,
                               projectId: ProjectID, invoiceId: InvoiceID? = nil) async throws -> [FrozenInvoiceContents] {
        try await database.readTransaction { local in
            try ProjectInvoicingItemLocalReader.requireAccess(transaction: local,
                accountId: accountId, principalId: principalId, projectId: projectId)
            _ = try PropertyManagementReportPowerSyncQuery.completedStreamCheckpoint(transaction: local,
                identity: ProjectExpenseStreamIdentity(accountId: accountId, projectId: projectId))
            return try Self.collectedRecords(transaction: local, accountId: accountId, projectId: projectId, invoiceId: invoiceId)
        }
    }

    func runCollectedInvoices(accountId: AccountID, principalId: PrincipalID, projectId: ProjectID, invoiceId: InvoiceID? = nil,
        receive: @Sendable @escaping ([FrozenInvoiceContents]?) async -> Bool) async throws {
        let stream = ProjectExpenseStreamIdentity(accountId: accountId, projectId: projectId)
        try await withOwnedSyncStreamWatch(subscribe: {
            try await database.syncStream(name: stream.name, params: stream.parameters).subscribe()
        }, observe: {
            let updates = try database.watch(sql: """
                SELECT EXISTS(SELECT 1 FROM spike_account_memberships)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_projects)
                UNION ALL SELECT EXISTS(SELECT 1 FROM collected_invoices)
                UNION ALL SELECT EXISTS(SELECT 1 FROM collected_invoice_lines)
                UNION ALL SELECT EXISTS(SELECT 1 FROM ps_stream_subscriptions)
                """, parameters: nil) { try $0.getInt(index: 0) }
            for try await _ in updates {
                try Task.checkCancellation()
                let value: [FrozenInvoiceContents]?
                do { value = try await readCollectedInvoices(accountId: accountId, principalId: principalId, projectId: projectId, invoiceId: invoiceId) }
                catch PropertyManagementReportFailure.incompleteReadiness { value = nil }
                guard await receive(value) else { return }
            }
        })
    }

    private static func collectedRecords(transaction: any Transaction, accountId: AccountID,
        projectId: ProjectID, expensesOnly: Bool = false, invoiceId: InvoiceID? = nil) throws -> [FrozenInvoiceContents] {
        try transaction.getAll(sql: """
            SELECT json_object('invoice_id',h.id,'invoice_revision',CAST(h.invoice_revision AS TEXT),
              'account_id',h.account_id,'project_id',h.project_id,'client_id',h.client_id,
              'purchase_id',h.purchase_id,'currency',h.currency,'total_minor_units',CAST(h.total_minor_units AS TEXT),
              'display_metadata',json(h.display_metadata),
              'lines',json((SELECT json_group_array(json_object(
                'id',id,'line_position',line_position,'source_kind',source_kind,'source_id',source_id,
                'item_id',item_id,'source_revision',CAST(source_revision AS TEXT),'category_id',category_id,
                'signed_amount_minor_units',CAST(signed_amount_minor_units AS TEXT),'description',description,
                'source_snapshot_json',source_snapshot_json)) FROM (
                  SELECT * FROM collected_invoice_lines WHERE account_id=h.account_id AND invoice_id=h.id ORDER BY line_position)))) AS record
            FROM collected_invoices h WHERE h.account_id=? AND h.project_id=? AND h.sealed=1
              AND (? IS NULL OR h.id=?)
              AND (?=0 OR EXISTS(SELECT 1 FROM collected_invoice_lines l WHERE l.account_id=h.account_id AND l.invoice_id=h.id AND l.source_kind='expense'))
            ORDER BY h.id
            """, parameters: [accountId.rawValue, projectId.rawValue, invoiceId?.rawValue,
                invoiceId?.rawValue, expensesOnly ? 1 : 0]) { c in
                try JSONDecoder().decode(FrozenInvoiceStorageRecord.self,
                    from: Data(c.getString(name: "record").utf8)).restored()
            }
    }

    func receiptObject(accountId: AccountID, principalId: PrincipalID, projectId: ProjectID,
                       expenseId: EntityID, attachmentId: AttachmentID) async throws -> DownloadedMediaObjectReference? {
        try await database.readTransaction { local in
            try ProjectInvoicingItemLocalReader.requireAccess(transaction: local,
                accountId: accountId, principalId: principalId, projectId: projectId)
            _ = try PropertyManagementReportPowerSyncQuery.completedStreamCheckpoint(transaction: local,
                identity: ProjectExpenseStreamIdentity(accountId: accountId, projectId: projectId))
            return try local.getOptional(sql: """
                SELECT o.* FROM expenses e
                JOIN expense_receipt_attachments r ON r.account_id=e.account_id AND r.expense_id=e.id
                JOIN item_image_objects o ON o.account_id=r.account_id AND o.id=r.attachment_id
                WHERE e.account_id=? AND e.project_id=? AND e.id=? AND r.attachment_id=?
                """, parameters: [accountId.rawValue, projectId.rawValue, expenseId.rawValue, attachmentId.rawValue]) {
                    let mediaType = try $0.getString(name: "media_type")
                    return try DownloadedMediaObjectReference(accountId: accountId, attachmentId: $0.getString(name: "id"),
                        sha256: $0.getString(name: "content_sha256"), byteCount: $0.getString(name: "byte_count"),
                        mediaType: mediaType, storagePath: $0.getString(name: "storage_path"),
                        kind: mediaType == "application/pdf" ? .pdf : .image)
                }
        }
    }

    func run(accountId: AccountID, principalId: PrincipalID, projectId: ProjectID,
             receive: @Sendable @escaping (ProjectExpenses?) async -> Bool) async throws {
        let stream = ProjectExpenseStreamIdentity(accountId: accountId, projectId: projectId)
        try await withOwnedSyncStreamWatch(subscribe: {
            try await database.syncStream(name: stream.name, params: stream.parameters).subscribe()
        }, observe: {
            let updates = try database.watch(sql: """
                SELECT EXISTS(SELECT 1 FROM spike_account_memberships)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_projects)
                UNION ALL SELECT EXISTS(SELECT 1 FROM expenses)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_local_operations)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_expense_entry_recovery)
                UNION ALL SELECT EXISTS(SELECT 1 FROM expense_receipt_lines)
                UNION ALL SELECT EXISTS(SELECT 1 FROM expense_receipt_attachments)
                UNION ALL SELECT EXISTS(SELECT 1 FROM item_image_objects)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_budget_categories)
                UNION ALL SELECT EXISTS(SELECT 1 FROM collected_invoices)
                UNION ALL SELECT EXISTS(SELECT 1 FROM collected_invoice_lines)
                UNION ALL SELECT EXISTS(SELECT 1 FROM ps_stream_subscriptions)
                """, parameters: nil) { try $0.getInt(index: 0) }
            for try await _ in updates {
                try Task.checkCancellation()
                let value: ProjectExpenses?
                do { value = try await read(accountId: accountId, principalId: principalId, projectId: projectId) }
                catch PropertyManagementReportFailure.incompleteReadiness { value = nil }
                guard await receive(value) else { return }
            }
        })
    }

    func read(accountId: AccountID, principalId: PrincipalID, projectId: ProjectID) async throws -> ProjectExpenses {
        try await database.readTransaction { local in
            try ProjectInvoicingItemLocalReader.requireAccess(transaction: local,
                accountId: accountId, principalId: principalId, projectId: projectId)
            _ = try PropertyManagementReportPowerSyncQuery.completedStreamCheckpoint(transaction: local,
                identity: ProjectExpenseStreamIdentity(accountId: accountId, projectId: projectId))
            let params: [String] = [accountId.rawValue, projectId.rawValue]
            let lines = try local.getAll(sql: """
                SELECT l.* FROM expense_receipt_lines l JOIN expenses e ON e.account_id=l.account_id AND e.id=l.expense_id
                WHERE e.account_id=? AND e.project_id=? ORDER BY l.expense_id,l.position
                """, parameters: params) { c in
                    let currency = try CurrencyCode(validating: c.getString(name: "currency"))
                    guard let magnitude = Int64(try c.getString(name: "magnitude_minor_units")),
                          let effect = NonItemReceiptLineEffect(rawValue: try c.getString(name: "effect")) else {
                        throw ProjectExpenses.Failure.invalidEvidence
                    }
                    let quantityText = try c.getStringOptional(name: "quantity")
                    let quantity = quantityText.flatMap(Int64.init)
                    guard quantityText == nil || quantity != nil else { throw ProjectExpenses.Failure.invalidEvidence }
                    return (try c.getString(name: "expense_id"), try c.getInt(name: "position"),
                        try NonItemReceiptLine(id: .init(validating: c.getString(name: "line_id")),
                            description: .init(validating: c.getString(name: "description")),
                            magnitude: .init(minorUnits: magnitude, currency: currency), effect: effect, quantity: quantity))
                }
            let attachments = try local.getAll(sql: """
                SELECT a.* FROM expense_receipt_attachments a JOIN expenses e ON e.account_id=a.account_id AND e.id=a.expense_id
                WHERE e.account_id=? AND e.project_id=? ORDER BY a.expense_id,a.position
                """, parameters: params) {
                    (try $0.getString(name: "expense_id"), try $0.getInt(name: "position"),
                     try AttachmentID(validating: $0.getString(name: "attachment_id")))
                }
            let groupedLines = Dictionary(grouping: lines, by: { $0.0 })
            let groupedAttachments = Dictionary(grouping: attachments, by: { $0.0 })
            let objects = try local.getAll(sql: """
                SELECT r.expense_id,o.* FROM expenses e
                JOIN expense_receipt_attachments r ON r.account_id=e.account_id AND r.expense_id=e.id
                JOIN item_image_objects o ON o.account_id=r.account_id AND o.id=r.attachment_id
                WHERE e.account_id=? AND e.project_id=? ORDER BY r.expense_id,r.position
                """, parameters: params) { c in
                    let mediaType = try c.getString(name: "media_type")
                    return (try c.getString(name: "expense_id"), try DownloadedMediaObjectReference(
                        accountId: accountId, attachmentId: c.getString(name: "id"),
                        sha256: c.getString(name: "content_sha256"), byteCount: c.getString(name: "byte_count"),
                        mediaType: mediaType, storagePath: c.getString(name: "storage_path"),
                        kind: mediaType == "application/pdf" ? .pdf : .image))
                }
            let groupedObjects = Dictionary(grouping: objects, by: { $0.0 })
            let invoices = try Self.collectedRecords(transaction: local, accountId: accountId,
                projectId: projectId, expensesOnly: true)
            var paid: [ExpenseID:FrozenInvoiceContents] = [:]
            for invoice in invoices {
                for line in invoice.lines {
                    guard case .expense(let id) = line.source else { continue }
                    guard paid.updateValue(invoice, forKey: id) == nil else { throw ProjectExpenses.Failure.invalidEvidence }
                }
            }
            let paidByExpense = paid
            let expenses = try local.getAll(sql: """
                SELECT e.*, category.display_name AS current_category_name FROM expenses e
                LEFT JOIN spike_budget_categories category ON category.account_id=e.account_id AND category.id=e.category_id
                WHERE e.account_id=? AND e.project_id=? ORDER BY e.id
                """, parameters: params) { c in
                let id = try c.getString(name: "id"), detail = groupedLines[id] ?? [], media = groupedAttachments[id] ?? []
                guard detail.enumerated().allSatisfy({ $0.offset == $0.element.1 }),
                      media.enumerated().allSatisfy({ $0.offset == $0.element.1 }),
                      let amount = Int64(try c.getString(name: "final_amount_minor_units")),
                      let revision = Int64(try c.getString(name: "revision")) else { throw ProjectExpenses.Failure.invalidEvidence }
                return try ProjectExpenses.Expense(entry: .init(accountId: accountId, projectId: projectId,
                    expenseId: .init(validating: id), vendor: c.getString(name: "vendor"), date: c.getString(name: "expense_date"),
                    finalAmount: .init(minorUnits: amount, currency: .init(validating: c.getString(name: "currency"))),
                    categoryId: .init(validating: c.getString(name: "category_id")), notes: c.getString(name: "notes"),
                    receiptAttachmentIds: media.map { $0.2 }, receiptLines: detail.map { $0.2 }), revision: revision,
                    currentCategoryName: c.getStringOptional(name: "current_category_name"),
                    receiptObjects: (groupedObjects[id] ?? []).map { $0.1 },
                    collectedInvoice: paidByExpense[try .init(validating: id)])
            }
            let pending: [ProjectExpenses.PendingCreation] = try local.getAll(sql: """
                SELECT id,subject_id,local_state,fingerprint,command_envelope_json FROM spike_local_operations
                WHERE account_id=? AND actor_principal_id=? AND command_type='create_expense'
                  AND local_state IN ('queued','applying','applied','rejected') ORDER BY accepted_at_ms,id
                """, parameters: [accountId.rawValue, principalId.rawValue]) { c -> ProjectExpenses.PendingCreation in
                    let json = try c.getString(name: "command_envelope_json")
                    let command = try OperationContractCodec.decode(CreateExpenseCommand.self,
                        from: Data("{\"envelope\":\(json)}".utf8))
                    let e = command.envelope
                    guard e.accountId == accountId, e.actorPrincipalId == principalId,
                          e.operationId.rawValue == (try c.getString(name: "id")),
                          e.payload.expenseId.rawValue == (try c.getString(name: "subject_id")),
                          AccountBoundOperationIdentity.isValid(e.operationId, family: .expenseCreation, accountId: accountId),
                          try CreateExpenseUploadRequest(command).fingerprint == c.getString(name: "fingerprint"),
                          let state = LocalOperationState(rawValue: try c.getString(name: "local_state"))
                    else { throw ProjectExpenses.Failure.invalidEvidence }
                    return try ProjectExpenses.PendingCreation(id: e.operationId, entry: e.payload, state: state)
                }.filter { pending in
                    pending.entry.projectId == projectId && !expenses.contains { $0.id == pending.entry.expenseId }
                }
            let edits: [ProjectExpenses.PendingEdit] = try local.getAll(sql: """
                SELECT id,subject_id,local_state,fingerprint,command_envelope_json FROM spike_local_operations
                WHERE account_id=? AND actor_principal_id=? AND command_type='edit_expense'
                  AND local_state IN ('queued','applying','applied','rejected') ORDER BY accepted_at_ms,id
                """, parameters: [accountId.rawValue, principalId.rawValue]) { c -> ProjectExpenses.PendingEdit in
                    let json = try c.getString(name: "command_envelope_json")
                    let command = try OperationContractCodec.decode(EditExpenseCommand.self,
                        from: Data("{\"envelope\":\(json)}".utf8))
                    let e = command.envelope
                    guard e.accountId == accountId, e.actorPrincipalId == principalId,
                          e.operationId.rawValue == (try c.getString(name: "id")),
                          e.payload.entry.expenseId.rawValue == (try c.getString(name: "subject_id")),
                          AccountBoundOperationIdentity.isValid(e.operationId, family: .expenseEdit, accountId: accountId),
                          try EditExpenseUploadRequest(command).fingerprint == c.getString(name: "fingerprint"),
                          let state = LocalOperationState(rawValue: try c.getString(name: "local_state"))
                    else { throw ProjectExpenses.Failure.invalidEvidence }
                    return try ProjectExpenses.PendingEdit(id: e.operationId, entry: e.payload.entry,
                        expectedRevision: e.payload.expectedRevision, state: state)
                }.filter { pending in
                    pending.entry.projectId == projectId && !(pending.state == .applied && expenses.contains {
                        $0.id == pending.entry.expenseId && $0.revision > pending.expectedRevision
                    })
                }
            let unfinished = try local.getAll(sql: """
                SELECT d.id,d.entry_json FROM spike_expense_entry_recovery d
                WHERE d.account_id=? AND d.actor_principal_id=? AND d.project_id=?
                  AND NOT EXISTS(SELECT 1 FROM spike_local_operations o WHERE o.account_id=d.account_id
                    AND o.command_type='create_expense' AND o.subject_id=d.id)
                  AND NOT EXISTS(SELECT 1 FROM expenses e WHERE e.account_id=d.account_id AND e.id=d.id)
                ORDER BY d.id
                """, parameters: [accountId.rawValue, principalId.rawValue, projectId.rawValue]) { c in
                    let value = try OperationContractCodec.decode(ExpenseEntryRecovery.self,
                        from: Data(c.getString(name: "entry_json").utf8))
                    guard value.accountId == accountId, value.projectId == projectId,
                          value.expenseId.rawValue == (try c.getString(name: "id")) else { throw ProjectExpenses.Failure.invalidEvidence }
                    return value
                }
            return try ProjectExpenses(accountId: accountId, projectId: projectId, expenses: expenses,
                pendingCreations: pending, pendingEdits: edits, unfinishedEntries: unfinished)
        }
    }
}
