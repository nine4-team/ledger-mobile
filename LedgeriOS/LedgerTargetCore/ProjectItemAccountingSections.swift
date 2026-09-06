import CryptoKit
import Foundation

public enum ProjectItemAccountingSectionFailure: Error, Equatable, Sendable {
    case invalidPurchaseClassification
    case invalidOccurrencePhase
    case scopeMismatch
    case itemRelationshipMismatch
    case duplicateItemIdentity
    case duplicateRelationshipIdentity
    case invalidSnapshotCompleteness
    case invalidSnapshotTimestamp
    case derivedEvidenceMismatch
    case evidenceFingerprintMismatch
    case invalidEncodedPurchaseConnection
    case invalidEncodedOccurrence
    case invalidEncodedItemEvidence
    case invalidEncodedRow
    case invalidEncodedSection
    case invalidEncodedFingerprint
    case invalidEncodedSnapshot

    public var diagnosticCode: String {
        switch self {
        case .invalidPurchaseClassification:
            "project_item_accounting_purchase_classification_invalid"
        case .invalidOccurrencePhase:
            "project_item_accounting_occurrence_phase_invalid"
        case .scopeMismatch:
            "project_item_accounting_scope_mismatch"
        case .itemRelationshipMismatch:
            "project_item_accounting_item_relationship_mismatch"
        case .duplicateItemIdentity:
            "project_item_accounting_item_identity_duplicate"
        case .duplicateRelationshipIdentity:
            "project_item_accounting_relationship_identity_duplicate"
        case .invalidSnapshotCompleteness:
            "project_item_accounting_snapshot_completeness_invalid"
        case .invalidSnapshotTimestamp:
            "project_item_accounting_snapshot_timestamp_invalid"
        case .derivedEvidenceMismatch:
            "project_item_accounting_derived_evidence_mismatch"
        case .evidenceFingerprintMismatch:
            "project_item_accounting_fingerprint_mismatch"
        case .invalidEncodedPurchaseConnection:
            "project_item_accounting_purchase_connection_encoding_invalid"
        case .invalidEncodedOccurrence:
            "project_item_accounting_occurrence_encoding_invalid"
        case .invalidEncodedItemEvidence:
            "project_item_accounting_item_evidence_encoding_invalid"
        case .invalidEncodedRow:
            "project_item_accounting_row_encoding_invalid"
        case .invalidEncodedSection:
            "project_item_accounting_section_encoding_invalid"
        case .invalidEncodedFingerprint:
            "project_item_accounting_fingerprint_encoding_invalid"
        case .invalidEncodedSnapshot:
            "project_item_accounting_snapshot_encoding_invalid"
        }
    }
}

public enum ItemAccountingConnectionIDTag: Sendable {}
public enum BillableItemOccurrenceIDTag: Sendable {}

public typealias ItemAccountingConnectionID =
    DomainEntityIdentifier<ItemAccountingConnectionIDTag>
public typealias BillableItemOccurrenceID =
    DomainEntityIdentifier<BillableItemOccurrenceIDTag>

public struct ClientPaidPurchaseAccountingConnection: Codable, Equatable, Sendable {
    public let id: ItemAccountingConnectionID
    public let accountId: AccountID
    public let projectId: ProjectID
    public let clientId: ClientID
    public let itemId: ItemID
    public let transactionId: TransactionID
    public let classification: TransactionClassification

    public init(
        id: ItemAccountingConnectionID,
        accountId: AccountID,
        projectId: ProjectID,
        clientId: ClientID,
        itemId: ItemID,
        transactionId: TransactionID,
        classification: TransactionClassification
    ) throws {
        guard classification.type == .purchase,
              classification.role == .standalone,
              classification.scope.ownerKind == .project else {
            throw ProjectItemAccountingSectionFailure.invalidPurchaseClassification
        }
        guard classification.scope.accountId == accountId,
              classification.scope.projectId == projectId,
              classification.scope.clientId == clientId else {
            throw ProjectItemAccountingSectionFailure.scopeMismatch
        }
        self.id = id
        self.accountId = accountId
        self.projectId = projectId
        self.clientId = clientId
        self.itemId = itemId
        self.transactionId = transactionId
        self.classification = classification
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                id: container.decode(ItemAccountingConnectionID.self, forKey: .id),
                accountId: container.decode(AccountID.self, forKey: .accountId),
                projectId: container.decode(ProjectID.self, forKey: .projectId),
                clientId: container.decode(ClientID.self, forKey: .clientId),
                itemId: container.decode(ItemID.self, forKey: .itemId),
                transactionId: container.decode(
                    TransactionID.self,
                    forKey: .transactionId
                ),
                classification: container.decode(
                    TransactionClassification.self,
                    forKey: .classification
                )
            )
        } catch let failure as ProjectItemAccountingSectionFailure {
            throw failure
        } catch {
            throw ProjectItemAccountingSectionFailure.invalidEncodedPurchaseConnection
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case accountId
        case projectId
        case clientId
        case itemId
        case transactionId
        case classification
    }
}

