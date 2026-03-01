import Foundation

/// Pure functions to compute the "Next Steps" checklist shown on TransactionDetailView.
enum TransactionNextStepsCalculations {

    struct NextStep: Equatable, Identifiable {
        let id: String
        let title: String
        let isComplete: Bool
    }

    /// Computes the next steps checklist for a transaction.
    /// Step 6 (tax rate) only appears when the budget category type is "itemized".
    static func computeNextSteps(
        transaction: Transaction,
        category: BudgetCategory?,
        items: [Item]
    ) -> [NextStep] {
        var steps: [NextStep] = []

        // Step 1: Add a budget category
        steps.append(NextStep(
            id: "budget-category",
            title: "Add a budget category",
            isComplete: transaction.budgetCategoryId != nil
        ))

        // Step 2: Enter the amount
        steps.append(NextStep(
            id: "amount",
            title: "Enter the amount",
            isComplete: transaction.amountCents != nil && transaction.amountCents != 0
        ))

        // Step 3: Add a receipt
        steps.append(NextStep(
            id: "receipt",
            title: "Add a receipt",
            isComplete: (transaction.receiptImages?.isEmpty == false) || transaction.hasEmailReceipt == true
        ))

        // Step 4: Add items
        steps.append(NextStep(
            id: "items",
            title: "Add items",
            isComplete: !items.isEmpty
        ))

        // Step 5: Set who purchased this
        steps.append(NextStep(
            id: "purchased-by",
            title: "Set who purchased this",
            isComplete: transaction.purchasedBy != nil
        ))

        // Step 6 (conditional): Set the tax rate — only for itemized categories
        let isItemized = category?.metadata?.categoryType == .itemized
        if isItemized {
            steps.append(NextStep(
                id: "tax-rate",
                title: "Set the tax rate",
                isComplete: transaction.taxRatePct != nil
            ))
        }

        return steps
    }

    /// Returns true when every step in the list is complete.
    static func allStepsComplete(_ steps: [NextStep]) -> Bool {
        steps.allSatisfy(\.isComplete)
    }
}
