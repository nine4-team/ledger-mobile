import SwiftUI

struct InventorySpacesSubTab: View {
    @Environment(InventoryContext.self) private var inventoryContext

    @State private var searchText = ""
    @State private var isSearchVisible = false
    @State private var showNewSpace = false

    // MARK: - Computed

    private var filteredSpaces: [Space] {
        let active = inventoryContext.spaces.filter { $0.isArchived != true }
        if searchText.isEmpty { return active }
        return active.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func itemCount(for space: Space) -> Int {
        inventoryContext.items.filter { $0.spaceId == space.id }.count
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            content
        }
        .sheet(isPresented: $showNewSpace) {
            Text("New Space — Coming Soon")
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        ListControlBar(
            searchText: $searchText,
            isSearchVisible: $isSearchVisible,
            actions: [
                ControlAction(
                    id: "search",
                    title: "",
                    icon: "magnifyingglass",
                    isActive: isSearchVisible,
                    appearance: .iconOnly
                ) {
                    withAnimation {
                        isSearchVisible.toggle()
                        if !isSearchVisible { searchText = "" }
                    }
                },
                ControlAction(
                    id: "add",
                    title: "",
                    variant: .primary,
                    icon: "plus",
                    appearance: .iconOnly,
                    action: { showNewSpace = true }
                ),
            ],
            searchPlaceholder: "Search spaces..."
        )
        .padding(.horizontal, Spacing.screenPadding)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if filteredSpaces.isEmpty {
            ContentUnavailableView {
                Label(
                    searchText.isEmpty
                        ? "No inventory spaces yet"
                        : "No spaces match your search",
                    systemImage: "square.grid.2x2"
                )
            }
            .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: Spacing.cardListGap) {
                    ForEach(filteredSpaces) { space in
                        NavigationLink(value: space) {
                            SpaceCard(
                                space: space,
                                itemCount: itemCount(for: space),
                                onPress: {}
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.vertical, Spacing.sm)
            }
        }
    }
}
