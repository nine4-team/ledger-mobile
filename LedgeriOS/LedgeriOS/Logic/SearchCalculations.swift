import Foundation

/// Pure functions for universal search across items, transactions, and spaces.
/// Three matching strategies: text substring, SKU normalization, and amount prefix-range.
enum SearchCalculations {

    struct SearchResults {
        let items: [Item]
        let transactions: [Transaction]
        let spaces: [Space]
    }

    // MARK: - Main Search

    static func search(
        query: String,
        items: [Item],
        transactions: [Transaction],
        spaces: [Space],
        categories: [BudgetCategory]
    ) -> SearchResults {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return SearchResults(items: items, transactions: transactions, spaces: spaces)
        }
        return SearchResults(
            items: items.filter { itemMatches(item: $0, query: trimmed, categories: categories) },
            transactions: transactions.filter { transactionMatches(transaction: $0, query: trimmed, categories: categories) },
            spaces: spaces.filter { spaceMatches(space: $0, query: trimmed) }
        )
    }

    // MARK: - Entity Matchers

    static func itemMatches(item: Item, query: String, categories: [BudgetCategory]) -> Bool {
        if query.isEmpty { return true }

        let categoryName = categories.first(where: { $0.id == item.budgetCategoryId })?.name

        // Text fields: name, source, SKU (raw), notes, budget category name
        let textFields: [String?] = [item.name, item.source, item.sku, item.notes, categoryName]
        if textFields.contains(where: { textMatch(query: query, in: $0) }) {
            return true
        }

        // SKU normalized match
        if let sku = item.sku, !sku.isEmpty {
            let normalizedItemSKU = normalizedSKU(sku)
            let normalizedQuery = normalizedSKU(query)
            if !normalizedQuery.isEmpty && normalizedItemSKU.contains(normalizedQuery) {
                return true
            }
        }

        // Amount fields: purchasePriceCents, projectPriceCents, marketValueCents
        if let range = parseAmountQuery(query) {
            let amounts = [item.purchasePriceCents, item.projectPriceCents, item.marketValueCents].compactMap { $0 }
            if amounts.contains(where: { range.contains($0) }) {
                return true
            }
        }

        return false
    }

    static func transactionMatches(transaction: Transaction, query: String, categories: [BudgetCategory]) -> Bool {
        if query.isEmpty { return true }

        let categoryName = categories.first(where: { $0.id == transaction.budgetCategoryId })?.name
        let displayName = transactionDisplayName(for: transaction)

        // Text fields: displayName, transactionType, notes, purchasedBy, budget category name
        let textFields: [String?] = [displayName, transaction.transactionType, transaction.notes, transaction.purchasedBy, categoryName]
        if textFields.contains(where: { textMatch(query: query, in: $0) }) {
            return true
        }

        // Amount field: amountCents
        if let range = parseAmountQuery(query), let cents = transaction.amountCents {
            if range.contains(cents) {
                return true
            }
        }

        return false
    }

    static func spaceMatches(space: Space, query: String) -> Bool {
        if query.isEmpty { return true }

        // Text fields: name, notes. No amount matching.
        let textFields: [String?] = [space.name, space.notes]
        return textFields.contains(where: { textMatch(query: query, in: $0) })
    }

    // MARK: - Matching Strategies

    /// Case-insensitive substring match.
    static func textMatch(query: String, in text: String?) -> Bool {
        guard let text, !text.isEmpty else { return false }
        return text.localizedCaseInsensitiveContains(query)
    }

    /// Strips all non-alphanumeric characters and lowercases.
    static func normalizedSKU(_ sku: String) -> String {
        sku.filter { $0.isLetter || $0.isNumber }.lowercased()
    }

    /// Parses a query string into a cents range for amount prefix matching.
    ///
    /// - "40" → 4000...4099 (any amount from $40.00 to $40.99)
    /// - "40.0" → 4000...4009 (any amount from $40.00 to $40.09)
    /// - "40.00" → 4000...4000 (exact $40.00)
    /// - "$1,200" → 120000...120099
    /// - "abc" → nil
    static func parseAmountQuery(_ query: String) -> ClosedRange<Int>? {
        // Strip $ and ,
        let cleaned = query.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")

        guard !cleaned.isEmpty else { return nil }

        let parts = cleaned.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)

        guard let integerPart = Int(parts[0]) else { return nil }

        if parts.count == 1 {
            // Integer only: "40" → 4000...4099
            let low = integerPart * 100
            return low...(low + 99)
        }

        let decimalString = String(parts[1])

        // Validate decimal part is numeric
        guard !decimalString.isEmpty, decimalString.allSatisfy({ $0.isNumber }) else { return nil }

        if decimalString.count == 1 {
            // One decimal digit: "40.0" → 4000...4009
            guard let d = Int(decimalString) else { return nil }
            let low = integerPart * 100 + d * 10
            return low...(low + 9)
        }

        if decimalString.count == 2 {
            // Two decimal digits: "40.00" → 4000...4000 (exact)
            guard let decimalCents = Int(decimalString) else { return nil }
            let cents = integerPart * 100 + decimalCents
            return cents...cents
        }

        // More than 2 decimal digits — not a valid amount query
        return nil
    }

    // MARK: - Helpers

    /// Resolves the display name for a transaction.
    /// Priority: source → "Untitled Transaction".
    static func transactionDisplayName(for transaction: Transaction) -> String {
        if let source = transaction.source, !source.isEmpty {
            return source
        }
        return "Untitled Transaction"
    }
}
