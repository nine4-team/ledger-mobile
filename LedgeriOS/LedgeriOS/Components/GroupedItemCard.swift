import SwiftUI

struct GroupedItemCard<ExpandedContent: View>: View {
    let name: String
    var thumbnailUrl: String?
    var countLabel: String?
    var totalLabel: String?
    var isExpanded: Binding<Bool>?
    var defaultExpanded: Bool = false
    var isSelected: Binding<Bool>?
    var onSelectedChange: ((Bool) -> Void)?
    var onPress: (() -> Void)?
    @ViewBuilder let expandedContent: () -> ExpandedContent

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
        @ViewBuilder expandedContent: @escaping () -> ExpandedContent
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
        self.expandedContent = expandedContent
        self._internalExpanded = State(initialValue: defaultExpanded)
    }

    private var expanded: Bool {
        get { isExpanded?.wrappedValue ?? internalExpanded }
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

                if expanded {
                    Divider()
                        .padding(.horizontal, Spacing.lg)

                    expandedContent()
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

// MARK: - Convenience init without expanded content

extension GroupedItemCard where ExpandedContent == EmptyView {
    init(
        name: String,
        thumbnailUrl: String? = nil,
        countLabel: String? = nil,
        totalLabel: String? = nil,
        isExpanded: Binding<Bool>? = nil,
        defaultExpanded: Bool = false,
        isSelected: Binding<Bool>? = nil,
        onSelectedChange: ((Bool) -> Void)? = nil,
        onPress: (() -> Void)? = nil
    ) {
        self.init(
            name: name,
            thumbnailUrl: thumbnailUrl,
            countLabel: countLabel,
            totalLabel: totalLabel,
            isExpanded: isExpanded,
            defaultExpanded: defaultExpanded,
            isSelected: isSelected,
            onSelectedChange: onSelectedChange,
            onPress: onPress,
            expandedContent: { EmptyView() }
        )
    }
}

// MARK: - Previews

#Preview("Collapsed") {
    GroupedItemCard(
        name: "Living Room Furniture",
        countLabel: "3 items",
        totalLabel: "$1,450"
    ) {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(["Sofa", "Coffee Table", "Lamp"], id: \.self) { item in
                Text(item)
                    .font(Typography.body)
                    .padding(Spacing.lg)
                if item != "Lamp" {
                    Divider().padding(.horizontal, Spacing.lg)
                }
            }
        }
    }
    .padding(Spacing.screenPadding)
}

#Preview("Expanded") {
    @Previewable @State var expanded = true

    GroupedItemCard(
        name: "Kitchen Appliances",
        countLabel: "2 items",
        totalLabel: "$780",
        isExpanded: $expanded
    ) {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(["Blender", "Toaster"], id: \.self) { item in
                Text(item)
                    .font(Typography.body)
                    .padding(Spacing.lg)
            }
        }
    }
    .padding(Spacing.screenPadding)
}

#Preview("With Selection") {
    @Previewable @State var selected = true

    GroupedItemCard(
        name: "Bedroom Set",
        countLabel: "4 items",
        totalLabel: "$2,100",
        isSelected: $selected
    ) {
        Text("Item cards would go here")
            .padding(Spacing.lg)
    }
    .padding(Spacing.screenPadding)
}
