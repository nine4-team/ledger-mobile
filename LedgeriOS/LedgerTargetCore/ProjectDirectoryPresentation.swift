import CryptoKit
import Foundation

public enum ProjectDirectoryPresentationFailure: Error, Equatable, Sendable {
    case segmentLifecycleMismatch
    case duplicateProjectIdentity
    case visibleCountMismatch
    case invalidCompleteness
    case invalidAsOf
    case invalidEvidenceFingerprint
    case invalidSelectionFingerprint
    case evidenceFingerprintMismatch
    case selectionFingerprintMismatch
    case projectNotSelectable
    case selectionSnapshotMismatch
    case invalidEncodedRow
    case invalidEncodedPresentation
    case invalidEncodedSelection

    public var diagnosticCode: String {
        switch self {
        case .segmentLifecycleMismatch: "project_directory_presentation_lifecycle_mismatch"
        case .duplicateProjectIdentity: "project_directory_presentation_identity_duplicate"
        case .visibleCountMismatch: "project_directory_presentation_visible_count_mismatch"
        case .invalidCompleteness: "project_directory_presentation_completeness_invalid"
        case .invalidAsOf: "project_directory_presentation_as_of_invalid"
        case .invalidEvidenceFingerprint: "project_directory_presentation_evidence_fingerprint_invalid"
        case .invalidSelectionFingerprint: "project_directory_presentation_selection_fingerprint_invalid"
        case .evidenceFingerprintMismatch: "project_directory_presentation_evidence_fingerprint_mismatch"
        case .selectionFingerprintMismatch: "project_directory_presentation_selection_fingerprint_mismatch"
        case .projectNotSelectable: "project_directory_presentation_project_not_selectable"
        case .selectionSnapshotMismatch: "project_directory_presentation_selection_snapshot_mismatch"
        case .invalidEncodedRow: "project_directory_presentation_row_encoding_invalid"
        case .invalidEncodedPresentation: "project_directory_presentation_encoding_invalid"
        case .invalidEncodedSelection: "project_directory_presentation_selection_encoding_invalid"
        }
    }
}

public enum ProjectDirectorySegment: String, Codable, CaseIterable, Sendable {
    case active
    case archived

    fileprivate var lifecycle: DirectoryLifecycleState {
        switch self {
        case .active: .active
        case .archived: .archived
        }
    }
}

public struct ProjectDirectoryCoreRow: Codable, Equatable, Sendable {
    public let projectId: ProjectID
    public let projectDisplayName: ProjectDisplayName
    public let clientId: ClientID
    public let clientDisplayName: ClientDisplayName
    public let projectLifecycle: DirectoryLifecycleState
    public let clientLifecycle: DirectoryLifecycleState

    fileprivate init(project: ProjectSummary) {
        projectId = project.id
        projectDisplayName = project.displayName
        clientId = project.clientId
        clientDisplayName = project.client.displayName
        projectLifecycle = project.lifecycle
        clientLifecycle = project.client.lifecycle
    }

