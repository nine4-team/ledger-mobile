import SwiftUI

struct ListSelectionInfo: View {
    let text: String
    var onPress: (() -> Void)?

    var body: some View {
        if let onPress {
            Button(action: onPress) {
                infoText
                    .underline()
            }
            .buttonStyle(.plain)
        } else {
            infoText
        }
    }

    private var infoText: some View {
        Text(text)
            .font(Typography.small)
            .foregroundStyle(BrandColors.textSecondary)
    }
}

// MARK: - Previews

#Preview("Static") {
    ListSelectionInfo(text: "3 of 10 selected")
        .padding(Spacing.screenPadding)
}

#Preview("Tappable") {
    ListSelectionInfo(text: "3 of 10 selected", onPress: {})
        .padding(Spacing.screenPadding)
}
