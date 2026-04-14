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

    static func itemMatches(item: Item, query: String, categories: [BudgetCategory] = []) -> Bool {
        if query.isEmpty { return true }

        let categoryName = categories.first(where: { $0.id == item.budgetCategoryId })?.name

        // Text fields: ID, name, original + current source, SKU (raw), notes, budget category name
        let textFields: [String?] = [item.id, item.displayName, item.source, item.currentSource, item.sku, item.notes, categoryName]
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
        let amounts = [item.purchasePriceCents, item.projectPriceCents, item.marketValueCents].compactMap { $0 }
        if amounts.contains(where: { amountMatch(query: query, cents: $0) }) {
            return true
        }

        return false
    }

    static func transactionMatches(transaction: Transaction, query: String, categories: [BudgetCategory] = []) -> Bool {
        if query.isEmpty { return true }

        let categoryName = categories.first(where: { $0.id == transaction.budgetCategoryId })?.name
        let displayName = transactionDisplayName(for: transaction)

        // Text fields: ID, displayName, transactionType, notes, purchasedBy, budget category name
        let textFields: [String?] = [transaction.id, displayName, transaction.transactionType?.rawValue, transaction.notes, transaction.purchasedBy, categoryName]
        if textFields.contains(where: { textMatch(query: query, in: $0) }) {
            return true
        }

        // Amount field: amountCents
        if let cents = transaction.amountCents, amountMatch(query: query, cents: cents) {
            return true
        }

        return false
    }

    static func spaceMatches(space: Space, query: String) -> Bool {
        if query.isEmpty { return true }

        // Text fields: ID, name, notes. No amount matching.
        let textFields: [String?] = [space.id, space.name, space.notes]
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

    /// Checks if a cents value's formatted dollar amount starts with the query.
    ///
    /// Formats cents as a decimal string (e.g. 637000 → "6370.00") and checks
    /// if it has the cleaned query as a prefix. This matches left-to-right as
    /// the user types, handling all edge cases naturally:
    ///
    /// - "637" matches 637000 ($6,370.00) — "6370.00".hasPrefix("637")
    /// - "407.87" matches 40787 ($407.87) — exact
    /// - "6370." matches 637000 — trailing dot works
    /// - "29" matches 2999 ($29.99) but NOT 12999 ($129.99)
    /// - Uses abs() so negative amounts (returns) are also found
    static func amountMatch(query: String, cents: Int) -> Bool {
        let cleaned = query.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard !cleaned.isEmpty, let first = cleaned.first,
              first.isNumber || first == "." else { return false }
        let formatted = String(format: "%.2f", abs(Double(cents)) / 100.0)
        return formatted.hasPrefix(cleaned)
    }

    // MARK: - Helpers

    /// Resolves the display name for a transaction. Delegates to the
    /// canonical implementation so Search and detail views stay consistent.
    static func transactionDisplayName(for transaction: Transaction) -> String {
        TransactionDisplayCalculations.displayName(for: transaction)
    }
}
