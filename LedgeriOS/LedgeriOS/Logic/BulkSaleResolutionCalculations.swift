import Foundation

/// Pure functions for bulk sale eligibility filtering and category resolution.
/// Used by bulk sell/reassign flows and testable without SwiftUI.
enum BulkSaleResolutionCalculations {

    /// Filters items eligible for bulk reassign.
    /// Items with a transactionId must be unlinked from their transaction first,
    /// so they are excluded from bulk operations.
    static func eligibleForBulkReassign(items: [Item]) -> [Item] {
        items.filter { $0.transactionId == nil || ($0.transactionId?.isEmpty == true) }
    }

    /// Resolves sale categories for a list of items.
    /// Returns a map of itemId -> categoryId (nil if the item needs user selection).
    /// Items with an existing budgetCategoryId use that; items without one return nil.
    static func resolveSaleCategories(items: [Item], categories: [BudgetCategory]) -> [String: String?] {
        var result: [String: String?] = [:]
        for item in items {
            guard let itemId = item.id else { continue }
            if let categoryId = item.budgetCategoryId, !categoryId.isEmpty {
                result[itemId] = categoryId
            } else {
                result[itemId] = nil as String?
            }
        }
        return result
    }

    /// Returns items that need the user to pick a category before a sell operation.
    /// These are items without a budgetCategoryId.
    static func itemsNeedingCategoryResolution(items: [Item]) -> [Item] {
        items.filter { $0.budgetCategoryId == nil || ($0.budgetCategoryId?.isEmpty == true) }
    }
}
