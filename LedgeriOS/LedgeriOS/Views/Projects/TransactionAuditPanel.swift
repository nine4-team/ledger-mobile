import SwiftUI

/// Audit panel for transaction completeness.
/// Reads stored audit data from the Cloud Function — no client-side computation.
/// Status is shown via the "Needs Review" badge on the CollapsibleSection header.
/// This panel shows the progress bar, detail breakdown, and missing price list.
struct TransactionAuditPanel: View {
    let audit: TransactionAudit
    let hasExplicitSubtotal: Bool
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
        VStack(alignment: .leading, spacing: Spacing.md) {
            progressSection
            detailBreakdown

            if !itemsMissingPrice.isEmpty {
                missingPriceListSection
            }
        }
    }

    // MARK: - Progress Bar

    private var progressSection: some View {
        VStack(spacing: Spacing.xs) {
            ProgressBar(
                percentage: min(completenessRatio * 100, 100),
                fillColor: statusBarColor,
                height: 8
            )

            HStack {
                Text("\(itemsCount) items")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)

                Spacer()

                Text(remainingLabel)
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)
            }
        }
    }

    // MARK: - Detail Breakdown

    private var hasLineageBreakdown: Bool {
        (audit.returnedItemsCount ?? 0) > 0 || (audit.soldItemsCount ?? 0) > 0
    }

    private var detailBreakdown: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            detailLine(
                label: hasExplicitSubtotal ? "Subtotal (pre-tax)" : "Estimated subtotal (pre-tax)",
                value: CurrencyFormatting.formatCentsWithDecimals(resolvedSubtotalCents)
            )

            if hasLineageBreakdown {
                detailLine(
                    label: "Linked items",
                    value: CurrencyFormatting.formatCentsWithDecimals(audit.linkedItemsSumCents ?? 0)
                )

                if let returnedCount = audit.returnedItemsCount, returnedCount > 0 {
                    detailLine(
                        label: "Returned items (\(returnedCount))",
                        value: CurrencyFormatting.formatCentsWithDecimals(audit.returnedItemsSumCents ?? 0)
                    )
                }

                if let soldCount = audit.soldItemsCount, soldCount > 0 {
                    detailLine(
                        label: "Sold items (\(soldCount))",
                        value: CurrencyFormatting.formatCentsWithDecimals(audit.soldItemsSumCents ?? 0)
                    )
                }
            }

            detailLine(
                label: hasLineageBreakdown ? "Total (pre-tax)" : "Associated items total (pre-tax)",
                value: CurrencyFormatting.formatCentsWithDecimals(itemsSumCents)
            )

            let missingCount = itemsMissingPrice.count
            if missingCount > 0 {
                Text("\(missingCount) items missing purchase price")
                    .font(Typography.caption)
                    .foregroundStyle(StatusColors.inProgressText)
            }
        }
    }

    private func detailLine(label: String, value: String) -> some View {
        Text("\(label): \(value)")
            .font(Typography.caption)
            .foregroundStyle(BrandColors.textSecondary)
    }

    // MARK: - Missing Price List

    private var missingPriceListSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            CardDivider()
                .padding(.vertical, Spacing.sm)

            Text("Missing Purchase Price")
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
            ForEach(itemsMissingPrice) { item in
                HStack {
                    Text(item.displayName)
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textPrimary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(item.sku ?? "—")
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                        .frame(width: 80, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Helpers

    private var remainingLabel: String {
        if varianceCents <= 0 {
            return "\(CurrencyFormatting.formatCentsWithDecimals(-varianceCents)) remaining"
        } else {
            return "Over by \(CurrencyFormatting.formatCentsWithDecimals(varianceCents))"
        }
    }

    private var statusBarColor: Color {
        isComplete ? StatusColors.metBarComplete : StatusColors.inProgressBar
    }
}
