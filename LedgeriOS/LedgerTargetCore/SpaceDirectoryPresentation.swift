import CryptoKit
import Foundation

public enum SpaceListFailure: Error, Equatable, Sendable {
    case accountScopeMismatch
    case spaceScopeMismatch
    case inactiveSelection
    case missingSelection
    case selectionEvidenceMismatch
    case detailIdentityMismatch
    case duplicateSpaceIdentity
    case visibleCountMismatch
    case invalidSnapshotAsOf
    case invalidCompleteness
    case noncanonicalRows
    case requestFingerprintMismatch
    case queryFingerprintMismatch
    case presentationFingerprintMismatch
    case selectionFingerprintMismatch
    case updateRequestMismatch
    case invalidWaitingState
    case unavailableCachedEvidence
    case localReadFailed
    case invalidEncodedRequest
    case invalidEncodedSourceRow
    case invalidEncodedLocalSnapshot
    case invalidEncodedPresentationRow
    case invalidEncodedPresentation
    case invalidEncodedSelection
    case invalidEncodedUpdate

    public var diagnosticCode: String {
        switch self {
        case .accountScopeMismatch: "space_list_account_scope_mismatch"
        case .spaceScopeMismatch: "space_list_space_scope_mismatch"
        case .inactiveSelection: "space_list_selection_inactive"
        case .missingSelection: "space_list_selection_missing"
        case .selectionEvidenceMismatch: "space_list_selection_evidence_mismatch"
        case .detailIdentityMismatch: "space_list_detail_identity_mismatch"
        case .duplicateSpaceIdentity: "space_list_space_identity_duplicate"
        case .visibleCountMismatch: "space_list_visible_count_mismatch"
        case .invalidSnapshotAsOf: "space_list_as_of_invalid"
        case .invalidCompleteness: "space_list_completeness_invalid"
        case .noncanonicalRows: "space_list_rows_noncanonical"
        case .requestFingerprintMismatch: "space_list_request_fingerprint_mismatch"
        case .queryFingerprintMismatch: "space_list_query_fingerprint_mismatch"
        case .presentationFingerprintMismatch: "space_list_presentation_fingerprint_mismatch"
        case .selectionFingerprintMismatch: "space_list_selection_fingerprint_mismatch"
        case .updateRequestMismatch: "space_list_update_request_mismatch"
        case .invalidWaitingState: "space_list_waiting_state_invalid"
        case .unavailableCachedEvidence: "space_list_unavailable_cache_invalid"
        case .localReadFailed: "space_list_local_read_failed"
        case .invalidEncodedRequest: "space_list_request_encoding_invalid"
        case .invalidEncodedSourceRow: "space_list_source_row_encoding_invalid"
        case .invalidEncodedLocalSnapshot: "space_list_snapshot_encoding_invalid"
        case .invalidEncodedPresentationRow: "space_list_row_encoding_invalid"
        case .invalidEncodedPresentation: "space_list_presentation_encoding_invalid"
        case .invalidEncodedSelection: "space_list_selection_encoding_invalid"
        case .invalidEncodedUpdate: "space_list_update_encoding_invalid"
        }
    }
}

public struct SpaceListRequest: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let scope: SpaceCreationScope
    public let queryFingerprint: ListQueryFingerprint

    public init(accountId: AccountID, scope: SpaceCreationScope) throws {
        self.accountId = accountId
        self.scope = scope
        queryFingerprint = try Self.fingerprint(accountId: accountId, scope: scope)
    }

    public init(from decoder: Decoder) throws {
        do {
            try requireExactSpaceListKeys(decoder, CodingKeys.self)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let accountId = try container.decode(AccountID.self, forKey: .accountId)
            let scope = try container.decode(StrictSpaceCreationScope.self, forKey: .scope).value
            let encoded = try container.decode(ListQueryFingerprint.self, forKey: .queryFingerprint)
            try self.init(accountId: accountId, scope: scope)
            guard queryFingerprint == encoded else {
                throw SpaceListFailure.requestFingerprintMismatch
            }
        } catch let failure as SpaceListFailure {
            throw failure
        } catch {
            throw SpaceListFailure.invalidEncodedRequest
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accountId, forKey: .accountId)
        try container.encode(StrictSpaceCreationScope(scope), forKey: .scope)
        try container.encode(queryFingerprint, forKey: .queryFingerprint)
    }

    private static func fingerprint(
        accountId: AccountID,
        scope: SpaceCreationScope
    ) throws -> ListQueryFingerprint {
        do {
            return try spaceListFingerprint(FingerprintBasis(
                contractVersion: "space-list-request-v1",
                accountId: accountId,
                scope: scope
            ))
        } catch {
            throw SpaceListFailure.invalidEncodedRequest
        }
    }

    private struct FingerprintBasis: Codable {
        let contractVersion: String
        let accountId: AccountID
        let scope: SpaceCreationScope
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case accountId
        case scope
        case queryFingerprint
    }
}

