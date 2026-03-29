import SwiftUI

/// Sheet shown when selected items are already linked to other transactions.
/// Groups conflicts by source transaction and shows up to 4 item names.
///
/// When `onReturn` is provided (destination is a return transaction), presents
/// two action options: "Return" and "Reassign". Otherwise shows a single
/// "Reassign" confirmation.
struct ItemConflictSheet: View {
    let message: String
    let itemNames: [String]
    let onConfirm: () -> Void
    var onReturn: (() -> Void)? = nil
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var isOptionsMode: Bool { onReturn != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text(isOptionsMode ? "How Should These Items Be Moved?" : "Reassign Items?")
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

            if isOptionsMode {
                optionsButtons
            } else {
                reassignButtons
            }
        }
    }

    // MARK: - Options Mode (return transaction destination)

    private var optionsButtons: some View {
        VStack(spacing: Spacing.sm) {
            Button {
                onReturn?()
                dismiss()
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "arrow.uturn.left")
                        .font(.system(size: 14))
                    Text("Return")
                        .font(Typography.button)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background(BrandColors.primary)
                .clipShape(RoundedRectangle(cornerRadius: Dimensions.buttonRadius))
            }

            Button {
                onConfirm()
                dismiss()
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 14))
                    Text("Reassign")
                        .font(Typography.button)
                }
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
                onCancel()
                dismiss()
            } label: {
                Text("Cancel")
                    .font(Typography.button)
                    .foregroundStyle(BrandColors.textTertiary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.bottom, Spacing.screenPadding)
    }

    // MARK: - Reassign Mode (non-return destination)

    private var reassignButtons: some View {
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
