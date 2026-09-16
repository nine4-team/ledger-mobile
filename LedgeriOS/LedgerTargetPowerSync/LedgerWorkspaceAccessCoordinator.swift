import Foundation

/// Shared by all handles; removal blocks admission before close tasks run.
final class LedgerWorkspaceAccessFence: @unchecked Sendable {
    private let lock = NSLock()
    private var removed = false
    private var commandUploadInProgress = false
    private var syncConnectionInUse = false
    private var openRuntimeCount = 0
    private var sessionEnding = false
    private var observers: [UUID: AsyncStream<Void>.Continuation] = [:]
    var isRemoved: Bool { lock.withLock { removed } }

    // Count pending opens too: database initialization/close in another handle
    // can alter the SDK coordinator shared by the physical database filename.
    func beginRuntimeOpen() throws {
        try lock.withLock {
            guard !sessionEnding else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            guard !removed else {
                throw LedgerPowerSyncLocalBootstrapFailure(stage: .workspaceAccessRemoved)
            }
            guard !syncConnectionInUse else { throw LedgerOfflineClientRuntimeFailure.syncAlreadyStarted }
            openRuntimeCount += 1
        }
    }

    func endRuntimeOpen() {
        lock.withLock {
            precondition(openRuntimeCount > 0)
            openRuntimeCount -= 1
        }
    }

    // Voluntary logout is not membership revocation. This temporary fence also
    // covers pending opens, and stays held through the caller's cleanup.
    func beginSessionEnding() throws {
        try lock.withLock {
            guard !removed, !sessionEnding else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            guard openRuntimeCount == 1 else {
                throw LedgerOfflineClientRuntimeFailure.syncRequiresExclusiveWorkspace
            }
            sessionEnding = true
        }
    }

    func endSessionEnding() { lock.withLock { sessionEnding = false } }

    func beginClosedWorkspaceCleanup() throws {
        try lock.withLock {
            guard !removed, !sessionEnding else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            guard openRuntimeCount == 0, !syncConnectionInUse, !commandUploadInProgress else {
                throw LedgerOfflineClientRuntimeFailure.syncRequiresExclusiveWorkspace
            }
            sessionEnding = true
        }
    }

    func beginSyncConnection() throws {
        try lock.withLock {
            guard !removed else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            guard !syncConnectionInUse else { throw LedgerOfflineClientRuntimeFailure.syncAlreadyStarted }
            guard openRuntimeCount == 1 else {
                throw LedgerOfflineClientRuntimeFailure.syncRequiresExclusiveWorkspace
            }
            syncConnectionInUse = true
        }
    }

    func endSyncConnection() {
        lock.withLock { syncConnectionInUse = false }
    }

    func beginCommandUpload() throws {
        try lock.withLock {
            guard !removed else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            guard !commandUploadInProgress else {
                throw LedgerPowerSyncUploadFailure.uploadAlreadyRunning
            }
            commandUploadInProgress = true
        }
    }

    func endCommandUpload() {
        lock.withLock { commandUploadInProgress = false }
    }
    func markRemoved() {
        let pending = lock.withLock {
            removed = true
            let values = Array(observers.values)
            observers.removeAll()
            return values
        }
        for observer in pending {
            observer.yield(())
            observer.finish()
        }
    }

    func watchRemoval() -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let id = UUID()
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { self?.observers.removeValue(forKey: id) }
            }
            let alreadyRemoved = lock.withLock {
                if removed { return true }
                observers[id] = continuation
                return false
            }
            if alreadyRemoved {
                continuation.yield(())
                continuation.finish()
            }
        }
    }
}

