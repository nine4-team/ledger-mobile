import SwiftUI

struct InvoiceReportView: View {
    let data: InvoiceReportData
    let projectName: String
    let clientName: String
    var businessName: String?
    var businessLogoUrl: String?
    var invoiceName: String? = nil
    var invoiceStatusLabel: String? = nil
    var invoiceDate: Date? = nil
    var notes: String? = nil
    var showsDownloadAction: Bool = true

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

                if let notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Notes").sectionLabelStyle()
                        Text(notes)
                            .font(Typography.body)
                            .foregroundStyle(BrandColors.textPrimary)
                    }
                    .padding(.top, Spacing.md)
                }
            }
            .padding(Spacing.screenPadding)
            }
        }
        } // else
        } // Group
        .textSelection(.enabled)
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
            if showsDownloadAction {
                ToolbarItem(placement: .trailingNavBar) {
                    Button {
                        downloadPDF()
                    } label: {
                        Image(systemName: "arrow.down.circle")
                    }
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
                    FindableText(businessName)
                        .font(Typography.h1)
                        .foregroundStyle(BrandColors.primary)
                }
                Text("Invoice")
                    .font(Typography.h3)
                    .foregroundStyle(BrandColors.textPrimary)
                if let invoiceName, !invoiceName.isEmpty {
                    FindableText(invoiceName)
                        .font(Typography.h3)
                        .foregroundStyle(BrandColors.textSecondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    metaRow(label: "Project:", value: projectName)
                    if !clientName.isEmpty {
                        metaRow(label: "Client:", value: clientName)
                    }
                    metaRow(label: "Date:", value: formattedDate(invoiceDate) ?? currentDateFormatted)
                    if let invoiceStatusLabel, !invoiceStatusLabel.isEmpty {
                        metaRow(label: "Status:", value: invoiceStatusLabel)
                    }
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
            FindableText(value)
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
                    FindableText(line.name)
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

    private func formattedDate(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }

    // MARK: - PDF Sharing

    private func downloadPDF() {
        let html = ReportHTMLBuilder.invoice(
            data: data,
            projectName: projectName,
            clientName: clientName,
            businessName: businessName,
            logoBase64: logoImage?.pngBase64,
            invoiceName: invoiceName,
            invoiceStatusLabel: invoiceStatusLabel,
            invoiceDate: invoiceDate,
            notes: notes
        )
        let label = (invoiceName?.isEmpty == false ? invoiceName! : projectName)
        ReportPDFSharing.downloadPDF(
            html: html,
            fileName: "invoice-\(label).pdf"
        )
    }
}
