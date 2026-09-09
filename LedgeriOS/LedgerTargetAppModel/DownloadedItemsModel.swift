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