public struct SpaceListSourceRow: Codable, Equatable, Sendable {
    public let id: SpaceID
    public let accountId: AccountID
    public let scope: SpaceCreationScope
    public let displayName: SpaceDisplayName
    public let lifecycle: DirectoryLifecycleState
    public let revision: UInt64
    public let checklists: SpaceChecklistCollection

    public var completedChecklistItemCount: Int { checklists.completedItemCount }
    public var totalChecklistItemCount: Int { checklists.totalItemCount }

    public init(
        id: SpaceID,
        accountId: AccountID,
        scope: SpaceCreationScope,
        displayName: SpaceDisplayName,
        lifecycle: DirectoryLifecycleState,
        revision: UInt64,
        checklists: SpaceChecklistCollection
    ) {
        self.id = id
        self.accountId = accountId
        self.scope = scope
        self.displayName = displayName
        self.lifecycle = lifecycle
        self.revision = revision
        self.checklists = checklists
    }

    public init(from decoder: Decoder) throws {
        do {
            try requireExactSpaceListKeys(decoder, CodingKeys.self)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                id: try container.decode(SpaceID.self, forKey: .id),
                accountId: try container.decode(AccountID.self, forKey: .accountId),
                scope: try container.decode(StrictSpaceCreationScope.self, forKey: .scope).value,
                displayName: try container.decode(SpaceDisplayName.self, forKey: .displayName),
                lifecycle: try container.decode(DirectoryLifecycleState.self, forKey: .lifecycle),
                revision: try container.decode(UInt64.self, forKey: .revision),
                checklists: try container.decode(
                    StrictSpaceChecklistCollection.self,
                    forKey: .checklists
                ).value
            )
        } catch {
            throw SpaceListFailure.invalidEncodedSourceRow
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(accountId, forKey: .accountId)
        try container.encode(StrictSpaceCreationScope(scope), forKey: .scope)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(lifecycle, forKey: .lifecycle)
        try container.encode(revision, forKey: .revision)
        try container.encode(StrictSpaceChecklistCollection(checklists), forKey: .checklists)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, accountId, scope, displayName, lifecycle, revision, checklists
    }
}

public struct SpaceListLocalSnapshot: Codable, Equatable, Sendable {
    public let request: SpaceListRequest
    public let local: ListLocalSnapshot<SpaceListSourceRow>

    public init(
        request: SpaceListRequest,
        rows: [SpaceListSourceRow],
        visibleRowCountBeforeFiltering: Int,
        isCompleteForQuery: Bool,
        quality: ListSnapshotQuality,
        localDataVersion: LocalDataVersion,
        asOf: Date
    ) throws {
        do {
            try self.init(
                request: request,
                local: ListLocalSnapshot(
                    queryFingerprint: request.queryFingerprint,
                    rows: rows,
                    visibleRowCountBeforeFiltering: visibleRowCountBeforeFiltering,
                    isCompleteForQuery: isCompleteForQuery,
                    quality: quality,
                    localDataVersion: localDataVersion,
                    asOf: asOf
                )
            )
        } catch let failure as SpaceListFailure {
            throw failure
        } catch ListQueryContractFailure.invalidVisibleRowCount {
            throw SpaceListFailure.visibleCountMismatch
        } catch ListQueryContractFailure.incompleteAuthoritativeEmpty {
            throw SpaceListFailure.invalidCompleteness
        } catch {
            throw SpaceListFailure.invalidEncodedLocalSnapshot
        }
    }

    public init(
        request: SpaceListRequest,
        local: ListLocalSnapshot<SpaceListSourceRow>
    ) throws {
        guard local.asOf.timeIntervalSinceReferenceDate.isFinite else {
            throw SpaceListFailure.invalidSnapshotAsOf
        }
        guard local.queryFingerprint == request.queryFingerprint else {
            throw SpaceListFailure.queryFingerprintMismatch
        }
        guard local.visibleRowCountBeforeFiltering == local.rows.count else {
            throw SpaceListFailure.visibleCountMismatch
        }
        guard local.rows.allSatisfy({ $0.accountId == request.accountId }) else {
            throw SpaceListFailure.accountScopeMismatch
        }
        guard local.rows.allSatisfy({ $0.scope == request.scope }) else {
            throw SpaceListFailure.spaceScopeMismatch
        }
        guard firstDuplicateSpaceListValue(local.rows.map(\.id)) == nil else {
            throw SpaceListFailure.duplicateSpaceIdentity
        }

        self.request = request
        self.local = try ListLocalSnapshot(
            queryFingerprint: local.queryFingerprint,
            rows: local.rows.sorted(by: spaceListRowPrecedes),
            visibleRowCountBeforeFiltering: local.visibleRowCountBeforeFiltering,
            isCompleteForQuery: local.isCompleteForQuery,
            quality: local.quality,
            localDataVersion: local.localDataVersion,
            asOf: local.asOf
        )
    }

