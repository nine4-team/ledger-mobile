import Foundation
import LedgerTargetCore
import Testing
@testable import LedgerTargetAppModel

@Suite("Client Browsing Staging Application Flow")
@MainActor
struct ClientBrowsingStagingExerciseTests {
    @Test("Directory evidence is atomic and unknown before or after represented truth")
    func atomicDirectoryAndHonestCounts() async throws {
        let directory = ClientControlledStream<ClientListSnapshot>()
        let model = Self.model()
        await model.start(runtime: Self.runtime(directory: directory))
        #expect(model.activeClientCountLabel == "unknown")
        #expect(model.archivedClientCountLabel == "unknown")
        #expect(model.directoryStatus == "loading • completeness unknown")

        let rows = try [
            Self.client("archived-z", name: "Same", lifecycle: .archived),
            Self.client("active-b", name: "Same"),
            Self.client("active-a", name: "Same"),
            Self.client("archived-a", lifecycle: .archived)
        ]
        directory.yield(try Self.directory(rows, visibleCount: 6))
        await Self.waitUntil { model.directoryPresentation != nil }
        #expect(model.activeClients.map(\.clientId) == [rows[1].id, rows[2].id])
        #expect(model.archivedClients.map(\.clientId) == [rows[0].id, rows[3].id])
        #expect(model.activeClientCountLabel == "2")
        #expect(model.archivedClientCountLabel == "2")
        #expect(model.directoryStatus == "ready • complete • source nonexhaustive")

        directory.finish(throwing: ClientSourceFailure.upstream)
        await Self.waitUntil { model.directoryDiagnostic == "client_directory_local_failed" }
        #expect(model.activeClientCountLabel == "unknown")
        #expect(model.archivedClientCountLabel == "unknown")
        #expect(model.activeClients.isEmpty)
        await model.stop()
    }

    @Test(arguments: ClientDirectoryTerminationCase.allCases)
    func directoryTerminationFailsClosed(_ terminal: ClientDirectoryTerminationCase) async throws {
        let directory = ClientControlledStream<ClientListSnapshot>()
        if terminal.isBeforeFirstValue { terminal.finish(directory) }
        let model = Self.model()
        await model.start(runtime: Self.runtime(directory: directory))
        if !terminal.isBeforeFirstValue {
            directory.yield(try Self.directory([Self.client("client-a")]))
            await Self.waitUntil { model.activeClients.count == 1 }
            terminal.finish(directory)
        }
        await Self.waitUntil { model.directoryDiagnostic == terminal.diagnostic }
        #expect(model.directoryPresentation == nil)
        #expect(model.directoryStatus == "blocked • completeness unknown")
        #expect(model.activeClientCountLabel == "unknown")
        await Self.waitUntil { directory.terminationCount == 1 }
        await model.stop()
        #expect(directory.terminationCount == 1)
    }

    @Test("Current evidence binds selection and refresh during drainage refuses dispatch")
    func currentSelectionAndRefreshRefusal() async throws {
        let directory = ClientControlledStream<ClientListSnapshot>()
        let delayedA = ClientDelayedCancellationDetailSource()
        let detailB = ClientControlledStream<ClientCoreDetailsUpdate>()
        let requests = ClientDetailRequestRecorder()
        let clientA = try Self.client("client-a", name: "A")
        let clientB = try Self.client("client-b", name: "B")
        let runtime = ClientBrowsingStagingRuntime(
            watchClients: { directory.stream },
            watchClient: { request in
                requests.record(request)
                return request.clientId == clientA.id ? delayedA.stream : detailB.stream
            }
        )
        let model = Self.model()
        await model.start(runtime: runtime)

        await model.select(clientId: clientA.id, segment: .active)
        #expect(model.detailDiagnostic == "client_detail_selection_invalid")
        #expect(requests.requests.isEmpty)

        let archived = try Self.client("client-c", name: "B", lifecycle: .archived)
        directory.yield(try Self.directory([clientA, clientB, archived]))
        await Self.waitUntil { model.activeClients.count == 2 }
        await model.select(clientId: archived.id, segment: .active)
        #expect(requests.requests.isEmpty)
        #expect(model.detailDiagnostic == "client_detail_selection_invalid")

        await model.select(clientId: clientA.id, segment: .active)
        await Self.waitUntil { requests.requests.count == 1 }
        #expect(requests.requests[0].accountId == Self.accountId)
        #expect(requests.requests[0].clientId == clientA.id)
        #expect(await Self.waitUntilAsync { await delayedA.isWaiting })

        let selectB = Task { @MainActor in
            await model.select(clientId: clientB.id, segment: .active)
        }
        let renamedB = try Self.client("client-b", name: "B Updated", updatedAt: Self.t2)
        directory.yield(try Self.directory(
            [clientA, renamedB, archived],
            version: "selection-refresh"
        ))
        await Self.waitUntil { model.activeClients.last?.displayName.rawValue == "B Updated" }
        await delayedA.releaseCancellation()
        await selectB.value
        #expect(requests.requests.count == 1)
        #expect(model.detailDiagnostic == "client_detail_selection_invalid")
        #expect(model.selectedClient == nil)

        await model.select(clientId: clientB.id, segment: .active)
        await Self.waitUntil { requests.requests.count == 2 }
        #expect(model.selectedClientName == "B Updated")
        await model.stop()
    }

