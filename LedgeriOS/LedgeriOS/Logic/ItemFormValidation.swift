import Foundation

/// Pure validation logic for the New Item creation form.
enum ItemFormValidation {

    /// Validates all item creation form fields.
    /// Returns an array of validation errors (empty if valid).
    static func validateItem(
        name: String,
        imageCount: Int = 0,
        purchasePriceCents: Int? = nil,
        projectPriceCents: Int? = nil,
        marketValueCents: Int? = nil
    ) -> [ValidationError] {
        var errors: [ValidationError] = []

        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && imageCount == 0 {
            errors.append(ValidationError(field: "name", message: "Add a name or at least one image"))
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
    /// Requires either a non-empty name or at least one image.
    static func isValidItem(name: String, imageCount: Int = 0) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || imageCount > 0
    }
}
