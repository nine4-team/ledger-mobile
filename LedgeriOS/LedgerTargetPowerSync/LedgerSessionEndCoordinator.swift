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

    static func end(
        targets: [Target],
        admissions: OfflineWorkspaceAdmissionStore,
        userId: UUID,
        expectedWorkspaces: [OfflineWorkspaceAdmission],
        clearCachesAndEndProviderSession: @escaping @Sendable () async throws -> Void
    ) async throws {
        guard !targets.isEmpty,
              targets.allSatisfy({ $0.request.expectedSummary.principalId == targets[0].request.expectedSummary.principalId }),
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
            for target in targets {
                try LedgerWorkspaceSessionCleanup.begin(target.request, location: target.runtime.location)
            }
            for target in targets {
                try LedgerWorkspaceSessionCleanup.removeLocalData(target.request, location: target.runtime.location)
            }
            try await clearCachesAndEndProviderSession()
            for target in targets {
                try LedgerWorkspaceSessionCleanup.complete(target.request, location: target.runtime.location)
            }
            // Retain the identity recovery directory until individual markers
            // have cleared; a failed final write must not forget recovery scope.
            try await admissions.completeSessionEnding(userId)
        }
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
