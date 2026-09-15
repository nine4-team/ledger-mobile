import SwiftUI

/// Original Item card layout with backend-dependent lookups supplied by its owner.
struct ItemCardPresentation<Thumbnail: View>: View {
    let id: String?
    let displayName: String
    let metadata: [String]
    let thumbnail: Thumbnail
    var badges: [CardBadge] = []
    var bookmarked = false

    // Selection — parent-owned, nil means no selector
    var isSelected: Binding<Bool>?
    /// Soft accent border + tinted Space metadata line. Used by pickers to flag
    /// items that live in another space (tap-to-move candidates).
    var accent: Bool = false

    // Bookmark
    var onBookmarkPress: (() -> Void)?

    // Space-photo matching
    var isMarkedInPhoto: Bool = false
    var photoMatchActionTitle: String?
    var isPhotoMatchTarget: Bool = false
    var onPhotoMatchPress: (() -> Void)?

    // Actions
    var onPress: (() -> Void)?
    var menuItems: [ActionMenuItem] = []

    // Warning
    var warningMessage: String?

    var body: some View {
        let base = Card(
            padding: 0,
            isSelected: isSelected?.wrappedValue ?? false,
            accent: accent || isPhotoMatchTarget
        ) {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(
                    isSelected: isSelected,
                    selectionLabel: displayName,
                    badges: badges,
                    bookmarked: bookmarked,
                    onBookmarkPress: onBookmarkPress,
                    warningMessage: warningMessage,
                    menuTitle: displayName,
                    menuItems: menuItems
                )
                contentArea
            }
        }
        .contentShape(Rectangle())
        .findEntity(id: id)
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
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                FindableText(displayName)
                    .font(Typography.h3)
                    .foregroundStyle(BrandColors.textPrimary)
                    .lineLimit(3)

                Spacer(minLength: 0)

                if isMarkedInPhoto {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.green)
                        .accessibilityLabel("Marked in a space photo")
                }
            }

            HStack(alignment: .top, spacing: Spacing.md) {
                thumbnail

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

            if let photoMatchActionTitle, let onPhotoMatchPress {
                Button(action: onPhotoMatchPress) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: isMarkedInPhoto ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                        Text(photoMatchActionTitle)
                    }
                    .font(Typography.label)
                    .foregroundStyle(isPhotoMatchTarget ? .white : BrandColors.primary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 40)
                    .background(isPhotoMatchTarget ? BrandColors.primary : BrandColors.primary.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: Dimensions.buttonRadius))
                }
                .buttonStyle(.plain)
                .accessibilityHint(isMarkedInPhoto
                    ? "Choose a new location for this item's checkmark"
                    : "Select this item, then tap its location in the pinned photo")
            }
        }
        .padding(Spacing.lg)
    }

}

struct ItemCardPlaceholder: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Dimensions.thumbnailRadius)
                .fill(BrandColors.surfaceTertiary)
            Image(systemName: "photo")
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

#if canImport(FirebaseFirestore)
/// Existing app binding. All lookups and image loading retain their old owners.
struct ItemCard: View {
    let item: Item
    var priceLabel: String?
    var budgetCategoryName: String?
    var locationLabel: String?
    var projectName: String?
    var indexLabel: String?
    var statusOverride: String?
    var stackSkuAndSource: Bool = true
    var isSelected: Binding<Bool>?
    var accent: Bool = false
    var onBookmarkPress: (() -> Void)?
    var isMarkedInPhoto: Bool = false
    var photoMatchActionTitle: String?
    var isPhotoMatchTarget: Bool = false
    var onPhotoMatchPress: (() -> Void)?
    var onPress: (() -> Void)?
    var menuItems: [ActionMenuItem] = []
    var warningMessage: String?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AccountContext.self) private var accountContext

    private var resolvedInvoiceStatus: InvoiceStatus? {
        guard let id = item.id else { return nil }
        return PerformanceDiagnostics.shared.measureAggregate("CardLookup", kind: "invoice-status") {
            accountContext.invoiceStatus(forItemId: id)
        }
    }
    private var resolvedSpaceName: String? {
        guard let spaceId = item.spaceId else { return nil }
        return PerformanceDiagnostics.shared.measureAggregate("CardLookup", kind: "space-name") {
            accountContext.spaceName(for: spaceId)
        }
    }
    var body: some View {
        ItemCardPresentation(id: item.id, displayName: item.displayName,
            metadata: ItemCardCalculations.metadataLines(name: item.name, sku: item.sku,
                sourceLabel: item.currentSource ?? item.source, locationLabel: locationLabel,
                priceLabel: priceLabel, projectName: projectName, spaceName: resolvedSpaceName,
                stackSkuAndSource: stackSkuAndSource), thumbnail: thumbnail,
            badges: ItemCardCalculations.badgeItems(statusLabel: statusOverride ?? item.status?.displayLabel,
                budgetCategoryName: budgetCategoryName, indexLabel: indexLabel,
                invoiceStatus: horizontalSizeClass == .regular ? resolvedInvoiceStatus : nil),
            bookmarked: item.bookmark == true, isSelected: isSelected, accent: accent,
            onBookmarkPress: onBookmarkPress, isMarkedInPhoto: isMarkedInPhoto,
            photoMatchActionTitle: photoMatchActionTitle, isPhotoMatchTarget: isPhotoMatchTarget,
            onPhotoMatchPress: onPhotoMatchPress, onPress: onPress, menuItems: menuItems,
            warningMessage: warningMessage)
    }
    @ViewBuilder private var thumbnail: some View {
        if let primaryImage = ItemCardCalculations.primaryImage(from: item.images) {
            FirebaseImage(url: primaryImage.url, thumbnailUrl: primaryImage.thumbnailUrlSm, contentMode: .fill) {
                ProgressView().frame(width: Dimensions.itemThumbnailSize, height: Dimensions.itemThumbnailSize)
            }
            .frame(width: Dimensions.itemThumbnailSize, height: Dimensions.itemThumbnailSize)
            .clipShape(RoundedRectangle(cornerRadius: Dimensions.thumbnailRadius))
            .background(BrandColors.surfaceTertiary, in: RoundedRectangle(cornerRadius: Dimensions.thumbnailRadius))
            .overlay(RoundedRectangle(cornerRadius: Dimensions.thumbnailRadius)
                .stroke(BrandColors.borderSecondary, lineWidth: Dimensions.borderWidth))
        } else { ItemCardPlaceholder() }
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
#endif
