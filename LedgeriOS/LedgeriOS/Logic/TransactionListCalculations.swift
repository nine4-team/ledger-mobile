import Foundation

/// Pure functions for filtering, sorting, and searching transaction lists.
enum TransactionListCalculations {

    // MARK: - Sort

    enum TransactionSort: String, CaseIterable {
        case dateDesc, dateAsc
        case createdDesc, createdAsc
        case sourceDesc, sourceAsc
        case amountDesc, amountAsc
    }

    // MARK: - Filter

    struct TransactionFilter: Equatable {
        var statusValues: Set<String> = []          // "pending", "completed", "canceled", "inventory-only"
        var reimbursementValues: Set<String> = []    // "owed-to-company", "owed-to-client"
        var hasReceipt: Bool? = nil
        var typeValues: Set<String> = []             // "purchase", "return", "sale", "to-inventory"
        var completenessValues: Set<String> = []     // "needs-review", "complete"
        var budgetCategoryId: String? = nil
        var purchasedByValues: Set<String> = []      // "client-card", "design-business", "missing"
        var sourceValues: Set<String> = []           // dynamic from unique sources

        var isActive: Bool {
            !statusValues.isEmpty || !reimbursementValues.isEmpty ||
            hasReceipt != nil || !typeValues.isEmpty ||
            !completenessValues.isEmpty || budgetCategoryId != nil ||
            !purchasedByValues.isEmpty || !sourceValues.isEmpty
        }
    }

    // MARK: - Combined Pipeline

    /// Applies filter, search query, and sort to a list of transactions.
    static func filterAndSort(
        transactions: [Transaction],
        filter: TransactionFilter,
        sort: TransactionSort,
        query: String,
        items: [String: [Item]] = [:],
        categories: [BudgetCategory] = []
    ) -> [Transaction] {
        var result = transactions

        // Apply filters
        result = applyFilters(result, filter: filter, items: items)

        // Apply text search
        result = applySearch(result, query: query)

        // Apply sort
        result = applySort(result, sort: sort)

        return result
    }

    // MARK: - Filtering

    static func applyFilters(
        _ transactions: [Transaction],
        filter: TransactionFilter,
        items: [String: [Item]] = [:]
    ) -> [Transaction] {
        guard filter.isActive else { return transactions }

        return transactions.filter { txn in
            // Status filter
            if !filter.statusValues.isEmpty {
                let status = txn.status?.lowercased() ?? ""
                if !filter.statusValues.contains(status) { return false }
            }

            // Reimbursement filter
            if !filter.reimbursementValues.isEmpty {
                let reimburse = txn.reimbursementType?.lowercased() ?? ""
                if !filter.reimbursementValues.contains(reimburse) { return false }
            }

            // Has receipt filter
            if let wantsReceipt = filter.hasReceipt {
                let hasReceipt = (txn.receiptImages?.isEmpty == false) || txn.hasEmailReceipt == true
                if hasReceipt != wantsReceipt { return false }
            }

            // Type filter
            if !filter.typeValues.isEmpty {
                let type = txn.transactionType?.lowercased() ?? ""
                if !filter.typeValues.contains(type) { return false }
            }

            // Completeness filter
            if !filter.completenessValues.isEmpty {
                let txnItems = items[txn.id ?? ""] ?? []
                let completeness = TransactionCompletenessCalculations.computeCompleteness(
                    transaction: txn, items: txnItems
                )
                if filter.completenessValues.contains("needs-review") {
                    if completeness == nil || completeness?.status == .complete { return false }
                }
                if filter.completenessValues.contains("complete") {
                    if completeness?.status != .complete { return false }
                }
            }

            // Budget category filter
            if let catId = filter.budgetCategoryId {
                if txn.budgetCategoryId != catId { return false }
            }

            // Purchased by filter
            if !filter.purchasedByValues.isEmpty {
                let purchasedBy = txn.purchasedBy?.lowercased() ?? "missing"
                if !filter.purchasedByValues.contains(purchasedBy) { return false }
            }

            // Source filter
            if !filter.sourceValues.isEmpty {
                let source = txn.source?.lowercased() ?? ""
                if !filter.sourceValues.contains(source) { return false }
            }

            return true
        }
    }

    // MARK: - Search

    /// Searches transactions by query across source, notes, type label, and formatted amount.
    static func applySearch(_ transactions: [Transaction], query: String) -> [Transaction] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return transactions }
        let needle = trimmed.lowercased()

        return transactions.filter { txn in
            let typeLabel = TransactionDisplayCalculations.canonicalTypeLabel(for: txn.transactionType) ?? ""
            let amount = txn.amountCents.map { CurrencyFormatting.formatCentsWithDecimals($0) } ?? ""
            let haystack = [
                txn.source ?? "",
                txn.notes ?? "",
                typeLabel,
                amount,
            ].joined(separator: " ").lowercased()
            return haystack.contains(needle)
        }
    }

    // MARK: - Sorting

    static func applySort(_ transactions: [Transaction], sort: TransactionSort) -> [Transaction] {
        transactions.sorted(by: sortComparator(for: sort))
    }

    private static func sortComparator(for sort: TransactionSort) -> (Transaction, Transaction) -> Bool {
        switch sort {
        case .dateDesc:
            return { a, b in
                guard let dateA = a.transactionDate, !dateA.isEmpty else { return false }
                guard let dateB = b.transactionDate, !dateB.isEmpty else { return true }
                return dateA > dateB
            }
        case .dateAsc:
            return { a, b in
                guard let dateA = a.transactionDate, !dateA.isEmpty else { return false }
                guard let dateB = b.transactionDate, !dateB.isEmpty else { return true }
                return dateA < dateB
            }
        case .createdDesc:
            return { a, b in
                let dA = a.createdAt ?? .distantPast
                let dB = b.createdAt ?? .distantPast
                return dA > dB
            }
        case .createdAsc:
            return { a, b in
                let dA = a.createdAt ?? .distantPast
                let dB = b.createdAt ?? .distantPast
                return dA < dB
            }
        case .sourceDesc:
            return { a, b in
                let sA = (a.source ?? "").lowercased()
                let sB = (b.source ?? "").lowercased()
                if sA.isEmpty && !sB.isEmpty { return false }
                if !sA.isEmpty && sB.isEmpty { return true }
                return sA.localizedCompare(sB) == .orderedDescending
            }
        case .sourceAsc:
            return { a, b in
                let sA = (a.source ?? "").lowercased()
                let sB = (b.source ?? "").lowercased()
                if sA.isEmpty && !sB.isEmpty { return false }
                if !sA.isEmpty && sB.isEmpty { return true }
                return sA.localizedCompare(sB) == .orderedAscending
            }
        case .amountDesc:
            return { a, b in
                let aAmt = a.amountCents ?? 0
                let bAmt = b.amountCents ?? 0
                return aAmt > bAmt
            }
        case .amountAsc:
            return { a, b in
                let aAmt = a.amountCents ?? 0
                let bAmt = b.amountCents ?? 0
                return aAmt < bAmt
            }
        }
    }

    // MARK: - Unique Sources

    /// Extracts unique non-empty sources from transactions, sorted alphabetically.
    static func uniqueSources(from transactions: [Transaction]) -> [String] {
        let sources = Set(transactions.compactMap { txn -> String? in
            guard let source = txn.source, !source.trimmingCharacters(in: .whitespaces).isEmpty else {
                return nil
            }
            return source
        })
        return sources.sorted { $0.localizedCompare($1) == .orderedAscending }
    }
}