    @Test("Every detail state and newer identity audit and revision evidence is reactive")
    func completeDetailStateMatrix() async throws {
        let directory = ClientControlledStream<ClientListSnapshot>()
        let detail = ClientControlledStream<ClientCoreDetailsUpdate>()
        let details = ClientDetailWatchProbe(defaultSource: detail)
        let model = Self.model()
        await model.start(runtime: Self.runtime(directory: directory, details: details))
        let client = try Self.client("client-a", name: "Original")
        directory.yield(try Self.directory([client]))
        await Self.waitUntil { model.activeClients.count == 1 }
        await model.select(clientId: client.id, segment: .active)
        await Self.waitUntil { details.requests.count == 1 }
        let request = try #require(details.requests.first)

        let newer = try Self.client(
            "client-a",
            name: "  Newer  ",
            lifecycle: .archived,
            updatedAt: Self.t2
        )
        detail.yield(try Self.snapshotUpdate(
            request,
            client: newer,
            revision: 22,
            version: "newer"
        ))
        await Self.waitUntil { model.selectedClientName == "  Newer  " }
        let newerContent = try #require(model.detailPresentation?.state.content)
        #expect(newerContent.lifecycle == .archived)
        #expect(newerContent.updatedAt == Self.t2)
        #expect(newerContent.locallyObservedRevision == ExpectedClientRevision(22))
        #expect(newerContent.observedRevisionIsFromCompleteReadySnapshot)

        let cachedReady = try Self.detailLocal(
            request,
            rows: [Self.detailRow(newer, revision: 22)],
            version: "cached-ready"
        )
        let cachedPartial = try Self.detailLocal(
            request,
            rows: [Self.detailRow(newer, revision: 21)],
            complete: false,
            quality: .partial,
            version: "cached-partial"
        )
        let updates = try [
            Self.update(request, .waiting(.notRequested)),
            Self.update(request, .waiting(.loading)),
            Self.update(request, .waiting(.blocked)),
            Self.snapshotUpdate(request, client: client, revision: 1, version: "found-ready"),
            Self.snapshotUpdate(request, client: client, revision: 2, complete: false, quality: .partial, version: "found-partial"),
            Self.snapshotUpdate(request, client: client, revision: 3, complete: false, quality: .stale, version: "found-stale"),
            Self.emptyUpdate(request, complete: false, quality: .ready, version: "incomplete-ready"),
            Self.emptyUpdate(request, complete: false, quality: .partial, version: "incomplete-partial"),
            Self.emptyUpdate(request, complete: false, quality: .stale, version: "incomplete-stale"),
            Self.emptyUpdate(request, complete: true, quality: .ready, version: "absent"),
            Self.update(request, .failed(failure: .unavailable, cached: nil)),
            Self.update(request, .failed(failure: .retryable, cached: cachedReady)),
            Self.update(request, .failed(failure: .retryable, cached: nil)),
            Self.update(request, .failed(failure: .requiredUpdate, cached: cachedPartial)),
            Self.update(request, .failed(failure: .requiredUpdate, cached: nil))
        ]
        let labels = [
            "waiting", "waiting", "waiting", "found", "found", "found",
            "incomplete", "incomplete", "incomplete", "authoritative absence",
            "unavailable", "retryable • cached", "retryable • uncached",
            "required update • cached", "required update • uncached"
        ]
        let readiness = [
            "notRequested", "loading", "blocked", "ready", "partial", "stale",
            "ready", "partial", "stale", "ready", "blocked", "stale", "blocked",
            "stale", "blocked"
        ]
        for index in updates.indices {
            let expected = try ClientDetailPresentationProjector.project(
                updates[index], validating: request
            )
            detail.yield(updates[index])
            await Self.waitUntil { model.detailPresentation == expected }
            #expect(model.detailStateLabel == labels[index])
            #expect(model.detailReadiness == readiness[index])
        }
        await model.stop()
    }

