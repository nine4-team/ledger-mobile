import CryptoKit
import Foundation

public enum ScopedRouteContractFailure: Error, Equatable, Sendable {
    case emptyRouteRegistry
    case duplicateRouteKind(RouteKindID)
    case invalidParentPolicy(RouteKindID)
    case unknownRouteKind(RouteKindID)
    case missingRouteSubject(RouteKindID)
    case unexpectedRouteSubject(RouteKindID)
    case routeSubjectKindMismatch(RouteKindID)
    case missingRouteParent(RouteKindID)
    case unexpectedRouteParent(RouteKindID)
    case routeParentKindMismatch(RouteKindID)
    case workspaceScopeMismatch
    case workspaceActivationMismatch
    case routeRequestMismatch
    case routeMismatch
    case restorationContractMismatch
    case invalidRestorationKey
}

public enum RouteKindIDTag: Sendable {}
public enum RouteContractVersionTag: Sendable {}
public enum WorkspaceActivationIDTag: Sendable {}
public enum RouteResolutionRequestIDTag: Sendable {}

public typealias RouteKindID = StableCode<RouteKindIDTag>
public typealias RouteContractVersion = LedgerIdentifier<RouteContractVersionTag>
public typealias WorkspaceActivationID = LedgerIdentifier<WorkspaceActivationIDTag>
public typealias RouteResolutionRequestID = LedgerIdentifier<RouteResolutionRequestIDTag>

public struct WorkspaceRouteScope: Codable, Equatable, Sendable {
    public let environment: LedgerEnvironmentKind
    public let principalId: PrincipalID
    public let accountId: AccountID

    public init(
        environment: LedgerEnvironmentKind,
        principalId: PrincipalID,
        accountId: AccountID
    ) {
        self.environment = environment
        self.principalId = principalId
        self.accountId = accountId
    }
}

public enum RouteParentPolicy: Codable, Equatable, Sendable {
    case forbidden
    case optional(allowedKinds: [LedgerEntityKind])
    case required(allowedKinds: [LedgerEntityKind])

    fileprivate var allowedKinds: [LedgerEntityKind] {
        switch self {
        case .forbidden:
            []
        case .optional(let allowedKinds), .required(let allowedKinds):
            allowedKinds
        }
    }
}

public struct RouteDefinition: Codable, Equatable, Sendable {
    public let kindId: RouteKindID
    public let subjectKind: LedgerEntityKind?
    public let parentPolicy: RouteParentPolicy

    public init(
        kindId: RouteKindID,
        subjectKind: LedgerEntityKind?,
        parentPolicy: RouteParentPolicy
    ) throws {
        let allowedKinds = parentPolicy.allowedKinds
        guard allowedKinds.isEmpty || Set(allowedKinds.map(\.rawValue)).count == allowedKinds.count else {
            throw ScopedRouteContractFailure.invalidParentPolicy(kindId)
        }
        switch parentPolicy {
        case .forbidden:
            break
        case .optional, .required:
            guard !allowedKinds.isEmpty else {
                throw ScopedRouteContractFailure.invalidParentPolicy(kindId)
            }
        }
        self.kindId = kindId
        self.subjectKind = subjectKind
        self.parentPolicy = parentPolicy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            kindId: container.decode(RouteKindID.self, forKey: .kindId),
            subjectKind: container.decodeIfPresent(LedgerEntityKind.self, forKey: .subjectKind),
            parentPolicy: container.decode(RouteParentPolicy.self, forKey: .parentPolicy)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case kindId
        case subjectKind
        case parentPolicy
    }
}

public struct ScopedRoute: Codable, Equatable, Sendable {
    public let kindId: RouteKindID
    public let subject: LedgerEntityReference?
    public let parent: LedgerEntityReference?

    public init(
        kindId: RouteKindID,
        subject: LedgerEntityReference? = nil,
        parent: LedgerEntityReference? = nil
    ) {
        self.kindId = kindId
        self.subject = subject
        self.parent = parent
    }
}

public struct RouteRegistry: Codable, Equatable, Sendable {
    public let definitions: [RouteDefinition]

