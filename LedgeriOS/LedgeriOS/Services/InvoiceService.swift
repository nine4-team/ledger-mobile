import FirebaseFirestore

/// CRUD + state-machine operations for `Invoice` documents.
///
/// All multi-doc operations (create, mark paid, void) commit through an injected
/// `BatchWriting` so they're atomic — the invoice and every cascaded item/transaction
/// update either all succeed or all fail. Modeled on `InventoryOperationsService`.
struct InvoiceService: InvoiceServiceProtocol {
    private let makeBatch: @Sendable () -> any BatchWriting
    private let itemsService: ItemsServiceProtocol
    private let transactionsService: TransactionsServiceProtocol

    init(
        itemsService: ItemsServiceProtocol = ItemsService(),
        transactionsService: TransactionsServiceProtocol = TransactionsService(),
        makeBatch: @escaping @Sendable () -> any BatchWriting = { FirestoreBatchWriter() }
    ) {
        self.itemsService = itemsService
        self.transactionsService = transactionsService
        self.makeBatch = makeBatch
    }

    private func repo(accountId: String) -> FirestoreRepository<Invoice> {
        FirestoreRepository<Invoice>(path: "accounts/\(accountId)/invoices")
    }

    private static func invoicesPath(_ accountId: String) -> String {
        "accounts/\(accountId)/invoices"
    }

    private static func itemsPath(_ accountId: String) -> String {
        "accounts/\(accountId)/items"
    }

    private static func transactionsPath(_ accountId: String) -> String {
        "accounts/\(accountId)/transactions"
    }

    // MARK: - Read

    func getInvoice(accountId: String, invoiceId: String) async throws -> Invoice? {
        try await repo(accountId: accountId).get(id: invoiceId)
    }

    func subscribeToInvoices(
        accountId: String,
        onChange: @escaping ([Invoice]) -> Void
    ) -> ListenerRegistration {
        repo(accountId: accountId).subscribe(onChange: onChange)
    }

    func subscribeToInvoice(
        accountId: String,
        invoiceId: String,
        onChange: @escaping (Invoice?) -> Void
    ) -> ListenerRegistration {
        repo(accountId: accountId).subscribe(id: invoiceId, onChange: onChange)
    }

    // MARK: - Create (cascade items + transactions to .invoiced)

    func createInvoice(
        accountId: String,
        projectId: String,
        itemIds: [String],
        transactionIds: [String],
        totalCents: Int,
        invoiceNumber: String?,
        notes: String?,
        userId: String?
    ) async throws -> String {
        let batch = makeBatch()
        let now = FieldValue.serverTimestamp()

        // Generate the invoice ID up front so the cascade writes can reference it
        // and so the caller gets a stable ID back. Firestore client supports this
        // via collection().document() — but BatchWriting only exposes setDataAutoId
        // (which generates internally). To return an ID we use a freshly-generated UUID
        // as the document ID via setData(merge:false).
        let invoiceId = UUID().uuidString
        let invoicePath = "\(Self.invoicesPath(accountId))/\(invoiceId)"

        var invoiceFields: [String: Any] = [
            "accountId": accountId,
            "projectId": projectId,
            "status": InvoiceStatus.draft.rawValue,
            "itemIds": itemIds,
            "transactionIds": transactionIds,
            "totalCents": totalCents,
            "dateIssued": now,
            "createdAt": now,
            "updatedAt": now,
        ]
        if let invoiceNumber { invoiceFields["invoiceNumber"] = invoiceNumber }
        if let notes { invoiceFields["notes"] = notes }
        if let userId {
            invoiceFields["createdBy"] = userId
            invoiceFields["updatedBy"] = userId
        }

        batch.setData(invoiceFields, forDocumentAt: invoicePath, merge: false)

        // Cascade: every referenced item → billingStatus = .invoiced
        for itemId in itemIds {
            var update: [String: Any] = [
                "billingStatus": BillingStatus.invoiced.rawValue,
                "updatedAt": now,
            ]
            if let userId { update["updatedBy"] = userId }
            batch.updateData(update, forDocumentAt: "\(Self.itemsPath(accountId))/\(itemId)")
        }

        // Cascade: every referenced transaction → billingStatus = .invoiced
        for txId in transactionIds {
            var update: [String: Any] = [
                "billingStatus": BillingStatus.invoiced.rawValue,
                "updatedAt": now,
            ]
            if let userId { update["updatedBy"] = userId }
            batch.updateData(update, forDocumentAt: "\(Self.transactionsPath(accountId))/\(txId)")
        }

        try await batch.commit()
        return invoiceId
    }

