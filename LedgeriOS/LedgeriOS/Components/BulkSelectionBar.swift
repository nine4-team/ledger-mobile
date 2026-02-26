import SwiftUI

struct BulkSelectionBar: View {
    let selectedCount: Int
    var totalCents: Int?
    var actionLabel: String = "Actions"
    let onBulkActions: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("\(selectedCount) selected")
                    .font(Typography.body)
                    .fontWeight(.bold)
                    .foregroundStyle(BrandColors.textPrimary)

                if let totalCents {
                    Text(CurrencyFormatting.formatCentsWithDecimals(totalCents))
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }

            Spacer()

            HStack(spacing: Spacing.sm) {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle")
                        .font(.title3)
                        .foregroundStyle(BrandColors.textSecondary)
                }
                .buttonStyle(.plain)

                AppButton(title: actionLabel, action: onBulkActions)
                    .fixedSize()
            }
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.vertical, Spacing.sm)
        .background(BrandColors.surface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(BrandColors.border)
                .frame(height: Dimensions.borderWidth)
        }
    }
}

#Preview("1 Selected") {
    VStack {
        Spacer()
        BulkSelectionBar(selectedCount: 1, onBulkActions: {}, onClear: {})
    }
}

#Preview("5 Selected with Total") {
    VStack {
        Spacer()
        BulkSelectionBar(selectedCount: 5, totalCents: 49500, onBulkActions: {}, onClear: {})
    }
}

#Preview("20 Selected") {
    VStack {
        Spacer()
        BulkSelectionBar(selectedCount: 20, totalCents: 1250075, onBulkActions: {}, onClear: {})
    }
}
