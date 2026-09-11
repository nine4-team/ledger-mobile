import Foundation
import LedgerTargetCore
import Testing
@testable import LedgerTargetAppModel

@Suite("Transfer destination staging presenter")
@MainActor
struct TransferDestinationSelectionStagingExerciseTests {
    @Test("All presentation states stay distinct and selection follows current identity")
    func presentationAndSelection() async throws {
        let controlled = ControlledTransferDestinationStream()
        let sourceA = try Self.project("source", clientId: "client-a", name: "Source A")
        let destinationA = try Self.project(
            "destination", clientId: "client-a", name: "Same Name"
        )
        let sourceB = try Self.project("source", clientId: "client-b", name: "Source B")
        let destinationB = try Self.project(
            "destination", clientId: "client-b", name: "Same Name"
        )
        let model = TransferDestinationSelectionStagingExercise(accountId: Self.accountId)
        await model.open(
            source: sourceA,
            runtime: .init(watch: { _ in controlled.stream })
        )
        #expect(model.presentation == .waiting)

        let partial = try Self.selection(
            source: sourceA, destinations: [destinationA], quality: .partial,
            complete: false, marker: "a"
        )
        controlled.yield(partial)
        await Self.wait { model.presentation == .partial(partial.candidates) }
        #expect(model.select(projectId: destinationA.id))
        #expect(model.selectedProjectId == destinationA.id)

        let stale = try Self.selection(
            source: sourceA, destinations: [destinationA], quality: .stale,
            complete: false, marker: "b"
        )
        controlled.yield(stale)
        await Self.wait { model.presentation == .stale(stale.candidates) }
        #expect(model.selectedProjectId == destinationA.id)

        let ready = try Self.selection(
            source: sourceA, destinations: [destinationA], quality: .ready,
            complete: true, marker: "c"
        )
        controlled.yield(ready)
        await Self.wait { model.presentation == .ready(ready.candidates) }

        let destinationMissing = try Self.selection(
            source: sourceA, destinations: [], quality: .ready,
            complete: true, marker: "7"
        )
        controlled.yield(destinationMissing)
        await Self.wait { model.presentation == .authoritativeEmpty }
        #expect(model.selectedProjectId == nil)

        controlled.yield(ready)
        await Self.wait { model.presentation == .ready(ready.candidates) }
        #expect(model.selectedProjectId == nil)

        let reassigned = try Self.selection(
            source: sourceB, destinations: [destinationB], quality: .ready,
            complete: true, marker: "d"
        )
        controlled.yield(reassigned)
        await Self.wait { model.presentation == .ready(reassigned.candidates) }
        #expect(model.selectedProjectId == nil)
        #expect(model.rows.map(\.destination.id) == [destinationB.id])

        let partialEmpty = try Self.selection(
            source: sourceB, destinations: [], quality: .partial,
            complete: false, marker: "e"
        )
        controlled.yield(partialEmpty)
        await Self.wait { model.presentation == .partialEmpty }
        let staleEmpty = try Self.selection(
            source: sourceB, destinations: [], quality: .stale,
            complete: false, marker: "f"
        )
        controlled.yield(staleEmpty)
        await Self.wait { model.presentation == .staleEmpty }
        let authoritativeEmpty = try Self.selection(
            source: sourceB, destinations: [], quality: .ready,
            complete: true, marker: "1"
        )
        controlled.yield(authoritativeEmpty)
        await Self.wait { model.presentation == .authoritativeEmpty }

        await model.stop()
        #expect(model.selectedProjectId == nil)
        #expect(controlled.terminationCount == 1)
    }

    @Test("Source replacement drains the old watch and ignores late evidence")
    func replacementAndStopAreGenerationSafe() async throws {
        let old = ControlledTransferDestinationStream()
        let replacement = ControlledTransferDestinationStream()
        let calls = TransferDestinationWatchRecorder()
        let sourceA = try Self.project("source-a", clientId: "client-a", name: "A")
        let sourceB = try Self.project("source-b", clientId: "client-b", name: "B")
        let destinationA = try Self.project("destination-a", clientId: "client-a", name: "Old")
        let destinationB = try Self.project("destination-b", clientId: "client-b", name: "New")
        let runtime = TransferDestinationSelectionStagingRuntime { source in
            calls.record(source.id)
            return source.id == sourceA.id ? old.stream : replacement.stream
        }
        let model = TransferDestinationSelectionStagingExercise(accountId: Self.accountId)

        await model.open(source: sourceA, runtime: runtime)
        await Self.wait { calls.values == [sourceA.id] }
        let oldValue = try Self.selection(
            source: sourceA, destinations: [destinationA], quality: .ready,
            complete: true, marker: "2"
        )
        old.yield(oldValue)
        await Self.wait { model.rows.map(\.destination.id) == [destinationA.id] }
        #expect(model.select(projectId: destinationA.id))

        await model.open(source: sourceB, runtime: runtime)
        await Self.wait { calls.values == [sourceA.id, sourceB.id] }
        #expect(old.terminationCount == 1)
        #expect(model.presentation == .waiting)
        #expect(model.selectedProjectId == nil)

        old.yield(oldValue)
        let newValue = try Self.selection(
            source: sourceB, destinations: [destinationB], quality: .ready,
            complete: true, marker: "3"
        )
        replacement.yield(newValue)
        await Self.wait { model.rows.map(\.destination.id) == [destinationB.id] }
        #expect(model.select(projectId: destinationB.id))

        await model.stop()
        #expect(replacement.terminationCount == 1)
        #expect(model.selectedProjectId == nil)
        replacement.yield(newValue)
        try? await Task.sleep(for: .milliseconds(5))
        #expect(model.selectedProjectId == nil)
    }

