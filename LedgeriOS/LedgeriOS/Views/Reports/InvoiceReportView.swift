import SwiftUI

struct InvoiceReportView: View {
    let data: InvoiceReportData
    let projectName: String
    let clientName: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Header
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(projectName)
                        .font(Typography.h1)
                        .foregroundStyle(BrandColors.textPrimary)
                    if !clientName.isEmpty {
                        Text(clientName)
                            .font(Typography.small)
                            .foregroundStyle(BrandColors.textSecondary)
                    }
                    Text(currentDateFormatted)
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textTertiary)
                }

                // Missing prices warning
                if data.chargeLines.contains(where: \.isMissingProjectPrices)
                    || data.creditLines.contains(where: \.isMissingProjectPrices) {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Some items are missing project prices. Totals may be incomplete.")
                            .font(Typography.small)
                            .foregroundStyle(BrandColors.textSecondary)
                    }
                    .padding(Spacing.md)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: Dimensions.cardRadius))
                }

                // Charges section
                if !data.chargeLines.isEmpty {
                    invoiceSection(title: "Charges", lines: data.chargeLines)
                }

                // Credits section
                if !data.creditLines.isEmpty {
                    invoiceSection(title: "Credits", lines: data.creditLines)
                }

                // Summary
                Divider()

                VStack(spacing: Spacing.sm) {
                    summaryRow(
                        label: "Charges Subtotal",
                        amount: data.chargesSubtotalCents,
                        isBold: false
                    )
                    summaryRow(
                        label: "Credits Subtotal",
                        amount: data.creditsSubtotalCents,
                        isBold: false
                    )
                    Divider()
                    summaryRow(
                        label: "Net Due",
                        amount: data.netDueCents,
                        isBold: true
                    )
                }
            }
            .padding(Spacing.screenPadding)
        }
        .navigationTitle("Invoice")
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

    private func invoiceSection(title: String, lines: [InvoiceLineItem]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(title)
                .sectionLabelStyle()

            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.displayName)
                                .font(Typography.body)
                                .foregroundStyle(BrandColors.textPrimary)
                            HStack(spacing: Spacing.sm) {
                                if !line.formattedDate.isEmpty {
                                    Text(line.formattedDate)
                                        .font(Typography.caption)
                                        .foregroundStyle(BrandColors.textTertiary)
                                }
                                if let category = line.categoryName {
                                    Text(category)
                                        .font(Typography.caption)
                                        .foregroundStyle(BrandColors.textTertiary)
                                }
                            }
                        }
                        Spacer()
                        Text(CurrencyFormatting.formatCentsWithDecimals(line.amountCents))
                            .font(Typography.body)
                            .foregroundStyle(BrandColors.textPrimary)
                    }

                    if let notes = line.notes, !notes.isEmpty {
                        Text(notes)
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textTertiary)
                    }

                    // Linked items (indented)
                    if !line.linkedItems.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(line.linkedItems.enumerated()), id: \.offset) { _, item in
                                HStack {
                                    Text(item.name ?? "Unnamed Item")
                                        .font(Typography.small)
                                        .foregroundStyle(BrandColors.textSecondary)
                                    Spacer()
                                    if let price = item.projectPriceCents {
                                        Text(CurrencyFormatting.formatCentsWithDecimals(price))
                                            .font(Typography.small)
                                            .foregroundStyle(
                                                item.isMissingPrice
                                                ? .orange
                                                : BrandColors.textSecondary
                                            )
                                    } else {
                                        Text("No Price")
                                            .font(Typography.small)
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }
                        }
                        .padding(.leading, Spacing.lg)
                    }
                }
                .padding(.vertical, Spacing.xs)

                Divider()
            }
        }
    }

    private func summaryRow(label: String, amount: Int, isBold: Bool) -> some View {
        HStack {
            Text(label)
                .font(isBold ? Typography.h3 : Typography.body)
                .foregroundStyle(BrandColors.textPrimary)
            Spacer()
            Text(CurrencyFormatting.formatCentsWithDecimals(amount))
                .font(isBold ? Typography.h3 : Typography.body)
                .foregroundStyle(BrandColors.textPrimary)
        }
    }

    private var currentDateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: Date())
    }

    // MARK: - PDF Sharing

    private func sharePDF() {
        let pdfContent = InvoiceReportPDFContent(
            data: data,
            projectName: projectName,
            clientName: clientName
        )
        ReportPDFSharing.sharePDF(
            content: pdfContent,
            fileName: "invoice-\(projectName).pdf"
        )
    }
}

// MARK: - PDF Content View

