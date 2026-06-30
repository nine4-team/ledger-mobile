import FirebaseFirestore
import SwiftUI

struct BudgetCategory: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var accountId: String?
    var projectId: String?
    var name: String = ""
    var slug: String?
    var isArchived: Bool?
    var order: Int?
    var metadata: BudgetCategoryMetadata?
    var supportedTypes: [TransactionType]?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, accountId, projectId, name, slug, isArchived, order, metadata, supportedTypes
    }
}

extension BudgetCategory {
    /// A fee category drives budget-tracker coloring and "received" vs "spent" labeling.
    var isFeeCategory: Bool { categoryKind == .feeCategory }

    /// An items category gates item entry and tax/subtotal fields on the transaction form.
    var isItemsCategory: Bool { categoryKind == .items }

    /// A project cost category stores transaction-level purchases without item rows.
    var isProjectCostCategory: Bool { categoryKind == .projectCost }

    var categoryKind: BudgetCategoryKind {
        BudgetCategoryKind(supportedTypes: resolvedSupportedTypes)
    }

    /// The transaction kinds this category accepts. Falls back to deriving from
    /// legacy `metadata.categoryType` when `supportedTypes` is absent (pre-migration docs).
    var resolvedSupportedTypes: [TransactionType] {
        if let explicit = supportedTypes, !explicit.isEmpty { return explicit }
        switch metadata?.categoryType {
        case .fee:      return [.fee]
        case .expense:  return [.expense]
        case .general:  return [.expense]
        case .itemized: return [.purchase, .return]
        case nil:       return [.purchase, .return]
        }
    }
}

// MARK: - BudgetCategoryKind

/// App-facing category behavior. This hides legacy storage literals like
/// `supportedTypes == [.expense]` behind names that match the product model.
enum BudgetCategoryKind: String, Codable, Hashable {
    case items
    case projectCost
    case feeCategory
    case unknown

    init(supportedTypes: [TransactionType]) {
        let set = Set(supportedTypes)
        if set == [.fee] {
            self = .feeCategory
        } else if set == [.expense] {
            self = .projectCost
        } else if set == [.purchase, .return] {
            self = .items
        } else {
            self = .unknown
        }
    }

    var displayLabel: String {
        switch self {
        case .items: return "Items"
        case .projectCost: return "Project Cost"
        case .feeCategory: return "Fee Category"
        case .unknown: return "General"
        }
    }
}

// MARK: - TransactionTaxonomy

/// Normalizes legacy transaction/category combinations for display and access checks.
///
/// New normal writes store project costs as `.purchase`; the linked category
/// carries fee/non-itemized/itemized behavior. Legacy `.fee` and `.expense`
/// transaction values may still exist in playground or historical data.
///
/// Spec: `docs/specs/transaction-type.md`
enum TransactionTaxonomy {
    static func resolve(storedType: TransactionType, category: BudgetCategory?) -> TransactionType {
        guard storedType == .purchase else { return storedType }
        let supported = category?.resolvedSupportedTypes ?? [.purchase, .return]
        if supported == [.fee] { return .fee }
        if supported == [.expense] { return .expense }
        return .purchase
    }
}

// MARK: - CategoryDisplay

/// Shared display logic for a `BudgetCategory` — the pill label + color shown
/// in settings rows, the budget tab, and anywhere else a category surfaces.
enum CategoryDisplay {
    static func pillLabel(for category: BudgetCategory) -> String {
        category.categoryKind.displayLabel
    }

    static func pillColor(for category: BudgetCategory) -> Color {
        pillColor(for: category.categoryKind)
    }

    static func pillLabel(for supportedTypes: [TransactionType]) -> String {
        BudgetCategoryKind(supportedTypes: supportedTypes).displayLabel
    }

    static func pillColor(for supportedTypes: [TransactionType]) -> Color {
        pillColor(for: BudgetCategoryKind(supportedTypes: supportedTypes))
    }

    private static func pillColor(for kind: BudgetCategoryKind) -> Color {
        switch kind {
        case .feeCategory: return StatusColors.badgeWarning
        case .projectCost: return BrandColors.primary
        case .items: return StatusColors.badgeInfo
        case .unknown: return BrandColors.primary
        }
    }
}

struct BudgetCategoryMetadata: Codable, Hashable {
    var categoryType: BudgetCategoryType?
    var excludeFromOverallBudget: Bool?
}
