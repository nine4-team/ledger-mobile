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
    case general, itemized, fee
}

enum MemberRole: String, Codable {
    case owner, admin, user

    var displayLabel: String {
        switch self {
        case .owner: return "Owner"
        case .admin: return "Admin"
        case .user: return "Employee"
        }
    }
}

enum CompanyFinancialAccess: String, Codable, CaseIterable, CaseInsensitiveStringEnum {
    case full, limited, none

    var displayLabel: String {
        switch self {
        case .full: return "Full access"
        case .limited: return "Limited access"
        case .none: return "No access"
        }
    }
}

enum InventorySaleDirection: String, Codable {
    case businessToProject = "business_to_project"
    case projectToBusiness = "project_to_business"
}

/// Why the design business paid for a purchase. This is intentionally
/// independent from `purchasedBy`: payer identity does not determine whether
/// the purchase belongs in inventory or directly in a project.
enum PurchaseHandling: String, Codable, CaseIterable, CaseInsensitiveStringEnum {
    case inventoryResale = "inventory_resale"
    case projectReimbursement = "project_reimbursement"
}

enum ItemStatus: String, Codable, CaseIterable, CaseInsensitiveStringEnum {
    case toPurchase = "to purchase"
    case purchased
    case toReturn = "to return"
    case returned
    case sold
    var displayLabel: String { rawValue.capitalized }
}

/// The kind of transaction event stored on a Transaction.
///
/// - `purchase` means money spent to buy goods or services. Itemized/inventory behavior
///   is determined by the linked budget category, not by this enum case alone.
/// - `paymentToBusiness` means money actually received from the client by the
///   design business, usually through invoice collection.
/// - `fee` and `expense` are legacy read-compatible values only. New normal write
///   paths should not create them.
enum TransactionType: String, Codable, CaseIterable, CaseInsensitiveStringEnum {
    case purchase, sale, fee, expense
    case paymentToBusiness
    case `return` = "return"

    static let legacyAliases = [
        "to inventory": "return",
        "paymenttobusiness": "paymentToBusiness",
        "payment_to_business": "paymentToBusiness",
        "payment-to-business": "paymentToBusiness",
    ]

    static var normalEntryCases: [TransactionType] { [.purchase, .return] }
    static var canonicalEventCases: [TransactionType] { [.purchase, .return, .sale, .paymentToBusiness] }
    static var legacyReadCases: [TransactionType] { [.fee, .expense] }

    var isLegacyReadType: Bool {
        self == .fee || self == .expense
    }

    var isLegacyWriteType: Bool { isLegacyReadType }

    var displayLabel: String {
        switch self {
        case .paymentToBusiness: return "Client Payment"
        default: return rawValue.capitalized
        }
    }
}

/// Transaction lifecycle state. Only `.canceled` is a real value; nil means
/// an active transaction. "Needs Review" is driven by `Transaction.isComplete`,
/// not this field.
enum TransactionStatus: String, Codable, CaseIterable, CaseInsensitiveStringEnum {
    case canceled
    var displayLabel: String { rawValue.capitalized }
    static let legacyAliases = ["cancelled": "canceled"]
}

extension KeyedDecodingContainer {
    /// Legacy Firestore docs may carry `status: "pending"` or `status: "completed"` —
    /// values that no longer exist on `TransactionStatus`. Treat any unknown string
    /// as nil (active) instead of letting the whole `Transaction` fail to decode.
    func decodeIfPresent(_ type: TransactionStatus.Type, forKey key: Key) throws -> TransactionStatus? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        let raw = try decode(String.self, forKey: key)
        let normalized = TransactionStatus.legacyAliases[raw.lowercased()] ?? raw.lowercased()
        return TransactionStatus(rawValue: normalized)
    }
}

enum InvoiceStatus: String, Codable, CaseIterable, CaseInsensitiveStringEnum {
    case created, sent, paid, canceled

    static let legacyAliases = [
        "draft": "created",
        "voided": "canceled",
        "void": "canceled",
        "cancelled": "canceled",
    ]

    var displayLabel: String { rawValue.capitalized }
}
