import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Scoped Route Resolution and Restoration")
struct ScopedRouteResolutionTests {
    @Test("Route registry rejects raw or structurally invalid destination shapes")
    func routeRegistryIsClosedAndValidated() throws {
        let registry = try Self.registry()
        let projectRoute = try Self.projectRoute()
        try registry.validate(projectRoute)

        let unknownKind = try RouteKindID(validating: "raw_firestore_path")
        let unknown = ScopedRoute(kindId: unknownKind)
        #expect(Self.captureFailure { try registry.validate(unknown) } == .unknownRouteKind(unknownKind))

        let projectKind = try RouteKindID(validating: "project_detail")
        let missingSubject = ScopedRoute(kindId: projectKind)
        #expect(Self.captureFailure { try registry.validate(missingSubject) } == .missingRouteSubject(projectKind))

        let wrongSubject = ScopedRoute(
            kindId: projectKind,
            subject: try Self.reference(.item, "item-001")
        )
        #expect(Self.captureFailure { try registry.validate(wrongSubject) } == .routeSubjectKindMismatch(projectKind))

        let settingsKind = try RouteKindID(validating: "settings_root")
        let settingsWithParent = ScopedRoute(
            kindId: settingsKind,
            parent: try Self.reference(.project, "project-001")
        )
        #expect(Self.captureFailure { try registry.validate(settingsWithParent) } == .unexpectedRouteParent(settingsKind))

        let itemKind = try RouteKindID(validating: "item_detail")
        let itemWithoutParent = ScopedRoute(
            kindId: itemKind,
            subject: try Self.reference(.item, "item-001")
        )
        #expect(Self.captureFailure { try registry.validate(itemWithoutParent) } == .missingRouteParent(itemKind))

        let duplicateFailure = Self.captureFailure {
            let definition = try RouteDefinition(
                kindId: settingsKind,
                subjectKind: nil,
                parentPolicy: .forbidden
            )
            _ = try RouteRegistry(definitions: [definition, definition])
        }
        #expect(duplicateFailure == .duplicateRouteKind(settingsKind))

        #expect(Self.captureFailure {
            _ = try RouteDefinition(
                kindId: itemKind,
                subjectKind: .item,
                parentPolicy: .required(allowedKinds: [])
            )
        } == .invalidParentPolicy(itemKind))

        #expect(Self.captureFailure {
            _ = try RouteRestorationKey(validating: "account-a/project-001")
        } == .invalidRestorationKey)
    }

    @Test("Restoration is deterministic offline and refuses every workspace boundary mismatch")
    func restorationIsScopedAndRestartSafe() throws {
        let scope = try Self.scope(
            environment: .targetStaging,
            principal: "principal-a",
            account: "account-a"
        )
        let version = try RouteContractVersion(validating: "routes-v1")
        let record = RouteRestorationRecord(
            contractVersion: version,
            scope: scope,
            route: try Self.projectRoute()
        )
        let registry = try Self.registry()
        let keyBeforeRestart = try record.validate(
            activeScope: scope,
            supportedContractVersion: version,
            registry: registry
        )
        let restored = try OperationContractCodec.decode(
            RouteRestorationRecord.self,
            from: OperationContractCodec.encode(record)
        )
        let keyAfterRestart = try restored.validate(
            activeScope: scope,
            supportedContractVersion: version,
            registry: registry
        )

        #expect(restored == record)
        #expect(keyAfterRestart == keyBeforeRestart)
        #expect(keyBeforeRestart.sha256.count == 64)
        #expect(!keyBeforeRestart.sha256.contains(scope.accountId.rawValue))
        #expect(!keyBeforeRestart.sha256.contains(scope.principalId.rawValue))

        for otherScope in [
            try Self.scope(
                environment: .targetLocal,
                principal: "principal-a",
                account: "account-a"
            ),
            try Self.scope(
                environment: .targetStaging,
                principal: "principal-b",
                account: "account-a"
            ),
            try Self.scope(
                environment: .targetStaging,
                principal: "principal-a",
                account: "account-b"
            )
        ] {
            #expect(Self.captureFailure {
                _ = try restored.validate(
                    activeScope: otherScope,
                    supportedContractVersion: version,
                    registry: registry
                )
            } == .workspaceScopeMismatch)
        }

        #expect(Self.captureFailure {
            _ = try restored.validate(
                activeScope: scope,
                supportedContractVersion: RouteContractVersion(validating: "routes-v2"),
                registry: registry
            )
        } == .restorationContractMismatch)

        let settingsOnly = try RouteRegistry(definitions: [
            RouteDefinition(
                kindId: RouteKindID(validating: "settings_root"),
                subjectKind: nil,
                parentPolicy: .forbidden
            )
        ])
        #expect(Self.captureFailure {
            _ = try restored.validate(
                activeScope: scope,
                supportedContractVersion: version,
                registry: settingsOnly
            )
        } == .unknownRouteKind(record.route.kindId))
    }

    @Test("Resolution is non-enumerating and rejects late workspace results without mutation")
    func resolutionFailsClosedAcrossWorkspaceTransitions() throws {
        let registry = try Self.registry()
        let scope = try Self.scope(
            environment: .targetStaging,
            principal: "principal-a",
            account: "account-a"
        )
        let request = try Self.request(
            scope: scope,
            activation: "activation-a",
            request: "request-a",
            route: Self.projectRoute(),
            registry: registry
        )
        let cached = RouteLocalSnapshot(
            destination: FixtureDestination(title: "Cached project"),
            localDataVersion: try LocalDataVersion(validating: "route-local-1"),
            asOf: Date(timeIntervalSince1970: 1_800_100_000)
        )

        var readyReducer = RouteResolutionReducer<FixtureDestination>(request: request)
        let ready = try readyReducer.apply(.ready(request: request, snapshot: cached))
        #expect(ready.readiness == .ready)
        #expect(ready.destination == cached.destination)

        let inaccessibleStates = try [
            RouteResolutionFailureCause.notFound,
            .notAuthorized,
            .notAuthenticated,
            .membershipRevoked
        ].map { cause in
            var reducer = RouteResolutionReducer<FixtureDestination>(request: request)
            _ = try reducer.apply(.ready(request: request, snapshot: cached))
            return try reducer.apply(.failed(request: request, cause: cause, cached: cached))
        }
        #expect(inaccessibleStates.dropFirst().allSatisfy { $0 == inaccessibleStates.first })
        #expect(inaccessibleStates.first?.readiness == .unavailable)
        #expect(inaccessibleStates.first?.destination == nil)
        #expect(inaccessibleStates.first?.localDataVersion == nil)

        var notSyncedReducer = RouteResolutionReducer<FixtureDestination>(request: request)
        let notSynced = try notSyncedReducer.apply(.notSynced(request: request, cached: cached))
        #expect(notSynced.readiness == .notSynced)
        #expect(notSynced.destination == cached.destination)
        #expect(notSynced.failure == nil)

        var transientReducer = RouteResolutionReducer<FixtureDestination>(request: request)
        let transient = try transientReducer.apply(
            .failed(request: request, cause: .transientInfrastructure, cached: cached)
        )
        #expect(transient.readiness == .stale)
        #expect(transient.destination == cached.destination)
        #expect(transient.failure == .retryable)
        #expect(transient.retryIntent == RetryRouteResolutionIntent(request: request))

        var requiredUpdateReducer = RouteResolutionReducer<FixtureDestination>(request: request)
        let requiredUpdate = try requiredUpdateReducer.apply(
            .failed(request: request, cause: .unsupportedContract, cached: cached)
        )
        #expect(requiredUpdate.readiness == .blocked)
        #expect(requiredUpdate.destination == nil)
        #expect(requiredUpdate.failure == .requiredUpdate)
        #expect(requiredUpdate.retryIntent == nil)

        let mismatchedRequests = try [
            Self.request(
                scope: Self.scope(
                    environment: .targetStaging,
                    principal: "principal-a",
                    account: "account-b"
                ),
                activation: "activation-a",
                request: "request-a",
                route: Self.projectRoute(),
                registry: registry
            ),
            Self.request(
                scope: scope,
                activation: "activation-old",
                request: "request-a",
                route: Self.projectRoute(),
                registry: registry
            ),
            Self.request(
                scope: scope,
                activation: "activation-a",
                request: "request-old",
                route: Self.projectRoute(),
                registry: registry
            ),
            Self.request(
                scope: scope,
                activation: "activation-a",
                request: "request-a",
                route: ScopedRoute(kindId: RouteKindID(validating: "settings_root")),
                registry: registry
            )
        ]
        let expectedFailures: [ScopedRouteContractFailure] = [
            .workspaceScopeMismatch,
            .workspaceActivationMismatch,
            .routeRequestMismatch,
            .routeMismatch
        ]
        for (lateRequest, expectedFailure) in zip(mismatchedRequests, expectedFailures) {
            var reducer = RouteResolutionReducer<FixtureDestination>(request: request)
            let before = reducer.state
            let failure = Self.captureFailure {
                _ = try reducer.apply(.ready(request: lateRequest, snapshot: cached))
            }
            #expect(failure == expectedFailure)
            #expect(reducer.state == before)
        }
    }

    private static func registry() throws -> RouteRegistry {
        try RouteRegistry(definitions: [
            RouteDefinition(
                kindId: RouteKindID(validating: "settings_root"),
                subjectKind: nil,
                parentPolicy: .forbidden
            ),
            RouteDefinition(
                kindId: RouteKindID(validating: "project_detail"),
                subjectKind: .project,
                parentPolicy: .optional(allowedKinds: [.client])
            ),
            RouteDefinition(
                kindId: RouteKindID(validating: "item_detail"),
                subjectKind: .item,
                parentPolicy: .required(allowedKinds: [.project, .invoice])
            )
        ])
    }

    private static func projectRoute() throws -> ScopedRoute {
        ScopedRoute(
            kindId: try RouteKindID(validating: "project_detail"),
            subject: try reference(.project, "project-001"),
            parent: try reference(.client, "client-001")
        )
    }

    private static func reference(
        _ kind: LedgerEntityKind,
        _ id: String
    ) throws -> LedgerEntityReference {
        LedgerEntityReference(kind: kind, id: try EntityID(validating: id))
    }

    private static func scope(
        environment: LedgerEnvironmentKind,
        principal: String,
        account: String
    ) throws -> WorkspaceRouteScope {
        WorkspaceRouteScope(
            environment: environment,
            principalId: try PrincipalID(validating: principal),
            accountId: try AccountID(validating: account)
        )
    }

    private static func request(
        scope: WorkspaceRouteScope,
        activation: String,
        request: String,
        route: ScopedRoute,
        registry: RouteRegistry
    ) throws -> RouteResolutionRequest {
        try RouteResolutionRequest(
            scope: scope,
            workspaceActivationId: WorkspaceActivationID(validating: activation),
            requestId: RouteResolutionRequestID(validating: request),
            route: route,
            registry: registry
        )
    }

    private static func captureFailure(
        _ operation: () throws -> Void
    ) -> ScopedRouteContractFailure? {
        do {
            try operation()
            return nil
        } catch let failure as ScopedRouteContractFailure {
            return failure
        } catch {
            return nil
        }
    }

    private struct FixtureDestination: Codable, Equatable, Sendable {
        let title: String
    }
}
