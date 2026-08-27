import SwiftUI

struct InventorySpacesSubTab: View {
    @Environment(InventoryContext.self) private var inventoryContext

    @State private var searchText = ""
    @State private var showNewSpace = false
    @State private var selectedSpaceId: String?
    @State private var showSpaceDetail = false

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
            .scrollContentTopFade()
            .safeAreaInset(edge: .top, spacing: 0) {
                SearchControlBar(
                    searchText: $searchText,
                    searchPlaceholder: "Search spaces...",
                    onAdd: { showNewSpace = true }
                )
            }
            .navigationDestination(isPresented: $showSpaceDetail) {
                if let selectedSpaceId,
                   let space = inventoryContext.spaces.first(where: { $0.id == selectedSpaceId }) {
                    SpaceDetailView(space: space, projectId: nil)
                } else {
                    ContentUnavailableView("Space Unavailable", systemImage: "square.grid.2x2")
                }
            }
        .adaptivePresentation(isPresented: $showNewSpace, style: .form) {
            NewSpaceView(context: .inventory)
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
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: Dimensions.cardMinWidth), spacing: Spacing.cardListGap)],
                    alignment: .leading,
                    spacing: Spacing.cardListGap
                ) {
                    ForEach(filteredSpaces) { space in
                        if let spaceId = space.id {
                            Button {
                                PerformanceDiagnostics.shared.event(
                                    "SpaceCardTapped",
                                    kind: "inventory"
                                )
                                selectedSpaceId = spaceId
                                showSpaceDetail = true
                            } label: {
                                SpaceCard(
                                    space: space,
                                    itemCount: itemCount(for: space)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.sm)
            }
        }
    }
}
