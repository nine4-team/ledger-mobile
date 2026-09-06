import CryptoKit
import Foundation

public enum ProjectExistingClientSelectionFailure: Error, Equatable, Sendable {
    case accountScopeMismatch
    case inactiveCandidate
    case duplicateClientIdentity
    case visibleCountMismatch
    case invalidCompleteness
    case invalidAsOf
    case invalidQueryFingerprint
    case invalidEvidenceFingerprint
    case queryFingerprintMismatch
    case evidenceFingerprintMismatch
    case clientNotSelectable
    case invalidEncodedSnapshot

    public var diagnosticCode: String {
        switch self {
        case .accountScopeMismatch:
            "project_client_selection_account_scope_mismatch"
        case .inactiveCandidate:
            "project_client_selection_candidate_inactive"
        case .duplicateClientIdentity:
            "project_client_selection_client_identity_duplicate"
        case .visibleCountMismatch:
            "project_client_selection_visible_count_mismatch"
        case .invalidCompleteness:
            "project_client_selection_completeness_invalid"
        case .invalidAsOf:
            "project_client_selection_as_of_invalid"
        case .invalidQueryFingerprint:
            "project_client_selection_query_fingerprint_invalid"
        case .invalidEvidenceFingerprint:
            "project_client_selection_evidence_fingerprint_invalid"
        case .queryFingerprintMismatch:
            "project_client_selection_query_fingerprint_mismatch"
        case .evidenceFingerprintMismatch:
            "project_client_selection_evidence_fingerprint_mismatch"
        case .clientNotSelectable:
            "project_client_selection_client_not_selectable"
        case .invalidEncodedSnapshot:
            "project_client_selection_snapshot_encoding_invalid"
        }
    }
}

public struct ProjectExistingClientSelectionQueryFingerprint:
    Codable, Equatable, Hashable, Sendable
{
    public let sha256: String

    public init(validating sha256: String) throws {
        guard Self.isCanonicalSHA256(sha256) else {
            throw ProjectExistingClientSelectionFailure.invalidQueryFingerprint
        }
        self.sha256 = sha256
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(validating: container.decode(String.self))
        } catch let failure as ProjectExistingClientSelectionFailure {
            throw failure
        } catch {
            throw ProjectExistingClientSelectionFailure.invalidQueryFingerprint
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(sha256)
    }

    private static func isCanonicalSHA256(_ value: String) -> Bool {
        let hexadecimal = CharacterSet(charactersIn: "0123456789abcdef")
        return value.utf8.count == 64
            && value.unicodeScalars.allSatisfy(hexadecimal.contains)
    }
}

public struct ProjectExistingClientSelectionEvidenceFingerprint:
    Codable, Equatable, Hashable, Sendable
{
    public let sha256: String

    public init(validating sha256: String) throws {
        guard Self.isCanonicalSHA256(sha256) else {
            throw ProjectExistingClientSelectionFailure.invalidEvidenceFingerprint
        }
        self.sha256 = sha256
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(validating: container.decode(String.self))
        } catch let failure as ProjectExistingClientSelectionFailure {
            throw failure
        } catch {
            throw ProjectExistingClientSelectionFailure.invalidEvidenceFingerprint
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(sha256)
    }

    private static func isCanonicalSHA256(_ value: String) -> Bool {
        let hexadecimal = CharacterSet(charactersIn: "0123456789abcdef")
        return value.utf8.count == 64
            && value.unicodeScalars.allSatisfy(hexadecimal.contains)
    }
}

public enum ProjectExistingClientSelectionAvailability: String, Codable, Sendable {
    case available
    case noActiveClient
    case directoryIncomplete
}

