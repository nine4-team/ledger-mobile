import Foundation
import LedgerTargetCore
import LedgerTargetAppModel
import Testing

@Suite("Property Management report presentation") @MainActor
struct PropertyManagementReportModelTests {
    private let account = try! AccountID(validating: "account-report")
    private let project = try! ProjectID(validating: "project-report")
    private let currency = try! CurrencyCode(validating: "USD")

    private func snapshot(accountId: AccountID? = nil, projectId: ProjectID? = nil,
                          currency: CurrencyCode? = nil, online: Bool = false) throws -> PropertyManagementReportSnapshot {
        let account = accountId ?? self.account, project = projectId ?? self.project
        return try .build(project: .init(accountId: account, projectId: project, name: "Property", address: nil, revision: 1),
            spaces: [], items: [], currency: currency ?? self.currency,
            provenance: .init(accountId: account, projectId: project, principalId: PrincipalID(validating: "principal-report"),
                visibilityScopeID: .make(bytes: Data("physical-report-member".utf8)),
                source: online ? .authoritative : .downloaded(localDataVersion: LocalDataVersion(validating: "local-1"),
                    lastSyncedAt: .init(validating: 1_800_000_000_000)),
                authorityVersion: .init(validating: "physical-market-value-v1"), asOf: .init(validating: 1_800_000_001_000),
                readiness: .ready))
    }
    private func start(_ model: PropertyManagementReportModel, watcher: ReportWatcher, projectId: ProjectID? = nil) -> Task<Void, Never> {
        Task { await model.load(accountId: account, projectId: projectId ?? project, currency: currency, watcher: watcher) }
    }
    private func reaches(_ expected: PropertyManagementReportState, model: PropertyManagementReportModel) async {
        for _ in 0..<1_000 {
            if model.state == expected { return }
            await Task.yield()
        }
        Issue.record("Report model did not reach expected state: \(expected)")
    }

    @Test("An online result cannot masquerade as the downloaded app report")
    func onlineNotDownloaded() async throws {
        let model = PropertyManagementReportModel(), watcher = ReportWatcher()
        let task = start(model, watcher: watcher)
        await watcher.started.wait()
        watcher.send(.ready(try snapshot(online: true)))
        await reaches(.unavailable, model: model)
        watcher.finish()
        await task.value
    }

    @Test("A new checkpoint can replace ready data with incomplete data without retaining report contents")
    func readinessTransitions() async throws {
        let model = PropertyManagementReportModel(), watcher = ReportWatcher()
        let task = start(model, watcher: watcher)
        await watcher.started.wait()
        #expect(model.state == .loading)
        let report = try snapshot()
        watcher.send(.ready(report))
        await reaches(.ready(report), model: model)
        watcher.send(.incomplete)
        await reaches(.incomplete, model: model)
        watcher.send(.ready(report))
        await reaches(.ready(report), model: model)
        task.cancel()
        await task.value
        #expect(model.state == .idle)
    }

    @Test("Removal failure or a stopped watch clears an already visible report", arguments: [false, true])
    func removal(fails: Bool) async throws {
        let model = PropertyManagementReportModel(), watcher = ReportWatcher()
        let task = start(model, watcher: watcher)
        await watcher.started.wait()
        let report = try snapshot()
        watcher.send(.ready(report))
        await reaches(.ready(report), model: model)
        watcher.finish(fails: fails)
        await task.value
        #expect(model.state == .unavailable)
    }

    @Test("Foreign Account, Project or currency clears valid data", arguments: ["account", "project", "currency"])
    func foreignUpdate(kind: String) async throws {
        let model = PropertyManagementReportModel(), watcher = ReportWatcher()
        let task = start(model, watcher: watcher)
        await watcher.started.wait()
        let report = try snapshot()
        watcher.send(.ready(report))
        await reaches(.ready(report), model: model)
        watcher.send(.ready(try snapshot(accountId: kind == "account" ? AccountID(validating: "foreign") : nil,
            projectId: kind == "project" ? ProjectID(validating: "foreign") : nil,
            currency: kind == "currency" ? CurrencyCode(validating: "EUR") : nil)))
        await task.value
        watcher.finish()
        #expect(model.state == .unavailable)
    }

    @Test("A delayed previous request cannot overwrite a new Project or a cleared screen", arguments: [false, true])
    func delayedRequest(replace: Bool) async throws {
        let model = PropertyManagementReportModel(), oldWatcher = ReportWatcher()
        let oldTask = start(model, watcher: oldWatcher)
        await oldWatcher.started.wait()
        var expected: PropertyManagementReportState = .idle
        var newTask: Task<Void, Never>?
        let newWatcher = ReportWatcher()
        if replace {
            let newProject = try ProjectID(validating: "new-project")
            let report = try snapshot(projectId: newProject)
            newTask = start(model, watcher: newWatcher, projectId: newProject)
            await newWatcher.started.wait()
            newWatcher.send(.ready(report))
            expected = .ready(report)
            await reaches(expected, model: model)
        } else {
            model.clear()
        }
        oldWatcher.send(.ready(try snapshot()))
        await oldTask.value
        #expect(model.state == expected)
        oldWatcher.finish()
        newTask?.cancel()
        await newTask?.value
        newWatcher.finish()
    }

    @Test("Cancellation clears visible data and suppresses late updates")
    func cancellation() async throws {
        let model = PropertyManagementReportModel(), watcher = ReportWatcher()
        let task = start(model, watcher: watcher)
        await watcher.started.wait()
        let report = try snapshot()
        watcher.send(.ready(report))
        await reaches(.ready(report), model: model)
        task.cancel()
        await task.value
        watcher.send(.ready(report))
        #expect(model.state == .idle)
        watcher.finish()
    }

    @Test("An empty watch terminates visibly rather than leaving an endless spinner")
    func emptyStream() async {
        let model = PropertyManagementReportModel(), watcher = ReportWatcher()
        watcher.finish()
        await model.load(accountId: account, projectId: project, currency: currency, watcher: watcher)
        #expect(model.state == .unavailable)
    }
}

private struct ReportWatcher: PropertyManagementReportWatching {
    let started = ReportStartSignal()
    let stream: AsyncThrowingStream<PropertyManagementReportUpdate, Error>
    let continuation: AsyncThrowingStream<PropertyManagementReportUpdate, Error>.Continuation
    init() {
        let pair = AsyncThrowingStream<PropertyManagementReportUpdate, Error>.makeStream()
        stream = pair.stream; continuation = pair.continuation
    }
    func watchPropertyManagementReport(accountId: AccountID, projectId: ProjectID, currency: CurrencyCode) -> AsyncThrowingStream<PropertyManagementReportUpdate, Error> {
        Task { await started.signal() }
        return stream
    }
    func send(_ update: PropertyManagementReportUpdate) { continuation.yield(update) }
    func finish(fails: Bool = false) {
        if fails { continuation.finish(throwing: CancellationError()) } else { continuation.finish() }
    }
}

private actor ReportStartSignal {
    private var didStart = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func signal() {
        didStart = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
    func wait() async {
        if didStart { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}
