import Foundation

public enum ProjectSetupFailure: Error, Equatable, Sendable {
    case invalidClientSelection
    case negativeCategoryAllocation
    case duplicateCategoryIdentity
    case invalidProjectCreatedAt
    case draftAccountMismatch
    case draftActorMismatch
    case draftContractMismatch
    case draftPayloadMismatch
    case unexpectedPreconditions
    case subjectMismatch
    case fingerprintMismatch
    case receiptMismatch
    case localAcceptanceFailed
    case invalidEncodedCategoryAllocation
    case invalidEncodedDraft
    case invalidEncodedCommand

    public var diagnosticCode: String {
        switch self {
        case .invalidClientSelection:
            "project_setup_client_selection_invalid"
        case .negativeCategoryAllocation:
            "project_setup_category_allocation_negative"
        case .duplicateCategoryIdentity:
            "project_setup_category_identity_duplicate"
        case .invalidProjectCreatedAt:
            "project_setup_created_at_invalid"
        case .draftAccountMismatch:
            "project_setup_account_mismatch"
        case .draftActorMismatch:
            "project_setup_actor_mismatch"
        case .draftContractMismatch:
            "project_setup_contract_mismatch"
        case .draftPayloadMismatch:
            "project_setup_payload_mismatch"
        case .unexpectedPreconditions:
            "project_setup_preconditions_unexpected"
        case .subjectMismatch:
            "project_setup_subject_mismatch"
        case .fingerprintMismatch:
            "project_setup_fingerprint_mismatch"
        case .receiptMismatch:
            "project_setup_receipt_mismatch"
        case .localAcceptanceFailed:
            "project_setup_local_acceptance_failed"
        case .invalidEncodedCategoryAllocation:
            "project_setup_category_allocation_encoding_invalid"
        case .invalidEncodedDraft:
            "project_setup_draft_encoding_invalid"
        case .invalidEncodedCommand:
            "project_setup_command_encoding_invalid"
        }
    }
}

public enum BudgetCategoryIDTag: Sendable {}
public typealias BudgetCategoryID = DomainEntityIdentifier<BudgetCategoryIDTag>

public enum ProjectClientSelectionInput: Codable, Equatable, Sendable {
    case existing(ClientID)
    case newClient(CreateClientPayload)

    public var clientId: ClientID {
        switch self {
        case .existing(let clientId):
            clientId
        case .newClient(let payload):
            payload.clientId
        }
    }

    public var newClientDisplayName: ClientDisplayName? {
        switch self {
        case .existing:
            nil
        case .newClient(let payload):
            payload.displayName
        }
    }

    public init(existing clientId: ClientID) {
        self = .existing(clientId)
    }

    public init(newClientId: ClientID, displayName: ClientDisplayName) {
        self = .newClient(CreateClientPayload(
            clientId: newClientId,
            displayName: displayName
        ))
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try container.decode(SelectionKind.self, forKey: .kind)
            let clientId = try container.decode(ClientID.self, forKey: .clientId)
            switch kind {
            case .existing:
                guard !container.contains(.displayName) else {
                    throw ProjectSetupFailure.invalidClientSelection
                }
                self = .existing(clientId)
            case .new:
                guard container.contains(.displayName) else {
                    throw ProjectSetupFailure.invalidClientSelection
                }
                self = .newClient(CreateClientPayload(
                    clientId: clientId,
                    displayName: try container.decode(
                        ClientDisplayName.self,
                        forKey: .displayName
                    )
                ))
            }
        } catch let failure as ProjectSetupFailure {
            throw failure
        } catch {
            throw ProjectSetupFailure.invalidClientSelection
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .existing(let clientId):
            try container.encode(SelectionKind.existing, forKey: .kind)
            try container.encode(clientId, forKey: .clientId)
        case .newClient(let payload):
            try container.encode(SelectionKind.new, forKey: .kind)
            try container.encode(payload.clientId, forKey: .clientId)
            try container.encode(payload.displayName, forKey: .displayName)
        }
    }

    private enum SelectionKind: String, Codable {
        case existing
        case new
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case clientId
        case displayName
    }
}

public struct NullableCategoryAllocation: Codable, Equatable, Sendable {
    public let categoryId: BudgetCategoryID
    public let allocation: Money?