private struct InvoiceReportPDFContent: View {
    let data: InvoiceReportData
    let projectName: String
    let clientName: String

    private typealias S = ReportPDFStyles

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Branded header with bottom border
            pdfHeader(title: "Invoice Report")

            // Missing prices warning
            if data.chargeLines.contains(where: \.isMissingProjectPrices)
                || data.creditLines.contains(where: \.isMissingProjectPrices) {
                HStack(spacing: 6) {
                    Text("⚠")
                        .font(S.bodyFont)
                    Text("Some items are missing project prices. Totals may be incomplete.")
                        .font(S.subItemFont)
                        .foregroundStyle(S.error)
                        .italic()
                }
                .padding(.top, 16)
            }

            // Charges section
            if !data.chargeLines.isEmpty {
                invoiceLinesSection(title: "Charges", lines: data.chargeLines)
            }

            // Credits section
            if !data.creditLines.isEmpty {
                invoiceLinesSection(title: "Credits", lines: data.creditLines)
            }

            // Totals
            VStack(alignment: .trailing, spacing: 0) {
                totalsRow(label: "Charges Total", cents: data.chargesSubtotalCents, isNet: false)
                totalsRow(label: "Credits Total", cents: data.creditsSubtotalCents, isNet: false, showParens: true)
                // Net due with brand-color top border
                HStack(spacing: 0) {
                    Spacer()
                    HStack {
                        Text("Net Amount Due")
                            .font(S.netDueFont)
                            .foregroundStyle(S.brand)
                        Spacer()
                        Text(CurrencyFormatting.formatCentsWithDecimals(data.netDueCents))
                            .font(S.netDueFont)
                            .foregroundStyle(S.brand)
                    }
                    .frame(width: 280)
                    .padding(.vertical, 10)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(S.brand)
                            .frame(height: S.netDueBorderWidth)
                    }
                }
                .padding(.top, 4)
            }
            .padding(.top, 12)

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
            VStack(alignment: .leading, spacing: 2) {
                if !clientName.isEmpty {
                    HStack(spacing: 4) {
                        Text("Client:")
                            .font(S.metaLabelFont)
                        Text(clientName)
                            .font(S.metaFont)
                    }
                }
                HStack(spacing: 4) {
                    Text("Date:")
                        .font(S.metaLabelFont)
                    Text(currentDateFormatted)
                        .font(S.metaFont)
                }
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

    // MARK: - Invoice Lines Table

    private func invoiceLinesSection(title: String, lines: [InvoiceLineItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header (h2 style)
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

            // Table header row
            HStack(spacing: 0) {
                Text("DATE")
                    .frame(width: 100, alignment: .leading)
                Text("DESCRIPTION")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("CATEGORY")
                    .frame(width: 140, alignment: .leading)
                Text("AMOUNT")
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

            // Data rows
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        Text(line.formattedDate)
                            .frame(width: 100, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(line.displayName)
                                if line.isMissingProjectPrices {
                                    Text("(contains missing prices)")
                                        .font(S.missingPriceFont)
                                        .foregroundStyle(S.error)
                                }
                            }
                            // Sub-items
                            ForEach(Array(line.linkedItems.enumerated()), id: \.offset) { _, item in
                                HStack(spacing: 4) {
                                    Text(item.name ?? "Unnamed Item")
                                    Text("—")
                                    if item.isMissingPrice {
                                        Text("\(CurrencyFormatting.formatCentsWithDecimals(item.projectPriceCents ?? 0)) (missing price)")
                                            .foregroundStyle(S.error)
                                    } else {
                                        Text(CurrencyFormatting.formatCentsWithDecimals(item.projectPriceCents ?? 0))
                                    }
                                }
                                .font(S.subItemFont)
                                .foregroundStyle(S.textSub)
                                .padding(.leading, 20)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(line.categoryName ?? "")
                            .frame(width: 140, alignment: .leading)
                        Text(CurrencyFormatting.formatCentsWithDecimals(line.amountCents))
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
        }
    }

    // MARK: - Totals

    private func totalsRow(label: String, cents: Int, isNet: Bool, showParens: Bool = false) -> some View {
        HStack(spacing: 0) {
            Spacer()
            HStack {
                Text(label)
                    .font(S.bodyBoldFont)
                    .foregroundStyle(S.textDark)
                Spacer()
                Text(showParens
                    ? "(\(CurrencyFormatting.formatCentsWithDecimals(cents)))"
                    : CurrencyFormatting.formatCentsWithDecimals(cents)
                )
                .font(S.bodyBoldFont)
                .foregroundStyle(S.textDark)
            }
            .frame(width: 280)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
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
