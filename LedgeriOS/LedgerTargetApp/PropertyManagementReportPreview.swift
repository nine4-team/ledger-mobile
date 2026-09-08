import Foundation
import LedgerTargetCore
import LedgerTargetAppModel
import LedgerTargetPowerSync
import SwiftUI

struct PropertyManagementReportPreview: View {
    let accountId: AccountID
    let projectId: ProjectID
    let currency: CurrencyCode
    let watcher: any PropertyManagementReportWatching
    let reader: (any PropertyManagementReportReading)?
    @State private var model = PropertyManagementReportModel()
    @State private var refresh = UUID()
    @State private var exporting = false
    @State private var exportError: String?

    private struct Request: Equatable {
        let accountId: AccountID
        let projectId: ProjectID
        let currency: CurrencyCode
        let refresh: UUID
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if exporting {
                    ProgressView("Preparing or delivering report…")
                        .accessibilityIdentifier("target-property-report-exporting")
                }
                if let exportError {
                    Text(exportError).foregroundStyle(.red)
                        .accessibilityIdentifier("target-property-report-export-error")
                }
                switch model.state {
                case .idle, .loading:
                    ProgressView("Loading report…")
                        .accessibilityIdentifier("target-property-report-loading")
                case .incomplete:
                    Text("The report is not ready. Some required data has not finished downloading. Reconnect or refresh to try again.")
                        .accessibilityIdentifier("target-property-report-incomplete")
                case .unavailable:
                    Text("Report unavailable. Access or required Project data may have changed. Refresh to try again.")
                        .accessibilityIdentifier("target-property-report-unavailable")
                case .ready(let snapshot):
                    if snapshot.project.accountId == accountId && snapshot.project.projectId == projectId && snapshot.currency == currency {
                        report(snapshot)
                    } else {
                        ProgressView("Loading report…")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Property Management")
        .toolbar {
            Button("Share") { export(.share) }
                .disabled(!canExport)
                .accessibilityIdentifier("target-property-report-share")
            Button("Print") { export(.print) }
                .disabled(!canExport)
                .accessibilityIdentifier("target-property-report-print")
            Button("Share CSV") { export(.share, format: .csv) }
                .disabled(!canExport)
                .accessibilityIdentifier("target-property-report-csv")
            Button("Refresh") { refresh = UUID() }
                .accessibilityIdentifier("target-property-report-refresh")
        }
        .task(id: Request(accountId: accountId, projectId: projectId, currency: currency, refresh: refresh)) {
            await model.load(accountId: accountId, projectId: projectId, currency: currency, watcher: watcher)
        }
        .onDisappear { model.clear() }
    }

    private var canExport: Bool {
        guard !exporting, reader != nil, case .ready(let snapshot) = model.state else { return false }
        return snapshot.project.accountId == accountId && snapshot.project.projectId == projectId && snapshot.currency == currency
    }

    private func export(_ action: PropertyManagementReportSystemDelivery.Action, format: ReportScratchFormat = .pdf) {
        guard canExport, let reader, case .ready(let snapshot) = model.state else { return }
        exporting = true
        exportError = nil
        // This task deliberately outlives disappearance while the OS owns a
        // handoff. The watched model is checked again before presenting it.
        Task { @MainActor in
            defer { exporting = false }
            do {
                let bytes = try await Task.detached {
                    switch format {
                    case .pdf: try PropertyManagementReportPDF.render(snapshot)
                    case .csv: Data(PropertyManagementReportCSV.render(snapshot).utf8)
                    }
                }.value
                try await PropertyManagementReportDelivery.deliver(data: bytes, format: format, snapshot: snapshot, reader: reader) { url in
                    guard case .ready(let visible) = model.state, visible.reference == snapshot.reference else {
                        throw PropertyManagementReportDeliveryFailure.snapshotChanged
                    }
                    try await PropertyManagementReportSystemDelivery.handoff(url, action: action)
                }
            } catch PropertyManagementReportDeliveryFailure.snapshotChanged {
                exportError = "The report changed. Refresh and try sharing or printing again."
            } catch {
                exportError = "The report could not be shared or printed. Refresh and try again."
            }
        }
    }

    @ViewBuilder private func report(_ snapshot: PropertyManagementReportSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(snapshot.project.name).font(.title2.bold())
            Text(snapshot.project.address ?? "Property address not provided")
            let date = Date(timeIntervalSince1970: Double(snapshot.provenance.asOf.rawValue) / 1_000)
            Text("As of \(date.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(.secondary)
        }
        if snapshot.totals.itemCount == 0 {
            Text("No data for this report")
                .accessibilityIdentifier("target-property-report-empty")
        } else {
            ForEach(snapshot.groups, id: \.spaceId) { group in
                VStack(alignment: .leading, spacing: 12) {
                    Text(group.name).font(.headline)
                    ForEach(group.rows, id: \.itemId) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name).font(.body.weight(.medium))
                            Text("SKU: \(item.sku ?? "Not provided")")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("Market value: \(PropertyManagementReportHTML.value(item.marketValue))")
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("target-property-report-item-\(item.itemId.rawValue)")
                    }
                    totals(group.totals)
                }
                Divider()
            }
        }
        VStack(alignment: .leading, spacing: 8) {
            Text("Report totals").font(.headline)
            totals(snapshot.totals)
        }
        .accessibilityIdentifier("target-property-report-totals")
    }

    @ViewBuilder private func totals(_ totals: PropertyManagementReportTotals) -> some View {
        Text("Items: \(totals.itemCount)")
        if let value = totals.totalMarketValue {
            Text("Total market value: \(PropertyManagementReportHTML.value(value))")
        } else {
            Text("Known market value subtotal: \(PropertyManagementReportHTML.value(totals.knownMarketValueSubtotal))")
            Text("Unknown values: \(totals.unknownMarketValueCount)")
                .foregroundStyle(.secondary)
        }
    }
}
