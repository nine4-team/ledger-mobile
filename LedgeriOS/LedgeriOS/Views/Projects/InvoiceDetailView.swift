import SwiftUI

/// Invoice detail screen — shows the polished invoice (the same rendering the
/// client receives as a PDF) inline, with operator controls in the nav chrome.
/// Edit and Download live in a row above the preview; lifecycle actions
/// (Mark Sent / Mark Paid / Void) live in the toolbar kebab menu.
struct InvoiceDetailView: View {
    let invoice: Invoice

    @Environment(AccountContext.self) private var accountContext
    @Environment(ProjectContext.self) private var projectContext
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var showingMenu = false
    @State private var showingMarkPaidConfirm = false
    @State private var showingVoidConfirm = false
    @State private var showingEdit = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    // Always read the latest copy from AccountContext so cascades update the UI live.
    private var liveInvoice: Invoice {
        accountContext.allInvoices.first { $0.id == invoice.id } ?? invoice
    }

    private var status: InvoiceStatus {
        liveInvoice.status ?? .draft
    }

    private var reportData: InvoiceReportData {
        ReportAggregationCalculations.computeInvoiceReport(
            for: liveInvoice,
            items: projectContext.items,
            transactions: projectContext.transactions
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            chromeRow
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.vertical, Spacing.sm)
                .background(BrandColors.background)

            Divider()

            InvoiceReportView(
                data: reportData,
                projectName: projectContext.project?.name ?? "",
                clientName: projectContext.project?.clientName ?? "",
                businessName: accountContext.account?.name,
                businessLogoUrl: accountContext.account?.logo?.url,
                invoiceName: liveInvoice.invoiceNumber,
                invoiceStatusLabel: status.displayLabel,
                invoiceDate: liveInvoice.datePaid ?? liveInvoice.dateSent ?? liveInvoice.dateIssued,
                notes: liveInvoice.notes,
                showsDownloadAction: false
            )
        }
        .background(BrandColors.background)
        .navBarTitleDisplayMode(.inline)
        .navigationTitle(liveInvoice.invoiceNumber ?? "Invoice")
        .toolbar {
            ToolbarItem(placement: .trailingNavBar) {
                Button { showingMenu = true } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }
        }
        .adaptivePresentation(isPresented: $showingMenu, style: .quickMenu) {
            ActionMenuSheet(title: "Invoice Actions", items: menuItems)
        }
        .adaptivePresentation(isPresented: $showingEdit, style: .form) {
            CreateInvoiceModal(
                accountId: accountContext.currentAccountId ?? "",
                projectId: liveInvoice.projectId ?? "",
                editingInvoice: liveInvoice
            )
        }
        .confirmationDialog(
            "Mark this invoice as paid?",
            isPresented: $showingMarkPaidConfirm,
            titleVisibility: .visible
        ) {
            Button("Mark Paid") { performMarkPaid() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All items and expenses on this invoice will be updated to Paid.")
        }
        .confirmationDialog(
            "Void this invoice?",
            isPresented: $showingVoidConfirm,
            titleVisibility: .visible
        ) {
            Button("Void Invoice", role: .destructive) { performVoid() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Items and expenses will revert to Unbilled. Anything already marked Paid will stay Paid.")
        }
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Chrome row

    @ViewBuilder
    private var chromeRow: some View {
        HStack(spacing: Spacing.md) {
            statusBadge
            Spacer()
            if status == .draft {
                Button {
                    showingEdit = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .buttonStyle(.bordered)
            }
            Button {
                performDownload()
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var statusBadge: some View {
        let color: Color = {
            switch status {
            case .draft: return BrandColors.textSecondary
            case .sent: return StatusColors.inProgressText
            case .paid: return StatusColors.metText
            case .voided: return BrandColors.destructive
            }
        }()
        return Text(status.displayLabel)
            .font(Typography.caption.weight(.semibold))
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(color.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.30), lineWidth: 1))
            .foregroundStyle(color)
    }

    // MARK: - Menu

    private var menuItems: [ActionMenuItem] {
        var items: [ActionMenuItem] = []
        if status == .draft {
            items.append(ActionMenuItem(id: "sent", label: "Mark Sent", icon: "paperplane", onPress: { performMarkSent() }))
        }
        if status == .draft || status == .sent {
            items.append(ActionMenuItem(id: "paid", label: "Mark Paid", icon: "checkmark.circle", onPress: { showingMarkPaidConfirm = true }))
        }
        if status != .voided && status != .paid {
            items.append(ActionMenuItem(id: "void", label: "Void Invoice", icon: "trash", isDestructive: true, onPress: { showingVoidConfirm = true }))
        }
        return items
    }

    // MARK: - Actions

    private func performDownload() {
        let inv = liveInvoice
        let html = ReportHTMLBuilder.invoice(
            data: reportData,
            projectName: projectContext.project?.name ?? "",
            clientName: projectContext.project?.clientName ?? "",
            businessName: accountContext.account?.name,
            logoBase64: nil,
            invoiceName: inv.invoiceNumber,
            invoiceStatusLabel: status.displayLabel,
            invoiceDate: inv.datePaid ?? inv.dateSent ?? inv.dateIssued,
            notes: inv.notes
        )
        let label = (inv.invoiceNumber?.isEmpty == false ? inv.invoiceNumber! : (projectContext.project?.name ?? "invoice"))
        ReportPDFSharing.downloadPDF(html: html, fileName: "invoice-\(label).pdf")
    }

    private func performMarkSent() {
        guard let id = liveInvoice.id else { return }
        let acctId = accountContext.currentAccountId ?? ""
        let userId = authManager.currentUser?.uid
        runService { try await InvoiceService().markSent(invoiceId: id, accountId: acctId, userId: userId) }
    }

    private func performMarkPaid() {
        let acctId = accountContext.currentAccountId ?? ""
        let inv = liveInvoice
        let userId = authManager.currentUser?.uid
        runService { try await InvoiceService().markPaid(invoice: inv, accountId: acctId, userId: userId) }
    }

    private func performVoid() {
        let acctId = accountContext.currentAccountId ?? ""
        let inv = liveInvoice
        let userId = authManager.currentUser?.uid
        runService { try await InvoiceService().voidInvoice(invoice: inv, accountId: acctId, userId: userId) }
    }

    private func runService(_ block: @escaping @Sendable () async throws -> Void) {
        isWorking = true
        Task {
            do {
                try await block()
                await MainActor.run { isWorking = false }
            } catch {
                await MainActor.run {
                    errorMessage = "Action failed. Please try again."
                    isWorking = false
                }
            }
        }
    }
}
