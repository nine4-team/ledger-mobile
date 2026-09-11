import CryptoKit
import Foundation

public enum ClientBrowsingPresentationFailure: Error, Equatable, Sendable {
    case segmentLifecycleMismatch
    case duplicateClientIdentity
    case visibleCountMismatch
    case invalidCompleteness
    case invalidAsOf
    case invalidEvidenceFingerprint
    case invalidSelectionFingerprint
    case evidenceFingerprintMismatch
    case selectionFingerprintMismatch
    case clientNotSelectable
    case selectionSnapshotMismatch
    case updateRequestMismatch
    case invalidEncodedRow
    case invalidEncodedPresentation
    case invalidEncodedSelection

    public var diagnosticCode: String {
        switch self {
        case .segmentLifecycleMismatch: "client_browsing_lifecycle_mismatch"
        case .duplicateClientIdentity: "client_browsing_identity_duplicate"
        case .visibleCountMismatch: "client_browsing_visible_count_mismatch"
        case .invalidCompleteness: "client_browsing_completeness_invalid"
        case .invalidAsOf: "client_browsing_as_of_invalid"
        case .invalidEvidenceFingerprint: "client_browsing_evidence_fingerprint_invalid"
        case .invalidSelectionFingerprint: "client_browsing_selection_fingerprint_invalid"
        case .evidenceFingerprintMismatch: "client_browsing_evidence_fingerprint_mismatch"
        case .selectionFingerprintMismatch: "client_browsing_selection_fingerprint_mismatch"
        case .clientNotSelectable: "client_browsing_client_not_selectable"
        case .selectionSnapshotMismatch: "client_browsing_selection_snapshot_mismatch"
        case .updateRequestMismatch: "client_browsing_update_request_mismatch"
        case .invalidEncodedRow: "client_browsing_row_encoding_invalid"
        case .invalidEncodedPresentation: "client_browsing_presentation_encoding_invalid"
        case .invalidEncodedSelection: "client_browsing_selection_encoding_invalid"
        }
    }
}

public enum ClientDirectorySegment: String, Codable, CaseIterable, Sendable {
    case active
    case archived

    fileprivate var lifecycle: DirectoryLifecycleState {
        switch self {
        case .active: .active
        case .archived: .archived
        }
    }
}

public struct ClientDirectoryCoreRow: Codable, Equatable, Sendable {
    public let clientId: ClientID
    public let displayName: ClientDisplayName
    public let lifecycle: DirectoryLifecycleState
    public let createdAt: Date
    public let updatedAt: Date

    fileprivate init(client: ClientSummary) {
        clientId = client.id
        displayName = client.displayName
        lifecycle = client.lifecycle
        createdAt = client.createdAt
        updatedAt = client.updatedAt
    }

