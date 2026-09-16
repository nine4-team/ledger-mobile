import Foundation
import LedgerTargetCore

/// Coordinates the real runtime/cleanup boundary across a signed-in user's
/// downloaded Accounts. Every target needs its own current scoped disposition.
/// The caller owns the identity-level durable recovery record and Auth session.
enum LedgerSessionEndCoordinator {
    struct Target: Sendable {
        let runtime: LedgerOfflineClientRuntime
        let request: SessionEndRequest
    }
    private struct CleanupTarget: Sendable {
        let request: SessionEndRequest
        let location: LedgerWorkspaceRuntimeLocation
    }

    static func end(
        targets: [Target],
        admissions: OfflineWorkspaceAdmissionStore,
        userId: UUID,
        expectedWorkspaces: [OfflineWorkspaceAdmission],
        clearCachesAndEndProviderSession: @escaping @Sendable () async throws -> Void
    ) async throws {
        guard targets.allSatisfy({ $0.request.expectedSummary.principalId == targets[0].request.expectedSummary.principalId }),
              Set(targets.map { $0.runtime.location.sessionScopeIdentity }).count == targets.count else {
            throw SessionEndingFailure.scopeMismatch
        }
        // Preflight every Account before closing any. Destructive consent for
        // one Account never grants permission to discard work in another.
        for target in targets {
            let current = try await target.runtime.pendingWorkSummary()
            guard case .readyForTeardown = try SessionEndPolicy.evaluate(target.request, against: current) else {
                throw SessionEndingFailure.synchronizationIncomplete
            }
        }
        try await shutdown(targets[...]) {
            // All runtimes are closed and their temporary open fences are held.
            try await admissions.beginApprovedSessionEnding(userId,
                expectedWorkspaces: expectedWorkspaces, requests: targets.map(\.request),
                workspaceBindings: Dictionary(uniqueKeysWithValues: targets.map {
                    ($0.runtime.location.sessionScopeIdentity, $0.runtime.location.cleanupBinding)
                }))
            try await finishCleanup(targets.map { .init(request: $0.request, location: $0.runtime.location) },
                admissions: admissions, userId: userId, finishProvider: clearCachesAndEndProviderSession)
        }
    }

    static func recover(admissions: OfflineWorkspaceAdmissionStore, userId: UUID,
                        locations: [LedgerWorkspaceRuntimeLocation],
                        accessCoordinator: LedgerWorkspaceAccessCoordinator = .shared,
                        clearCachesAndEndProviderSession: @escaping @Sendable () async throws -> Void) async throws {
        let requests = try await admissions.approvedSessionEndingRequests(userId)
        guard locations.count == requests.count,
              Set(locations.map(\.sessionScopeIdentity)).count == locations.count else {
            throw SessionEndingFailure.scopeMismatch
        }
        var byScope: [String: SessionEndRequest] = [:]
        for request in requests {
            let summary = request.expectedSummary
            let scope = try LedgerWorkspaceRemovalRegistry.identity(environment: summary.environment,
                principalId: summary.principalId, accountId: summary.accountId)
            guard byScope.updateValue(request, forKey: scope) == nil else { throw SessionEndingFailure.scopeMismatch }
        }
        var prepared: [CleanupTarget] = []
        for location in locations {
            try await admissions.requireApprovedCleanupLocation(userId, location: location)
            guard let request = byScope[location.sessionScopeIdentity] else { throw SessionEndingFailure.scopeMismatch }
            prepared.append(.init(request: request, location: location))
        }
        let targets = prepared
        if targets.isEmpty {
            // Explicitly persisted empty plan: there are no database fences or
            // files to acquire/remove. Missing plans still fail above.
            guard try await admissions.workspacesForSessionEnding(userId).isEmpty else {
                throw SessionEndingFailure.summaryChanged
            }
            try await finishCleanup([], admissions: admissions, userId: userId,
                finishProvider: clearCachesAndEndProviderSession)
            return
        }
        try await accessCoordinator.withClosedWorkspaces(locations.map(\.sessionScopeIdentity)) {
            // A competing completion cannot turn stale recovery state into new
            // deletion authority while this task was acquiring its fences.
            guard try await admissions.approvedSessionEndingRequests(userId) == requests else {
                throw SessionEndingFailure.summaryChanged
            }
            for location in locations { try await admissions.requireApprovedCleanupLocation(userId, location: location) }
            try await finishCleanup(targets, admissions: admissions, userId: userId,
                finishProvider: clearCachesAndEndProviderSession)
        }
    }

    private static func finishCleanup(_ targets: [CleanupTarget], admissions: OfflineWorkspaceAdmissionStore,
                                      userId: UUID, finishProvider: @Sendable () async throws -> Void) async throws {
        for target in targets { try LedgerWorkspaceSessionCleanup.begin(target.request, location: target.location) }
        for target in targets { try LedgerWorkspaceSessionCleanup.removeLocalData(target.request, location: target.location) }
        try await finishProvider()
        for target in targets { try LedgerWorkspaceSessionCleanup.complete(target.request, location: target.location) }
        // Retain the complete recovery directory until individual markers clear.
        try await admissions.completeSessionEnding(userId)
    }

    private static func shutdown(
        _ targets: ArraySlice<Target>,
        teardown: @escaping @Sendable () async throws -> Void
    ) async throws {
        guard let target = targets.first else { return try await teardown() }
        try await target.runtime.lifecycleOwner.withSessionEndShutdown(target.request) {
            try await shutdown(targets.dropFirst(), teardown: teardown)
        }
    }
}
