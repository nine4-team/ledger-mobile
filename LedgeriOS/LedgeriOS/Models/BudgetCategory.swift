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
    /// A fee category accepts only `.fee` transactions — the distinction that
    /// drives budget-tracker coloring and "received" vs "spent" labeling.
    var isFeeCategory: Bool { resolvedSupportedTypes == [.fee] }

    /// An items category accepts `.purchase` and `.return` — the distinction
    /// that gates tax/subtotal fields on the transaction form.
    var isItemsCategory: Bool { resolvedSupportedTypes.contains(.purchase) }

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

// MARK: - TransactionTaxonomy

/// Normalizes legacy transaction types to their intended value given the linked category.
///
/// Pre-migration, all non-itemized money-out transactions were stored as `.purchase` and the
/// linked category's `metadata.categoryType` carried the real semantic (fee / expense / itemized).
/// Post-migration, `.fee` and `.expense` are stored directly on the transaction. This resolver
/// lets read-side code handle both worlds transparently.
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
        pillLabel(for: category.resolvedSupportedTypes)
    }

    static func pillColor(for category: BudgetCategory) -> Color {
        pillColor(for: category.resolvedSupportedTypes)
    }

    static func pillLabel(for supportedTypes: [TransactionType]) -> String {
        switch shape(of: supportedTypes) {
        case .fee: return "Fee"
        case .expense: return "Expense"
        case .itemsPurchasesReturns: return "Items"
        case .mixed: return "Mixed"
        case .unknown: return "General"
        }
    }

    static func pillColor(for supportedTypes: [TransactionType]) -> Color {
        switch shape(of: supportedTypes) {
        case .fee: return StatusColors.badgeWarning
        case .expense: return BrandColors.primary
        case .itemsPurchasesReturns: return StatusColors.badgeInfo
        case .mixed: return StatusColors.badgeInfo
        case .unknown: return BrandColors.primary
        }
    }

    private enum Shape { case fee, expense, itemsPurchasesReturns, mixed, unknown }

    private static func shape(of supportedTypes: [TransactionType]) -> Shape {
        let set = Set(supportedTypes)
        if set == [.fee] { return .fee }
        if set == [.expense] { return .expense }
        if set == [.purchase, .return] { return .itemsPurchasesReturns }
        if set.contains(.purchase) && set.contains(.expense) { return .mixed }
        return .unknown
    }
}

struct BudgetCategoryMetadata: Codable, Hashable {
    var categoryType: BudgetCategoryType?
    var excludeFromOverallBudget: Bool?
}
