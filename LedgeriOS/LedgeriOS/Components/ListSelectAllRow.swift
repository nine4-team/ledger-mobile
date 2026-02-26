import SwiftUI

struct ListSelectAllRow: View {
    let isChecked: Bool
    var label: String = "Select All"
    var isDisabled: Bool = false
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: Spacing.md) {
                SelectorCircle(isSelected: isChecked, indicator: .check)
                Text(label)
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textPrimary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1.0)
    }
}

// MARK: - Previews

#Preview("Unchecked") {
    ListSelectAllRow(isChecked: false, onToggle: {})
        .padding(Spacing.screenPadding)
}

#Preview("Checked") {
    ListSelectAllRow(isChecked: true, onToggle: {})
        .padding(Spacing.screenPadding)
}

#Preview("Disabled") {
    ListSelectAllRow(isChecked: false, isDisabled: true, onToggle: {})
        .padding(Spacing.screenPadding)
}
