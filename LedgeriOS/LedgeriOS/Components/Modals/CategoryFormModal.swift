import SwiftUI

struct CategoryFormModal: View {
    enum Mode {
        case create
        case edit(BudgetCategory)
    }

    /// App-facing category kinds. The persisted `supportedTypes` values are kept
    /// for storage compatibility, but the UI names use the product model.
    enum Kind: Hashable {
        case feeCategories
        case projectCosts
        case items

        var label: String {
            switch self {
            case .feeCategories: return "Fee Categories"
            case .projectCosts: return "Project Costs"
            case .items: return "Items"
            }
        }

        var supportedTypes: [TransactionType] {
            switch self {
            case .feeCategories: return [.fee]
            case .projectCosts: return [.expense]
            case .items: return [.purchase, .return]
            }
        }

        /// Best-effort initialization from an existing category. Drives off
        /// `resolvedSupportedTypes` so it works for both new-model docs and
        /// legacy docs (which derive supportedTypes from metadata.categoryType).
        init(from category: BudgetCategory) {
            switch category.categoryKind {
            case .feeCategory: self = .feeCategories
            case .items: self = .items
            case .projectCost, .unknown: self = .projectCosts
            }
        }
    }

    let mode: Mode
    /// Callback fires with (name, supportedTypes, excludeFromBudget).
    let onSave: (String, [TransactionType], Bool) -> Void
    /// Names of existing categories (excluding the one being edited) for uniqueness validation (L14).
    let existingNames: [String]

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var kind: Kind
    @State private var excludeFromOverallBudget: Bool
    @State private var validationError: String?
    @State private var hasSubmitted = false

    private var kindOptions: [InlineOption<Kind>] {
        [
            InlineOption(id: Kind.feeCategories, label: Kind.feeCategories.label),
            InlineOption(id: Kind.projectCosts, label: Kind.projectCosts.label),
            InlineOption(id: Kind.items, label: Kind.items.label),
        ]
    }

    init(
        mode: Mode,
        existingNames: [String] = [],
        onSave: @escaping (String, [TransactionType], Bool) -> Void
    ) {
        self.mode = mode
        self.existingNames = existingNames
        self.onSave = onSave

        switch mode {
        case .create:
            _name = State(initialValue: "")
            _kind = State(initialValue: .projectCosts)
            _excludeFromOverallBudget = State(initialValue: false)
        case .edit(let category):
            _name = State(initialValue: category.name)
            _kind = State(initialValue: Kind(from: category))
            _excludeFromOverallBudget = State(initialValue: category.metadata?.excludeFromOverallBudget ?? false)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        FormSheet(
            title: isEditing ? "Edit Category" : "New Category",
            primaryAction: FormSheetAction(
                title: isEditing ? "Save" : "Create",
                action: handleSave
            ),
            secondaryAction: FormSheetAction(
                title: "Cancel",
                action: { dismiss() }
            ),
            error: hasSubmitted ? validationError : nil
        ) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                FormField(
                    label: "Name",
                    text: $name,
                    placeholder: "Category name",
                    errorText: hasSubmitted ? nameError : nil
                )

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Type")
                        .font(Typography.label)
                        .foregroundStyle(BrandColors.textSecondary)
                    InlineOptionPicker(selection: $kind, options: kindOptions)
                }

                Toggle("Exclude from Overall Budget", isOn: $excludeFromOverallBudget)
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textPrimary)
                    .tint(BrandColors.primary)
            }
        }
    }

    // MARK: - Validation

    private var nameError: String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return "Name is required"
        }
        if trimmed.count > 100 {
            return "Category name must be 100 characters or less"
        }
        // L13: Block control characters (newlines, tabs, etc.) in names
        if trimmed.unicodeScalars.contains(where: { $0.value < 32 }) {
            return "Category name cannot contain control characters"
        }
        // L14: Uniqueness check — case-insensitive, per-account
        let lowered = trimmed.lowercased()
        if existingNames.contains(where: { $0.lowercased() == lowered }) {
            return "A category with this name already exists"
        }
        return nil
    }

    private func validate() -> String? {
        if let error = nameError { return error }
        return nil
    }

    private func handleSave() {
        hasSubmitted = true
        let error = validate()
        validationError = error
        guard error == nil else { return }

        onSave(
            name.trimmingCharacters(in: .whitespaces),
            kind.supportedTypes,
            excludeFromOverallBudget
        )
        dismiss()
    }
}

#Preview("Create") {
    CategoryFormModal(mode: .create) { name, supportedTypes, exclude in
        print("Create: \(name), \(supportedTypes), exclude: \(exclude)")
    }
}

#Preview("Edit") {
    var category = BudgetCategory()
    category.name = "Materials"
    category.supportedTypes = [.expense]

    return CategoryFormModal(mode: .edit(category)) { name, supportedTypes, exclude in
        print("Edit: \(name), \(supportedTypes), exclude: \(exclude)")
    }
}