    public init(from decoder: Decoder) throws {
        do {
            let unbounded = try decoder.container(keyedBy: ClientBrowsingCodingKey.self)
            guard Set(unbounded.allKeys.map(\.stringValue))
                    == Set(CodingKeys.allCases.map(\.rawValue)) else {
                throw ClientBrowsingPresentationFailure.invalidEncodedRow
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let createdAt = try container.decode(Date.self, forKey: .createdAt)
            let updatedAt = try container.decode(Date.self, forKey: .updatedAt)
            guard createdAt.timeIntervalSinceReferenceDate.isFinite,
                  updatedAt.timeIntervalSinceReferenceDate.isFinite,
                  createdAt <= updatedAt else {
                throw ClientBrowsingPresentationFailure.invalidEncodedRow
            }
            clientId = try container.decode(ClientID.self, forKey: .clientId)
            displayName = try container.decode(ClientDisplayName.self, forKey: .displayName)
            lifecycle = try container.decode(DirectoryLifecycleState.self, forKey: .lifecycle)
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        } catch let failure as ClientBrowsingPresentationFailure {
            throw failure
        } catch {
            throw ClientBrowsingPresentationFailure.invalidEncodedRow
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case clientId, displayName, lifecycle, createdAt, updatedAt
    }
}

public struct ClientDirectoryEvidenceFingerprint: Codable, Equatable, Hashable, Sendable {
    public let sha256: String

    public init(validating sha256: String) throws {
        let hexadecimal = CharacterSet(charactersIn: "0123456789abcdef")
        guard sha256.utf8.count == 64,
              sha256.unicodeScalars.allSatisfy(hexadecimal.contains) else {
            throw ClientBrowsingPresentationFailure.invalidEvidenceFingerprint
        }
        self.sha256 = sha256
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            try self.init(validating: container.decode(String.self))
        } catch let failure as ClientBrowsingPresentationFailure {
            throw failure
        } catch {
            throw ClientBrowsingPresentationFailure.invalidEvidenceFingerprint
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(sha256)
    }
}

public struct ClientBrowsingSelectionFingerprint: Codable, Equatable, Hashable, Sendable {
    public let sha256: String

    public init(validating sha256: String) throws {
        let hexadecimal = CharacterSet(charactersIn: "0123456789abcdef")
        guard sha256.utf8.count == 64,
              sha256.unicodeScalars.allSatisfy(hexadecimal.contains) else {
            throw ClientBrowsingPresentationFailure.invalidSelectionFingerprint
        }
        self.sha256 = sha256
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            try self.init(validating: container.decode(String.self))
        } catch let failure as ClientBrowsingPresentationFailure {
            throw failure
        } catch {
            throw ClientBrowsingPresentationFailure.invalidSelectionFingerprint
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(sha256)
    }
}

public struct ClientDirectoryPresentationSnapshot: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let segment: ClientDirectorySegment
    public let rows: [ClientDirectoryCoreRow]
    public let sourceDirectoryFingerprint: ListQueryFingerprint
    public let sourceDirectoryRowCount: Int
    public let visibleRowCountBeforeFiltering: Int
    public let isCompleteForQuery: Bool
    public let quality: ListSnapshotQuality
    public let localDataVersion: LocalDataVersion
    public let asOf: Date
    public let evidenceFingerprint: ClientDirectoryEvidenceFingerprint

    public var readiness: ListReadiness { quality.readiness }
    public var isSourceExhaustive: Bool {
        sourceDirectoryRowCount == visibleRowCountBeforeFiltering
    }
    public var isAuthoritativeEmpty: Bool {
        rows.isEmpty && quality == .ready && isCompleteForQuery && isSourceExhaustive
    }

    fileprivate init(snapshot: ClientListSnapshot, segment: ClientDirectorySegment) throws {
        let rows = snapshot.local.rows
            .filter { $0.lifecycle == segment.lifecycle }
            .map(ClientDirectoryCoreRow.init(client:))
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
        segment: ClientDirectorySegment,
        rows: [ClientDirectoryCoreRow],
        sourceDirectoryFingerprint: ListQueryFingerprint,
        sourceDirectoryRowCount: Int,
        visibleRowCountBeforeFiltering: Int,
        isCompleteForQuery: Bool,
        quality: ListSnapshotQuality,
        localDataVersion: LocalDataVersion,
        asOf: Date,
        evidenceFingerprint: ClientDirectoryEvidenceFingerprint
    ) throws {
        guard rows.allSatisfy({ $0.lifecycle == segment.lifecycle }) else {
            throw ClientBrowsingPresentationFailure.segmentLifecycleMismatch
        }
        guard Set(rows.map(\.clientId)).count == rows.count else {
            throw ClientBrowsingPresentationFailure.duplicateClientIdentity
        }
        guard sourceDirectoryRowCount >= rows.count,
              sourceDirectoryRowCount >= 0,
              visibleRowCountBeforeFiltering >= sourceDirectoryRowCount else {
            throw ClientBrowsingPresentationFailure.visibleCountMismatch
        }
        guard quality == .ready || !isCompleteForQuery else {
            throw ClientBrowsingPresentationFailure.invalidCompleteness
        }
        guard asOf.timeIntervalSinceReferenceDate.isFinite else {
            throw ClientBrowsingPresentationFailure.invalidAsOf
        }
        let expected = try Self.makeEvidenceFingerprint(
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
        guard evidenceFingerprint == expected else {
            throw ClientBrowsingPresentationFailure.evidenceFingerprintMismatch
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

    public func selection(clientId: ClientID) throws -> ClientBrowsingSelection {
        guard let row = rows.first(where: { $0.clientId == clientId }) else {
            throw ClientBrowsingPresentationFailure.clientNotSelectable
        }
        return try ClientBrowsingSelection(
            accountId: accountId,
            segment: segment,
            row: row,
            directoryEvidenceFingerprint: evidenceFingerprint
        )
    }

    public init(from decoder: Decoder) throws {
        do {
            let unbounded = try decoder.container(keyedBy: ClientBrowsingCodingKey.self)
            guard Set(unbounded.allKeys.map(\.stringValue))
                    == Set(CodingKeys.allCases.map(\.rawValue)) else {
                throw ClientBrowsingPresentationFailure.invalidEncodedPresentation
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                accountId: container.decode(AccountID.self, forKey: .accountId),
                segment: container.decode(ClientDirectorySegment.self, forKey: .segment),
                rows: container.decode([ClientDirectoryCoreRow].self, forKey: .rows),
                sourceDirectoryFingerprint: container.decode(
                    ListQueryFingerprint.self,
                    forKey: .sourceDirectoryFingerprint
                ),
                sourceDirectoryRowCount: container.decode(Int.self, forKey: .sourceDirectoryRowCount),
                visibleRowCountBeforeFiltering: container.decode(
                    Int.self,
                    forKey: .visibleRowCountBeforeFiltering
                ),
                isCompleteForQuery: container.decode(Bool.self, forKey: .isCompleteForQuery),
                quality: container.decode(ListSnapshotQuality.self, forKey: .quality),
                localDataVersion: container.decode(LocalDataVersion.self, forKey: .localDataVersion),
                asOf: container.decode(Date.self, forKey: .asOf),
                evidenceFingerprint: container.decode(
                    ClientDirectoryEvidenceFingerprint.self,
                    forKey: .evidenceFingerprint
                )
            )
        } catch let failure as ClientBrowsingPresentationFailure {
            throw failure
        } catch {
            throw ClientBrowsingPresentationFailure.invalidEncodedPresentation
        }
    }

    private static func makeEvidenceFingerprint(
        accountId: AccountID,
        segment: ClientDirectorySegment,
        rows: [ClientDirectoryCoreRow],
        sourceDirectoryFingerprint: ListQueryFingerprint,
        sourceDirectoryRowCount: Int,
        visibleRowCountBeforeFiltering: Int,
        isCompleteForQuery: Bool,
        quality: ListSnapshotQuality,
        localDataVersion: LocalDataVersion,
        asOf: Date
    ) throws -> ClientDirectoryEvidenceFingerprint {
        do {
            let basis = EvidenceFingerprintBasis(
                contractVersion: "client-directory-presentation-evidence-v1",
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
            let digest = SHA256.hash(data: try OperationContractCodec.encode(basis))
                .map { String(format: "%02x", $0) }
                .joined()
            return try ClientDirectoryEvidenceFingerprint(validating: digest)
        } catch let failure as ClientBrowsingPresentationFailure {
            throw failure
        } catch {
            throw ClientBrowsingPresentationFailure.invalidEncodedPresentation
        }
    }

    private struct EvidenceFingerprintBasis: Codable {
        let contractVersion: String
        let accountId: AccountID
        let segment: ClientDirectorySegment
        let rows: [ClientDirectoryCoreRow]
        let sourceDirectoryFingerprint: ListQueryFingerprint
        let sourceDirectoryRowCount: Int
        let visibleRowCountBeforeFiltering: Int
        let isCompleteForQuery: Bool
        let quality: ListSnapshotQuality
        let localDataVersion: LocalDataVersion
        let asOf: Date
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case accountId, segment, rows, sourceDirectoryFingerprint, sourceDirectoryRowCount
        case visibleRowCountBeforeFiltering, isCompleteForQuery, quality, localDataVersion, asOf
        case evidenceFingerprint
    }
}

public struct ClientBrowsingDirectoryPresentation: Equatable, Sendable {
    public let active: ClientDirectoryPresentationSnapshot
    public let archived: ClientDirectoryPresentationSnapshot

    fileprivate init(snapshot: ClientListSnapshot) throws {
        active = try ClientDirectoryPresentationSnapshot(snapshot: snapshot, segment: .active)
        archived = try ClientDirectoryPresentationSnapshot(snapshot: snapshot, segment: .archived)
    }

    public var readiness: ListReadiness { active.readiness }
    public var isCompleteForQuery: Bool { active.isCompleteForQuery }
    public var isSourceExhaustive: Bool { active.isSourceExhaustive }
}

public enum ClientDirectoryPresentationProjector {
    public static func project(_ snapshot: ClientListSnapshot) throws
        -> ClientBrowsingDirectoryPresentation
    {
        try ClientBrowsingDirectoryPresentation(snapshot: snapshot)
    }
}

public struct ClientBrowsingSelection: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let segment: ClientDirectorySegment
    public let row: ClientDirectoryCoreRow
    public let directoryEvidenceFingerprint: ClientDirectoryEvidenceFingerprint
    public let selectionFingerprint: ClientBrowsingSelectionFingerprint

    fileprivate init(
        accountId: AccountID,
        segment: ClientDirectorySegment,
        row: ClientDirectoryCoreRow,
        directoryEvidenceFingerprint: ClientDirectoryEvidenceFingerprint
    ) throws {
        let fingerprint = try Self.makeSelectionFingerprint(
            accountId: accountId,
            segment: segment,
            row: row,
            directoryEvidenceFingerprint: directoryEvidenceFingerprint
        )
        self.accountId = accountId
        self.segment = segment
        self.row = row
        self.directoryEvidenceFingerprint = directoryEvidenceFingerprint
        selectionFingerprint = fingerprint
    }

    public func detailRequest(
        validating currentSnapshot: ClientDirectoryPresentationSnapshot
    ) throws -> ClientCoreDetailsRequest {
        guard accountId == currentSnapshot.accountId,
              segment == currentSnapshot.segment,
              directoryEvidenceFingerprint == currentSnapshot.evidenceFingerprint,
              currentSnapshot.rows.contains(row) else {
            throw ClientBrowsingPresentationFailure.selectionSnapshotMismatch
        }
        return try ClientCoreDetailsRequest(accountId: accountId, clientId: row.clientId)
    }

    public init(from decoder: Decoder) throws {
        do {
            let unbounded = try decoder.container(keyedBy: ClientBrowsingCodingKey.self)
            guard Set(unbounded.allKeys.map(\.stringValue))
                    == Set(CodingKeys.allCases.map(\.rawValue)) else {
                throw ClientBrowsingPresentationFailure.invalidEncodedSelection
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let segment = try container.decode(ClientDirectorySegment.self, forKey: .segment)
            let row = try container.decode(ClientDirectoryCoreRow.self, forKey: .row)
            guard row.lifecycle == segment.lifecycle else {
                throw ClientBrowsingPresentationFailure.segmentLifecycleMismatch
            }
            let accountId = try container.decode(AccountID.self, forKey: .accountId)
            let directoryFingerprint = try container.decode(
                ClientDirectoryEvidenceFingerprint.self,
                forKey: .directoryEvidenceFingerprint
            )
            let encoded = try container.decode(
                ClientBrowsingSelectionFingerprint.self,
                forKey: .selectionFingerprint
            )
            try self.init(
                accountId: accountId,
                segment: segment,
                row: row,
                directoryEvidenceFingerprint: directoryFingerprint
            )
            guard selectionFingerprint == encoded else {
                throw ClientBrowsingPresentationFailure.selectionFingerprintMismatch
            }
        } catch let failure as ClientBrowsingPresentationFailure {
            throw failure
        } catch {
            throw ClientBrowsingPresentationFailure.invalidEncodedSelection
        }
    }

    private static func makeSelectionFingerprint(
        accountId: AccountID,
        segment: ClientDirectorySegment,
        row: ClientDirectoryCoreRow,
        directoryEvidenceFingerprint: ClientDirectoryEvidenceFingerprint
    ) throws -> ClientBrowsingSelectionFingerprint {
        do {
            let basis = SelectionFingerprintBasis(
                contractVersion: "client-browsing-selection-v1",
                accountId: accountId,
                segment: segment,
                row: row,
                directoryEvidenceFingerprint: directoryEvidenceFingerprint
            )
            let digest = SHA256.hash(data: try OperationContractCodec.encode(basis))
                .map { String(format: "%02x", $0) }
                .joined()
            return try ClientBrowsingSelectionFingerprint(validating: digest)
        } catch let failure as ClientBrowsingPresentationFailure {
            throw failure
        } catch {
            throw ClientBrowsingPresentationFailure.invalidEncodedSelection
        }
    }

    private struct SelectionFingerprintBasis: Codable {
        let contractVersion: String
        let accountId: AccountID
        let segment: ClientDirectorySegment
        let row: ClientDirectoryCoreRow
        let directoryEvidenceFingerprint: ClientDirectoryEvidenceFingerprint
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case accountId, segment, row, directoryEvidenceFingerprint, selectionFingerprint
    }
}

public struct ClientDetailPresentationContent: Equatable, Sendable {
    public let clientId: ClientID
    public let displayName: ClientDisplayName
    public let lifecycle: DirectoryLifecycleState
    public let createdAt: Date
    public let updatedAt: Date
    public let locallyObservedRevision: ExpectedClientRevision
    public let observedRevisionIsFromCompleteReadySnapshot: Bool
    public let sourceQuality: ListSnapshotQuality
    public let readiness: ListReadiness
    public let localDataVersion: LocalDataVersion
    public let asOf: Date

    fileprivate init(
        snapshot: ClientCoreDetailsLocalSnapshot,
        row: ClientCoreDetailsSnapshot,
        displayedReadiness: ListReadiness
    ) {
        clientId = row.client.id
        displayName = row.client.displayName
        lifecycle = row.client.lifecycle
        createdAt = row.client.createdAt
        updatedAt = row.client.updatedAt
        locallyObservedRevision = row.locallyObservedRevision
        observedRevisionIsFromCompleteReadySnapshot =
            snapshot.observedRevisionIsFromCompleteReadySnapshot
        sourceQuality = snapshot.local.quality
        readiness = displayedReadiness
        localDataVersion = snapshot.local.localDataVersion
        asOf = snapshot.local.asOf
    }
}

public enum ClientDetailPresentationState: Equatable, Sendable {
    case waiting(ListReadiness)
    case found(ClientDetailPresentationContent)
    case incomplete(ListReadiness)
    case authoritativeAbsence
    case unavailable
    case retryable(cached: ClientDetailPresentationContent?)
    case requiredUpdate(cached: ClientDetailPresentationContent?)

    public var content: ClientDetailPresentationContent? {
        switch self {
        case .found(let content), .retryable(cached: .some(let content)),
             .requiredUpdate(cached: .some(let content)):
            content
        case .waiting, .incomplete, .authoritativeAbsence, .unavailable,
             .retryable(cached: .none), .requiredUpdate(cached: .none):
            nil
        }
    }
}

public struct ClientDetailPresentation: Equatable, Sendable {
    public let request: ClientCoreDetailsRequest
    public let state: ClientDetailPresentationState

    fileprivate init(request: ClientCoreDetailsRequest, state: ClientDetailPresentationState) {
        self.request = request
        self.state = state
    }
}

public enum ClientDetailPresentationProjector {
    public static func project(
        _ update: ClientCoreDetailsUpdate,
        validating request: ClientCoreDetailsRequest
    ) throws -> ClientDetailPresentation {
        do {
            let validated = try update.validating(request: request)
            let state: ClientDetailPresentationState
            switch validated.state {
            case .waiting(let readiness):
                state = .waiting(readiness)
            case .snapshot(let snapshot):
                if let row = snapshot.row {
                    state = .found(ClientDetailPresentationContent(
                        snapshot: snapshot,
                        row: row,
                        displayedReadiness: snapshot.local.quality.readiness
                    ))
                } else if snapshot.isAuthoritativeAbsence {
                    state = .authoritativeAbsence
                } else {
                    state = .incomplete(snapshot.local.quality.readiness)
                }
            case .failed(.unavailable, _):
                state = .unavailable
            case .failed(.retryable, let cached):
                state = .retryable(cached: staleContent(cached))
            case .failed(.requiredUpdate, let cached):
                state = .requiredUpdate(cached: staleContent(cached))
            }
            return ClientDetailPresentation(request: request, state: state)
        } catch ClientCoreDetailsFailure.updateRequestMismatch {
            throw ClientBrowsingPresentationFailure.updateRequestMismatch
        }
    }

    private static func staleContent(
        _ cached: ClientCoreDetailsLocalSnapshot?
    ) -> ClientDetailPresentationContent? {
        guard let cached, let row = cached.row else { return nil }
        return ClientDetailPresentationContent(
            snapshot: cached,
            row: row,
            displayedReadiness: .stale
        )
    }
}

private struct ClientBrowsingCodingKey: CodingKey {
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
