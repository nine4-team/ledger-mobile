import CryptoKit
import Foundation

public enum SpaceCoreDetailsFailure: Error, Equatable, Sendable {
    case accountScopeMismatch
    case spaceIdentityMismatch
    case invalidSpaceScope
    case invalidSpaceTimestamp
    case multipleRows
    case visibleCountMismatch
    case invalidSnapshotAsOf
    case invalidCompleteness
    case requestFingerprintMismatch
    case queryFingerprintMismatch
    case updateRequestMismatch
    case invalidWaitingState
    case unavailableCachedEvidence
    case localReadFailed
    case invalidEncodedRequest
    case invalidEncodedSpace
    case invalidEncodedLocalSnapshot
    case invalidEncodedUpdate

    public var diagnosticCode: String {
        switch self {
        case .accountScopeMismatch: "space_core_details_account_scope_mismatch"
        case .spaceIdentityMismatch: "space_core_details_identity_mismatch"
        case .invalidSpaceScope: "space_core_details_scope_invalid"
        case .invalidSpaceTimestamp: "space_core_details_timestamp_invalid"
        case .multipleRows: "space_core_details_multiple_rows"
        case .visibleCountMismatch: "space_core_details_visible_count_mismatch"
        case .invalidSnapshotAsOf: "space_core_details_as_of_invalid"
        case .invalidCompleteness: "space_core_details_completeness_invalid"
        case .requestFingerprintMismatch: "space_core_details_request_fingerprint_mismatch"
        case .queryFingerprintMismatch: "space_core_details_query_fingerprint_mismatch"
        case .updateRequestMismatch: "space_core_details_update_request_mismatch"
        case .invalidWaitingState: "space_core_details_waiting_state_invalid"
        case .unavailableCachedEvidence: "space_core_details_unavailable_cache_invalid"
        case .localReadFailed: "space_core_details_local_read_failed"
        case .invalidEncodedRequest: "space_core_details_request_encoding_invalid"
        case .invalidEncodedSpace: "space_core_details_space_encoding_invalid"
        case .invalidEncodedLocalSnapshot: "space_core_details_snapshot_encoding_invalid"
        case .invalidEncodedUpdate: "space_core_details_update_encoding_invalid"
        }
    }
}

public struct SpaceCoreDetailsRequest: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let spaceId: SpaceID
    public let queryFingerprint: ListQueryFingerprint

    public init(accountId: AccountID, spaceId: SpaceID) throws {
        self.accountId = accountId
        self.spaceId = spaceId
        queryFingerprint = try Self.makeFingerprint(accountId: accountId, spaceId: spaceId)
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let accountId = try container.decode(AccountID.self, forKey: .accountId)
            let spaceId = try container.decode(SpaceID.self, forKey: .spaceId)
            let encodedFingerprint = try container.decode(
                ListQueryFingerprint.self,
                forKey: .queryFingerprint
            )
            try self.init(accountId: accountId, spaceId: spaceId)
            guard queryFingerprint == encodedFingerprint else {
                throw SpaceCoreDetailsFailure.requestFingerprintMismatch
            }
        } catch let failure as SpaceCoreDetailsFailure {
            throw failure
        } catch {
            throw SpaceCoreDetailsFailure.invalidEncodedRequest
        }
    }

    private static func makeFingerprint(
        accountId: AccountID,
        spaceId: SpaceID
    ) throws -> ListQueryFingerprint {
        do {
            let basis = FingerprintBasis(
                contractVersion: "space-core-details-v1",
                accountId: accountId,
                spaceId: spaceId
            )
            let bytes = try OperationContractCodec.encode(basis)
            let digest = SHA256.hash(data: bytes)
                .map { String(format: "%02x", $0) }
                .joined()
            return try ListQueryFingerprint(validating: digest)
        } catch {
            throw SpaceCoreDetailsFailure.invalidEncodedRequest
        }
    }

    private struct FingerprintBasis: Codable {
        let contractVersion: String
        let accountId: AccountID
        let spaceId: SpaceID
    }

    private enum CodingKeys: String, CodingKey {
        case accountId
        case spaceId
        case queryFingerprint
    }
}

