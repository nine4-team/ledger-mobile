import SwiftUI

#if canImport(FirebaseFirestore)
// Existing source-app binding only. Both builds use the presentation below;
// the Supabase target does not import BudgetCategory or a Firebase adapter.
struct CategoryFormModal: View {
    enum Mode {
        case create
        case edit(BudgetCategory)
    }

    let mode: Mode
    var existingNames: [String] = []
    let onSave: (String, BudgetCategoryType, Bool) -> Void

    var body: some View {
        CategoryFormPresentation(mode: presentationMode, existingNames: existingNames) { name, kind, excluded in
            let type: BudgetCategoryType = switch kind {
            case .general: .general
            case .itemized: .itemized
            case .fee: .fee
            }
            onSave(name, type, excluded)
        }
    }

    private var presentationMode: CategoryFormPresentation.Mode {
        switch mode {
        case .create: return .create
        case .edit(let category):
            let kind: CategoryFormPresentation.Kind = switch category.resolvedCategoryType {
            case .general: .general
            case .itemized: .itemized
            case .fee: .fee
            }
            return .edit(name: category.name, kind: kind,
                excluded: category.metadata?.excludeFromOverallBudget ?? false)
        }
    }
}
#endif

/// Reused category form: presentation inputs and a durable save action only.
struct CategoryFormPresentation: View {
    enum Mode {
        case create
        case edit(name: String, kind: Kind, excluded: Bool)
    }

    enum Kind: String, Hashable {
        case general
        case itemized
        case fee

        var label: String {
            switch self {
            case .general: return "General"
            case .itemized: return "Itemized"
            case .fee: return "Fee"
            }
        }

    }

    let mode: Mode
    /// Callback fires with (name, categoryType, excludeFromBudget).
    let onSave: (String, Kind, Bool) async throws -> Void
    /// Names of existing categories (excluding the one being edited) for uniqueness validation (L14).
    let existingNames: [String]

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var kind: Kind
    @State private var excludeFromOverallBudget: Bool
    @State private var validationError: String?
    @State private var hasSubmitted = false
    @State private var showingKindInfo = false
    @State private var isSaving = false

    private var kindOptions: [InlineOption<Kind>] {
        [
            InlineOption(id: Kind.general, label: Kind.general.label),
            InlineOption(id: Kind.itemized, label: Kind.itemized.label),
            InlineOption(id: Kind.fee, label: Kind.fee.label),
        ]
    }

    init(
        mode: Mode,
        existingNames: [String] = [],
        onSave: @escaping (String, Kind, Bool) async throws -> Void
    ) {
        self.mode = mode
        self.existingNames = existingNames
        self.onSave = onSave

        switch mode {
        case .create:
            _name = State(initialValue: "")
            _kind = State(initialValue: .general)
            _excludeFromOverallBudget = State(initialValue: false)
        case .edit(let name, let kind, let excluded):
            _name = State(initialValue: name)
            _kind = State(initialValue: kind)
            _excludeFromOverallBudget = State(initialValue: excluded)
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
                isLoading: isSaving,
                isDisabled: isSaving,
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
                    HStack(spacing: Spacing.xs) {
                        Text("Type")
                            .font(Typography.label)
                            .foregroundStyle(BrandColors.textSecondary)

                        Button {
                            showingKindInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(Typography.small)
                                .foregroundStyle(BrandColors.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Category behavior info")
                    }

                    InlineOptionPicker(selection: $kind, options: kindOptions)
                }

                Toggle("Exclude from Overall Budget", isOn: $excludeFromOverallBudget)
                    .accessibilityIdentifier("category-exclude-overall-budget")
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textPrimary)
                    .tint(BrandColors.primary)
            }
        }
        .disabled(isSaving)
        .interactiveDismissDisabled(isSaving)
        .alert("Category Behavior", isPresented: $showingKindInfo) {
            Button("OK", role: .cancel) { showingKindInfo = false }
        } message: {
            Text(kindInfoMessage)
        }
    }

    private var kindInfoMessage: String {
        """
        General: non-itemized project costs like labor, fuel, delivery, storage, receiving, and install services. These do not require item rows.

        Itemized: purchases and returns that require item rows and are checked against the transaction subtotal.

        Fee: money received by the business, such as design fees or client payments.
        """
    }

    // MARK: - Validation

    private var nameError: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Name is required"
        }
        if trimmed.unicodeScalars.count > 100 {
            return "Category name must be 100 characters or less"
        }
        // L13: Block control characters (newlines, tabs, etc.) in names
        if trimmed.unicodeScalars.contains(where: {
            $0.properties.generalCategory == .control || $0.properties.generalCategory == .format
        }) {
            return "Category name cannot contain control characters"
        }
        // L14: Uniqueness check — case-insensitive, per-account
        let lowered = (trimmed as NSString).lowercased
        if existingNames.contains(where: { ($0 as NSString).lowercased == lowered }) {
            return "A category with this name already exists"
        }
        return nil
    }

    private func validate() -> String? {
        if let error = nameError { return error }
        return nil
    }

    private func handleSave() {
        guard !isSaving else { return }
        hasSubmitted = true
        let error = validate()
        validationError = error
        guard error == nil else { return }

        let savedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedKind = kind
        let savedExclusion = excludeFromOverallBudget
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            do {
                try await onSave(savedName, savedKind, savedExclusion)
                dismiss()
            } catch {
                validationError = "Could not save this category. Your changes are still here; try again."
            }
        }
    }
}

#if canImport(FirebaseFirestore)
#Preview("Create") {
    CategoryFormModal(mode: .create) { name, categoryType, exclude in
        print("Create: \(name), \(categoryType), exclude: \(exclude)")
    }
}

#Preview("Edit") {
    var category = BudgetCategory()
    category.name = "Materials"
    category.metadata = BudgetCategoryMetadata(categoryType: .general, excludeFromOverallBudget: false)

    return CategoryFormModal(mode: .edit(category)) { name, categoryType, exclude in
        print("Edit: \(name), \(categoryType), exclude: \(exclude)")
    }
}
#endif
