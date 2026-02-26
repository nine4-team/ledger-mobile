import SwiftUI

struct TransactionCard: View {
    // Core data
    let id: String
    let source: String
    var amountCents: Int?
    var transactionDate: String?
    var notes: String?

    // Badge data
    var budgetCategoryName: String?
    var transactionType: String?
    var needsReview: Bool = false
    var reimbursementType: String?
    var hasEmailReceipt: Bool = false
    var status: String?
    var itemCount: Int?

    // Selection
    var isSelected: Binding<Bool>?
    var defaultSelected: Bool = false

    // Actions
    var bookmarked: Bool = false
    var onBookmarkPress: (() -> Void)?
    var menuItems: [ActionMenuItem] = []
    var onPress: (() -> Void)?

    @State private var internalSelected: Bool
    @State private var showMenu = false
    @State private var menuPendingAction: (() -> Void)?

    init(
        id: String,
        source: String,
        amountCents: Int? = nil,
        transactionDate: String? = nil,
        notes: String? = nil,
        budgetCategoryName: String? = nil,
        transactionType: String? = nil,
        needsReview: Bool = false,
        reimbursementType: String? = nil,
        hasEmailReceipt: Bool = false,
        status: String? = nil,
        itemCount: Int? = nil,
        isSelected: Binding<Bool>? = nil,
        defaultSelected: Bool = false,
        bookmarked: Bool = false,
        onBookmarkPress: (() -> Void)? = nil,
        menuItems: [ActionMenuItem] = [],
        onPress: (() -> Void)? = nil
    ) {
        self.id = id
        self.source = source
        self.amountCents = amountCents
        self.transactionDate = transactionDate
        self.notes = notes
        self.budgetCategoryName = budgetCategoryName
        self.transactionType = transactionType
        self.needsReview = needsReview
        self.reimbursementType = reimbursementType
        self.hasEmailReceipt = hasEmailReceipt
        self.status = status
        self.itemCount = itemCount
        self.isSelected = isSelected
        self.defaultSelected = defaultSelected
        self.bookmarked = bookmarked
        self.onBookmarkPress = onBookmarkPress
        self.menuItems = menuItems
        self.onPress = onPress
        self._internalSelected = State(initialValue: defaultSelected)
    }

    private var selected: Bool {
        isSelected?.wrappedValue ?? internalSelected
    }

    private func setSelected(_ value: Bool) {
        if let binding = isSelected {
            binding.wrappedValue = value
        } else {
            internalSelected = value
        }
    }

    private var badges: [TransactionCardCalculations.BadgeItem] {
        TransactionCardCalculations.badgeItems(
            transactionType: transactionType,
            reimbursementType: reimbursementType,
            hasEmailReceipt: hasEmailReceipt,
            needsReview: needsReview,
            budgetCategoryName: budgetCategoryName,
            status: status
        )
    }

    private var showSelector: Bool {
        isSelected != nil
    }

