import SwiftUI

#if canImport(FirebaseFirestore)
/// Audit panel for transaction completeness.
/// Reads stored audit data from the Cloud Function — no client-side computation.
/// Status is shown via the "Needs Review" badge on the CollapsibleSection header.
/// This panel shows the progress bar, detail breakdown, and missing price list.
struct TransactionAuditPanel: View {
    let audit: TransactionAudit
    let hasExplicitSubtotal: Bool
    let usesProjectPrice: Bool
    let itemsMissingPrice: [Item]
    let itemsCount: Int

    private var resolvedSubtotalCents: Int { audit.resolvedSubtotalCents ?? 0 }
    private var itemsSumCents: Int { audit.itemsSumCents ?? 0 }
    private var varianceCents: Int { audit.varianceCents ?? 0 }
    private var variancePercent: Double { audit.variancePercent ?? 0 }

    private var completenessRatio: Double {
        guard resolvedSubtotalCents > 0 else { return 0 }
        return Double(itemsSumCents) / Double(resolvedSubtotalCents)
    }

    private var isComplete: Bool {
        abs(variancePercent) <= 1.0
    }

    var body: some View {
        TransactionAuditPanelPresentation(progressPercentage: min(completenessRatio * 100, 100),
            isComplete: isComplete, itemCount: itemsCount, statusLabel: remainingLabel,
            details: details, missingPriceTitle: usesProjectPrice ? "Missing Project Price" : "Missing Purchase Price",
            missingPriceSummary: "\(itemsMissingPrice.count) items missing \(usesProjectPrice ? "project" : "purchase") price",
            missingItems: itemsMissingPrice, itemName: { $0.displayName }, itemSKU: { $0.sku })
    }

    private var hasLineageBreakdown: Bool {
        (audit.returnedItemsCount ?? 0) > 0 || (audit.soldItemsCount ?? 0) > 0
    }

    private var details: [String] {
        func line(_ name: String, _ cents: Int) -> String {
            "\(name): \(CurrencyFormatting.formatCentsWithDecimals(cents))"
        }
        var rows = [line(hasExplicitSubtotal ? "Subtotal (pre-tax)" : "Estimated subtotal (pre-tax)", resolvedSubtotalCents)]
        if hasLineageBreakdown {
            rows.append(line("Linked items", audit.linkedItemsSumCents ?? 0))
            if let count = audit.returnedItemsCount, count > 0 { rows.append(line("Returned items (\(count))", audit.returnedItemsSumCents ?? 0)) }
            if let count = audit.soldItemsCount, count > 0 { rows.append(line("Sold items (\(count))", audit.soldItemsSumCents ?? 0)) }
        }
        rows.append(line(hasLineageBreakdown ? "Total (pre-tax)" : "Associated items total (pre-tax)", itemsSumCents))
        return rows
    }

    private var remainingLabel: String {
        if varianceCents <= 0 {
            return "\(CurrencyFormatting.formatCentsWithDecimals(-varianceCents)) remaining"
        } else {
            return "Over by \(CurrencyFormatting.formatCentsWithDecimals(varianceCents))"
        }
    }
}
#endif

/// Original panel layout with provider-independent inputs. Neither this view nor
/// its progress bar decides whether receipt accounting is complete.
struct TransactionAuditPanelPresentation<MissingItem: Identifiable>: View {
    let progressPercentage: Double?
    let isComplete: Bool
    let itemCount: Int
    let statusLabel: String
    let details: [String]
    let missingPriceTitle: String
    let missingPriceSummary: String
    let missingItems: [MissingItem]
    let itemName: (MissingItem) -> String
    let itemSKU: (MissingItem) -> String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(spacing: Spacing.xs) {
                if let progressPercentage {
                    ProgressBar(percentage: progressPercentage,
                        fillColor: isComplete ? StatusColors.metBarComplete : StatusColors.inProgressBar, height: 8)
                }
                HStack {
                    Text("\(itemCount) items")
                    Spacer()
                    Text(statusLabel).accessibilityIdentifier("transaction-audit-status")
                }
                .font(Typography.caption)
                .foregroundStyle(BrandColors.textSecondary)
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(Array(details.enumerated()), id: \.offset) { _, text in
                    Text(text).font(Typography.caption).foregroundStyle(BrandColors.textSecondary)
                }
                if !missingItems.isEmpty {
                    Text(missingPriceSummary).font(Typography.caption).foregroundStyle(StatusColors.inProgressText)
                }
            }
            if !missingItems.isEmpty { missingPriceListSection }
        }
    }

    // MARK: - Missing Price List

    private var missingPriceListSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            CardDivider()
                .padding(.vertical, Spacing.sm)

            Text(missingPriceTitle)
                .font(Typography.small.weight(.medium))
                .foregroundStyle(BrandColors.textPrimary)

            // Header row
            HStack {
                Text("ITEM")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("SKU")
                    .frame(width: 80, alignment: .leading)
            }
            .font(Typography.microLabel)
            .foregroundStyle(BrandColors.textSecondary)

            // Item rows
            ForEach(missingItems) { item in
                HStack {
                    Text(itemName(item))
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textPrimary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(itemSKU(item) ?? "—")
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                        .frame(width: 80, alignment: .leading)
                }
            }
        }
    }

}
