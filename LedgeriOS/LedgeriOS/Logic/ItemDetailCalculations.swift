import Foundation

/// Pure functions for item detail display values and action menu generation.
/// Used by ItemDetailView and testable without SwiftUI.
enum ItemDetailCalculations {

    /// Actions that can be performed on an item from its detail screen.
    enum ItemAction: String, CaseIterable {
        case changeStatus, setSpace, clearSpace, setTransaction, clearTransaction
        case returnToInventory, sellToProject, moveToProject, reassignToProject
        case moveToReturn, makeCopies, bookmark, unbookmark, delete
    }

    /// Returns the available actions for an item based on its current state.
    /// All statuses get the full action menu — no status is terminal so users can correct mistakes.
    static func availableActions(for item: Item) -> [ItemAction] {
        var actions: [ItemAction] = [.changeStatus]

        // Space: set or clear based on current state
        if item.spaceId == nil || (item.spaceId?.isEmpty == true) {
            actions.append(.setSpace)
        } else {
            actions.append(.clearSpace)
        }

        // Transaction: set or clear
        if item.transactionId == nil || (item.transactionId?.isEmpty == true) {
            actions.append(.setTransaction)
        } else {
            actions.append(.clearTransaction)
        }

        // Move/sell operations — visibility depends on scope
        // Items in a project can be returned to inventory, sold/moved to another project,
        // or reassigned within the same project.
        // Items in inventory (no projectId) can only be sold into a project.
        let inProject = item.projectId != nil
        if inProject {
            actions.append(.returnToInventory)
            actions.append(.sellToProject)
            actions.append(.moveToProject)
            actions.append(.reassignToProject)
        } else {
            actions.append(.sellToProject)
        }
        actions.append(.moveToReturn)
        actions.append(.makeCopies)

        // Bookmark toggle
        actions.append(item.bookmark == true ? .unbookmark : .bookmark)

        // Delete is always last
        actions.append(.delete)

        return actions
    }

    /// Returns the display price for an item.
    /// Priority: projectPriceCents > purchasePriceCents > nil.
    static func displayPrice(for item: Item) -> Int? {
        item.projectPriceCents ?? item.purchasePriceCents
    }

    /// Resolves a space name from a spaceId by looking up in the provided spaces array.
    static func resolveSpaceName(spaceId: String?, spaces: [Space]) -> String? {
        guard let spaceId, !spaceId.isEmpty else { return nil }
        return spaces.first { $0.id == spaceId }?.name
    }

    /// Resolves a category name from a categoryId by looking up in the provided categories array.
    static func resolveCategoryName(categoryId: String?, categories: [BudgetCategory]) -> String? {
        guard let categoryId, !categoryId.isEmpty else { return nil }
        return categories.first { $0.id == categoryId }?.name
    }
}
