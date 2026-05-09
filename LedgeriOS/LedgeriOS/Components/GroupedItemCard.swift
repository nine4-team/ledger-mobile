import SwiftUI

// MARK: - Item Card Data

struct ItemCardData: Identifiable, Sendable {
    let id: String
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
    var warningMessage: String?
    var isSelected: Bool = false
    var menuItems: [ActionMenuItem] = []
}

// MARK: - Grouped Item Card

struct GroupedItemCard<ExpandedContent: View>: View {
    let name: String
    var thumbnailUrl: String?
    var thumbnailSmUrl: String?
    var countLabel: String?
    var totalLabel: String?
    var sku: String?
    var sourceLabel: String?
    var spaceName: String?
    var locationLabel: String?
    var priceLabel: String?
    var microcopyWhenCollapsed: String? = "View All"
    var isExpanded: Binding<Bool>?
    var defaultExpanded: Bool = false
    var isSelected: Binding<Bool>?
    var onSelectedChange: ((Bool) -> Void)?
    var onPress: (() -> Void)?
    var itemCount: Int = 0
    @ViewBuilder var expandedContent: () -> ExpandedContent

    @State private var internalExpanded: Bool

    init(
        name: String,
        thumbnailUrl: String? = nil,
        thumbnailSmUrl: String? = nil,
        countLabel: String? = nil,
        totalLabel: String? = nil,
        sku: String? = nil,
        sourceLabel: String? = nil,
        spaceName: String? = nil,
        locationLabel: String? = nil,
        priceLabel: String? = nil,
        microcopyWhenCollapsed: String? = "View All",
        isExpanded: Binding<Bool>? = nil,
        defaultExpanded: Bool = false,
        isSelected: Binding<Bool>? = nil,
        onSelectedChange: ((Bool) -> Void)? = nil,
        onPress: (() -> Void)? = nil,
        itemCount: Int = 0,
        @ViewBuilder expandedContent: @escaping () -> ExpandedContent
    ) {
        self.name = name
        self.thumbnailUrl = thumbnailUrl
        self.thumbnailSmUrl = thumbnailSmUrl
        self.countLabel = countLabel
        self.totalLabel = totalLabel
        self.sku = sku
        self.sourceLabel = sourceLabel
        self.spaceName = spaceName
        self.locationLabel = locationLabel
        self.priceLabel = priceLabel
        self.microcopyWhenCollapsed = microcopyWhenCollapsed
        self.isExpanded = isExpanded
        self.defaultExpanded = defaultExpanded
        self.isSelected = isSelected
        self.onSelectedChange = onSelectedChange
        self.onPress = onPress
        self.itemCount = itemCount
        self._internalExpanded = State(initialValue: defaultExpanded)
        self.expandedContent = expandedContent
    }

    private var expanded: Bool {
        isExpanded?.wrappedValue ?? internalExpanded
    }

    private func setExpanded(_ value: Bool) {
        if let binding = isExpanded {
            binding.wrappedValue = value
        } else {
            internalExpanded = value
        }
    }

    private var selected: Bool {
        isSelected?.wrappedValue ?? false
    }

    var body: some View {
        Card(padding: 0, isSelected: selected) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    if let onPress {
                        onPress()
                    } else {
                        withAnimation { setExpanded(!expanded) }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        headerRow
                        if !expanded {
                            collapsedContent
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if expanded && itemCount > 0 {
                    VStack(spacing: Spacing.cardListGap) {
                        expandedContent()
                    }
                    .padding(.horizontal, Spacing.cardPadding / 2)
                    .padding(.vertical, Spacing.sm)
                }
            }
        }
        .animation(.default, value: expanded)
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: Spacing.sm) {
            if isSelected != nil {
                CardSelectorButton(
                    isSelected: selected,
                    label: name,
                    action: {
                        let newValue = !selected
                        isSelected?.wrappedValue = newValue
                        onSelectedChange?(newValue)
                    }
                )
            }

            Spacer()

            HStack(spacing: Spacing.sm) {
                if let countLabel {
                    Badge(text: countLabel, color: BrandColors.primary)
                }

                if !expanded, let microcopyWhenCollapsed {
                    Text(microcopyWhenCollapsed)
                        .font(Typography.caption.italic())
                        .foregroundStyle(BrandColors.textSecondary)
                }

                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BrandColors.textTertiary)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .overlay(alignment: .bottom) {
            CardDivider()
        }
    }

    // MARK: - Collapsed Content

