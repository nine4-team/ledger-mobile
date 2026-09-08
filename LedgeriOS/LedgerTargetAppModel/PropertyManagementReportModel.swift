import Foundation
import LedgerTargetCore
import Observation

public enum PropertyManagementReportState: Equatable, Sendable {
    case idle, loading, incomplete, unavailable
    case ready(PropertyManagementReportSnapshot)
}

@MainActor @Observable
public final class PropertyManagementReportModel {
    public private(set) var state: PropertyManagementReportState = .idle
    private var generation = UUID()
    public init() {}

    public func load(accountId: AccountID, projectId: ProjectID, currency: CurrencyCode,
                     watcher: any PropertyManagementReportWatching) async {
        let request = UUID()
        generation = request
        state = .loading
        do {
            for try await update in watcher.watchPropertyManagementReport(accountId: accountId, projectId: projectId, currency: currency) {
                try Task.checkCancellation()
                guard generation == request else { return }
                switch update {
                case .incomplete:
                    state = .incomplete
                case .ready(let snapshot):
                    guard snapshot.project.accountId == accountId, snapshot.project.projectId == projectId,
                          snapshot.provenance.accountId == accountId, snapshot.provenance.projectId == projectId,
                          snapshot.currency == currency, snapshot.provenance.localDataVersion != nil else {
                        state = .unavailable
                        return
                    }
                    state = .ready(snapshot)
                }
            }
            guard generation == request else { return }
            // A stopped live watch no longer vouches for visible report data.
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