public struct SpaceCoreDetailsSnapshot: Codable, Equatable, Sendable {
    public let id: SpaceID
    public let accountId: AccountID
    public let scope: SpaceCreationScope
    public let displayName: SpaceDisplayName
    public let notes: SpaceCreationNotes
    public let lifecycle: DirectoryLifecycleState
    public let revision: UInt64
    public let createdAt: Date
    public let updatedAt: Date
    public let checklists: SpaceChecklistCollection

    public var completedItemCount: Int { checklists.completedItemCount }
    public var totalItemCount: Int { checklists.totalItemCount }

    public init(
        id: SpaceID,
        accountId: AccountID,
        scope: SpaceCreationScope,
        displayName: SpaceDisplayName,
        notes: SpaceCreationNotes,
        lifecycle: DirectoryLifecycleState,
        revision: UInt64,
        createdAt: Date,
        updatedAt: Date,
        checklists: SpaceChecklistCollection
    ) throws {
        guard createdAt.timeIntervalSinceReferenceDate.isFinite,
              updatedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw SpaceCoreDetailsFailure.invalidSpaceTimestamp
        }
        self.id = id
        self.accountId = accountId
        self.scope = scope
        self.displayName = displayName
        self.notes = notes
        self.lifecycle = lifecycle
        self.revision = revision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.checklists = checklists
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                id: container.decode(SpaceID.self, forKey: .id),
                accountId: container.decode(AccountID.self, forKey: .accountId),
                scope: container.decode(SpaceCreationScope.self, forKey: .scope),
                displayName: container.decode(SpaceDisplayName.self, forKey: .displayName),
                notes: container.decode(SpaceCreationNotes.self, forKey: .notes),
                lifecycle: container.decode(DirectoryLifecycleState.self, forKey: .lifecycle),
                revision: container.decode(UInt64.self, forKey: .revision),
                createdAt: container.decode(Date.self, forKey: .createdAt),
                updatedAt: container.decode(Date.self, forKey: .updatedAt),
                checklists: container.decode(SpaceChecklistCollection.self, forKey: .checklists)
            )
        } catch let failure as SpaceCoreDetailsFailure {
            throw failure
        } catch let failure as SpaceCreationFailure {
            if failure == .invalidCreationScope {
                throw SpaceCoreDetailsFailure.invalidSpaceScope
            }
            throw SpaceCoreDetailsFailure.invalidEncodedSpace
        } catch is SpaceChecklistRevisionFailure {
            throw SpaceCoreDetailsFailure.invalidEncodedSpace
        } catch {
            throw SpaceCoreDetailsFailure.invalidEncodedSpace
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case accountId
        case scope
        case displayName
        case notes
        case lifecycle
        case revision
        case createdAt
        case updatedAt
        case checklists
    }
}

public struct SpaceCoreDetailsLocalSnapshot: Codable, Equatable, Sendable {
    public let request: SpaceCoreDetailsRequest
    public let local: ListLocalSnapshot<SpaceCoreDetailsSnapshot>

    public var row: SpaceCoreDetailsSnapshot? { local.rows.first }

    public var isAuthoritativeAbsence: Bool {
        local.rows.isEmpty && local.quality == .ready && local.isCompleteForQuery
    }

    public var progressCountsAreAuthoritative: Bool {
        row != nil && local.isCompleteForQuery
    }

    public init(
        request: SpaceCoreDetailsRequest,
        rows: [SpaceCoreDetailsSnapshot],
        visibleRowCountBeforeFiltering: Int,
        isCompleteForQuery: Bool,
        quality: ListSnapshotQuality,
        localDataVersion: LocalDataVersion,
        asOf: Date
    ) throws {
        do {
            let local = try ListLocalSnapshot(
                queryFingerprint: request.queryFingerprint,
                rows: rows,
                visibleRowCountBeforeFiltering: visibleRowCountBeforeFiltering,
                isCompleteForQuery: isCompleteForQuery,
                quality: quality,
                localDataVersion: localDataVersion,
                asOf: asOf
            )
            try self.init(request: request, local: local)
        } catch let failure as SpaceCoreDetailsFailure {
            throw failure
        } catch ListQueryContractFailure.invalidVisibleRowCount {
            throw SpaceCoreDetailsFailure.visibleCountMismatch
        } catch ListQueryContractFailure.incompleteAuthoritativeEmpty {
            throw SpaceCoreDetailsFailure.invalidCompleteness
        } catch {
            throw SpaceCoreDetailsFailure.invalidEncodedLocalSnapshot
        }
    }

