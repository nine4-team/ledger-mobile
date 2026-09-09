import LedgerTargetCore
import LedgerTargetAppModel
import SwiftUI

/// Real workspace reader; missing downloads never prove zero or Unaccounted.
struct DownloadedItemsView: View {
    let accountId: AccountID
    let scope: ItemPlacementScope
    let reader: any DownloadedItemPlacementReading
    var spaceId: SpaceID? = nil
    @State private var model = DownloadedItemsModel()
    @State private var refresh = UUID()
    @State private var selectedItem: ItemSelection?
    @State private var search = ""
    @State private var order = DownloadedItemOrder.newest
    @State private var filters = DownloadedItemFilters()
    @State private var selection = DownloadedItemSelection()
    @State private var collapsedSections: Set<ProjectItemAccountingResolution> = []
    @FocusState private var searchFocused: Bool

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
            Text(partialNotice)
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("target-items-partial-notice")
            TextField("Search downloaded names, descriptions or SKU", text: $search)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
                .accessibilityIdentifier("target-items-search")
            Picker("Sort Items", selection: $order) {
                ForEach(DownloadedItemOrder.allCases, id: \.self) { value in
                    Text(value.rawValue).tag(value)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("target-items-sort")
            Menu("Filter Items") {
                facetMenu("Name", selection: $filters.name)
                facetMenu("SKU", selection: $filters.sku)
                if spaceId == nil, case .downloaded(let snapshot) = model.state,
                   snapshot.accountId == accountId, snapshot.scope == scope {
                    spaceFacetMenu(snapshot.spaceChoices)
                }
            }
            .accessibilityIdentifier("target-items-filters")
            if filters.isActive {
                Button("Clear filters") { filters = .init() }
                    .accessibilityIdentifier("target-items-filters-clear")
            }
            if !search.isEmpty {
                Button("Clear search") { search = ""; searchFocused = false }
                    .accessibilityIdentifier("target-items-search-clear")
            }
            switch model.state {
            case .idle, .loading:
                ProgressView("Loading downloaded Items…")
            case .unavailable:
                Text("Item data is unavailable or incomplete. Reconnect and try again.")
                    .accessibilityIdentifier("target-items-unavailable")
            case .downloaded(let snapshot):
                let rows = snapshot.rows(in: spaceId, matching: search, order: order, filters: filters)
                if snapshot.accountId == accountId, snapshot.scope == scope {
                    Text(search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !filters.isActive
                        ? "Downloaded Items: \(rows.count)"
                        : "Matching Items: \(rows.count) of \(snapshot.rows(in: spaceId).count) downloaded")
                        .font(.caption)
                        .accessibilityIdentifier("target-items-downloaded-count")
                    selectionControls(rows.map(\.itemId))
                }
                if snapshot.accountId != accountId || snapshot.scope != scope {
                    ProgressView("Loading downloaded Items…")
                } else if rows.isEmpty {
                    if !snapshot.rows(in: spaceId).isEmpty {
                        Text("No downloaded Items match this search or these filters.")
                            .accessibilityIdentifier("target-items-no-match")
                    } else {
                        Text("No Item placements are downloaded for this location yet.")
                            .accessibilityIdentifier("target-items-downloaded-empty")
                    }
                } else {
                    if case .project = scope {
                        accountingGroup("Unaccounted For Items", resolution: .unaccountedFor, rows: rows)
                        accountingGroup("Accounted For Items", resolution: .accountedFor, rows: rows)
                        accountingGroup("Accounting status unknown", resolution: .relationshipEvidenceIncomplete, rows: rows)
                    } else {
                        ForEach(rows, id: \.itemId) { row in itemButton(row) }
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
        .onChange(of: accountId) { _, _ in resetContext() }
        .onChange(of: scope) { _, _ in resetContext() }
        .onChange(of: spaceId.map { Array($0.rawValue.utf8) }) { _, _ in resetContext() }
        .onChange(of: visibleItemIds, initial: true) { _, ids in selection.reconcile(visible: ids) }
        .onDisappear { model.clear(); selectedItem = nil; selection.clear() }
    }

    private var visibleItemIds: [ItemID] {
        guard case .downloaded(let snapshot) = model.state,
              snapshot.accountId == accountId, snapshot.scope == scope else { return [] }
        return snapshot.rows(in: spaceId, matching: search, order: order, filters: filters).map(\.itemId)
    }

    private func selectionControls(_ ids: [ItemID]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(selection.isAllSelected(visible: ids) ? "Deselect all visible" : "Select all visible") {
                selection.toggleAll(visible: visibleItemIds)
            }
            .disabled(ids.isEmpty)
            .accessibilityIdentifier("target-items-select-all")
            Text("\(selection.ids.intersection(ids).count) selected")
                .accessibilityIdentifier("target-items-selected-count")
            if !selection.ids.intersection(ids).isEmpty {
                Button("Clear selection") { selection.clear() }
                    .accessibilityIdentifier("target-items-selection-clear")
                Text("Selected price totals and bulk edits are not available yet.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var partialNotice: String {
        if case .project = scope {
            "Downloaded Items only. Missing or restricted accounting evidence is shown as unknown, not Unaccounted For. Linking and editing are not available yet."
        } else {
            "Downloaded physical data only. Accounting and full inventory coverage are not yet available."
        }
    }

    private func facetMenu(_ title: String, selection: Binding<DownloadedItemFacetSelection>) -> some View {
        Menu(title) {
            Button("All") { selection.wrappedValue = .all }
            Button("None") { selection.wrappedValue = .only([]) }
            Divider()
            ForEach(["has", "missing"], id: \.self) { value in
                facetToggle(value, label: value == "has" ? "Has \(title)" : "No \(title)", selection: selection)
            }
        }
    }

    private func spaceFacetMenu(_ choices: [DownloadedItemSpace]) -> some View {
        Menu("Space") {
            Button("All") { filters.space = .all }
            Button("None") { filters.space = .only([]) }
            Divider()
            facetToggle("", label: "No Space", selection: $filters.space)
            ForEach(choices, id: \.id) { space in
                let name = space.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? "Space name not downloaded"
                let ambiguous = space.displayName?.isEmpty != false || choices.filter { $0.displayName == space.displayName }.count > 1
                let label = name + (ambiguous ? " (\(space.id.rawValue))" : "") + (space.isArchived ? " — archived" : "")
                facetToggle(space.id.rawValue, label: label, selection: $filters.space)
                    .accessibilityIdentifier("target-items-space-choice-\(space.id.rawValue)")
            }
            Text("Downloaded Spaces only")
        }
        .accessibilityIdentifier("target-items-space-filter")
    }

    private func facetToggle(_ value: String, label: String,
                             selection: Binding<DownloadedItemFacetSelection>) -> some View {
        Toggle(label, isOn: Binding(
            get: { selection.wrappedValue.includes(value) },
            set: { desired in
                if desired != selection.wrappedValue.includes(value) { selection.wrappedValue.toggle(value) }
            }
        ))
    }

    @ViewBuilder
    private func accountingGroup(_ title: String, resolution: ProjectItemAccountingResolution,
                                 rows: [PhysicalItemPlacement]) -> some View {
        let resolutions = Dictionary(uniqueKeysWithValues:
            (model.accounting?.rows ?? []).map { ($0.evidence.itemId, $0.resolution) })
        let matching = rows.filter { (resolutions[$0.itemId] ?? .relationshipEvidenceIncomplete) == resolution }
        if !matching.isEmpty {
            // Native DisclosureGroup loses its content inside the macOS List
            // cell that embeds this view. Keep the expansion control and rows
            // explicit so both platforms expose the same real controls.
            Button {
                if !collapsedSections.insert(resolution).inserted { collapsedSections.remove(resolution) }
            } label: {
                HStack {
                    Image(systemName: collapsedSections.contains(resolution) ? "chevron.right" : "chevron.down")
                    Text("\(title) (\(matching.count))").font(.subheadline).bold()
                }
            }
            .buttonStyle(.plain)
            .accessibilityValue(collapsedSections.contains(resolution) ? "Collapsed" : "Expanded")
            .accessibilityIdentifier("target-items-group-\(resolution.rawValue)")
            if !collapsedSections.contains(resolution) {
                ForEach(matching, id: \.itemId) { row in itemButton(row) }
            }
        }
    }

    private func itemButton(_ row: PhysicalItemPlacement) -> some View {
        HStack {
            Button {
                selection.toggle(itemId: row.itemId, visible: visibleItemIds)
            } label: {
                Image(systemName: selection.ids.contains(row.itemId) ? "checkmark.circle.fill" : "circle")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Select \(row.displayName.isEmpty ? "Untitled Item" : row.displayName)")
            .accessibilityValue(selection.ids.contains(row.itemId) ? "Selected" : "Not selected")
            .accessibilityIdentifier("target-item-select-\(row.itemId.rawValue)")
            Button(row.displayName.isEmpty ? "Untitled Item" : row.displayName) {
                selection.reconcile(visible: visibleItemIds)
                guard visibleItemIds.contains(row.itemId) else { return }
                if selection.ids.isEmpty {
                    selectedItem = ItemSelection(accountId: accountId, itemId: row.itemId)
                } else {
                    selection.toggle(itemId: row.itemId, visible: visibleItemIds)
                }
            }
            .buttonStyle(.plain)
            .disabled(selection.ids.isEmpty && !(reader is any DownloadedItemPlacementHistoryReading))
            .accessibilityHint(selection.ids.isEmpty ? "Show downloaded location history" : "Toggle selection")
            .accessibilityIdentifier("target-physical-item-\(row.itemId.rawValue)")
        }
    }

    private func resetContext() {
        selectedItem = nil
        search = ""
        order = .newest
        filters = .init()
        selection.clear()
        collapsedSections = []
        searchFocused = false
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
