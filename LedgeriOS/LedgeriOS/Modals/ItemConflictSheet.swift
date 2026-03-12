import SwiftUI

/// Confirmation sheet shown when selected items are already linked to other transactions.
/// Groups conflicts by source transaction and shows up to 4 item names.
struct ItemConflictSheet: View {
    let message: String
    let itemNames: [String]
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Reassign Items?")
                .font(Typography.h2)
                .foregroundStyle(BrandColors.textPrimary)
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.screenPadding)

            Text(message)
                .font(Typography.body)
                .foregroundStyle(BrandColors.textSecondary)
                .padding(.horizontal, Spacing.screenPadding)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(itemNames, id: \.self) { name in
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 14))
                            .foregroundStyle(BrandColors.textTertiary)
                        Text(name)
                            .font(Typography.small)
                            .foregroundStyle(BrandColors.textPrimary)
                    }
                }
            }
            .padding(.horizontal, Spacing.screenPadding)

            Spacer()

            HStack(spacing: Spacing.md) {
                Button {
                    onCancel()
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(Typography.button)
                        .foregroundStyle(BrandColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background(BrandColors.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: Dimensions.buttonRadius)
                                .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Dimensions.buttonRadius))
                }

                Button {
                    onConfirm()
                    dismiss()
                } label: {
                    Text("Reassign")
                        .font(Typography.button)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background(BrandColors.primary)
                        .clipShape(RoundedRectangle(cornerRadius: Dimensions.buttonRadius))
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.screenPadding)
        }
    }
}