public enum BillableItemOccurrencePolarity: String, Codable, CaseIterable, Sendable {
    case charge
    case credit
}

public enum BillableItemOccurrencePhaseKind: String, Codable, CaseIterable, Sendable {
    case availableToInvoice
    case onLiveInvoice
    case frozenPaid
}

public struct BillableItemOccurrencePhase: Codable, Equatable, Sendable {
    public let kind: BillableItemOccurrencePhaseKind
    public let invoiceId: InvoiceID?

    public init(
        kind: BillableItemOccurrencePhaseKind,
        invoiceId: InvoiceID? = nil
    ) throws {
        switch kind {
        case .availableToInvoice:
            guard invoiceId == nil else {
                throw ProjectItemAccountingSectionFailure.invalidOccurrencePhase
            }
        case .onLiveInvoice, .frozenPaid:
            guard invoiceId != nil else {
                throw ProjectItemAccountingSectionFailure.invalidOccurrencePhase
            }
        }
        self.kind = kind
        self.invoiceId = invoiceId
    }

    public static var availableToInvoice: Self {
        Self(validatedKind: .availableToInvoice, invoiceId: nil)
    }

    public static func onLiveInvoice(invoiceId: InvoiceID) -> Self {
        Self(validatedKind: .onLiveInvoice, invoiceId: invoiceId)
    }

    public static func frozenPaid(invoiceId: InvoiceID) -> Self {
        Self(validatedKind: .frozenPaid, invoiceId: invoiceId)
    }

    private init(
        validatedKind kind: BillableItemOccurrencePhaseKind,
        invoiceId: InvoiceID?
    ) {
        self.kind = kind
        self.invoiceId = invoiceId
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                kind: container.decode(
                    BillableItemOccurrencePhaseKind.self,
                    forKey: .kind
                ),
                invoiceId: container.decodeIfPresent(InvoiceID.self, forKey: .invoiceId)
            )
        } catch let failure as ProjectItemAccountingSectionFailure {
            throw failure
        } catch {
            throw ProjectItemAccountingSectionFailure.invalidOccurrencePhase
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case invoiceId
    }
}

public struct BillableItemAccountingOccurrence: Codable, Equatable, Sendable {
    public let id: BillableItemOccurrenceID
    public let accountId: AccountID
    public let projectId: ProjectID
    public let itemId: ItemID
    public let polarity: BillableItemOccurrencePolarity
    public let phase: BillableItemOccurrencePhase

    public init(
        id: BillableItemOccurrenceID,
        accountId: AccountID,
        projectId: ProjectID,
        itemId: ItemID,
        polarity: BillableItemOccurrencePolarity,
        phase: BillableItemOccurrencePhase
    ) {
        self.id = id
        self.accountId = accountId
        self.projectId = projectId
        self.itemId = itemId
        self.polarity = polarity
        self.phase = phase
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                id: try container.decode(BillableItemOccurrenceID.self, forKey: .id),
                accountId: try container.decode(AccountID.self, forKey: .accountId),
                projectId: try container.decode(ProjectID.self, forKey: .projectId),
                itemId: try container.decode(ItemID.self, forKey: .itemId),
                polarity: try container.decode(
                    BillableItemOccurrencePolarity.self,
                    forKey: .polarity
                ),
                phase: try container.decode(
                    BillableItemOccurrencePhase.self,
                    forKey: .phase
                )
            )
        } catch let failure as ProjectItemAccountingSectionFailure {
            throw failure
        } catch {
            throw ProjectItemAccountingSectionFailure.invalidEncodedOccurrence
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case accountId
        case projectId
        case itemId
        case polarity
        case phase
    }
}

