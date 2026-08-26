import SwiftUI

enum ItemFilterScope {
    case inventory
    case project
    case spaceDetail
}

struct ItemFilterChoice: Identifiable, Equatable {
    let id: String
    let label: String
}

/// Grouped multi-select filter menu for item lists. Each facet supports both
/// inclusion and exclusion so users can start from All and remove a value, or
/// start from None and add only the values they want.
struct ItemFilterMenu: View {
    @Binding var isPresented: Bool
    @Binding var filterState: ItemFilterState
    var scope: ItemFilterScope
    var spaces: [ItemFilterChoice] = []
    var sources: [ItemFilterChoice] = []
    var budgetCategories: [ItemFilterChoice] = []
    var purchasedByOptions: [ItemFilterChoice] = []

    var body: some View {
        EmptyView()
            .adaptivePresentation(isPresented: $isPresented, style: .selectionMenu) {
                ActionMenuSheet(
                    title: "Filter",
                    items: buildMenuItems(),
                    closeOnItemPress: false
                )
            }
    }

    private func buildMenuItems() -> [ActionMenuItem] {
        var items: [ActionMenuItem] = []

        items.append(filterGroup(
            id: "item-status",
            label: "Status",
            group: .status,
            options: ItemStatus.allCases.map {
                ItemFilterChoice(id: ItemFilterValues.status($0), label: $0.displayLabel)
            } + [ItemFilterChoice(id: ItemFilterValues.missing, label: "Not Set")]
        ))

        if scope != .spaceDetail {
            items.append(filterGroup(
                id: "item-space",
                label: "Space",
                group: .space,
                options: [ItemFilterChoice(id: ItemFilterValues.missing, label: "No Space")] + spaces
            ))
        }

        items.append(filterGroup(
            id: "item-source",
            label: "Source",
            group: .source,
            options: [ItemFilterChoice(id: ItemFilterValues.missing, label: "No Source")] + sources
        ))

        if scope != .inventory, !budgetCategories.isEmpty {
            items.append(filterGroup(
                id: "item-budget-category",
                label: "Budget Category",
                group: .budgetCategory,
                options: [ItemFilterChoice(id: ItemFilterValues.missing, label: "Uncategorized")] + budgetCategories
            ))
        }

        items.append(filterGroup(
            id: "item-purchased-by",
            label: "Purchased By",
            group: .purchasedBy,
            options: purchasedByOptions
        ))

        items.append(filterGroup(
            id: "item-transaction",
            label: "Transaction",
            group: .transaction,
            options: [
                ItemFilterChoice(id: ItemFilterValues.yes, label: "Has Transaction"),
                ItemFilterChoice(id: ItemFilterValues.no, label: "No Transaction"),
            ]
        ))

        items.append(filterGroup(
            id: "item-bookmark",
            label: "Bookmark",
            group: .bookmark,
            options: yesNoOptions(yes: "Bookmarked", no: "Not Bookmarked")
        ))
        items.append(filterGroup(
            id: "item-image",
            label: "Image",
            group: .image,
            options: yesNoOptions(yes: "Has Image", no: "No Image")
        ))
        items.append(filterGroup(
            id: "item-sku",
            label: "SKU",
            group: .sku,
            options: yesNoOptions(yes: "Has SKU", no: "No SKU")
        ))
        items.append(filterGroup(
            id: "item-name",
            label: "Name",
            group: .name,
            options: yesNoOptions(yes: "Has Name", no: "No Name")
        ))
        items.append(filterGroup(
            id: "item-project-price",
            label: "Project Price",
            group: .projectPrice,
            options: yesNoOptions(yes: "Has Project Price", no: "No Project Price")
        ))

        return items
    }

    private func yesNoOptions(yes: String, no: String) -> [ItemFilterChoice] {
        [
            ItemFilterChoice(id: ItemFilterValues.yes, label: yes),
            ItemFilterChoice(id: ItemFilterValues.no, label: no),
        ]
    }

    private func filterGroup(
        id: String,
        label: String,
        group: ItemFilterGroup,
        options: [ItemFilterChoice]
    ) -> ActionMenuItem {
        let selection = filterState.selection(for: group)
        let availableValues = Set(options.map(\.id))
        var subactions: [ActionMenuSubitem] = [
            ActionMenuSubitem(
                id: "all",
                label: "All",
                icon: selection == .all ? "checkmark.circle.fill" : "circle"
            ) {
                filterState.selectAll(group: group)
            },
            ActionMenuSubitem(
                id: "none",
                label: "None",
                icon: selection == .only([]) ? "checkmark.circle.fill" : "circle"
            ) {
                filterState.selectNone(group: group)
            },
        ]

        subactions.append(contentsOf: options.map { option in
            ActionMenuSubitem(
                id: option.id,
                label: option.label,
                icon: selection.includes(option.id) ? "checkmark.circle.fill" : "circle"
            ) {
                filterState.toggle(
                    group: group,
                    value: option.id,
                    availableValues: availableValues
                )
            }
        })

        return ActionMenuItem(
            id: id,
            label: label,
            subactions: subactions,
            selectionSummary: summary(for: selection, options: options),
            isFilterActive: selection.isActive
        )
    }

    private func summary(
        for selection: ItemFacetSelection,
        options: [ItemFilterChoice]
    ) -> String {
        switch selection {
        case .all:
            return "All"
        case .only(let selected):
            guard !selected.isEmpty else { return "None" }
            if selected.count == 1,
               let label = options.first(where: { selected.contains($0.id) })?.label {
                return label
            }
            return "\(selected.count) of \(options.count)"
        case .allExcept(let excluded):
            let visibleExcluded = options.filter { excluded.contains($0.id) }
            if visibleExcluded.count == 1, let label = visibleExcluded.first?.label {
                return "Except \(label)"
            }
            let selectedCount = max(options.count - visibleExcluded.count, 0)
            return "\(selectedCount) of \(options.count)"
        }
    }
}

#Preview("Item Filter Menu") {
    @Previewable @State var show = true
    @Previewable @State var filters = ItemFilterState()

    ItemFilterMenu(
        isPresented: $show,
        filterState: $filters,
        scope: .project,
        spaces: [
            ItemFilterChoice(id: "living", label: "Living Room"),
            ItemFilterChoice(id: "bedroom", label: "Primary Bedroom"),
        ],
        sources: [
            ItemFilterChoice(id: "1584 design inventory", label: "1584 Design Inventory"),
            ItemFilterChoice(id: "wayfair", label: "Wayfair"),
        ],
        budgetCategories: [
            ItemFilterChoice(id: "furnishings", label: "Furnishings")
        ],
        purchasedByOptions: [
            ItemFilterChoice(id: "client-card", label: "Client"),
            ItemFilterChoice(id: "design-business", label: "Design Business"),
            ItemFilterChoice(id: ItemFilterValues.missing, label: "Not Set"),
        ]
    )
}
