import SwiftUI

/// Single budget category row for settings/management screens.
struct CategoryRow: View {
    let name: String
    let categoryType: BudgetCategoryType
    var onTap: (() -> Void)?

    private var typeLabel: String { BudgetCategoryKind(categoryType: categoryType).displayLabel }
    private var typeColor: Color {
        switch categoryType {
        case .fee: return StatusColors.badgeWarning
        case .general: return BrandColors.primary
        case .itemized: return StatusColors.badgeInfo
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
        .frame(minHeight: 44)
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

#Preview("Project Cost") {
    CategoryRow(name: "Materials", categoryType: .general)
        .padding(Spacing.screenPadding)
}

#Preview("Items") {
    CategoryRow(name: "Appliances", categoryType: .itemized)
        .padding(Spacing.screenPadding)
}

#Preview("Fee Category") {
    CategoryRow(name: "Architect Fee", categoryType: .fee)
        .padding(Spacing.screenPadding)
}

#Preview("Tappable") {
    CategoryRow(name: "Materials", categoryType: .general, onTap: {})
        .padding(Spacing.screenPadding)
}
