import FirebaseFirestore

/// Sign of a signed invoice line. `+1` = charge (adds to total), `-1` = credit (subtracts).
/// Stored as an Int so Firestore round-trips cleanly and math stays simple.
enum InvoiceLineSign: Int, Codable {
    case charge = 1
    case credit = -1
}

/// Source of an invoice line.
enum InvoiceLineSourceType: String, Codable, CaseInsensitiveStringEnum {
    case item, transaction, manual
}

/// A single signed line on an invoice.
struct InvoiceLine: Codable, Hashable {
    /// Stable line identifier used for line-level settlement. Legacy lines that
    /// predate this field decode with a generated id until the backfill writes a
    /// deterministic one.
    var id: String
    var sourceType: InvoiceLineSourceType
    /// Item or transaction id for sourced lines. Nil for manual New Charge lines.
    var sourceId: String?
    var amountCents: Int
    var sign: InvoiceLineSign
    /// Optional display-name snapshot taken when the line was added, so historical
    /// invoices still render sensibly after the source item/transaction is renamed.
    var snapshotName: String?
    /// Convenience reverse lookup for line-level settlement transactions. The
    /// source of truth lives on Transaction.settlementInvoiceLineIds.
    var settlementTransactionIds: [String]?

    var signedAmountCents: Int { amountCents * sign.rawValue }

    init(
        id: String = UUID().uuidString,
        sourceType: InvoiceLineSourceType,
        sourceId: String? = nil,
        amountCents: Int,
        sign: InvoiceLineSign,
        snapshotName: String? = nil,
        settlementTransactionIds: [String]? = nil
    ) {
        self.id = id
        self.sourceType = sourceType
        self.sourceId = sourceId
        self.amountCents = amountCents
        self.sign = sign
        self.snapshotName = snapshotName
        self.settlementTransactionIds = settlementTransactionIds
    }

    enum CodingKeys: String, CodingKey {
        case id, sourceType, sourceId, amountCents, sign, snapshotName, settlementTransactionIds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        sourceType = try container.decode(InvoiceLineSourceType.self, forKey: .sourceType)
        sourceId = try container.decodeIfPresent(String.self, forKey: .sourceId)
        amountCents = try container.decode(Int.self, forKey: .amountCents)
        sign = try container.decode(InvoiceLineSign.self, forKey: .sign)
        snapshotName = try container.decodeIfPresent(String.self, forKey: .snapshotName)
        settlementTransactionIds = try container.decodeIfPresent([String].self, forKey: .settlementTransactionIds)
    }
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
    var containsCompanyRevenue: Bool?
    var feeCategoryIds: [String]?
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
             totalCents, containsCompanyRevenue, feeCategoryIds, notes, invoiceNumber,
             dateIssued, dateSent, datePaid, dateVoided,
             createdBy, updatedBy
        // createdAt / updatedAt intentionally omitted — written via FieldValue.serverTimestamp(),
        // matching the convention used by Item and Transaction.
    }
}