    public init(from decoder: Decoder) throws {
        do {
            try requireExactSpaceListKeys(decoder, CodingKeys.self)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let request = try container.decode(SpaceListRequest.self, forKey: .request)
            let encodedLocal = try container.decode(
                StrictSpaceListLocalSnapshot.self,
                forKey: .local
            ).value
            try self.init(request: request, local: encodedLocal)
            guard local == encodedLocal else { throw SpaceListFailure.noncanonicalRows }
        } catch let failure as SpaceListFailure {
            throw failure
        } catch ListQueryContractFailure.incompleteAuthoritativeEmpty {
            throw SpaceListFailure.invalidCompleteness
        } catch ListQueryContractFailure.invalidVisibleRowCount {
            throw SpaceListFailure.visibleCountMismatch
        } catch {
            throw SpaceListFailure.invalidEncodedLocalSnapshot
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(request, forKey: .request)
        try container.encode(StrictSpaceListLocalSnapshot(local), forKey: .local)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case request, local }
}

public enum SpaceDirectoryItemCountState: String, Codable, CaseIterable, Sendable {
    case unavailable
}

public struct SpaceDirectoryRowPresentation: Codable, Equatable, Sendable {
    public let id: SpaceID
    public let accountId: AccountID
    public let scope: SpaceCreationScope
    public let displayName: SpaceDisplayName
    public let lifecycle: DirectoryLifecycleState
    public let revision: UInt64
    public let checklists: SpaceChecklistCollection
    public let itemCountState: SpaceDirectoryItemCountState

    public var completedChecklistItemCount: Int { checklists.completedItemCount }
    public var totalChecklistItemCount: Int { checklists.totalItemCount }

    public init(sourceRow: SpaceListSourceRow) throws {
        guard sourceRow.lifecycle == .active else {
            throw SpaceListFailure.inactiveSelection
        }
        id = sourceRow.id
        accountId = sourceRow.accountId
        scope = sourceRow.scope
        displayName = sourceRow.displayName
        lifecycle = sourceRow.lifecycle
        revision = sourceRow.revision
        checklists = sourceRow.checklists
        itemCountState = .unavailable
    }

    public init(from decoder: Decoder) throws {
        do {
            try requireExactSpaceListKeys(decoder, CodingKeys.self)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let itemCountState = try container.decode(
                SpaceDirectoryItemCountState.self,
                forKey: .itemCountState
            )
            guard itemCountState == .unavailable else {
                throw SpaceListFailure.invalidEncodedPresentationRow
            }
            try self.init(sourceRow: SpaceListSourceRow(
                id: try container.decode(SpaceID.self, forKey: .id),
                accountId: try container.decode(AccountID.self, forKey: .accountId),
                scope: try container.decode(StrictSpaceCreationScope.self, forKey: .scope).value,
                displayName: try container.decode(SpaceDisplayName.self, forKey: .displayName),
                lifecycle: try container.decode(DirectoryLifecycleState.self, forKey: .lifecycle),
                revision: try container.decode(UInt64.self, forKey: .revision),
                checklists: try container.decode(
                    StrictSpaceChecklistCollection.self,
                    forKey: .checklists
                ).value
            ))
        } catch let failure as SpaceListFailure {
            throw failure
        } catch {
            throw SpaceListFailure.invalidEncodedPresentationRow
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(accountId, forKey: .accountId)
        try container.encode(StrictSpaceCreationScope(scope), forKey: .scope)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(lifecycle, forKey: .lifecycle)
        try container.encode(revision, forKey: .revision)
        try container.encode(StrictSpaceChecklistCollection(checklists), forKey: .checklists)
        try container.encode(itemCountState, forKey: .itemCountState)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, accountId, scope, displayName, lifecycle, revision, checklists, itemCountState
    }
}

public struct ActiveSpaceDirectoryPresentationSnapshot: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let scope: SpaceCreationScope
    public let sourceRows: [SpaceListSourceRow]
    public let rows: [SpaceDirectoryRowPresentation]
    public let sourceQueryFingerprint: ListQueryFingerprint
    public let sourceRowCount: Int
    public let visibleRowCountBeforeFiltering: Int
    public let isCompleteForQuery: Bool
    public let quality: ListSnapshotQuality
    public let localDataVersion: LocalDataVersion
    public let asOf: Date
    public let evidenceFingerprint: ListQueryFingerprint

