import SwiftUI

/// Editable list of parsed line items for invoice import review.
struct DraftItemsList: View {
    @Binding var items: [DraftLineItem]

    private var includedCount: Int {
        items.filter(\.isIncluded).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Line Items")
                    .font(Typography.label)
                    .foregroundStyle(BrandColors.textSecondary)
                Spacer()
                Text("\(includedCount) of \(items.count) included")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textTertiary)
            }

            if items.isEmpty {
                Text("No line items detected")
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Spacing.lg)
            } else {
                VStack(spacing: 0) {
                    ForEach($items) { $item in
                        DraftItemRow(item: $item)

                        if item.id != items.last?.id {
                            Divider()
                                .padding(.leading, 30)
                        }
                    }
                }
                .padding(Spacing.sm)
                .background(BrandColors.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                        .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
                )
            }
        }
    }
}
