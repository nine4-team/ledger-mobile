import Foundation

/// Validation error returned by form validation functions.
struct ValidationError: Equatable {
    let field: String
    let message: String
}

/// Pure validation logic for the New Project creation form.
enum ProjectFormValidation {

    /// Validates all project creation form fields.
    /// Returns an array of validation errors (empty if valid).
    static func validateProject(
        name: String,
        clientName: String,
        budgetAllocations: [String: Int] = [:]
    ) -> [ValidationError] {
        var errors: [ValidationError] = []

        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(ValidationError(field: "name", message: "Name is required"))
        }

        if clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(ValidationError(field: "clientName", message: "Client name is required"))
        }

        for (_, allocation) in budgetAllocations where allocation < 0 {
            errors.append(ValidationError(
                field: "budgetAllocations",
                message: "Budget allocations must be zero or greater"
            ))
            break
        }

        return errors
    }

    /// Quick check whether a project has the minimum required fields.
    static func isValidProject(name: String, clientName: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
