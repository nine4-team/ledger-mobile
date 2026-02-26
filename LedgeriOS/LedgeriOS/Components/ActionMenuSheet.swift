import SwiftUI

struct ActionMenuSheet: View {
    let title: String?
    let items: [ActionMenuItem]
    var closeOnItemPress: Bool = true
    var onSelectAction: ((@escaping () -> Void) -> Void)?

    @State private var expandedItemKey: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let title {
                    Text(title)
                        .font(Typography.h2)
                        .foregroundStyle(BrandColors.textPrimary)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.top, Spacing.lg)
                        .padding(.bottom, Spacing.md)

                    Divider()
                        .foregroundStyle(BrandColors.border)
                }

                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    menuItemRow(item)

                    if expandedItemKey == item.id, let subactions = item.subactions {
                        submenuSection(subactions: subactions, parentItem: item)
                    }

                    if index < items.count - 1 {
                        Divider()
                            .padding(.horizontal, Spacing.lg)
                    }
                }
            }
        }
        .background(BrandColors.surface)
    }

    // MARK: - Menu Item Row

    @ViewBuilder
    private func menuItemRow(_ item: ActionMenuItem) -> some View {
        let isExpanded = expandedItemKey == item.id
        let hasSubmenu = ActionMenuCalculations.hasSubactions(item)
        let isDestructive = ActionMenuCalculations.isDestructiveItem(item)

        Button {
            handleItemTap(item)
        } label: {
            HStack(spacing: Spacing.md) {
                if let icon = item.icon {
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundStyle(isDestructive ? BrandColors.destructive : BrandColors.primary)
                        .frame(width: 24, alignment: .center)
                }

                Text(item.label)
                    .font(Typography.body)
                    .foregroundStyle(isDestructive ? BrandColors.destructive : BrandColors.textPrimary)

                Spacer()

                if hasSubmenu {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundStyle(BrandColors.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .padding(.horizontal, Spacing.lg)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Submenu Section

    @ViewBuilder
    private func submenuSection(subactions: [ActionMenuSubitem], parentItem: ActionMenuItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(subactions) { subaction in
                Button {
                    handleSubactionTap(subaction)
                } label: {
                    HStack(spacing: Spacing.md) {
                        if let icon = subaction.icon {
                            Image(systemName: icon)
                                .font(.system(size: 18))
                                .foregroundStyle(BrandColors.textSecondary)
                                .frame(width: 24, alignment: .center)
                        }

                        Text(subaction.label)
                            .font(Typography.small)
                            .foregroundStyle(BrandColors.textSecondary)

                        Spacer()

                        if ActionMenuCalculations.isSubactionSelected(item: parentItem, subactionKey: subaction.id) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(BrandColors.primary)
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.leading, Spacing.xl)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Actions

    private func handleItemTap(_ item: ActionMenuItem) {
        let result = ActionMenuCalculations.resolveMenuAction(item: item, expandedKey: expandedItemKey)
        switch result {
        case .expand(let key):
            withAnimation(.easeInOut(duration: 0.25)) {
                expandedItemKey = key
            }
        case .collapse:
            withAnimation(.easeInOut(duration: 0.25)) {
                expandedItemKey = nil
            }
        case .executeAction:
            if closeOnItemPress {
                if let action = item.onPress {
                    onSelectAction?(action)
                }
                dismiss()
            } else {
                item.onPress?()
            }
        }
    }

    private func handleSubactionTap(_ subaction: ActionMenuSubitem) {
        if closeOnItemPress {
            onSelectAction?(subaction.onPress)
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
