import SwiftUI

struct ItemCard: View {
    let item: Item

    // External context (varies by caller)
    var priceLabel: String?
    var budgetCategoryName: String?
    var locationLabel: String?
    var projectName: String?
    var indexLabel: String?
    var statusOverride: String?
    var stackSkuAndSource: Bool = true

    // Selection — parent-owned, nil means no selector
    var isSelected: Binding<Bool>?
    /// Soft accent border + tinted Space metadata line. Used by pickers to flag
    /// items that live in another space (tap-to-move candidates).
    var accent: Bool = false

    // Bookmark
    var onBookmarkPress: (() -> Void)?

    // Actions
    var onPress: (() -> Void)?
    var menuItems: [ActionMenuItem] = []

    // Warning
    var warningMessage: String?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AccountContext.self) private var accountContext

    private var resolvedInvoiceStatus: InvoiceStatus? {
        guard let id = item.id else { return nil }
        return firstNonVoidedInvoiceStatus(forItemId: id, in: accountContext.allInvoices)
    }

    private var badges: [CardBadge] {
        ItemCardCalculations.badgeItems(
            statusLabel: statusOverride ?? item.status?.displayLabel,
            budgetCategoryName: budgetCategoryName,
            indexLabel: indexLabel,
            // Tight on iPhone — only show invoice badge in regular width.
            invoiceStatus: horizontalSizeClass == .regular ? resolvedInvoiceStatus : nil
        )
    }

    private var resolvedSpaceName: String? {
        guard let spaceId = item.spaceId else { return nil }
        return accountContext.allSpaces.first(where: { $0.id == spaceId })?.name
    }

    private var metadata: [String] {
        ItemCardCalculations.metadataLines(
            name: item.name,
            sku: item.sku,
            // Show the immediate source ("Inventory" for items sold from inventory)
            // with a fallback to the original vendor for legacy items written
            // before `currentSource` existed.
            sourceLabel: item.currentSource ?? item.source,
            locationLabel: locationLabel,
            priceLabel: priceLabel,
            projectName: projectName,
            spaceName: resolvedSpaceName,
            stackSkuAndSource: stackSkuAndSource
        )
    }

    var body: some View {
        let base = Card(padding: 0, isSelected: isSelected?.wrappedValue ?? false, accent: accent) {
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
        .findEntity(id: item.id)
        .findMatchHighlight()

        if let onPress {
            base.onTapGesture { onPress() }
        } else {
            base
        }
    }

    // MARK: - Content Area

    private var contentArea: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            FindableText(item.displayName)
                .font(Typography.h3)
                .foregroundStyle(BrandColors.textPrimary)
                .lineLimit(3)

            HStack(alignment: .top, spacing: Spacing.md) {
                thumbnailView

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(metadata.enumerated()), id: \.offset) { index, line in
                        if index == 0 {
                            FindableText(line)
                                .font(Typography.h3)
                                .foregroundStyle(BrandColors.textPrimary)
                        } else {
                            let isSpaceLine = line.hasPrefix("Space: ")
                            let highlightSpaceLine = accent && isSpaceLine
                            FindableText(line)
                                .font(Typography.small)
                                .fontWeight(highlightSpaceLine ? .bold : .regular)
                                .foregroundStyle(
                                    highlightSpaceLine
                                        ? BrandColors.primary
                                        : BrandColors.textSecondary
                                )
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
        if let primaryImage = ItemCardCalculations.primaryImage(from: item.images) {
            FirebaseImage(url: primaryImage.url, thumbnailUrl: primaryImage.thumbnailUrlSm, contentMode: .fill) {
                ProgressView()
                    .frame(width: Dimensions.itemThumbnailSize, height: Dimensions.itemThumbnailSize)
            }
            .frame(width: Dimensions.itemThumbnailSize, height: Dimensions.itemThumbnailSize)
            .clipShape(RoundedRectangle(cornerRadius: Dimensions.thumbnailRadius))
            .background(BrandColors.surfaceTertiary, in: RoundedRectangle(cornerRadius: Dimensions.thumbnailRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Dimensions.thumbnailRadius)
                    .stroke(BrandColors.borderSecondary, lineWidth: Dimensions.borderWidth)
            )
        } else {
            placeholderView(icon: "photo")
        }
    }

    private func placeholderView(icon: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Dimensions.thumbnailRadius)
                .fill(BrandColors.surfaceTertiary)
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(BrandColors.textTertiary)
        }
        .frame(width: Dimensions.itemThumbnailSize, height: Dimensions.itemThumbnailSize)
        .overlay(
            RoundedRectangle(cornerRadius: Dimensions.thumbnailRadius)
                .stroke(BrandColors.borderSecondary, lineWidth: Dimensions.borderWidth)
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
