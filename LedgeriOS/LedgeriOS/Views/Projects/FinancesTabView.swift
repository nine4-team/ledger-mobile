import SwiftUI

struct FinancesTabView: View {
    @State private var selectedSubtab = "budget"

    var body: some View {
        VStack(spacing: 0) {
            SegmentedControl(selection: $selectedSubtab, options: [
                SegmentOption(id: "budget", label: "Budget"),
                SegmentOption(id: "billing", label: "Billing"),
                SegmentOption(id: "reports", label: "Reports"),
            ])
            .frame(maxWidth: Dimensions.contentMaxWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.vertical, Spacing.sm)

            switch selectedSubtab {
            case "reports":
                AccountingTabView()
            case "billing":
                BillingSubTab()
            default:
                BudgetTabView()
            }
        }
    }
}

// MARK: - Billing Sub-Tab

private struct BillingSubTab: View {
    @Environment(AccountContext.self) private var accountContext
    @Environment(ProjectContext.self) private var projectContext
    @State private var showingCreateInvoice = false

    private var projectInvoices: [Invoice] {
        guard let projectId = projectContext.currentProjectId else { return [] }
        return accountContext.allInvoices
            .filter { $0.projectId == projectId }
            .sorted { ($0.dateIssued ?? .distantPast) > ($1.dateIssued ?? .distantPast) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                BillingSummaryCard()

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        Text("Invoices").sectionLabelStyle()
                        Spacer()
                        Button {
                            showingCreateInvoice = true
                        } label: {
                            Label("Create Invoice", systemImage: "plus.circle.fill")
                                .font(Typography.body.weight(.semibold))
                                .foregroundStyle(BrandColors.primary)
                        }
                        .buttonStyle(.plain)
                    }

                    if projectInvoices.isEmpty {
                        Card {
                            Text("No invoices yet. Tap Create Invoice to bill the client for approved items.")
                                .font(Typography.small)
                                .foregroundStyle(BrandColors.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        ForEach(projectInvoices, id: \.id) { invoice in
                            NavigationLink(value: invoice) {
                                InvoiceRow(invoice: invoice)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(Spacing.screenPadding)
            .frame(maxWidth: Dimensions.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .adaptivePresentation(isPresented: $showingCreateInvoice, style: .form) {
            if let accountId = accountContext.currentAccountId,
               let projectId = projectContext.currentProjectId {
                CreateInvoiceModal(accountId: accountId, projectId: projectId)
            }
        }
    }
}

// MARK: - Invoice Row

private struct InvoiceRow: View {
    let invoice: Invoice

    private var status: InvoiceStatus { invoice.status ?? .draft }

    private var statusColor: Color {
        switch status {
        case .draft: return BrandColors.textSecondary
        case .sent: return StatusColors.inProgressText
        case .paid: return StatusColors.metText
        case .voided: return BrandColors.destructive
        }
    }

    var body: some View {
        Card {
            HStack(alignment: .center, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: Spacing.sm) {
                        Text(invoice.invoiceNumber ?? "Invoice")
                            .font(Typography.body.weight(.semibold))
                            .foregroundStyle(BrandColors.textPrimary)
                        Text(status.displayLabel)
                            .font(Typography.caption.weight(.semibold))
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 2)
                            .background(statusColor.opacity(0.10), in: Capsule())
                            .overlay(Capsule().stroke(statusColor.opacity(0.30), lineWidth: 1))
                            .foregroundStyle(statusColor)
                    }
                    if let date = invoice.dateIssued {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)
                    }
                }
                Spacer()
                Text(CurrencyFormatting.formatCents(invoice.totalCents ?? 0))
                    .font(Typography.body.weight(.semibold))
                    .foregroundStyle(BrandColors.textPrimary)
                    .monospacedDigit()
            }
        }
    }
}
