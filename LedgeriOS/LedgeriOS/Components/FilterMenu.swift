import SwiftUI

struct FilterMenu: View {
    @Binding var isPresented: Bool
    let filters: [ActionMenuItem]
    var title: String = "Filter"
    var closeOnItemPress: Bool = false

    var body: some View {
        EmptyView()
            .sheet(isPresented: $isPresented) {
                ActionMenuSheet(
                    title: title,
                    items: filters,
                    closeOnItemPress: closeOnItemPress
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
    }

    static func filterMenuItems(
        activeFilters: Set<ItemFilterOption>,
        onToggle: @escaping (ItemFilterOption) -> Void
    ) -> [ActionMenuItem] {
        ItemFilterOption.allCases.compactMap { option in
            guard option != .all else { return nil }
            return ActionMenuItem(
                id: option.rawValue,
                label: filterLabel(for: option),
                icon: activeFilters.contains(option) ? "checkmark.circle.fill" : "circle",
                onPress: { onToggle(option) }
            )
        }
    }

    /// Single-select filter menu: selecting a filter replaces the current one.
    static func filterMenuItems(
        activeFilter: ItemFilterOption,
        onSelect: @escaping (ItemFilterOption) -> Void
    ) -> [ActionMenuItem] {
        ItemFilterOption.allCases.map { option in
            ActionMenuItem(
                id: option.rawValue,
                label: filterLabel(for: option),
                icon: activeFilter == option ? "checkmark.circle.fill" : "circle",
                onPress: { onSelect(option) }
            )
        }
    }

    private static func filterLabel(for option: ItemFilterOption) -> String {
        switch option {
        case .all: return "All"
        case .bookmarked: return "Bookmarked"
        case .fromInventory: return "From Inventory"
        case .toReturn: return "To Return"
        case .returned: return "Returned"
        case .noSku: return "No SKU"
        case .noName: return "No Name"
        case .noProjectPrice: return "No Project Price"
        case .noImage: return "No Image"
        case .noTransaction: return "No Transaction"
        }
    }
}

// MARK: - Previews

#Preview("Filter Menu") {
    @Previewable @State var show = true

    FilterMenu(
        isPresented: $show,
        filters: FilterMenu.filterMenuItems(
            activeFilters: [.bookmarked, .noSku],
            onToggle: { _ in }
        )
    )
}
