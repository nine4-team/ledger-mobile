import SwiftUI

struct TransactionCard: View {
    // Core data
    let transaction: Transaction

    // Cross-collection lookup — not on Transaction model
    var budgetCategoryName: String?

    // Selection — parent-owned, nil means no selector
    var isSelected: Binding<Bool>?

    // Actions
    var bookmarked: Bool = false
    var onBookmarkPress: (() -> Void)?
    var menuItems: [ActionMenuItem] = []
    var onPress: (() -> Void)?

    private var badges: [CardBadge] {
        TransactionCardCalculations.badgeItems(
            transactionType: transaction.transactionType,
            reimbursementType: transaction.reimbursementType,
            hasEmailReceipt: transaction.hasEmailReceipt ?? false,
            needsReview: transaction.needsReview ?? false,
            budgetCategoryName: budgetCategoryName,
            status: transaction.status
        )
    }

    private var source: String {
        transaction.source ?? ""
    }

    private var itemCount: Int? {
        transaction.itemIds?.count
    }

    var body: some View {
        cardView
    }

    @ViewBuilder
    private var cardView: some View {
        let base = Card(padding: 0, isSelected: isSelected?.wrappedValue ?? false) {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(
                    isSelected: isSelected,
                    selectionLabel: source,
                    badges: badges,
                    bookmarked: bookmarked,
                    onBookmarkPress: onBookmarkPress,
                    menuTitle: source,
                    menuItems: menuItems
                )
                contentSection
            }
        }
        .contentShape(Rectangle())

        if let onPress {
            base.onTapGesture { onPress() }
        } else {
            base
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Source + Amount row
            HStack(alignment: .firstTextBaseline) {
                Text(source.isEmpty ? "Transaction \((transaction.id ?? "").prefix(6))" : source)
                    .font(Typography.body.weight(.semibold))
                    .foregroundStyle(BrandColors.textPrimary)
                    .lineLimit(2)

                Spacer(minLength: Spacing.md)

                Text(TransactionCardCalculations.formattedAmount(amountCents: transaction.amountCents, transactionType: transaction.transactionType))
                    .font(Typography.body.weight(.bold))
                    .foregroundStyle(BrandColors.textPrimary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }

            // Date + item count row
            HStack(spacing: 0) {
                Text(TransactionCardCalculations.formattedDate(transaction.transactionDate))
                    .font(Typography.small.weight(.medium))
                    .foregroundStyle(BrandColors.textSecondary)

                if let count = itemCount {
                    Text(" \u{00B7} ")
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                    Text("\(count) \(count == 1 ? "item" : "items")")
                        .font(Typography.small.weight(.medium))
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }

            // Notes
            if let truncated = TransactionCardCalculations.truncatedNotes(transaction.notes) {
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
        transaction: Transaction(
            amountCents: 10012,
            source: "Amazon"
        )
    )
    .padding(Spacing.screenPadding)
    .preferredColorScheme(.dark)
}

#Preview("Full Badges & Notes") {
    TransactionCard(
        transaction: Transaction(
            transactionDate: "2026-02-02",
            amountCents: 44620,
            source: "Wayfair",
            reimbursementType: nil,
            notes: "***REPLACEMENT KING BED FOR MBR- first one came in with wrong piece and couldn't assemble......",
            transactionType: "purchase",
            hasEmailReceipt: false,
            needsReview: true
        ),
        budgetCategoryName: "Furnishings",
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
        transaction: Transaction(
            transactionDate: "2026-02-02",
            amountCents: 14194,
            source: "Amazon",
            notes: "1king sham for MBR, ochre king quilt set for green king wingback bed",
            transactionType: "purchase",
            needsReview: true
        ),
        budgetCategoryName: "Furnishings",
        isSelected: $selected,
        menuItems: [
            ActionMenuItem(id: "edit", label: "Edit", icon: "pencil"),
        ]
    )
    .padding(Spacing.screenPadding)
    .preferredColorScheme(.dark)
}
