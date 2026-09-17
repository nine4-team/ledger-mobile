import LedgerTargetCore
import LedgerTargetAppModel
import LedgerTargetPowerSync
import SwiftUI

/// Data adapter for the original report view. Own the authorized watch instead
/// of retaining a financial snapshot from the preceding list after revocation.
struct InvoicingInvoicePreview: View {
    let runtime: any ProjectInvoicingReading
    let accountId: AccountID
    let projectId: ProjectID
    let invoiceId: InvoiceID
    let projectName: String
    let clientName: String
    @State private var report: CollectedInvoiceReportSnapshot?
    @State private var liveInvoice: LiveInvoiceContents?
    @State private var liveLoading = true
    private var invoice: FrozenInvoiceContents? { report?.invoice }
    @State private var loading = true
    @State private var find = FindStateManager()
    @State private var profileModel = AccountBusinessProfileModel()
    @State private var exporting = false
    @State private var exportTask: Task<Void, Never>?
    @State private var exportError: String?
    @State private var categoryNames: [[UInt8]: String] = [:]
    @State private var editingInvoice = false
    @State private var editState = InvoiceCreationFormState()
    @State private var pendingEdits: [PendingInvoiceRevision] = []

    var body: some View {
        Group {
            if let invoice {
                InvoiceReportView(data: reportData(invoice), projectName: projectName,
                    clientName: clientName, businessName: profile?.name.rawValue,
                    invoiceName: invoice.displayMetadata?.invoiceNumber,
                    invoiceStatusLabel: "Paid", invoiceDate: invoice.displayMetadata?.displayDate,
                    notes: invoice.displayMetadata?.notes, showsDownloadAction: false,
                    currencyCode: invoice.total.currency.rawValue, usesCurrentDateWhenMissing: false,
                    suppliedLogo: logo, provenance: provenance(invoice), totalLabel: "Invoice Total")
                    .accessibilityIdentifier("target-invoice-preview")
            } else if let liveInvoice {
                InvoiceReportView(data: liveReportData(liveInvoice), projectName: projectName,
                    clientName: clientName, businessName: profile?.name.rawValue,
                    invoiceName: liveInvoice.name, invoiceStatusLabel: liveInvoice.status.rawValue.capitalized,
                    invoiceDate: nil, notes: liveInvoice.notes, showsDownloadAction: false,
                    currencyCode: liveInvoice.total.currency.rawValue, usesCurrentDateWhenMissing: false,
                    suppliedLogo: logo, provenance: "Live Invoice: source edits update this total. Not collected.", totalLabel: "Invoice Total")
                    .accessibilityIdentifier("target-live-invoice-preview")
            } else if loading || liveLoading {
                ProgressView("Downloading Invoice")
            } else {
                ContentUnavailableView("Invoice unavailable", systemImage: "doc.text",
                    description: Text("The Invoice is not available in authorized downloaded data."))
                    .accessibilityIdentifier("target-invoice-preview-unavailable")
            }
        }
        .environment(find)
        .safeAreaInset(edge: .bottom) {
            if invoice != nil || liveInvoice != nil, let notice = brandingNotice {
                Text(notice).font(.caption).padding().background(.regularMaterial)
                    .accessibilityIdentifier("target-invoice-branding-notice")
            }
        }
        .toolbar {
            if invoice == nil, let liveInvoice, liveInvoice.status == .created,
               runtime is any ProjectInvoiceCreating, runtime is any ProjectInvoiceRevising {
                ToolbarItem(placement: .trailingNavBar) {
                    Button("Edit") {
                        editState.prepareEdit(liveInvoice)
                        editingInvoice = true
                    }
                    .disabled(pendingEdits.contains { $0.state != .rejected })
                    .accessibilityIdentifier("target-edit-invoice")
                }
            }
            ToolbarItem(placement: .trailingNavBar) {
                Button { download() } label: {
                    if exporting { ProgressView() } else { Image(systemName: "arrow.down.circle") }
                }
                .accessibilityLabel("Download Invoice")
                .accessibilityIdentifier("target-invoice-download")
                .disabled(exporting || (invoice == nil && liveInvoice == nil) || profile == nil)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !pendingEdits.isEmpty {
                VStack(alignment: .leading) {
                    ForEach(pendingEdits) { edit in
                        Text(edit.state == .rejected ? "Invoice edit was not saved to the server — review required."
                            : edit.state == .applied ? "Invoice edit saved — waiting for updated contents."
                            : "Invoice edit saved on this device — waiting to sync.")
                    }
                }.font(.caption).padding().background(.regularMaterial)
                    .accessibilityIdentifier("target-pending-invoice-edit")
            }
        }
        .adaptivePresentation(isPresented: $editingInvoice, style: .form) {
            if let service = runtime as? any ProjectInvoiceCreating {
                CreateInvoiceModal(accountId: accountId, projectId: projectId, service: service, state: editState) { _ in
                    editingInvoice = false
                }
            }
        }
        .alert("Invoice download failed", isPresented: Binding(get: { exportError != nil },
            set: { if !$0 { exportError = nil } })) {
            Button("OK") { exportError = nil }
        } message: { Text(exportError ?? "") }
        .task {
            if let reader = runtime as? any AccountBusinessProfileReading {
                await profileModel.load(accountId: accountId, reader: reader)
            }
        }
        .task {
            guard let reader = runtime as? any ExpenseCreating else { return }
            do {
                for try await snapshot in reader.watchBudgetCategories() {
                    guard !Task.isCancelled else { return }
                    guard snapshot.accountId.rawValue.utf8.elementsEqual(accountId.rawValue.utf8) else {
                        categoryNames = [:]; return
                    }
                    categoryNames = Dictionary(uniqueKeysWithValues: snapshot.local.rows.map {
                        (Array($0.id.rawValue.utf8), $0.name.rawValue)
                    })
                }
                if !Task.isCancelled { categoryNames = [:] }
            } catch {
                if !Task.isCancelled { categoryNames = [:] }
            }
        }
        .onDisappear {
            profileModel.clear()
            exportTask?.cancel()
        }
        .onChange(of: invoice == nil) { _, unavailable in
            if unavailable { exportTask?.cancel() }
        }
        .onChange(of: liveInvoice) { _, _ in
            if exporting { exportTask?.cancel() }
        }
        .task {
            do {
                for try await values in runtime.watchCollectedInvoices(accountId: accountId, projectId: projectId, invoiceId: invoiceId) {
                    guard !Task.isCancelled else { return }
                    if values?.contains(where: { $0.invoiceId == invoiceId }) == true {
                        report = try await runtime.readCollectedInvoiceReport(accountId: accountId,
                            projectId: projectId, invoiceId: invoiceId,
                            asOf: .init(validating: Int64(Date().timeIntervalSince1970 * 1000)))
                    } else { report = nil }
                    loading = false
                }
                if !Task.isCancelled { report = nil; loading = false }
            } catch {
                if !Task.isCancelled { report = nil; loading = false }
            }
        }
        .task {
            guard let reader = runtime as? any ProjectLiveInvoiceReading else { liveLoading = false; return }
            do {
                if let reviser = runtime as? any ProjectInvoiceRevising {
                    pendingEdits = try await reviser.readPendingInvoiceRevisions(accountId: accountId, projectId: projectId)
                        .filter { $0.payload.invoice.invoiceId == invoiceId }
                }
                for try await values in reader.watchLiveInvoices(accountId: accountId, projectId: projectId) {
                    let pending = try await (runtime as? any ProjectInvoiceRevising)?
                        .readPendingInvoiceRevisions(accountId: accountId, projectId: projectId) ?? []
                    guard !Task.isCancelled else { return }
                    pendingEdits = pending.filter { $0.payload.invoice.invoiceId == invoiceId }
                    liveInvoice = values?.first { $0.invoiceId == invoiceId }
                    liveLoading = false
                }
                if !Task.isCancelled { liveInvoice = nil; pendingEdits = []; editingInvoice = false; liveLoading = false }
            } catch { if !Task.isCancelled { liveInvoice = nil; pendingEdits = []; editingInvoice = false; liveLoading = false } }
        }
    }

    private var profile: AccountBusinessProfile? {
        guard case .downloaded(let profile) = profileModel.state else { return nil }
        return profile
    }

    private var logo: Image? {
        guard case .downloaded(let bytes) = profile?.logo,
              let image = AccountBusinessLogoImage.decode(bytes) else { return nil }
        return Image(decorative: image, scale: 1)
    }

    private var brandingNotice: String? {
        guard let profile else { return "Business profile unavailable or not downloaded." }
        var messages: [String] = []
        if profile.isStale { messages.append("Showing saved business profile.") }
        switch profile.logo {
        case .absent: break
        case .notDownloaded: messages.append("Business logo not downloaded.")
        case .unavailable: messages.append("Business logo unavailable.")
        case .downloaded: if logo == nil { messages.append("Business logo unavailable.") }
        }
        return messages.isEmpty ? nil : messages.joined(separator: " ")
    }

    private func download() {
        guard !exporting, let profile,
              let profileReader = runtime as? any AccountBusinessProfileReading else { return }
        let report = report, invoice = invoice, live = liveInvoice
        guard invoice != nil || live != nil else { return }
        let renderedCategoryNames = categoryNames
        exporting = true
        exportTask = Task { @MainActor in
            defer { exporting = false; exportTask = nil }
            do {
                try await PropertyManagementReportDelivery.withActivity(reader: runtime) {
                let logoBase64: String?
                if case .downloaded(let bytes) = profile.logo,
                   let image = AccountBusinessLogoImage.decode(bytes) {
                    #if canImport(UIKit)
                    logoBase64 = UIImage(cgImage: image).pngData()?.base64EncodedString()
                    #else
                    logoBase64 = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.base64EncodedString()
                    #endif
                } else { logoBase64 = nil }
                let html: String
                if let invoice, let report {
                    html = ReportHTMLBuilder.invoice(data: reportData(invoice), projectName: projectName,
                    clientName: clientName, businessName: profile.name.rawValue, logoBase64: logoBase64,
                    invoiceName: invoice.displayMetadata?.invoiceNumber, invoiceStatusLabel: "Paid",
                    invoiceDate: invoice.displayMetadata?.displayDate, notes: invoice.displayMetadata?.notes,
                    currencyCode: invoice.total.currency.rawValue, totalLabel: "Invoice Total",
                    provenance: "\(provenance(invoice, evidence: report.provenance)) \(brandingNotice ?? "")")
                } else if let live {
                    html = ReportHTMLBuilder.invoice(data: liveReportData(live), projectName: projectName,
                        clientName: clientName, businessName: profile.name.rawValue, logoBase64: logoBase64,
                        invoiceName: live.name, invoiceStatusLabel: live.status.rawValue.capitalized,
                        invoiceDate: nil, notes: live.notes, currencyCode: live.total.currency.rawValue,
                        totalLabel: "Invoice Total", provenance: "Live Invoice \(live.invoiceId.rawValue), revision \(live.revision). Downloaded source values; not collected. \(brandingNotice ?? "")")
                } else { throw CollectedInvoiceReportDeliveryFailure.snapshotChanged }
                let bytes: Data
                #if os(macOS)
                let scratch = try ReportScratchStore()
                do {
                    try await scratch.recoverAbandonedSessions()
                    bytes = try await scratch.generatePDF { url in
                        try await ReportPDFSharing.renderData(html: html, outputURL: url)
                    }
                    try await scratch.close()
                } catch {
                    try? await scratch.close()
                    throw error
                }
                #else
                bytes = try await ReportPDFSharing.renderData(html: html)
                #endif
                let handoff: @MainActor (URL) async throws -> Void = { url in
                    try await PDFDownloadHelper.downloadAndWait(url: url,
                        fileName: "invoice-\(invoice?.displayMetadata?.invoiceNumber ?? projectName).pdf") {
                        guard self.categoryNames == renderedCategoryNames,
                              try await profileReader.readAccountBusinessProfile(accountId: accountId).matchesExportedBranding(profile) else {
                            throw CollectedInvoiceReportDeliveryFailure.snapshotChanged
                        }
                        if let invoice, let report {
                            let current = try await runtime.readCollectedInvoiceReport(accountId: accountId,
                                projectId: projectId, invoiceId: invoiceId, asOf: report.provenance.asOf)
                            guard self.invoice == invoice, current.invoice == report.invoice,
                                  current.provenance.localDataVersion == report.provenance.localDataVersion,
                                  current.provenance.visibilityScopeID == report.provenance.visibilityScopeID else {
                                throw CollectedInvoiceReportDeliveryFailure.snapshotChanged
                            }
                        } else if let live, let reader = runtime as? any ProjectLiveInvoiceReading {
                            guard self.liveInvoice == live else {
                                throw CollectedInvoiceReportDeliveryFailure.snapshotChanged
                            }
                            try await CollectedInvoiceReportDelivery.revalidate(live, reader: reader)
                        } else { throw CollectedInvoiceReportDeliveryFailure.snapshotChanged }
                    }
                }
                if let invoice {
                    try await CollectedInvoiceReportDelivery.deliver(data: bytes, invoice: invoice, reader: runtime, handoff: handoff)
                } else if let live, let reader = runtime as? any ProjectLiveInvoiceReading {
                    try await CollectedInvoiceReportDelivery.deliver(data: bytes, invoice: live, reader: reader, handoff: handoff)
                } else { throw CollectedInvoiceReportDeliveryFailure.snapshotChanged }
                }
            } catch is CancellationError { }
            catch let error as ReportPDFSharing.RenderFailure {
                switch error {
                case .loadFailed: exportError = "The Invoice layout could not be loaded. Try again."
                case .renderFailed: exportError = "The Invoice PDF could not be generated. Try again."
                case .emptyDocument: exportError = "The Invoice renderer returned no pages. Try again."
                case .loadTimedOut: exportError = "The Invoice layout took too long to load. Try again."
                }
            }
            catch {
                print("Invoice download failure category: \(String(reflecting: type(of: error)))")
                exportError = "The Invoice could not be downloaded. Data or access may have changed. Try again."
            }
        }
    }

    private func provenance(_ invoice: FrozenInvoiceContents, evidence: PropertyManagementReportProvenance? = nil) -> String {
        let payment = "Invoice \(invoice.invoiceId.rawValue), revision \(invoice.invoiceRevision). Collected by Purchase \(invoice.purchaseId.rawValue). This payment is not an additional Invoice charge."
        guard let evidence = evidence ?? report?.provenance else { return payment }
        let source: String
        switch evidence.source {
        case .downloaded(let version, let checkpoint):
            source = "Downloaded data version \(version.rawValue). Last completed sync (UTC milliseconds): \(checkpoint.rawValue)."
        case .authoritative: source = "Authoritative data."
        }
        return "\(payment) \(source) Report read (UTC milliseconds): \(evidence.asOf.rawValue). Accounting: \(evidence.authorityVersion.rawValue)."
    }

    private func reportData(_ invoice: FrozenInvoiceContents) -> InvoiceReportData {
        let sections = invoice.reportSections()
        func entry(_ line: FrozenInvoiceLine, credit: Bool) -> InvoiceLineEntry {
            let fallback: Bool
            if case .item(_, _, let price) = line.source, case .purchaseCost = price.basis {
                fallback = true
            } else { fallback = false }
            let cents = Decimal(line.signedAmount.minorUnits)
            return InvoiceLineEntry(name: line.description, exactPriceCents: credit ? -cents : cents,
                isMissingPrice: fallback, categoryId: line.categoryId.rawValue,
                categoryName: categoryNames[Array(line.categoryId.rawValue.utf8)])
        }
        return InvoiceReportData(chargeLines: sections.charges.map { entry($0, credit: false) },
            creditLines: sections.credits.map { entry($0, credit: true) })
    }

    private func liveReportData(_ invoice: LiveInvoiceContents) -> InvoiceReportData {
        func entry(_ line: LiveInvoiceContents.Line) -> InvoiceLineEntry {
            let cents = Decimal(line.selection.reviewedAmount.minorUnits)
            return InvoiceLineEntry(name: line.description, exactPriceCents: cents < 0 ? -cents : cents,
                isMissingPrice: false, categoryId: line.categoryId.rawValue,
                categoryName: categoryNames[Array(line.categoryId.rawValue.utf8)])
        }
        return InvoiceReportData(chargeLines: invoice.lines.filter { $0.selection.reviewedAmount.minorUnits >= 0 }.map(entry),
            creditLines: invoice.lines.filter { $0.selection.reviewedAmount.minorUnits < 0 }.map(entry))
    }
}
