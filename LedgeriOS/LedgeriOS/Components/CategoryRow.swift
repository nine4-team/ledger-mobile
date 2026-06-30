import SwiftUI

/// Single budget category row for settings/management screens.
struct CategoryRow: View {
    let name: String
    let supportedTypes: [TransactionType]
    var onTap: (() -> Void)?

    private var typeLabel: String { CategoryDisplay.pillLabel(for: supportedTypes) }
    private var typeColor: Color { CategoryDisplay.pillColor(for: supportedTypes) }

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
    CategoryRow(name: "Materials", supportedTypes: [.expense])
        .padding(Spacing.screenPadding)
}

#Preview("Items") {
    CategoryRow(name: "Appliances", supportedTypes: [.purchase, .return])
        .padding(Spacing.screenPadding)
}

#Preview("Fee Category") {
    CategoryRow(name: "Architect Fee", supportedTypes: [.fee])
        .padding(Spacing.screenPadding)
}

#Preview("Tappable") {
    CategoryRow(name: "Materials", supportedTypes: [.expense], onTap: {})
        .padding(Spacing.screenPadding)
}
