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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(projectName)
                .font(.title2.bold())
            if !clientName.isEmpty {
                Text(clientName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none))
                .font(.caption)
                .foregroundStyle(.tertiary)

            Divider()

            if !data.chargeLines.isEmpty {
                Text("CHARGES")
                    .font(.caption.weight(.semibold))
                ForEach(Array(data.chargeLines.enumerated()), id: \.offset) { _, line in
                    HStack {
                        Text(line.displayName)
                        Spacer()
                        Text(formatCents(line.amountCents))
                    }
                    .font(.body)
                }
            }

            if !data.creditLines.isEmpty {
                Text("CREDITS")
                    .font(.caption.weight(.semibold))
                ForEach(Array(data.creditLines.enumerated()), id: \.offset) { _, line in
                    HStack {
                        Text(line.displayName)
                        Spacer()
                        Text(formatCents(line.amountCents))
                    }
                    .font(.body)
                }
            }

            Divider()

            HStack {
                Text("Charges Subtotal")
                Spacer()
                Text(formatCents(data.chargesSubtotalCents))
            }
            .font(.body)

            HStack {
                Text("Credits Subtotal")
                Spacer()
                Text(formatCents(data.creditsSubtotalCents))
            }
            .font(.body)

            HStack {
                Text("Net Due")
                    .bold()
                Spacer()
                Text(formatCents(data.netDueCents))
                    .bold()
            }
            .font(.body)
        }
        .padding(24)
        .frame(width: 612)
    }

    private func formatCents(_ cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        return String(format: "$%.2f", dollars)
    }
}
