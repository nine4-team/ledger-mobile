import FirebaseFirestore

protocol InvoiceServiceProtocol: Sendable {
    func getInvoice(accountId: String, invoiceId: String) async throws -> Invoice?

    /// Create a draft invoice referencing items + transactions.
    /// Cascades referenced items + transactions to billingStatus = .invoiced in one batch.
    /// Returns the new invoice document ID.
    func createInvoice(
        accountId: String,
        projectId: String,
        itemIds: [String],
        transactionIds: [String],
        totalCents: Int,
        invoiceNumber: String?,
        notes: String?,
        userId: String?
    ) async throws -> String

    /// Status-only transition (no cascade). Updates invoice.status = .sent and stamps dateSent.
    func markSent(invoiceId: String, accountId: String, userId: String?) async throws

    /// Cascade billingStatus = .paid to all referenced items + transactions in one batch.
    /// Sets invoice.status = .paid and stamps datePaid.
    func markPaid(invoice: Invoice, accountId: String, userId: String?) async throws

    /// Reverts referenced items + transactions from .invoiced → .unbilled
    /// (skipping any already at .paid — paid is terminal).
    /// Sets invoice.status = .voided and stamps dateVoided.
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
