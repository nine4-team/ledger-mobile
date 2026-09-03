import CryptoKit
import Foundation

public enum ProjectSetupFormFailure: Error, Equatable, Sendable {
    case accountScopeMismatch
    case clientNotSelectable
    case newClientIdentityCollision
    case categoryNotSelectable
    case duplicateCategoryIdentity
    case invalidPreparationFingerprint
    case invalidSelectionFingerprint
    case preparationFingerprintMismatch
    case selectionFingerprintMismatch
    case selectionPreparationMismatch
    case invalidEncodedPreparation
    case invalidEncodedSelection

    public var diagnosticCode: String {
        switch self {
        case .accountScopeMismatch: "project_setup_form_account_scope_mismatch"
        case .clientNotSelectable: "project_setup_form_client_not_selectable"
        case .newClientIdentityCollision: "project_setup_form_new_client_identity_collision"
        case .categoryNotSelectable: "project_setup_form_category_not_selectable"
        case .duplicateCategoryIdentity: "project_setup_form_category_identity_duplicate"
        case .invalidPreparationFingerprint: "project_setup_form_preparation_fingerprint_invalid"
        case .invalidSelectionFingerprint: "project_setup_form_selection_fingerprint_invalid"
        case .preparationFingerprintMismatch: "project_setup_form_preparation_fingerprint_mismatch"
        case .selectionFingerprintMismatch: "project_setup_form_selection_fingerprint_mismatch"
        case .selectionPreparationMismatch: "project_setup_form_selection_preparation_mismatch"
        case .invalidEncodedPreparation: "project_setup_form_preparation_encoding_invalid"
        case .invalidEncodedSelection: "project_setup_form_selection_encoding_invalid"
        }
    }
}

public struct ProjectSetupFormPreparationFingerprint:
    Codable, Equatable, Hashable, Sendable
{
    public let sha256: String

    public init(validating sha256: String) throws {
        guard ProjectSetupFormDigest.isCanonicalSHA256(sha256) else {
            throw ProjectSetupFormFailure.invalidPreparationFingerprint
        }
        self.sha256 = sha256
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            try self.init(validating: container.decode(String.self))
        } catch let failure as ProjectSetupFormFailure {
            throw failure
        } catch {
            throw ProjectSetupFormFailure.invalidPreparationFingerprint
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(sha256)
    }
}

public struct ProjectSetupFormSelectionFingerprint:
    Codable, Equatable, Hashable, Sendable
{
    public let sha256: String

    public init(validating sha256: String) throws {
        guard ProjectSetupFormDigest.isCanonicalSHA256(sha256) else {
            throw ProjectSetupFormFailure.invalidSelectionFingerprint
        }
        self.sha256 = sha256
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            try self.init(validating: container.decode(String.self))
        } catch let failure as ProjectSetupFormFailure {
            throw failure
        } catch {
            throw ProjectSetupFormFailure.invalidSelectionFingerprint
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(sha256)
    }
}