    private var collapsedContent: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            FindableText(name)
                .font(Typography.h3)
                .foregroundStyle(BrandColors.textPrimary)
                .lineLimit(3)

            HStack(alignment: .top, spacing: Spacing.md) {
                thumbnail

                VStack(alignment: .leading, spacing: 6) {
                    if let displayPrice = priceLabel ?? totalLabel, !displayPrice.isEmpty {
                        FindableText(displayPrice)
                            .font(Typography.h3)
                            .foregroundStyle(BrandColors.textPrimary)
                    }
                    if let sourceLabel, !sourceLabel.isEmpty {
                        FindableText("Source: \(sourceLabel)")
                            .font(Typography.small)
                            .foregroundStyle(BrandColors.textSecondary)
                    }
                    if let sku, !sku.isEmpty {
                        FindableText("SKU: \(sku)")
                            .font(Typography.small)
                            .foregroundStyle(BrandColors.textSecondary)
                    }
                    if let spaceName, !spaceName.isEmpty {
                        FindableText("Space: \(spaceName)")
                            .font(Typography.small)
                            .fontWeight(.bold)
                            .foregroundStyle(BrandColors.primary)
                            .lineLimit(2)
                    }
                    if let locationLabel, !locationLabel.isEmpty {
                        FindableText("Location: \(locationLabel)")
                            .font(Typography.small)
                            .foregroundStyle(BrandColors.textSecondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(Spacing.lg)
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnail: some View {
        if let thumbnailUrl, !thumbnailUrl.isEmpty {
            FirebaseImage(url: thumbnailUrl, thumbnailUrl: thumbnailSmUrl, contentMode: .fill) {
                ProgressView()
                    .frame(width: 108, height: 108)
            }
            .frame(width: 108, height: 108)
            .clipShape(RoundedRectangle(cornerRadius: Dimensions.thumbnailRadius))
            .background(BrandColors.surfaceTertiary, in: RoundedRectangle(cornerRadius: Dimensions.thumbnailRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Dimensions.thumbnailRadius)
                    .stroke(BrandColors.borderSecondary, lineWidth: Dimensions.borderWidth)
            )
        } else {
            thumbnailPlaceholder
        }
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Dimensions.thumbnailRadius)
                .fill(BrandColors.surfaceTertiary)
            Image(systemName: "photo")
                .font(.system(size: 24))
                .foregroundStyle(BrandColors.textTertiary)
        }
        .frame(width: 108, height: 108)
        .overlay(
            RoundedRectangle(cornerRadius: Dimensions.thumbnailRadius)
                .stroke(BrandColors.borderSecondary, lineWidth: Dimensions.borderWidth)
        )
    }
}

// MARK: - Previews

#Preview("Collapsed") {
    GroupedItemCard(
        name: "Living Room Furniture",
        thumbnailUrl: "https://picsum.photos/200",
        countLabel: "×3",
        totalLabel: "$1,450",
        sku: "SF-001",
        sourceLabel: "West Elm",
        spaceName: "Living Room",
        priceLabel: "$1,450",
        itemCount: 3
    ) {
        Text("Items go here")
    }
    .padding(Spacing.screenPadding)
}

#Preview("Collapsed - No Image") {
    GroupedItemCard(
        name: "Living Room Furniture",
        countLabel: "×3",
        totalLabel: "$1,450",
        sourceLabel: "West Elm",
        priceLabel: "$1,450",
        itemCount: 3
    ) {
        Text("Items go here")
    }
    .padding(Spacing.screenPadding)
}

#Preview("Expanded") {
    @Previewable @State var expanded = true

    GroupedItemCard(
        name: "Kitchen Appliances",
        thumbnailUrl: "https://picsum.photos/201",
        countLabel: "×3",
        totalLabel: "$1,450",
        priceLabel: "$1,450",
        isExpanded: $expanded,
        itemCount: 3
    ) {
        ForEach(["Blender", "Toaster", "Mixer"], id: \.self) { name in
            ItemCard(
                item: Item(name: name),
                priceLabel: "$99"
            )
        }
    }
    .padding(Spacing.screenPadding)
}

#Preview("With Selection") {
    @Previewable @State var selected = false

    GroupedItemCard(
        name: "Bedroom Set",
        countLabel: "×3",
        totalLabel: "$1,450",
        priceLabel: "$1,450",
        isSelected: $selected,
        itemCount: 3
    ) {
        Text("Items go here")
    }
    .padding(Spacing.screenPadding)
}