    public init(from decoder: Decoder) throws {
        do {
            let unbounded = try decoder.container(keyedBy: ProjectDirectoryCodingKey.self)
            guard Set(unbounded.allKeys.map(\.stringValue))
                    == Set(CodingKeys.allCases.map(\.rawValue)) else {
                throw ProjectDirectoryPresentationFailure.invalidEncodedRow
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            projectId = try container.decode(ProjectID.self, forKey: .projectId)
            projectDisplayName = try container.decode(
                ProjectDisplayName.self,
                forKey: .projectDisplayName
            )
            clientId = try container.decode(ClientID.self, forKey: .clientId)
            clientDisplayName = try container.decode(
                ClientDisplayName.self,
                forKey: .clientDisplayName
            )
            projectLifecycle = try container.decode(
                DirectoryLifecycleState.self,
                forKey: .projectLifecycle
            )
            clientLifecycle = try container.decode(
                DirectoryLifecycleState.self,
                forKey: .clientLifecycle
            )
        } catch let failure as ProjectDirectoryPresentationFailure {
            throw failure
        } catch {
            throw ProjectDirectoryPresentationFailure.invalidEncodedRow
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case projectId
        case projectDisplayName
        case clientId
        case clientDisplayName
        case projectLifecycle
        case clientLifecycle
    }
}

public struct ProjectDirectoryEvidenceFingerprint: Codable, Equatable, Hashable, Sendable {
    public let sha256: String

    public init(validating sha256: String) throws {
        let hexadecimal = CharacterSet(charactersIn: "0123456789abcdef")
        guard sha256.utf8.count == 64,
              sha256.unicodeScalars.allSatisfy(hexadecimal.contains) else {
            throw ProjectDirectoryPresentationFailure.invalidEvidenceFingerprint
        }
        self.sha256 = sha256
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            try self.init(validating: container.decode(String.self))
        } catch let failure as ProjectDirectoryPresentationFailure {
            throw failure
        } catch {
            throw ProjectDirectoryPresentationFailure.invalidEvidenceFingerprint
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(sha256)
    }
}

public struct ProjectBrowsingSelectionFingerprint: Codable, Equatable, Hashable, Sendable {
    public let sha256: String

    public init(validating sha256: String) throws {
        let hexadecimal = CharacterSet(charactersIn: "0123456789abcdef")
        guard sha256.utf8.count == 64,
              sha256.unicodeScalars.allSatisfy(hexadecimal.contains) else {
            throw ProjectDirectoryPresentationFailure.invalidSelectionFingerprint
        }
        self.sha256 = sha256
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            try self.init(validating: container.decode(String.self))
        } catch let failure as ProjectDirectoryPresentationFailure {
            throw failure
        } catch {
            throw ProjectDirectoryPresentationFailure.invalidSelectionFingerprint
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(sha256)
    }
}

public struct ProjectDirectoryPresentationSnapshot: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let segment: ProjectDirectorySegment
    public let rows: [ProjectDirectoryCoreRow]
    public let sourceDirectoryFingerprint: ListQueryFingerprint
    public let sourceDirectoryRowCount: Int
    public let visibleRowCountBeforeFiltering: Int
    public let isCompleteForQuery: Bool
    public let quality: ListSnapshotQuality
    public let localDataVersion: LocalDataVersion
    public let asOf: Date
    public let evidenceFingerprint: ProjectDirectoryEvidenceFingerprint

    public var readiness: ListReadiness { quality.readiness }

    public var isSourceExhaustive: Bool {
        sourceDirectoryRowCount == visibleRowCountBeforeFiltering
    }

    public var isAuthoritativeEmpty: Bool {
        rows.isEmpty && quality == .ready && isCompleteForQuery && isSourceExhaustive
    }

    fileprivate init(snapshot: ProjectListSnapshot, segment: ProjectDirectorySegment) throws {
        guard snapshot.local.asOf.timeIntervalSinceReferenceDate.isFinite else {
            throw ProjectDirectoryPresentationFailure.invalidAsOf
        }
        let rows = snapshot.local.rows
            .filter { $0.lifecycle == segment.lifecycle }
            .map(ProjectDirectoryCoreRow.init(project:))
        let fingerprint = try Self.makeEvidenceFingerprint(
            accountId: snapshot.accountId,
            segment: segment,
            rows: rows,
            sourceDirectoryFingerprint: snapshot.local.queryFingerprint,
            sourceDirectoryRowCount: snapshot.local.rows.count,
            visibleRowCountBeforeFiltering: snapshot.local.visibleRowCountBeforeFiltering,
            isCompleteForQuery: snapshot.local.isCompleteForQuery,
            quality: snapshot.local.quality,
            localDataVersion: snapshot.local.localDataVersion,
            asOf: snapshot.local.asOf
        )
        try self.init(
            accountId: snapshot.accountId,
            segment: segment,
            rows: rows,
            sourceDirectoryFingerprint: snapshot.local.queryFingerprint,
            sourceDirectoryRowCount: snapshot.local.rows.count,
            visibleRowCountBeforeFiltering: snapshot.local.visibleRowCountBeforeFiltering,
            isCompleteForQuery: snapshot.local.isCompleteForQuery,
            quality: snapshot.local.quality,
            localDataVersion: snapshot.local.localDataVersion,
            asOf: snapshot.local.asOf,
            evidenceFingerprint: fingerprint
        )
    }

    private init(
        accountId: AccountID,
        segment: ProjectDirectorySegment,
        rows: [ProjectDirectoryCoreRow],
        sourceDirectoryFingerprint: ListQueryFingerprint,
        sourceDirectoryRowCount: Int,
        visibleRowCountBeforeFiltering: Int,
        isCompleteForQuery: Bool,
        quality: ListSnapshotQuality,
        localDataVersion: LocalDataVersion,
        asOf: Date,
        evidenceFingerprint: ProjectDirectoryEvidenceFingerprint
    ) throws {
        guard rows.allSatisfy({ $0.projectLifecycle == segment.lifecycle }) else {
            throw ProjectDirectoryPresentationFailure.segmentLifecycleMismatch
        }
        guard Set(rows.map(\.projectId)).count == rows.count else {
            throw ProjectDirectoryPresentationFailure.duplicateProjectIdentity
        }
        guard sourceDirectoryRowCount >= rows.count,
              sourceDirectoryRowCount >= 0,
              visibleRowCountBeforeFiltering >= sourceDirectoryRowCount else {
            throw ProjectDirectoryPresentationFailure.visibleCountMismatch
        }
        guard quality == .ready || !isCompleteForQuery else {
            throw ProjectDirectoryPresentationFailure.invalidCompleteness
        }
        guard asOf.timeIntervalSinceReferenceDate.isFinite else {
            throw ProjectDirectoryPresentationFailure.invalidAsOf
        }
        let expectedFingerprint = try Self.makeEvidenceFingerprint(
            accountId: accountId,
            segment: segment,
            rows: rows,
            sourceDirectoryFingerprint: sourceDirectoryFingerprint,
            sourceDirectoryRowCount: sourceDirectoryRowCount,
            visibleRowCountBeforeFiltering: visibleRowCountBeforeFiltering,
            isCompleteForQuery: isCompleteForQuery,
            quality: quality,
            localDataVersion: localDataVersion,
            asOf: asOf
        )
        guard evidenceFingerprint == expectedFingerprint else {
            throw ProjectDirectoryPresentationFailure.evidenceFingerprintMismatch
        }
        self.accountId = accountId
        self.segment = segment
        self.rows = rows
        self.sourceDirectoryFingerprint = sourceDirectoryFingerprint
        self.sourceDirectoryRowCount = sourceDirectoryRowCount
        self.visibleRowCountBeforeFiltering = visibleRowCountBeforeFiltering
        self.isCompleteForQuery = isCompleteForQuery
        self.quality = quality
        self.localDataVersion = localDataVersion
        self.asOf = asOf
        self.evidenceFingerprint = evidenceFingerprint
    }

    public func selection(projectId: ProjectID) throws -> ProjectBrowsingSelection {
        guard let row = rows.first(where: { $0.projectId == projectId }) else {
            throw ProjectDirectoryPresentationFailure.projectNotSelectable
        }
        return try ProjectBrowsingSelection(
            accountId: accountId,
            segment: segment,
            row: row,
            directoryEvidenceFingerprint: evidenceFingerprint
        )
    }

    public init(from decoder: Decoder) throws {
        do {
            let unbounded = try decoder.container(keyedBy: ProjectDirectoryCodingKey.self)
            guard Set(unbounded.allKeys.map(\.stringValue))
                    == Set(CodingKeys.allCases.map(\.rawValue)) else {
                throw ProjectDirectoryPresentationFailure.invalidEncodedPresentation
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                accountId: container.decode(AccountID.self, forKey: .accountId),
                segment: container.decode(ProjectDirectorySegment.self, forKey: .segment),
                rows: container.decode([ProjectDirectoryCoreRow].self, forKey: .rows),
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
                evidenceFingerprint: container.decode(
                    ProjectDirectoryEvidenceFingerprint.self,
                    forKey: .evidenceFingerprint
                )
            )
        } catch let failure as ProjectDirectoryPresentationFailure {
            throw failure
        } catch {
            throw ProjectDirectoryPresentationFailure.invalidEncodedPresentation
        }
    }

    private static func makeEvidenceFingerprint(
        accountId: AccountID,
        segment: ProjectDirectorySegment,
        rows: [ProjectDirectoryCoreRow],
        sourceDirectoryFingerprint: ListQueryFingerprint,
        sourceDirectoryRowCount: Int,
        visibleRowCountBeforeFiltering: Int,
        isCompleteForQuery: Bool,
        quality: ListSnapshotQuality,
        localDataVersion: LocalDataVersion,
        asOf: Date
    ) throws -> ProjectDirectoryEvidenceFingerprint {
        do {
            let basis = EvidenceFingerprintBasis(
                contractVersion: "project-directory-presentation-evidence-v1",
                accountId: accountId,
                segment: segment,
                rows: rows,
                sourceDirectoryFingerprint: sourceDirectoryFingerprint,
                sourceDirectoryRowCount: sourceDirectoryRowCount,
                visibleRowCountBeforeFiltering: visibleRowCountBeforeFiltering,
                isCompleteForQuery: isCompleteForQuery,
                quality: quality,
                localDataVersion: localDataVersion,
                asOf: asOf
            )
            let bytes = try OperationContractCodec.encode(basis)
            let digest = SHA256.hash(data: bytes)
                .map { String(format: "%02x", $0) }
                .joined()
            return try ProjectDirectoryEvidenceFingerprint(validating: digest)
        } catch let failure as ProjectDirectoryPresentationFailure {
            throw failure
        } catch {
            throw ProjectDirectoryPresentationFailure.invalidEncodedPresentation
        }
    }

    private struct EvidenceFingerprintBasis: Codable {
        let contractVersion: String
        let accountId: AccountID
        let segment: ProjectDirectorySegment
        let rows: [ProjectDirectoryCoreRow]
        let sourceDirectoryFingerprint: ListQueryFingerprint
        let sourceDirectoryRowCount: Int
        let visibleRowCountBeforeFiltering: Int
        let isCompleteForQuery: Bool
        let quality: ListSnapshotQuality
        let localDataVersion: LocalDataVersion
        let asOf: Date
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case accountId
        case segment
        case rows
        case sourceDirectoryFingerprint
        case sourceDirectoryRowCount
        case visibleRowCountBeforeFiltering
        case isCompleteForQuery
        case quality
        case localDataVersion
        case asOf
        case evidenceFingerprint
    }
}

public enum ProjectDirectoryPresentationProjector {
    public static func project(
        _ snapshot: ProjectListSnapshot,
        segment: ProjectDirectorySegment
    ) throws -> ProjectDirectoryPresentationSnapshot {
        try ProjectDirectoryPresentationSnapshot(snapshot: snapshot, segment: segment)
    }
}

public struct ProjectBrowsingSelection: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let segment: ProjectDirectorySegment
    public let row: ProjectDirectoryCoreRow
    public let directoryEvidenceFingerprint: ProjectDirectoryEvidenceFingerprint
    public let selectionFingerprint: ProjectBrowsingSelectionFingerprint

