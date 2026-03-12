import Foundation

// MARK: - Types

enum PickerTab: String, CaseIterable, Hashable {
    case suggested
    case project
    case outside
    // Inventory-scope (deferred — future PR)
    // case inventory, projects
}

struct ItemConflict {
    let item: Item
    let sourceTransactionId: String
}

struct ScopeRoutingResult {
    /// Items already in the destination project (or both in inventory) → reassign
    let sameScope: [Item]
    /// Items from a different project or inventory ↔ project → sell
    let crossScope: [Item]
}

// MARK: - Tab Logic

enum AddExistingItemsCalculations {

    /// Returns the visible tabs for a transaction-context picker.
    static func availableTabs(
        transaction: Transaction,
        projectItems: [Item]
    ) -> [PickerTab] {
        var tabs: [PickerTab] = []

        // Suggested: only if transaction has a source AND there's at least one matching item
        if let source = transaction.source, !source.isEmpty {
            let alreadyLinked = Set(transaction.itemIds ?? [])
            let hasMatch = projectItems.contains { item in
                guard let id = item.id, !alreadyLinked.contains(id) else { return false }
                return item.source == source
            }
            if hasMatch {
                tabs.append(.suggested)
            }
        }

        // Project tab: always shown for project-scoped transactions
        if transaction.projectId != nil {
            tabs.append(.project)
        }

        // Outside: always shown
        tabs.append(.outside)

        return tabs
    }

    /// Returns the visible tabs for a space-context picker.
    static func spaceAvailableTabs() -> [PickerTab] {
        [.project, .outside]
    }

    // MARK: - Items for Tab

    /// Filters items for the given tab in a transaction-context picker.
    static func itemsForTab(
        _ tab: PickerTab,
        transaction: Transaction,
        projectItems: [Item],
        allItems: [Item]
    ) -> [Item] {
        let alreadyLinked = Set(transaction.itemIds ?? [])

        switch tab {
        case .suggested:
            guard let source = transaction.source else { return [] }
            return projectItems.filter { item in
                guard let id = item.id, !alreadyLinked.contains(id) else { return false }
                return item.source == source
            }
        case .project:
            return projectItems.filter { item in
                guard let id = item.id else { return false }
                return !alreadyLinked.contains(id)
            }
        case .outside:
            let projectId = transaction.projectId
            return allItems.filter { item in
                guard let id = item.id, !alreadyLinked.contains(id) else { return false }
                return item.projectId != projectId
            }
        }
    }

    /// Filters items for the given tab in a space-context picker.
    static func itemsForSpaceTab(
        _ tab: PickerTab,
        space: Space,
        projectId: String?,
        projectItems: [Item],
        allItems: [Item]
    ) -> [Item] {
        let alreadyLinked = Set(projectItems.filter { $0.spaceId == space.id }.compactMap(\.id))

        switch tab {
        case .project:
            return projectItems.filter { item in
                guard let id = item.id else { return false }
                return !alreadyLinked.contains(id)
            }
        case .outside:
            return allItems.filter { item in
                guard item.id != nil else { return false }
                return item.projectId != projectId
            }
        case .suggested:
            return []
        }
    }

    // MARK: - Conflict Detection

    /// Detects items that are currently linked to a different transaction.
    static func detectConflicts(
        selectedItems: [Item],
        destinationTransactionId: String
    ) -> [ItemConflict] {
        selectedItems.compactMap { item in
            guard let txId = item.transactionId,
                  txId != destinationTransactionId else { return nil }
            return ItemConflict(item: item, sourceTransactionId: txId)
        }
    }

    /// Builds a user-facing summary of conflicts.
    /// Returns nil if no conflicts.
    static func conflictSummary(
        conflicts: [ItemConflict],
        allTransactions: [Transaction]
    ) -> (message: String, itemNames: [String])? {
        guard !conflicts.isEmpty else { return nil }

        let txLookup = Dictionary(
            allTransactions.compactMap { tx in tx.id.map { ($0, tx) } },
            uniquingKeysWith: { first, _ in first }
        )

        // Group by source transaction
        var groups: [String: [ItemConflict]] = [:]
        for conflict in conflicts {
            groups[conflict.sourceTransactionId, default: []].append(conflict)
        }

        let itemNames = conflicts.prefix(4).map { $0.item.displayName.isEmpty ? "Unnamed item" : $0.item.displayName }
        var names = itemNames
        if conflicts.count > 4 {
            names.append("+ \(conflicts.count - 4) more")
        }

        let message: String
        if groups.count == 1, let (txId, _) = groups.first {
            let txName = txLookup[txId]?.source ?? "another transaction"
            message = "These items are currently in \(txName). Reassign them?"
        } else {
            message = "\(conflicts.count) items from \(groups.count) transactions will be reassigned."
        }

        return (message, names)
    }

    // MARK: - Scope Routing

    /// Splits items into same-scope (reassign) and cross-scope (sell) groups
    /// relative to the destination project.
    static func routeByScope(
        items: [Item],
        destinationProjectId: String?
    ) -> ScopeRoutingResult {
        var sameScope: [Item] = []
        var crossScope: [Item] = []

        for item in items {
            if item.projectId == destinationProjectId {
                sameScope.append(item)
            } else {
                crossScope.append(item)
            }
        }

        return ScopeRoutingResult(sameScope: sameScope, crossScope: crossScope)
    }
}
