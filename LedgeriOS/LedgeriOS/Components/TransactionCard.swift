import SwiftUI

#if canImport(FirebaseFirestore)
struct TransactionCard: View {
    // Core data
    let transaction: Transaction

    // Cross-collection lookup — not on Transaction model
    var budgetCategoryName: String?
    var assignmentLabel: String?
    /// Project name, or "Business Inventory" for null-projectId transactions.
    /// Resolved by the caller via `TransactionDisplayCalculations.projectLabel(for:projects:)`.
    /// Pass nil to suppress (e.g. in already-project-scoped views where it would be redundant).
    var projectName: String?
    /// When this query matches the transaction ID, show that ID on the card so
    /// the reason the transaction matched is visible to the user.
    var searchQuery: String? = nil

    // Selection — parent-owned, nil means no selector
    var isSelected: Binding<Bool>?

    // Actions
    var bookmarked: Bool = false
    var onBookmarkPress: (() -> Void)?
    var menuItems: [ActionMenuItem] = []
    var onPress: (() -> Void)?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AccountContext.self) private var accountContext

    private var badges: [CardBadge] {
        // Only show invoice badge for non-itemized transactions on regular width (iPad/macOS).
        let isNonItemized = (transaction.itemIds ?? []).isEmpty
        let invoice: InvoiceStatus? = {
            guard isNonItemized, horizontalSizeClass == .regular, let id = transaction.id else { return nil }
            return firstNonCanceledInvoiceStatus(forTransactionId: id, in: accountContext.allInvoices)
        }()
        return TransactionCardCalculations.badgeItems(
            transactionType: transaction.transactionType,
            reimbursementType: transaction.reimbursementType,
            hasEmailReceipt: transaction.hasEmailReceipt ?? false,
            isComplete: transaction.isComplete,
            status: transaction.status,
            isCanonicalInventorySale: transaction.isCanonicalInventorySale,
            inventorySaleDirection: transaction.inventorySaleDirection,
            budgetCategoryId: transaction.budgetCategoryId,
            invoiceStatus: invoice
        )
    }

    private var source: String {
        transaction.source ?? ""
    }

    private var itemCount: Int? {
        transaction.itemIds?.count
    }

    private var matchingTransactionID: String? {
        SearchCalculations.matchingTransactionID(transaction: transaction, query: searchQuery)
    }

    var body: some View {
        TransactionCardPresentation(
            id: transaction.id,
            title: TransactionDisplayCalculations.displayName(for: transaction),
            source: source,
            amountText: TransactionCardCalculations.formattedAmount(amountCents: transaction.amountCents, transactionType: transaction.transactionType),
            dateText: TransactionCardCalculations.formattedDate(transaction.transactionDate),
            itemCount: itemCount,
            budgetCategoryName: budgetCategoryName,
            assignmentLabel: assignmentLabel,
            projectName: projectName,
            matchingTransactionID: matchingTransactionID,
            notesPreview: TransactionCardCalculations.truncatedNotes(transaction.notes),
            badges: badges,
            isSelected: isSelected,
            bookmarked: bookmarked,
            onBookmarkPress: onBookmarkPress,
            menuItems: menuItems,
            onPress: onPress
        )
    }
}
#endif

/// The original card layout receives display values and actions, not a backend
/// model or Account context. Callers own authorized data and accounting meaning.
/// Original grouped Transaction filter shell. Options and selections are inputs.
struct TransactionFilterMenuPresentation: View {
    @Binding var isPresented: Bool
    let items: [ActionMenuItem]
    @State private var expandedFilterGroup: String?
    var body: some View {
        // Keep a concrete presentation anchor when this shell is embedded in a
        // list. EmptyView can leave macOS with a disabled window and no sheet.
        Color.clear.frame(width: 0, height: 0).adaptivePresentation(isPresented: $isPresented, style: .selectionMenu,
            onDismiss: { expandedFilterGroup = nil }) {
                ActionMenuSheet(title: "Filter", items: items, closeOnItemPress: false,
                    persistentExpandedItemKey: $expandedFilterGroup)
            }
    }
}

