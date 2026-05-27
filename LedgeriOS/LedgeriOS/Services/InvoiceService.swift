import FirebaseFirestore

/// CRUD + state-machine operations for `Invoice` documents (v2 model).
///
/// v2 behavior: the invoice is the single source of truth for paid-state.
/// `itemIds` / `transactionIds` are written as a flat membership index
/// (derived from `lines`) so "is this source on any invoice?" queries don't
/// have to scan every line.
///
/// **Drafts are live previews.** While an invoice is `status == .draft`,
/// the document stores only `itemIds` / `transactionIds` — the membership index.
/// `lines` and `totalCents` are materialized at `markSent` from the then-current
/// item / transaction state. Readers of a draft recompute the displayed total
/// from that live state; readers of a sent / paid invoice read the frozen snapshot.
struct InvoiceService: InvoiceServiceProtocol {
    private let makeBatch: @Sendable () -> any BatchWriting

    init(
        makeBatch: @escaping @Sendable () -> any BatchWriting = { FirestoreBatchWriter() }
    ) {
        self.makeBatch = makeBatch
    }

    private func repo(accountId: String) -> FirestoreRepository<Invoice> {
        FirestoreRepository<Invoice>(path: "accounts/\(accountId)/invoices")
    }

    private static func invoicesPath(_ accountId: String) -> String {
        "accounts/\(accountId)/invoices"
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

    // MARK: - Create (draft — live preview, no stored lines/total)

    func createInvoice(
        accountId: String,
        projectId: String,
        itemIds: [String],
        transactionIds: [String],
        lines: [InvoiceLine]? = nil,
        invoiceNumber: String?,
        notes: String?,
        userId: String?
    ) async throws -> String {
        let batch = makeBatch()
        let now = FieldValue.serverTimestamp()

        let invoiceId = UUID().uuidString
        let invoicePath = "\(Self.invoicesPath(accountId))/\(invoiceId)"

        var invoiceFields: [String: Any] = [
            "accountId": accountId,
            "projectId": projectId,
            "status": InvoiceStatus.draft.rawValue,
            "itemIds": itemIds,
            "transactionIds": transactionIds,
            "dateIssued": now,
            "createdAt": now,
            "updatedAt": now,
        ]
        if let invoiceNumber { invoiceFields["invoiceNumber"] = invoiceNumber }
        if let notes { invoiceFields["notes"] = notes }
        if let lines { invoiceFields["lines"] = lines.map(Self.encodeLine) }
        if let userId {
            invoiceFields["createdBy"] = userId
            invoiceFields["updatedBy"] = userId
        }

        batch.setData(invoiceFields, forDocumentAt: invoicePath, merge: false)
        try await batch.commit()
        return invoiceId
    }

    // MARK: - Update Selections (draft-only per UI gate)

    func updateSelections(
        invoice: Invoice,
        accountId: String,
        newItemIds: [String],
        newTransactionIds: [String],
        lines: [InvoiceLine]? = nil,
        invoiceNumber: String?,
        notes: String?,
        userId: String?
    ) async throws {
        guard let invoiceId = invoice.id else { return }

        let batch = makeBatch()
        let now = FieldValue.serverTimestamp()

        var invoiceFields: [String: Any] = [
            "itemIds": newItemIds,
            "transactionIds": newTransactionIds,
            // Clear any stale total snapshot — drafts render totals live from
            // membership plus stored manual lines.
            "totalCents": FieldValue.delete(),
            "updatedAt": now,
        ]
        if let lines {
            invoiceFields["lines"] = lines.map(Self.encodeLine)
        } else {
            invoiceFields["lines"] = FieldValue.delete()
        }
        invoiceFields["invoiceNumber"] = (invoiceNumber?.isEmpty == false) ? invoiceNumber! : FieldValue.delete()
        invoiceFields["notes"] = (notes?.isEmpty == false) ? notes! : FieldValue.delete()
        if let userId { invoiceFields["updatedBy"] = userId }

        batch.updateData(invoiceFields, forDocumentAt: "\(Self.invoicesPath(accountId))/\(invoiceId)")
        try await batch.commit()
    }

    // MARK: - Mark Sent (materialize the snapshot)

    func markSent(
        invoiceId: String,
        accountId: String,
        lines: [InvoiceLine],
        totalCents: Int,
        userId: String?
    ) async throws {
        let batch = makeBatch()
        let now = FieldValue.serverTimestamp()

        let (itemIds, transactionIds) = Self.membership(from: lines)

        var fields: [String: Any] = [
            "status": InvoiceStatus.sent.rawValue,
            "dateSent": now,
            "lines": lines.map(Self.encodeLine),
            "totalCents": totalCents,
            "itemIds": itemIds,
            "transactionIds": transactionIds,
            "updatedAt": now,
        ]
        if let userId { fields["updatedBy"] = userId }

        batch.updateData(fields, forDocumentAt: "\(Self.invoicesPath(accountId))/\(invoiceId)")
        try await batch.commit()
    }

    // MARK: - Mark Paid (status only — no cascade)

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
        try await batch.commit()
    }