    public var readiness: ListReadiness { quality.readiness }
    public var isAuthoritativeEmpty: Bool {
        rows.isEmpty && quality == .ready && isCompleteForQuery
            && sourceRowCount == visibleRowCountBeforeFiltering
    }

    public init(source: SpaceListLocalSnapshot) throws {
        accountId = source.request.accountId
        scope = source.request.scope
        sourceRows = source.local.rows
        rows = try source.local.rows.filter { $0.lifecycle == .active }
            .map(SpaceDirectoryRowPresentation.init(sourceRow:))
        sourceQueryFingerprint = source.request.queryFingerprint
        sourceRowCount = source.local.rows.count
        visibleRowCountBeforeFiltering = source.local.visibleRowCountBeforeFiltering
        isCompleteForQuery = source.local.isCompleteForQuery
        quality = source.local.quality
        localDataVersion = source.local.localDataVersion
        asOf = source.local.asOf
        evidenceFingerprint = try Self.fingerprint(
            accountId: accountId,
            scope: scope,
            sourceRows: sourceRows,
            rows: rows,
            sourceQueryFingerprint: sourceQueryFingerprint,
            sourceRowCount: sourceRowCount,
            visibleRowCountBeforeFiltering: visibleRowCountBeforeFiltering,
            isCompleteForQuery: isCompleteForQuery,
            quality: quality,
            localDataVersion: localDataVersion,
            asOf: asOf
        )
    }

    public init(from decoder: Decoder) throws {
        do {
            try requireExactSpaceListKeys(decoder, CodingKeys.self)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let accountId = try container.decode(AccountID.self, forKey: .accountId)
            let scope = try container.decode(StrictSpaceCreationScope.self, forKey: .scope).value
            let sourceRows = try container.decode([SpaceListSourceRow].self, forKey: .sourceRows)
            let rows = try container.decode([SpaceDirectoryRowPresentation].self, forKey: .rows)
            let sourceQueryFingerprint = try container.decode(
                ListQueryFingerprint.self,
                forKey: .sourceQueryFingerprint
            )
            let sourceRowCount = try container.decode(Int.self, forKey: .sourceRowCount)
            let visibleCount = try container.decode(
                Int.self,
                forKey: .visibleRowCountBeforeFiltering
            )
            let complete = try container.decode(Bool.self, forKey: .isCompleteForQuery)
            let quality = try container.decode(ListSnapshotQuality.self, forKey: .quality)
            let version = try container.decode(LocalDataVersion.self, forKey: .localDataVersion)
            let asOf = try container.decode(Date.self, forKey: .asOf)
            let encodedFingerprint = try container.decode(
                ListQueryFingerprint.self,
                forKey: .evidenceFingerprint
            )

            guard sourceRowCount == sourceRows.count else {
                throw SpaceListFailure.visibleCountMismatch
            }
            let request = try SpaceListRequest(accountId: accountId, scope: scope)
            guard request.queryFingerprint == sourceQueryFingerprint else {
                throw SpaceListFailure.queryFingerprintMismatch
            }
            let source = try SpaceListLocalSnapshot(
                request: request,
                rows: sourceRows,
                visibleRowCountBeforeFiltering: visibleCount,
                isCompleteForQuery: complete,
                quality: quality,
                localDataVersion: version,
                asOf: asOf
            )
            try self.init(source: source)
            guard self.sourceRows == sourceRows, self.rows == rows else {
                throw SpaceListFailure.noncanonicalRows
            }
            guard evidenceFingerprint == encodedFingerprint else {
                throw SpaceListFailure.presentationFingerprintMismatch
            }
        } catch let failure as SpaceListFailure {
            throw failure
        } catch {
            throw SpaceListFailure.invalidEncodedPresentation
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accountId, forKey: .accountId)
        try container.encode(StrictSpaceCreationScope(scope), forKey: .scope)
        try container.encode(sourceRows, forKey: .sourceRows)
        try container.encode(rows, forKey: .rows)
        try container.encode(sourceQueryFingerprint, forKey: .sourceQueryFingerprint)
        try container.encode(sourceRowCount, forKey: .sourceRowCount)
        try container.encode(
            visibleRowCountBeforeFiltering,
            forKey: .visibleRowCountBeforeFiltering
        )
        try container.encode(isCompleteForQuery, forKey: .isCompleteForQuery)
        try container.encode(quality, forKey: .quality)
        try container.encode(localDataVersion, forKey: .localDataVersion)
        try container.encode(asOf, forKey: .asOf)
        try container.encode(evidenceFingerprint, forKey: .evidenceFingerprint)
    }