    public init(
        request: SpaceCoreDetailsRequest,
        local: ListLocalSnapshot<SpaceCoreDetailsSnapshot>
    ) throws {
        guard local.asOf.timeIntervalSinceReferenceDate.isFinite else {
            throw SpaceCoreDetailsFailure.invalidSnapshotAsOf
        }
        guard local.queryFingerprint == request.queryFingerprint else {
            throw SpaceCoreDetailsFailure.queryFingerprintMismatch
        }
        guard local.rows.count <= 1 else {
            throw SpaceCoreDetailsFailure.multipleRows
        }
        guard local.visibleRowCountBeforeFiltering == local.rows.count else {
            throw SpaceCoreDetailsFailure.visibleCountMismatch
        }
        guard local.rows.allSatisfy({ $0.accountId == request.accountId }) else {
            throw SpaceCoreDetailsFailure.accountScopeMismatch
        }
        guard local.rows.allSatisfy({ $0.id == request.spaceId }) else {
            throw SpaceCoreDetailsFailure.spaceIdentityMismatch
        }
        self.request = request
        self.local = local
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                request: container.decode(SpaceCoreDetailsRequest.self, forKey: .request),
                local: container.decode(
                    ListLocalSnapshot<SpaceCoreDetailsSnapshot>.self,
                    forKey: .local
                )
            )
        } catch let failure as SpaceCoreDetailsFailure {
            throw failure
        } catch ListQueryContractFailure.incompleteAuthoritativeEmpty {
            throw SpaceCoreDetailsFailure.invalidCompleteness
        } catch ListQueryContractFailure.invalidVisibleRowCount {
            throw SpaceCoreDetailsFailure.visibleCountMismatch
        } catch {
            throw SpaceCoreDetailsFailure.invalidEncodedLocalSnapshot
        }
    }

    private enum CodingKeys: String, CodingKey {
        case request
        case local
    }
}

public enum SpaceCoreDetailsUpdateState: Codable, Equatable, Sendable {
    case waiting(ListReadiness)
    case snapshot(SpaceCoreDetailsLocalSnapshot)
    case failed(failure: ListFailureState, cached: SpaceCoreDetailsLocalSnapshot?)
}

public struct SpaceCoreDetailsUpdate: Codable, Equatable, Sendable {
    public let request: SpaceCoreDetailsRequest
    public let state: SpaceCoreDetailsUpdateState

    public init(
        request: SpaceCoreDetailsRequest,
        state: SpaceCoreDetailsUpdateState
    ) throws {
        switch state {
        case .waiting(let readiness):
            guard [.notRequested, .loading, .blocked].contains(readiness) else {
                throw SpaceCoreDetailsFailure.invalidWaitingState
            }
        case .snapshot(let snapshot):
            guard snapshot.request == request else {
                throw SpaceCoreDetailsFailure.updateRequestMismatch
            }
        case .failed(let failure, let cached):
            guard failure != .unavailable || cached == nil else {
                throw SpaceCoreDetailsFailure.unavailableCachedEvidence
            }
            guard cached?.request == request || cached == nil else {
                throw SpaceCoreDetailsFailure.updateRequestMismatch
            }
        }
        self.request = request
        self.state = state
    }

    public func validating(request expectedRequest: SpaceCoreDetailsRequest) throws -> Self {
        guard request == expectedRequest else {
            throw SpaceCoreDetailsFailure.updateRequestMismatch
        }
        return self
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                request: container.decode(SpaceCoreDetailsRequest.self, forKey: .request),
                state: container.decode(SpaceCoreDetailsUpdateState.self, forKey: .state)
            )
        } catch let failure as SpaceCoreDetailsFailure {
            throw failure
        } catch {
            throw SpaceCoreDetailsFailure.invalidEncodedUpdate
        }
    }

    private enum CodingKeys: String, CodingKey {
        case request
        case state
    }
}

public protocol SpaceCoreDetailsQuerying: Sendable {
    func watchSpaceCoreDetails(
        _ request: SpaceCoreDetailsRequest
    ) -> AsyncThrowingStream<SpaceCoreDetailsUpdate, Error>
}
