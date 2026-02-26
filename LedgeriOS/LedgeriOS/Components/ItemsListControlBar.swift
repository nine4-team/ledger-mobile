import SwiftUI

struct ItemsListControlBar: View {
    @Binding var searchText: String
    @Binding var isSearchVisible: Bool
    var onSort: () -> Void
    var onFilter: () -> Void
    var onAdd: (() -> Void)?
    var activeFilterCount: Int = 0
    var activeSortLabel: String?

    var body: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                // Search toggle
                Button {
                    withAnimation {
                        isSearchVisible.toggle()
                        if !isSearchVisible { searchText = "" }
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isSearchVisible ? BrandColors.primary : BrandColors.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(isSearchVisible ? BrandColors.primary.opacity(0.1) : BrandColors.buttonSecondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Dimensions.buttonRadius))
                }

                // Sort button
                Button(action: onSort) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 14))
                        if let activeSortLabel {
                            Text(activeSortLabel)
                                .font(Typography.buttonSmall)
                                .lineLimit(1)
                        } else {
                            Text("Sort")
                                .font(Typography.buttonSmall)
                        }
                    }
                    .foregroundStyle(activeSortLabel != nil ? BrandColors.primary : BrandColors.textSecondary)
                    .padding(.horizontal, Spacing.md)
                    .frame(height: 36)
                    .background(activeSortLabel != nil ? BrandColors.primary.opacity(0.1) : BrandColors.buttonSecondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Dimensions.buttonRadius))
                }

                // Filter button
                Button(action: onFilter) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 14))
                        Text("Filter")
                            .font(Typography.buttonSmall)
                        if activeFilterCount > 0 {
                            Text("\(activeFilterCount)")
                                .font(Typography.caption)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(BrandColors.primary)
                                .clipShape(Capsule())
                        }
                    }
                    .foregroundStyle(activeFilterCount > 0 ? BrandColors.primary : BrandColors.textSecondary)
                    .padding(.horizontal, Spacing.md)
                    .frame(height: 36)
                    .background(activeFilterCount > 0 ? BrandColors.primary.opacity(0.1) : BrandColors.buttonSecondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Dimensions.buttonRadius))
                }

                Spacer()

                // Add button
                if let onAdd {
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(BrandColors.primary)
                            .clipShape(RoundedRectangle(cornerRadius: Dimensions.buttonRadius))
                    }
                }
            }

            if isSearchVisible {
                ListStateControls(
                    searchText: $searchText,
                    isSearchVisible: isSearchVisible
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

// MARK: - Previews

#Preview("Default") {
    @Previewable @State var search = ""
    @Previewable @State var showSearch = false

    ItemsListControlBar(
        searchText: $search,
        isSearchVisible: $showSearch,
        onSort: {},
        onFilter: {},
        onAdd: {}
    )
    .padding(Spacing.screenPadding)
}

#Preview("Active Filters") {
    @Previewable @State var search = ""
    @Previewable @State var showSearch = true

    ItemsListControlBar(
        searchText: $search,
        isSearchVisible: $showSearch,
        onSort: {},
        onFilter: {},
        onAdd: {},
        activeFilterCount: 2,
        activeSortLabel: "A-Z"
    )
    .padding(Spacing.screenPadding)
}
