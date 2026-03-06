import SwiftUI

/// Toolbar appearance variants. `.card` is the active style.
/// `.capsule` and `.plain` are kept as backups for comparison.
enum ControlBarStyle {
    /// Backup: labeled icons in a glass capsule pill
    case capsule
    /// Active: circle glass buttons inside a card container
    case card
    /// Backup: circle glass buttons with no background container
    case plain
}

struct NativeListControlBar<SelectAllContent: View, SortContent: View, FilterContent: View>: View {
    @Binding var searchText: String
    var searchPlaceholder: String = "Search..."
    var onAdd: (() -> Void)?
    var style: ControlBarStyle
    @ViewBuilder var selectAll: () -> SelectAllContent
    @ViewBuilder var sortMenu: () -> SortContent
    @ViewBuilder var filterMenu: () -> FilterContent

    @State private var isSearchExpanded = false
    @State private var isSearchFocused = false

    init(
        searchText: Binding<String>,
        searchPlaceholder: String = "Search...",
        onAdd: (() -> Void)? = nil,
        style: ControlBarStyle = .capsule,
        @ViewBuilder selectAll: @escaping () -> SelectAllContent = { EmptyView() },
        @ViewBuilder sortMenu: @escaping () -> SortContent = { EmptyView() },
        @ViewBuilder filterMenu: @escaping () -> FilterContent = { EmptyView() }
    ) {
        self._searchText = searchText
        self.searchPlaceholder = searchPlaceholder
        self.onAdd = onAdd
        self.style = style
        self.selectAll = selectAll
        self.sortMenu = sortMenu
        self.filterMenu = filterMenu
    }

    private var usesCircleButtons: Bool {
        style == .card || style == .plain
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
            .frame(maxWidth: .infinity)
            .padding(.horizontal, usesCircleButtons ? Spacing.xl : Spacing.lg)
            .padding(.vertical, usesCircleButtons ? Spacing.sm : 14)
            .modifier(containerModifier)

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
        .padding(.vertical, Spacing.sm)
        .onChange(of: isSearchExpanded) { _, expanded in
            if expanded {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isSearchFocused = true
                }
            }
        }
    }

    private var containerModifier: AnyGlassModifier {
        switch style {
        case .capsule:
            AnyGlassModifier(CapsuleGlassModifier())
        case .card:
            AnyGlassModifier(CardGlassModifier())
        case .plain:
            AnyGlassModifier(TransparentModifier())
        }
    }

    @ViewBuilder
    private func barItem<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        if usesCircleButtons {
            circleBarItem { content() }
        } else {
            labeledBarItem(label: label) { content() }
        }
    }

    private func labeledBarItem<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
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

    private func circleBarItem<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .buttonStyle(CircleBarButtonStyle())
            .tint(.secondary)
            .font(.system(size: 16))
            .imageScale(.medium)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .overlay(Circle().stroke(BrandColors.border, lineWidth: Dimensions.borderWidth))
            .frame(maxWidth: .infinity)
    }
}

struct CircleBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Glass Material

struct AnyGlassModifier: ViewModifier {
    private let apply: (Content) -> AnyView

    init<M: ViewModifier>(_ modifier: M) {
        self.apply = { AnyView($0.modifier(modifier)) }
    }

    func body(content: Content) -> some View {
        apply(content)
    }
}

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

struct CircleGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(in: .circle)
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
        }
    }
}

struct TransparentModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

struct CardGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(BrandColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Dimensions.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Dimensions.cardRadius)
                    .stroke(BrandColors.borderSecondary, lineWidth: Dimensions.borderWidth)
            )
            .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
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
