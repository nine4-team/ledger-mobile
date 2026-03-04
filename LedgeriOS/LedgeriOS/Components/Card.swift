import SwiftUI

struct Card<Content: View>: View {
    let padding: CGFloat
    let content: Content

    init(padding: CGFloat = Spacing.cardPadding, @ViewBuilder content: () -> Content) {
        self.padding = padding
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
            .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }
}

struct CardStyle: ViewModifier {
    let padding: CGFloat

    init(padding: CGFloat = Spacing.cardPadding) {
        self.padding = padding
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
            .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }
}

extension View {
    func cardStyle(padding: CGFloat = Spacing.cardPadding) -> some View {
        modifier(CardStyle(padding: padding))
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
