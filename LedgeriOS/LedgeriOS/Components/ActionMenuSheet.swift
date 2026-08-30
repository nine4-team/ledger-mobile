import SwiftUI

struct ActionMenuSheet: View {
    let title: String?
    let items: [ActionMenuItem]
    var closeOnItemPress: Bool = true
    var onSelectAction: ((@escaping () -> Void) -> Void)?
    var persistentExpandedItemKey: Binding<String?>?

    @State private var localExpandedItemKey: String?
    @Environment(\.dismiss) private var dismiss

    private var expandedItemKey: String? {
        persistentExpandedItemKey?.wrappedValue ?? localExpandedItemKey
    }

    private func setExpandedItemKey(_ key: String?) {
        if let persistentExpandedItemKey {
            persistentExpandedItemKey.wrappedValue = key
        } else {
            localExpandedItemKey = key
        }
    }

    // MARK: - Flattened Row Model

    private enum MenuRow: Identifiable {
        case item(ActionMenuItem)
        case subaction(ActionMenuSubitem, parent: ActionMenuItem)

        var id: String {
            switch self {
            case .item(let item): return item.id
            case .subaction(let sub, let parent): return "\(parent.id)_\(sub.id)"
            }
        }
    }

    private var flatRows: [MenuRow] {
        items.flatMap { item -> [MenuRow] in
            var rows: [MenuRow] = [.item(item)]
            if expandedItemKey == item.id, let subs = item.subactions {
                rows += subs.map { .subaction($0, parent: item) }
            }
            return rows
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header with title and dismiss button
            if let title {
                HStack {
                    Text(title)
                        .font(Typography.h2)
                        .foregroundStyle(BrandColors.textPrimary)
                    Spacer()
                    if !closeOnItemPress && hasActiveSelections {
                        Button("Clear") {
                            clearAllFilters()
                        }
                        .font(Typography.buttonSmall)
                        .foregroundStyle(BrandColors.primary)
                        .buttonStyle(.plain)
                    }
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(BrandColors.textTertiary)
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.screenPadding)
                .padding(.bottom, Spacing.md)
            }

            List {
                ForEach(flatRows) { row in
                    switch row {
                    case .item(let item):
                        menuItemRow(item)
                    case .subaction(let sub, let parent):
                        submenuRow(sub, parentItem: parent)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(BrandColors.surface)
        .onAppear {
            PerformanceDiagnostics.shared.event(
                "ActionMenuAppeared",
                kind: "shared-action-menu",
                count: items.count
            )
        }
    }

    // MARK: - Menu Item Row

    @ViewBuilder
    private func menuItemRow(_ item: ActionMenuItem) -> some View {
        let hasSubmenu = ActionMenuCalculations.hasSubactions(item)
        let isExpanded = expandedItemKey == item.id

        Button {
            handleItemTap(item)
        } label: {
            HStack(spacing: Spacing.md) {
                if let icon = item.icon {
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundStyle(BrandColors.primary)
                        .frame(width: 24, alignment: .center)
                }

                Text(item.label)
                    .font(Typography.body)
                    .foregroundStyle(
                        item.isSelected ? BrandColors.primary
                            : BrandColors.textPrimary
                    )

                Spacer()

                if item.isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BrandColors.primary)
                } else if hasSubmenu {
                    selectionIndicator(for: item)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundStyle(BrandColors.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(BrandColors.surface)
        .listRowSeparatorTint(BrandColors.border)
        .listRowInsets(EdgeInsets(top: 0, leading: Spacing.lg, bottom: 0, trailing: Spacing.lg))
    }

    // MARK: - Selection Indicator

    @ViewBuilder
    private func selectionIndicator(for item: ActionMenuItem) -> some View {
        let iconSelected = item.subactions?.filter { $0.id != "all" && $0.icon == "checkmark.circle.fill" } ?? []
        let keySelected = item.selectedSubactionKey.flatMap { key in
            item.subactions?.first(where: { $0.id == key })
        }

        if let selectionSummary = item.selectionSummary {
            Text(selectionSummary)
                .font(Typography.small)
                .foregroundStyle(item.isFilterActive == true ? BrandColors.primary : BrandColors.textSecondary)
                .lineLimit(1)
        } else if let keySelected {
            Text(keySelected.label)
                .font(Typography.small)
                .foregroundStyle(BrandColors.primary)
        } else if iconSelected.count == 1, let selected = iconSelected.first {
            Text(selected.label)
                .font(Typography.small)
                .foregroundStyle(BrandColors.primary)
        } else if iconSelected.count > 1 {
            Text("(\(iconSelected.count))")
                .font(Typography.small)
                .foregroundStyle(BrandColors.primary)
        }
    }

    // MARK: - Submenu Row

    @ViewBuilder
    private func submenuRow(_ subaction: ActionMenuSubitem, parentItem: ActionMenuItem) -> some View {
        let isSelected = subaction.icon == "checkmark.circle.fill"
            || ActionMenuCalculations.isSubactionSelected(item: parentItem, subactionKey: subaction.id)

        Button {
            handleSubactionTap(subaction)
        } label: {
            HStack(spacing: Spacing.md) {
                Text(subaction.label)
                    .font(Typography.small)
                    .foregroundStyle(isSelected ? BrandColors.primary : BrandColors.textSecondary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BrandColors.primary)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(BrandColors.surface)
        .listRowSeparatorTint(BrandColors.border)
        .listRowInsets(EdgeInsets(top: 0, leading: Spacing.lg + Spacing.xl, bottom: 0, trailing: Spacing.lg))
    }

    // MARK: - Clear All

    private var hasActiveSelections: Bool {
        items.contains { item in
            if let isFilterActive = item.isFilterActive {
                return isFilterActive
            }
            return item.isSelected ||
                (item.subactions?.contains { $0.id != "all" && $0.icon == "checkmark.circle.fill" } ?? false)
        }
    }

    private func clearAllFilters() {
        for item in items {
            if let subactions = item.subactions,
               let allOption = subactions.first(where: { $0.id == "all" }) {
                allOption.onPress()
            } else if item.isSelected, let onPress = item.onPress {
                onPress()
            }
        }
    }

    // MARK: - Actions

    private func handleItemTap(_ item: ActionMenuItem) {
        let result = ActionMenuCalculations.resolveMenuAction(item: item, expandedKey: expandedItemKey)
        switch result {
        case .expand(let key):
            withAnimation(.easeInOut(duration: 0.25)) {
                setExpandedItemKey(key)
            }
        case .collapse:
            withAnimation(.easeInOut(duration: 0.25)) {
                setExpandedItemKey(nil)
            }
        case .executeAction:
            if closeOnItemPress {
                if let onSelectAction {
                    if let action = item.onPress { onSelectAction(action) }
                } else {
                    item.onPress?()
                }
                dismiss()
            } else {
                item.onPress?()
            }
        }
    }

    private func handleSubactionTap(_ subaction: ActionMenuSubitem) {
        if closeOnItemPress {
            if let onSelectAction {
                onSelectAction(subaction.onPress)
            } else {
                subaction.onPress()
            }
            dismiss()
        } else {
            subaction.onPress()
        }
    }
}

// MARK: - Previews

#Preview("Simple Menu") {
    @Previewable @State var showSheet = true

    Color.clear
        .sheet(isPresented: $showSheet) {
            ActionMenuSheet(
                title: "Options",
                items: [
                    ActionMenuItem(id: "open", label: "Open", icon: "doc"),
                    ActionMenuItem(id: "share", label: "Share", icon: "square.and.arrow.up"),
                    ActionMenuItem(id: "copy", label: "Copy Link", icon: "link"),
                ]
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
}

#Preview("Hierarchical Menu") {
    @Previewable @State var showSheet = true

    Color.clear
        .sheet(isPresented: $showSheet) {
            ActionMenuSheet(
                title: "Olive green faded area rug 8x10",
                items: [
                    ActionMenuItem(id: "open", label: "Open", icon: "arrow.up.right.square"),
                    ActionMenuItem(
                        id: "status", label: "Status", icon: "flag",
                        subactions: [
                            ActionMenuSubitem(id: "active", label: "Active") {},
                            ActionMenuSubitem(id: "sold", label: "Sold") {},
                            ActionMenuSubitem(id: "archived", label: "Archived") {},
                        ],
                        selectedSubactionKey: "active"
                    ),
                    ActionMenuItem(
                        id: "space", label: "Space", icon: "mappin.and.ellipse",
                        subactions: [
                            ActionMenuSubitem(id: "living", label: "Living Room") {},
                            ActionMenuSubitem(id: "bed", label: "Bedroom") {},
                        ]
                    ),
                    ActionMenuItem(id: "delete", label: "Delete", icon: "trash", isDestructive: true),
                ]
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
}

#Preview("Multi-Select Mode") {
    @Previewable @State var showSheet = true

    Color.clear
        .sheet(isPresented: $showSheet) {
            ActionMenuSheet(
                title: "Filter",
                items: [
                    ActionMenuItem(id: "active", label: "Active", icon: "circle.fill"),
                    ActionMenuItem(id: "sold", label: "Sold", icon: "circle.fill"),
                    ActionMenuItem(id: "archived", label: "Archived", icon: "circle.fill"),
                ],
                closeOnItemPress: false
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
}
