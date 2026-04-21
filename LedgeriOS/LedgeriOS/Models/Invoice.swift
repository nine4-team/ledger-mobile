import FirebaseFirestore

/// Sign of a signed invoice line. `+1` = charge (adds to total), `-1` = credit (subtracts).
/// Stored as an Int so Firestore round-trips cleanly and math stays simple.
enum InvoiceLineSign: Int, Codable {
    case charge = 1
    case credit = -1
}

/// Source of an invoice line — either an item or a non-itemized transaction.
enum InvoiceLineSourceType: String, Codable, CaseInsensitiveStringEnum {
    case item, transaction
}

/// A single signed line on an invoice. Part of the v2 bidirectional-invoice model
/// (see `docs/specs/billing-invoicing-v2.md`).
struct InvoiceLine: Codable, Hashable {
    var sourceType: InvoiceLineSourceType
    var sourceId: String
    var amountCents: Int
    var sign: InvoiceLineSign
    /// Optional display-name snapshot taken when the line was added, so historical
    /// invoices still render sensibly after the source item/transaction is renamed.
    var snapshotName: String?

    var signedAmountCents: Int { amountCents * sign.rawValue }
}

/// A project-scoped invoice that references items + non-itemized expense transactions.
/// Stored at `accounts/{accountId}/invoices/{invoiceId}` with a `projectId` field.
///
/// Lifecycle: draft → sent → paid (or → voided).
///
/// **v2 model:** `lines: [InvoiceLine]?` carries signed charge/credit entries;
/// `totalCents` is the net (charges − credits). `itemIds` / `transactionIds` are
/// maintained as a flat membership index for cheap "is this source on any invoice?"
/// queries, but the authoritative per-line amount + sign lives in `lines`.
///
/// Legacy v1 invoices have `lines == nil` and `totalCents` as a pure charge sum;
/// reader code should treat a missing `lines` as all-charge.
struct Invoice: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var accountId: String?
    var projectId: String?
    var status: InvoiceStatus?
    /// Itemized references — items billed on this invoice. Flat membership index.
    var itemIds: [String]?
    /// Non-itemized expense references — transactions billed on this invoice. Flat membership index.
    var transactionIds: [String]?
    /// Signed line entries (v2). Nil on legacy v1 invoices.
    var lines: [InvoiceLine]?
    /// Snapshot of the net total at creation time. For v2 invoices this is
    /// `sum(lines[].signedAmountCents)`; for v1 invoices it is a pure sum of charges.
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
        case id, accountId, projectId, status, itemIds, transactionIds, lines,
             totalCents, notes, invoiceNumber,
             dateIssued, dateSent, datePaid, dateVoided,
             createdBy, updatedBy
        // createdAt / updatedAt intentionally omitted — written via FieldValue.serverTimestamp(),
        // matching the convention used by Item and Transaction.
    }
}