    @Test(arguments: ClientDetailTerminationCase.allCases)
    func detailTerminationFailsClosed(_ terminal: ClientDetailTerminationCase) async throws {
        let directory = ClientControlledStream<ClientListSnapshot>()
        let detail = ClientControlledStream<ClientCoreDetailsUpdate>()
        if terminal.isBeforeFirstValue { terminal.finish(detail) }
        let details = ClientDetailWatchProbe(defaultSource: detail)
        let model = Self.model()
        await model.start(runtime: Self.runtime(directory: directory, details: details))
        let client = try Self.client("client-a")
        directory.yield(try Self.directory([client]))
        await Self.waitUntil { model.activeClients.count == 1 }
        await model.select(clientId: client.id, segment: .active)
        await Self.waitUntil { details.requests.count == 1 }
        if !terminal.isBeforeFirstValue {
            detail.yield(try Self.update(details.requests[0], .waiting(.loading)))
            await Self.waitUntil { model.detailStateLabel == "waiting" }
            terminal.finish(detail)
        }
        await Self.waitUntil { model.detailDiagnostic == terminal.diagnostic }
        #expect(model.detailPresentation == nil)
        #expect(model.detailStateLabel == "blocked")
        #expect(model.selectedClientId == client.id)
        await Self.waitUntil { detail.terminationCount == 1 }
        await model.stop()
        #expect(detail.terminationCount == 1)
    }

    @Test("Cross-Account directory and mismatched detail evidence fail closed exactly once")
    func invalidEvidenceFailsClosed() async throws {
        let directory = ClientControlledStream<ClientListSnapshot>()
        let detail = ClientControlledStream<ClientCoreDetailsUpdate>()
        let details = ClientDetailWatchProbe(defaultSource: detail)
        let model = Self.model()
        await model.start(runtime: Self.runtime(directory: directory, details: details))

        let otherAccount = try AccountID(validating: "other-account")
        directory.yield(try Self.directory(
            [Self.client("other", account: otherAccount)],
            account: otherAccount,
            version: "cross-account"
        ))
        await Self.waitUntil { model.directoryDiagnostic == "client_directory_evidence_invalid" }
        await Self.waitUntil { directory.terminationCount == 1 }
        #expect(model.directoryPresentation == nil)
        #expect(directory.terminationCount == 1)
        await model.stop()

        let validDirectory = ClientControlledStream<ClientListSnapshot>()
        await model.start(runtime: Self.runtime(directory: validDirectory, details: details))
        let client = try Self.client("client-a")
        validDirectory.yield(try Self.directory([client], version: "valid"))
        await Self.waitUntil { model.activeClients.count == 1 }
        await model.select(clientId: client.id, segment: .active)
        await Self.waitUntil { details.requests.count == 1 }
        let wrong = try ClientCoreDetailsRequest(
            accountId: Self.accountId,
            clientId: ClientID(validating: "client-other")
        )
        detail.yield(try Self.update(wrong, .waiting(.loading)))
        await Self.waitUntil { model.detailDiagnostic == "client_detail_evidence_invalid" }
        await Self.waitUntil { detail.terminationCount == 1 }
        #expect(model.detailPresentation == nil)
        #expect(detail.terminationCount == 1)
        await model.stop()
    }

