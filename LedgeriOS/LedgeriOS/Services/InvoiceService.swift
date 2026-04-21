import FirebaseFirestore

/// CRUD + state-machine operations for `Invoice` documents (v2 model).
///
/// v2 behavior: the invoice is the single source of truth for paid-state.
/// `itemIds` / `transactionIds` are written as a flat membership index
/// (derived from `lines`) so "is this source on any invoice?" queries don't
/// have to scan every line.
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

    // MARK: - Create

    func createInvoice(
        accountId: String,
        projectId: String,
        lines: [InvoiceLine],
        totalCents: Int,
        invoiceNumber: String?,
        notes: String?,
        userId: String?
    ) async throws -> String {
        let batch = makeBatch()
        let now = FieldValue.serverTimestamp()

        let invoiceId = UUID().uuidString
        let invoicePath = "\(Self.invoicesPath(accountId))/\(invoiceId)"

        let (itemIds, transactionIds) = Self.membership(from: lines)

        var invoiceFields: [String: Any] = [
            "accountId": accountId,
            "projectId": projectId,
            "status": InvoiceStatus.draft.rawValue,
            "itemIds": itemIds,
            "transactionIds": transactionIds,
            "lines": lines.map(Self.encodeLine),
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
        try await batch.commit()
        return invoiceId
    }

    // MARK: - Update Selections (draft-only per UI gate)

    func updateSelections(
        invoice: Invoice,
        accountId: String,
        newLines: [InvoiceLine],
        newTotalCents: Int,
        invoiceNumber: String?,
        notes: String?,
        userId: String?
    ) async throws {
        guard let invoiceId = invoice.id else { return }

        let batch = makeBatch()
        let now = FieldValue.serverTimestamp()
        let (itemIds, transactionIds) = Self.membership(from: newLines)

        var invoiceFields: [String: Any] = [
            "itemIds": itemIds,
            "transactionIds": transactionIds,
            "lines": newLines.map(Self.encodeLine),
            "totalCents": newTotalCents,
            "updatedAt": now,
        ]
        invoiceFields["invoiceNumber"] = (invoiceNumber?.isEmpty == false) ? invoiceNumber! : FieldValue.delete()
        invoiceFields["notes"] = (notes?.isEmpty == false) ? notes! : FieldValue.delete()
        if let userId { invoiceFields["updatedBy"] = userId }

        batch.updateData(invoiceFields, forDocumentAt: "\(Self.invoicesPath(accountId))/\(invoiceId)")
        try await batch.commit()
    }

    // MARK: - Mark Sent

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
                if seenItems.insert(line.sourceId).inserted { itemIds.append(line.sourceId) }
            case .transaction:
                if seenTx.insert(line.sourceId).inserted { txIds.append(line.sourceId) }
            }
        }
        return (itemIds, txIds)
    }

    /// Encode an InvoiceLine as a plain `[String: Any]` for Firestore's untyped batch writer.
    private static func encodeLine(_ line: InvoiceLine) -> [String: Any] {
        var dict: [String: Any] = [
            "sourceType": line.sourceType.rawValue,
            "sourceId": line.sourceId,
            "amountCents": line.amountCents,
            "sign": line.sign.rawValue,
        ]
        if let name = line.snapshotName { dict["snapshotName"] = name }
        return dict
    }
}
