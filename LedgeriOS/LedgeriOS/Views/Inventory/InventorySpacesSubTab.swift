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
            searchBar
            content
        }
        .sheet(isPresented: $showNewSpace) {
            Text("New Space — Coming Soon")
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
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

                Button {
                    showNewSpace = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(BrandColors.primary)
                        .clipShape(RoundedRectangle(cornerRadius: Dimensions.buttonRadius))
                }
                .buttonStyle(.plain)
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
