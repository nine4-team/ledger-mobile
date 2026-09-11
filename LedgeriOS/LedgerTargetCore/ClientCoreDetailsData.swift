import CryptoKit
import Foundation

public enum ClientCoreDetailsFailure: Error, Equatable, Sendable {
    case accountScopeMismatch
    case clientIdentityMismatch
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
    case invalidEncodedClient
    case invalidEncodedRevision
    case invalidEncodedLocalSnapshot
    case invalidEncodedUpdate

    public var diagnosticCode: String {
        switch self {
        case .accountScopeMismatch: "client_core_details_account_scope_mismatch"
        case .clientIdentityMismatch: "client_core_details_identity_mismatch"
        case .multipleRows: "client_core_details_multiple_rows"
        case .visibleCountMismatch: "client_core_details_visible_count_mismatch"
        case .invalidSnapshotAsOf: "client_core_details_as_of_invalid"
        case .invalidCompleteness: "client_core_details_completeness_invalid"
        case .requestFingerprintMismatch: "client_core_details_request_fingerprint_mismatch"
        case .queryFingerprintMismatch: "client_core_details_query_fingerprint_mismatch"
        case .updateRequestMismatch: "client_core_details_update_request_mismatch"
        case .invalidWaitingState: "client_core_details_waiting_state_invalid"
        case .unavailableCachedEvidence: "client_core_details_unavailable_cache_invalid"
        case .localReadFailed: "client_core_details_local_read_failed"
        case .invalidEncodedRequest: "client_core_details_request_encoding_invalid"
        case .invalidEncodedClient: "client_core_details_client_encoding_invalid"
        case .invalidEncodedRevision: "client_core_details_revision_encoding_invalid"
        case .invalidEncodedLocalSnapshot: "client_core_details_snapshot_encoding_invalid"
        case .invalidEncodedUpdate: "client_core_details_update_encoding_invalid"
        }
    }
}

public struct ClientCoreDetailsRequest: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let clientId: ClientID
    public let queryFingerprint: ListQueryFingerprint

    public init(accountId: AccountID, clientId: ClientID) throws {
        self.accountId = accountId
        self.clientId = clientId
        queryFingerprint = try Self.makeFingerprint(accountId: accountId, clientId: clientId)
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let accountId = try container.decode(AccountID.self, forKey: .accountId)
            let clientId = try container.decode(ClientID.self, forKey: .clientId)
            let encodedFingerprint = try container.decode(
                ListQueryFingerprint.self,
                forKey: .queryFingerprint
            )
            try self.init(accountId: accountId, clientId: clientId)
            guard queryFingerprint == encodedFingerprint else {
                throw ClientCoreDetailsFailure.requestFingerprintMismatch
            }
        } catch let failure as ClientCoreDetailsFailure {
            throw failure
        } catch {
            throw ClientCoreDetailsFailure.invalidEncodedRequest
        }
    }

    private static func makeFingerprint(
        accountId: AccountID,
        clientId: ClientID
    ) throws -> ListQueryFingerprint {
        do {
            let basis = FingerprintBasis(
                contractVersion: "client-core-details-v1",
                accountId: accountId,
                clientId: clientId
            )
            let bytes = try OperationContractCodec.encode(basis)
            let digest = SHA256.hash(data: bytes)
                .map { String(format: "%02x", $0) }
                .joined()
            return try ListQueryFingerprint(validating: digest)
        } catch {
            throw ClientCoreDetailsFailure.invalidEncodedRequest
        }
    }

    private struct FingerprintBasis: Codable {
        let contractVersion: String
        let accountId: AccountID
        let clientId: ClientID
    }

    private enum CodingKeys: String, CodingKey {
        case accountId
        case clientId
        case queryFingerprint
    }
}

public struct ClientCoreDetailsSnapshot: Codable, Equatable, Sendable {
    public let client: ClientSummary
    public let locallyObservedRevision: ExpectedClientRevision

    public init(
        client: ClientSummary,
        locallyObservedRevision: ExpectedClientRevision
    ) {
        self.client = client
        self.locallyObservedRevision = locallyObservedRevision
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let client: ClientSummary
            do {
                client = try container.decode(ClientSummary.self, forKey: .client)
            } catch {
                throw ClientCoreDetailsFailure.invalidEncodedClient
            }
            let revision: ExpectedClientRevision
            do {
                revision = try container.decode(
                    ExpectedClientRevision.self,
                    forKey: .locallyObservedRevision
                )
            } catch {
                throw ClientCoreDetailsFailure.invalidEncodedRevision
            }
            self.init(client: client, locallyObservedRevision: revision)
        } catch let failure as ClientCoreDetailsFailure {
            throw failure
        } catch {
            throw ClientCoreDetailsFailure.invalidEncodedClient
        }
    }

    private enum CodingKeys: String, CodingKey {
        case client
        case locallyObservedRevision
    }
}

public struct ClientCoreDetailsLocalSnapshot: Codable, Equatable, Sendable {
    public let request: ClientCoreDetailsRequest
    public let local: ListLocalSnapshot<ClientCoreDetailsSnapshot>

