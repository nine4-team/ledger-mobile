import SwiftUI

/// Single budget category row for settings/management screens.
struct CategoryRow: View {
    let name: String
    let categoryType: BudgetCategoryType
    var onTap: (() -> Void)?

    private var typeLabel: String {
        switch categoryType {
        case .general: "General"
        case .itemized: "Itemized"
        case .fee: "Fee"
        }
    }

    private var typeColor: Color {
        switch categoryType {
        case .general: BrandColors.primary
        case .itemized: StatusColors.badgeInfo
        case .fee: StatusColors.badgeWarning
        }
    }

    var body: some View {
        let content = HStack(spacing: Spacing.md) {
            Text(name)
                .font(Typography.body)
                .foregroundStyle(BrandColors.textPrimary)

            Spacer()

            Badge(text: typeLabel, color: typeColor)

            if onTap != nil {
                Image(systemName: "chevron.right")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textTertiary)
            }
        }
        .padding(.vertical, Spacing.sm)
        .contentShape(Rectangle())

        if let onTap {
            Button(action: onTap) {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }
}

#Preview("General") {
    CategoryRow(name: "Materials", categoryType: .general)
        .padding(Spacing.screenPadding)
}

#Preview("Itemized") {
    CategoryRow(name: "Appliances", categoryType: .itemized)
        .padding(Spacing.screenPadding)
}

#Preview("Fee") {
    CategoryRow(name: "Architect Fee", categoryType: .fee)
        .padding(Spacing.screenPadding)
}

#Preview("Tappable") {
    CategoryRow(name: "Materials", categoryType: .general, onTap: {})
        .padding(Spacing.screenPadding)
}