    @Test("Directory termination drains an active detail before stop returns")
    func directoryTerminationDrainsDetail() async throws {
        let directory = ClientControlledStream<ClientListSnapshot>()
        let delayed = ClientDelayedCancellationDetailSource()
        let requests = ClientDetailRequestRecorder()
        let model = Self.model()
        await model.start(runtime: ClientBrowsingStagingRuntime(
            watchClients: { directory.stream },
            watchClient: { request in requests.record(request); return delayed.stream }
        ))
        let client = try Self.client("client-a")
        directory.yield(try Self.directory([client]))
        await Self.waitUntil { model.activeClients.count == 1 }
        await model.select(clientId: client.id, segment: .active)
        await Self.waitUntil { requests.requests.count == 1 }
        #expect(await Self.waitUntilAsync { await delayed.isWaiting })

        directory.finish()
        await Self.waitUntil { model.directoryDiagnostic == "client_directory_source_completed" }
        #expect(model.selectedClient == nil)
        let completion = ClientCompletionProbe()
        let stop = Task { @MainActor in
            completion.markStarted()
            await model.stop()
            completion.markFinished()
        }
        await Self.waitUntil { completion.didStart }
        for _ in 0..<20 { await Task.yield() }
        #expect(!completion.didFinish)
        await delayed.releaseCancellation()
        await stop.value
        #expect(completion.didFinish)
        #expect(delayed.terminationCount == 1)
    }

    @Test("Rapid A to B reselection drains A and cannot rebound")
    func rapidReselection() async throws {
        let directory = ClientControlledStream<ClientListSnapshot>()
        let detailA = ClientDelayedDetailValueSource()
        let detailB = ClientControlledStream<ClientCoreDetailsUpdate>()
        let requests = ClientDetailRequestRecorder()
        let model = Self.model()
        let a = try Self.client("client-a", name: "A")
        let b = try Self.client("client-b", name: "B")
        await model.start(runtime: ClientBrowsingStagingRuntime(
            watchClients: { directory.stream },
            watchClient: { request in
                requests.record(request)
                return request.clientId == a.id ? detailA.stream : detailB.stream
            }
        ))
        directory.yield(try Self.directory([a, b]))
        await Self.waitUntil { model.activeClients.count == 2 }
        await model.select(clientId: a.id, segment: .active)
        await Self.waitUntil { requests.requests.count == 1 }
        #expect(await Self.waitUntilAsync { await detailA.isWaiting })
        await detailA.release(try Self.snapshotUpdate(
            requests.requests[0], client: a, revision: 1, version: "a"
        ))
        await Self.waitUntil { model.detailStateLabel == "found" }
        #expect(await Self.waitUntilAsync { await detailA.isWaiting })

        let selectB = Task { @MainActor in
            await model.select(clientId: b.id, segment: .active)
        }
        for _ in 0..<20 { await Task.yield() }
        #expect(requests.requests.count == 1)
        await detailA.release(try Self.snapshotUpdate(
            requests.requests[0],
            client: try Self.client("client-a", name: "Late A", updatedAt: Self.t2),
            revision: 2,
            version: "late-a"
        ))
        await selectB.value
        await Self.waitUntil { requests.requests.count == 2 }
        #expect(model.selectedClientId == b.id)
        #expect(model.selectedClientName == "B")
        detailB.yield(try Self.update(requests.requests[1], .waiting(.loading)))
        await Self.waitUntil { model.detailStateLabel == "waiting" }
        #expect(model.selectedClientId == b.id)
        await model.stop()
    }

    @Test("Stop cancels and joins both active observations before returning")
    func stopDrainsBothActiveObservations() async throws {
        let directory = ClientControlledStream<ClientListSnapshot>()
        let detail = ClientDelayedCancellationDetailSource()
        let requests = ClientDetailRequestRecorder()
        let model = Self.model()
        await model.start(runtime: ClientBrowsingStagingRuntime(
            watchClients: { directory.stream },
            watchClient: { request in requests.record(request); return detail.stream }
        ))
        let client = try Self.client("client-a")
        directory.yield(try Self.directory([client]))
        await Self.waitUntil { model.activeClients.count == 1 }
        await model.select(clientId: client.id, segment: .active)
        await Self.waitUntil { requests.requests.count == 1 }
        #expect(await Self.waitUntilAsync { await detail.isWaiting })

        let completion = ClientCompletionProbe()
        let stop = Task { @MainActor in
            completion.markStarted()
            await model.stop()
            completion.markFinished()
        }
        await Self.waitUntil { completion.didStart }
        await Self.waitUntil { directory.terminationCount == 1 }
        #expect(!completion.didFinish)
        #expect(detail.terminationCount == 0)

        await detail.releaseCancellation()
        await stop.value
        #expect(completion.didFinish)
        #expect(directory.terminationCount == 1)
        #expect(detail.terminationCount == 1)
        #expect(model.directoryStatus == "stopped • completeness unknown")
        #expect(model.detailStateLabel == "stopped")
        directory.yield(try Self.directory(
            [Self.client("post-stop")], version: "post-stop-both"
        ))
        #expect(model.activeClients.isEmpty)
    }