    public init(definitions: [RouteDefinition]) throws {
        guard !definitions.isEmpty else {
            throw ScopedRouteContractFailure.emptyRouteRegistry
        }
        var seen: Set<RouteKindID> = []
        for definition in definitions where !seen.insert(definition.kindId).inserted {
            throw ScopedRouteContractFailure.duplicateRouteKind(definition.kindId)
        }
        self.definitions = definitions.sorted { $0.kindId.rawValue < $1.kindId.rawValue }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(definitions: container.decode([RouteDefinition].self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(definitions)
    }

    public func validate(_ route: ScopedRoute) throws {
        guard let definition = definitions.first(where: { $0.kindId == route.kindId }) else {
            throw ScopedRouteContractFailure.unknownRouteKind(route.kindId)
        }
        switch (definition.subjectKind, route.subject) {
        case (.none, .none):
            break
        case (.none, .some):
            throw ScopedRouteContractFailure.unexpectedRouteSubject(route.kindId)
        case (.some, .none):
            throw ScopedRouteContractFailure.missingRouteSubject(route.kindId)
        case (.some(let requiredKind), .some(let subject)):
            guard subject.kind == requiredKind else {
                throw ScopedRouteContractFailure.routeSubjectKindMismatch(route.kindId)
            }
        }

        switch (definition.parentPolicy, route.parent) {
        case (.forbidden, .none):
            break
        case (.forbidden, .some):
            throw ScopedRouteContractFailure.unexpectedRouteParent(route.kindId)
        case (.required, .none):
            throw ScopedRouteContractFailure.missingRouteParent(route.kindId)
        case (.optional, .none):
            break
        case (.optional(let allowed), .some(let parent)),
             (.required(let allowed), .some(let parent)):
            guard allowed.contains(parent.kind) else {
                throw ScopedRouteContractFailure.routeParentKindMismatch(route.kindId)
            }
        }
    }
}

public struct RouteRestorationKey: Codable, Equatable, Hashable, Sendable {
    public let sha256: String

    public init(validating sha256: String) throws {
        let hexadecimal = CharacterSet(charactersIn: "0123456789abcdef")
        guard sha256.utf8.count == 64,
              sha256.unicodeScalars.allSatisfy(hexadecimal.contains) else {
            throw ScopedRouteContractFailure.invalidRestorationKey
        }
        self.sha256 = sha256
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(validating: container.decode(String.self))
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid route restoration key"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(sha256)
    }
}

public struct RouteRestorationRecord: Codable, Equatable, Sendable {
    public let contractVersion: RouteContractVersion
    public let scope: WorkspaceRouteScope
    public let route: ScopedRoute

    public init(
        contractVersion: RouteContractVersion,
        scope: WorkspaceRouteScope,
        route: ScopedRoute
    ) {
        self.contractVersion = contractVersion
        self.scope = scope
        self.route = route
    }

    @discardableResult
    public func validate(
        activeScope: WorkspaceRouteScope,
        supportedContractVersion: RouteContractVersion,
        registry: RouteRegistry
    ) throws -> RouteRestorationKey {
        guard scope == activeScope else {
            throw ScopedRouteContractFailure.workspaceScopeMismatch
        }
        guard contractVersion == supportedContractVersion else {
            throw ScopedRouteContractFailure.restorationContractMismatch
        }
        try registry.validate(route)
        return try restorationKey()
    }

    public func restorationKey() throws -> RouteRestorationKey {
        let bytes = try OperationContractCodec.encode(self)
        let digest = SHA256.hash(data: bytes)
            .map { String(format: "%02x", $0) }
            .joined()
        return try RouteRestorationKey(validating: digest)
    }
}

public struct RouteResolutionRequest: Equatable, Sendable {
    public let scope: WorkspaceRouteScope
    public let workspaceActivationId: WorkspaceActivationID
    public let requestId: RouteResolutionRequestID
    public let route: ScopedRoute

    public init(
        scope: WorkspaceRouteScope,
        workspaceActivationId: WorkspaceActivationID,
        requestId: RouteResolutionRequestID,
        route: ScopedRoute,
        registry: RouteRegistry
    ) throws {
        try registry.validate(route)
        self.scope = scope
        self.workspaceActivationId = workspaceActivationId
        self.requestId = requestId
        self.route = route
    }

}

public struct RouteLocalSnapshot<Destination: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public let destination: Destination
    public let localDataVersion: LocalDataVersion
    public let asOf: Date

    public init(
        destination: Destination,
        localDataVersion: LocalDataVersion,
        asOf: Date
    ) {
        self.destination = destination
        self.localDataVersion = localDataVersion
        self.asOf = asOf
    }
}

public enum RouteResolutionReadiness: String, Codable, CaseIterable, Sendable {
    case loading
    case ready
    case notSynced
    case stale
    case unavailable
    case blocked
}

public enum RouteResolutionFailureState: String, Codable, CaseIterable, Sendable {
    case retryable
    case requiredUpdate
}

enum RouteResolutionFailureCause: String, Codable, CaseIterable, Sendable {
    case notFound
    case notAuthorized
    case notAuthenticated
    case membershipRevoked
    case transientInfrastructure
    case requiredUpdate
    case unsupportedContract

    fileprivate var presentation: RouteResolutionUpdateKind {
        switch self {
        case .notFound, .notAuthorized, .notAuthenticated, .membershipRevoked:
            .unavailable
        case .transientInfrastructure:
            .retryable
        case .requiredUpdate, .unsupportedContract:
            .requiredUpdate
        }
    }
}

private enum RouteResolutionUpdateKind: String, Codable, Sendable {
    case loading
    case ready
    case notSynced
    case unavailable
    case retryable
    case requiredUpdate
}

public struct RouteResolutionUpdate<Destination: Codable & Equatable & Sendable>: Equatable, Sendable {
    public let request: RouteResolutionRequest
    fileprivate let kind: RouteResolutionUpdateKind
    fileprivate let cached: RouteLocalSnapshot<Destination>?

