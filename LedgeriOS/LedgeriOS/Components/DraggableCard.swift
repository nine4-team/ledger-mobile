import SwiftUI

/// Card with drag handle for reorder operations in settings screens.
struct DraggableCard<RightContent: View>: View {
    let title: String
    var isDisabled: Bool = false
    var isActive: Bool = false
    @ViewBuilder var rightContent: RightContent

    init(
        title: String,
        isDisabled: Bool = false,
        isActive: Bool = false,
        @ViewBuilder rightContent: () -> RightContent = { EmptyView() }
    ) {
        self.title = title
        self.isDisabled = isDisabled
        self.isActive = isActive
        self.rightContent = rightContent()
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "line.3.horizontal")
                .font(Typography.body)
                .foregroundStyle(BrandColors.textTertiary)

            Text(title)
                .font(Typography.body)
                .foregroundStyle(isDisabled ? BrandColors.textDisabled : BrandColors.textPrimary)

            Spacer()

            rightContent
        }
        .cardStyle()
        .opacity(isDisabled ? 0.5 : 1)
        .shadow(color: isActive ? Color.black.opacity(0.15) : .clear, radius: 8, y: 4)
        .scaleEffect(isActive ? 1.02 : 1)
        .animation(.easeInOut(duration: 0.15), value: isActive)
    }
}

#Preview("Normal") {
    DraggableCard(title: "Materials")
        .padding(Spacing.screenPadding)
}

#Preview("Disabled") {
    DraggableCard(title: "Archived Category", isDisabled: true)
        .padding(Spacing.screenPadding)
}

#Preview("Active (Dragging)") {
    DraggableCard(title: "Being Dragged", isActive: true)
        .padding(Spacing.screenPadding)
}

#Preview("With Right Content") {
    DraggableCard(title: "Materials") {
        Badge(text: "General")
    }
    .padding(Spacing.screenPadding)
}