    private static func fingerprint(
        accountId: AccountID,
        scope: SpaceCreationScope,
        sourceRows: [SpaceListSourceRow],
        rows: [SpaceDirectoryRowPresentation],
        sourceQueryFingerprint: ListQueryFingerprint,
        sourceRowCount: Int,
        visibleRowCountBeforeFiltering: Int,
        isCompleteForQuery: Bool,
        quality: ListSnapshotQuality,
        localDataVersion: LocalDataVersion,
        asOf: Date
    ) throws -> ListQueryFingerprint {
        try spaceListFingerprint(FingerprintBasis(
            contractVersion: "space-list-presentation-evidence-v1",
            accountId: accountId,
            scope: scope,
            sourceRows: sourceRows,
            rows: rows,
            sourceQueryFingerprint: sourceQueryFingerprint,
            sourceRowCount: sourceRowCount,
            visibleRowCountBeforeFiltering: visibleRowCountBeforeFiltering,
            isCompleteForQuery: isCompleteForQuery,
            quality: quality,
            localDataVersion: localDataVersion,
            asOf: asOf
        ))
    }

    private struct FingerprintBasis: Codable {
        let contractVersion: String
        let accountId: AccountID
        let scope: SpaceCreationScope
        let sourceRows: [SpaceListSourceRow]
        let rows: [SpaceDirectoryRowPresentation]
        let sourceQueryFingerprint: ListQueryFingerprint
        let sourceRowCount: Int
        let visibleRowCountBeforeFiltering: Int
        let isCompleteForQuery: Bool
        let quality: ListSnapshotQuality
        let localDataVersion: LocalDataVersion
        let asOf: Date
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case accountId, scope, sourceRows, rows, sourceQueryFingerprint, sourceRowCount
        case visibleRowCountBeforeFiltering, isCompleteForQuery, quality, localDataVersion
        case asOf, evidenceFingerprint
    }
}

public struct SpaceBrowsingSelection: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let scope: SpaceCreationScope
    public let row: SpaceDirectoryRowPresentation
    public let directoryEvidenceFingerprint: ListQueryFingerprint
    public let selectionFingerprint: ListQueryFingerprint

    public init(
        selecting spaceId: SpaceID,
        in directory: ActiveSpaceDirectoryPresentationSnapshot
    ) throws {
        guard let row = directory.rows.first(where: { $0.id == spaceId }) else {
            throw SpaceListFailure.missingSelection
        }
        guard row.lifecycle == .active else { throw SpaceListFailure.inactiveSelection }
        accountId = directory.accountId
        scope = directory.scope
        self.row = row
        directoryEvidenceFingerprint = directory.evidenceFingerprint
        selectionFingerprint = try Self.fingerprint(
            accountId: accountId,
            scope: scope,
            row: row,
            directoryEvidenceFingerprint: directoryEvidenceFingerprint
        )
    }

    public func detailRequest(
        validating directory: ActiveSpaceDirectoryPresentationSnapshot
    ) throws -> SpaceCoreDetailsRequest {
        guard directory.accountId == accountId, directory.scope == scope,
              directory.evidenceFingerprint == directoryEvidenceFingerprint,
              directory.rows.contains(row) else {
            throw SpaceListFailure.selectionEvidenceMismatch
        }
        return try SpaceCoreDetailsRequest(accountId: accountId, spaceId: row.id)
    }

    @discardableResult
    public func validateDetail(
        _ detail: SpaceCoreDetailsSnapshot
    ) throws -> SpaceCoreDetailsSnapshot {
        guard detail.accountId == accountId, detail.id == row.id, detail.scope == scope else {
            throw SpaceListFailure.detailIdentityMismatch
        }
        return detail
    }

    public init(from decoder: Decoder) throws {
        do {
            try requireExactSpaceListKeys(decoder, CodingKeys.self)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            accountId = try container.decode(AccountID.self, forKey: .accountId)
            scope = try container.decode(StrictSpaceCreationScope.self, forKey: .scope).value
            row = try container.decode(SpaceDirectoryRowPresentation.self, forKey: .row)
            directoryEvidenceFingerprint = try container.decode(
                ListQueryFingerprint.self,
                forKey: .directoryEvidenceFingerprint
            )
            selectionFingerprint = try container.decode(
                ListQueryFingerprint.self,
                forKey: .selectionFingerprint
            )
            guard row.accountId == accountId else { throw SpaceListFailure.accountScopeMismatch }
            guard row.scope == scope else { throw SpaceListFailure.spaceScopeMismatch }
            guard selectionFingerprint == (try Self.fingerprint(
                accountId: accountId,
                scope: scope,
                row: row,
                directoryEvidenceFingerprint: directoryEvidenceFingerprint
            )) else {
                throw SpaceListFailure.selectionFingerprintMismatch
            }
        } catch let failure as SpaceListFailure {
            throw failure
        } catch {
            throw SpaceListFailure.invalidEncodedSelection
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accountId, forKey: .accountId)
        try container.encode(StrictSpaceCreationScope(scope), forKey: .scope)
        try container.encode(row, forKey: .row)
        try container.encode(directoryEvidenceFingerprint, forKey: .directoryEvidenceFingerprint)
        try container.encode(selectionFingerprint, forKey: .selectionFingerprint)
    }