    var body: some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                headerRow
                contentSection
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Dimensions.cardRadius)
                .stroke(
                    selected ? BrandColors.primary : Color.clear,
                    lineWidth: selected ? 2 : 0
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onPress?()
        }
        .sheet(isPresented: $showMenu) {
            ActionMenuSheet(
                title: source,
                items: menuItems,
                onSelectAction: { action in
                    menuPendingAction = action
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: showMenu) { _, isShowing in
            if !isShowing, let action = menuPendingAction {
                menuPendingAction = nil
                action()
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerRow: some View {
        HStack(spacing: Spacing.md) {
            if showSelector {
                Button {
                    setSelected(!selected)
                } label: {
                    SelectorCircle(isSelected: selected, indicator: .dot)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Select \(source)")
            }

            Spacer(minLength: 0)

            if !badges.isEmpty {
                badgeRow
            }

            headerActions
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .overlay(alignment: .bottom) {
            Divider().foregroundStyle(BrandColors.border)
        }
    }

    @ViewBuilder
    private var badgeRow: some View {
        // Use a flexible layout that wraps on smaller screens
        FlowLayout(spacing: Spacing.sm) {
            ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
                Badge(text: badge.text, color: badge.color)
            }
        }
    }

    @ViewBuilder
    private var headerActions: some View {
        HStack(spacing: Spacing.sm) {
            if let onBookmarkPress {
                Button {
                    onBookmarkPress()
                } label: {
                    Image(systemName: bookmarked ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 20))
                        .foregroundStyle(bookmarked ? StatusColors.badgeError : BrandColors.primary)
                }
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(bookmarked ? "Remove bookmark" : "Add bookmark")
            }

            if !menuItems.isEmpty {
                Button {
                    showMenu = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20))
                        .foregroundStyle(BrandColors.textSecondary)
                        .rotationEffect(.degrees(90))
                }
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("More options")
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Source + Amount row
            HStack(alignment: .firstTextBaseline) {
                Text(source.isEmpty ? "Transaction \(id.prefix(6))" : source)
                    .font(Typography.body.weight(.semibold))
                    .foregroundStyle(BrandColors.textPrimary)
                    .lineLimit(2)

                Spacer(minLength: Spacing.md)

                Text(TransactionCardCalculations.formattedAmount(amountCents: amountCents, transactionType: transactionType))
                    .font(Typography.body.weight(.bold))
                    .foregroundStyle(BrandColors.textPrimary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }

            // Date + item count row
            HStack(spacing: 0) {
                Text(TransactionCardCalculations.formattedDate(transactionDate))
                    .font(Typography.small.weight(.medium))
                    .foregroundStyle(BrandColors.textSecondary)

                if let count = itemCount {
                    Text(" · ")
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                    Text("\(count) \(count == 1 ? "item" : "items")")
                        .font(Typography.small.weight(.medium))
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }

            // Notes
            if let truncated = TransactionCardCalculations.truncatedNotes(notes) {
                Text(truncated)
                    .font(Typography.small)
                    .italic()
                    .foregroundStyle(BrandColors.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(Spacing.cardPadding)
    }
}

// MARK: - Flow Layout

/// Simple horizontal flow layout that wraps badges to the next line.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private struct ArrangementResult {
        var size: CGSize
        var positions: [CGPoint]
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> ArrangementResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalWidth = max(totalWidth, x - spacing)
            totalHeight = y + rowHeight
        }

        return ArrangementResult(
            size: CGSize(width: totalWidth, height: totalHeight),
            positions: positions
        )
    }
}

// MARK: - Previews

#Preview("Minimal") {
    TransactionCard(
        id: "tx001",
        source: "Amazon",
        amountCents: 10012
    )
    .padding(Spacing.screenPadding)
    .preferredColorScheme(.dark)
}

#Preview("Full Badges & Notes") {
    TransactionCard(
        id: "tx002",
        source: "Wayfair",
        amountCents: 44620,
        transactionDate: "2026-02-02",
        notes: "***REPLACEMENT KING BED FOR MBR- first one came in with wrong piece and couldn't assemble......",
        budgetCategoryName: "Furnishings",
        transactionType: "purchase",
        needsReview: true,
        itemCount: 0,
        bookmarked: true,
        onBookmarkPress: {},
        menuItems: [
            ActionMenuItem(id: "edit", label: "Edit", icon: "pencil"),
            ActionMenuItem(id: "delete", label: "Delete", icon: "trash", isDestructive: true),
        ]
    )
    .padding(Spacing.screenPadding)
    .preferredColorScheme(.dark)
}

#Preview("Selected State") {
    @Previewable @State var selected = true

    TransactionCard(
        id: "tx003",
        source: "Amazon",
        amountCents: 14194,
        transactionDate: "2026-02-02",
        notes: "1king sham for MBR, ochre king quilt set for green king wingback bed",
        budgetCategoryName: "Furnishings",
        transactionType: "purchase",
        needsReview: true,
        itemCount: 0,
        isSelected: $selected,
        menuItems: [
            ActionMenuItem(id: "edit", label: "Edit", icon: "pencil"),
        ]
    )
    .padding(Spacing.screenPadding)
    .preferredColorScheme(.dark)
}
