import Foundation

enum SelectionCalculations {
    static func selectAllToggle(selectedIds: Set<String>, allIds: [String]) -> Set<String> {
        if isAllSelected(selectedIds: selectedIds, allIds: allIds) {
            return []
        }
        return Set(allIds)
    }

    static func isAllSelected(selectedIds: Set<String>, allIds: [String]) -> Bool {
        !allIds.isEmpty && allIds.allSatisfy { selectedIds.contains($0) }
    }

    static func selectedCount(_ selectedIds: Set<String>) -> Int {
        selectedIds.count
    }

    static func totalCentsForSelected(selectedIds: Set<String>, items: [(id: String, cents: Int)]) -> Int {
        items.filter { selectedIds.contains($0.id) }.reduce(0) { $0 + $1.cents }
    }

    /// Sums transaction amounts for selected IDs using the same direction-aware
    /// normalization as the budget tab and the denormalized project summary.
    /// Cancelled transactions contribute $0; returns subtract; canonical
    /// inventory sales add or subtract based on `inventorySaleDirection`.
    static func totalCentsForSelectedTransactions(
        selectedIds: Set<String>,
        transactions: [Transaction]
    ) -> Int {
        transactions
            .filter { tx in
                guard let id = tx.id else { return false }
                return selectedIds.contains(id)
            }
            .reduce(0) { sum, tx in
                sum + BudgetTabCalculations.normalizeTransactionAmount(tx)
            }
    }

    static func selectionLabel(count: Int, total: Int) -> String {
        "\(count) of \(total) selected"
    }
}
