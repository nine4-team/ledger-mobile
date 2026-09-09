import Foundation
import LedgerTargetCore
import LedgerTargetAppModel
import Testing

@Suite("Client Summary presentation") @MainActor
struct ClientSummaryPhysicalReportModelTests {
    private let account = try! AccountID(validating: "account")
    private let project = try! ProjectID(validating: "project")

    private func snapshot(project: ProjectID? = nil) throws -> ClientSummaryPhysicalReportSnapshot {
        let project = project ?? self.project
        return try .build(project: .init(accountId: account, projectId: project, name: "Project", address: nil, revision: 1),
            client: .known(clientId: ClientID(validating: "client"), name: "Client", revision: 1),
            spaces: [], items: [], provenance: .init(accountId: account, projectId: project,
                principalId: PrincipalID(validating: "principal"), visibilityScopeID: .make(bytes: Data("scope".utf8)),
                localDataVersion: .init(validating: "version"), authorityVersion: .init(validating: "physical-v1"),
                asOf: .init(validating: 1000), readiness: .ready, lastSyncedAt: .init(validating: 1000)))
    }

    private func reaches(_ expected: ClientSummaryPhysicalReportState, model: ClientSummaryPhysicalReportModel) async {
        for _ in 0..<1000 {
            if model.state == expected { return }
            await Task.yield()
        }
        Issue.record("Client Summary did not reach expected state")
    }

    @Test func readinessAndStoppedWatchClearContents() async throws {
        let model = ClientSummaryPhysicalReportModel(), watcher = ClientReportWatcher()
        let task = Task { await model.load(accountId: account, projectId: project, watcher: watcher) }
        await reaches(.loading, model: model)
        let report = try snapshot()
        watcher.continuation.yield(.ready(report))
        await reaches(.ready(report), model: model)
        watcher.continuation.yield(.incomplete)
        await reaches(.incomplete, model: model)
        watcher.continuation.finish()
        await task.value
        #expect(model.state == .unavailable)
    }

    @Test func foreignSnapshotCannotDisplay() async throws {
        let model = ClientSummaryPhysicalReportModel(), watcher = ClientReportWatcher()
        watcher.continuation.yield(.ready(try snapshot(project: ProjectID(validating: "foreign"))))
        await model.load(accountId: account, projectId: project, watcher: watcher)
        #expect(model.state == .unavailable)
        watcher.continuation.finish()
    }

    @Test func disappearanceSuppressesLateResult() async throws {
        let model = ClientSummaryPhysicalReportModel(), watcher = ClientReportWatcher()
        let task = Task { await model.load(accountId: account, projectId: project, watcher: watcher) }
        await reaches(.loading, model: model)
        model.clear()
        watcher.continuation.yield(.ready(try snapshot()))
        await task.value
        #expect(model.state == .idle)
        watcher.continuation.finish()
    }

    @Test func cancellationClearsVisibleResult() async throws {
        let model = ClientSummaryPhysicalReportModel(), watcher = ClientReportWatcher()
        let task = Task { await model.load(accountId: account, projectId: project, watcher: watcher) }
        let report = try snapshot()
        watcher.continuation.yield(.ready(report))
        await reaches(.ready(report), model: model)
        task.cancel()
        await task.value
        #expect(model.state == .idle)
        watcher.continuation.finish()
    }
}

private struct ClientReportWatcher: ClientSummaryPhysicalReportWatching {
    let pair = AsyncThrowingStream<ClientSummaryPhysicalReportUpdate, Error>.makeStream()
    var continuation: AsyncThrowingStream<ClientSummaryPhysicalReportUpdate, Error>.Continuation { pair.continuation }
    func watchClientSummaryPhysicalReport(accountId: AccountID, projectId: ProjectID)
        -> AsyncThrowingStream<ClientSummaryPhysicalReportUpdate, Error> { pair.stream }
}