public struct ProjectItemAccountingEvidence: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let projectId: ProjectID
    public let clientId: ClientID
    public let itemId: ItemID
    public let spaceId: SpaceID?
    public let clientPaidPurchases: [ClientPaidPurchaseAccountingConnection]
    public let billableOccurrences: [BillableItemAccountingOccurrence]

    public var hasQualifyingRelationship: Bool {
        !clientPaidPurchases.isEmpty || !billableOccurrences.isEmpty
    }

    public init(
        accountId: AccountID,
        projectId: ProjectID,
        clientId: ClientID,
        itemId: ItemID,
        spaceId: SpaceID? = nil,
        clientPaidPurchases: [ClientPaidPurchaseAccountingConnection] = [],
        billableOccurrences: [BillableItemAccountingOccurrence] = []
    ) throws {
        guard clientPaidPurchases.allSatisfy({
            $0.accountId == accountId &&
                $0.projectId == projectId &&
                $0.clientId == clientId
        }), billableOccurrences.allSatisfy({
            $0.accountId == accountId && $0.projectId == projectId
        }) else {
            throw ProjectItemAccountingSectionFailure.scopeMismatch
        }
        guard clientPaidPurchases.allSatisfy({ $0.itemId == itemId }),
              billableOccurrences.allSatisfy({ $0.itemId == itemId }) else {
            throw ProjectItemAccountingSectionFailure.itemRelationshipMismatch
        }
        guard Self.hasUniqueIdentities(clientPaidPurchases.map(\.id)),
              Self.hasUniqueIdentities(billableOccurrences.map(\.id)) else {
            throw ProjectItemAccountingSectionFailure.duplicateRelationshipIdentity
        }
        self.accountId = accountId
        self.projectId = projectId
        self.clientId = clientId
        self.itemId = itemId
        self.spaceId = spaceId
        self.clientPaidPurchases = clientPaidPurchases
        self.billableOccurrences = billableOccurrences
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                accountId: container.decode(AccountID.self, forKey: .accountId),
                projectId: container.decode(ProjectID.self, forKey: .projectId),
                clientId: container.decode(ClientID.self, forKey: .clientId),
                itemId: container.decode(ItemID.self, forKey: .itemId),
                spaceId: container.decodeIfPresent(SpaceID.self, forKey: .spaceId),
                clientPaidPurchases: container.decode(
                    [ClientPaidPurchaseAccountingConnection].self,
                    forKey: .clientPaidPurchases
                ),
                billableOccurrences: container.decode(
                    [BillableItemAccountingOccurrence].self,
                    forKey: .billableOccurrences
                )
            )
        } catch let failure as ProjectItemAccountingSectionFailure {
            throw failure
        } catch {
            throw ProjectItemAccountingSectionFailure.invalidEncodedItemEvidence
        }
    }

    private static func hasUniqueIdentities<Value: Hashable>(_ values: [Value]) -> Bool {
        Set(values).count == values.count
    }

    private enum CodingKeys: String, CodingKey {
        case accountId
        case projectId
        case clientId
        case itemId
        case spaceId
        case clientPaidPurchases
        case billableOccurrences
    }
}

public enum ProjectItemAccountingState: String, Codable, CaseIterable, Sendable {
    case unaccountedFor
    case accountedFor
}

public enum ProjectItemAccountingResolution: String, Codable, CaseIterable, Sendable {
    case unaccountedFor
    case accountedFor
    case relationshipEvidenceIncomplete

    public var accountingState: ProjectItemAccountingState? {
        switch self {
        case .unaccountedFor:
            .unaccountedFor
        case .accountedFor:
            .accountedFor
        case .relationshipEvidenceIncomplete:
            nil
        }
    }
}

public struct ProjectItemAccountingRow: Codable, Equatable, Sendable {
    public let evidence: ProjectItemAccountingEvidence
    public let relationshipAbsenceIsAuthoritative: Bool
    public let resolution: ProjectItemAccountingResolution

    public var accountingState: ProjectItemAccountingState? {
        resolution.accountingState
    }

    public init(
        evidence: ProjectItemAccountingEvidence,
        relationshipAbsenceIsAuthoritative: Bool
    ) {
        self.evidence = evidence
        self.relationshipAbsenceIsAuthoritative = relationshipAbsenceIsAuthoritative
        resolution = Self.resolve(
            evidence: evidence,
            relationshipAbsenceIsAuthoritative: relationshipAbsenceIsAuthoritative
        )
    }

