import Foundation

/// Progressive disclosure validation for the New Transaction multi-step form.
enum TransactionFormValidation {

    /// Validates step 1: transaction type selection.
    static func validateTransactionStep1(type: String?) -> [ValidationError] {
        var errors: [ValidationError] = []

        if type == nil || type!.isEmpty {
            errors.append(ValidationError(
                field: "transactionType",
                message: "Transaction type is required"
            ))
        }

        return errors
    }

    /// Validates step 2: destination selection.
    /// Purchase, sale, and return types require a destination (project or channel).
    static func validateTransactionStep2(
        type: String,
        destination: String?
    ) -> [ValidationError] {
        var errors: [ValidationError] = []

        let typesRequiringDestination = ["purchase", "sale", "return"]
        if typesRequiringDestination.contains(type) && destination == nil {
            errors.append(ValidationError(
                field: "destination",
                message: "Destination is required"
            ))
        }

        return errors
    }

    /// Validates transaction detail fields.
    /// All detail fields are optional for creation — returns empty array.
    static func validateTransactionDetail(
        type: String,
        source: String?,
        amountCents: Int?,
        date: Date?
    ) -> [ValidationError] {
        []
    }

    /// Quick check whether a transaction has the minimum required fields to submit.
    static func isTransactionReadyToSubmit(type: TransactionType?) -> Bool {
        type != nil
    }

    /// Business-paid itemized purchases are first recorded in inventory, then
    /// optionally sold into the project. Returns and other transaction types
    /// must remain in the selected destination scope.
    static func shouldRouteThroughInventory(
        type: TransactionType?,
        isItemizedCategory: Bool,
        purchasedBy: String
    ) -> Bool {
        type == .purchase
            && isItemizedCategory
            && purchasedBy == "design-business"
    }
}
