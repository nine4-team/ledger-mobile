import FirebaseFirestore

protocol InvoiceServiceProtocol: Sendable {
    func getInvoice(accountId: String, invoiceId: String) async throws -> Invoice?

    /// Create an invoice in the created state that references the given item and transaction ids.
    /// Created invoices are live previews — amounts are recomputed from the current item /
    /// transaction state every time the invoice is rendered. The document
    /// therefore stores the membership index (`itemIds`, `transactionIds`) plus
    /// any manual credit/charge lines; sourced amounts are finalized when paid.
    ///
    /// Does **not** cascade any status to the referenced items / transactions —
    /// v2 tracks paid-state only on the invoice.
    func createInvoice(
        accountId: String,
        projectId: String,
        itemIds: [String],
        transactionIds: [String],
        lines: [InvoiceLine]?,
        invoiceNumber: String?,
        notes: String?,
        userId: String?
    ) async throws -> String

    /// Replace the membership on a created invoice. Does not cascade and does not
    /// write `lines` / `totalCents` — created invoices are live previews (see `createInvoice`).
    /// Any stale `lines` / `totalCents` left over from a pre-v2-live-preview write
    /// are cleared so readers fall through to the live-derivation path.
    func updateSelections(
        invoice: Invoice,
        accountId: String,
        newItemIds: [String],
        newTransactionIds: [String],
        lines: [InvoiceLine]?,
        invoiceNumber: String?,
        notes: String?,
        userId: String?
    ) async throws

    /// Transition a created invoice to sent. This records source-linked lines
    /// for display/settlement grouping, but sent invoices remain live: source
    /// amounts are still rederived until the paid boundary.
    /// `itemIds` / `transactionIds` are rederived from `lines` so the membership
    /// index stays consistent with the selected sources.
    func markSent(
        invoiceId: String,
        accountId: String,
        lines: [InvoiceLine],
        totalCents: Int,
        userId: String?
    ) async throws

    /// Compatibility status-only transition. Prefer `markCollected` for new
    /// collection flows so a real settlement transaction is created.
    func markPaid(invoice: Invoice, accountId: String, userId: String?) async throws

    /// Record collection by creating categorized payment-to-business
    /// transactions for the real payment event, linking them to the invoice and
    /// settled line ids, then marking the invoice paid. The caller should pass
    /// the current source-derived lines on `invoice.lines`; those lines become
    /// the final paid snapshot.
    func markCollected(
        invoice: Invoice,
        accountId: String,
        projectId: String,
        amountCents: Int,
        source: String,
        settlementInvoiceLineIds: [String]?,
        userId: String?
    ) async throws -> [String]

    /// Correct a mistaken collected/paid marking. Generated settlement
    /// transactions stay in history but are canceled, the invoice returns to
    /// sent, and an invoice event records the correction.
    func voidInvoicePayment(
        invoice: Invoice,
        accountId: String,
        settlementTransactionIds: [String],
        userId: String?
    ) async throws

    /// Status-only transition. Updates `invoice.status = .canceled` and stamps `dateCanceled`.
    /// Does not cascade — canceled invoices' members return to the unbilled pool
    /// automatically via the derived billable-membership query.
    func cancelInvoice(invoice: Invoice, accountId: String, userId: String?) async throws

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
