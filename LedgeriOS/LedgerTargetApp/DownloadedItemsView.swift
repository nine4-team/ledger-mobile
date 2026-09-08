import LedgerTargetCore
import LedgerTargetAppModel
import SwiftUI

/// Real workspace reader; no synthetic rows and no claim that missing downloads
/// prove zero Items. Financial sections/actions await their complete query.
struct DownloadedItemsView: View {
    let accountId: AccountID
    let scope: ItemPlacementScope
    let reader: any DownloadedItemPlacementReading
    @State private var model = DownloadedItemsModel()
    @State private var refresh = UUID()

    private struct Request: Equatable {
        let accountId: AccountID
        let scope: ItemPlacementScope
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
                if snapshot.accountId != accountId || snapshot.scope != scope {
                    ProgressView("Loading downloaded Items…")
                } else if snapshot.rows.isEmpty {
                    Text("No Item placements are downloaded for this location yet.")
                        .accessibilityIdentifier("target-items-downloaded-empty")
                } else {
                    ForEach(snapshot.rows, id: \.itemId) { row in
                        Text(row.description.isEmpty ? "Untitled Item" : row.description)
                            .accessibilityIdentifier("target-physical-item-\(row.itemId.rawValue)")
                    }
                }
            }
            Button("Refresh Items") { refresh = UUID() }
                .accessibilityIdentifier("target-items-refresh")
        }
        .task(id: Request(accountId: accountId, scope: scope, refresh: refresh)) {
            await model.load(accountId: accountId, scope: scope, reader: reader)
        }
        .onDisappear { model.clear() }
    }
}