/// Serializes in-process bootstrap/removal for all handles of one stable
/// workspace. This is not an authentication provider or a grant of access.
actor LedgerWorkspaceAccessCoordinator {
    static let shared = LedgerWorkspaceAccessCoordinator()

    private struct Reference {
        weak var lifecycleOwner: AccountWorkspacePendingWorkRuntime?
    }
    private var fences: [String: LedgerWorkspaceAccessFence] = [:]
    private var runtimes: [String: [Reference]] = [:]

    /// Recovery cannot open databases whose cleanup is pending. Fence their
    /// closed locations directly, acquiring every scope before awaiting work.
    func withClosedWorkspaces(_ identities: [String],
                              body: @Sendable () async throws -> Void) async throws {
        guard !identities.isEmpty, Set(identities).count == identities.count else {
            throw LedgerOfflineClientRuntimeFailure.runtimeClosed
        }
        var acquired: [LedgerWorkspaceAccessFence] = []
        defer { for fence in acquired { fence.endSessionEnding() } }
        for identity in identities {
            let candidate = fence(for: identity)
            try candidate.beginClosedWorkspaceCleanup()
            acquired.append(candidate)
        }
        try await body()
    }

    func open(
        identity: String,
        body: @Sendable (LedgerWorkspaceAccessFence) async throws -> LedgerOfflineClientRuntime
    ) async throws -> LedgerOfflineClientRuntime {
        let fence = fence(for: identity)
        guard !fence.isRemoved else {
            throw LedgerPowerSyncLocalBootstrapFailure(stage: .workspaceAccessRemoved)
        }
        try fence.beginRuntimeOpen()
        let runtime: LedgerOfflineClientRuntime
        do {
            runtime = try await body(fence)
        } catch {
            fence.endRuntimeOpen()
            throw error
        }
        await runtime.lifecycleOwner.adoptOpenRegistration()
        // The actor is reentrant while opening databases. Removal wins even
        // when that opening ignores cancellation or has already passed a check.
        if fence.isRemoved {
            try? await runtime.lockLocalAccessPreservingPendingWork()
            throw LedgerPowerSyncLocalBootstrapFailure(stage: .workspaceAccessRemoved)
        }
        if Task.isCancelled {
            try? await runtime.close()
            throw CancellationError()
        }
        runtimes[identity, default: []].removeAll { $0.lifecycleOwner == nil }
        runtimes[identity, default: []].append(Reference(lifecycleOwner: runtime.lifecycleOwner))
        return runtime
    }

    /// Safe inside an SDK callback: fence and persist, but never await drainage
    /// of the callback that is reporting removal. The workspace owner observes
    /// the existing removal stream and completes cleanup outside that callback.
    func reportRemoval(identity: String, persist: @Sendable () throws -> Void) throws {
        fence(for: identity).markRemoved()
        do { try persist() }
        catch { throw LedgerOfflineClientRuntimeFailure.removalPersistenceFailed }
    }

    func finishReportedRemoval(identity: String, persist: @Sendable () throws -> Void) async throws {
        guard fences[identity]?.isRemoved == true else {
            throw LedgerOfflineClientRuntimeFailure.workspaceMembershipNotReady
        }
        try await remove(identity: identity, persist: persist)
    }

    func remove(
        identity: String,
        persist: @Sendable () throws -> Void
    ) async throws {
        var persistenceFailed = false
        do { try reportRemoval(identity: identity, persist: persist) } catch { persistenceFailed = true }
        let active = runtimes[identity, default: []].compactMap(\.lifecycleOwner)
        // Do not retain closed workspaces or wait for one handle's drain before
        // asking the other handles to lock. Each lifecycle owns its own drain.
        let closeFailed = await withTaskGroup(of: Bool.self) { group in
            for runtime in active {
                group.addTask {
                    do {
                        try await runtime.lockAccessPreservingPendingWork()
                        return false
                    } catch { return true }
                }
            }
            var failed = false
            for await value in group { failed = failed || value }
            return failed
        }
        if persistenceFailed { throw LedgerOfflineClientRuntimeFailure.removalPersistenceFailed }
        if closeFailed { throw LedgerOfflineClientRuntimeFailure.removalCloseFailed }
    }

    private func fence(for identity: String) -> LedgerWorkspaceAccessFence {
        if let existing = fences[identity] { return existing }
        let created = LedgerWorkspaceAccessFence()
        fences[identity] = created
        return created
    }
}