public struct ProjectSetupFormPreparation: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let clientSelectionSnapshot: ProjectExistingClientSelectionSnapshot
    public let categoryReferenceSnapshot: BudgetCategoryReferenceSnapshot
    public let evidenceFingerprint: ProjectSetupFormPreparationFingerprint

    public var existingClients: [ClientSummary] {
        clientSelectionSnapshot.activeClients
    }

    public var configurableCategories: [BudgetCategoryDefinitionSnapshot] {
        categoryReferenceSnapshot.local.rows.filter(\.isSelectableForProjectConfiguration)
    }

    public var clientReadiness: ListReadiness { clientSelectionSnapshot.readiness }
    public var categoryReadiness: ListReadiness {
        categoryReferenceSnapshot.local.quality.readiness
    }

    public init(
        clientSelectionSnapshot: ProjectExistingClientSelectionSnapshot,
        categoryReferenceSnapshot: BudgetCategoryReferenceSnapshot
    ) throws {
        let fingerprint = try Self.makeEvidenceFingerprint(
            accountId: clientSelectionSnapshot.accountId,
            clientSelectionSnapshot: clientSelectionSnapshot,
            categoryReferenceSnapshot: categoryReferenceSnapshot
        )
        try self.init(
            accountId: clientSelectionSnapshot.accountId,
            clientSelectionSnapshot: clientSelectionSnapshot,
            categoryReferenceSnapshot: categoryReferenceSnapshot,
            evidenceFingerprint: fingerprint
        )
    }

    private init(
        accountId: AccountID,
        clientSelectionSnapshot: ProjectExistingClientSelectionSnapshot,
        categoryReferenceSnapshot: BudgetCategoryReferenceSnapshot,
        evidenceFingerprint: ProjectSetupFormPreparationFingerprint
    ) throws {
        guard clientSelectionSnapshot.accountId == accountId,
              categoryReferenceSnapshot.accountId == accountId else {
            throw ProjectSetupFormFailure.accountScopeMismatch
        }
        let expectedFingerprint = try Self.makeEvidenceFingerprint(
            accountId: accountId,
            clientSelectionSnapshot: clientSelectionSnapshot,
            categoryReferenceSnapshot: categoryReferenceSnapshot
        )
        guard evidenceFingerprint == expectedFingerprint else {
            throw ProjectSetupFormFailure.preparationFingerprintMismatch
        }
        self.accountId = accountId
        self.clientSelectionSnapshot = clientSelectionSnapshot
        self.categoryReferenceSnapshot = categoryReferenceSnapshot
        self.evidenceFingerprint = evidenceFingerprint
    }

    public func selection(
        client: ProjectClientSelectionInput,
        projectDisplayName: ProjectDisplayName,
        rawDescription: String?,
        categoryAllocations: [NullableCategoryAllocation]
    ) throws -> ProjectSetupFormSelection {
        try validate(client: client, categoryAllocations: categoryAllocations)
        return try ProjectSetupFormSelection(
            accountId: accountId,
            clientSelection: client,
            projectDisplayName: projectDisplayName,
            descriptionReplacement: ProjectDescriptionReplacement(rawDescription),
            categoryAllocations: Self.canonicalize(categoryAllocations),
            preparationEvidenceFingerprint: evidenceFingerprint
        )
    }

    fileprivate func validate(
        client: ProjectClientSelectionInput,
        categoryAllocations: [NullableCategoryAllocation]
    ) throws {
        switch client {
        case .existing(let clientId):
            guard existingClients.contains(where: { $0.id == clientId }) else {
                throw ProjectSetupFormFailure.clientNotSelectable
            }
        case .newClient(let payload):
            guard !existingClients.contains(where: { $0.id == payload.clientId }) else {
                throw ProjectSetupFormFailure.newClientIdentityCollision
            }
        }

        let canonicalAllocations = try Self.canonicalize(categoryAllocations)
        let selectableCategoryIds = Set(configurableCategories.map(\.id))
        guard canonicalAllocations.allSatisfy({
            selectableCategoryIds.contains($0.categoryId)
        }) else {
            throw ProjectSetupFormFailure.categoryNotSelectable
        }
    }

    public init(from decoder: Decoder) throws {
        do {
            try ProjectSetupFormCoding.requireExactKeys(
                decoder,
                allowed: CodingKeys.allCases.map(\.rawValue),
                failure: .invalidEncodedPreparation
            )
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                accountId: container.decode(AccountID.self, forKey: .accountId),
                clientSelectionSnapshot: container.decode(
                    ProjectExistingClientSelectionSnapshot.self,
                    forKey: .clientSelectionSnapshot
                ),
                categoryReferenceSnapshot: container.decode(
                    StrictBudgetCategoryReferenceSnapshot.self,
                    forKey: .categoryReferenceSnapshot
                ).value,
                evidenceFingerprint: container.decode(
                    ProjectSetupFormPreparationFingerprint.self,
                    forKey: .evidenceFingerprint
                )
            )
        } catch let failure as ProjectSetupFormFailure {
            throw failure
        } catch {
            throw ProjectSetupFormFailure.invalidEncodedPreparation
        }
    }

    fileprivate static func canonicalize(
        _ allocations: [NullableCategoryAllocation]
    ) throws -> [NullableCategoryAllocation] {
        var categoryIds: Set<BudgetCategoryID> = []
        guard allocations.allSatisfy({ categoryIds.insert($0.categoryId).inserted }) else {
            throw ProjectSetupFormFailure.duplicateCategoryIdentity
        }
        return allocations.sorted { $0.categoryId.rawValue < $1.categoryId.rawValue }
    }

    private static func makeEvidenceFingerprint(
        accountId: AccountID,
        clientSelectionSnapshot: ProjectExistingClientSelectionSnapshot,
        categoryReferenceSnapshot: BudgetCategoryReferenceSnapshot
    ) throws -> ProjectSetupFormPreparationFingerprint {
        do {
            let basis = PreparationFingerprintBasis(
                contractVersion: "project-setup-form-preparation-v1",
                accountId: accountId,
                clientSelectionSnapshot: clientSelectionSnapshot,
                categoryReferenceSnapshot: categoryReferenceSnapshot
            )
            return try ProjectSetupFormPreparationFingerprint(
                validating: ProjectSetupFormDigest.sha256(
                    try OperationContractCodec.encode(basis)
                )
            )
        } catch let failure as ProjectSetupFormFailure {
            throw failure
        } catch {
            throw ProjectSetupFormFailure.invalidEncodedPreparation
        }
    }

    private struct PreparationFingerprintBasis: Codable {
        let contractVersion: String
        let accountId: AccountID
        let clientSelectionSnapshot: ProjectExistingClientSelectionSnapshot
        let categoryReferenceSnapshot: BudgetCategoryReferenceSnapshot
    }

    private struct StrictBudgetCategoryDefinition: Decodable {
        let value: BudgetCategoryDefinitionSnapshot

        init(from decoder: Decoder) throws {
            try ProjectSetupFormCoding.requireExactKeys(
                decoder,
                allowed: CategoryCodingKeys.allCases.map(\.rawValue),
                failure: .invalidEncodedPreparation
            )
            let container = try decoder.container(keyedBy: CategoryCodingKeys.self)
            value = BudgetCategoryDefinitionSnapshot(
                id: try container.decode(BudgetCategoryID.self, forKey: .id),
                accountId: try container.decode(AccountID.self, forKey: .accountId),
                name: try container.decode(BudgetCategoryName.self, forKey: .name),
                kind: try container.decode(BudgetCategoryKind.self, forKey: .kind),
                lifecycle: try container.decode(
                    DirectoryLifecycleState.self,
                    forKey: .lifecycle
                ),
                isSystem: try container.decode(Bool.self, forKey: .isSystem),
                excludesFromOverallBudget: try container.decode(
                    Bool.self,
                    forKey: .excludesFromOverallBudget
                ),
                presentationOrder: try container.decode(
                    UInt32.self,
                    forKey: .presentationOrder
                ),
                revision: try container.decode(UInt64.self, forKey: .revision)
            )
        }
    }

    private struct StrictBudgetCategoryReferenceSnapshot: Decodable {
        let value: BudgetCategoryReferenceSnapshot

        init(from decoder: Decoder) throws {
            try ProjectSetupFormCoding.requireExactKeys(
                decoder,
                allowed: ReferenceCodingKeys.allCases.map(\.rawValue),
                failure: .invalidEncodedPreparation
            )
            let container = try decoder.container(keyedBy: ReferenceCodingKeys.self)
            let accountId = try container.decode(AccountID.self, forKey: .accountId)
            let local = try container.decode(
                StrictCategoryListLocalSnapshot.self,
                forKey: .local
            ).value
            let snapshot = try BudgetCategoryReferenceSnapshot(accountId: accountId, local: local)
            guard snapshot.local == local else {
                throw ProjectSetupFormFailure.invalidEncodedPreparation
            }
            value = snapshot
        }
    }

    private struct StrictCategoryListLocalSnapshot: Decodable {
        let value: ListLocalSnapshot<BudgetCategoryDefinitionSnapshot>

        init(from decoder: Decoder) throws {
            try ProjectSetupFormCoding.requireExactKeys(
                decoder,
                allowed: LocalCodingKeys.allCases.map(\.rawValue),
                failure: .invalidEncodedPreparation
            )
            let container = try decoder.container(keyedBy: LocalCodingKeys.self)
            value = try ListLocalSnapshot(
                queryFingerprint: container.decode(
                    ListQueryFingerprint.self,
                    forKey: .queryFingerprint
                ),
                rows: container.decode(
                    [StrictBudgetCategoryDefinition].self,
                    forKey: .rows
                ).map(\.value),
                visibleRowCountBeforeFiltering: container.decode(
                    Int.self,
                    forKey: .visibleRowCountBeforeFiltering
                ),
                isCompleteForQuery: container.decode(Bool.self, forKey: .isCompleteForQuery),
                quality: container.decode(ListSnapshotQuality.self, forKey: .quality),
                localDataVersion: container.decode(
                    LocalDataVersion.self,
                    forKey: .localDataVersion
                ),
                asOf: container.decode(Date.self, forKey: .asOf)
            )
        }
    }

    private enum CategoryCodingKeys: String, CodingKey, CaseIterable {
        case id
        case accountId
        case name
        case kind
        case lifecycle
        case isSystem
        case excludesFromOverallBudget
        case presentationOrder
        case revision
    }

    private enum ReferenceCodingKeys: String, CodingKey, CaseIterable {
        case accountId
        case local
    }

    private enum LocalCodingKeys: String, CodingKey, CaseIterable {
        case queryFingerprint
        case rows
        case visibleRowCountBeforeFiltering
        case isCompleteForQuery
        case quality
        case localDataVersion
        case asOf
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case accountId
        case clientSelectionSnapshot
        case categoryReferenceSnapshot
        case evidenceFingerprint
    }
}