    private init(
        evidence: ProjectItemAccountingEvidence,
        relationshipAbsenceIsAuthoritative: Bool,
        expectedResolution: ProjectItemAccountingResolution
    ) throws {
        let resolved = Self.resolve(
            evidence: evidence,
            relationshipAbsenceIsAuthoritative: relationshipAbsenceIsAuthoritative
        )
        guard expectedResolution == resolved else {
            throw ProjectItemAccountingSectionFailure.derivedEvidenceMismatch
        }
        self.evidence = evidence
        self.relationshipAbsenceIsAuthoritative = relationshipAbsenceIsAuthoritative
        resolution = resolved
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                evidence: container.decode(
                    ProjectItemAccountingEvidence.self,
                    forKey: .evidence
                ),
                relationshipAbsenceIsAuthoritative: container.decode(
                    Bool.self,
                    forKey: .relationshipAbsenceIsAuthoritative
                ),
                expectedResolution: container.decode(
                    ProjectItemAccountingResolution.self,
                    forKey: .resolution
                )
            )
        } catch let failure as ProjectItemAccountingSectionFailure {
            throw failure
        } catch {
            throw ProjectItemAccountingSectionFailure.invalidEncodedRow
        }
    }

    private static func resolve(
        evidence: ProjectItemAccountingEvidence,
        relationshipAbsenceIsAuthoritative: Bool
    ) -> ProjectItemAccountingResolution {
        if evidence.hasQualifyingRelationship {
            return .accountedFor
        }
        return relationshipAbsenceIsAuthoritative
            ? .unaccountedFor
            : .relationshipEvidenceIncomplete
    }

    private enum CodingKeys: String, CodingKey {
        case evidence
        case relationshipAbsenceIsAuthoritative
        case resolution
    }
}

public enum ProjectItemAccountingSectionKind: String, Codable, CaseIterable, Sendable {
    case unaccountedFor
    case accountedFor
}

public struct ProjectItemAccountingSection: Codable, Equatable, Sendable {
    public let kind: ProjectItemAccountingSectionKind
    public let rows: [ProjectItemAccountingRow]

    public init(
        kind: ProjectItemAccountingSectionKind,
        rows: [ProjectItemAccountingRow]
    ) throws {
        let expectedResolution: ProjectItemAccountingResolution = switch kind {
        case .unaccountedFor: .unaccountedFor
        case .accountedFor: .accountedFor
        }
        guard rows.allSatisfy({ $0.resolution == expectedResolution }) else {
            throw ProjectItemAccountingSectionFailure.derivedEvidenceMismatch
        }
        guard Set(rows.map(\.evidence.itemId)).count == rows.count else {
            throw ProjectItemAccountingSectionFailure.duplicateItemIdentity
        }
        self.kind = kind
        self.rows = rows
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                kind: container.decode(ProjectItemAccountingSectionKind.self, forKey: .kind),
                rows: container.decode([ProjectItemAccountingRow].self, forKey: .rows)
            )
        } catch let failure as ProjectItemAccountingSectionFailure {
            throw failure
        } catch {
            throw ProjectItemAccountingSectionFailure.invalidEncodedSection
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case rows
    }
}

public enum ProjectItemAccountingSectionsAvailability: String, Codable, CaseIterable, Sendable {
    case available
    case authoritativeEmpty
    case relationshipEvidenceIncomplete
}

public struct ProjectItemAccountingEvidenceFingerprint: Codable, Equatable, Hashable, Sendable {
    public let sha256: String

    public init(validating sha256: String) throws {
        let hexadecimal = CharacterSet(charactersIn: "0123456789abcdef")
        guard sha256.utf8.count == 64,
              sha256.unicodeScalars.allSatisfy(hexadecimal.contains) else {
            throw ProjectItemAccountingSectionFailure.invalidEncodedFingerprint
        }
        self.sha256 = sha256
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            try self.init(validating: container.decode(String.self))
        } catch let failure as ProjectItemAccountingSectionFailure {
            throw failure
        } catch {
            throw ProjectItemAccountingSectionFailure.invalidEncodedFingerprint
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(sha256)
    }
}

