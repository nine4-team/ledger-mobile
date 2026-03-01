import SwiftUI

struct CategoryFormModal: View {
    enum Mode {
        case create
        case edit(BudgetCategory)
    }

    let mode: Mode
    let onSave: (String, BudgetCategoryType, Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var isItemized: Bool
    @State private var isFee: Bool
    @State private var excludeFromOverallBudget: Bool
    @State private var validationError: String?
    @State private var hasSubmitted = false

    init(mode: Mode, onSave: @escaping (String, BudgetCategoryType, Bool) -> Void) {
        self.mode = mode
        self.onSave = onSave

        switch mode {
        case .create:
            _name = State(initialValue: "")
            _isItemized = State(initialValue: false)
            _isFee = State(initialValue: false)
            _excludeFromOverallBudget = State(initialValue: false)
        case .edit(let category):
            _name = State(initialValue: category.name)
            _isItemized = State(initialValue: category.metadata?.categoryType == .itemized)
            _isFee = State(initialValue: category.metadata?.categoryType == .fee)
            _excludeFromOverallBudget = State(initialValue: category.metadata?.excludeFromOverallBudget ?? false)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var categoryType: BudgetCategoryType {
        if isItemized { return .itemized }
        if isFee { return .fee }
        return .general
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

                VStack(alignment: .leading, spacing: Spacing.md) {
                    Toggle("Itemized", isOn: $isItemized)
                        .font(Typography.body)
                        .foregroundStyle(BrandColors.textPrimary)
                        .onChange(of: isItemized) { _, newValue in
                            if newValue { isFee = false }
                        }

                    Toggle("Fee", isOn: $isFee)
                        .font(Typography.body)
                        .foregroundStyle(BrandColors.textPrimary)
                        .onChange(of: isFee) { _, newValue in
                            if newValue { isItemized = false }
                        }

                    Toggle("Exclude from Overall Budget", isOn: $excludeFromOverallBudget)
                        .font(Typography.body)
                        .foregroundStyle(BrandColors.textPrimary)
                }
                .tint(BrandColors.primary)
            }
        }
    }

    // MARK: - Validation

    private var nameError: String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Name is required"
        }
        if name.count > 100 {
            return "Category name must be 100 characters or less"
        }
        return nil
    }

    private func validate() -> String? {
        if let error = nameError { return error }
        if isItemized && isFee {
            return "A category cannot be both Itemized and Fee"
        }
        return nil
    }

    private func handleSave() {
        hasSubmitted = true
        let error = validate()
        validationError = error
        guard error == nil else { return }

        onSave(name.trimmingCharacters(in: .whitespaces), categoryType, excludeFromOverallBudget)
        dismiss()
    }
}

#Preview("Create") {
    CategoryFormModal(mode: .create) { name, type, exclude in
        print("Create: \(name), \(type), exclude: \(exclude)")
    }
}

#Preview("Edit") {
    var category = BudgetCategory()
    category.name = "Materials"
    category.metadata = BudgetCategoryMetadata(categoryType: .general, excludeFromOverallBudget: false)

    return CategoryFormModal(mode: .edit(category)) { name, type, exclude in
        print("Edit: \(name), \(type), exclude: \(exclude)")
    }
}
