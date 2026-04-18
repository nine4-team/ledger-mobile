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

    // MARK: - Pending buckets

    enum PendingBucket: Hashable {
        case unassigned
        case inventory
        case project(String)
    }

    static func bucket(for tx: Transaction) -> PendingBucket {
        if let pid = tx.projectId, !pid.isEmpty {
            return .project(pid)
        }
        return (tx.itemIds?.isEmpty ?? true) ? .unassigned : .inventory
    }

    static func filter(_ txs: [Transaction], bucket target: PendingBucket) -> [Transaction] {
        txs.filter { bucket(for: $0) == target }
    }

    static func counts(_ txs: [Transaction]) -> [PendingBucket: Int] {
        var result: [PendingBucket: Int] = [:]
        for tx in txs {
            result[bucket(for: tx), default: 0] += 1
        }
        return result
    }

    static func assignmentLabel(for tx: Transaction, projects: [Project]) -> String {
        switch bucket(for: tx) {
        case .unassigned: return "Unassigned"
        case .inventory: return "Inventory"
        case .project(let id):
            return projects.first(where: { $0.id == id })?.name ?? "Project"
        }
    }
}