    public init(categoryId: BudgetCategoryID, allocation: Money?) throws {
        guard allocation?.minorUnits ?? 0 >= 0 else {
            throw ProjectSetupFailure.negativeCategoryAllocation
        }
        self.categoryId = categoryId
        self.allocation = allocation
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                categoryId: container.decode(BudgetCategoryID.self, forKey: .categoryId),
                allocation: container.decodeIfPresent(Money.self, forKey: .allocation)
            )
        } catch let failure as ProjectSetupFailure {
            throw failure
        } catch {
            throw ProjectSetupFailure.invalidEncodedCategoryAllocation
        }
    }

    private enum CodingKeys: String, CodingKey {
        case categoryId
        case allocation
    }
}

public struct ProjectSetupDraft: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let actorPrincipalId: PrincipalID
    public let operationContractVersion: OperationContractVersion
    public let projectId: ProjectID
    public let clientSelection: ProjectClientSelectionInput
    public let displayName: ProjectDisplayName
    public let description: String?
    public let categoryAllocations: [NullableCategoryAllocation]
    public let capturedAt: Date

    public init(
        accountId: AccountID,
        actorPrincipalId: PrincipalID,
        operationContractVersion: OperationContractVersion,
        projectId: ProjectID,
        clientSelection: ProjectClientSelectionInput,
        displayName: ProjectDisplayName,
        description: String?,
        categoryAllocations: [NullableCategoryAllocation],
        capturedAt: Date
    ) throws {
        guard capturedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw ProjectSetupFailure.invalidProjectCreatedAt
        }
        self.accountId = accountId
        self.actorPrincipalId = actorPrincipalId
        self.operationContractVersion = operationContractVersion
        self.projectId = projectId
        self.clientSelection = clientSelection
        self.displayName = displayName
        self.description = description
        self.categoryAllocations = try Self.canonicalize(categoryAllocations)
        self.capturedAt = capturedAt
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                accountId: container.decode(AccountID.self, forKey: .accountId),
                actorPrincipalId: container.decode(
                    PrincipalID.self,
                    forKey: .actorPrincipalId
                ),
                operationContractVersion: container.decode(
                    OperationContractVersion.self,
                    forKey: .operationContractVersion
                ),
                projectId: container.decode(ProjectID.self, forKey: .projectId),
                clientSelection: container.decode(
                    ProjectClientSelectionInput.self,
                    forKey: .clientSelection
                ),
                displayName: container.decode(ProjectDisplayName.self, forKey: .displayName),
                description: container.decodeIfPresent(String.self, forKey: .description),
                categoryAllocations: container.decode(
                    [NullableCategoryAllocation].self,
                    forKey: .categoryAllocations
                ),
                capturedAt: container.decode(Date.self, forKey: .capturedAt)
            )
        } catch let failure as ProjectSetupFailure {
            throw failure
        } catch {
            throw ProjectSetupFailure.invalidEncodedDraft
        }
    }

    private static func canonicalize(
        _ allocations: [NullableCategoryAllocation]
    ) throws -> [NullableCategoryAllocation] {
        var identities: Set<BudgetCategoryID> = []
        for allocation in allocations {
            guard identities.insert(allocation.categoryId).inserted else {
                throw ProjectSetupFailure.duplicateCategoryIdentity
            }
        }
        return allocations.sorted {
            $0.categoryId.rawValue < $1.categoryId.rawValue
        }
    }

    private enum CodingKeys: String, CodingKey {
        case accountId
        case actorPrincipalId
        case operationContractVersion
        case projectId
        case clientSelection
        case displayName
        case description
        case categoryAllocations
        case capturedAt
    }
}

public struct CreateProjectPayload: Codable, Equatable, Sendable {
    public let projectId: ProjectID
    public let clientSelection: ProjectClientSelectionInput
    public let displayName: ProjectDisplayName
    public let description: String?
    public let categoryAllocations: [NullableCategoryAllocation]

    public init(
        projectId: ProjectID,
        clientSelection: ProjectClientSelectionInput,
        displayName: ProjectDisplayName,
        description: String?,
        categoryAllocations: [NullableCategoryAllocation]
    ) {
        self.projectId = projectId
        self.clientSelection = clientSelection
        self.displayName = displayName
        self.description = description
        self.categoryAllocations = categoryAllocations
    }
}

public struct CreateProjectCommand: Codable, Equatable, Sendable {
    public let draft: ProjectSetupDraft
    public let envelope: OperationEnvelope<CreateProjectPayload>
    public let subject: LedgerEntityReference
    public let fingerprint: OperationFingerprint