    @Test("Stop restart rejects noncooperative old directory and detail evidence")
    func restartGenerationIsolation() async throws {
        let oldDirectory = ClientDelayedDirectoryValueSource()
        let firstModel = Self.model()
        await firstModel.start(runtime: ClientBrowsingStagingRuntime(
            watchClients: { oldDirectory.stream },
            watchClient: { _ in AsyncThrowingStream { $0.finish() } }
        ))
        #expect(await Self.waitUntilAsync { await oldDirectory.isWaiting })
        let newDirectory = ClientControlledStream<ClientListSnapshot>()
        let restartDirectory = Task { @MainActor in
            await firstModel.start(runtime: Self.runtime(directory: newDirectory))
        }
        await Self.waitUntil { firstModel.directoryStatus == "loading • completeness unknown" }
        await oldDirectory.release(try Self.directory(
            [Self.client("old")], version: "late-old-directory"
        ))
        await restartDirectory.value
        let newClient = try Self.client("new")
        newDirectory.yield(try Self.directory([newClient], version: "new-directory"))
        await Self.waitUntil { firstModel.activeClients.first?.clientId == newClient.id }
        #expect(firstModel.activeClients.map(\.clientId) == [newClient.id])
        await firstModel.stop()

        let firstDirectory = ClientControlledStream<ClientListSnapshot>()
        let oldDetail = ClientDelayedDetailValueSource()
        let requests = ClientDetailRequestRecorder()
        let model = Self.model()
        await model.start(runtime: ClientBrowsingStagingRuntime(
            watchClients: { firstDirectory.stream },
            watchClient: { request in requests.record(request); return oldDetail.stream }
        ))
        let first = try Self.client("first", name: "First")
        firstDirectory.yield(try Self.directory([first], version: "first"))
        await Self.waitUntil { model.activeClients.count == 1 }
        await model.select(clientId: first.id, segment: .active)
        await Self.waitUntil { requests.requests.count == 1 }
        #expect(await Self.waitUntilAsync { await oldDetail.isWaiting })
        await oldDetail.release(try Self.snapshotUpdate(
            requests.requests[0], client: first, revision: 1, version: "accepted-old-detail"
        ))
        await Self.waitUntil { model.detailStateLabel == "found" }
        #expect(await Self.waitUntilAsync { await oldDetail.isWaiting })

        let secondDirectory = ClientControlledStream<ClientListSnapshot>()
        let restartDetail = Task { @MainActor in
            await model.start(runtime: Self.runtime(directory: secondDirectory))
        }
        await Self.waitUntil { model.directoryStatus == "loading • completeness unknown" }
        await oldDetail.release(try Self.snapshotUpdate(
            requests.requests[0],
            client: try Self.client("first", name: "Late First", updatedAt: Self.t2),
            revision: 2,
            version: "late-old-detail"
        ))
        await restartDetail.value
        let second = try Self.client("second", name: "Second")
        secondDirectory.yield(try Self.directory([second], version: "second"))
        await Self.waitUntil { model.activeClients.first?.clientId == second.id }
        #expect(model.selectedClient == nil)
        #expect(model.detailStateLabel == "not selected")
        await model.stop()

        let beforeEvidence = ClientControlledStream<ClientListSnapshot>()
        await model.start(runtime: Self.runtime(directory: beforeEvidence))
        await model.stop()
        #expect(beforeEvidence.terminationCount == 1)
        #expect(model.directoryStatus == "stopped • completeness unknown")
        #expect(model.detailStateLabel == "stopped")
        beforeEvidence.yield(try Self.directory(
            [Self.client("post-stop")], version: "post-stop"
        ))
        #expect(model.activeClients.isEmpty)
    }

