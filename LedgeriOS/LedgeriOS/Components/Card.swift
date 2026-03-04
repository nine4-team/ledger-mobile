import SwiftUI

struct Card<Content: View>: View {
    let padding: CGFloat
    let isSelected: Bool
    let content: Content

    init(
        padding: CGFloat = Spacing.cardPadding,
        isSelected: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.isSelected = isSelected
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(BrandColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Dimensions.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Dimensions.cardRadius)
                    .stroke(BrandColors.borderSecondary, lineWidth: Dimensions.borderWidth)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Dimensions.cardRadius)
                    .stroke(
                        isSelected ? BrandColors.primary : Color.clear,
                        lineWidth: isSelected ? Dimensions.selectionBorderWidth : 0
                    )
            )
            .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }
}

struct CardStyle: ViewModifier {
    let padding: CGFloat
    let isSelected: Bool

    init(padding: CGFloat = Spacing.cardPadding, isSelected: Bool = false) {
        self.padding = padding
        self.isSelected = isSelected
    }

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(BrandColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Dimensions.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Dimensions.cardRadius)
                    .stroke(BrandColors.borderSecondary, lineWidth: Dimensions.borderWidth)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Dimensions.cardRadius)
                    .stroke(
                        isSelected ? BrandColors.primary : Color.clear,
                        lineWidth: isSelected ? Dimensions.selectionBorderWidth : 0
                    )
            )
            .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }
}

extension View {
    func cardStyle(padding: CGFloat = Spacing.cardPadding, isSelected: Bool = false) -> some View {
        modifier(CardStyle(padding: padding, isSelected: isSelected))
    }
}

// MARK: - Card Divider

/// Consistent divider for card internal sections. Uses borderSecondary at borderWidth height.
struct CardDivider: View {
    var horizontalPadding: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(BrandColors.borderSecondary)
            .frame(height: Dimensions.borderWidth)
            .padding(.horizontal, horizontalPadding)
    }
}

#Preview("Light Mode") {
    VStack(spacing: Spacing.cardListGap) {
        Card {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Card Title")
                    .font(Typography.h3)
                Text("Some card body content goes here.")
                    .font(Typography.body)
            }
        }

        Card(isSelected: true) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Selected Card")
                    .font(Typography.h3)
                Text("This card is selected.")
                    .font(Typography.body)
            }
        }

        Text("Using .cardStyle() modifier")
            .font(Typography.body)
            .cardStyle()
    }
    .padding(Spacing.screenPadding)
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    VStack(spacing: Spacing.cardListGap) {
        Card {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Card Title")
                    .font(Typography.h3)
                Text("Some card body content goes here.")
                    .font(Typography.body)
            }
        }

        Text("Using .cardStyle() modifier")
            .font(Typography.body)
            .cardStyle()
    }
    .padding(Spacing.screenPadding)
    .preferredColorScheme(.dark)
}