    public var row: ClientCoreDetailsSnapshot? { local.rows.first }

    public var isAuthoritativeAbsence: Bool {
        local.rows.isEmpty && local.quality == .ready && local.isCompleteForQuery
    }

    public var observedRevisionIsFromCompleteReadySnapshot: Bool {
        row != nil && local.quality == .ready && local.isCompleteForQuery
    }

    public init(
        request: ClientCoreDetailsRequest,
        rows: [ClientCoreDetailsSnapshot],
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
        } catch let failure as ClientCoreDetailsFailure {
            throw failure
        } catch ListQueryContractFailure.invalidVisibleRowCount {
            throw ClientCoreDetailsFailure.visibleCountMismatch
        } catch ListQueryContractFailure.incompleteAuthoritativeEmpty {
            throw ClientCoreDetailsFailure.invalidCompleteness
        } catch {
            throw ClientCoreDetailsFailure.invalidEncodedLocalSnapshot
        }
    }

    public init(
        request: ClientCoreDetailsRequest,
        local: ListLocalSnapshot<ClientCoreDetailsSnapshot>
    ) throws {
        guard local.asOf.timeIntervalSinceReferenceDate.isFinite else {
            throw ClientCoreDetailsFailure.invalidSnapshotAsOf
        }
        guard local.queryFingerprint == request.queryFingerprint else {
            throw ClientCoreDetailsFailure.queryFingerprintMismatch
        }
        guard local.rows.count <= 1 else {
            throw ClientCoreDetailsFailure.multipleRows
        }
        guard local.visibleRowCountBeforeFiltering == local.rows.count else {
            throw ClientCoreDetailsFailure.visibleCountMismatch
        }
        guard local.rows.allSatisfy({ $0.client.accountId == request.accountId }) else {
            throw ClientCoreDetailsFailure.accountScopeMismatch
        }
        guard local.rows.allSatisfy({ $0.client.id == request.clientId }) else {
            throw ClientCoreDetailsFailure.clientIdentityMismatch
        }
        self.request = request
        self.local = local
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                request: container.decode(ClientCoreDetailsRequest.self, forKey: .request),
                local: container.decode(
                    ListLocalSnapshot<ClientCoreDetailsSnapshot>.self,
                    forKey: .local
                )
            )
        } catch let failure as ClientCoreDetailsFailure {
            throw failure
        } catch ListQueryContractFailure.incompleteAuthoritativeEmpty {
            throw ClientCoreDetailsFailure.invalidCompleteness
        } catch ListQueryContractFailure.invalidVisibleRowCount {
            throw ClientCoreDetailsFailure.visibleCountMismatch
        } catch {
            throw ClientCoreDetailsFailure.invalidEncodedLocalSnapshot
        }
    }

    private enum CodingKeys: String, CodingKey {
        case request
        case local
    }
}

public enum ClientCoreDetailsUpdateState: Codable, Equatable, Sendable {
    case waiting(ListReadiness)
    case snapshot(ClientCoreDetailsLocalSnapshot)
    case failed(failure: ListFailureState, cached: ClientCoreDetailsLocalSnapshot?)
}

public struct ClientCoreDetailsUpdate: Codable, Equatable, Sendable {
    public let request: ClientCoreDetailsRequest
    public let state: ClientCoreDetailsUpdateState

    public init(
        request: ClientCoreDetailsRequest,
        state: ClientCoreDetailsUpdateState
    ) throws {
        switch state {
        case .waiting(let readiness):
            guard [.notRequested, .loading, .blocked].contains(readiness) else {
                throw ClientCoreDetailsFailure.invalidWaitingState
            }
        case .snapshot(let snapshot):
            guard snapshot.request == request else {
                throw ClientCoreDetailsFailure.updateRequestMismatch
            }
        case .failed(let failure, let cached):
            guard failure != .unavailable || cached == nil else {
                throw ClientCoreDetailsFailure.unavailableCachedEvidence
            }
            guard cached?.request == request || cached == nil else {
                throw ClientCoreDetailsFailure.updateRequestMismatch
            }
        }
        self.request = request
        self.state = state
    }

    public func validating(request expectedRequest: ClientCoreDetailsRequest) throws -> Self {
        guard request == expectedRequest else {
            throw ClientCoreDetailsFailure.updateRequestMismatch
        }
        return self
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                request: container.decode(ClientCoreDetailsRequest.self, forKey: .request),
                state: container.decode(ClientCoreDetailsUpdateState.self, forKey: .state)
            )
        } catch let failure as ClientCoreDetailsFailure {
            throw failure
        } catch {
            throw ClientCoreDetailsFailure.invalidEncodedUpdate
        }
    }

    private enum CodingKeys: String, CodingKey {
        case request
        case state
    }
}

public protocol ClientCoreDetailsQuerying: Sendable {
    func watchClientCoreDetails(
        _ request: ClientCoreDetailsRequest
    ) -> AsyncThrowingStream<ClientCoreDetailsUpdate, Error>
}
