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

    /// Sums transaction amounts for selected IDs with sign-aware logic.
    /// `return` and `sale` types count as negative; all others are positive.
    static func totalCentsForSelectedTransactions(
        selectedIds: Set<String>,
        transactions: [(id: String, cents: Int, type: String?)]
    ) -> Int {
        transactions
            .filter { selectedIds.contains($0.id) }
            .reduce(0) { sum, tx in
                let isNegative = tx.type?.lowercased() == "return" || tx.type?.lowercased() == "sale"
                return sum + (isNegative ? -tx.cents : tx.cents)
            }
    }

    static func selectionLabel(count: Int, total: Int) -> String {
        "\(count) of \(total) selected"
    }
}
