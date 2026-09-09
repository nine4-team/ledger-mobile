import Foundation
import LedgerTargetCore
import LedgerTargetAppModel
import SwiftUI

/// A linked Space owns a separate read/toggle session, not the browser's selection.
struct ReferencedSpaceDetailView: View {
    let accountId: AccountID
    let spaceId: SpaceID
    let scope: SpaceCreationScope
    let reader: any DownloadedItemPlacementReading
    let navigation: ItemSpaceNavigation
    @Environment(\.dismiss) private var dismiss
    @State private var details: SpaceCoreDetailsStagingExercise
    @State private var toggle: SpaceChecklistItemToggleStagingExercise
    @State private var expanded = true
    @State private var refresh = UUID()
    @State private var session: UUID?
    @State private var synchronizationTask: Task<Void, Never>?
    @State private var synchronizationOwner: UUID?

    init(accountId: AccountID, spaceId: SpaceID, scope: SpaceCreationScope,
         reader: any DownloadedItemPlacementReading, navigation: ItemSpaceNavigation) {
        self.accountId = accountId
        self.spaceId = spaceId
        self.scope = scope
        self.reader = reader
        self.navigation = navigation
        _details = State(initialValue: SpaceCoreDetailsStagingExercise(accountId: accountId))
        _toggle = State(initialValue: navigation.makeToggle())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Back to Item") { dismiss() }
                    .accessibilityIdentifier("target-item-space-back")
                Spacer()
                Button("Refresh Space") { refresh = UUID() }
                    .accessibilityIdentifier("target-referenced-space-refresh")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(details.status).font(.caption)
                        .accessibilityIdentifier("target-item-space-status")
                    if let row = details.row, row.accountId == accountId,
                       row.id == spaceId, row.scope == scope {
                        Text(row.displayName.rawValue).font(.headline)
                            .accessibilityIdentifier("target-item-space-name")
                        Text(row.lifecycle == .archived ? "Archived Space" : "Active Space")
                            .accessibilityIdentifier(row.lifecycle == .archived ? "target-item-space-archived" : "target-item-space-active")
                        Text(row.notes.value ?? "No notes")
                            .accessibilityIdentifier("target-referenced-space-notes")
                        SpaceChecklistSection(toggle: toggle, expanded: $expanded) { checklistId, itemId in
                            guard let activeSession = session, synchronizationOwner == activeSession,
                                  details.row?.lifecycle == .active else { return }
                            scheduleSynchronization()
                            await synchronizationTask?.value
                            guard session == activeSession, !Task.isCancelled, details.row?.lifecycle == .active else { return }
                            await toggle.toggle(checklistId: checklistId, itemId: itemId)
                        }
                        .disabled(synchronizationOwner == nil)
                        DownloadedItemsView(accountId: accountId, scope: placementScope,
                            reader: reader, spaceId: spaceId, spaceNavigation: navigation)
                    } else {
                        Text(details.isAuthoritativelyEmpty ? "Space unavailable" : "Space details are loading or unavailable.")
                            .accessibilityIdentifier("target-item-space-unavailable")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .itemThumbnailViewport()
            .accessibilityIdentifier("target-referenced-space-scroll")
        }
        .padding()
        .frame(minWidth: 280, minHeight: 300)
        .task(id: refresh) {
            let activeSession = UUID()
            session = activeSession
            synchronizationOwner = nil
            let previousSynchronization = synchronizationTask
            synchronizationTask = nil
            previousSynchronization?.cancel()
            await previousSynchronization?.value
            guard session == activeSession else { return }
            await toggle.start(runtime: navigation.toggleRuntime)
            guard session == activeSession else { return }
            if !Task.isCancelled {
                await details.select(spaceId: spaceId, runtime: navigation.detailRuntime, expectedScope: scope)
            }
            guard session == activeSession else { return }
            if !Task.isCancelled {
                synchronizationOwner = activeSession
                scheduleSynchronization()
            }
            // Own the session until SwiftUI cancels this presentation task.
            // Cancellation ends the stream wait and drains both observers.
            if !Task.isCancelled {
                let lifetime = AsyncStream<Void>.makeStream()
                for await _ in lifetime.stream {}
                lifetime.continuation.finish()
            }
            guard session == activeSession else { return }
            session = nil
            synchronizationOwner = nil
            let pendingSynchronization = synchronizationTask
            synchronizationTask = nil
            pendingSynchronization?.cancel()
            await pendingSynchronization?.value
            guard session == nil else { return }
            await details.stop()
            guard session == nil else { return }
            await toggle.stop()
        }
        .onChange(of: details.evidenceSequence) { _, _ in
            scheduleSynchronization()
        }
    }

    private func scheduleSynchronization() {
        guard let owner = synchronizationOwner, session == owner else { return }
        let previous = synchronizationTask
        previous?.cancel()
        synchronizationTask = Task {
            await previous?.value
            guard !Task.isCancelled, session == owner else { return }
            await toggle.receiveDetailUpdate(details.currentUpdate,
                selectedSpaceId: details.currentUpdate == nil ? nil : spaceId)
        }
    }

    private var placementScope: ItemPlacementScope {
        switch scope {
        case .businessInventory: .businessInventory
        case .project(let projectId): .project(projectId)
        }
    }
}
