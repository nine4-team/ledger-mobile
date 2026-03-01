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

    private typealias S = ReportPDFStyles

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Branded header
            pdfHeader(title: "Client Summary Report")

            // Overview cards grid
            HStack(spacing: 12) {
                overviewCard(label: "Total Spent", value: CurrencyFormatting.formatCentsWithDecimals(data.totalSpentCents))
                overviewCard(label: "Market Value", value: CurrencyFormatting.formatCentsWithDecimals(data.totalMarketValueCents))
                overviewCard(label: "Total Saved", value: CurrencyFormatting.formatCentsWithDecimals(data.totalSavedCents))
            }
            .padding(.top, 20)

            // Category Breakdown
            if !data.categoryBreakdowns.isEmpty {
                sectionHeader("Category Breakdown")

                // Table header
                HStack(spacing: 0) {
                    Text("CATEGORY")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("TOTAL")
                        .frame(width: 120, alignment: .trailing)
                }
                .font(S.tableHeaderFont)
                .foregroundStyle(S.textSecondary)
                .textCase(.uppercase)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(S.headerBg)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(S.border)
                        .frame(height: 1)
                }

                ForEach(Array(data.categoryBreakdowns.enumerated()), id: \.offset) { index, breakdown in
                    HStack(spacing: 0) {
                        Text(breakdown.categoryName)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(CurrencyFormatting.formatCentsWithDecimals(breakdown.spentCents))
                            .frame(width: 120, alignment: .trailing)
                    }
                    .font(S.bodyFont)
                    .foregroundStyle(S.textPrimary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(index.isMultiple(of: 2) ? Color.clear : S.cardBg)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(S.rowBorder)
                            .frame(height: 1)
                    }
                }
            }

            // Items
            if !data.items.isEmpty {
                sectionHeader("Items")

                // Table header
                HStack(spacing: 0) {
                    Text("ITEM")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("SOURCE")
                        .frame(width: 120, alignment: .leading)
                    Text("SPACE")
                        .frame(width: 120, alignment: .leading)
                    Text("PROJECT PRICE")
                        .frame(width: 110, alignment: .trailing)
                }
                .font(S.tableHeaderFont)
                .foregroundStyle(S.textSecondary)
                .textCase(.uppercase)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(S.headerBg)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(S.border)
                        .frame(height: 1)
                }

                ForEach(Array(data.items.enumerated()), id: \.offset) { index, clientItem in
                    HStack(spacing: 0) {
                        HStack(spacing: 0) {
                            Text(clientItem.item.name)
                            receiptBadge(clientItem.receiptLink)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(clientItem.item.source ?? "")
                            .frame(width: 120, alignment: .leading)
                        Text(clientItem.spaceName ?? "")
                            .frame(width: 120, alignment: .leading)
                        Text(CurrencyFormatting.formatCentsWithDecimals(clientItem.item.projectPriceCents ?? 0))
                            .frame(width: 110, alignment: .trailing)
                    }
                    .font(S.bodyFont)
                    .foregroundStyle(S.textPrimary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(index.isMultiple(of: 2) ? Color.clear : S.cardBg)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(S.rowBorder)
                            .frame(height: 1)
                    }
                }
            }

            // Footer
            pdfFooter()
        }
        .padding(S.pagePadding)
        .frame(width: S.pageWidth)
        .background(Color.white)
    }

    // MARK: - Header

    private func pdfHeader(title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(projectName)
                .font(S.titleFont)
                .foregroundStyle(S.brand)
            Text(title)
                .font(S.subtitleFont)
                .foregroundStyle(S.textDark)
            HStack(spacing: 4) {
                Text("Date:")
                    .font(S.metaLabelFont)
                Text(currentDateFormatted)
                    .font(S.metaFont)
            }
            .foregroundStyle(S.textSecondary)
            .padding(.top, 4)
        }
        .padding(.bottom, 20)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(S.brand)
                .frame(height: S.headerBorderWidth)
        }
    }

    // MARK: - Overview Card

    private func overviewCard(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(S.cardLabelFont)
                .foregroundStyle(S.textSecondary)
            Text(value)
                .font(S.cardValueFont)
                .foregroundStyle(S.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(S.cardBg)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(S.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(S.sectionHeaderFont)
            .foregroundStyle(S.brand)
            .padding(.top, 28)
            .padding(.bottom, 12)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(S.border)
                    .frame(height: 1)
            }
    }

    // MARK: - Receipt Badge

    @ViewBuilder
    private func receiptBadge(_ link: ReceiptLink) -> some View {
        switch link {
        case .invoice:
            Text("Invoice")
                .font(S.badgeFont)
                .foregroundStyle(S.brand)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(S.headerBg)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(.leading, 6)
        case .receiptURL:
            Text("Receipt")
                .font(S.badgeFont)
                .foregroundStyle(S.brand)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(S.headerBg)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(.leading, 6)
        case .none:
            EmptyView()
        }
    }

    // MARK: - Footer

    private func pdfFooter() -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(S.border)
                .frame(height: 1)
                .padding(.top, 40)
            Text("Generated on \(currentDateFormatted)")
                .font(S.footerFont)
                .foregroundStyle(S.textFooter)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
        }
    }

    private var currentDateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: Date())
    }
}
