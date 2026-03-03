import SwiftUI

struct ListControlBar<LeftElement: View>: View {
    @Binding var searchText: String
    @Binding var isSearchVisible: Bool
    var actions: [ControlAction]
    var searchPlaceholder: String = "Search..."
    @ViewBuilder var leftElement: () -> LeftElement

    init(
        searchText: Binding<String>,
        isSearchVisible: Binding<Bool>,
        actions: [ControlAction],
        searchPlaceholder: String = "Search...",
        @ViewBuilder leftElement: @escaping () -> LeftElement = { EmptyView() }
    ) {
        self._searchText = searchText
        self._isSearchVisible = isSearchVisible
        self.actions = actions
        self.searchPlaceholder = searchPlaceholder
        self.leftElement = leftElement
    }

    var body: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                leftElement()

                ForEach(actions) { action in
                    actionButton(action)
                }
            }

            ListStateControls(
                searchText: $searchText,
                isSearchVisible: isSearchVisible,
                placeholder: searchPlaceholder
            )
        }
        .padding(.top, Spacing.sm)
    }

    @ViewBuilder
    private func actionButton(_ action: ControlAction) -> some View {
        switch action.appearance {
        case .iconOnly:
            iconOnlyButton(action)
        case .tile:
            tileButton(action)
        case .standard:
            standardButton(action)
        }
    }

    private func standardButton(_ action: ControlAction) -> some View {
        Button {
            action.action()
        } label: {
            HStack(spacing: Spacing.xs) {
                if let icon = action.icon {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                }
                Text(action.title)
                    .font(Typography.buttonSmall)
            }
            .foregroundStyle(
                action.isDisabled
                    ? BrandColors.textDisabled
                    : action.variant == .primary ? .white : BrandColors.textPrimary
            )
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: 40)
            .background(
                action.variant == .primary
                    ? BrandColors.primary
                    : BrandColors.buttonSecondaryBackground
            )
            .clipShape(RoundedRectangle(cornerRadius: Dimensions.buttonRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Dimensions.buttonRadius)
                    .stroke(
                        action.isActive ? BrandColors.primary : BrandColors.border,
                        lineWidth: action.variant == .secondary ? Dimensions.borderWidth : 0
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(action.isDisabled)
        .opacity(action.isDisabled ? 0.5 : 1)
    }

    private func iconOnlyButton(_ action: ControlAction) -> some View {
        Button {
            action.action()
        } label: {
            Image(systemName: action.icon ?? "questionmark")
                .font(.system(size: 16))
                .foregroundStyle(
                    action.variant == .primary ? .white : BrandColors.textPrimary
                )
                .frame(width: 40, height: 40)
                .background(
                    action.variant == .primary
                        ? BrandColors.primary
                        : BrandColors.buttonSecondaryBackground
                )
                .clipShape(RoundedRectangle(cornerRadius: Dimensions.buttonRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Dimensions.buttonRadius)
                        .stroke(
                            action.isActive ? BrandColors.primary : BrandColors.border,
                            lineWidth: Dimensions.borderWidth
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(action.isDisabled)
        .opacity(action.isDisabled ? 0.5 : 1)
    }

    private func tileButton(_ action: ControlAction) -> some View {
        Button {
            action.action()
        } label: {
            Image(systemName: action.icon ?? "plus")
                .font(.system(size: 16))
                .foregroundStyle(BrandColors.textSecondary)
                .frame(width: 40, height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: Dimensions.cardRadius)
                        .stroke(
                            action.isActive ? BrandColors.primary : BrandColors.borderSecondary,
                            style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(action.isDisabled)
        .opacity(action.isDisabled ? 0.5 : 1)
    }
}

// MARK: - Previews

#Preview("2 Actions") {
    ListControlBar(
        searchText: .constant(""),
        isSearchVisible: .constant(false),
        actions: [
            ControlAction(id: "sort", title: "Sort", icon: "arrow.up.arrow.down") {},
            ControlAction(id: "filter", title: "Filter", icon: "line.3.horizontal.decrease") {},
        ]
    )
    .padding(.horizontal)
}

#Preview("With Search Visible") {
    ListControlBar(
        searchText: .constant("Pillow"),
        isSearchVisible: .constant(true),
        actions: [
            ControlAction(id: "sort", title: "Sort", icon: "arrow.up.arrow.down") {},
            ControlAction(id: "filter", title: "Filter", icon: "line.3.horizontal.decrease") {},
        ]
    )
    .padding(.horizontal)
}

#Preview("With Left Element (Select All)") {
    @Previewable @State var allSelected = false

    ListControlBar(
        searchText: .constant(""),
        isSearchVisible: .constant(false),
        actions: [
            ControlAction(id: "search", title: "", icon: "magnifyingglass", appearance: .iconOnly) {},
            ControlAction(id: "sort", title: "Sort", icon: "arrow.up.arrow.down") {},
            ControlAction(id: "filter", title: "Filter", icon: "line.3.horizontal.decrease") {},
            ControlAction(id: "add", title: "", variant: .primary, icon: "plus", appearance: .iconOnly) {},
        ]
    ) {
        Button { allSelected.toggle() } label: {
            SelectorCircle(isSelected: allSelected, indicator: .check)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Select all")
    }
    .padding(.horizontal)
}

#Preview("Mixed Appearances") {
    ListControlBar(
        searchText: .constant(""),
        isSearchVisible: .constant(false),
        actions: [
            ControlAction(id: "search", title: "", icon: "magnifyingglass", appearance: .iconOnly) {},
            ControlAction(id: "sort", title: "Sort", icon: "arrow.up.arrow.down") {},
            ControlAction(id: "filter", title: "Filter", icon: "line.3.horizontal.decrease") {},
            ControlAction(id: "add", title: "Add", variant: .primary, icon: "plus") {},
        ]
    )
    .padding(.horizontal)
}
