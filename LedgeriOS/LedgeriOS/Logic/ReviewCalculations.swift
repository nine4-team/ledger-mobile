import Foundation

enum ReviewCalculations {
    /// Transactions that need attention: incomplete and not canceled.
    static func pendingTransactions(_ all: [Transaction]) -> [Transaction] {
        all.filter { $0.isComplete != true && $0.status != .canceled }
    }

    /// Recently completed transactions, sorted by most recently updated.
    static func doneTransactions(_ all: [Transaction], limit: Int = 50) -> [Transaction] {
        Array(
            all.filter { $0.isComplete == true }
                .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
                .prefix(limit)
        )
    }
}