    private static func fingerprint(
        accountId: AccountID,
        scope: SpaceCreationScope,
        row: SpaceDirectoryRowPresentation,
        directoryEvidenceFingerprint: ListQueryFingerprint
    ) throws -> ListQueryFingerprint {
        try spaceListFingerprint(FingerprintBasis(
            contractVersion: "space-browsing-selection-v1",
            accountId: accountId,
            scope: scope,
            row: row,
            directoryEvidenceFingerprint: directoryEvidenceFingerprint
        ))
    }

    private struct FingerprintBasis: Codable {
        let contractVersion: String
        let accountId: AccountID
        let scope: SpaceCreationScope
        let row: SpaceDirectoryRowPresentation
        let directoryEvidenceFingerprint: ListQueryFingerprint
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case accountId, scope, row, directoryEvidenceFingerprint, selectionFingerprint
    }
}

public enum SpaceListUpdateState: Codable, Equatable, Sendable {
    case waiting(ListReadiness)
    case snapshot(SpaceListLocalSnapshot)
    case failed(failure: ListFailureState, cached: SpaceListLocalSnapshot?)

    public init(from decoder: Decoder) throws {
        let rawContainer = try decoder.container(keyedBy: SpaceListAnyCodingKey.self)
        let rawKeys = rawContainer.allKeys.map(\.stringValue)
        guard rawKeys.count == 1, let rawKey = rawKeys.first,
              let key = CodingKeys(rawValue: rawKey) else {
            throw SpaceListStrictDecodingFailure.invalidKeys
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch key {
        case .waiting:
            let valuesDecoder = try container.superDecoder(forKey: .waiting)
            try requireExactSpaceListKeys(valuesDecoder, UnlabeledAssociatedValueKeys.self)
            let values = try valuesDecoder.container(keyedBy: UnlabeledAssociatedValueKeys.self)
            self = .waiting(try values.decode(ListReadiness.self, forKey: .value))
        case .snapshot:
            let valuesDecoder = try container.superDecoder(forKey: .snapshot)
            try requireExactSpaceListKeys(valuesDecoder, UnlabeledAssociatedValueKeys.self)
            let values = try valuesDecoder.container(keyedBy: UnlabeledAssociatedValueKeys.self)
            self = .snapshot(try values.decode(SpaceListLocalSnapshot.self, forKey: .value))
        case .failed:
            let valuesDecoder = try container.superDecoder(forKey: .failed)
            try requireExactSpaceListKeys(valuesDecoder, FailedAssociatedValueKeys.self)
            let values = try valuesDecoder.container(keyedBy: FailedAssociatedValueKeys.self)
            self = .failed(
                failure: try values.decode(ListFailureState.self, forKey: .failure),
                cached: try values.decodeIfPresent(SpaceListLocalSnapshot.self, forKey: .cached)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .waiting(let readiness):
            var values = container.nestedContainer(
                keyedBy: UnlabeledAssociatedValueKeys.self,
                forKey: .waiting
            )
            try values.encode(readiness, forKey: .value)
        case .snapshot(let snapshot):
            var values = container.nestedContainer(
                keyedBy: UnlabeledAssociatedValueKeys.self,
                forKey: .snapshot
            )
            try values.encode(snapshot, forKey: .value)
        case .failed(let failure, let cached):
            var values = container.nestedContainer(
                keyedBy: FailedAssociatedValueKeys.self,
                forKey: .failed
            )
            try values.encode(failure, forKey: .failure)
            try values.encode(cached, forKey: .cached)
        }
    }

    private enum CodingKeys: String, CodingKey { case waiting, snapshot, failed }
    private enum UnlabeledAssociatedValueKeys: String, CodingKey, CaseIterable {
        case value = "_0"
    }
    private enum FailedAssociatedValueKeys: String, CodingKey, CaseIterable {
        case failure, cached
    }
}

public enum SpaceDirectoryPresentationUpdate: Equatable, Sendable {
    case waiting(ListReadiness)
    case snapshot(ActiveSpaceDirectoryPresentationSnapshot)
    case failed(failure: ListFailureState, cached: ActiveSpaceDirectoryPresentationSnapshot?)
}

public struct SpaceListUpdate: Codable, Equatable, Sendable {
    public let request: SpaceListRequest
    public let state: SpaceListUpdateState

    public init(request: SpaceListRequest, state: SpaceListUpdateState) throws {
        switch state {
        case .waiting(let readiness):
            guard [.notRequested, .loading, .blocked].contains(readiness) else {
                throw SpaceListFailure.invalidWaitingState
            }
        case .snapshot(let snapshot):
            guard snapshot.request == request else {
                throw SpaceListFailure.updateRequestMismatch
            }
        case .failed(let failure, let cached):
            guard failure != .unavailable || cached == nil else {
                throw SpaceListFailure.unavailableCachedEvidence
            }
            guard cached?.request == request || cached == nil else {
                throw SpaceListFailure.updateRequestMismatch
            }
        }
        self.request = request
        self.state = state
    }

    public func validating(request expected: SpaceListRequest) throws -> Self {
        guard request == expected else { throw SpaceListFailure.updateRequestMismatch }
        return self
    }

    public func presentingActiveDirectory() throws -> SpaceDirectoryPresentationUpdate {
        switch state {
        case .waiting(let readiness):
            return .waiting(readiness)
        case .snapshot(let snapshot):
            return .snapshot(try ActiveSpaceDirectoryPresentationSnapshot(source: snapshot))
        case .failed(let failure, nil):
            return .failed(failure: failure, cached: nil)
        case .failed(let failure, let cached?):
            let staleEvidence = try SpaceListLocalSnapshot(
                request: cached.request,
                rows: cached.local.rows,
                visibleRowCountBeforeFiltering: cached.local.visibleRowCountBeforeFiltering,
                isCompleteForQuery: false,
                quality: .stale,
                localDataVersion: cached.local.localDataVersion,
                asOf: cached.local.asOf
            )
            return .failed(
                failure: failure,
                cached: try ActiveSpaceDirectoryPresentationSnapshot(source: staleEvidence)
            )
        }
    }

    public init(from decoder: Decoder) throws {
        do {
            try requireExactSpaceListKeys(decoder, CodingKeys.self)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                request: container.decode(SpaceListRequest.self, forKey: .request),
                state: container.decode(SpaceListUpdateState.self, forKey: .state)
            )
        } catch let failure as SpaceListFailure {
            throw failure
        } catch {
            throw SpaceListFailure.invalidEncodedUpdate
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case request, state }
}

public protocol SpaceListQuerying: Sendable {
    func watchSpaces(_ request: SpaceListRequest) -> AsyncThrowingStream<SpaceListUpdate, Error>
}

private func spaceListRowPrecedes(_ lhs: SpaceListSourceRow, _ rhs: SpaceListSourceRow) -> Bool {
    let lhsFolded = lhs.displayName.rawValue.lowercased()
    let rhsFolded = rhs.displayName.rawValue.lowercased()
    if lhsFolded != rhsFolded { return lhsFolded < rhsFolded }
    if lhs.displayName.rawValue != rhs.displayName.rawValue {
        return lhs.displayName.rawValue < rhs.displayName.rawValue
    }
    return lhs.id.rawValue < rhs.id.rawValue
}

private func firstDuplicateSpaceListValue<Value: Hashable>(_ values: [Value]) -> Value? {
    var seen: Set<Value> = []
    return values.first { !seen.insert($0).inserted }
}

private func spaceListFingerprint<Value: Encodable>(
    _ basis: Value
) throws -> ListQueryFingerprint {
    let bytes = try OperationContractCodec.encode(basis)
    let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    return try ListQueryFingerprint(validating: digest)
}

private enum SpaceListStrictDecodingFailure: Error { case invalidKeys }

private struct StrictSpaceCreationScope: Codable {
    let value: SpaceCreationScope

    init(_ value: SpaceCreationScope) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ScopeKind.self, forKey: .kind) {
        case .project:
            try requireExactSpaceListKeyNames(decoder, ["kind", "projectId"])
            value = .project(try container.decode(ProjectID.self, forKey: .projectId))
        case .businessInventory:
            try requireExactSpaceListKeyNames(decoder, ["kind"])
            value = .businessInventory
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch value {
        case .project(let projectId):
            try container.encode(ScopeKind.project, forKey: .kind)
            try container.encode(projectId, forKey: .projectId)
        case .businessInventory:
            try container.encode(ScopeKind.businessInventory, forKey: .kind)
        }
    }

    private enum ScopeKind: String, Codable { case project, businessInventory }
    private enum CodingKeys: String, CodingKey { case kind, projectId }
}

private struct StrictSpaceChecklistItem: Codable {
    let value: SpaceChecklistItemState

