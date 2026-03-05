import SwiftUI

struct NativeListControlBar<SelectAllContent: View, SortContent: View, FilterContent: View>: View {
    @Binding var searchText: String
    var searchPlaceholder: String = "Search..."
    var onAdd: (() -> Void)?
    @ViewBuilder var selectAll: () -> SelectAllContent
    @ViewBuilder var sortMenu: () -> SortContent
    @ViewBuilder var filterMenu: () -> FilterContent

    @State private var isSearchExpanded = false
    @State private var isSearchFocused = false

    init(
        searchText: Binding<String>,
        searchPlaceholder: String = "Search...",
        onAdd: (() -> Void)? = nil,
        @ViewBuilder selectAll: @escaping () -> SelectAllContent = { EmptyView() },
        @ViewBuilder sortMenu: @escaping () -> SortContent = { EmptyView() },
        @ViewBuilder filterMenu: @escaping () -> FilterContent = { EmptyView() }
    ) {
        self._searchText = searchText
        self.searchPlaceholder = searchPlaceholder
        self.onAdd = onAdd
        self.selectAll = selectAll
        self.sortMenu = sortMenu
        self.filterMenu = filterMenu
    }

    var body: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: 0) {
                barItem(label: "Select") {
                    selectAll()
                }

                barItem(label: "Search") {
                    Button {
                        withAnimation(.spring(duration: 0.3)) {
                            isSearchExpanded.toggle()
                            if !isSearchExpanded {
                                isSearchFocused = false
                            }
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(isSearchExpanded ? BrandColors.primary : .secondary)
                    }
                    .tint(isSearchExpanded ? BrandColors.primary : .secondary)
                    .accessibilityLabel("Search")
                }

                barItem(label: "Sort") {
                    sortMenu()
                }

                barItem(label: "Filter") {
                    filterMenu()
                }

                if let onAdd {
                    barItem(label: "Add") {
                        Button(action: onAdd) {
                            Image(systemName: "plus")
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                        }
                        .tint(.secondary)
                        .accessibilityLabel("Add")
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, 14)
            .modifier(CapsuleGlassModifier())

            if isSearchExpanded {
                SearchField(
                    text: $searchText,
                    placeholder: searchPlaceholder,
                    isFocused: $isSearchFocused,
                    onDismiss: {
                        withAnimation(.spring(duration: 0.3)) {
                            isSearchExpanded = false
                            isSearchFocused = false
                        }
                    }
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.vertical, Spacing.sm)
        .onChange(of: isSearchExpanded) { _, expanded in
            if expanded {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isSearchFocused = true
                }
            }
        }
    }

    private func barItem<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 2) {
            content()
                .tint(.secondary)
                .imageScale(.large)
                .frame(height: 24)
                .frame(minWidth: 44)
                .contentShape(Rectangle())
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Glass Material

struct CapsuleGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(in: .capsule)
        } else {
            content
                .background(.thickMaterial)
                .clipShape(Capsule(style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        }
    }
}

// MARK: - Previews

#Preview("Full (Items/Transactions)") {
    @Previewable @State var sort = ItemSortOption.createdDesc
    @Previewable @State var filter = ItemFilterOption.all
    @Previewable @State var allSelected = false

    NativeListControlBar(
        searchText: .constant(""),
        searchPlaceholder: "Search items...",
        onAdd: {}
    ) {
        Button { allSelected.toggle() } label: {
            SelectorCircle(isSelected: allSelected, indicator: .check)
        }
        .buttonStyle(.plain)
    } sortMenu: {
        Menu {
            Picker("Sort", selection: $sort) {
                ForEach(ItemSortOption.allCases, id: \.self) { option in
                    Text(ListFilterSortCalculations.sortLabel(for: option)).tag(option)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .foregroundStyle(sort != .createdDesc ? BrandColors.primary : .secondary)
        }
    } filterMenu: {
        Menu {
            Picker("Filter", selection: $filter) {
                ForEach(ItemFilterOption.allCases, id: \.self) { option in
                    Text(ListFilterSortCalculations.filterLabel(for: option)).tag(option)
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .foregroundStyle(filter != .all ? BrandColors.primary : .secondary)
        }
    }
}
