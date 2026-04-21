import Foundation

// MARK: - Case-Insensitive Decoding

/// Enums conforming to this protocol decode case-insensitively by lowercasing
/// the raw value before matching. Handles legacy data that stores "Purchase"
/// where the enum expects "purchase".
protocol CaseInsensitiveStringEnum: RawRepresentable, Decodable where RawValue == String {
    /// Optional aliases for legacy values that don't match any case after lowercasing.
    /// e.g. ["standard": "general", "complete": "completed"]
    static var legacyAliases: [String: String] { get }
}

extension CaseInsensitiveStringEnum {
    static var legacyAliases: [String: String] { [:] }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        let normalized = Self.legacyAliases[raw.lowercased()] ?? raw.lowercased()
        guard let value = Self(rawValue: normalized) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Cannot initialize \(Self.self) from '\(raw)'"
            ))
        }
        self = value
    }
}

// MARK: - Enums

enum BudgetCategoryType: String, Codable, CaseInsensitiveStringEnum {
    case general, itemized, fee, expense
    static let legacyAliases = ["standard": "general"]
}

enum MemberRole: String, Codable {
    case owner, admin, user
}

enum InventorySaleDirection: String, Codable {
    case businessToProject = "business_to_project"
    case projectToBusiness = "project_to_business"
}

enum ItemStatus: String, Codable, CaseIterable, CaseInsensitiveStringEnum {
    case toPurchase = "to purchase"
    case purchased
    case toReturn = "to return"
    case returned
    case sold
    var displayLabel: String { rawValue.capitalized }
}

/// The kind of a transaction. Five values covering both money-out (fee/expense/purchase)
/// and money-in-or-item-movement (sale/return) flows.
///
/// - `purchase` means **itemized purchase only** — items that flow through the inventory/item
///   model. Pre-migration, legacy `purchase` documents may semantically be a fee or expense;
///   use `TransactionTaxonomy.resolve(...)` at read time to normalize.
/// - `fee` and `expense` were added in the taxonomy migration. See
///   `docs/specs/transaction-type.md`.
enum TransactionType: String, Codable, CaseIterable, CaseInsensitiveStringEnum {
    case purchase, sale, fee, expense
    case `return` = "return"
    var displayLabel: String { rawValue.capitalized }
}

/// Transaction lifecycle state. Only `.canceled` is a real value; nil means
/// an active transaction. "Needs Review" is driven by `Transaction.isComplete`,
/// not this field.
enum TransactionStatus: String, Codable, CaseIterable, CaseInsensitiveStringEnum {
    case canceled
    var displayLabel: String { rawValue.capitalized }
    static let legacyAliases = ["cancelled": "canceled"]
}

enum InvoiceStatus: String, Codable, CaseIterable, CaseInsensitiveStringEnum {
    case draft, sent, paid, voided
    var displayLabel: String { rawValue.capitalized }
}
