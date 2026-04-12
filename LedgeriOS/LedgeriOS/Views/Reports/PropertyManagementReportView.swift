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
                        FindableText(businessName)
                            .font(Typography.h2)
                            .foregroundStyle(BrandColors.textPrimary)
                    }
                    FindableText(projectName)
                        .font(Typography.h1)
                        .foregroundStyle(BrandColors.textPrimary)
                    if let clientName, !clientName.isEmpty {
                        FindableText(clientName)
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
                        marketValueCents: data.noSpaceItems.reduce(0) { $0 + ReportAggregationCalculations.propertyValueCents(for: $1) }
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
                FindableText(title)
                    .sectionLabelStyle()
                Spacer()
                Text(CurrencyFormatting.formatCentsWithDecimals(marketValueCents))
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textTertiary)
            }

            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        FindableText(item.displayName)
                            .font(Typography.body)
                            .foregroundStyle(BrandColors.textPrimary)
                        HStack(spacing: Spacing.sm) {
                            if let source = item.currentSource ?? item.source {
                                FindableText(source)
                                    .font(Typography.caption)
                                    .foregroundStyle(BrandColors.textTertiary)
                            }
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        let valueCents = ReportAggregationCalculations.propertyValueCents(for: item)
                        Text(CurrencyFormatting.formatCentsWithDecimals(valueCents))
                            .font(Typography.body)
                            .foregroundStyle(BrandColors.textSecondary)
                        if valueCents == 0 {
                            Text("No value")
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
        let html = ReportHTMLBuilder.propertyManagement(
            data: data,
            projectName: projectName,
            clientName: clientName,
            businessName: businessName,
            logoBase64: logoImage?.pngBase64
        )
        ReportPDFSharing.sharePDF(
            html: html,
            fileName: "property-management-\(projectName).pdf"
        )
    }
}
