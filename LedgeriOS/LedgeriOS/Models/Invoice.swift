import FirebaseFirestore

/// A project-scoped invoice that references items + non-itemized expense transactions.
/// Stored at `accounts/{accountId}/invoices/{invoiceId}` with a `projectId` field
/// (matches the existing top-level pattern used by `items` and `transactions`).
///
/// Lifecycle: draft → sent → paid (or → voided). Marking paid cascades
/// `billingStatus = .paid` to every referenced item and transaction in one batch.
struct Invoice: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var accountId: String?
    var projectId: String?
    var status: InvoiceStatus?
    /// Itemized references — items billed on this invoice.
    var itemIds: [String]?
    /// Non-itemized expense references — transactions (install, fuel, etc.) billed on this invoice.
    var transactionIds: [String]?
    /// Snapshot of the total at creation time. Source of truth for the bill amount
    /// even if referenced item prices change later.
    var totalCents: Int?
    var notes: String?
    /// Optional human-readable label, e.g. "INV-001".
    var invoiceNumber: String?
    var dateIssued: Date?
    var dateSent: Date?
    var datePaid: Date?
    var dateVoided: Date?
    var createdBy: String?
    var updatedBy: String?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, accountId, projectId, status, itemIds, transactionIds,
             totalCents, notes, invoiceNumber,
             dateIssued, dateSent, datePaid, dateVoided,
             createdBy, updatedBy
        // createdAt / updatedAt intentionally omitted — written via FieldValue.serverTimestamp(),
        // matching the convention used by Item and Transaction.
    }
}