    private static let accountId = try! AccountID(validating: "client-account")
    private static let t0 = Date(timeIntervalSince1970: 1_804_100_000)
    private static let t1 = Date(timeIntervalSince1970: 1_804_100_001)
    private static let t2 = Date(timeIntervalSince1970: 1_804_100_002)

    private static func model() -> ClientBrowsingStagingExercise {
        ClientBrowsingStagingExercise(accountId: accountId)
    }

    private static func runtime(
        directory: ClientControlledStream<ClientListSnapshot>,
        details: ClientDetailWatchProbe = ClientDetailWatchProbe()
    ) -> ClientBrowsingStagingRuntime {
        ClientBrowsingStagingRuntime(
            watchClients: { directory.stream },
            watchClient: { details.watch($0) }
        )
    }

    private static func client(
        _ id: String,
        name: String = "Client",
        lifecycle: DirectoryLifecycleState = .active,
        updatedAt: Date = t1,
        account: AccountID = accountId
    ) throws -> ClientSummary {
        try ClientSummary(
            id: ClientID(validating: id),
            accountId: account,
            displayName: ClientDisplayName(validating: name),
            lifecycle: lifecycle,
            createdAt: t0,
            updatedAt: updatedAt
        )
    }

    private static func directory(
        _ rows: [ClientSummary],
        account: AccountID = accountId,
        visibleCount: Int? = nil,
        complete: Bool = true,
        quality: ListSnapshotQuality = .ready,
        version: String = "directory"
    ) throws -> ClientListSnapshot {
        try ClientListSnapshot(
            accountId: account,
            local: ListLocalSnapshot(
                queryFingerprint: ListQueryFingerprint(
                    validating: String(repeating: String(version.utf8.count % 10), count: 64)
                ),
                rows: rows,
                visibleRowCountBeforeFiltering: visibleCount ?? rows.count,
                isCompleteForQuery: complete,
                quality: quality,
                localDataVersion: LocalDataVersion(validating: version),
                asOf: t2.addingTimeInterval(Double(version.utf8.count))
            )
        )
    }

    private static func detailRow(
        _ client: ClientSummary,
        revision: UInt64
    ) -> ClientCoreDetailsSnapshot {
        ClientCoreDetailsSnapshot(
            client: client,
            locallyObservedRevision: ExpectedClientRevision(revision)
        )
    }

    private static func detailLocal(
        _ request: ClientCoreDetailsRequest,
        rows: [ClientCoreDetailsSnapshot],
        complete: Bool = true,
        quality: ListSnapshotQuality = .ready,
        version: String
    ) throws -> ClientCoreDetailsLocalSnapshot {
        try ClientCoreDetailsLocalSnapshot(
            request: request,
            rows: rows,
            visibleRowCountBeforeFiltering: rows.count,
            isCompleteForQuery: complete,
            quality: quality,
            localDataVersion: LocalDataVersion(validating: version),
            asOf: t2.addingTimeInterval(Double(version.utf8.count))
        )
    }

    private static func update(
        _ request: ClientCoreDetailsRequest,
        _ state: ClientCoreDetailsUpdateState
    ) throws -> ClientCoreDetailsUpdate {
        try ClientCoreDetailsUpdate(request: request, state: state)
    }

    private static func snapshotUpdate(
        _ request: ClientCoreDetailsRequest,
        client: ClientSummary,
        revision: UInt64,
        complete: Bool = true,
        quality: ListSnapshotQuality = .ready,
        version: String
    ) throws -> ClientCoreDetailsUpdate {
        try update(request, .snapshot(detailLocal(
            request,
            rows: [detailRow(client, revision: revision)],
            complete: complete,
            quality: quality,
            version: version
        )))
    }

    private static func emptyUpdate(
        _ request: ClientCoreDetailsRequest,
        complete: Bool,
        quality: ListSnapshotQuality,
        version: String
    ) throws -> ClientCoreDetailsUpdate {
        try update(request, .snapshot(detailLocal(
            request,
            rows: [],
            complete: complete,
            quality: quality,
            version: version
        )))
    }

