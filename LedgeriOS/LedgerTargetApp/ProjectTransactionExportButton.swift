import LedgerTargetCore
import LedgerTargetPowerSync
import SwiftUI

/// Binds the original Project Options/field sheet to the target reader and
/// existing system handoff. The download watch remains owned until handoff ends.
struct ProjectTransactionExportButton: View {
    let scope: TransactionScope
    let reader: any TransactionBrowsing
    var orderedTransactionIDs: [TransactionID]? = nil
    var processedSourceRows: [TransactionDetailSnapshot]? = nil
    var canOpen = true
    private struct Request {
        let id = UUID()
        let scope: TransactionScope
        let selection: [TransactionID]?
        let processedSourceRows: [TransactionDetailSnapshot]?
        let asOf: ProtectedArtifactEpochMilliseconds
    }
    @State private var optionsPresented = false
    @State private var exportAfterOptions = false
    @State private var fieldsPresented = false
    @State private var request: Request?
    @State private var snapshot: TransactionExportSnapshot?
    @State private var selectedFields = TransactionExportCalculations.targetDefaultSelectedIds
    @State private var formError: String?
    @State private var deliveryError: String?
    @State private var prepared: (TransactionExportSnapshot, Data)?
    @State private var deliveryTask: Task<Void, Never>?

    private var fields: [ExportFieldConfig] {
        ExportFields.all + [
            .init(id: "receiptLines", label: "Receipt Lines", defaultSelected: false),
            .init(id: "receiptLinesJSON", label: "Receipt Lines JSON", defaultSelected: false),
            .init(id: "receiptAuditStatus", label: "Receipt Audit", defaultSelected: false),
            .init(id: "receiptItemTotal", label: "Items Subtotal", defaultSelected: false),
            .init(id: "receiptAdjustments", label: "Adjustments", defaultSelected: false),
            .init(id: "receiptDifference", label: "Difference", defaultSelected: false),
            .init(id: "receiptAuditJSON", label: "Exact Item Adjustment Details JSON", defaultSelected: false),
            .init(id: "receiptLineIncreaseTotal", label: "Receipt Increases", defaultSelected: false),
            .init(id: "receiptLineDecreaseTotal", label: "Receipt Decreases", defaultSelected: false),
            .init(id: "receiptReconstructedTotal", label: "Reconstructed Receipt Total", defaultSelected: false),
            .init(id: "receiptVariance", label: "Receipt Variance (Reconstructed − Total)", defaultSelected: false)]
    }

    var body: some View {
        Button { optionsPresented = true } label: {
            Image(systemName: "ellipsis").foregroundStyle(BrandColors.textSecondary)
        }
        .accessibilityLabel("Project Options")
        .accessibilityIdentifier("target-project-options")
        .disabled(deliveryTask != nil || !canOpen)
        .adaptivePresentation(isPresented: $optionsPresented, style: .quickMenu, onDismiss: {
            guard exportAfterOptions else { return }
            exportAfterOptions = false
            do {
                request = Request(scope: scope, selection: orderedTransactionIDs,
                    processedSourceRows: processedSourceRows,
                    asOf: try .init(validating: Int64(Date().timeIntervalSince1970 * 1_000)))
                snapshot = nil; formError = nil; selectedFields = TransactionExportCalculations.targetDefaultSelectedIds
                fieldsPresented = true
            } catch { deliveryError = "Export could not be opened." }
        }) {
            ActionMenuSheet(title: "Project Options", items: [
                ActionMenuItem(id: "export", label: "Export Transactions", icon: "square.and.arrow.up",
                    onPress: { exportAfterOptions = true })],
                onSelectAction: { action in action() })
        }
        .adaptivePresentation(isPresented: $fieldsPresented, style: .selectionMenu, onDismiss: finishSelection) {
            ExportTransactionFieldsForm(transactionCount: snapshot?.rows.count, fields: fields,
                defaultSelectedIds: TransactionExportCalculations.targetDefaultSelectedIds, selectedFieldIds: $selectedFields,
                errorMessage: formError, canExport: snapshot != nil, onExport: prepare)
        }
        .task(id: request?.id) {
            guard let request, let exporter = reader as? any TransactionExportReading else {
                if request != nil { formError = "Transaction export is not connected yet." }
                return
            }
            do {
                for try await update in reader.watchTransactions(scope: request.scope) {
                    try Task.checkCancellation()
                    guard self.request?.id == request.id else { return }
                    switch update {
                    case .incomplete:
                        snapshot = nil; formError = "Transactions have not finished downloading."
                    case .unavailable:
                        snapshot = nil; formError = "Project Transactions are unavailable."
                    case .partial, .ready:
                        do {
                            let value = try await exporter.readTransactionExport(scope: request.scope,
                                orderedTransactionIDs: request.selection, asOf: request.asOf)
                            if let source = request.processedSourceRows, try !value.hasSameSourceRows(source) {
                                throw TransactionExportSnapshot.Failure.incomplete
                            }
                            try Task.checkCancellation()
                            guard self.request?.id == request.id else { return }
                            snapshot = value; formError = nil
                        } catch is CancellationError { throw CancellationError() }
                        catch {
                            try Task.checkCancellation()
                            guard self.request?.id == request.id else { return }
                            snapshot = nil
                            formError = "A complete authorized export is not available. Wait for the download or reopen export."
                        }
                    }
                }
                guard self.request?.id == request.id else { return }
                snapshot = nil
                formError = "Project Transactions are unavailable."
            } catch {
                guard self.request?.id == request.id else { return }
                snapshot = nil
                if !Task.isCancelled { formError = "Project Transactions are unavailable." }
            }
        }
        .onDisappear { stop() }
        .onChange(of: scope) { _, _ in stop() }
        .alert("Export failed", isPresented: Binding(get: { deliveryError != nil }, set: { if !$0 { deliveryError = nil } })) {
            Button("OK") { deliveryError = nil }
        } message: { Text(deliveryError ?? "") }
    }

    private func prepare() {
        guard let snapshot else { return }
        do {
            let csv = try TransactionExportCalculations.exportTransactionsCSV(snapshot: snapshot,
                selectedFields: fields.filter { selectedFields.contains($0.id) })
            prepared = (snapshot, Data(csv.utf8)); fieldsPresented = false
        } catch TransactionExportValues.Failure.incompleteField(let id) {
            let label = fields.first { $0.id == id }?.label ?? "This field"
            formError = "\(label) requires complete authorized Item category data. Deselect it to export the other fields."
        } catch TransactionExportValues.Failure.unavailableField(let id) {
            let label = fields.first { $0.id == id }?.label ?? "This field"
            formError = "\(label) export is not implemented yet. Deselect it to export the other fields."
        } catch { formError = "The selected fields could not be exported." }
    }

    private func finishSelection() {
        guard let prepared, let exporter = reader as? any TransactionExportReading else {
            self.prepared = nil; request = nil; snapshot = nil; return
        }
        self.prepared = nil
        deliveryTask = Task { @MainActor in
            defer { deliveryTask = nil; request = nil; snapshot = nil }
            do {
                try await TransactionExportDelivery.deliver(data: prepared.1, snapshot: prepared.0, reader: exporter) { url in
                    try await PropertyManagementReportSystemDelivery.handoff(url, action: .share)
                }
            } catch is CancellationError { }
            catch { deliveryError = "Export could not be shared. The data or your access may have changed. Please try again." }
        }
    }

    private func stop() {
        prepared = nil; request = nil; snapshot = nil; fieldsPresented = false
        deliveryTask?.cancel()
    }
}
