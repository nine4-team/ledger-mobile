import SwiftUI

struct ClientSummaryReportView: View {
    let data: ClientSummaryData
    let projectName: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Summary cards
                VStack(spacing: Spacing.cardListGap) {
                    summaryCard(label: "Total Spent", cents: data.totalSpentCents)
                    summaryCard(label: "Total Market Value", cents: data.totalMarketValueCents)
                    summaryCard(label: "Total Saved", cents: data.totalSavedCents)
                }

                // Category breakdown
                if !data.categoryBreakdowns.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text("Category Breakdown")
                            .sectionLabelStyle()

                        ForEach(Array(data.categoryBreakdowns.enumerated()), id: \.offset) { _, breakdown in
                            HStack {
                                Text(breakdown.categoryName)
                                    .font(Typography.body)
                                    .foregroundStyle(BrandColors.textPrimary)
                                Spacer()
                                Text(CurrencyFormatting.formatCentsWithDecimals(breakdown.spentCents))
                                    .font(Typography.body)
                                    .foregroundStyle(BrandColors.textSecondary)
                            }
                            .padding(.vertical, Spacing.xs)
                        }
                    }
                }

                // Items list
                if !data.items.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text("Items")
                            .sectionLabelStyle()

                        ForEach(Array(data.items.enumerated()), id: \.offset) { _, clientItem in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(clientItem.item.name)
                                        .font(Typography.body)
                                        .foregroundStyle(BrandColors.textPrimary)
                                    if let spaceName = clientItem.spaceName {
                                        Text(spaceName)
                                            .font(Typography.caption)
                                            .foregroundStyle(BrandColors.textTertiary)
                                    }
                                }
                                Spacer()
                                HStack(spacing: Spacing.sm) {
                                    receiptLinkIcon(clientItem.receiptLink)
                                    Text(CurrencyFormatting.formatCentsWithDecimals(
                                        clientItem.item.projectPriceCents ?? 0
                                    ))
                                    .font(Typography.body)
                                    .foregroundStyle(BrandColors.textSecondary)
                                }
                            }
                            .padding(.vertical, Spacing.xs)

                            Divider()
                        }
                    }
                }
            }
            .padding(Spacing.screenPadding)
        }
        .navigationTitle("Client Summary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    sharePDF()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }

    // MARK: - Subviews

    private func summaryCard(label: String, cents: Int) -> some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(label)
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                    Text(CurrencyFormatting.formatCentsWithDecimals(cents))
                        .font(Typography.h2)
                        .foregroundStyle(BrandColors.textPrimary)
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func receiptLinkIcon(_ link: ReceiptLink) -> some View {
        switch link {
        case .invoice:
            Image(systemName: "doc.text")
                .font(Typography.caption)
                .foregroundStyle(BrandColors.primary)
        case .receiptURL:
            Image(systemName: "photo")
                .font(Typography.caption)
                .foregroundStyle(BrandColors.primary)
        case .none:
            EmptyView()
        }
    }

    // MARK: - PDF Sharing

    private func sharePDF() {
        let pdfContent = ClientSummaryPDFContent(data: data, projectName: projectName)
        ReportPDFSharing.sharePDF(
            content: pdfContent,
            fileName: "client-summary-\(projectName).pdf"
        )
    }
}

// MARK: - PDF Content View

private struct ClientSummaryPDFContent: View {
    let data: ClientSummaryData
    let projectName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Client Summary — \(projectName)")
                .font(.title2.bold())
            Text(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none))
                .font(.caption)
                .foregroundStyle(.tertiary)

            Divider()

            HStack(spacing: 24) {
                VStack(alignment: .leading) {
                    Text("Total Spent")
                        .font(.caption)
                    Text(formatCents(data.totalSpentCents))
                        .font(.headline)
                }
                VStack(alignment: .leading) {
                    Text("Market Value")
                        .font(.caption)
                    Text(formatCents(data.totalMarketValueCents))
                        .font(.headline)
                }
                VStack(alignment: .leading) {
                    Text("Total Saved")
                        .font(.caption)
                    Text(formatCents(data.totalSavedCents))
                        .font(.headline)
                }
            }

            if !data.categoryBreakdowns.isEmpty {
                Divider()
                Text("CATEGORY BREAKDOWN")
                    .font(.caption.weight(.semibold))
                ForEach(Array(data.categoryBreakdowns.enumerated()), id: \.offset) { _, b in
                    HStack {
                        Text(b.categoryName)
                        Spacer()
                        Text(formatCents(b.spentCents))
                    }
                    .font(.body)
                }
            }

            if !data.items.isEmpty {
                Divider()
                Text("ITEMS")
                    .font(.caption.weight(.semibold))
                ForEach(Array(data.items.enumerated()), id: \.offset) { _, item in
                    HStack {
                        Text(item.item.name)
                        if let space = item.spaceName {
                            Text("(\(space))")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(formatCents(item.item.projectPriceCents ?? 0))
                    }
                    .font(.body)
                }
            }
        }
        .padding(24)
        .frame(width: 612)
    }

    private func formatCents(_ cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        return String(format: "$%.2f", dollars)
    }
}