    // MARK: - Update Selections (add/remove items + tx, draft-only per UI gate)

    /// Replaces the items+transactions on a draft invoice and cascades billingStatus
    /// changes for both removed (→ unbilled) and added (→ invoiced) entries.
    /// Also updates the invoice's name (`invoiceNumber`), notes, and snapshot total.
    func updateSelections(
        invoice: Invoice,
        accountId: String,
        newItemIds: [String],
        newTransactionIds: [String],
        newTotalCents: Int,
        invoiceNumber: String?,
        notes: String?,
        userId: String?
    ) async throws {
        guard let invoiceId = invoice.id else { return }

        let oldItemIds = Set(invoice.itemIds ?? [])
        let oldTxIds = Set(invoice.transactionIds ?? [])
        let newItemSet = Set(newItemIds)
        let newTxSet = Set(newTransactionIds)

        let removedItemIds = oldItemIds.subtracting(newItemSet)
        let addedItemIds = newItemSet.subtracting(oldItemIds)
        let removedTxIds = oldTxIds.subtracting(newTxSet)
        let addedTxIds = newTxSet.subtracting(oldTxIds)

        let batch = makeBatch()
        let now = FieldValue.serverTimestamp()

        // Invoice doc
        var invoiceFields: [String: Any] = [
            "itemIds": newItemIds,
            "transactionIds": newTransactionIds,
            "totalCents": newTotalCents,
            "updatedAt": now,
        ]
        invoiceFields["invoiceNumber"] = (invoiceNumber?.isEmpty == false) ? invoiceNumber! : FieldValue.delete()
        invoiceFields["notes"] = (notes?.isEmpty == false) ? notes! : FieldValue.delete()
        if let userId { invoiceFields["updatedBy"] = userId }
        batch.updateData(invoiceFields, forDocumentAt: "\(Self.invoicesPath(accountId))/\(invoiceId)")

        // Removed → unbilled
        for itemId in removedItemIds {
            var update: [String: Any] = [
                "billingStatus": BillingStatus.unbilled.rawValue,
                "updatedAt": now,
            ]
            if let userId { update["updatedBy"] = userId }
            batch.updateData(update, forDocumentAt: "\(Self.itemsPath(accountId))/\(itemId)")
        }
        for txId in removedTxIds {
            var update: [String: Any] = [
                "billingStatus": BillingStatus.unbilled.rawValue,
                "updatedAt": now,
            ]
            if let userId { update["updatedBy"] = userId }
            batch.updateData(update, forDocumentAt: "\(Self.transactionsPath(accountId))/\(txId)")
        }

        // Added → invoiced
        for itemId in addedItemIds {
            var update: [String: Any] = [
                "billingStatus": BillingStatus.invoiced.rawValue,
                "updatedAt": now,
            ]
            if let userId { update["updatedBy"] = userId }
            batch.updateData(update, forDocumentAt: "\(Self.itemsPath(accountId))/\(itemId)")
        }
        for txId in addedTxIds {
            var update: [String: Any] = [
                "billingStatus": BillingStatus.invoiced.rawValue,
                "updatedAt": now,
            ]
            if let userId { update["updatedBy"] = userId }
            batch.updateData(update, forDocumentAt: "\(Self.transactionsPath(accountId))/\(txId)")
        }

        try await batch.commit()
    }