public struct ProjectItemAccountingSectionsSnapshot: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let projectId: ProjectID
    public let clientId: ClientID
    public let rows: [ProjectItemAccountingRow]
    public let sections: [ProjectItemAccountingSection]
    public let unresolvedRows: [ProjectItemAccountingRow]
    public let availability: ProjectItemAccountingSectionsAvailability
    public let isCompleteForAccounting: Bool
    public let quality: ListSnapshotQuality
    public let localDataVersion: LocalDataVersion
    public let asOf: Date
    public let evidenceFingerprint: ProjectItemAccountingEvidenceFingerprint

    public var readiness: ListReadiness {
        quality.readiness
    }

    public init(
        accountId: AccountID,
        projectId: ProjectID,
        clientId: ClientID,
        items: [ProjectItemAccountingEvidence],
        isCompleteForAccounting: Bool,
        quality: ListSnapshotQuality,
        localDataVersion: LocalDataVersion,
        asOf: Date
    ) throws {
        guard !isCompleteForAccounting || quality == .ready else {
            throw ProjectItemAccountingSectionFailure.invalidSnapshotCompleteness
        }
        guard asOf.timeIntervalSinceReferenceDate.isFinite else {
            throw ProjectItemAccountingSectionFailure.invalidSnapshotTimestamp
        }
        guard items.allSatisfy({
            $0.accountId == accountId &&
                $0.projectId == projectId &&
                $0.clientId == clientId
        }) else {
            throw ProjectItemAccountingSectionFailure.scopeMismatch
        }
        guard Self.hasUniqueIdentities(items.map(\.itemId)) else {
            throw ProjectItemAccountingSectionFailure.duplicateItemIdentity
        }
        guard Self.relationshipIdentitiesAreUnique(items) else {
            throw ProjectItemAccountingSectionFailure.duplicateRelationshipIdentity
        }

        let relationshipAbsenceIsAuthoritative =
            isCompleteForAccounting && quality == .ready
        let rows = items.map {
            ProjectItemAccountingRow(
                evidence: $0,
                relationshipAbsenceIsAuthoritative: relationshipAbsenceIsAuthoritative
            )
        }
        let sections = try Self.makeSections(rows: rows)
        let unresolvedRows = rows.filter {
            $0.resolution == .relationshipEvidenceIncomplete
        }
        let availability = Self.makeAvailability(
            rowCount: rows.count,
            isCompleteForAccounting: isCompleteForAccounting
        )
        let fingerprint = try Self.makeFingerprint(
            accountId: accountId,
            projectId: projectId,
            clientId: clientId,
            rows: rows,
            sections: sections,
            unresolvedRows: unresolvedRows,
            availability: availability,
            isCompleteForAccounting: isCompleteForAccounting,
            quality: quality,
            localDataVersion: localDataVersion,
            asOf: asOf
        )

        self.accountId = accountId
        self.projectId = projectId
        self.clientId = clientId
        self.rows = rows
        self.sections = sections
        self.unresolvedRows = unresolvedRows
        self.availability = availability
        self.isCompleteForAccounting = isCompleteForAccounting
        self.quality = quality
        self.localDataVersion = localDataVersion
        self.asOf = asOf
        evidenceFingerprint = fingerprint
    }

    private init(
        accountId: AccountID,
        projectId: ProjectID,
        clientId: ClientID,
        rows: [ProjectItemAccountingRow],
        sections: [ProjectItemAccountingSection],
        unresolvedRows: [ProjectItemAccountingRow],
        availability: ProjectItemAccountingSectionsAvailability,
        isCompleteForAccounting: Bool,
        quality: ListSnapshotQuality,
        localDataVersion: LocalDataVersion,
        asOf: Date,
        evidenceFingerprint: ProjectItemAccountingEvidenceFingerprint
    ) throws {
        let rebuilt = try Self(
            accountId: accountId,
            projectId: projectId,
            clientId: clientId,
            items: rows.map(\.evidence),
            isCompleteForAccounting: isCompleteForAccounting,
            quality: quality,
            localDataVersion: localDataVersion,
            asOf: asOf
        )
        guard rows == rebuilt.rows,
              sections == rebuilt.sections,
              unresolvedRows == rebuilt.unresolvedRows,
              availability == rebuilt.availability else {
            throw ProjectItemAccountingSectionFailure.derivedEvidenceMismatch
        }
        guard evidenceFingerprint == rebuilt.evidenceFingerprint else {
            throw ProjectItemAccountingSectionFailure.evidenceFingerprintMismatch
        }
        self = rebuilt
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                accountId: container.decode(AccountID.self, forKey: .accountId),
                projectId: container.decode(ProjectID.self, forKey: .projectId),
                clientId: container.decode(ClientID.self, forKey: .clientId),
                rows: container.decode([ProjectItemAccountingRow].self, forKey: .rows),
                sections: container.decode(
                    [ProjectItemAccountingSection].self,
                    forKey: .sections
                ),
                unresolvedRows: container.decode(
                    [ProjectItemAccountingRow].self,
                    forKey: .unresolvedRows
                ),
                availability: container.decode(
                    ProjectItemAccountingSectionsAvailability.self,
                    forKey: .availability
                ),
                isCompleteForAccounting: container.decode(
                    Bool.self,
                    forKey: .isCompleteForAccounting
                ),
                quality: container.decode(ListSnapshotQuality.self, forKey: .quality),
                localDataVersion: container.decode(
                    LocalDataVersion.self,
                    forKey: .localDataVersion
                ),
                asOf: container.decode(Date.self, forKey: .asOf),
                evidenceFingerprint: container.decode(
                    ProjectItemAccountingEvidenceFingerprint.self,
                    forKey: .evidenceFingerprint
                )
            )
        } catch let failure as ProjectItemAccountingSectionFailure {
            throw failure
        } catch {
            throw ProjectItemAccountingSectionFailure.invalidEncodedSnapshot
        }
    }

    private static func makeSections(
        rows: [ProjectItemAccountingRow]
    ) throws -> [ProjectItemAccountingSection] {
        [
            try ProjectItemAccountingSection(
                kind: .unaccountedFor,
                rows: rows.filter { $0.resolution == .unaccountedFor }
            ),
            try ProjectItemAccountingSection(
                kind: .accountedFor,
                rows: rows.filter { $0.resolution == .accountedFor }
            )
        ]
    }

    private static func makeAvailability(
        rowCount: Int,
        isCompleteForAccounting: Bool
    ) -> ProjectItemAccountingSectionsAvailability {
        guard isCompleteForAccounting else {
            return .relationshipEvidenceIncomplete
        }
        return rowCount == 0 ? .authoritativeEmpty : .available
    }

    private static func relationshipIdentitiesAreUnique(
        _ items: [ProjectItemAccountingEvidence]
    ) -> Bool {
        hasUniqueIdentities(items.flatMap { $0.clientPaidPurchases.map(\.id) }) &&
            hasUniqueIdentities(items.flatMap { $0.billableOccurrences.map(\.id) })
    }

    private static func hasUniqueIdentities<Value: Hashable>(_ values: [Value]) -> Bool {
        Set(values).count == values.count
    }

    private static func makeFingerprint(
        accountId: AccountID,
        projectId: ProjectID,
        clientId: ClientID,
        rows: [ProjectItemAccountingRow],
        sections: [ProjectItemAccountingSection],
        unresolvedRows: [ProjectItemAccountingRow],
        availability: ProjectItemAccountingSectionsAvailability,
        isCompleteForAccounting: Bool,
        quality: ListSnapshotQuality,
        localDataVersion: LocalDataVersion,
        asOf: Date
    ) throws -> ProjectItemAccountingEvidenceFingerprint {
        do {
            let basis = FingerprintBasis(
                contractVersion: "project-item-accounting-sections-v1",
                accountId: accountId,
                projectId: projectId,
                clientId: clientId,
                rows: rows,
                sections: sections,
                unresolvedRows: unresolvedRows,
                availability: availability,
                isCompleteForAccounting: isCompleteForAccounting,
                quality: quality,
                localDataVersion: localDataVersion,
                asOf: asOf
            )
            let bytes = try OperationContractCodec.encode(basis)
            let digest = SHA256.hash(data: bytes)
                .map { String(format: "%02x", $0) }
                .joined()
            return try ProjectItemAccountingEvidenceFingerprint(validating: digest)
        } catch let failure as ProjectItemAccountingSectionFailure {
            throw failure
        } catch {
            throw ProjectItemAccountingSectionFailure.evidenceFingerprintMismatch
        }
    }

    private struct FingerprintBasis: Codable {
        let contractVersion: String
        let accountId: AccountID
        let projectId: ProjectID
        let clientId: ClientID
        let rows: [ProjectItemAccountingRow]
        let sections: [ProjectItemAccountingSection]
        let unresolvedRows: [ProjectItemAccountingRow]
        let availability: ProjectItemAccountingSectionsAvailability
        let isCompleteForAccounting: Bool
        let quality: ListSnapshotQuality
        let localDataVersion: LocalDataVersion
        let asOf: Date
    }

    private enum CodingKeys: String, CodingKey {
        case accountId
        case projectId
        case clientId
        case rows
        case sections
        case unresolvedRows
        case availability
        case isCompleteForAccounting
        case quality
        case localDataVersion
        case asOf
        case evidenceFingerprint
    }
}

public protocol ProjectItemAccountingQuerying: Sendable {
    func watchProjectItemAccountingSections(
        accountId: AccountID,
        projectId: ProjectID
    ) -> AsyncThrowingStream<ProjectItemAccountingSectionsSnapshot, Error>
}
