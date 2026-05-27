import FirebaseFirestore

protocol InvoiceServiceProtocol: Sendable {
    func getInvoice(accountId: String, invoiceId: String) async throws -> Invoice?

    /// Create a draft invoice that references the given item and transaction ids.
    /// Drafts are live previews — amounts are recomputed from the current item /
    /// transaction state every time the draft is rendered. The draft document
    /// therefore stores only the membership index (`itemIds`, `transactionIds`);
    /// `lines` and `totalCents` are materialized later, at `markSent`.
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

    /// Replace the membership on a draft invoice. Does not cascade and does not
    /// write `lines` / `totalCents` — drafts are live previews (see `createInvoice`).
    /// Any stale `lines` / `totalCents` left over from a pre-v2-live-draft write
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

    /// Transition a draft to sent. This is the canonical "snapshot at send time" —
    /// `lines` and `totalCents` are materialized from the caller-supplied signed
    /// lines and written atomically with the status transition and `dateSent`.
    /// `itemIds` / `transactionIds` are rederived from `lines` so the membership
    /// index stays consistent with the frozen snapshot.
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

    /// Record collection by creating one fee transaction for the real payment
    /// event, linking it to the invoice (and optionally selected line ids), then
    /// marking the invoice paid.
    func markCollected(
        invoice: Invoice,
        accountId: String,
        projectId: String,
        amountCents: Int,
        source: String,
        budgetCategoryId: String?,
        settlementInvoiceLineIds: [String]?,
        userId: String?
    ) async throws -> String

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