    init(_ value: SpaceChecklistItemState) { self.value = value }

    init(from decoder: Decoder) throws {
        try requireExactSpaceListKeys(decoder, CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = SpaceChecklistItemState(
            id: try container.decode(SpaceChecklistItemID.self, forKey: .id),
            text: try container.decode(SpaceChecklistItemText.self, forKey: .text),
            isChecked: try container.decode(Bool.self, forKey: .isChecked),
            presentationOrder: try container.decode(UInt32.self, forKey: .presentationOrder)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value.id, forKey: .id)
        try container.encode(value.text, forKey: .text)
        try container.encode(value.isChecked, forKey: .isChecked)
        try container.encode(value.presentationOrder, forKey: .presentationOrder)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, text, isChecked, presentationOrder
    }
}

private struct StrictSpaceChecklist: Codable {
    let value: SpaceChecklistState

    init(_ value: SpaceChecklistState) { self.value = value }

    init(from decoder: Decoder) throws {
        try requireExactSpaceListKeys(decoder, CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let items = try container.decode([StrictSpaceChecklistItem].self, forKey: .items)
            .map(\.value)
        value = try SpaceChecklistState(
            id: container.decode(SpaceChecklistID.self, forKey: .id),
            name: container.decode(SpaceChecklistName.self, forKey: .name),
            presentationOrder: container.decode(UInt32.self, forKey: .presentationOrder),
            items: items
        )
        guard value.items == items else { throw SpaceListStrictDecodingFailure.invalidKeys }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value.id, forKey: .id)
        try container.encode(value.name, forKey: .name)
        try container.encode(value.presentationOrder, forKey: .presentationOrder)
        try container.encode(value.items.map(StrictSpaceChecklistItem.init), forKey: .items)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, name, presentationOrder, items
    }
}

private struct StrictSpaceChecklistCollection: Codable {
    let value: SpaceChecklistCollection

