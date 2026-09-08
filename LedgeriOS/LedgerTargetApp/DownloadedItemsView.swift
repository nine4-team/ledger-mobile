import LedgerTargetCore
import LedgerTargetAppModel
import SwiftUI

/// Real workspace reader; no synthetic rows and no claim that missing downloads
/// prove zero Items. Financial sections/actions await their complete query.
struct DownloadedItemsView: View {
    let accountId: AccountID
    let scope: ItemPlacementScope
    let reader: any DownloadedItemPlacementReading
    var spaceId: SpaceID? = nil
    @State private var model = DownloadedItemsModel()
    @State private var refresh = UUID()
    @State private var selectedItem: ItemSelection?

    private struct ItemSelection: Identifiable {
        let accountId: AccountID
        let itemId: ItemID
        var id: String { itemId.rawValue }
    }

    private struct Request: Equatable {
        let accountId: AccountID
        let scope: ItemPlacementScope
        let spaceBytes: [UInt8]?
        let refresh: UUID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Items").font(.headline)
            Text("Downloaded physical data only. Accounting and full inventory coverage are not yet available.")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("target-items-partial-notice")
            switch model.state {
            case .idle, .loading:
                ProgressView("Loading downloaded Items…")
            case .unavailable:
                Text("Item data is unavailable or incomplete. Reconnect and try again.")
                    .accessibilityIdentifier("target-items-unavailable")
            case .downloaded(let snapshot):
                let rows = snapshot.rows(in: spaceId)
                if snapshot.accountId == accountId, snapshot.scope == scope {
                    Text("Downloaded Items: \(rows.count)")
                        .font(.caption)
                        .accessibilityIdentifier("target-items-downloaded-count")
                }
                if snapshot.accountId != accountId || snapshot.scope != scope {
                    ProgressView("Loading downloaded Items…")
                } else if rows.isEmpty {
                    Text("No Item placements are downloaded for this location yet.")
                        .accessibilityIdentifier("target-items-downloaded-empty")
                } else {
                    ForEach(rows, id: \.itemId) { row in
                        Button(row.description.isEmpty ? "Untitled Item" : row.description) {
                            selectedItem = ItemSelection(accountId: accountId, itemId: row.itemId)
                        }
                            .buttonStyle(.plain)
                            .disabled(!(reader is any DownloadedItemPlacementHistoryReading))
                            .accessibilityHint("Show downloaded location history")
                            .accessibilityIdentifier("target-physical-item-\(row.itemId.rawValue)")
                    }
                }
            }
            Button("Refresh Items") { refresh = UUID() }
                .accessibilityIdentifier("target-items-refresh")
        }
        .task(id: Request(accountId: accountId, scope: scope,
                          spaceBytes: spaceId.map { Array($0.rawValue.utf8) }, refresh: refresh)) {
            await model.load(accountId: accountId, scope: scope, reader: reader)
        }
        .sheet(item: $selectedItem) { selection in
            if selection.accountId.rawValue.utf8.elementsEqual(accountId.rawValue.utf8),
               let historyReader = reader as? any DownloadedItemPlacementHistoryReading {
                DownloadedItemHistoryView(accountId: accountId, itemId: selection.itemId, reader: historyReader)
            }
        }
        .onChange(of: accountId) { _, _ in selectedItem = nil }
        .onChange(of: scope) { _, _ in selectedItem = nil }
        .onChange(of: spaceId.map { Array($0.rawValue.utf8) }) { _, _ in selectedItem = nil }
        .onDisappear { model.clear(); selectedItem = nil }
    }
}

private struct DownloadedItemHistoryView: View {
    let accountId: AccountID
    let itemId: ItemID
    let reader: any DownloadedItemPlacementHistoryReading
    @Environment(\.dismiss) private var dismiss
    @State private var model = DownloadedItemHistoryModel()
    @State private var refresh = UUID()
    private struct Request: Equatable {
        let accountBytes: [UInt8]
        let itemBytes: [UInt8]
        let refresh: UUID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Location history").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.accessibilityIdentifier("target-item-history-done")
            }
            Text("Downloaded locations only. Older moves may be missing. Payments, sales and refunds are not shown here.")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("target-item-history-partial")
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch model.state {
                    case .idle, .loading: ProgressView("Loading location history…")
                    case .unavailable:
                        Text("Location history is unavailable or incomplete. Reconnect and try again.")
                            .accessibilityIdentifier("target-item-history-unavailable")
                    case .downloaded(let history):
                        if history.accountId.rawValue.utf8.elementsEqual(accountId.rawValue.utf8),
                           history.itemId.rawValue.utf8.elementsEqual(itemId.rawValue.utf8) {
                            Text(history.description.isEmpty ? "Untitled Item" : history.description).font(.title3)
                            if history.intervals.isEmpty {
                                Text("No location history is downloaded for this Item yet.")
                            }
                            ForEach(history.intervals, id: \.placementId) { interval in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(location(interval)).font(.subheadline)
                                    if interval.spaceId != nil {
                                        Text(interval.spaceDisplayName ?? "Space name not downloaded")
                                    }
                                    Text("From: \(interval.startedAt)")
                                    Text(interval.endedAt.map { "Until: \($0)" } ?? "Current downloaded location")
                                }
                                .accessibilityIdentifier("target-item-history-\(interval.placementId.rawValue)")
                            }
                        } else { ProgressView("Loading location history…") }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("Refresh history") { refresh = UUID() }
                .accessibilityIdentifier("target-item-history-refresh")
        }
        .padding()
        .frame(minWidth: 280, minHeight: 300)
        .task(id: Request(accountBytes: Array(accountId.rawValue.utf8),
                          itemBytes: Array(itemId.rawValue.utf8), refresh: refresh)) {
            await model.load(accountId: accountId, itemId: itemId, reader: reader)
        }
        .onDisappear { model.clear() }
    }

    private func location(_ interval: PhysicalItemPlacementHistoryInterval) -> String {
        switch interval.scope {
        case .businessInventory: "Business Inventory"
        case .project: interval.projectDisplayName ?? "Project name not downloaded"
        }
    }
}
