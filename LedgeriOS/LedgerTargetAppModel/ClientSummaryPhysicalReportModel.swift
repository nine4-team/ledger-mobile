import Foundation
import LedgerTargetCore
import Observation

public enum ClientSummaryPhysicalReportState: Equatable, Sendable {
    case idle, loading, incomplete, unavailable
    case ready(ClientSummaryPhysicalReportSnapshot)
}

@MainActor @Observable
public final class ClientSummaryPhysicalReportModel {
    public private(set) var state: ClientSummaryPhysicalReportState = .idle
    private var generation = UUID()
    public init() {}

    public func load(accountId: AccountID, projectId: ProjectID,
        watcher: any ClientSummaryPhysicalReportWatching) async {
        let request = UUID()
        generation = request
        state = .loading
        do {
            for try await update in watcher.watchClientSummaryPhysicalReport(accountId: accountId, projectId: projectId) {
                try Task.checkCancellation()
                guard generation == request else { return }
                switch update {
                case .incomplete: state = .incomplete
                case .ready(let snapshot):
                    guard snapshot.project.accountId == accountId, snapshot.project.projectId == projectId,
                          snapshot.provenance.accountId == accountId, snapshot.provenance.projectId == projectId,
                          snapshot.provenance.localDataVersion != nil else {
                        state = .unavailable
                        return
                    }
                    state = .ready(snapshot)
                }
            }
            guard generation == request else { return }
            state = Task.isCancelled ? .idle : .unavailable
        } catch {
            guard generation == request else { return }
            state = Task.isCancelled ? .idle : .unavailable
        }
    }

    public func clear() {
        generation = UUID()
        state = .idle
    }
}
