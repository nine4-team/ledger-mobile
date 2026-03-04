import SwiftUI

struct InventorySpacesSubTab: View {
    @Environment(InventoryContext.self) private var inventoryContext

    @State private var searchText = ""
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
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                SearchControlBar(
                    searchText: $searchText,
                    searchPlaceholder: "Search spaces...",
                    onAdd: { showNewSpace = true }
                )
            }
        .sheet(isPresented: $showNewSpace) {
            Text("New Space — Coming Soon")
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
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
                AdaptiveContentWidth {
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
                    .padding(.bottom, Spacing.sm)
                }
            }
        }
    }
}
