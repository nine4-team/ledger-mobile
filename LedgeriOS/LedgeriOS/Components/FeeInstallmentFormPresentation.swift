import SwiftUI

/// Extracted from the existing FeeInstallmentFormSheet; backend-independent.
struct FeeInstallmentFormPresentation: View {
    let categoryName: String
    let totalText: String?
    @Binding var label: String
    @Binding var amount: String
    let isSaving: Bool
    let canSave: Bool
    let errorMessage: String?
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        FormSheet(
            title: "Add \(categoryName) Installment",
            description: "Create one billable portion of this fee.",
            primaryAction: FormSheetAction(title: "Add Installment", isLoading: isSaving,
                isDisabled: !canSave, action: onSave),
            secondaryAction: FormSheetAction(title: "Cancel") { dismiss() },
            error: errorMessage
        ) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                FormField(label: "Label", text: $label, placeholder: "Design fee 1 of 3")
                FormField(label: "Amount", text: $amount, placeholder: "$2,500")
                if let totalText {
                    Text("Total fee: \(totalText)")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }
        }
    }
}
