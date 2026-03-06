import Foundation

/// Pure functions for computing transaction item completeness.
/// Ported from RN `transactionCompleteness.ts`.
enum TransactionCompletenessCalculations {

    enum CompletenessStatus: String {
        case complete, near, incomplete, over
    }

    struct TransactionCompleteness {
        let itemsNetTotalCents: Int
        let itemsCount: Int
        let itemsMissingPriceCount: Int
        let transactionSubtotalCents: Int
        let completenessRatio: Double
        let status: CompletenessStatus
        let missingTaxData: Bool
        /// Tax computed from taxRatePct when only amountCents is available (no explicit subtotal).
        let inferredTax: Int?
        /// Explicit tax: amountCents - subtotalCents when both fields are set in Firestore.
        let taxAmount: Int?
        let varianceCents: Int
        let variancePercent: Double
        let returnedItemsCount: Int
        let returnedItemsTotalCents: Int
        let soldItemsCount: Int
        let soldItemsTotalCents: Int
    }

    /// Compute transaction completeness by comparing linked item prices
    /// against the transaction subtotal.
    /// Returns nil when the resolved subtotal is zero or invalid (N/A state).
    static func computeCompleteness(
        transaction: Transaction,
        items: [Item],
        returnedItems: [Item] = [],
        soldItems: [Item] = []
    ) -> TransactionCompleteness? {
        // Resolve subtotal: explicit > inferred from tax > fallback to amount
        var transactionSubtotalCents: Int
        var missingTaxData = false
        var inferredTax: Int?
        var taxAmount: Int?  // M7: explicit tax when both amountCents and subtotalCents are set

        if let subtotal = transaction.subtotalCents, subtotal > 0 {
            transactionSubtotalCents = subtotal
            // Compute explicit tax if we also have amountCents (amountCents = subtotal + tax)
            if let amount = transaction.amountCents, amount > subtotal {
                taxAmount = amount - subtotal
            }
        } else if let amount = transaction.amountCents, amount > 0,
                  let taxRate = transaction.taxRatePct {
            transactionSubtotalCents = Int((Double(amount) / (1.0 + taxRate / 100.0)).rounded())
            inferredTax = amount - transactionSubtotalCents
        } else if let amount = transaction.amountCents, amount > 0 {
            transactionSubtotalCents = amount
            missingTaxData = true
        } else {
            return nil
        }

        let allItems = items + returnedItems + soldItems
        let itemsNetTotalCents = allItems.reduce(0) { $0 + ($1.purchasePriceCents ?? 0) }
        let itemsCount = allItems.count
        let itemsMissingPriceCount = allItems.filter { ($0.purchasePriceCents ?? 0) == 0 }.count

        let returnedItemsCount = returnedItems.count
        let returnedItemsTotalCents = returnedItems.reduce(0) { $0 + ($1.purchasePriceCents ?? 0) }
        let soldItemsCount = soldItems.count
        let soldItemsTotalCents = soldItems.reduce(0) { $0 + ($1.purchasePriceCents ?? 0) }

        let completenessRatio = Double(itemsNetTotalCents) / Double(transactionSubtotalCents)
        let varianceCents = itemsNetTotalCents - transactionSubtotalCents
        let variancePercent = (Double(varianceCents) / Double(transactionSubtotalCents)) * 100.0

        let status: CompletenessStatus
        if completenessRatio > 1.2 {
            status = .over
        } else if abs(variancePercent) <= 1.0 {
            status = .complete
        } else if abs(variancePercent) <= 20.0 {
            status = .near
        } else {
            status = .incomplete
        }

        return TransactionCompleteness(
            itemsNetTotalCents: itemsNetTotalCents,
            itemsCount: itemsCount,
            itemsMissingPriceCount: itemsMissingPriceCount,
            transactionSubtotalCents: transactionSubtotalCents,
            completenessRatio: completenessRatio,
            status: status,
            missingTaxData: missingTaxData,
            inferredTax: inferredTax,
            taxAmount: taxAmount,
            varianceCents: varianceCents,
            variancePercent: variancePercent,
            returnedItemsCount: returnedItemsCount,
            returnedItemsTotalCents: returnedItemsTotalCents,
            soldItemsCount: soldItemsCount,
            soldItemsTotalCents: soldItemsTotalCents
        )
    }

    /// Subtotal label depending on whether an explicit subtotal exists.
    static func subtotalLabel(hasExplicitSubtotal: Bool) -> String {
        hasExplicitSubtotal ? "Subtotal (pre-tax)" : "Estimated subtotal (pre-tax)"
    }

    /// Remaining/over label for progress bar annotation.
    static func remainingLabel(varianceCents: Int) -> String {
        if varianceCents <= 0 {
            return "\(CurrencyFormatting.formatCentsWithDecimals(-varianceCents)) remaining"
        } else {
            return "Over by \(CurrencyFormatting.formatCentsWithDecimals(varianceCents))"
        }
    }
}
