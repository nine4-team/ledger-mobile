import SwiftUI

/// Information display card for contextual help or tips.
struct InfoCard: View {
    let message: String
    var icon: String = "info.circle"

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: icon)
                .font(Typography.body)
                .foregroundStyle(BrandColors.primary)

            Text(message)
                .font(Typography.small)
                .foregroundStyle(BrandColors.textSecondary)
        }
        .padding(Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandColors.primary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Dimensions.cardRadius))
    }
}

#Preview("Default") {
    InfoCard(message: "Budget categories help you track spending by type. Add categories to get started.")
        .padding(Spacing.screenPadding)
}

#Preview("Custom Icon") {
    InfoCard(message: "Tip: You can drag categories to reorder them.", icon: "lightbulb")
        .padding(Spacing.screenPadding)
}

#Preview("Dark Mode") {
    InfoCard(message: "Budget categories help you track spending by type.")
        .padding(Spacing.screenPadding)
        .preferredColorScheme(.dark)
}
