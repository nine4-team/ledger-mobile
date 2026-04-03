import SwiftUI

struct ClientSummaryReportView: View {
    let data: ClientSummaryData
    let projectName: String
    var clientName: String?
    var businessName: String?
    var businessLogoUrl: String?

    @State private var logoImage: PlatformImage?
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
        if data.items.isEmpty {
            ContentUnavailableView("No Items", systemImage: "doc.text", description: Text("No items available for this report."))
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
                                FindableText(breakdown.categoryName)
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
                                    FindableText(clientItem.item.displayName)
                                        .font(Typography.body)
                                        .foregroundStyle(BrandColors.textPrimary)
                                    HStack(spacing: Spacing.sm) {
                                        if let source = clientItem.item.source, !source.isEmpty {
                                            FindableText(source)
                                                .font(Typography.caption)
                                                .foregroundStyle(BrandColors.textTertiary)
                                        }
                                        if let spaceName = clientItem.spaceName {
                                            FindableText(spaceName)
                                                .font(Typography.caption)
                                                .foregroundStyle(BrandColors.textTertiary)
                                        }
                                    }
                                }
                                Spacer()
                                HStack(spacing: Spacing.sm) {
                                    receiptLinkView(clientItem.receiptLink)
                                    Text(CurrencyFormatting.formatCentsWithDecimals(
                                        ReportAggregationCalculations.clientPriceCents(for: clientItem.item)
                                    ))
                                    .font(Typography.body)
                                    .foregroundStyle(BrandColors.textSecondary)
                                }
                            }
                            .padding(.vertical, Spacing.xs)

                            Divider()
                        }

                        // Items total
                        HStack {
                            Text("Total")
                                .font(Typography.body)
                                .fontWeight(.semibold)
                                .foregroundStyle(BrandColors.textPrimary)
                            Spacer()
                            Text(CurrencyFormatting.formatCentsWithDecimals(data.totalSpentCents))
                                .font(Typography.body)
                                .fontWeight(.semibold)
                                .foregroundStyle(BrandColors.textPrimary)
                        }
                        .padding(.top, Spacing.sm)
                    }
                }
            }
            .padding(Spacing.screenPadding)
            }
        }
        } // else
        } // Group
        .navigationTitle("Client Summary")
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
    private func receiptLinkView(_ link: ReceiptLink) -> some View {
        switch link {
        case .invoice:
            NavigationLink(value: ReportType.invoice) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                    Text("View Receipt")
                }
                .font(Typography.caption)
                .foregroundStyle(BrandColors.primary)
            }
        case .receiptURL(let urlString):
            Button {
                Task {
                    if let resolved = await StorageURLResolver.resolve(urlString) {
                        openURL(resolved)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "photo")
                    Text("View Receipt")
                }
                .font(Typography.caption)
                .foregroundStyle(BrandColors.primary)
            }
        case .none:
            EmptyView()
        }
    }

    // MARK: - PDF Sharing

    private func sharePDF() {
        Task {
            // Pre-resolve gs:// receipt URLs so the PDF can embed clickable links
            var resolvedURLs: [String: URL] = [:]
            for clientItem in data.items {
                if case .receiptURL(let urlString) = clientItem.receiptLink {
                    if let resolved = await StorageURLResolver.resolve(urlString) {
                        resolvedURLs[urlString] = resolved
                    }
                }
            }

            let html = ReportHTMLBuilder.clientSummary(
                data: data,
                projectName: projectName,
                clientName: clientName,
                businessName: businessName,
                logoBase64: logoImage?.pngBase64,
                resolvedReceiptURLs: resolvedURLs
            )
            ReportPDFSharing.sharePDF(
                html: html,
                fileName: "client-summary-\(projectName).pdf"
            )
        }
    }
}