    fileprivate init(
        accountId: AccountID,
        segment: ProjectDirectorySegment,
        row: ProjectDirectoryCoreRow,
        directoryEvidenceFingerprint: ProjectDirectoryEvidenceFingerprint
    ) throws {
        let selectionFingerprint = try Self.makeSelectionFingerprint(
            accountId: accountId,
            segment: segment,
            row: row,
            directoryEvidenceFingerprint: directoryEvidenceFingerprint
        )
        self.accountId = accountId
        self.segment = segment
        self.row = row
        self.directoryEvidenceFingerprint = directoryEvidenceFingerprint
        self.selectionFingerprint = selectionFingerprint
    }

    public func detailRequest(
        validating currentSnapshot: ProjectDirectoryPresentationSnapshot
    ) throws -> ProjectCoreDetailsRequest {
        guard accountId == currentSnapshot.accountId,
              segment == currentSnapshot.segment,
              directoryEvidenceFingerprint == currentSnapshot.evidenceFingerprint,
              currentSnapshot.rows.contains(row) else {
            throw ProjectDirectoryPresentationFailure.selectionSnapshotMismatch
        }
        return try ProjectCoreDetailsRequest(accountId: accountId, projectId: row.projectId)
    }

    public init(from decoder: Decoder) throws {
        do {
            let unbounded = try decoder.container(keyedBy: ProjectDirectoryCodingKey.self)
            guard Set(unbounded.allKeys.map(\.stringValue))
                    == Set(CodingKeys.allCases.map(\.rawValue)) else {
                throw ProjectDirectoryPresentationFailure.invalidEncodedSelection
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let segment = try container.decode(ProjectDirectorySegment.self, forKey: .segment)
            let row = try container.decode(ProjectDirectoryCoreRow.self, forKey: .row)
            guard row.projectLifecycle == segment.lifecycle else {
                throw ProjectDirectoryPresentationFailure.segmentLifecycleMismatch
            }
            let accountId = try container.decode(AccountID.self, forKey: .accountId)
            let directoryEvidenceFingerprint = try container.decode(
                ProjectDirectoryEvidenceFingerprint.self,
                forKey: .directoryEvidenceFingerprint
            )
            let encodedSelectionFingerprint = try container.decode(
                ProjectBrowsingSelectionFingerprint.self,
                forKey: .selectionFingerprint
            )
            try self.init(
                accountId: accountId,
                segment: segment,
                row: row,
                directoryEvidenceFingerprint: directoryEvidenceFingerprint
            )
            guard selectionFingerprint == encodedSelectionFingerprint else {
                throw ProjectDirectoryPresentationFailure.selectionFingerprintMismatch
            }
        } catch let failure as ProjectDirectoryPresentationFailure {
            throw failure
        } catch {
            throw ProjectDirectoryPresentationFailure.invalidEncodedSelection
        }
    }

    private static func makeSelectionFingerprint(
        accountId: AccountID,
        segment: ProjectDirectorySegment,
        row: ProjectDirectoryCoreRow,
        directoryEvidenceFingerprint: ProjectDirectoryEvidenceFingerprint
    ) throws -> ProjectBrowsingSelectionFingerprint {
        do {
            let basis = SelectionFingerprintBasis(
                contractVersion: "project-browsing-selection-v1",
                accountId: accountId,
                segment: segment,
                row: row,
                directoryEvidenceFingerprint: directoryEvidenceFingerprint
            )
            let bytes = try OperationContractCodec.encode(basis)
            let digest = SHA256.hash(data: bytes)
                .map { String(format: "%02x", $0) }
                .joined()
            return try ProjectBrowsingSelectionFingerprint(validating: digest)
        } catch let failure as ProjectDirectoryPresentationFailure {
            throw failure
        } catch {
            throw ProjectDirectoryPresentationFailure.invalidEncodedSelection
        }
    }

    private struct SelectionFingerprintBasis: Codable {
        let contractVersion: String
        let accountId: AccountID
        let segment: ProjectDirectorySegment
        let row: ProjectDirectoryCoreRow
        let directoryEvidenceFingerprint: ProjectDirectoryEvidenceFingerprint
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case accountId
        case segment
        case row
        case directoryEvidenceFingerprint
        case selectionFingerprint
    }
}

private struct ProjectDirectoryCodingKey: CodingKey {
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
