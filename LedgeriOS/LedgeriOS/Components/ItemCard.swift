import SwiftUI

struct ItemCard: View {
    let item: Item

    // External context (varies by caller)
    var priceLabel: String?
    var budgetCategoryName: String?
    var locationLabel: String?
    var indexLabel: String?
    var statusOverride: String?
    var stackSkuAndSource: Bool = true

    // Selection — parent-owned, nil means no selector
    var isSelected: Binding<Bool>?

    // Bookmark
    var onBookmarkPress: (() -> Void)?

    // Actions
    var onPress: (() -> Void)?
    var menuItems: [ActionMenuItem] = []

    // Warning
    var warningMessage: String?

    private var badges: [CardBadge] {
        ItemCardCalculations.badgeItems(
            statusLabel: statusOverride ?? item.status,
            budgetCategoryName: budgetCategoryName,
            indexLabel: indexLabel
        )
    }

    private var metadata: [String] {
        ItemCardCalculations.metadataLines(
            name: item.name,
            sku: item.sku,
            sourceLabel: item.source,
            locationLabel: locationLabel,
            priceLabel: priceLabel,
            stackSkuAndSource: stackSkuAndSource
        )
    }

    var body: some View {
        let base = Card(padding: 0, isSelected: isSelected?.wrappedValue ?? false) {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(
                    isSelected: isSelected,
                    selectionLabel: item.displayName,
                    badges: badges,
                    bookmarked: item.bookmark == true,
                    onBookmarkPress: onBookmarkPress,
                    warningMessage: warningMessage,
                    menuTitle: item.displayName,
                    menuItems: menuItems
                )
                contentArea
            }
        }
        .contentShape(Rectangle())

        if let onPress {
            base.onTapGesture { onPress() }
        } else {
            base
        }
    }

    // MARK: - Content Area

    private var contentArea: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(item.displayName)
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
        if let url = ItemCardCalculations.thumbnailUrl(from: item.images?.first?.url) {
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
            .clipShape(RoundedRectangle(cornerRadius: Dimensions.thumbnailRadius))
            .background(BrandColors.surfaceTertiary)
            .overlay(
                RoundedRectangle(cornerRadius: Dimensions.thumbnailRadius)
                    .stroke(BrandColors.borderSecondary, lineWidth: Dimensions.borderWidth)
            )
        } else {
            placeholderView(icon: "camera.fill")
        }
    }

    private func placeholderView(icon: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Dimensions.thumbnailRadius)
                .fill(BrandColors.surfaceTertiary)
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(BrandColors.textSecondary)
        }
        .frame(width: 108, height: 108)
        .overlay(
            RoundedRectangle(cornerRadius: Dimensions.thumbnailRadius)
                .stroke(BrandColors.borderSecondary, style: StrokeStyle(lineWidth: Dimensions.borderWidth, dash: [6, 4]))
        )
    }
}

// MARK: - Previews

#Preview("Minimal") {
    ItemCard(item: Item(name: "Gold metal branch decor"))
        .padding(Spacing.screenPadding)
}

#Preview("Full Metadata") {
    ItemCard(
        item: Item(
            name: "Gold metal branch decor",
            source: "Ross",
            sku: "400293670643",
            images: [AttachmentRef(url: "https://picsum.photos/200")]
        ),
        priceLabel: "$10.99",
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
        item: Item(
            name: "Beige/lime green velvet pillow",
            source: "Joon Loloi"
        ),
        priceLabel: "$24.00",
        budgetCategoryName: "Furnishings",
        indexLabel: "1/4",
        statusOverride: "Purchased",
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
        item: Item(
            name: "Blue-gray matte pottery vase",
            source: "Homegoods",
            sku: "373346"
        ),
        priceLabel: "$24.99",
        warningMessage: "Price exceeds budget allocation"
    )
    .padding(Spacing.screenPadding)
}

#Preview("No Image Placeholder") {
    ItemCard(
        item: Item(
            name: "Large area rug 8x10",
            source: "Wayfair"
        ),
        priceLabel: "$299.00",
        isSelected: .constant(false),
        onBookmarkPress: {},
        menuItems: [
            ActionMenuItem(id: "open", label: "Open"),
        ]
    )
    .padding(Spacing.screenPadding)
}
