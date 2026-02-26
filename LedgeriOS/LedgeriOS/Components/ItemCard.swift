import SwiftUI

struct ItemCard: View {
    let name: String
    var sku: String?
    var sourceLabel: String?
    var locationLabel: String?
    var notes: String?
    var priceLabel: String?
    var indexLabel: String?
    var statusLabel: String?
    var budgetCategoryName: String?
    var thumbnailUri: String?
    var stackSkuAndSource: Bool = true

    // Selection
    var isSelected: Binding<Bool>?
    var defaultSelected: Bool = false

    // Bookmark
    var bookmarked: Bool = false
    var onBookmarkPress: (() -> Void)?

    // Actions
    var onPress: (() -> Void)?
    var menuItems: [ActionMenuItem] = []

    // Warning
    var warningMessage: String?

    @State private var internalSelected: Bool
    @State private var showMenu = false
    @State private var menuPendingAction: (() -> Void)?

    init(
        name: String,
        sku: String? = nil,
        sourceLabel: String? = nil,
        locationLabel: String? = nil,
        notes: String? = nil,
        priceLabel: String? = nil,
        indexLabel: String? = nil,
        statusLabel: String? = nil,
        budgetCategoryName: String? = nil,
        thumbnailUri: String? = nil,
        stackSkuAndSource: Bool = true,
        isSelected: Binding<Bool>? = nil,
        defaultSelected: Bool = false,
        bookmarked: Bool = false,
        onBookmarkPress: (() -> Void)? = nil,
        onPress: (() -> Void)? = nil,
        menuItems: [ActionMenuItem] = [],
        warningMessage: String? = nil
    ) {
        self.name = name
        self.sku = sku
        self.sourceLabel = sourceLabel
        self.locationLabel = locationLabel
        self.notes = notes
        self.priceLabel = priceLabel
        self.indexLabel = indexLabel
        self.statusLabel = statusLabel
        self.budgetCategoryName = budgetCategoryName
        self.thumbnailUri = thumbnailUri
        self.stackSkuAndSource = stackSkuAndSource
        self.isSelected = isSelected
        self.defaultSelected = defaultSelected
        self.bookmarked = bookmarked
        self.onBookmarkPress = onBookmarkPress
        self.onPress = onPress
        self.menuItems = menuItems
        self.warningMessage = warningMessage
        self._internalSelected = State(initialValue: defaultSelected)
    }

    private var currentSelected: Bool {
        ItemCardCalculations.resolvedSelected(
            externalSelected: isSelected?.wrappedValue,
            internalSelected: internalSelected
        )
    }

    private var showSelector: Bool {
        isSelected != nil
    }

    private var badges: [ItemCardCalculations.BadgeItem] {
        ItemCardCalculations.badgeItems(
            statusLabel: statusLabel,
            budgetCategoryName: budgetCategoryName,
            indexLabel: indexLabel
        )
    }

    private var metadata: [String] {
        ItemCardCalculations.metadataLines(
            name: name,
            sku: sku,
            sourceLabel: sourceLabel,
            locationLabel: locationLabel,
            priceLabel: priceLabel,
            stackSkuAndSource: stackSkuAndSource
        )
    }

