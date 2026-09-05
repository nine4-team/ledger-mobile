import Foundation
import LedgerTargetCore

enum TransferDestinationSelectionPowerSyncFailure: Error, Equatable, Sendable {
    case sourceUnavailable

    var diagnosticCode: String {
        switch self {
        case .sourceUnavailable:
            "transfer_destination_source_unavailable"
        }
    }
}

protocol AccountWorkspaceTransferDestinationSelectionQuerying:
    TransferDestinationSelectionQuerying
{
    func cancelAndDrainWatches() async
}

/// A derived read over the existing Account-bound Project directory. This owns
/// no SQL, Sync Stream, cache, eligibility table, or Transfer write authority.
final class TransferDestinationSelectionPowerSyncQuery:
    AccountWorkspaceTransferDestinationSelectionQuerying, @unchecked Sendable
{
    private let directoryQuery: any ClientProjectDirectoryQuerying
    private let boundAccountId: AccountID
    private let registry = TransferDestinationSelectionWatchRegistry()

    init(
        directoryQuery: any ClientProjectDirectoryQuerying,
        accountId: AccountID
    ) {
        self.directoryQuery = directoryQuery
        boundAccountId = accountId
    }

    func watchTransferDestinations(
        source: ProjectSummary
    ) -> AsyncThrowingStream<TransferDestinationSelectionSnapshot, Error> {
        guard source.accountId == boundAccountId else {
            return Self.failedStream(
                TransferDestinationSelectionFailure.sourceDirectoryAccountMismatch
            )
        }

        return AsyncThrowingStream { continuation in
            let id = UUID()
            let handle = TransferDestinationSelectionWatchTaskHandle()
            let registration = Task { await registry.register(id: id, handle: handle) }
            let task = Task {
                let admitted = await registration.value
                guard admitted, !Task.isCancelled else {
                    continuation.finish()
                    if admitted { await registry.finished(id: id) }
                    return
                }
                await runWatch(sourceRequest: source, continuation: continuation)
                await registry.finished(id: id)
            }
            handle.install(task)
            continuation.onTermination = { _ in handle.cancel() }
        }
    }

    func cancelAndDrainWatches() async {
        await registry.cancelAndDrain()
    }

    private func runWatch(
        sourceRequest: ProjectSummary,
        continuation:
            AsyncThrowingStream<TransferDestinationSelectionSnapshot, Error>.Continuation
    ) async {
        do {
            let updates = directoryQuery.watchProjects(accountId: boundAccountId)
            for try await directory in updates {
                try Task.checkCancellation()
                guard directory.accountId == boundAccountId else {
                    throw TransferDestinationSelectionFailure.sourceDirectoryAccountMismatch
                }

                let snapshot: TransferDestinationSelectionSnapshot
                if let currentSource = directory.local.rows.first(where: {
                    $0.id == sourceRequest.id
                }) {
                    snapshot = try TransferDestinationSelectionSnapshot(
                        source: currentSource,
                        directory: directory
                    )
                } else if directory.local.isCompleteForQuery,
                          directory.local.quality == .ready {
                    throw TransferDestinationSelectionPowerSyncFailure.sourceUnavailable
                } else {
                    // With no represented source, caller fields are not allowed
                    // to filter rows. Reuse only its stable identity to produce
                    // an explicitly incomplete, zero-candidate result. If the
                    // source later appears, its current directory row replaces
                    // this request material before eligibility is derived.
                    let emptyDirectory = try ProjectListSnapshot(
                        accountId: directory.accountId,
                        local: ListLocalSnapshot(
                            queryFingerprint: directory.local.queryFingerprint,
                            rows: [],
                            visibleRowCountBeforeFiltering:
                                directory.local.visibleRowCountBeforeFiltering,
                            isCompleteForQuery: false,
                            quality: directory.local.quality,
                            localDataVersion: directory.local.localDataVersion,
                            asOf: directory.local.asOf
                        )
                    )
                    snapshot = try TransferDestinationSelectionSnapshot(
                        source: sourceRequest,
                        directory: emptyDirectory
                    )
                }
                if case .terminated = continuation.yield(snapshot) { break }
            }
            continuation.finish()
        } catch is CancellationError {
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    private static func failedStream<Value: Sendable>(
        _ error: Error
    ) -> AsyncThrowingStream<Value, Error> {
        AsyncThrowingStream { $0.finish(throwing: error) }
    }
}

private final class TransferDestinationSelectionWatchTaskHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var cancellationRequested = false

    func install(_ task: Task<Void, Never>) {
        let shouldCancel = lock.withLock {
            self.task = task
            return cancellationRequested
        }
        if shouldCancel { task.cancel() }
    }

    func cancel() {
        let installed = lock.withLock {
            cancellationRequested = true
            return task
        }
        installed?.cancel()
    }
}

private actor TransferDestinationSelectionWatchRegistry {
    private var handles: [UUID: TransferDestinationSelectionWatchTaskHandle] = [:]
    private var closing = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func register(
        id: UUID,
        handle: TransferDestinationSelectionWatchTaskHandle
    ) -> Bool {
        guard !closing else {
            handle.cancel()
            return false
        }
        handles[id] = handle
        return true
    }

    func finished(id: UUID) {
        handles.removeValue(forKey: id)
        guard handles.isEmpty else { return }
        let current = waiters
        waiters.removeAll(keepingCapacity: false)
        for waiter in current { waiter.resume() }
    }

    func cancelAndDrain() async {
        closing = true
        for handle in handles.values { handle.cancel() }
        guard !handles.isEmpty else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}
