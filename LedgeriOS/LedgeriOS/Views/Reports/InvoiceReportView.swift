import SwiftUI

struct InvoiceReportView: View {
    let data: InvoiceReportData
    let projectName: String
    let clientName: String
    var businessName: String?
    var businessLogoUrl: String?

    @State private var logoImage: PlatformImage?

    var body: some View {
        Group {
        if data.chargeLines.isEmpty && data.creditLines.isEmpty {
            ContentUnavailableView("No Invoice Data", systemImage: "doc.text", description: Text("No transactions available for this report."))
        } else {
        ScrollView {
            AdaptiveContentWidth {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Header — logo + info side-by-side, brand border bottom
                invoiceHeader

                // Totals summary card
                Card {
                    VStack(spacing: Spacing.sm) {
                        HStack {
                            Text("Charges")
                                .font(Typography.small)
                                .foregroundStyle(BrandColors.textSecondary)
                            Spacer()
                            Text(CurrencyFormatting.formatCentsWithDecimals(data.chargesSubtotalCents))
                                .font(Typography.body)
                                .fontWeight(.semibold)
                                .foregroundStyle(BrandColors.textPrimary)
                        }
                        HStack {
                            Text("Credits")
                                .font(Typography.small)
                                .foregroundStyle(BrandColors.textSecondary)
                            Spacer()
                            Text("(\(CurrencyFormatting.formatCentsWithDecimals(data.creditsSubtotalCents)))")
                                .font(Typography.body)
                                .fontWeight(.semibold)
                                .foregroundStyle(BrandColors.textPrimary)
                        }
                        Divider()
                        HStack {
                            Text("Net Amount Due")
                                .font(Typography.body)
                                .fontWeight(.bold)
                                .foregroundStyle(BrandColors.primary)
                            Spacer()
                            Text(CurrencyFormatting.formatCentsWithDecimals(data.netDueCents))
                                .font(Typography.body)
                                .fontWeight(.bold)
                                .foregroundStyle(BrandColors.primary)
                        }
                    }
                }

                // Legend
                if data.hasFallbackPrices {
                    HStack(spacing: Spacing.xs) {
                        Circle()
                            .fill(.orange)
                            .frame(width: 8, height: 8)
                        Text("Using purchase price (no project price set)")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                }

                // Charges section
                if !data.chargeLines.isEmpty {
                    invoiceSection(
                        title: "Charges",
                        lines: data.chargeLines,
                        totalCents: data.chargesSubtotalCents,
                        totalLabel: "Charges Total"
                    )
                }

                // Credits section
                if !data.creditLines.isEmpty {
                    invoiceSection(
                        title: "Credits",
                        lines: data.creditLines,
                        totalCents: data.creditsSubtotalCents,
                        totalLabel: "Credits Total"
                    )
                }
            }
            .padding(Spacing.screenPadding)
            }
        }
        } // else
        } // Group
        .navigationTitle("Invoice")
        .navBarTitleDisplayMode(.inline)
        .task {
            if let urlString = businessLogoUrl, let url = URL(string: urlString) {
                if let (data, _) = try? await URLSession.shared.data(from: url),
                   let image = PlatformImage(data: data) {
                    logoImage = image
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .trailingNavBar) {
                Button {
                    sharePDF()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }

    // MARK: - Subviews

    private var invoiceHeader: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            if let logoImage {
                #if canImport(UIKit)
                Image(uiImage: logoImage)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: Dimensions.buttonRadius))
                #elseif canImport(AppKit)
                Image(nsImage: logoImage)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: Dimensions.buttonRadius))
                #endif
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if let businessName, !businessName.isEmpty {
                    Text(businessName)
                        .font(Typography.h1)
                        .foregroundStyle(BrandColors.primary)
                }
                Text("Invoice")
                    .font(Typography.h3)
                    .foregroundStyle(BrandColors.textPrimary)
                VStack(alignment: .leading, spacing: 2) {
                    metaRow(label: "Project:", value: projectName)
                    if !clientName.isEmpty {
                        metaRow(label: "Client:", value: clientName)
                    }
                    metaRow(label: "Date:", value: currentDateFormatted)
                }
            }
            Spacer()
        }
        .padding(.bottom, Spacing.md)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BrandColors.primary)
                .frame(height: 2)
        }
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(BrandColors.textSecondary)
            Text(value)
                .font(Typography.caption)
                .foregroundStyle(BrandColors.textSecondary)
        }
    }

    private func invoiceSection(
        title: String,
        lines: [InvoiceLineEntry],
        totalCents: Int,
        totalLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .sectionLabelStyle()

            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack {
                    Text(line.name)
                        .font(Typography.body)
                        .foregroundStyle(BrandColors.textPrimary)
                    Spacer()
                    Text(CurrencyFormatting.formatCentsWithDecimals(line.priceCents))
                        .font(Typography.body)
                        .foregroundStyle(
                            line.isMissingPrice ? .orange : BrandColors.textPrimary
                        )
                }
                .padding(.vertical, Spacing.xs)

                Divider()
            }

            // Section total
            HStack {
                Text(totalLabel)
                    .font(Typography.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(BrandColors.textPrimary)
                Spacer()
                Text(CurrencyFormatting.formatCentsWithDecimals(totalCents))
                    .font(Typography.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(BrandColors.textPrimary)
            }
            .padding(.vertical, Spacing.sm)
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
            clientName: clientName,
            businessName: businessName,
            logoImage: logoImage
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
    var businessName: String?
    var logoImage: PlatformImage?

    private typealias S = ReportPDFStyles

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            pdfHeader


            // Charges section
            if !data.chargeLines.isEmpty {
                pdfSection(title: "Charges", lines: data.chargeLines)
            }

            // Credits section
            if !data.creditLines.isEmpty {
                pdfSection(title: "Credits", lines: data.creditLines)
            }

            // Totals
            VStack(alignment: .trailing, spacing: 0) {
                pdfTotalsRow(label: "Charges Total", cents: data.chargesSubtotalCents)
                pdfTotalsRow(label: "Credits Total", cents: data.creditsSubtotalCents, showParens: true)
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
            pdfFooter
        }
        .frame(width: S.pageWidth - S.pagePadding * 2)
        .padding(S.pagePadding)
        .background(Color.white)
    }

    // MARK: - Header

    private var pdfHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            if let logoImage {
                #if canImport(UIKit)
                Image(uiImage: logoImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                #elseif canImport(AppKit)
                Image(nsImage: logoImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                #endif
            }
            VStack(alignment: .leading, spacing: 4) {
                if let businessName, !businessName.isEmpty {
                    Text(businessName)
                        .font(S.titleFont)
                        .foregroundStyle(S.brand)
                }
                Text("Invoice")
                    .font(S.subtitleFont)
                    .foregroundStyle(S.textDark)
                VStack(alignment: .leading, spacing: 2) {
                    pdfMetaRow(label: "Project:", value: projectName)
                    if !clientName.isEmpty {
                        pdfMetaRow(label: "Client:", value: clientName)
                    }
                }
                .foregroundStyle(S.textSecondary)
                .padding(.top, 4)
            }
            Spacer()
        }
        .padding(.bottom, 20)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(S.brand)
                .frame(height: S.headerBorderWidth)
        }
    }

    private func pdfMetaRow(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(S.metaLabelFont)
            Text(value)
                .font(S.metaFont)
        }
    }

    // MARK: - Invoice Lines Table

    private func pdfSection(title: String, lines: [InvoiceLineEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            Text(title)
                .font(S.sectionHeaderFont)
                .foregroundStyle(S.brand)
                .padding(.top, 28)
                .padding(.bottom, 12)

            // Table header row
            HStack(spacing: 0) {
                Text("ITEM")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("AMOUNT")
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

            // Data rows
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                HStack(spacing: 0) {
                    Text(line.name)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(CurrencyFormatting.formatCentsWithDecimals(line.priceCents))
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
    }

    // MARK: - Totals

    private func pdfTotalsRow(label: String, cents: Int, showParens: Bool = false) -> some View {
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

    private var pdfFooter: some View {
        Rectangle()
            .fill(S.border)
            .frame(height: 1)
            .padding(.top, 40)
    }
}