    public static func loading(request: RouteResolutionRequest) -> Self {
        Self(request: request, kind: .loading, cached: nil)
    }

    public static func ready(
        request: RouteResolutionRequest,
        snapshot: RouteLocalSnapshot<Destination>
    ) -> Self {
        Self(request: request, kind: .ready, cached: snapshot)
    }

    public static func notSynced(
        request: RouteResolutionRequest,
        cached: RouteLocalSnapshot<Destination>? = nil
    ) -> Self {
        Self(request: request, kind: .notSynced, cached: cached)
    }

    public static func unavailable(request: RouteResolutionRequest) -> Self {
        Self(request: request, kind: .unavailable, cached: nil)
    }

    public static func retryableFailure(
        request: RouteResolutionRequest,
        cached: RouteLocalSnapshot<Destination>? = nil
    ) -> Self {
        Self(request: request, kind: .retryable, cached: cached)
    }

    public static func requiredUpdate(request: RouteResolutionRequest) -> Self {
        Self(request: request, kind: .requiredUpdate, cached: nil)
    }

    static func failed(
        request: RouteResolutionRequest,
        cause: RouteResolutionFailureCause,
        cached: RouteLocalSnapshot<Destination>? = nil
    ) -> Self {
        let safeCached = cause.presentation == .retryable ? cached : nil
        return Self(request: request, kind: cause.presentation, cached: safeCached)
    }
}

public struct RetryRouteResolutionIntent: Equatable, Sendable {
    public let request: RouteResolutionRequest

    public init(request: RouteResolutionRequest) {
        self.request = request
    }
}

public struct RouteResolutionState<Destination: Codable & Equatable & Sendable>: Equatable, Sendable {
    public let request: RouteResolutionRequest
    public let readiness: RouteResolutionReadiness
    public let destination: Destination?
    public let failure: RouteResolutionFailureState?
    public let localDataVersion: LocalDataVersion?
    public let asOf: Date?

    public var retryIntent: RetryRouteResolutionIntent? {
        guard failure == .retryable else { return nil }
        return RetryRouteResolutionIntent(request: request)
    }

    fileprivate init(
        request: RouteResolutionRequest,
        readiness: RouteResolutionReadiness,
        snapshot: RouteLocalSnapshot<Destination>? = nil,
        failure: RouteResolutionFailureState? = nil
    ) {
        self.request = request
        self.readiness = readiness
        destination = snapshot?.destination
        self.failure = failure
        localDataVersion = snapshot?.localDataVersion
        asOf = snapshot?.asOf
    }
}

public struct RouteResolutionReducer<Destination: Codable & Equatable & Sendable>: Sendable {
    public private(set) var state: RouteResolutionState<Destination>

    public init(request: RouteResolutionRequest) {
        state = RouteResolutionState(request: request, readiness: .loading)
    }

    @discardableResult
    public mutating func apply(
        _ update: RouteResolutionUpdate<Destination>
    ) throws -> RouteResolutionState<Destination> {
        try Self.validate(update.request, matches: state.request)
        let next: RouteResolutionState<Destination>
        switch update.kind {
        case .loading:
            next = RouteResolutionState(request: state.request, readiness: .loading)
        case .ready:
            guard let snapshot = update.cached else {
                throw ScopedRouteContractFailure.routeRequestMismatch
            }
            next = RouteResolutionState(
                request: state.request,
                readiness: .ready,
                snapshot: snapshot
            )
        case .notSynced:
            next = RouteResolutionState(
                request: state.request,
                readiness: .notSynced,
                snapshot: update.cached
            )
        case .unavailable:
            next = RouteResolutionState(request: state.request, readiness: .unavailable)
        case .retryable:
            next = RouteResolutionState(
                request: state.request,
                readiness: update.cached == nil ? .blocked : .stale,
                snapshot: update.cached,
                failure: .retryable
            )
        case .requiredUpdate:
            next = RouteResolutionState(
                request: state.request,
                readiness: .blocked,
                failure: .requiredUpdate
            )
        }
        state = next
        return next
    }

    private static func validate(
        _ update: RouteResolutionRequest,
        matches active: RouteResolutionRequest
    ) throws {
        guard update.scope == active.scope else {
            throw ScopedRouteContractFailure.workspaceScopeMismatch
        }
        guard update.workspaceActivationId == active.workspaceActivationId else {
            throw ScopedRouteContractFailure.workspaceActivationMismatch
        }
        guard update.requestId == active.requestId else {
            throw ScopedRouteContractFailure.routeRequestMismatch
        }
        guard update.route == active.route else {
            throw ScopedRouteContractFailure.routeMismatch
        }
    }
}
