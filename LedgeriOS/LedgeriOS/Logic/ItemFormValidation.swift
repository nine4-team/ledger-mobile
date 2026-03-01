import Foundation

/// Pure validation logic for the New Item creation form.
enum ItemFormValidation {

    /// Validates all item creation form fields.
    /// Returns an array of validation errors (empty if valid).
    static func validateItem(
        name: String,
        purchasePriceCents: Int? = nil,
        projectPriceCents: Int? = nil,
        marketValueCents: Int? = nil
    ) -> [ValidationError] {
        var errors: [ValidationError] = []

        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(ValidationError(field: "name", message: "Name is required"))
        }

        if let price = purchasePriceCents, price < 0 {
            errors.append(ValidationError(
                field: "purchasePrice",
                message: "Price must be zero or greater"
            ))
        }

        if let price = projectPriceCents, price < 0 {
            errors.append(ValidationError(
                field: "projectPrice",
                message: "Price must be zero or greater"
            ))
        }

        if let price = marketValueCents, price < 0 {
            errors.append(ValidationError(
                field: "marketValue",
                message: "Price must be zero or greater"
            ))
        }

        return errors
    }

    /// Quick check whether an item has the minimum required fields.
    static func isValidItem(name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
