import Foundation
import LedgerTargetCore
import LedgerTargetAppModel
import LedgerTargetPowerSync
import SwiftUI

struct ClientSummaryPhysicalReportPreview: View {
    let accountId: AccountID
    let projectId: ProjectID
    let watcher: any ClientSummaryPhysicalReportWatching
    let reader: any ClientSummaryPhysicalReportReading
    let profileReader: any AccountBusinessProfileReading
    @State private var model = ClientSummaryPhysicalReportModel()
    @State private var profileModel = AccountBusinessProfileModel()
    @State private var refresh = UUID()
    @State private var exporting = false
    @State private var exportError: String?

    private struct Request: Equatable {
        let accountId: AccountID
        let projectId: ProjectID
        let refresh: UUID
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AccountBusinessProfileView(accountId: accountId, reader: profileReader, model: profileModel)
                if exporting { ProgressView("Preparing or delivering report…") }
                if let exportError { Text(exportError).foregroundStyle(.red) }
                switch model.state {
                case .idle, .loading:
                    ProgressView("Loading report…").accessibilityIdentifier("target-client-report-loading")
                case .incomplete:
                    incompleteMessage
                case .unavailable:
                    Text("Report unavailable. Access or required Project data may have changed. Refresh to try again.")
                        .accessibilityIdentifier("target-client-report-unavailable")
                case .ready(let snapshot):
                    if snapshot.project.accountId == accountId && snapshot.project.projectId == projectId {
                        report(snapshot)
                    } else { ProgressView("Loading report…") }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding()
        }
        .navigationTitle("Client Summary")
        .toolbar {
            ToolbarItemGroup {
                Button("Refresh") { refresh = UUID() }.accessibilityIdentifier("target-client-report-refresh")
                Button("Share") { share() }.disabled(!canExport).accessibilityIdentifier("target-client-report-share")
            }
        }
        .task(id: Request(accountId: accountId, projectId: projectId, refresh: refresh)) {
            await model.load(accountId: accountId, projectId: projectId, watcher: watcher)
        }
        .onDisappear { model.clear() }
    }

    private var incompleteMessage: some View {
        Text("This report is incomplete. Required downloads, Item accounting relationships or categories are missing. Refresh after the data is available. Sharing is disabled.")
            .accessibilityIdentifier("target-client-report-incomplete")
    }

    @ViewBuilder private func report(_ snapshot: ClientSummaryPhysicalReportSnapshot) -> some View {
        Text(snapshot.project.name).font(.title2.bold())
        if case .known(_, let name, _) = snapshot.client { Text("Client: \(name)") }
        Text("Physical Item detail").font(.headline)
        Text("As of \(Date(timeIntervalSince1970: Double(snapshot.provenance.asOf.rawValue) / 1000).formatted(date: .abbreviated, time: .shortened))")
            .font(.caption).foregroundStyle(.secondary)
        if !snapshot.isComplete { incompleteMessage }
        if snapshot.items.isEmpty && snapshot.isComplete {
            Text("No data for this report").accessibilityIdentifier("target-client-report-empty")
        }
        ForEach(snapshot.items, id: \.itemId) { item in
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).font(.body.weight(.medium))
                Text("SKU: \(item.sku ?? "Not provided")")
                if case .known(_, let name) = item.category { Text("Category: \(name)") }
                else { Text("Category unavailable").foregroundStyle(.secondary) }
                Text("Space: \(item.spaceId.flatMap { id in snapshot.spaces.first { $0.spaceId == id }?.name } ?? "No Space")")
                if item.accounting?.resolution != .accountedFor {
                    Text("Accounting evidence incomplete").foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("target-client-report-item-\(item.itemId.rawValue)")
            Divider()
        }
    }

    private var canExport: Bool {
        guard !exporting, case .ready(let snapshot) = model.state, snapshot.isComplete,
              snapshot.project.accountId == accountId, snapshot.project.projectId == projectId,
              case .downloaded(let profile) = profileModel.state, profile.accountId == accountId else { return false }
        return true
    }

    private func share() {
        guard canExport, case .ready(let snapshot) = model.state,
              case .downloaded(let profile) = profileModel.state else { return }
        exporting = true
        exportError = nil
        Task { @MainActor in
            defer { exporting = false }
            do {
                let bytes = try await Task.detached { try ClientSummaryPhysicalReportPDF.render(snapshot, profile: profile) }.value
                try await ClientSummaryPhysicalReportDelivery.deliver(data: bytes, snapshot: snapshot, reader: reader) { url in
                    guard case .ready(let visible) = model.state, visible.reference == snapshot.reference,
                          try await profileReader.readAccountBusinessProfile(accountId: accountId).matchesExportedBranding(profile),
                          case .downloaded(let current) = profileModel.state, current == profile else {
                        throw ClientSummaryPhysicalReportDeliveryFailure.snapshotChanged
                    }
                    try await PropertyManagementReportSystemDelivery.handoff(url, action: .share)
                }
            } catch {
                exportError = "The report could not be shared. Data or access may have changed. Refresh and try again."
            }
        }
    }
}
