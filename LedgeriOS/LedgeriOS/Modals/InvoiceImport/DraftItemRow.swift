import SwiftUI

/// Single editable draft item row for invoice import review.
struct DraftItemRow: View {
    @Binding var item: DraftLineItem

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            // Inclusion toggle
            Button {
                item.isIncluded.toggle()
            } label: {
                Image(systemName: item.isIncluded ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isIncluded ? BrandColors.primary : BrandColors.textTertiary)
                    .font(.system(size: 20))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isIncluded ? "Included" : "Excluded")

            // Thumbnail (Wayfair only)
            if let thumbnail = item.thumbnailImage {
                Image(decorative: thumbnail, scale: 2.0)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            // Content
            VStack(alignment: .leading, spacing: Spacing.xs) {
                // Description
                TextField("Description", text: $item.description)
                    .font(Typography.body)
                    .foregroundStyle(item.isIncluded ? BrandColors.textPrimary : BrandColors.textTertiary)

                // SKU badge
                if let sku = item.sku, !sku.isEmpty {
                    Text(sku)
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 2)
                        .background(BrandColors.inputBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                // Attribute lines
                if let attrs = item.attributeLines, !attrs.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(attrs, id: \.self) { attr in
                            Text(attr)
                                .font(Typography.caption)
                                .foregroundStyle(BrandColors.textSecondary)
                        }
                    }
                }

                // Qty × Price = Total
                HStack(spacing: Spacing.sm) {
                    HStack(spacing: 2) {
                        Text("Qty:")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)
                        TextField("1", value: $item.qty, format: .number)
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textPrimary)
                            .platformKeyboardType(.numberPad)
                            .frame(width: 30)
                    }

                    HStack(spacing: 2) {
                        Text("@")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)
                        TextField("0.00", text: $item.unitPrice)
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textPrimary)
                            .platformKeyboardType(.decimalPad)
                            .frame(width: 60)
                    }

                    Spacer()

                    Text("$\(item.total)")
                        .font(Typography.caption.weight(.medium))
                        .foregroundStyle(item.isIncluded ? BrandColors.textPrimary : BrandColors.textTertiary)
                }
            }
        }
        .padding(.vertical, Spacing.xs)
        .opacity(item.isIncluded ? 1 : 0.5)
    }
}