    // MARK: - Mark Collected (create settlement transaction + paid status)

    func markCollected(
        invoice: Invoice,
        accountId: String,
        projectId: String,
        amountCents: Int,
        source: String,
        budgetCategoryId: String?,
        settlementInvoiceLineIds: [String]?,
        userId: String?
    ) async throws -> String {
        guard let invoiceId = invoice.id else { return "" }

        let batch = makeBatch()
        let now = FieldValue.serverTimestamp()
        let transactionId = UUID().uuidString
        let txPath = "accounts/\(accountId)/transactions/\(transactionId)"

        var txFields: [String: Any] = [
            "projectId": projectId,
            "amountCents": amountCents,
            "type": TransactionType.fee.rawValue,
            "source": source,
            "transactionDate": Self.todayString(),
            "isComplete": true,
            "settlementInvoiceId": invoiceId,
            "createdAt": now,
            "updatedAt": now,
        ]
        if let budgetCategoryId { txFields["budgetCategoryId"] = budgetCategoryId }
        if let lineIds = settlementInvoiceLineIds, !lineIds.isEmpty {
            txFields["settlementInvoiceLineIds"] = lineIds
        }

        var invoiceFields: [String: Any] = [
            "status": InvoiceStatus.paid.rawValue,
            "datePaid": now,
            "updatedAt": now,
        ]
        if let userId { invoiceFields["updatedBy"] = userId }

        batch.setData(txFields, forDocumentAt: txPath, merge: false)
        batch.updateData(invoiceFields, forDocumentAt: "\(Self.invoicesPath(accountId))/\(invoiceId)")
        try await batch.commit()
        return transactionId
    }

    // MARK: - Void (status only — members return to pool via derived query)

    func voidInvoice(invoice: Invoice, accountId: String, userId: String?) async throws {
        guard let invoiceId = invoice.id else { return }

        let batch = makeBatch()
        let now = FieldValue.serverTimestamp()

        var invoiceFields: [String: Any] = [
            "status": InvoiceStatus.voided.rawValue,
            "dateVoided": now,
            "updatedAt": now,
        ]
        if let userId { invoiceFields["updatedBy"] = userId }
        batch.updateData(invoiceFields, forDocumentAt: "\(Self.invoicesPath(accountId))/\(invoiceId)")
        try await batch.commit()
    }

    // MARK: - Helpers

    /// Derive the flat membership index (itemIds, transactionIds) from a list of
    /// signed lines. Order preserved, duplicates stripped (shouldn't occur in
    /// practice since the picker enforces single membership).
    private static func membership(from lines: [InvoiceLine]) -> (itemIds: [String], transactionIds: [String]) {
        var itemIds: [String] = []
        var txIds: [String] = []
        var seenItems: Set<String> = []
        var seenTx: Set<String> = []
        for line in lines {
            switch line.sourceType {
            case .item:
                guard let sourceId = line.sourceId else { continue }
                if seenItems.insert(sourceId).inserted { itemIds.append(sourceId) }
            case .transaction:
                guard let sourceId = line.sourceId else { continue }
                if seenTx.insert(sourceId).inserted { txIds.append(sourceId) }
            case .manual:
                continue
            }
        }
        return (itemIds, txIds)
    }

    /// Encode an InvoiceLine as a plain `[String: Any]` for Firestore's untyped batch writer.
    private static func encodeLine(_ line: InvoiceLine) -> [String: Any] {
        var dict: [String: Any] = [
            "id": line.id,
            "sourceType": line.sourceType.rawValue,
            "amountCents": line.amountCents,
            "sign": line.sign.rawValue,
        ]
        if let sourceId = line.sourceId { dict["sourceId"] = sourceId }
        if let name = line.snapshotName { dict["snapshotName"] = name }
        if let settlementIds = line.settlementTransactionIds { dict["settlementTransactionIds"] = settlementIds }
        return dict
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date())
    }
}
