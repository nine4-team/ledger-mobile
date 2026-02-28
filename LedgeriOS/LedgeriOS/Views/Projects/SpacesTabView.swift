import SwiftUI

struct SpacesTabView: View {
    @Environment(ProjectContext.self) private var projectContext

    @State private var searchText = ""
    @State private var isSearchVisible = false

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
            searchBar
            content
        }
        .navigationDestination(for: Space.self) { space in
            SpaceDetailView(space: space)
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                Button {
                    withAnimation {
                        isSearchVisible.toggle()
                        if !isSearchVisible { searchText = "" }
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16))
                        .foregroundStyle(BrandColors.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(BrandColors.buttonSecondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Dimensions.buttonRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: Dimensions.buttonRadius)
                                .stroke(
                                    isSearchVisible ? BrandColors.primary : BrandColors.border,
                                    lineWidth: Dimensions.borderWidth
                                )
                        )
                }
                .buttonStyle(.plain)

                Spacer()
            }

            ListStateControls(
                searchText: $searchText,
                isSearchVisible: isSearchVisible,
                placeholder: "Search spaces..."
            )
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.vertical, Spacing.sm)
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
