import FirebaseFirestore

protocol InvoiceServiceProtocol: Sendable {
    func getInvoice(accountId: String, invoiceId: String) async throws -> Invoice?

    /// Create a draft invoice from pre-built signed lines (v2 model).
    /// The service derives the flat `itemIds` / `transactionIds` membership index
    /// from `lines` and writes the net `totalCents`. Returns the new invoice ID.
    ///
    /// Does **not** cascade any status to the referenced items / transactions —
    /// v2 tracks paid-state only on the invoice.
    func createInvoice(
        accountId: String,
        projectId: String,
        lines: [InvoiceLine],
        totalCents: Int,
        invoiceNumber: String?,
        notes: String?,
        userId: String?
    ) async throws -> String

    /// Replace the lines on a draft invoice. Derives the new membership index
    /// from `newLines`. Does not cascade.
    func updateSelections(
        invoice: Invoice,
        accountId: String,
        newLines: [InvoiceLine],
        newTotalCents: Int,
        invoiceNumber: String?,
        notes: String?,
        userId: String?
    ) async throws

    /// Status-only transition. Updates `invoice.status = .sent` and stamps `dateSent`.
    func markSent(invoiceId: String, accountId: String, userId: String?) async throws

    /// Status-only transition. Updates `invoice.status = .paid` and stamps `datePaid`.
    /// Does not cascade — v2 tracks paid-state only on the invoice.
    func markPaid(invoice: Invoice, accountId: String, userId: String?) async throws

    /// Status-only transition. Updates `invoice.status = .voided` and stamps `dateVoided`.
    /// Does not cascade — voided invoices' members return to the unbilled pool
    /// automatically via the derived billable-membership query.
    func voidInvoice(invoice: Invoice, accountId: String, userId: String?) async throws

    func subscribeToInvoices(
        accountId: String,
        onChange: @escaping ([Invoice]) -> Void
    ) -> ListenerRegistration

    func subscribeToInvoice(
        accountId: String,
        invoiceId: String,
        onChange: @escaping (Invoice?) -> Void
    ) -> ListenerRegistration
}
