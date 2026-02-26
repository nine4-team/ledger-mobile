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
                summaryRow

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

    // MARK: - Summary Row

    private var summaryRow: some View {
        Button {
            if let onPress {
                onPress()
            } else {
                withAnimation { setExpanded(!expanded) }
            }
        } label: {
            HStack(spacing: Spacing.md) {
                if isSelected != nil {
                    SelectorCircle(isSelected: selected, indicator: .check)
                        .onTapGesture {
                            let newValue = !selected
                            isSelected?.wrappedValue = newValue
                            onSelectedChange?(newValue)
                        }
                }

                thumbnail

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(name)
                        .font(Typography.h3)
                        .foregroundStyle(BrandColors.textPrimary)
                        .lineLimit(2)

                    HStack(spacing: Spacing.sm) {
                        if let countLabel {
                            Text(countLabel)
                                .font(Typography.small)
                                .foregroundStyle(BrandColors.textSecondary)
                        }
                        if let totalLabel {
                            Text(totalLabel)
                                .font(Typography.small)
                                .foregroundStyle(BrandColors.textSecondary)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BrandColors.textTertiary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
            .padding(Spacing.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                default:
                    thumbnailPlaceholder
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: Dimensions.buttonRadius))
        } else {
            thumbnailPlaceholder
        }
    }

    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: Dimensions.buttonRadius)
            .fill(BrandColors.inputBackground)
            .frame(width: 56, height: 56)
            .overlay(
                Image(systemName: "photo")
                    .foregroundStyle(BrandColors.textTertiary)
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
        countLabel: "3 items",
        totalLabel: "$1,450",
        items: previewItems
    )
    .padding(Spacing.screenPadding)
}

#Preview("Expanded") {
    @Previewable @State var expanded = true

    GroupedItemCard(
        name: "Kitchen Appliances",
        countLabel: "3 items",
        totalLabel: "$1,450",
        isExpanded: $expanded,
        items: previewItems,
        onItemPress: { item in print("Tapped \(item.name)") }
    )
    .padding(Spacing.screenPadding)
}

#Preview("With Selection") {
    @Previewable @State var selected = true

    GroupedItemCard(
        name: "Bedroom Set",
        countLabel: "3 items",
        totalLabel: "$1,450",
        isSelected: $selected,
        items: previewItems
    )
    .padding(Spacing.screenPadding)
}
