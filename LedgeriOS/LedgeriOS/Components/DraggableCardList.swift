import SwiftUI

/// Generic drag-to-reorder list for settings screens (category reordering, template reordering).
/// Uses `List` with `.onMove` for native drag-to-reorder support.
struct DraggableCardList<T: Identifiable>: View {
    @Binding var items: [T]
    let content: (T) -> String
    var rightContent: ((T) -> AnyView)?
    var onReorder: (([T]) -> Void)?
    var isItemDraggable: ((T) -> Bool)?

    @State private var editMode: EditMode = .active

    var body: some View {
        List {
            ForEach(items) { item in
                DraggableCard(
                    title: content(item),
                    isDisabled: !(isItemDraggable?(item) ?? true)
                ) {
                    if let rightContent {
                        rightContent(item)
                    }
                }
                .listRowInsets(EdgeInsets(
                    top: Spacing.xs,
                    leading: Spacing.screenPadding,
                    bottom: Spacing.xs,
                    trailing: Spacing.screenPadding
                ))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .moveDisabled(!(isItemDraggable?(item) ?? true))
            }
            .onMove(perform: moveItems)
        }
        .listStyle(.plain)
        .environment(\.editMode, $editMode)
    }

    private func moveItems(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        onReorder?(items)
    }
}

// MARK: - Convenience Init (String title only)

extension DraggableCardList where T: Identifiable {
    init(
        items: Binding<[T]>,
        titleKeyPath: KeyPath<T, String>,
        onReorder: (([T]) -> Void)? = nil,
        isItemDraggable: ((T) -> Bool)? = nil
    ) {
        self._items = items
        self.content = { $0[keyPath: titleKeyPath] }
        self.rightContent = nil
        self.onReorder = onReorder
        self.isItemDraggable = isItemDraggable
    }
}

// MARK: - Preview Model

private struct PreviewCategory: Identifiable {
    let id: String
    let name: String
    var isArchived: Bool = false
}

// MARK: - Previews

#Preview("Reorderable List") {
    @Previewable @State var categories = [
        PreviewCategory(id: "1", name: "Materials"),
        PreviewCategory(id: "2", name: "Furnishings"),
        PreviewCategory(id: "3", name: "Labor"),
        PreviewCategory(id: "4", name: "Fixtures"),
        PreviewCategory(id: "5", name: "Archived Category", isArchived: true),
    ]

    NavigationStack {
        DraggableCardList(
            items: $categories,
            content: { $0.name },
            rightContent: { category in
                AnyView(
                    Group {
                        if category.isArchived {
                            Badge(text: "Archived")
                        }
                    }
                )
            },
            onReorder: { newOrder in
                print("New order: \(newOrder.map(\.name))")
            },
            isItemDraggable: { !$0.isArchived }
        )
        .navigationTitle("Budget Categories")
    }
}
