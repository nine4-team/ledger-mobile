import SwiftUI

struct SpacesTabView: View {
    @Environment(ProjectContext.self) private var projectContext

    @State private var searchText = ""
    @State private var isSearchVisible = false
    @State private var showNewSpace = false

    // MARK: - Computed

    private var filteredSpaces: [Space] {
        let active = projectContext.spaces.filter { $0.isArchived != true }
        if searchText.isEmpty { return active }
        return active.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func itemCount(for space: Space) -> Int {
        projectContext.items.filter { $0.spaceId == space.id }.count
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            content
        }
        .navigationDestination(for: Space.self) { space in
            SpaceDetailView(space: space)
        }
        .sheet(isPresented: $showNewSpace) {
            if let projectId = projectContext.currentProjectId {
                NewSpaceView(context: .project(projectId))
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
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
                        ? "No spaces yet"
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