    var body: some View {
        Button {
            if let onPress {
                onPress()
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                headerRow
                contentArea
            }
        }
        .buttonStyle(ItemCardButtonStyle())
        .disabled(onPress == nil)
        .padding(0)
        .background(BrandColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Dimensions.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Dimensions.cardRadius)
                .stroke(
                    currentSelected ? BrandColors.primary : BrandColors.border,
                    lineWidth: Dimensions.borderWidth
                )
        )
        .sheet(isPresented: $showMenu, onDismiss: {
            menuPendingAction?()
            menuPendingAction = nil
        }) {
            ActionMenuSheet(
                title: name,
                items: menuItems,
                onSelectAction: { action in
                    menuPendingAction = action
                    showMenu = false
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: Spacing.sm) {
            if showSelector {
                Button {
                    toggleSelection()
                } label: {
                    SelectorCircle(isSelected: currentSelected, indicator: .dot)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if !badges.isEmpty {
                HStack(spacing: Spacing.sm) {
                    ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
                        Badge(text: badge.text, color: badge.color)
                    }
                }
            }

            if let warningMessage {
                Button {
                    // Could show alert
                } label: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(StatusColors.badgeWarning)
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
            }

            if onBookmarkPress != nil {
                Button {
                    onBookmarkPress?()
                } label: {
                    Image(systemName: bookmarked ? "bookmark.fill" : "bookmark")
                        .foregroundStyle(bookmarked ? StatusColors.missedText : BrandColors.primary)
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
            }

            if !menuItems.isEmpty {
                Button {
                    showMenu = true
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(BrandColors.textSecondary)
                        .font(.system(size: 18))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .overlay(alignment: .bottom) {
            Divider()
                .foregroundStyle(BrandColors.borderSecondary)
        }
    }

    // MARK: - Content Area

    private var contentArea: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(name)
                .font(Typography.h3)
                .foregroundStyle(BrandColors.textPrimary)
                .lineLimit(3)

            HStack(alignment: .top, spacing: Spacing.md) {
                thumbnailView

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(metadata.enumerated()), id: \.offset) { index, line in
                        if index == 0 {
                            Text(line)
                                .font(Typography.h3)
                                .foregroundStyle(BrandColors.textPrimary)
                        } else {
                            Text(line)
                                .font(Typography.small)
                                .foregroundStyle(BrandColors.textSecondary)
                                .lineLimit(2)
                        }
                    }

                    if let notes, !notes.isEmpty {
                        Text(notes)
                            .font(Typography.small)
                            .italic()
                            .foregroundStyle(BrandColors.textSecondary)
                            .lineLimit(2)
                    }
                }
            }

            if let warningMessage, !warningMessage.isEmpty {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                    Text(warningMessage)
                        .font(Typography.small)
                }
                .foregroundStyle(StatusColors.badgeWarning)
            }
        }
        .padding(Spacing.lg)
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnailView: some View {
        if let url = ItemCardCalculations.thumbnailUrl(from: thumbnailUri) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    placeholderView(icon: "photo.badge.exclamationmark")
                case .empty:
                    ProgressView()
                        .frame(width: 108, height: 108)
                @unknown default:
                    placeholderView(icon: "photo")
                }
            }
            .frame(width: 108, height: 108)
            .clipShape(RoundedRectangle(cornerRadius: 21))
            .background(BrandColors.surfaceTertiary)
            .overlay(
                RoundedRectangle(cornerRadius: 21)
                    .stroke(BrandColors.borderSecondary, lineWidth: Dimensions.borderWidth)
            )
        } else {
            placeholderView(icon: "camera.fill")
        }
    }

    private func placeholderView(icon: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 21)
                .fill(BrandColors.surfaceTertiary)
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(BrandColors.textSecondary)
        }
        .frame(width: 108, height: 108)
        .overlay(
            RoundedRectangle(cornerRadius: 21)
                .stroke(BrandColors.borderSecondary, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
        )
    }

    // MARK: - Selection

    private func toggleSelection() {
        if let binding = isSelected {
            binding.wrappedValue.toggle()
        } else {
            internalSelected.toggle()
        }
    }
}

// MARK: - Button Style

private struct ItemCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Previews

#Preview("Minimal") {
    ItemCard(name: "Gold metal branch decor")
        .padding(Spacing.screenPadding)
}

#Preview("Full Metadata") {
    ItemCard(
        name: "Gold metal branch decor",
        sku: "400293670643",
        sourceLabel: "Ross",
        priceLabel: "$10.99",
        thumbnailUri: "https://picsum.photos/200",
        isSelected: .constant(false),
        onBookmarkPress: {},
        menuItems: [
            ActionMenuItem(id: "open", label: "Open", icon: "arrow.up.right.square"),
            ActionMenuItem(id: "delete", label: "Delete", icon: "trash", isDestructive: true),
        ]
    )
    .padding(Spacing.screenPadding)
}

#Preview("Selected with Badges") {
    ItemCard(
        name: "Beige/lime green velvet pillow",
        sourceLabel: "Joon Loloi",
        priceLabel: "$24.00",
        indexLabel: "1/4",
        statusLabel: "Purchased",
        budgetCategoryName: "Furnishings",
        isSelected: .constant(true),
        onBookmarkPress: {},
        menuItems: [
            ActionMenuItem(id: "edit", label: "Edit", icon: "pencil"),
        ]
    )
    .padding(Spacing.screenPadding)
}

#Preview("With Warning") {
    ItemCard(
        name: "Blue-gray matte pottery vase",
        sku: "373346",
        sourceLabel: "Homegoods",
        priceLabel: "$24.99",
        warningMessage: "Price exceeds budget allocation"
    )
    .padding(Spacing.screenPadding)
}

#Preview("No Image Placeholder") {
    ItemCard(
        name: "Large area rug 8x10",
        sourceLabel: "Wayfair",
        priceLabel: "$299.00",
        isSelected: .constant(false),
        onBookmarkPress: {},
        menuItems: [
            ActionMenuItem(id: "open", label: "Open"),
        ]
    )
    .padding(Spacing.screenPadding)
}