public struct ProjectSetupFormSelection: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let clientSelection: ProjectClientSelectionInput
    public let projectDisplayName: ProjectDisplayName
    public let descriptionReplacement: ProjectDescriptionReplacement
    public let categoryAllocations: [NullableCategoryAllocation]
    public let preparationEvidenceFingerprint: ProjectSetupFormPreparationFingerprint
    public let selectionFingerprint: ProjectSetupFormSelectionFingerprint

    fileprivate init(
        accountId: AccountID,
        clientSelection: ProjectClientSelectionInput,
        projectDisplayName: ProjectDisplayName,
        descriptionReplacement: ProjectDescriptionReplacement,
        categoryAllocations: [NullableCategoryAllocation],
        preparationEvidenceFingerprint: ProjectSetupFormPreparationFingerprint
    ) throws {
        let canonicalAllocations = try ProjectSetupFormPreparation.canonicalize(
            categoryAllocations
        )
        let selectionFingerprint = try Self.makeSelectionFingerprint(
            accountId: accountId,
            clientSelection: clientSelection,
            projectDisplayName: projectDisplayName,
            descriptionReplacement: descriptionReplacement,
            categoryAllocations: canonicalAllocations,
            preparationEvidenceFingerprint: preparationEvidenceFingerprint
        )
        self.accountId = accountId
        self.clientSelection = clientSelection
        self.projectDisplayName = projectDisplayName
        self.descriptionReplacement = descriptionReplacement
        self.categoryAllocations = canonicalAllocations
        self.preparationEvidenceFingerprint = preparationEvidenceFingerprint
        self.selectionFingerprint = selectionFingerprint
    }

    private init(
        accountId: AccountID,
        clientSelection: ProjectClientSelectionInput,
        projectDisplayName: ProjectDisplayName,
        descriptionReplacement: ProjectDescriptionReplacement,
        categoryAllocations: [NullableCategoryAllocation],
        preparationEvidenceFingerprint: ProjectSetupFormPreparationFingerprint,
        selectionFingerprint: ProjectSetupFormSelectionFingerprint
    ) throws {
        let canonicalAllocations = try ProjectSetupFormPreparation.canonicalize(
            categoryAllocations
        )
        guard categoryAllocations == canonicalAllocations else {
            throw ProjectSetupFormFailure.selectionFingerprintMismatch
        }
        let expectedFingerprint = try Self.makeSelectionFingerprint(
            accountId: accountId,
            clientSelection: clientSelection,
            projectDisplayName: projectDisplayName,
            descriptionReplacement: descriptionReplacement,
            categoryAllocations: canonicalAllocations,
            preparationEvidenceFingerprint: preparationEvidenceFingerprint
        )
        guard selectionFingerprint == expectedFingerprint else {
            throw ProjectSetupFormFailure.selectionFingerprintMismatch
        }
        self.accountId = accountId
        self.clientSelection = clientSelection
        self.projectDisplayName = projectDisplayName
        self.descriptionReplacement = descriptionReplacement
        self.categoryAllocations = canonicalAllocations
        self.preparationEvidenceFingerprint = preparationEvidenceFingerprint
        self.selectionFingerprint = selectionFingerprint
    }

    public func command(
        validating currentPreparation: ProjectSetupFormPreparation,
        projectId: ProjectID,
        operationId: OperationID,
        actorPrincipalId: PrincipalID,
        operationContractVersion: OperationContractVersion,
        capturedAt: Date
    ) throws -> CreateProjectCommand {
        guard accountId == currentPreparation.accountId,
              preparationEvidenceFingerprint == currentPreparation.evidenceFingerprint else {
            throw ProjectSetupFormFailure.selectionPreparationMismatch
        }
        let expectedFingerprint = try Self.makeSelectionFingerprint(
            accountId: accountId,
            clientSelection: clientSelection,
            projectDisplayName: projectDisplayName,
            descriptionReplacement: descriptionReplacement,
            categoryAllocations: categoryAllocations,
            preparationEvidenceFingerprint: preparationEvidenceFingerprint
        )
        guard selectionFingerprint == expectedFingerprint else {
            throw ProjectSetupFormFailure.selectionFingerprintMismatch
        }
        try currentPreparation.validate(
            client: clientSelection,
            categoryAllocations: categoryAllocations
        )
        let draft = try ProjectSetupDraft(
            accountId: accountId,
            actorPrincipalId: actorPrincipalId,
            operationContractVersion: operationContractVersion,
            projectId: projectId,
            clientSelection: clientSelection,
            displayName: projectDisplayName,
            description: descriptionReplacement.value,
            categoryAllocations: categoryAllocations,
            capturedAt: capturedAt
        )
        return try CreateProjectCommand(operationId: operationId, draft: draft)
    }

    public init(from decoder: Decoder) throws {
        do {
            try ProjectSetupFormCoding.requireExactKeys(
                decoder,
                allowed: CodingKeys.allCases.map(\.rawValue),
                failure: .invalidEncodedSelection
            )
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                accountId: container.decode(AccountID.self, forKey: .accountId),
                clientSelection: container.decode(
                    StrictClientSelection.self,
                    forKey: .clientSelection
                ).value,
                projectDisplayName: container.decode(
                    ProjectDisplayName.self,
                    forKey: .projectDisplayName
                ),
                descriptionReplacement: container.decode(
                    StrictDescriptionReplacement.self,
                    forKey: .descriptionReplacement
                ).value,
                categoryAllocations: container.decode(
                    [StrictCategoryAllocation].self,
                    forKey: .categoryAllocations
                ).map(\.value),
                preparationEvidenceFingerprint: container.decode(
                    ProjectSetupFormPreparationFingerprint.self,
                    forKey: .preparationEvidenceFingerprint
                ),
                selectionFingerprint: container.decode(
                    ProjectSetupFormSelectionFingerprint.self,
                    forKey: .selectionFingerprint
                )
            )
        } catch let failure as ProjectSetupFormFailure {
            throw failure
        } catch {
            throw ProjectSetupFormFailure.invalidEncodedSelection
        }
    }

    private static func makeSelectionFingerprint(
        accountId: AccountID,
        clientSelection: ProjectClientSelectionInput,
        projectDisplayName: ProjectDisplayName,
        descriptionReplacement: ProjectDescriptionReplacement,
        categoryAllocations: [NullableCategoryAllocation],
        preparationEvidenceFingerprint: ProjectSetupFormPreparationFingerprint
    ) throws -> ProjectSetupFormSelectionFingerprint {
        do {
            let basis = SelectionFingerprintBasis(
                contractVersion: "project-setup-form-selection-v1",
                accountId: accountId,
                clientSelection: clientSelection,
                projectDisplayName: projectDisplayName,
                descriptionReplacement: descriptionReplacement,
                categoryAllocations: categoryAllocations,
                preparationEvidenceFingerprint: preparationEvidenceFingerprint
            )
            return try ProjectSetupFormSelectionFingerprint(
                validating: ProjectSetupFormDigest.sha256(
                    try OperationContractCodec.encode(basis)
                )
            )
        } catch let failure as ProjectSetupFormFailure {
            throw failure
        } catch {
            throw ProjectSetupFormFailure.invalidEncodedSelection
        }
    }

    private struct SelectionFingerprintBasis: Codable {
        let contractVersion: String
        let accountId: AccountID
        let clientSelection: ProjectClientSelectionInput
        let projectDisplayName: ProjectDisplayName
        let descriptionReplacement: ProjectDescriptionReplacement
        let categoryAllocations: [NullableCategoryAllocation]
        let preparationEvidenceFingerprint: ProjectSetupFormPreparationFingerprint
    }

    private struct StrictClientSelection: Decodable {
        let value: ProjectClientSelectionInput

        init(from decoder: Decoder) throws {
            let unbounded = try decoder.container(keyedBy: ProjectSetupFormCoding.AnyCodingKey.self)
            let keys = Set(unbounded.allKeys.map(\.stringValue))
            let container = try decoder.container(keyedBy: ClientSelectionCodingKeys.self)
            let kind = try container.decode(String.self, forKey: .kind)
            let clientId = try container.decode(ClientID.self, forKey: .clientId)
            switch kind {
            case "existing":
                guard keys == ["kind", "clientId"] else {
                    throw ProjectSetupFormFailure.invalidEncodedSelection
                }
                value = .existing(clientId)
            case "new":
                guard keys == ["kind", "clientId", "displayName"] else {
                    throw ProjectSetupFormFailure.invalidEncodedSelection
                }
                value = ProjectClientSelectionInput(
                    newClientId: clientId,
                    displayName: try container.decode(
                        ClientDisplayName.self,
                        forKey: .displayName
                    )
                )
            default:
                throw ProjectSetupFormFailure.invalidEncodedSelection
            }
        }
    }

    private struct StrictDescriptionReplacement: Decodable {
        let value: ProjectDescriptionReplacement

        init(from decoder: Decoder) throws {
            try ProjectSetupFormCoding.requireExactKeys(
                decoder,
                allowed: ["value"],
                failure: .invalidEncodedSelection
            )
            let container = try decoder.container(keyedBy: DescriptionCodingKeys.self)
            let rawValue = try container.decodeIfPresent(String.self, forKey: .value)
            let canonical = ProjectDescriptionReplacement(rawValue)
            guard rawValue == canonical.value else {
                throw ProjectSetupFormFailure.invalidEncodedSelection
            }
            value = canonical
        }
    }

    private struct StrictCategoryAllocation: Decodable {
        let value: NullableCategoryAllocation

        init(from decoder: Decoder) throws {
            let unbounded = try decoder.container(
                keyedBy: ProjectSetupFormCoding.AnyCodingKey.self
            )
            let keys = Set(unbounded.allKeys.map(\.stringValue))
            guard keys == ["categoryId"] || keys == ["categoryId", "allocation"] else {
                throw ProjectSetupFormFailure.invalidEncodedSelection
            }
            let container = try decoder.container(keyedBy: AllocationCodingKeys.self)
            value = try NullableCategoryAllocation(
                categoryId: container.decode(BudgetCategoryID.self, forKey: .categoryId),
                allocation: container.decodeIfPresent(
                    StrictMoney.self,
                    forKey: .allocation
                )?.value
            )
        }
    }

    private struct StrictMoney: Decodable {
        let value: Money

        init(from decoder: Decoder) throws {
            try ProjectSetupFormCoding.requireExactKeys(
                decoder,
                allowed: MoneyCodingKeys.allCases.map(\.rawValue),
                failure: .invalidEncodedSelection
            )
            let container = try decoder.container(keyedBy: MoneyCodingKeys.self)
            value = Money(
                minorUnits: try container.decode(Int64.self, forKey: .minorUnits),
                currency: try container.decode(CurrencyCode.self, forKey: .currency)
            )
        }
    }

    private enum ClientSelectionCodingKeys: String, CodingKey {
        case kind
        case clientId
        case displayName
    }

    private enum DescriptionCodingKeys: String, CodingKey {
        case value
    }

    private enum AllocationCodingKeys: String, CodingKey, CaseIterable {
        case categoryId
        case allocation
    }

    private enum MoneyCodingKeys: String, CodingKey, CaseIterable {
        case minorUnits
        case currency
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case accountId
        case clientSelection
        case projectDisplayName
        case descriptionReplacement
        case categoryAllocations
        case preparationEvidenceFingerprint
        case selectionFingerprint
    }
}

public enum ProjectSetupFormPresentation {
    public static func prepare(
        clientSelectionSnapshot: ProjectExistingClientSelectionSnapshot,
        categoryReferenceSnapshot: BudgetCategoryReferenceSnapshot
    ) throws -> ProjectSetupFormPreparation {
        try ProjectSetupFormPreparation(
            clientSelectionSnapshot: clientSelectionSnapshot,
            categoryReferenceSnapshot: categoryReferenceSnapshot
        )
    }
}

private enum ProjectSetupFormDigest {
    static func isCanonicalSHA256(_ value: String) -> Bool {
        let hexadecimal = CharacterSet(charactersIn: "0123456789abcdef")
        return value.utf8.count == 64
            && value.unicodeScalars.allSatisfy(hexadecimal.contains)
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private enum ProjectSetupFormCoding {
    static func requireExactKeys(
        _ decoder: Decoder,
        allowed: [String],
        failure: ProjectSetupFormFailure
    ) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        guard Set(container.allKeys.map(\.stringValue)) == Set(allowed) else {
            throw failure
        }
    }

    struct AnyCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            intValue = nil
        }

        init?(intValue: Int) {
            stringValue = String(intValue)
            self.intValue = intValue
        }
    }
}
