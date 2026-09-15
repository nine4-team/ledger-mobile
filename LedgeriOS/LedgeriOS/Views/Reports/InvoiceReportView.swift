import SwiftUI
#if canImport(UIKit)
private typealias InvoiceReportPlatformImage = UIImage
#else
private typealias InvoiceReportPlatformImage = NSImage
#endif

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
    var currencyCode: String = "USD"
    var usesCurrentDateWhenMissing: Bool = true
    var loadLogo: (() async throws -> Data)? = nil
    var onDownload: (() -> Void)? = nil
    var suppliedLogo: Image? = nil
    var provenance: String? = nil
    var totalLabel: String = "Net Amount Due"

    @State private var logoImage: InvoiceReportPlatformImage?

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
                            Text(formatAmount(data.chargesSubtotalCents))
                                .font(Typography.body)
                                .fontWeight(.semibold)
                                .foregroundStyle(BrandColors.textPrimary)
                        }
                        HStack {
                            Text("Credits")
                                .font(Typography.small)
                                .foregroundStyle(BrandColors.textSecondary)
                            Spacer()
                            Text("(\(formatAmount(data.creditsSubtotalCents)))")
                                .font(Typography.body)
                                .fontWeight(.semibold)
                                .foregroundStyle(BrandColors.textPrimary)
                        }
                        Divider()
                        HStack {
                            Text(totalLabel)
                                .font(Typography.body)
                                .fontWeight(.bold)
                                .foregroundStyle(BrandColors.primary)
                            Spacer()
                            Text(formatAmount(data.netDueCents))
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

                if let provenance {
                    Text(provenance)
                        .accessibilityIdentifier("invoice-report-provenance")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                        .textSelection(.enabled)
                }
                if let notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Notes").sectionLabelStyle()
                        SelectableNoteText(text: notes, style: .body)
                    }
                    .padding(.top, Spacing.md)
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
            if let loadLogo {
                if let data = try? await loadLogo(), !Task.isCancelled {
                    logoImage = InvoiceReportPlatformImage(data: data)
                }
            } else if let urlString = businessLogoUrl, let url = URL(string: urlString) {
                if let (data, _) = try? await URLSession.shared.data(from: url),
                   let image = InvoiceReportPlatformImage(data: data) {
                    logoImage = image
                }
            }
        }
        .toolbar {
            if showsDownloadAction {
                ToolbarItem(placement: .trailingNavBar) {
                    Button {
                        if let onDownload { onDownload(); return }
                        #if canImport(FirebaseFirestore)
                        downloadPDF()
                        #endif
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
            if let image = displayedLogo {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: Dimensions.buttonRadius))
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
                    if let date = formattedDate(invoiceDate) {
                        metaRow(label: "Date:", value: date)
                    } else if usesCurrentDateWhenMissing {
                        metaRow(label: "Date:", value: currentDateFormatted)
                    }
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

    private var displayedLogo: Image? {
        if let suppliedLogo { return suppliedLogo }
        guard let logoImage else { return nil }
        #if canImport(UIKit)
        return Image(uiImage: logoImage)
        #else
        return Image(nsImage: logoImage)
        #endif
    }

    private func invoiceSection(
        title: String,
        lines: [InvoiceLineEntry],
        totalCents: Decimal,
        totalLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .sectionLabelStyle()

            ForEach(Array(InvoiceReportData.groups(lines).enumerated()), id: \.offset) { _, group in
                if group.categoryId != nil {
                    Text(group.categoryName ?? "Category name unavailable")
                        .font(Typography.body).fontWeight(.semibold).padding(.top, Spacing.sm)
                }
                ForEach(Array(group.lines.enumerated()), id: \.offset) { _, line in
                HStack {
                    FindableText(line.name)
                        .font(Typography.body)
                        .foregroundStyle(BrandColors.textPrimary)
                    Spacer()
                    Text(formatAmount(line.priceCents))
                        .font(Typography.body)
                        .foregroundStyle(
                            line.isMissingPrice ? .orange : BrandColors.textPrimary
                        )
                }
                .padding(.vertical, Spacing.xs)

                Divider()
                }
                if group.categoryId != nil {
                    HStack {
                        Text("Category Total")
                        Spacer()
                        Text(formatAmount(group.subtotalCents))
                    }.font(Typography.small).fontWeight(.semibold).padding(.vertical, Spacing.xs)
                }
            }

            // Section total
            HStack {
                Text(totalLabel)
                    .font(Typography.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(BrandColors.textPrimary)
                Spacer()
                Text(formatAmount(totalCents))
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

    private func formatAmount(_ cents: Decimal) -> String {
        (cents / 100).formatted(.currency(code: currencyCode))
    }

    #if canImport(FirebaseFirestore)
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
    #endif
}