    public init(operationId: OperationID, draft: ProjectSetupDraft) throws {
        let payload = Self.makePayload(from: draft)
        let envelope = OperationEnvelope(
            operationId: operationId,
            contractVersion: draft.operationContractVersion,
            accountId: draft.accountId,
            actorPrincipalId: draft.actorPrincipalId,
            clientCreatedAt: draft.capturedAt,
            payload: payload
        )
        let subject = try Self.makeSubject(projectId: draft.projectId)
        let fingerprint = try OperationFingerprint.make(for: envelope)
        try self.init(
            draft: draft,
            envelope: envelope,
            subject: subject,
            fingerprint: fingerprint
        )
    }

    private init(
        draft: ProjectSetupDraft,
        envelope: OperationEnvelope<CreateProjectPayload>,
        subject: LedgerEntityReference,
        fingerprint: OperationFingerprint
    ) throws {
        guard envelope.clientCreatedAt.timeIntervalSinceReferenceDate.isFinite,
              envelope.clientCreatedAt == draft.capturedAt else {
            throw ProjectSetupFailure.invalidProjectCreatedAt
        }
        guard envelope.accountId == draft.accountId else {
            throw ProjectSetupFailure.draftAccountMismatch
        }
        guard envelope.actorPrincipalId == draft.actorPrincipalId else {
            throw ProjectSetupFailure.draftActorMismatch
        }
        guard envelope.contractVersion == draft.operationContractVersion else {
            throw ProjectSetupFailure.draftContractMismatch
        }
        guard envelope.payload == Self.makePayload(from: draft) else {
            throw ProjectSetupFailure.draftPayloadMismatch
        }
        guard envelope.preconditions.isEmpty else {
            throw ProjectSetupFailure.unexpectedPreconditions
        }
        guard subject == (try Self.makeSubject(projectId: draft.projectId)) else {
            throw ProjectSetupFailure.subjectMismatch
        }
        guard fingerprint == (try OperationFingerprint.make(for: envelope)) else {
            throw ProjectSetupFailure.fingerprintMismatch
        }

        self.draft = draft
        self.envelope = envelope
        self.subject = subject
        self.fingerprint = fingerprint
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                draft: container.decode(ProjectSetupDraft.self, forKey: .draft),
                envelope: container.decode(
                    OperationEnvelope<CreateProjectPayload>.self,
                    forKey: .envelope
                ),
                subject: container.decode(LedgerEntityReference.self, forKey: .subject),
                fingerprint: container.decode(OperationFingerprint.self, forKey: .fingerprint)
            )
        } catch let failure as ProjectSetupFailure {
            throw failure
        } catch {
            throw ProjectSetupFailure.invalidEncodedCommand
        }
    }

    public func validate(_ receipt: OperationReceipt) throws -> OperationReceipt {
        guard receipt.operationId == envelope.operationId else {
            throw ProjectSetupFailure.receiptMismatch
        }
        return receipt
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.draft == rhs.draft &&
            lhs.envelope.operationId == rhs.envelope.operationId &&
            lhs.envelope.contractVersion == rhs.envelope.contractVersion &&
            lhs.envelope.accountId == rhs.envelope.accountId &&
            lhs.envelope.actorPrincipalId == rhs.envelope.actorPrincipalId &&
            lhs.envelope.clientCreatedAt == rhs.envelope.clientCreatedAt &&
            lhs.envelope.payload == rhs.envelope.payload &&
            lhs.envelope.preconditions == rhs.envelope.preconditions &&
            lhs.subject == rhs.subject &&
            lhs.fingerprint == rhs.fingerprint
    }

    private static func makePayload(from draft: ProjectSetupDraft) -> CreateProjectPayload {
        CreateProjectPayload(
            projectId: draft.projectId,
            clientSelection: draft.clientSelection,
            displayName: draft.displayName,
            description: draft.description,
            categoryAllocations: draft.categoryAllocations
        )
    }

    private static func makeSubject(projectId: ProjectID) throws -> LedgerEntityReference {
        do {
            return LedgerEntityReference(
                kind: .project,
                id: try EntityID(validating: projectId.rawValue)
            )
        } catch {
            throw ProjectSetupFailure.subjectMismatch
        }
    }

    private enum CodingKeys: String, CodingKey {
        case draft
        case envelope
        case subject
        case fingerprint
    }
}

public protocol ProjectSetupOperating: Sendable {
    func create(_ command: CreateProjectCommand) async throws -> OperationReceipt
}
