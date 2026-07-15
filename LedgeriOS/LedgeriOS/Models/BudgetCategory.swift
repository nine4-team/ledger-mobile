import FirebaseFirestore
import SwiftUI

struct BudgetCategory: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var accountId: String?
    var projectId: String?
    var name: String = ""
    var slug: String?
    var isArchived: Bool?
    /// System-owned categories support accounting invariants but are not
    /// available in normal budget/category selection flows.
    var isSystem: Bool?
    var order: Int?
    var metadata: BudgetCategoryMetadata?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, accountId, projectId, name, slug, isArchived, isSystem, order, metadata
    }
}

extension BudgetCategory {
    /// A fee category drives budget-tracker coloring and "received" vs "spent" labeling.
    var isFeeCategory: Bool { categoryKind == .feeCategory }

    /// An items category gates item entry and tax/subtotal fields on the transaction form.
    var isItemsCategory: Bool { categoryKind == .items }

    /// A project cost category stores transaction-level purchases without item rows.
    var isProjectCostCategory: Bool { categoryKind == .projectCost }

    var isSystemCategory: Bool { isSystem == true }

    var categoryKind: BudgetCategoryKind {
        BudgetCategoryKind(categoryType: resolvedCategoryType)
    }

    /// Canonical category behavior.
    var resolvedCategoryType: BudgetCategoryType {
        switch metadata?.categoryType {
        case .fee: return .fee
        case .itemized: return .itemized
        case .general, nil: return .general
        }
    }
}

enum SystemBudgetCategory {
    static let otherClientChargesAndCreditsId = "system-other-client-charges-and-credits"
    static let otherClientChargesAndCreditsName = "Other Client Charges & Credits"

    static func fields(accountId: String) -> [String: Any] {
        [
            "accountId": accountId,
            "name": otherClientChargesAndCreditsName,
            "slug": "other-client-charges-and-credits",
            "isSystem": true,
            "metadata": [
                "categoryType": BudgetCategoryType.general.rawValue,
                "excludeFromOverallBudget": true,
            ],
            "updatedAt": FieldValue.serverTimestamp(),
        ]
    }
}

// MARK: - BudgetCategoryKind

/// App-facing category behavior.
enum BudgetCategoryKind: String, Codable, Hashable {
    case items
    case projectCost
    case feeCategory
    case unknown

    init(categoryType: BudgetCategoryType) {
        switch categoryType {
        case .fee:
            self = .feeCategory
        case .itemized:
            self = .items
        case .general:
            self = .projectCost
        }
    }

    var displayLabel: String {
        switch self {
        case .items: return "Itemized"
        case .projectCost: return "General"
        case .feeCategory: return "Fee"
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
        guard let category else { return .purchase }
        if category.resolvedCategoryType == .fee { return .fee }
        if category.resolvedCategoryType == .general { return .expense }
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