    private static func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<2_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("Timed out waiting for Client browsing state")
    }

    private static func waitUntilAsync(
        _ condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        for _ in 0..<2_000 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return false
    }
}

enum ClientDirectoryTerminationCase: String, CaseIterable, Sendable {
    case throwBeforeFirst, throwAfterFirst, cancelBeforeFirst, cancelAfterFirst
    case completeBeforeFirst, completeAfterFirst

    var isBeforeFirstValue: Bool {
        switch self {
        case .throwBeforeFirst, .cancelBeforeFirst, .completeBeforeFirst: true
        case .throwAfterFirst, .cancelAfterFirst, .completeAfterFirst: false
        }
    }
    var diagnostic: String {
        switch self {
        case .throwBeforeFirst, .throwAfterFirst: "client_directory_local_failed"
        case .cancelBeforeFirst, .cancelAfterFirst: "client_directory_source_cancelled"
        case .completeBeforeFirst, .completeAfterFirst: "client_directory_source_completed"
        }
    }
    fileprivate func finish(_ stream: ClientControlledStream<ClientListSnapshot>) {
        switch self {
        case .throwBeforeFirst, .throwAfterFirst: stream.finish(throwing: ClientSourceFailure.upstream)
        case .cancelBeforeFirst, .cancelAfterFirst: stream.finish(throwing: CancellationError())
        case .completeBeforeFirst, .completeAfterFirst: stream.finish()
        }
    }
}

enum ClientDetailTerminationCase: String, CaseIterable, Sendable {
    case throwBeforeFirst, throwAfterFirst, cancelBeforeFirst, cancelAfterFirst
    case completeBeforeFirst, completeAfterFirst

    var isBeforeFirstValue: Bool {
        switch self {
        case .throwBeforeFirst, .cancelBeforeFirst, .completeBeforeFirst: true
        case .throwAfterFirst, .cancelAfterFirst, .completeAfterFirst: false
        }
    }
    var diagnostic: String {
        switch self {
        case .throwBeforeFirst, .throwAfterFirst: "client_detail_local_failed"
        case .cancelBeforeFirst, .cancelAfterFirst: "client_detail_source_cancelled"
        case .completeBeforeFirst, .completeAfterFirst: "client_detail_source_completed"
        }
    }
    fileprivate func finish(_ stream: ClientControlledStream<ClientCoreDetailsUpdate>) {
        switch self {
        case .throwBeforeFirst, .throwAfterFirst: stream.finish(throwing: ClientSourceFailure.upstream)
        case .cancelBeforeFirst, .cancelAfterFirst: stream.finish(throwing: CancellationError())
        case .completeBeforeFirst, .completeAfterFirst: stream.finish()
        }
    }
}

private enum ClientSourceFailure: Error { case upstream }

private final class ClientControlledStream<Value: Sendable>: @unchecked Sendable {
    let stream: AsyncThrowingStream<Value, Error>
    private let continuation: AsyncThrowingStream<Value, Error>.Continuation
    private let termination = ClientTerminationProbe()

    init() {
        var captured: AsyncThrowingStream<Value, Error>.Continuation?
        let termination = termination
        stream = AsyncThrowingStream { continuation in
            captured = continuation
            continuation.onTermination = { _ in termination.record() }
        }
        continuation = captured!
    }
    var terminationCount: Int { termination.count }
    func yield(_ value: Value) { continuation.yield(value) }
    func finish() { continuation.finish() }
    func finish(throwing error: Error) { continuation.finish(throwing: error) }
}

private final class ClientTerminationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded = 0
    var count: Int { lock.withLock { recorded } }
    func record() { lock.withLock { recorded += 1 } }
}