/// Original Transaction detail hero, with display values supplied by its owner.
struct TransactionHeroPresentation: View {
    let title: String
    let amount: String
    let date: String
    let project: String
    var category: String?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                FindableText(title)
                    .font(Typography.h2)
                    .foregroundStyle(BrandColors.textPrimary)
                row("Amount:", amount)
                row("Date:", date)
                row("Project:", project)
                if let category, !category.isEmpty { row("Budget Category:", category) }
            }
        }
    }
    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Text(label).font(Typography.small).foregroundStyle(BrandColors.textSecondary)
            FindableText(value).font(Typography.small).foregroundStyle(BrandColors.textPrimary)
        }
    }
}

struct TransactionCardPresentation: View {
    let id: String?
    let title: String
    let source: String
    let amountText: String
    let dateText: String
    var itemCount: Int?
    var budgetCategoryName: String?
    var assignmentLabel: String?
    var projectName: String?
    var matchingTransactionID: String?
    var notesPreview: String?
    var badges: [CardBadge] = []
    var isSelected: Binding<Bool>?
    var bookmarked = false
    var onBookmarkPress: (() -> Void)?
    var menuItems: [ActionMenuItem] = []
    var onPress: (() -> Void)?

    @ViewBuilder
    var body: some View {
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
        .findEntity(id: id)
        .findMatchHighlight()

        if let onPress {
            base.onTapGesture { onPress() }
        } else {
            base
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Source + Amount row
            HStack(alignment: .firstTextBaseline) {
                FindableText(title)
                    .font(Typography.body.weight(.semibold))
                    .foregroundStyle(BrandColors.textPrimary)
                    .lineLimit(2)

                Spacer(minLength: Spacing.md)

                FindableText(amountText)
                    .font(Typography.body.weight(.bold))
                    .foregroundStyle(BrandColors.textPrimary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }

            // Detail rows
            VStack(alignment: .leading, spacing: Spacing.xs) {

            // Date + item count + project + category (collapsed on macOS)
            #if os(macOS)
            HStack(spacing: 0) {
                Text("Date: ")
                    .font(Typography.small)
                    .foregroundStyle(BrandColors.textSecondary)
                FindableText(dateText)
                    .font(Typography.small)
                    .foregroundStyle(BrandColors.textSecondary)

                if let count = itemCount {
                    Text(" \u{00B7} ")
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                    Text("\(count) \(count == 1 ? "item" : "items")")
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                }

                if let project = projectName, !project.isEmpty {
                    Text(" \u{00B7} ")
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                    FindableText(project)
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                }

                if let category = budgetCategoryName, !category.isEmpty {
                    Text(" \u{00B7} ")
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                    FindableText(category)
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }
            #else
            HStack(spacing: 0) {
                Text("Date: ")
                    .font(Typography.small)
                    .foregroundStyle(BrandColors.textSecondary)
                FindableText(dateText)
                    .font(Typography.small)
                    .foregroundStyle(BrandColors.textSecondary)

                if let count = itemCount {
                    Text(" \u{00B7} ")
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                    Text("\(count) \(count == 1 ? "item" : "items")")
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }

            if let project = projectName, !project.isEmpty {
                HStack(spacing: Spacing.xs) {
                    Text("Project:")
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                    FindableText(project)
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }

            if let category = budgetCategoryName, !category.isEmpty {
                HStack(spacing: Spacing.xs) {
                    Text("Budget Category:")
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                    FindableText(category)
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }

            if let label = assignmentLabel {
                HStack(spacing: 0) {
                    Text("Assigned To: ")
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                    Text(label)
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }
            #endif

            if let transactionID = matchingTransactionID {
                HStack(spacing: Spacing.xs) {
                    Text("Transaction ID:")
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                    FindableText(transactionID)
                        .font(Typography.small.monospaced())
                        .foregroundStyle(BrandColors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .accessibilityElement(children: .combine)
            }

            // Notes
            Group {
                if let truncated = notesPreview {
                    FindableText(truncated)
                        .font(Typography.small)
                        .italic()
                        .foregroundStyle(BrandColors.textSecondary)
                        .lineLimit(1)
                } else {
                    EmptyView()
                }
            }
            } // end detail rows VStack
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

#if canImport(FirebaseFirestore)
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
            transactionType: .purchase,
            hasEmailReceipt: false
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
            transactionType: .purchase
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
#endif
