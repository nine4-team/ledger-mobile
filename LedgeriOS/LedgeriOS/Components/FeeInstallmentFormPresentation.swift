import SwiftUI

/// Original FeeGroupCard layout, with data and row content supplied by its caller.
struct FeeGroupCardPresentation<Rows: View>: View {
    let name: String
    let rowCount: Int
    let remainingText: String
    let totalText: String
    let invoicedText: String
    let receivedText: String
    let invoicedRatio: Double
    let receivedRatio: Double
    @Binding var isExpanded: Bool
    var onAddInstallment: (() -> Void)?
    @ViewBuilder let rows: () -> Rows

    var body: some View {
        BillingRowSurface(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation { isExpanded.toggle() }
                } label: {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack(spacing: Spacing.sm) {
                            Text(name)
                                .font(Typography.body.weight(.semibold))
                                .foregroundStyle(BrandColors.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text(remainingText)
                                .font(Typography.small.weight(.semibold))
                                .foregroundStyle(BrandColors.textPrimary)
                                .monospacedDigit()
                            if rowCount > 0 { Badge(text: "\(rowCount)", color: BrandColors.primary) }
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(BrandColors.textTertiary)
                        }
                        HStack(spacing: Spacing.sm) {
                            Text("Total \(totalText)")
                            Text("Invoiced \(invoicedText)")
                            Text("Received \(receivedText)")
                        }
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                        .lineLimit(1)
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(BrandColors.progressTrack)
                                Capsule().fill(BrandColors.primary.opacity(0.35))
                                    .frame(width: geometry.size.width * invoicedRatio)
                                Capsule().fill(BrandColors.primary)
                                    .frame(width: geometry.size.width * receivedRatio)
                            }
                        }
                        .frame(height: 7).clipShape(Capsule())
                        .accessibilityLabel("Fee invoicing progress")
                        .accessibilityValue("\(invoicedText) invoiced, \(receivedText) received")
                    }
                    .padding(Spacing.md).contentShape(Rectangle())
                }.buttonStyle(.plain)
                if isExpanded {
                    CardDivider()
                    VStack(spacing: 0) {
                        rows()
                        if let onAddInstallment {
                            Button(action: onAddInstallment) {
                                Label("Add Installment", systemImage: "plus.circle.fill")
                                    .font(Typography.body.weight(.semibold))
                                    .foregroundStyle(BrandColors.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(Spacing.md)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

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
