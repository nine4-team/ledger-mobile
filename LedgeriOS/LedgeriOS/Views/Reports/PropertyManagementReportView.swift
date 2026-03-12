import SwiftUI

struct PropertyManagementReportView: View {
    let data: PropertyManagementData
    let projectName: String
    var clientName: String?
    var businessName: String?
    var businessLogoUrl: String?

    @State private var logoImage: PlatformImage?

    var body: some View {
        Group {
        if data.spaceGroups.isEmpty && data.noSpaceItems.isEmpty {
            ContentUnavailableView("No Items", systemImage: "house", description: Text("No items assigned to spaces yet."))
        } else {
        ScrollView {
            AdaptiveContentWidth {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Header
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    if let logoImage {
                        #if canImport(UIKit)
                        Image(uiImage: logoImage)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 48)
                        #elseif canImport(AppKit)
                        Image(nsImage: logoImage)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 48)
                        #endif
                    }
                    if let businessName, !businessName.isEmpty {
                        Text(businessName)
                            .font(Typography.h2)
                            .foregroundStyle(BrandColors.textPrimary)
                    }
                    Text(projectName)
                        .font(Typography.h1)
                        .foregroundStyle(BrandColors.textPrimary)
                    if let clientName, !clientName.isEmpty {
                        Text(clientName)
                            .font(Typography.small)
                            .foregroundStyle(BrandColors.textSecondary)
                    }
                }

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
        }
        } // else
        } // Group
        .navigationTitle("Property Management")
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
                        Text(item.displayName)
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
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(CurrencyFormatting.formatCentsWithDecimals(item.marketValueCents ?? 0))
                            .font(Typography.body)
                            .foregroundStyle(BrandColors.textSecondary)
                        if item.marketValueCents == nil || item.marketValueCents == 0 {
                            Text("No market value")
                                .font(Typography.caption)
                                .foregroundStyle(BrandColors.textTertiary)
                        }
                    }
                }
                .padding(.vertical, Spacing.xs)

                Divider()
            }
        }
    }

    // MARK: - PDF Sharing

    private func sharePDF() {
        let pdfContent = PropertyManagementPDFContent(data: data, projectName: projectName, clientName: clientName, businessName: businessName, logoImage: logoImage)
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
    var clientName: String?
    var businessName: String?
    var logoImage: PlatformImage?

    private typealias S = ReportPDFStyles

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Branded header
            pdfHeader(title: "Property Management Summary")

            // Overview cards
            HStack(spacing: 12) {
                overviewCard(label: "Total Items", value: "\(data.totalItemCount)")
                overviewCard(label: "Total Market Value", value: CurrencyFormatting.formatCentsWithDecimals(data.totalMarketValueCents))
            }
            .padding(.top, 20)

            // Per-space grouped sections
            ForEach(Array(data.spaceGroups.enumerated()), id: \.offset) { _, group in
                spaceTableSection(
                    title: group.space.name,
                    items: group.items,
                    marketValueCents: group.marketValueCents
                )
            }

            // No Space section
            if !data.noSpaceItems.isEmpty {
                let noSpaceMarketValue = data.noSpaceItems.reduce(0) { $0 + ($1.marketValueCents ?? 0) }
                spaceTableSection(
                    title: "No Space",
                    items: data.noSpaceItems,
                    marketValueCents: noSpaceMarketValue
                )
            }

            // Footer
            pdfFooter()
        }
        .padding(S.pagePadding)
        .frame(width: S.pageWidth)
        .background(Color.white)
    }

    // MARK: - Space Table Section

    private func spaceTableSection(title: String, items: [Item], marketValueCents: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header with space name
            HStack {
                Text(title)
                    .font(S.sectionHeaderFont)
                    .foregroundStyle(S.brand)
                Spacer()
                Text(CurrencyFormatting.formatCentsWithDecimals(marketValueCents))
                    .font(S.bodyBoldFont)
                    .foregroundStyle(S.textDark)
            }
            .padding(.top, 28)
            .padding(.bottom, 12)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(S.border)
                    .frame(height: 1)
            }

            // Table header for this section
            HStack(spacing: 0) {
                Text("ITEM")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("SOURCE")
                    .frame(width: 120, alignment: .leading)
                Text("SKU")
                    .frame(width: 110, alignment: .leading)
                Text("MARKET VALUE")
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

            // Item rows with zebra striping restarting per section
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                itemRow(item: item, index: index)
            }
        }
    }

    // MARK: - Header

    private func pdfHeader(title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let logoImage {
                #if canImport(UIKit)
                Image(uiImage: logoImage)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 60)
                    .padding(.bottom, 8)
                #elseif canImport(AppKit)
                Image(nsImage: logoImage)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 60)
                    .padding(.bottom, 8)
                #endif
            }
            if let businessName, !businessName.isEmpty {
                Text(businessName)
                    .font(S.subtitleFont)
                    .foregroundStyle(S.textDark)
            }
            Text(projectName)
                .font(S.titleFont)
                .foregroundStyle(S.brand)
            Text(title)
                .font(S.subtitleFont)
                .foregroundStyle(S.textDark)
            VStack(alignment: .leading, spacing: 2) {
                if let clientName, !clientName.isEmpty {
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

    // MARK: - Item Row

    private func itemRow(item: Item, index: Int) -> some View {
        HStack(spacing: 0) {
            Text(item.displayName)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(item.source ?? "")
                .frame(width: 120, alignment: .leading)
            Text(item.sku ?? "")
                .frame(width: 110, alignment: .leading)
            if item.marketValueCents == nil || item.marketValueCents == 0 {
                Text("No market value")
                    .font(S.missingPriceFont)
                    .foregroundStyle(S.error)
                    .frame(width: 120, alignment: .trailing)
            } else {
                Text(CurrencyFormatting.formatCentsWithDecimals(item.marketValueCents ?? 0))
                    .frame(width: 120, alignment: .trailing)
            }
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