public struct ProjectExistingClientSelectionSnapshot: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let activeClients: [ClientSummary]
    public let availability: ProjectExistingClientSelectionAvailability
    public let sourceDirectoryFingerprint: ListQueryFingerprint
    public let sourceDirectoryRowCount: Int
    public let visibleRowCountBeforeFiltering: Int
    public let isCompleteForQuery: Bool
    public let quality: ListSnapshotQuality
    public let localDataVersion: LocalDataVersion
    public let asOf: Date
    public let queryFingerprint: ProjectExistingClientSelectionQueryFingerprint
    public let evidenceFingerprint: ProjectExistingClientSelectionEvidenceFingerprint

    public var readiness: ListReadiness { quality.readiness }

    public init(directory: ClientListSnapshot) throws {
        let activeClients = directory.local.rows.filter { $0.lifecycle == .active }
        guard directory.local.visibleRowCountBeforeFiltering >= directory.local.rows.count else {
            throw ProjectExistingClientSelectionFailure.visibleCountMismatch
        }
        guard directory.local.quality == .ready || !directory.local.isCompleteForQuery else {
            throw ProjectExistingClientSelectionFailure.invalidCompleteness
        }
        guard directory.local.asOf.timeIntervalSinceReferenceDate.isFinite else {
            throw ProjectExistingClientSelectionFailure.invalidAsOf
        }
        let queryFingerprint = try Self.makeQueryFingerprint(
            accountId: directory.accountId,
            sourceDirectoryFingerprint: directory.local.queryFingerprint
        )
        let evidenceFingerprint = try Self.makeEvidenceFingerprint(
            accountId: directory.accountId,
            activeClients: activeClients,
            sourceDirectoryFingerprint: directory.local.queryFingerprint,
            sourceDirectoryRowCount: directory.local.rows.count,
            visibleRowCountBeforeFiltering: directory.local.visibleRowCountBeforeFiltering,
            isCompleteForQuery: directory.local.isCompleteForQuery,
            quality: directory.local.quality,
            localDataVersion: directory.local.localDataVersion,
            asOf: directory.local.asOf
        )
        try self.init(
            accountId: directory.accountId,
            activeClients: activeClients,
            sourceDirectoryFingerprint: directory.local.queryFingerprint,
            sourceDirectoryRowCount: directory.local.rows.count,
            visibleRowCountBeforeFiltering: directory.local.visibleRowCountBeforeFiltering,
            isCompleteForQuery: directory.local.isCompleteForQuery,
            quality: directory.local.quality,
            localDataVersion: directory.local.localDataVersion,
            asOf: directory.local.asOf,
            queryFingerprint: queryFingerprint,
            evidenceFingerprint: evidenceFingerprint
        )
    }

    private init(
        accountId: AccountID,
        activeClients: [ClientSummary],
        sourceDirectoryFingerprint: ListQueryFingerprint,
        sourceDirectoryRowCount: Int,
        visibleRowCountBeforeFiltering: Int,
        isCompleteForQuery: Bool,
        quality: ListSnapshotQuality,
        localDataVersion: LocalDataVersion,
        asOf: Date,
        queryFingerprint: ProjectExistingClientSelectionQueryFingerprint,
        evidenceFingerprint: ProjectExistingClientSelectionEvidenceFingerprint
    ) throws {
        guard activeClients.allSatisfy({ $0.accountId == accountId }) else {
            throw ProjectExistingClientSelectionFailure.accountScopeMismatch
        }
        guard activeClients.allSatisfy({ $0.lifecycle == .active }) else {
            throw ProjectExistingClientSelectionFailure.inactiveCandidate
        }
        guard Set(activeClients.map(\.id)).count == activeClients.count else {
            throw ProjectExistingClientSelectionFailure.duplicateClientIdentity
        }
        guard sourceDirectoryRowCount >= 0,
              sourceDirectoryRowCount >= activeClients.count,
              visibleRowCountBeforeFiltering >= 0,
              sourceDirectoryRowCount <= visibleRowCountBeforeFiltering else {
            throw ProjectExistingClientSelectionFailure.visibleCountMismatch
        }
        guard quality == .ready || !isCompleteForQuery else {
            throw ProjectExistingClientSelectionFailure.invalidCompleteness
        }
        guard asOf.timeIntervalSinceReferenceDate.isFinite else {
            throw ProjectExistingClientSelectionFailure.invalidAsOf
        }

        let expectedQueryFingerprint = try Self.makeQueryFingerprint(
            accountId: accountId,
            sourceDirectoryFingerprint: sourceDirectoryFingerprint
        )
        guard queryFingerprint == expectedQueryFingerprint else {
            throw ProjectExistingClientSelectionFailure.queryFingerprintMismatch
        }
        let expectedEvidenceFingerprint = try Self.makeEvidenceFingerprint(
            accountId: accountId,
            activeClients: activeClients,
            sourceDirectoryFingerprint: sourceDirectoryFingerprint,
            sourceDirectoryRowCount: sourceDirectoryRowCount,
            visibleRowCountBeforeFiltering: visibleRowCountBeforeFiltering,
            isCompleteForQuery: isCompleteForQuery,
            quality: quality,
            localDataVersion: localDataVersion,
            asOf: asOf
        )
        guard evidenceFingerprint == expectedEvidenceFingerprint else {
            throw ProjectExistingClientSelectionFailure.evidenceFingerprintMismatch
        }

        self.accountId = accountId
        self.activeClients = activeClients
        availability = Self.makeAvailability(
            activeClients: activeClients,
            sourceDirectoryRowCount: sourceDirectoryRowCount,
            visibleRowCountBeforeFiltering: visibleRowCountBeforeFiltering,
            isCompleteForQuery: isCompleteForQuery,
            quality: quality
        )
        self.sourceDirectoryFingerprint = sourceDirectoryFingerprint
        self.sourceDirectoryRowCount = sourceDirectoryRowCount
        self.visibleRowCountBeforeFiltering = visibleRowCountBeforeFiltering
        self.isCompleteForQuery = isCompleteForQuery
        self.quality = quality
        self.localDataVersion = localDataVersion
        self.asOf = asOf
        self.queryFingerprint = queryFingerprint
        self.evidenceFingerprint = evidenceFingerprint
    }

    public func selection(clientId: ClientID) throws -> ProjectClientSelectionInput {
        guard activeClients.contains(where: { $0.id == clientId }) else {
            throw ProjectExistingClientSelectionFailure.clientNotSelectable
        }
        return .existing(clientId)
    }

    public init(from decoder: Decoder) throws {
        do {
            let unboundedContainer = try decoder.container(keyedBy: UnboundedCodingKey.self)
            let encodedKeys = Set(unboundedContainer.allKeys.map(\.stringValue))
            let allowedKeys = Set(CodingKeys.allCases.map(\.rawValue))
            guard encodedKeys == allowedKeys else {
                throw ProjectExistingClientSelectionFailure.invalidEncodedSnapshot
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let encodedAvailability = try container.decode(
                ProjectExistingClientSelectionAvailability.self,
                forKey: .availability
            )
            let encodedClients = try container.decode(
                [StrictClientSummary].self,
                forKey: .activeClients
            ).map(\.value)
            try self.init(
                accountId: container.decode(AccountID.self, forKey: .accountId),
                activeClients: encodedClients,
                sourceDirectoryFingerprint: container.decode(
                    ListQueryFingerprint.self,
                    forKey: .sourceDirectoryFingerprint
                ),
                sourceDirectoryRowCount: container.decode(
                    Int.self,
                    forKey: .sourceDirectoryRowCount
                ),
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
                asOf: container.decode(Date.self, forKey: .asOf),
                queryFingerprint: container.decode(
                    ProjectExistingClientSelectionQueryFingerprint.self,
                    forKey: .queryFingerprint
                ),
                evidenceFingerprint: container.decode(
                    ProjectExistingClientSelectionEvidenceFingerprint.self,
                    forKey: .evidenceFingerprint
                )
            )
            guard availability == encodedAvailability else {
                throw ProjectExistingClientSelectionFailure.evidenceFingerprintMismatch
            }
        } catch let failure as ProjectExistingClientSelectionFailure {
            throw failure
        } catch {
            throw ProjectExistingClientSelectionFailure.invalidEncodedSnapshot
        }
    }

    private static func makeAvailability(
        activeClients: [ClientSummary],
        sourceDirectoryRowCount: Int,
        visibleRowCountBeforeFiltering: Int,
        isCompleteForQuery: Bool,
        quality: ListSnapshotQuality
    ) -> ProjectExistingClientSelectionAvailability {
        if !activeClients.isEmpty {
            return .available
        }
        if quality == .ready,
           isCompleteForQuery,
           sourceDirectoryRowCount == visibleRowCountBeforeFiltering {
            return .noActiveClient
        }
        return .directoryIncomplete
    }

    private static func makeQueryFingerprint(
        accountId: AccountID,
        sourceDirectoryFingerprint: ListQueryFingerprint
    ) throws -> ProjectExistingClientSelectionQueryFingerprint {
        do {
            let basis = QueryFingerprintBasis(
                contractVersion: "project-existing-client-selection-v1",
                accountId: accountId,
                sourceDirectoryFingerprint: sourceDirectoryFingerprint
            )
            return try ProjectExistingClientSelectionQueryFingerprint(
                validating: sha256(try OperationContractCodec.encode(basis))
            )
        } catch let failure as ProjectExistingClientSelectionFailure {
            throw failure
        } catch {
            throw ProjectExistingClientSelectionFailure.invalidQueryFingerprint
        }
    }

    private static func makeEvidenceFingerprint(
        accountId: AccountID,
        activeClients: [ClientSummary],
        sourceDirectoryFingerprint: ListQueryFingerprint,
        sourceDirectoryRowCount: Int,
        visibleRowCountBeforeFiltering: Int,
        isCompleteForQuery: Bool,
        quality: ListSnapshotQuality,
        localDataVersion: LocalDataVersion,
        asOf: Date
    ) throws -> ProjectExistingClientSelectionEvidenceFingerprint {
        do {
            let basis = EvidenceFingerprintBasis(
                contractVersion: "project-existing-client-selection-evidence-v1",
                accountId: accountId,
                activeClients: activeClients,
                sourceDirectoryFingerprint: sourceDirectoryFingerprint,
                sourceDirectoryRowCount: sourceDirectoryRowCount,
                visibleRowCountBeforeFiltering: visibleRowCountBeforeFiltering,
                isCompleteForQuery: isCompleteForQuery,
                quality: quality,
                localDataVersion: localDataVersion,
                asOf: asOf
            )
            return try ProjectExistingClientSelectionEvidenceFingerprint(
                validating: sha256(try OperationContractCodec.encode(basis))
            )
        } catch let failure as ProjectExistingClientSelectionFailure {
            throw failure
        } catch {
            throw ProjectExistingClientSelectionFailure.invalidEvidenceFingerprint
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private struct QueryFingerprintBasis: Codable {
        let contractVersion: String
        let accountId: AccountID
        let sourceDirectoryFingerprint: ListQueryFingerprint
    }

    private struct EvidenceFingerprintBasis: Codable {
        let contractVersion: String
        let accountId: AccountID
        let activeClients: [ClientSummary]
        let sourceDirectoryFingerprint: ListQueryFingerprint
        let sourceDirectoryRowCount: Int
        let visibleRowCountBeforeFiltering: Int
        let isCompleteForQuery: Bool
        let quality: ListSnapshotQuality
        let localDataVersion: LocalDataVersion
        let asOf: Date
    }

    private struct StrictClientSummary: Decodable {
        let value: ClientSummary

        init(from decoder: Decoder) throws {
            let unboundedContainer = try decoder.container(keyedBy: UnboundedCodingKey.self)
            let encodedKeys = Set(unboundedContainer.allKeys.map(\.stringValue))
            let allowedKeys = Set(ClientCodingKeys.allCases.map(\.rawValue))
            guard encodedKeys == allowedKeys else {
                throw ProjectExistingClientSelectionFailure.invalidEncodedSnapshot
            }
            let container = try decoder.container(keyedBy: ClientCodingKeys.self)
            value = try ClientSummary(
                id: container.decode(ClientID.self, forKey: .id),
                accountId: container.decode(AccountID.self, forKey: .accountId),
                displayName: container.decode(ClientDisplayName.self, forKey: .displayName),
                lifecycle: container.decode(DirectoryLifecycleState.self, forKey: .lifecycle),
                createdAt: container.decode(Date.self, forKey: .createdAt),
                updatedAt: container.decode(Date.self, forKey: .updatedAt)
            )
        }
    }

    private struct UnboundedCodingKey: CodingKey {
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

    private enum ClientCodingKeys: String, CodingKey, CaseIterable {
        case id
        case accountId
        case displayName
        case lifecycle
        case createdAt
        case updatedAt
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case accountId
        case activeClients
        case availability
        case sourceDirectoryFingerprint
        case sourceDirectoryRowCount
        case visibleRowCountBeforeFiltering
        case isCompleteForQuery
        case quality
        case localDataVersion
        case asOf
        case queryFingerprint
        case evidenceFingerprint
    }
}
