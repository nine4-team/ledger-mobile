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

    // MARK: - Hierarchical Item Sort Menu

    static func itemSortMenuItems(
        activeSort: ItemSortOption,
        onSelect: @escaping (ItemSortOption) -> Void
    ) -> [ActionMenuItem] {
        [
            ActionMenuItem(
                id: "created",
                label: "Created",
                icon: "calendar",
                subactions: [
                    ActionMenuSubitem(id: ItemSortOption.createdDesc.rawValue, label: "Newest First") { onSelect(.createdDesc) },
                    ActionMenuSubitem(id: ItemSortOption.createdAsc.rawValue, label: "Oldest First") { onSelect(.createdAsc) },
                ],
                selectedSubactionKey: [.createdDesc, .createdAsc].contains(activeSort) ? activeSort.rawValue : nil
            ),
            ActionMenuItem(
                id: "alphabetical",
                label: "Alphabetical",
                icon: "textformat",
                subactions: [
                    ActionMenuSubitem(id: ItemSortOption.alphabeticalAsc.rawValue, label: "A to Z") { onSelect(.alphabeticalAsc) },
                    ActionMenuSubitem(id: ItemSortOption.alphabeticalDesc.rawValue, label: "Z to A") { onSelect(.alphabeticalDesc) },
                ],
                selectedSubactionKey: [.alphabeticalAsc, .alphabeticalDesc].contains(activeSort) ? activeSort.rawValue : nil
            ),
        ]
    }

    // MARK: - Hierarchical Transaction Sort Menu

    static func transactionSortMenuItems(
        activeSort: TransactionSortOption,
        onSelect: @escaping (TransactionSortOption) -> Void
    ) -> [ActionMenuItem] {
        [
            ActionMenuItem(
                id: "purchase-date",
                label: "Purchase Date",
                icon: "calendar",
                subactions: [
                    ActionMenuSubitem(id: TransactionSortOption.dateDesc.rawValue, label: "Newest First") { onSelect(.dateDesc) },
                    ActionMenuSubitem(id: TransactionSortOption.dateAsc.rawValue, label: "Oldest First") { onSelect(.dateAsc) },
                ],
                selectedSubactionKey: [.dateDesc, .dateAsc].contains(activeSort) ? activeSort.rawValue : nil
            ),
            ActionMenuItem(
                id: "created-date",
                label: "Created Date",
                icon: "clock",
                subactions: [
                    ActionMenuSubitem(id: TransactionSortOption.createdDesc.rawValue, label: "Newest First") { onSelect(.createdDesc) },
                    ActionMenuSubitem(id: TransactionSortOption.createdAsc.rawValue, label: "Oldest First") { onSelect(.createdAsc) },
                ],
                selectedSubactionKey: [.createdDesc, .createdAsc].contains(activeSort) ? activeSort.rawValue : nil
            ),
            ActionMenuItem(
                id: "source",
                label: "Source",
                icon: "building.2",
                subactions: [
                    ActionMenuSubitem(id: TransactionSortOption.sourceAsc.rawValue, label: "A to Z") { onSelect(.sourceAsc) },
                    ActionMenuSubitem(id: TransactionSortOption.sourceDesc.rawValue, label: "Z to A") { onSelect(.sourceDesc) },
                ],
                selectedSubactionKey: [.sourceAsc, .sourceDesc].contains(activeSort) ? activeSort.rawValue : nil
            ),
            ActionMenuItem(
                id: "price",
                label: "Price",
                icon: "dollarsign.circle",
                subactions: [
                    ActionMenuSubitem(id: TransactionSortOption.amountDesc.rawValue, label: "Highest First") { onSelect(.amountDesc) },
                    ActionMenuSubitem(id: TransactionSortOption.amountAsc.rawValue, label: "Lowest First") { onSelect(.amountAsc) },
                ],
                selectedSubactionKey: [.amountDesc, .amountAsc].contains(activeSort) ? activeSort.rawValue : nil
            ),
        ]
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