    // MARK: - Mark Sent (status only, no cascade)

    func markSent(invoiceId: String, accountId: String, userId: String?) async throws {
        let batch = makeBatch()
        let now = FieldValue.serverTimestamp()

        var fields: [String: Any] = [
            "status": InvoiceStatus.sent.rawValue,
            "dateSent": now,
            "updatedAt": now,
        ]
        if let userId { fields["updatedBy"] = userId }

        batch.updateData(fields, forDocumentAt: "\(Self.invoicesPath(accountId))/\(invoiceId)")
        try await batch.commit()
    }

    // MARK: - Mark Paid (cascade items + transactions to .paid)

    func markPaid(invoice: Invoice, accountId: String, userId: String?) async throws {
        guard let invoiceId = invoice.id else { return }

        let batch = makeBatch()
        let now = FieldValue.serverTimestamp()

        var invoiceFields: [String: Any] = [
            "status": InvoiceStatus.paid.rawValue,
            "datePaid": now,
            "updatedAt": now,
        ]
        if let userId { invoiceFields["updatedBy"] = userId }
        batch.updateData(invoiceFields, forDocumentAt: "\(Self.invoicesPath(accountId))/\(invoiceId)")

        for itemId in invoice.itemIds ?? [] {
            var update: [String: Any] = [
                "billingStatus": BillingStatus.paid.rawValue,
                "updatedAt": now,
            ]
            if let userId { update["updatedBy"] = userId }
            batch.updateData(update, forDocumentAt: "\(Self.itemsPath(accountId))/\(itemId)")
        }

        for txId in invoice.transactionIds ?? [] {
            var update: [String: Any] = [
                "billingStatus": BillingStatus.paid.rawValue,
                "updatedAt": now,
            ]
            if let userId { update["updatedBy"] = userId }
            batch.updateData(update, forDocumentAt: "\(Self.transactionsPath(accountId))/\(txId)")
        }

        try await batch.commit()
    }

    // MARK: - Void (revert .invoiced → .unbilled, skip .paid)

    func voidInvoice(invoice: Invoice, accountId: String, userId: String?) async throws {
        guard let invoiceId = invoice.id else { return }

        // Pre-batch reads: skip any item/transaction already at .paid (paid is terminal).
        // Reads happen outside the batch — Firestore client batches don't support reads.
        var revertItemIds: [String] = []
        for itemId in invoice.itemIds ?? [] {
            let item = try await itemsService.getItem(accountId: accountId, itemId: itemId)
            if item?.billingStatus != .paid {
                revertItemIds.append(itemId)
            }
        }

        var revertTxIds: [String] = []
        for txId in invoice.transactionIds ?? [] {
            let tx = try await transactionsService.getTransaction(accountId: accountId, transactionId: txId)
            if tx?.billingStatus != .paid {
                revertTxIds.append(txId)
            }
        }

        let batch = makeBatch()
        let now = FieldValue.serverTimestamp()

        var invoiceFields: [String: Any] = [
            "status": InvoiceStatus.voided.rawValue,
            "dateVoided": now,
            "updatedAt": now,
        ]
        if let userId { invoiceFields["updatedBy"] = userId }
        batch.updateData(invoiceFields, forDocumentAt: "\(Self.invoicesPath(accountId))/\(invoiceId)")

        for itemId in revertItemIds {
            var update: [String: Any] = [
                "billingStatus": BillingStatus.unbilled.rawValue,
                "updatedAt": now,
            ]
            if let userId { update["updatedBy"] = userId }
            batch.updateData(update, forDocumentAt: "\(Self.itemsPath(accountId))/\(itemId)")
        }

        for txId in revertTxIds {
            var update: [String: Any] = [
                "billingStatus": BillingStatus.unbilled.rawValue,
                "updatedAt": now,
            ]
            if let userId { update["updatedBy"] = userId }
            batch.updateData(update, forDocumentAt: "\(Self.transactionsPath(accountId))/\(txId)")
        }

        try await batch.commit()
    }
}
