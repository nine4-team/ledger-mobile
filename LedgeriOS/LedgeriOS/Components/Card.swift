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
            .padding(padding)
            .background(BrandColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Dimensions.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Dimensions.cardRadius)
                    .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
            )
    }
}

struct CardStyle: ViewModifier {
    let padding: CGFloat

    init(padding: CGFloat = Spacing.cardPadding) {
        self.padding = padding
    }

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(BrandColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Dimensions.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Dimensions.cardRadius)
                    .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
            )
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
