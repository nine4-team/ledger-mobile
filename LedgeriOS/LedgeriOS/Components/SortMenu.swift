import SwiftUI

struct SortMenu: View {
    @Binding var isPresented: Bool
    let sortOptions: [ActionMenuItem]
    var title: String = "Sort By"

    var body: some View {
        EmptyView()
            .sheet(isPresented: $isPresented) {
                ActionMenuSheet(
                    title: title,
                    items: sortOptions,
                    closeOnItemPress: true
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
    }

    static func sortMenuItems(
        activeSort: ItemSortOption,
        onSelect: @escaping (ItemSortOption) -> Void
    ) -> [ActionMenuItem] {
        ItemSortOption.allCases.map { option in
            ActionMenuItem(
                id: option.rawValue,
                label: sortLabel(for: option),
                icon: activeSort == option ? "checkmark" : nil,
                onPress: { onSelect(option) }
            )
        }
    }

    private static func sortLabel(for option: ItemSortOption) -> String {
        switch option {
        case .createdDesc: return "Newest First"
        case .createdAsc: return "Oldest First"
        case .alphabeticalAsc: return "A to Z"
        case .alphabeticalDesc: return "Z to A"
        }
    }
}

// MARK: - Previews

#Preview("Sort Menu") {
    @Previewable @State var show = true

    SortMenu(
        isPresented: $show,
        sortOptions: SortMenu.sortMenuItems(
            activeSort: .createdDesc,
            onSelect: { _ in }
        )
    )
}
