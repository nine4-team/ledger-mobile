import SwiftUI

/// A radio-button style inline picker for small option sets in forms.
///
/// Displays options vertically with radio circles — filled when selected,
/// hollow when not. Matches the visual language of `InlineVendorPicker`
/// but works with any `Hashable` type.
///
/// Use this for form fields with 2–4 fixed options (e.g. "Purchased By",
/// "Payable", yes/no toggles). For tab-style navigation, use
/// `SegmentedControl` instead.
struct InlineOptionPicker<T: Hashable>: View {
    @Binding var selection: T
    let options: [InlineOption<T>]

    var body: some View {
        VStack(spacing: Spacing.xs) {
            ForEach(options, id: \.id) { option in
                let isSelected = selection == option.id

                Button {
                    selection = option.id
                } label: {
                    HStack(spacing: Spacing.md) {
                        Circle()
                            .strokeBorder(isSelected ? BrandColors.primary : BrandColors.border, lineWidth: 2)
                            .frame(width: 20, height: 20)
                            .overlay {
                                if isSelected {
                                    Circle()
                                        .fill(BrandColors.primary)
                                        .frame(width: 10, height: 10)
                                }
                            }

                        Text(option.label)
                            .font(Typography.body)
                            .foregroundStyle(BrandColors.textPrimary)

                        Spacer()
                    }
                    .padding(.vertical, Spacing.sm)
                    .padding(.horizontal, Spacing.md)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .background(Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                            .stroke(isSelected ? BrandColors.primary : BrandColors.border, lineWidth: Dimensions.borderWidth)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// An option for `InlineOptionPicker`.
struct InlineOption<T: Hashable> {
    let id: T
    let label: String
}
