import Foundation

/// Original display fields, independent of accounting arithmetic. Missing
/// metadata stays unknown; never substitute the import time or a generated label.
public struct InvoiceDisplayMetadata: Codable, Equatable, Sendable {
    public let invoiceNumber: String?
    public let notes: String?
    public let issuedAtMilliseconds: String?
    public let sentAtMilliseconds: String?
    public let paidAtMilliseconds: String?
    public let canceledAtMilliseconds: String?
    public let voidedAtMilliseconds: String?

    public init(invoiceNumber: String? = nil, notes: String? = nil,
                issuedAtMilliseconds: String? = nil, sentAtMilliseconds: String? = nil,
                paidAtMilliseconds: String? = nil, canceledAtMilliseconds: String? = nil,
                voidedAtMilliseconds: String? = nil) throws {
        guard [invoiceNumber, notes].compactMap({ $0 }).allSatisfy({ !$0.contains("\0") }) else { throw Failure.invalid }
        for text in [issuedAtMilliseconds, sentAtMilliseconds, paidAtMilliseconds, canceledAtMilliseconds, voidedAtMilliseconds].compactMap({ $0 }) {
            guard let value = Int64(text), String(value) == text,
                  (-62_135_596_800_000...253_402_300_799_999).contains(value) else { throw Failure.invalid }
        }
        self.invoiceNumber = invoiceNumber; self.notes = notes
        self.issuedAtMilliseconds = issuedAtMilliseconds; self.sentAtMilliseconds = sentAtMilliseconds
        self.paidAtMilliseconds = paidAtMilliseconds; self.canceledAtMilliseconds = canceledAtMilliseconds
        self.voidedAtMilliseconds = voidedAtMilliseconds
    }

    public var displayDate: Date? {
        (paidAtMilliseconds ?? sentAtMilliseconds ?? issuedAtMilliseconds).flatMap(Int64.init)
            .map { Date(timeIntervalSince1970: Double($0) / 1000) }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(invoiceNumber: c.decodeIfPresent(String.self, forKey: .invoiceNumber),
            notes: c.decodeIfPresent(String.self, forKey: .notes),
            issuedAtMilliseconds: c.decodeIfPresent(String.self, forKey: .issuedAtMilliseconds),
            sentAtMilliseconds: c.decodeIfPresent(String.self, forKey: .sentAtMilliseconds),
            paidAtMilliseconds: c.decodeIfPresent(String.self, forKey: .paidAtMilliseconds),
            canceledAtMilliseconds: c.decodeIfPresent(String.self, forKey: .canceledAtMilliseconds),
            voidedAtMilliseconds: c.decodeIfPresent(String.self, forKey: .voidedAtMilliseconds))
    }
    private enum CodingKeys: String, CodingKey {
        case invoiceNumber, notes, issuedAtMilliseconds, sentAtMilliseconds, paidAtMilliseconds, canceledAtMilliseconds, voidedAtMilliseconds
    }
    public enum Failure: Error { case invalid }
}
