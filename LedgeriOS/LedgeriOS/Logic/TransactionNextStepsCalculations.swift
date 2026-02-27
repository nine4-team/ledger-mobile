import Foundation

/// Pure functions for computing transaction "Next Steps" checklist.
/// Ported from RN `NextStepsSection.computeNextSteps()`.
enum TransactionNextStepsCalculations {

    struct NextStep: Identifiable, Equatable {
        let id: String
        let label: String
        let completed: Bool
        let sfSymbol: String
    }

    /// Computes the ordered list of next steps for a transaction.
    /// The 6th step (tax rate) only appears if the budget category type is "itemized".
    static func computeNextSteps(
        transaction: Transaction,
        itemCount: Int,
        budgetCategories: [String: BudgetCategory]
    ) -> [NextStep] {
        var steps: [NextStep] = []

        // 1. Budget category
        let hasBudgetCategory = transaction.budgetCategoryId != nil
            && budgetCategories[transaction.budgetCategoryId ?? ""] != nil
        steps.append(NextStep(
            id: "budget-category",
            label: "Categorize this transaction",
            completed: hasBudgetCategory,
            sfSymbol: "folder"
        ))

        // 2. Amount
        let hasAmount = (transaction.amountCents ?? 0) > 0
        steps.append(NextStep(
            id: "amount",
            label: "Enter the amount",
            completed: hasAmount,
            sfSymbol: "dollarsign"
        ))

        // 3. Receipt
        let hasReceipt = !(transaction.receiptImages ?? []).isEmpty
        steps.append(NextStep(
            id: "receipt",
            label: "Add a receipt",
            completed: hasReceipt,
            sfSymbol: "doc.text"
        ))

        // 4. Items
        let hasItems = itemCount > 0
        steps.append(NextStep(
            id: "items",
            label: "Add items",
            completed: hasItems,
            sfSymbol: "shippingbox"
        ))

        // 5. Purchased by
        let hasPurchasedBy = !(transaction.purchasedBy ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        steps.append(NextStep(
            id: "purchased-by",
            label: "Set purchased by",
            completed: hasPurchasedBy,
            sfSymbol: "person"
        ))

        // 6. Tax rate (only if budget category is itemized)
        if hasBudgetCategory, let catId = transaction.budgetCategoryId,
           let cat = budgetCategories[catId],
           cat.metadata?.categoryType == .itemized {
            let hasTaxRate = (transaction.taxRatePct ?? 0) > 0
            steps.append(NextStep(
                id: "tax-rate",
                label: "Set tax rate",
                completed: hasTaxRate,
                sfSymbol: "percent"
            ))
        }

        return steps
    }

    /// Returns true when every step is completed.
    static func allStepsComplete(_ steps: [NextStep]) -> Bool {
        !steps.isEmpty && steps.allSatisfy(\.completed)
    }
}
