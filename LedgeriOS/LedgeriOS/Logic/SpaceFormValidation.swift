import Foundation

/// Pure validation logic for the New Space creation form.
enum SpaceFormValidation {

    /// Validates all space creation form fields.
    /// Returns an array of validation errors (empty if valid).
    static func validateSpace(name: String) -> [ValidationError] {
        var errors: [ValidationError] = []

        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(ValidationError(field: "name", message: "Name is required"))
        }

        return errors
    }

    /// Quick check whether a space has the minimum required fields.
    static func isValidSpace(name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
