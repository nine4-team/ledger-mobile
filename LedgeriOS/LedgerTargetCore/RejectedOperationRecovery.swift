import Foundation

public enum RejectedOperationRecoveryFailure: Error, Equatable, Sendable {
    case invalidRequest
    case invalidCandidate
    case duplicateCandidate
    case localEvidenceMalformed
}

public enum RejectedOperationFamily: String, Codable, CaseIterable, Sendable {
    case reviseSpaceChecklists = "revise_space_checklists"
}

public struct RejectedOperationRecoveryRequest: Equatable, Sendable {
    public let accountId: AccountID
    public let actorPrincipalId: PrincipalID
    public let family: RejectedOperationFamily
    public let expectedContractVersion: OperationContractVersion
    public let subject: LedgerEntityReference

    public init(
        accountId: AccountID,
        actorPrincipalId: PrincipalID,
        family: RejectedOperationFamily,
        expectedContractVersion: OperationContractVersion,
        subject: LedgerEntityReference
    ) throws {
        guard family != .reviseSpaceChecklists || subject.kind == .space else {
            throw RejectedOperationRecoveryFailure.invalidRequest
        }
        self.accountId = accountId
        self.actorPrincipalId = actorPrincipalId
        self.family = family
        self.expectedContractVersion = expectedContractVersion
        self.subject = subject
    }
}

public enum RejectedOperationCommand: Equatable, Sendable {
    case reviseSpaceChecklists(ReviseSpaceChecklistsCommand)

    public var family: RejectedOperationFamily {
        switch self {
        case .reviseSpaceChecklists: .reviseSpaceChecklists
        }
    }

    public var operationId: OperationID {
        switch self {
        case .reviseSpaceChecklists(let command): command.envelope.operationId
        }
    }

    public var accountId: AccountID {
        switch self {
        case .reviseSpaceChecklists(let command): command.envelope.accountId
        }
    }

    public var actorPrincipalId: PrincipalID {
        switch self {
        case .reviseSpaceChecklists(let command): command.envelope.actorPrincipalId
        }
    }

    public var contractVersion: OperationContractVersion {
        switch self {
        case .reviseSpaceChecklists(let command): command.envelope.contractVersion
        }
    }

    public var fingerprint: OperationFingerprint {
        switch self {
        case .reviseSpaceChecklists(let command): command.fingerprint
        }
    }

    public var subject: LedgerEntityReference {
        switch self {
        case .reviseSpaceChecklists(let command): command.subject
        }
    }
}

public struct RejectedOperationRecoveryCandidate: Equatable, Sendable {
    public let command: RejectedOperationCommand
    public let acceptedAt: Date
    public let updatedAt: Date
    public let rejection: OperationRejection

    public var operationId: OperationID { command.operationId }

    public init(
        command: RejectedOperationCommand,
        acceptedAt: Date,
        updatedAt: Date,
        rejection: OperationRejection
    ) throws {
        guard acceptedAt.timeIntervalSinceReferenceDate.isFinite,
              updatedAt.timeIntervalSinceReferenceDate.isFinite,
              rejection.rejectedAt.timeIntervalSinceReferenceDate.isFinite,
              updatedAt >= acceptedAt,
              rejection.rejectedAt >= acceptedAt,
              rejection.rejectedAt <= updatedAt else {
            throw RejectedOperationRecoveryFailure.invalidCandidate
        }
        self.command = command
        self.acceptedAt = acceptedAt
        self.updatedAt = updatedAt
        self.rejection = rejection
    }

    public func validating(
        request: RejectedOperationRecoveryRequest
    ) throws -> Self {
        guard command.accountId == request.accountId,
              command.actorPrincipalId == request.actorPrincipalId,
              command.family == request.family,
              command.contractVersion == request.expectedContractVersion,
              command.subject == request.subject else {
            throw RejectedOperationRecoveryFailure.invalidCandidate
        }
        return self
    }
}

public struct RejectedOperationRecoverySnapshot: Equatable, Sendable {
    public let request: RejectedOperationRecoveryRequest
    public let candidates: [RejectedOperationRecoveryCandidate]

    public init(
        request: RejectedOperationRecoveryRequest,
        candidates: [RejectedOperationRecoveryCandidate]
    ) throws {
        guard Set(candidates.map(\.operationId)).count == candidates.count else {
            throw RejectedOperationRecoveryFailure.duplicateCandidate
        }
        let validated = try candidates.map { try $0.validating(request: request) }
        self.request = request
        self.candidates = validated.sorted(by: Self.isOrderedBefore)
    }

    private static func isOrderedBefore(
        _ lhs: RejectedOperationRecoveryCandidate,
        _ rhs: RejectedOperationRecoveryCandidate
    ) -> Bool {
        if lhs.rejection.rejectedAt != rhs.rejection.rejectedAt {
            return lhs.rejection.rejectedAt > rhs.rejection.rejectedAt
        }
        if lhs.acceptedAt != rhs.acceptedAt {
            return lhs.acceptedAt > rhs.acceptedAt
        }
        return lhs.operationId.rawValue < rhs.operationId.rawValue
    }
}

public protocol RejectedOperationRecoveryQuerying: Sendable {
    func rejectedOperations(
        _ request: RejectedOperationRecoveryRequest
    ) async throws -> RejectedOperationRecoverySnapshot

    func watchRejectedOperations(
        _ request: RejectedOperationRecoveryRequest
    ) -> AsyncThrowingStream<RejectedOperationRecoverySnapshot, Error>
}
