import SwiftUI

// MARK: - Item Card Data

struct ItemCardData: Identifiable {
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
}

// MARK: - Grouped Item Card

struct GroupedItemCard: View {
    let name: String
    var thumbnailUrl: String?
    var countLabel: String?
    var totalLabel: String?
    var sku: String?
    var sourceLabel: String?
    var locationLabel: String?
    var priceLabel: String?
    var microcopyWhenCollapsed: String? = "View All"
    var isExpanded: Binding<Bool>?
    var defaultExpanded: Bool = false
    var isSelected: Binding<Bool>?
    var onSelectedChange: ((Bool) -> Void)?
    var onPress: (() -> Void)?
    var items: [ItemCardData] = []
    var onItemPress: ((ItemCardData) -> Void)?

    @State private var internalExpanded: Bool

    init(
        name: String,
        thumbnailUrl: String? = nil,
        countLabel: String? = nil,
        totalLabel: String? = nil,
        sku: String? = nil,
        sourceLabel: String? = nil,
        locationLabel: String? = nil,
        priceLabel: String? = nil,
        microcopyWhenCollapsed: String? = "View All",
        isExpanded: Binding<Bool>? = nil,
        defaultExpanded: Bool = false,
        isSelected: Binding<Bool>? = nil,
        onSelectedChange: ((Bool) -> Void)? = nil,
        onPress: (() -> Void)? = nil,
        items: [ItemCardData] = [],
        onItemPress: ((ItemCardData) -> Void)? = nil
    ) {
        self.name = name
        self.thumbnailUrl = thumbnailUrl
        self.countLabel = countLabel
        self.totalLabel = totalLabel
        self.sku = sku
        self.sourceLabel = sourceLabel
        self.locationLabel = locationLabel
        self.priceLabel = priceLabel
        self.microcopyWhenCollapsed = microcopyWhenCollapsed
        self.isExpanded = isExpanded
        self.defaultExpanded = defaultExpanded
        self.isSelected = isSelected
        self.onSelectedChange = onSelectedChange
        self.onPress = onPress
        self.items = items
        self.onItemPress = onItemPress
        self._internalExpanded = State(initialValue: defaultExpanded)
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
        Card(padding: 0) {
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

                if expanded && !items.isEmpty {
                    Divider()
                        .padding(.horizontal, Spacing.lg)

                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            ItemCard(
                                name: item.name,
                                sku: item.sku,
                                sourceLabel: item.sourceLabel,
                                locationLabel: item.locationLabel,
                                notes: item.notes,
                                priceLabel: item.priceLabel,
                                indexLabel: item.indexLabel,
                                statusLabel: item.statusLabel,
                                budgetCategoryName: item.budgetCategoryName,
                                thumbnailUri: item.thumbnailUri,
                                onPress: onItemPress.map { callback in { callback(item) } },
                                warningMessage: item.warningMessage
                            )

                            if index < items.count - 1 {
                                Divider()
                                    .padding(.horizontal, Spacing.lg)
                            }
                        }
                    }
                    .padding(.vertical, Spacing.sm)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Dimensions.cardRadius)
                .stroke(selected ? BrandColors.primary : .clear, lineWidth: 2)
        )
        .animation(.default, value: expanded)
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: Spacing.sm) {
            if isSelected != nil {
                SelectorCircle(isSelected: selected, indicator: .dot)
                    .onTapGesture {
                        let newValue = !selected
                        isSelected?.wrappedValue = newValue
                        onSelectedChange?(newValue)
                    }
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
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .overlay(alignment: .bottom) {
            Divider()
                .foregroundStyle(BrandColors.borderSecondary)
        }
    }

    // MARK: - Collapsed Content

    private var collapsedContent: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(name)
                .font(Typography.h3)
                .foregroundStyle(BrandColors.textPrimary)
                .lineLimit(3)

            HStack(alignment: .top, spacing: Spacing.md) {
                thumbnail

                VStack(alignment: .leading, spacing: 6) {
                    if let displayPrice = priceLabel ?? totalLabel, !displayPrice.isEmpty {
                        Text(displayPrice)
                            .font(Typography.h3)
                            .foregroundStyle(BrandColors.textPrimary)
                    }
                    if let sourceLabel, !sourceLabel.isEmpty {
                        Text("Source: \(sourceLabel)")
                            .font(Typography.small)
                            .foregroundStyle(BrandColors.textSecondary)
                    }
                    if let sku, !sku.isEmpty {
                        Text("SKU: \(sku)")
                            .font(Typography.small)
                            .foregroundStyle(BrandColors.textSecondary)
                    }
                    if let locationLabel, !locationLabel.isEmpty {
                        Text("Location: \(locationLabel)")
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
        if let thumbnailUrl, let url = URL(string: thumbnailUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty:
                    ProgressView()
                        .frame(width: 108, height: 108)
                default:
                    thumbnailPlaceholder
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
            thumbnailPlaceholder
        }
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 21)
                .fill(BrandColors.surfaceTertiary)
            Image(systemName: "photo")
                .font(.system(size: 24))
                .foregroundStyle(BrandColors.textSecondary)
        }
        .frame(width: 108, height: 108)
        .overlay(
            RoundedRectangle(cornerRadius: 21)
                .stroke(BrandColors.borderSecondary, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
        )
    }
}

// MARK: - Previews

private let previewItems: [ItemCardData] = [
    ItemCardData(id: "1", name: "Sofa", sku: "SF-001", sourceLabel: "West Elm", priceLabel: "$899"),
    ItemCardData(id: "2", name: "Coffee Table", sourceLabel: "CB2", priceLabel: "$350"),
    ItemCardData(id: "3", name: "Floor Lamp", sku: "FL-042", priceLabel: "$201"),
]

#Preview("Collapsed") {
    GroupedItemCard(
        name: "Living Room Furniture",
        thumbnailUrl: "https://picsum.photos/200",
        countLabel: "×3",
        totalLabel: "$1,450",
        sku: "SF-001",
        sourceLabel: "West Elm",
        priceLabel: "$1,450",
        items: previewItems
    )
    .padding(Spacing.screenPadding)
}

#Preview("Collapsed - No Image") {
    GroupedItemCard(
        name: "Living Room Furniture",
        countLabel: "×3",
        totalLabel: "$1,450",
        sourceLabel: "West Elm",
        priceLabel: "$1,450",
        items: previewItems
    )
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
        items: previewItems,
        onItemPress: { item in print("Tapped \(item.name)") }
    )
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
        items: previewItems
    )
    .padding(Spacing.screenPadding)
}