private final class ClientDetailWatchProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [ClientCoreDetailsRequest] = []
    private var sources: [String: [ClientControlledStream<ClientCoreDetailsUpdate>]]
    private let defaultSource: ClientControlledStream<ClientCoreDetailsUpdate>?

    init(
        sources: [String: [ClientControlledStream<ClientCoreDetailsUpdate>]] = [:],
        defaultSource: ClientControlledStream<ClientCoreDetailsUpdate>? = nil
    ) {
        self.sources = sources
        self.defaultSource = defaultSource
    }
    convenience init(defaultSource: ClientControlledStream<ClientCoreDetailsUpdate>) {
        self.init(sources: [:], defaultSource: defaultSource)
    }
    var requests: [ClientCoreDetailsRequest] { lock.withLock { recorded } }
    func watch(_ request: ClientCoreDetailsRequest)
        -> AsyncThrowingStream<ClientCoreDetailsUpdate, Error>
    {
        lock.withLock {
            recorded.append(request)
            let key = request.clientId.rawValue
            if var queued = sources[key], !queued.isEmpty {
                let source = queued.removeFirst()
                sources[key] = queued
                return source.stream
            }
            if let defaultSource { return defaultSource.stream }
            return AsyncThrowingStream { $0.finish(throwing: ClientSourceFailure.upstream) }
        }
    }
}

private final class ClientDetailRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [ClientCoreDetailsRequest] = []
    var requests: [ClientCoreDetailsRequest] { lock.withLock { recorded } }
    func record(_ request: ClientCoreDetailsRequest) { lock.withLock { recorded.append(request) } }
}

private final class ClientCompletionProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var started = false
    private var finished = false
    var didStart: Bool { lock.withLock { started } }
    var didFinish: Bool { lock.withLock { finished } }
    func markStarted() { lock.withLock { started = true } }
    func markFinished() { lock.withLock { finished = true } }
}

private final class ClientDelayedCancellationDetailSource: @unchecked Sendable {
    let stream: AsyncThrowingStream<ClientCoreDetailsUpdate, Error>
    private let gate: ClientDelayedCancellationGate
    private let termination = ClientTerminationProbe()

    init() {
        let gate = ClientDelayedCancellationGate()
        let termination = termination
        self.gate = gate
        stream = AsyncThrowingStream(unfolding: {
            do { return try await gate.next() }
            catch { termination.record(); throw error }
        })
    }
    var terminationCount: Int { termination.count }
    var isWaiting: Bool { get async { await gate.isWaiting } }
    func releaseCancellation() async { await gate.releaseCancellation() }
}

private final class ClientDelayedDirectoryValueSource: @unchecked Sendable {
    let stream: AsyncThrowingStream<ClientListSnapshot, Error>
    private let gate: ClientDelayedDirectoryGate
    init() {
        let gate = ClientDelayedDirectoryGate()
        self.gate = gate
        stream = AsyncThrowingStream(unfolding: { await gate.next() })
    }
    var isWaiting: Bool { get async { await gate.isWaiting } }
    func release(_ value: ClientListSnapshot) async { await gate.release(value) }
}

private final class ClientDelayedDetailValueSource: @unchecked Sendable {
    let stream: AsyncThrowingStream<ClientCoreDetailsUpdate, Error>
    private let gate: ClientDelayedDetailGate
    init() {
        let gate = ClientDelayedDetailGate()
        self.gate = gate
        stream = AsyncThrowingStream(unfolding: { await gate.next() })
    }
    var isWaiting: Bool { get async { await gate.isWaiting } }
    func release(_ value: ClientCoreDetailsUpdate) async { await gate.release(value) }
}

private actor ClientDelayedCancellationGate {
    private var continuation: CheckedContinuation<ClientCoreDetailsUpdate?, Error>?
    var isWaiting: Bool { continuation != nil }
    func next() async throws -> ClientCoreDetailsUpdate? {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func releaseCancellation() {
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}

private actor ClientDelayedDirectoryGate {
    private var continuation: CheckedContinuation<ClientListSnapshot?, Never>?
    var isWaiting: Bool { continuation != nil }
    func next() async -> ClientListSnapshot? {
        await withCheckedContinuation { continuation = $0 }
    }
    func release(_ value: ClientListSnapshot) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}

private actor ClientDelayedDetailGate {
    private var continuation: CheckedContinuation<ClientCoreDetailsUpdate?, Never>?
    var isWaiting: Bool { continuation != nil }
    func next() async -> ClientCoreDetailsUpdate? {
        await withCheckedContinuation { continuation = $0 }
    }
    func release(_ value: ClientCoreDetailsUpdate) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}