    @Test("Incoherent evidence, stream completion, scope mismatch, and failures are bounded")
    func failuresAreBounded() async throws {
        let source = try Self.project("source", clientId: "client-a", name: "Source")

        let incoherentStream = ControlledTransferDestinationStream()
        let incoherentModel = TransferDestinationSelectionStagingExercise(
            accountId: Self.accountId
        )
        await incoherentModel.open(
            source: source,
            runtime: .init(watch: { _ in incoherentStream.stream })
        )
        incoherentStream.yield(try Self.selection(
            source: source, destinations: [], quality: .ready,
            complete: false, marker: "4"
        ))
        await Self.wait {
            incoherentModel.diagnostic == "transfer_destination_completeness_invalid"
        }
        #expect(incoherentModel.presentation != .authoritativeEmpty)

        let completed = ControlledTransferDestinationStream()
        let completedModel = TransferDestinationSelectionStagingExercise(
            accountId: Self.accountId
        )
        await completedModel.open(
            source: source,
            runtime: .init(watch: { _ in completed.stream })
        )
        completed.finish()
        await Self.wait {
            completedModel.diagnostic == "transfer_destination_local_read_failed"
        }

        let failed = ControlledTransferDestinationStream()
        let failedModel = TransferDestinationSelectionStagingExercise(
            accountId: Self.accountId
        )
        await failedModel.open(
            source: source,
            runtime: .init(watch: { _ in failed.stream })
        )
        failed.finish(throwing: PresenterControlledFailure.failed)
        await Self.wait {
            failedModel.diagnostic == "transfer_destination_local_read_failed"
        }

        let wrongAccount = try AccountID(validating: "account-other")
        let wrongSource = try Self.project(
            "wrong", accountId: wrongAccount, clientId: "client-other", name: "Wrong"
        )
        let watchCount = TransferDestinationWatchRecorder()
        let mismatch = TransferDestinationSelectionStagingExercise(accountId: Self.accountId)
        await mismatch.open(
            source: wrongSource,
            runtime: .init(watch: { _ in
                watchCount.record(wrongSource.id)
                return failed.stream
            })
        )
        await Self.wait {
            mismatch.diagnostic == "transfer_destination_directory_account_mismatch"
        }
        #expect(watchCount.values.isEmpty)

        await incoherentModel.stop()
        await completedModel.stop()
        await failedModel.stop()
        await mismatch.stop()
    }

    private static let accountId = try! AccountID(validating: "account-presenter")
    private static let observedAt = Date(timeIntervalSince1970: 1_788_600_000)

    private static func project(
        _ id: String,
        accountId: AccountID = accountId,
        clientId: String,
        name: String
    ) throws -> ProjectSummary {
        let clientID = try ClientID(validating: clientId)
        return try ProjectSummary(
            id: ProjectID(validating: id),
            accountId: accountId,
            clientId: clientID,
            client: ClientSummary(
                id: clientID,
                accountId: accountId,
                displayName: ClientDisplayName(validating: "Client \(clientId)"),
                lifecycle: .active,
                createdAt: observedAt,
                updatedAt: observedAt
            ),
            displayName: ProjectDisplayName(validating: name),
            description: nil,
            lifecycle: .active
        )
    }

    private static func selection(
        source: ProjectSummary,
        destinations: [ProjectSummary],
        quality: ListSnapshotQuality,
        complete: Bool,
        marker: Character
    ) throws -> TransferDestinationSelectionSnapshot {
        let directory = try ProjectListSnapshot(
            accountId: source.accountId,
            local: ListLocalSnapshot(
                queryFingerprint: ListQueryFingerprint(
                    validating: String(repeating: marker, count: 64)
                ),
                rows: [source] + destinations,
                visibleRowCountBeforeFiltering: destinations.count + 1,
                isCompleteForQuery: complete,
                quality: quality,
                localDataVersion: LocalDataVersion(
                    validating: "transfer-presenter-\(marker)"
                ),
                asOf: observedAt
            )
        )
        return try TransferDestinationSelectionSnapshot(
            source: source,
            directory: directory
        )
    }

    private static func wait(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<2_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("Timed out waiting for Transfer destination presentation")
    }
}

private enum PresenterControlledFailure: Error, Sendable {
    case failed
}

private final class ControlledTransferDestinationStream: @unchecked Sendable {
    let stream: AsyncThrowingStream<TransferDestinationSelectionSnapshot, Error>
    private let continuation:
        AsyncThrowingStream<TransferDestinationSelectionSnapshot, Error>.Continuation
    private let termination = TransferDestinationTerminationCounter()

    init() {
        var captured:
            AsyncThrowingStream<TransferDestinationSelectionSnapshot, Error>.Continuation!
        let termination = termination
        stream = AsyncThrowingStream { value in
            captured = value
            value.onTermination = { _ in termination.record() }
        }
        continuation = captured
    }

    var terminationCount: Int { termination.value }
    func yield(_ snapshot: TransferDestinationSelectionSnapshot) {
        continuation.yield(snapshot)
    }
    func finish() { continuation.finish() }
    func finish(throwing error: Error) { continuation.finish(throwing: error) }
}

private final class TransferDestinationTerminationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func record() { lock.withLock { count += 1 } }
}

private final class TransferDestinationWatchRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var projects: [ProjectID] = []
    var values: [ProjectID] { lock.withLock { projects } }
    func record(_ id: ProjectID) { lock.withLock { projects.append(id) } }
}
