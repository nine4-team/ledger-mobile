import Foundation

/// Pure functions to compute transaction completeness by comparing
/// linked item prices against the transaction subtotal.
/// Port of `src/utils/transactionCompleteness.ts`.
enum TransactionCompletenessCalculations {

    enum CompletenessStatus: String, Equatable {
        case over
        case complete
        case near
        case incomplete
    }

    struct CompletenessResult: Equatable {
        /// nil if no valid subtotal could be resolved
        let status: CompletenessStatus?
        let ratio: Double?
        let variancePct: Double?
        let itemsNetTotalCents: Int
        let subtotalCents: Int?
        let missingTaxData: Bool
        let inferredTaxCents: Int?
        let varianceCents: Int?
        let itemsCount: Int
        let itemsMissingPriceCount: Int
    }

    // MARK: - Subtotal Resolution

    /// Resolves the effective subtotal for completeness calculation.
    /// Priority: explicit subtotalCents → inferred from amount + taxRate → fallback amountCents.
    /// Returns (subtotalCents, missingTaxData, inferredTaxCents).
    static func resolveSubtotal(
        transaction: Transaction
    ) -> (subtotalCents: Int?, missingTaxData: Bool, inferredTaxCents: Int?) {
        // Priority 1: explicit subtotal
        if let subtotal = transaction.subtotalCents, subtotal > 0 {
            return (subtotal, false, nil)
        }

        // Priority 2: infer from amount and tax rate
        if let amount = transaction.amountCents, amount > 0,
           let taxRate = transaction.taxRatePct, taxRate > 0 {
            let subtotal = Int((Double(amount) / (1.0 + taxRate / 100.0)).rounded())
            let inferredTax = amount - subtotal
            return (subtotal, false, inferredTax)
        }

        // Priority 3: fallback to full amount (missing tax data)
        if let amount = transaction.amountCents, amount > 0 {
            return (amount, true, nil)
        }

        // No valid subtotal
        return (nil, false, nil)
    }

    // MARK: - Items Net Total

    /// Sums purchasePriceCents across all items. Nil/zero treated as 0.
    static func computeItemsNetTotal(items: [Item]) -> Int {
        items.reduce(0) { sum, item in
            sum + (item.purchasePriceCents ?? 0)
        }
    }

    // MARK: - Completeness Computation

    /// Computes transaction completeness by comparing item prices to the subtotal.
    /// Returns a result with status=nil when no valid subtotal exists.
    /// Matches the exact logic from `transactionCompleteness.ts`.
    static func computeCompleteness(
        transaction: Transaction,
        items: [Item]
    ) -> CompletenessResult {
        let (subtotal, missingTaxData, inferredTax) = resolveSubtotal(transaction: transaction)

        let itemsNetTotalCents = computeItemsNetTotal(items: items)
        let itemsCount = items.count
        let itemsMissingPriceCount = items.filter { ($0.purchasePriceCents ?? 0) == 0 }.count

        guard let subtotalCents = subtotal else {
            return CompletenessResult(
                status: nil,
                ratio: nil,
                variancePct: nil,
                itemsNetTotalCents: itemsNetTotalCents,
                subtotalCents: nil,
                missingTaxData: missingTaxData,
                inferredTaxCents: inferredTax,
                varianceCents: nil,
                itemsCount: itemsCount,
                itemsMissingPriceCount: itemsMissingPriceCount
            )
        }

        let ratio = Double(itemsNetTotalCents) / Double(subtotalCents)
        let varianceCents = itemsNetTotalCents - subtotalCents
        let variancePct = (Double(varianceCents) / Double(subtotalCents)) * 100.0

        // Status classification — check order matters (matches TS exactly)
        let status: CompletenessStatus
        if ratio > 1.2 {
            status = .over
        } else if abs(variancePct) <= 1.0 {
            status = .complete
        } else if abs(variancePct) <= 20.0 {
            status = .near
        } else {
            status = .incomplete
        }

        return CompletenessResult(
            status: status,
            ratio: ratio,
            variancePct: variancePct,
            itemsNetTotalCents: itemsNetTotalCents,
            subtotalCents: subtotalCents,
            missingTaxData: missingTaxData,
            inferredTaxCents: inferredTax,
            varianceCents: varianceCents,
            itemsCount: itemsCount,
            itemsMissingPriceCount: itemsMissingPriceCount
        )
    }
}
