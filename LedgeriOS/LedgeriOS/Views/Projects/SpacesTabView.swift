import SwiftUI

struct SpacesTabView: View {
    @Environment(ProjectContext.self) private var projectContext

    @State private var searchText = ""
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
        content
            .safeAreaInset(edge: .top) {
                NativeListControlBar(
                    searchText: $searchText,
                    searchPlaceholder: "Search spaces...",
                    onAdd: { showNewSpace = true }
                )
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
        .onReceive(NotificationCenter.default.publisher(for: .createSpace)) { _ in
            showNewSpace = true
        }
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
                    .padding(.vertical, Spacing.sm)
                }
            }
        }
    }
}