    init(_ value: SpaceChecklistCollection) { self.value = value }

    init(from decoder: Decoder) throws {
        try requireExactSpaceListKeys(decoder, CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let checklists = try container.decode([StrictSpaceChecklist].self, forKey: .checklists)
            .map(\.value)
        value = try SpaceChecklistCollection(checklists: checklists)
        guard value.checklists == checklists else {
            throw SpaceListStrictDecodingFailure.invalidKeys
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(
            value.checklists.map(StrictSpaceChecklist.init),
            forKey: .checklists
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case checklists }
}

private struct StrictSpaceListLocalSnapshot: Codable {
    let value: ListLocalSnapshot<SpaceListSourceRow>

    init(_ value: ListLocalSnapshot<SpaceListSourceRow>) { self.value = value }

    init(from decoder: Decoder) throws {
        try requireExactSpaceListKeys(decoder, CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try ListLocalSnapshot(
            queryFingerprint: container.decode(ListQueryFingerprint.self, forKey: .queryFingerprint),
            rows: container.decode([SpaceListSourceRow].self, forKey: .rows),
            visibleRowCountBeforeFiltering: container.decode(
                Int.self,
                forKey: .visibleRowCountBeforeFiltering
            ),
            isCompleteForQuery: container.decode(Bool.self, forKey: .isCompleteForQuery),
            quality: container.decode(ListSnapshotQuality.self, forKey: .quality),
            localDataVersion: container.decode(LocalDataVersion.self, forKey: .localDataVersion),
            asOf: container.decode(Date.self, forKey: .asOf)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value.queryFingerprint, forKey: .queryFingerprint)
        try container.encode(value.rows, forKey: .rows)
        try container.encode(
            value.visibleRowCountBeforeFiltering,
            forKey: .visibleRowCountBeforeFiltering
        )
        try container.encode(value.isCompleteForQuery, forKey: .isCompleteForQuery)
        try container.encode(value.quality, forKey: .quality)
        try container.encode(value.localDataVersion, forKey: .localDataVersion)
        try container.encode(value.asOf, forKey: .asOf)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case queryFingerprint, rows, visibleRowCountBeforeFiltering, isCompleteForQuery
        case quality, localDataVersion, asOf
    }
}

private struct SpaceListAnyCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private func requireExactSpaceListKeys<Keys: CodingKey & CaseIterable>(
    _ decoder: Decoder,
    _ keys: Keys.Type
) throws where Keys.AllCases: Collection {
    let container = try decoder.container(keyedBy: SpaceListAnyCodingKey.self)
    let actual = Set(container.allKeys.map(\.stringValue))
    let expected = Set(Keys.allCases.map(\.stringValue))
    guard actual == expected else { throw SpaceListStrictDecodingFailure.invalidKeys }
}

private func requireExactSpaceListKeyNames(
    _ decoder: Decoder,
    _ expectedNames: Set<String>
) throws {
    let container = try decoder.container(keyedBy: SpaceListAnyCodingKey.self)
    let actual = Set(container.allKeys.map(\.stringValue))
    guard actual == expectedNames else { throw SpaceListStrictDecodingFailure.invalidKeys }
}
