import FirebaseFirestore

/// CRUD + state-machine operations for `Invoice` documents (v2 model).
///
/// v2 behavior: the invoice is the single source of truth for paid-state.
/// `itemIds` / `transactionIds` are written as a flat membership index
/// (derived from `lines`) so "is this source on any invoice?" queries don't
/// have to scan every line.
///
/// **Created invoices are live previews.** While an invoice is `status == .created`,
/// the document stores only `itemIds` / `transactionIds` — the membership index.
/// `lines` and `totalCents` are finalized when the invoice is paid. Created and
/// sent invoice readers recompute displayed totals from live source state.
struct InvoiceService: InvoiceServiceProtocol {
    enum InvoiceServiceError: Error {
        case invoiceMissingId
        case invoiceLineMissingCategory(lineId: String)
        case noCollectibleLines
        case nonPositiveCollection
        case noSettlementTransactions
    }

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

    // MARK: - Create (live preview, no stored lines/total)

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
            "status": InvoiceStatus.created.rawValue,
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

        Self.ensureSystemCategory(for: lines ?? [], accountId: accountId, batch: batch)
        batch.setData(invoiceFields, forDocumentAt: invoicePath, merge: false)
        try await batch.commit()
        return invoiceId
    }

    // MARK: - Update Selections (created-only per UI gate)

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
            // Clear any stale total snapshot — created invoices render totals live from
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

        Self.ensureSystemCategory(for: lines ?? [], accountId: accountId, batch: batch)
        batch.updateData(invoiceFields, forDocumentAt: "\(Self.invoicesPath(accountId))/\(invoiceId)")
        try await batch.commit()
    }

    // MARK: - Mark Sent (record source-linked lines, keep amounts live)

    func markSent(
        invoiceId: String,
        accountId: String,
        lines: [InvoiceLine],
        totalCents: Int,
        userId: String?
    ) async throws {
        let batch = makeBatch()
        let now = FieldValue.serverTimestamp()

        Self.ensureSystemCategory(for: lines, accountId: accountId, batch: batch)

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
        settlementInvoiceLineIds: [String]?,
        userId: String?
    ) async throws -> [String] {
        guard let invoiceId = invoice.id else { throw InvoiceServiceError.invoiceMissingId }
        guard let invoiceLines = invoice.lines, !invoiceLines.isEmpty else {
            throw InvoiceServiceError.noCollectibleLines
        }

        let selectedLineIds = settlementInvoiceLineIds.map(Set.init)
        let lines = invoiceLines.filter { line in
            selectedLineIds?.contains(line.id) ?? true
        }
        guard !lines.isEmpty else { throw InvoiceServiceError.noCollectibleLines }
        let settlesWholeInvoice = lines.count == invoiceLines.count
        let selectedTotal = lines.reduce(0) { $0 + $1.signedAmountCents }
        guard selectedTotal > 0 else { throw InvoiceServiceError.nonPositiveCollection }

        var grouped: [String: [InvoiceLine]] = [:]
        for line in lines {
            guard let categoryId = line.budgetCategoryId, !categoryId.isEmpty else {
                throw InvoiceServiceError.invoiceLineMissingCategory(lineId: line.id)
            }
            grouped[categoryId, default: []].append(line)
        }

        let batch = makeBatch()
        let now = FieldValue.serverTimestamp()

        Self.ensureSystemCategory(for: lines, accountId: accountId, batch: batch)

        var transactionIds: [String] = []
        for (categoryId, categoryLines) in grouped.sorted(by: { $0.key < $1.key }) {
            let categoryAmount = categoryLines.reduce(0) { $0 + $1.signedAmountCents }
            guard categoryAmount > 0 else { throw InvoiceServiceError.nonPositiveCollection }

            let transactionId = UUID().uuidString
            transactionIds.append(transactionId)
            let txPath = "accounts/\(accountId)/transactions/\(transactionId)"
            let lineIds = categoryLines.map(\.id)

            let txFields: [String: Any] = [
                "projectId": projectId,
                "amountCents": categoryAmount,
                "type": TransactionType.paymentToBusiness.rawValue,
                "source": source,
                "transactionDate": Self.todayString(),
                "isComplete": true,
                "budgetCategoryId": categoryId,
                "settlementInvoiceId": invoiceId,
                "settlementInvoiceLineIds": lineIds,
                "createdAt": now,
                "updatedAt": now,
            ]
            batch.setData(txFields, forDocumentAt: txPath, merge: false)
        }

        guard !transactionIds.isEmpty else { throw InvoiceServiceError.noCollectibleLines }

        var invoiceFields: [String: Any] = [
            "status": settlesWholeInvoice ? InvoiceStatus.paid.rawValue : InvoiceStatus.sent.rawValue,
            "lines": invoiceLines.map { line in
                guard lines.contains(where: { $0.id == line.id }) else { return Self.encodeLine(line) }
                return Self.encodeLine(InvoiceLine(
                    id: line.id,
                    sourceType: line.sourceType,
                    sourceId: line.sourceId,
                    amountCents: line.amountCents,
                    sign: line.sign,
                    budgetCategoryId: line.budgetCategoryId,
                    snapshotName: line.snapshotName,
                    settlementTransactionIds: transactionIds
                ))
            },
            "totalCents": settlesWholeInvoice ? selectedTotal : (invoice.totalCents ?? invoiceLines.reduce(0) { $0 + $1.signedAmountCents }),
            "itemIds": Self.membership(from: invoiceLines).itemIds,
            "transactionIds": Self.membership(from: invoiceLines).transactionIds,
            "updatedAt": now,
        ]
        if settlesWholeInvoice { invoiceFields["datePaid"] = now }
        if let userId { invoiceFields["updatedBy"] = userId }

        batch.updateData(invoiceFields, forDocumentAt: "\(Self.invoicesPath(accountId))/\(invoiceId)")
        try await batch.commit()
        return transactionIds
    }

    // MARK: - Void Payment (correction — cancel generated settlement transactions)

    func voidInvoicePayment(
        invoice: Invoice,
        accountId: String,
        settlementTransactionIds: [String],
        userId: String?
    ) async throws {
        guard let invoiceId = invoice.id else { throw InvoiceServiceError.invoiceMissingId }
        guard !settlementTransactionIds.isEmpty else { throw InvoiceServiceError.noSettlementTransactions }

        let batch = makeBatch()
        let now = FieldValue.serverTimestamp()

        var transactionFields: [String: Any] = [
            "status": TransactionStatus.canceled.rawValue,
            "updatedAt": now,
        ]
        if let userId { transactionFields["updatedBy"] = userId }

        for transactionId in settlementTransactionIds {
            batch.updateData(
                transactionFields,
                forDocumentAt: "accounts/\(accountId)/transactions/\(transactionId)"
            )
        }

        var invoiceFields: [String: Any] = [
            "status": InvoiceStatus.sent.rawValue,
            "datePaid": FieldValue.delete(),
            "updatedAt": now,
        ]
        if let userId { invoiceFields["updatedBy"] = userId }
        batch.updateData(invoiceFields, forDocumentAt: "\(Self.invoicesPath(accountId))/\(invoiceId)")

        var eventFields: [String: Any] = [
            "accountId": accountId,
            "invoiceId": invoiceId,
            "kind": "paymentCanceled",
            "fromStatus": InvoiceStatus.paid.rawValue,
            "toStatus": InvoiceStatus.sent.rawValue,
            "settlementTransactionIds": settlementTransactionIds,
            "source": "app",
            "createdAt": now,
        ]
        if let projectId = invoice.projectId { eventFields["projectId"] = projectId }
        if let userId { eventFields["createdBy"] = userId }
        batch.setDataAutoId(eventFields, inCollection: "accounts/\(accountId)/invoiceEvents")

        try await batch.commit()
    }

    // MARK: - Cancel (status only — members return to pool via derived query)

    func cancelInvoice(invoice: Invoice, accountId: String, userId: String?) async throws {
        guard let invoiceId = invoice.id else { return }

        let batch = makeBatch()
        let now = FieldValue.serverTimestamp()

        var invoiceFields: [String: Any] = [
            "status": InvoiceStatus.canceled.rawValue,
            "dateCanceled": now,
            "updatedAt": now,
        ]
        if let userId { invoiceFields["updatedBy"] = userId }
        batch.updateData(invoiceFields, forDocumentAt: "\(Self.invoicesPath(accountId))/\(invoiceId)")
        try await batch.commit()
    }

    // MARK: - Helpers

    static func appendReturnedPaidItemCreditInvoices(
        accountId: String,
        credits: [InvoiceLineCalculations.ReturnedPaidItemCreditContext],
        batch: any BatchWriting,
        userId: String?
    ) {
        guard !credits.isEmpty else { return }

        let grouped = Dictionary(grouping: credits, by: \.projectId)
        let now = FieldValue.serverTimestamp()

        for (projectId, projectCredits) in grouped {
            let invoiceId = UUID().uuidString
            let lines = projectCredits
                .sorted { $0.lineId < $1.lineId }
                .map { credit in
                    InvoiceLine(
                        id: credit.lineId,
                        sourceType: .manual,
                        sourceId: nil,
                        amountCents: credit.amountCents,
                        sign: .credit,
                        budgetCategoryId: credit.budgetCategoryId,
                        snapshotName: "Credit: returned \(credit.itemName)"
                    )
                }

            var fields: [String: Any] = [
                "accountId": accountId,
                "projectId": projectId,
                "status": InvoiceStatus.created.rawValue,
                "itemIds": [],
                "transactionIds": [],
                "lines": lines.map(Self.encodeLine),
                "notes": "Credit for paid item(s) returned to inventory.",
                "dateIssued": now,
                "createdAt": now,
                "updatedAt": now,
            ]
            if let userId {
                fields["createdBy"] = userId
                fields["updatedBy"] = userId
            }
            batch.setData(fields, forDocumentAt: "\(Self.invoicesPath(accountId))/\(invoiceId)", merge: false)
        }
    }

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
            case .feeInstallment, .manual:
                continue
            }
        }
        return (itemIds, txIds)
    }

    private static func ensureSystemCategory(
        for lines: [InvoiceLine],
        accountId: String,
        batch: any BatchWriting
    ) {
        guard lines.contains(where: { $0.budgetCategoryId == SystemBudgetCategory.otherClientChargesAndCreditsId }) else {
            return
        }
        batch.setData(
            SystemBudgetCategory.fields(accountId: accountId),
            forDocumentAt: "accounts/\(accountId)/presets/default/budgetCategories/\(SystemBudgetCategory.otherClientChargesAndCreditsId)",
            merge: true
        )
    }

    /// Encode an InvoiceLine as a plain `[String: Any]` for Firestore's untyped batch writer.
    static func encodeLine(_ line: InvoiceLine) -> [String: Any] {
        var dict: [String: Any] = [
            "id": line.id,
            "sourceType": line.sourceType.rawValue,
            "amountCents": line.amountCents,
            "sign": line.sign.rawValue,
        ]
        if let sourceId = line.sourceId { dict["sourceId"] = sourceId }
        if let categoryId = line.budgetCategoryId { dict["budgetCategoryId"] = categoryId }
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
