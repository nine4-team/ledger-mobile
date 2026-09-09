import Foundation
import LedgerTargetCore
import Observation

public enum DownloadedItemsState: Equatable, Sendable {
    case idle, loading, unavailable
    case downloaded(DownloadedItemPlacements)
}

@MainActor @Observable
public final class DownloadedItemsModel {
    public private(set) var state: DownloadedItemsState = .idle
    public private(set) var accounting: ProjectItemAccountingSectionsSnapshot?
    private var generation = UUID()
    public init() {}

    /// Nil is temporary absence of evidence, not an authoritative empty list.
    /// Selection must survive loading/covering; actual filtered empty results
    /// still prune it once a matching snapshot arrives.
    public func selectionEvidence(accountId: AccountID, scope: ItemPlacementScope,
                                  spaceId: SpaceID? = nil, search: String = "",
                                  order: DownloadedItemOrder = .newest,
                                  filters: DownloadedItemFilters = .init()) -> [ItemID]? {
        guard case .downloaded(let snapshot) = state,
              snapshot.accountId == accountId, snapshot.scope == scope else { return nil }
        return snapshot.rows(in: spaceId,matching: search,order: order,filters: filters).map(\.itemId)
    }

    public func load(accountId: AccountID, scope: ItemPlacementScope, reader: any DownloadedItemPlacementReading) async {
        let request = UUID()
        generation = request
        accounting = nil
        state = .loading
        do {
            if case .project(let projectId) = scope,
               let projectReader = reader as? any DownloadedProjectItemsReading {
                for try await snapshot in projectReader.watchDownloadedProjectItems(accountId: accountId, projectId: projectId) {
                    try Task.checkCancellation()
                    guard generation == request else { return }
                    guard snapshot.placements.accountId == accountId, snapshot.placements.scope == scope else {
                        accounting = nil
                        state = .unavailable
                        return
                    }
                    // Both values come from one local read transaction. Never
                    // join separately watched physical and accounting revisions.
                    accounting = snapshot.accounting
                    state = .downloaded(snapshot.placements)
                }
                guard generation == request else { return }
                if Task.isCancelled { accounting = nil; state = .idle }
                else if state == .loading { state = .unavailable }
                return
            }
            for try await snapshot in reader.watchDownloadedItemPlacements(accountId: accountId, scope: scope) {
                try Task.checkCancellation()
                guard generation == request else { return }
                guard snapshot.accountId == accountId, snapshot.scope == scope else {
                    state = .unavailable
                    return
                }
                state = .downloaded(snapshot)
            }
            guard generation == request else { return }
            if Task.isCancelled { state = .idle }
            else if state == .loading { state = .unavailable }
        } catch {
            guard generation == request else { return }
            accounting = nil
            state = Task.isCancelled ? .idle : .unavailable
        }
    }

    public func clear() {
        generation = UUID()
        accounting = nil
        state = .idle
    }
}
