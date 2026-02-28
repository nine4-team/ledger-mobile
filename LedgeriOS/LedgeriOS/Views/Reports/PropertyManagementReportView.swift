import SwiftUI

struct PropertyManagementReportView: View {
    let data: PropertyManagementData
    let projectName: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Space groups
                ForEach(Array(data.spaceGroups.enumerated()), id: \.offset) { _, group in
                    spaceSection(
                        title: group.space.name,
                        items: group.items,
                        marketValueCents: group.marketValueCents
                    )
                }

                // No Space section
                if !data.noSpaceItems.isEmpty {
                    spaceSection(
                        title: "No Space",
                        items: data.noSpaceItems,
                        marketValueCents: data.noSpaceItems.reduce(0) { $0 + ($1.marketValueCents ?? 0) }
                    )
                }

                // Summary footer
                Divider()

                VStack(spacing: Spacing.sm) {
                    HStack {
                        Text("Total Items")
                            .font(Typography.body)
                            .foregroundStyle(BrandColors.textSecondary)
                        Spacer()
                        Text("\(data.totalItemCount)")
                            .font(Typography.h3)
                            .foregroundStyle(BrandColors.textPrimary)
                    }
                    HStack {
                        Text("Total Market Value")
                            .font(Typography.body)
                            .foregroundStyle(BrandColors.textSecondary)
                        Spacer()
                        Text(CurrencyFormatting.formatCentsWithDecimals(data.totalMarketValueCents))
                            .font(Typography.h3)
                            .foregroundStyle(BrandColors.textPrimary)
                    }
                }
            }
            .padding(Spacing.screenPadding)
        }
        .navigationTitle("Property Management")
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

    private func spaceSection(title: String, items: [Item], marketValueCents: Int) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text(title)
                    .sectionLabelStyle()
                Spacer()
                Text(CurrencyFormatting.formatCentsWithDecimals(marketValueCents))
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textTertiary)
            }

            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(Typography.body)
                            .foregroundStyle(BrandColors.textPrimary)
                        HStack(spacing: Spacing.sm) {
                            if let source = item.source {
                                Text(source)
                                    .font(Typography.caption)
                                    .foregroundStyle(BrandColors.textTertiary)
                            }
                            if let sku = item.sku {
                                Text("SKU: \(sku)")
                                    .font(Typography.caption)
                                    .foregroundStyle(BrandColors.textTertiary)
                            }
                        }
                    }
                    Spacer()
                    Text(CurrencyFormatting.formatCentsWithDecimals(item.marketValueCents ?? 0))
                        .font(Typography.body)
                        .foregroundStyle(BrandColors.textSecondary)
                }
                .padding(.vertical, Spacing.xs)

                Divider()
            }
        }
    }

    // MARK: - PDF Sharing

    private func sharePDF() {
        let pdfContent = PropertyManagementPDFContent(data: data, projectName: projectName)
        ReportPDFSharing.sharePDF(
            content: pdfContent,
            fileName: "property-management-\(projectName).pdf"
        )
    }
}

// MARK: - PDF Content View

private struct PropertyManagementPDFContent: View {
    let data: PropertyManagementData
    let projectName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Property Management — \(projectName)")
                .font(.title2.bold())
            Text(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none))
                .font(.caption)
                .foregroundStyle(.tertiary)

            Divider()

            ForEach(Array(data.spaceGroups.enumerated()), id: \.offset) { _, group in
                Text(group.space.name.uppercased())
                    .font(.caption.weight(.semibold))
                ForEach(Array(group.items.enumerated()), id: \.offset) { _, item in
                    HStack {
                        Text(item.name)
                        if let source = item.source {
                            Text("(\(source))")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(formatCents(item.marketValueCents ?? 0))
                    }
                    .font(.body)
                }
            }

            if !data.noSpaceItems.isEmpty {
                Text("NO SPACE")
                    .font(.caption.weight(.semibold))
                ForEach(Array(data.noSpaceItems.enumerated()), id: \.offset) { _, item in
                    HStack {
                        Text(item.name)
                        Spacer()
                        Text(formatCents(item.marketValueCents ?? 0))
                    }
                    .font(.body)
                }
            }

            Divider()

            HStack {
                Text("Total Items: \(data.totalItemCount)")
                Spacer()
                Text("Total Market Value: \(formatCents(data.totalMarketValueCents))")
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
