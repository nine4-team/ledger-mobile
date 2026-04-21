import SwiftUI

enum ReportType: Hashable {
    case invoice
    case clientSummary
    case propertyManagement
}

struct AccountingTabView: View {
    @Environment(ProjectContext.self) private var projectContext
    @Environment(AccountContext.self) private var accountContext

    private var owedToCompanyCents: Int {
        projectContext.transactions
            .filter { $0.status != .canceled && ReportAggregationCalculations.reimbursementDirection(for: $0) == .owedToCompany }
            .reduce(0) { $0 + ($1.amountCents ?? 0) }
    }

    private var owedToClientCents: Int {
        projectContext.transactions
            .filter { $0.status != .canceled && ReportAggregationCalculations.reimbursementDirection(for: $0) == .owedToClient }
            .reduce(0) { $0 + ($1.amountCents ?? 0) }
    }

    var body: some View {
        ScrollView {
            AdaptiveContentWidth {
                VStack(spacing: Spacing.cardListGap) {
                    // Responsive grid for payable summary cards
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.cardListGap), count: 2),
                        spacing: Spacing.cardListGap
                    ) {
                        Card {
                            HStack {
                                VStack(alignment: .leading, spacing: Spacing.xs) {
                                    Text("Owed to Business")
                                        .font(Typography.small)
                                        .foregroundStyle(BrandColors.textSecondary)
                                    Text(CurrencyFormatting.formatCentsWithDecimals(owedToCompanyCents))
                                        .font(Typography.h2)
                                        .foregroundStyle(BrandColors.textPrimary)
                                }
                                Spacer()
                            }
                        }

                        Card {
                            HStack {
                                VStack(alignment: .leading, spacing: Spacing.xs) {
                                    Text("Owed to Client")
                                        .font(Typography.small)
                                        .foregroundStyle(BrandColors.textSecondary)
                                    Text(CurrencyFormatting.formatCentsWithDecimals(owedToClientCents))
                                        .font(Typography.h2)
                                        .foregroundStyle(BrandColors.textPrimary)
                                }
                                Spacer()
                            }
                        }
                    }

                    // Report navigation
                    Text("Reports")
                        .sectionLabelStyle()
                        .frame(maxWidth: .infinity, alignment: .leading)

                    NavigationLink(value: ReportType.propertyManagement) {
                        reportButton(
                            title: "Property Management Summary",
                            icon: "building.2"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink(value: ReportType.clientSummary) {
                        reportButton(
                            title: "Client Summary",
                            icon: "chart.bar.doc.horizontal"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink(value: ReportType.invoice) {
                        reportButton(
                            title: "Invoice",
                            icon: "doc.text"
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(Spacing.screenPadding)
            }
        }
        .navigationDestination(for: ReportType.self) { reportType in
            switch reportType {
            case .invoice:
                InvoiceReportView(
                    data: ReportAggregationCalculations.computeInvoiceReport(
                        transactions: projectContext.transactions,
                        items: accountContext.allItems,
                        categories: projectContext.budgetCategories
                    ),
                    projectName: projectContext.project?.name ?? "",
                    clientName: projectContext.project?.clientName ?? "",
                    businessName: accountContext.account?.name,
                    businessLogoUrl: accountContext.account?.logo?.url
                )
            case .clientSummary:
                ClientSummaryReportView(
                    data: ReportAggregationCalculations.computeClientSummary(
                        items: projectContext.items,
                        transactions: projectContext.transactions,
                        spaces: projectContext.spaces,
                        categories: projectContext.budgetCategories
                    ),
                    projectName: projectContext.project?.name ?? "",
                    clientName: projectContext.project?.clientName,
                    businessName: accountContext.account?.name,
                    businessLogoUrl: accountContext.account?.logo?.url
                )
            case .propertyManagement:
                PropertyManagementReportView(
                    data: ReportAggregationCalculations.computePropertyManagement(
                        items: projectContext.items,
                        spaces: projectContext.spaces
                    ),
                    projectName: projectContext.project?.name ?? "",
                    clientName: projectContext.project?.clientName,
                    businessName: accountContext.account?.name,
                    businessLogoUrl: accountContext.account?.logo?.url
                )
            }
        }
    }

    private func reportButton(title: String, icon: String) -> some View {
        Card {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(BrandColors.primary)
                    .frame(width: 24)
                Text(title)
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textTertiary)
            }
        }
    }
}
