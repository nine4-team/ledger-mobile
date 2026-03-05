import SwiftUI

/// Audit panel for transaction completeness — matches web app's
/// TransactionAudit (TransactionCompletenessPanel + MissingPriceList).
struct TransactionAuditPanel: View {
    let completeness: TransactionCompletenessCalculations.TransactionCompleteness
    let hasExplicitSubtotal: Bool
    let itemsMissingPrice: [Item]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            completenessSection

            if !itemsMissingPrice.isEmpty {
                missingPriceListSection
            }
        }
    }

    // MARK: - Completeness Section

    private var completenessSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            statusHeaderRow
            progressSection

            if completeness.itemsCount == 0 {
                Text("No items linked yet")
                    .font(Typography.caption)
                    .foregroundStyle(StatusColors.missedText)
                    .fontWeight(.medium)
            } else {
                detailBreakdown
            }

            missingTaxWarning
        }
    }

    // MARK: - Status Header

    private var statusHeaderRow: some View {
        HStack {
            HStack(spacing: Spacing.sm) {
                Image(systemName: TransactionCompletenessCalculations.statusIcon(completeness.status))
                    .font(.system(size: 18))
                    .foregroundStyle(statusColor)

                Text(TransactionCompletenessCalculations.statusLabel(completeness.status))
                    .font(Typography.body.weight(.medium))
                    .foregroundStyle(BrandColors.textPrimary)
            }

            Spacer()

            Text("\(CurrencyFormatting.formatCentsWithDecimals(completeness.itemsNetTotalCents)) / \(CurrencyFormatting.formatCentsWithDecimals(completeness.transactionSubtotalCents))")
                .font(Typography.small)
                .foregroundStyle(BrandColors.textSecondary)
        }
    }

    // MARK: - Progress Bar

    private var progressSection: some View {
        VStack(spacing: Spacing.xs) {
            ProgressBar(
                percentage: min(completeness.completenessRatio * 100, 100),
                fillColor: statusBarColor,
                height: 8
            )

            HStack {
                Text("\(completeness.itemsCount) items")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)

                Spacer()

                Text(TransactionCompletenessCalculations.remainingLabel(varianceCents: completeness.varianceCents))
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)
            }
        }
    }

    // MARK: - Detail Breakdown

    private var detailBreakdown: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            detailLine(
                label: TransactionCompletenessCalculations.subtotalLabel(hasExplicitSubtotal: hasExplicitSubtotal),
                value: CurrencyFormatting.formatCentsWithDecimals(completeness.transactionSubtotalCents)
            )

            detailLine(
                label: "Associated items total (pre-tax)",
                value: CurrencyFormatting.formatCentsWithDecimals(completeness.itemsNetTotalCents)
            )

            if let inferredTax = completeness.inferredTax {
                detailLine(
                    label: "Calculated tax",
                    value: CurrencyFormatting.formatCentsWithDecimals(inferredTax)
                )
            }

            if completeness.itemsMissingPriceCount > 0 {
                Text("\(completeness.itemsMissingPriceCount) items missing purchase price")
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

    // MARK: - Missing Tax Warning

    @ViewBuilder
    private var missingTaxWarning: some View {
        if completeness.missingTaxData {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(StatusColors.inProgressText)

                (Text("Tax rate not set. ").bold()
                    + Text("Set tax rate or transaction subtotal for accurate calculations."))
                    .font(Typography.caption)
                    .foregroundStyle(StatusColors.inProgressText)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(StatusColors.inProgressBackground)
            .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
        }
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
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(BrandColors.textSecondary)

            // Item rows
            ForEach(itemsMissingPrice) { item in
                VStack(spacing: 0) {
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
    }

    // MARK: - Color Helpers

    private var statusColor: Color {
        switch completeness.status {
        case .complete: return StatusColors.metBarComplete
        case .near, .incomplete, .over: return StatusColors.inProgressText
        }
    }

    private var statusBarColor: Color {
        switch completeness.status {
        case .complete: return StatusColors.metBarComplete
        case .near, .incomplete, .over: return StatusColors.inProgressBar
        }
    }
}
