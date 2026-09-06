import CryptoKit
import Foundation

public enum ProjectCoreDetailsFailure: Error, Equatable, Sendable {
    case accountScopeMismatch
    case projectIdentityMismatch
    case clientRelationshipMismatch
    case noncanonicalDescription
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
    case invalidEncodedProject
    case invalidEncodedRevision
    case invalidEncodedLocalSnapshot
    case invalidEncodedUpdate

    public var diagnosticCode: String {
        switch self {
        case .accountScopeMismatch: "project_core_details_account_scope_mismatch"
        case .projectIdentityMismatch: "project_core_details_identity_mismatch"
        case .clientRelationshipMismatch: "project_core_details_client_relationship_mismatch"
        case .noncanonicalDescription: "project_core_details_description_noncanonical"
        case .multipleRows: "project_core_details_multiple_rows"
        case .visibleCountMismatch: "project_core_details_visible_count_mismatch"
        case .invalidSnapshotAsOf: "project_core_details_as_of_invalid"
        case .invalidCompleteness: "project_core_details_completeness_invalid"
        case .requestFingerprintMismatch: "project_core_details_request_fingerprint_mismatch"
        case .queryFingerprintMismatch: "project_core_details_query_fingerprint_mismatch"
        case .updateRequestMismatch: "project_core_details_update_request_mismatch"
        case .invalidWaitingState: "project_core_details_waiting_state_invalid"
        case .unavailableCachedEvidence: "project_core_details_unavailable_cache_invalid"
        case .localReadFailed: "project_core_details_local_read_failed"
        case .invalidEncodedRequest: "project_core_details_request_encoding_invalid"
        case .invalidEncodedProject: "project_core_details_project_encoding_invalid"
        case .invalidEncodedRevision: "project_core_details_revision_encoding_invalid"
        case .invalidEncodedLocalSnapshot: "project_core_details_snapshot_encoding_invalid"
        case .invalidEncodedUpdate: "project_core_details_update_encoding_invalid"
        }
    }
}

public struct ProjectCoreDetailsRequest: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let projectId: ProjectID
    public let queryFingerprint: ListQueryFingerprint

    public init(accountId: AccountID, projectId: ProjectID) throws {
        self.accountId = accountId
        self.projectId = projectId
        queryFingerprint = try Self.makeFingerprint(accountId: accountId, projectId: projectId)
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let accountId = try container.decode(AccountID.self, forKey: .accountId)
            let projectId = try container.decode(ProjectID.self, forKey: .projectId)
            let encodedFingerprint = try container.decode(
                ListQueryFingerprint.self,
                forKey: .queryFingerprint
            )
            try self.init(accountId: accountId, projectId: projectId)
            guard queryFingerprint == encodedFingerprint else {
                throw ProjectCoreDetailsFailure.requestFingerprintMismatch
            }
        } catch let failure as ProjectCoreDetailsFailure {
            throw failure
        } catch {
            throw ProjectCoreDetailsFailure.invalidEncodedRequest
        }
    }

    private static func makeFingerprint(
        accountId: AccountID,
        projectId: ProjectID
    ) throws -> ListQueryFingerprint {
        do {
            let basis = FingerprintBasis(
                contractVersion: "project-core-details-v1",
                accountId: accountId,
                projectId: projectId
            )
            let bytes = try OperationContractCodec.encode(basis)
            let digest = SHA256.hash(data: bytes)
                .map { String(format: "%02x", $0) }
                .joined()
            return try ListQueryFingerprint(validating: digest)
        } catch {
            throw ProjectCoreDetailsFailure.invalidEncodedRequest
        }
    }

    private struct FingerprintBasis: Codable {
        let contractVersion: String
        let accountId: AccountID
        let projectId: ProjectID
    }

    private enum CodingKeys: String, CodingKey {
        case accountId
        case projectId
        case queryFingerprint
    }
}

public struct ProjectCoreDetailsSnapshot: Codable, Equatable, Sendable {
    public let project: ProjectSummary
    public let locallyObservedRevision: ExpectedProjectRevision

    public init(
        project: ProjectSummary,
        locallyObservedRevision: ExpectedProjectRevision
    ) throws {
        guard ProjectDescriptionReplacement(project.description).value == project.description else {
            throw ProjectCoreDetailsFailure.noncanonicalDescription
        }
        self.project = project
        self.locallyObservedRevision = locallyObservedRevision
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let project: ProjectSummary
            do {
                project = try container.decode(ProjectSummary.self, forKey: .project)
            } catch ClientProjectDirectoryFailure.accountScopeMismatch {
                throw ProjectCoreDetailsFailure.accountScopeMismatch
            } catch ClientProjectDirectoryFailure.clientRelationshipMismatch {
                throw ProjectCoreDetailsFailure.clientRelationshipMismatch
            } catch {
                throw ProjectCoreDetailsFailure.invalidEncodedProject
            }
            let revision: ExpectedProjectRevision
            do {
                revision = try container.decode(
                    ExpectedProjectRevision.self,
                    forKey: .locallyObservedRevision
                )
            } catch {
                throw ProjectCoreDetailsFailure.invalidEncodedRevision
            }
            try self.init(project: project, locallyObservedRevision: revision)
        } catch let failure as ProjectCoreDetailsFailure {
            throw failure
        } catch {
            throw ProjectCoreDetailsFailure.invalidEncodedProject
        }
    }

    private enum CodingKeys: String, CodingKey {
        case project
        case locallyObservedRevision
    }
}

public struct ProjectCoreDetailsLocalSnapshot: Codable, Equatable, Sendable {
    public let request: ProjectCoreDetailsRequest
    public let local: ListLocalSnapshot<ProjectCoreDetailsSnapshot>

    public var row: ProjectCoreDetailsSnapshot? { local.rows.first }

    public var isAuthoritativeAbsence: Bool {
        local.rows.isEmpty && local.quality == .ready && local.isCompleteForQuery
    }

    public var observedRevisionIsFromCompleteReadySnapshot: Bool {
        row != nil && local.quality == .ready && local.isCompleteForQuery
    }

    public init(
        request: ProjectCoreDetailsRequest,
        rows: [ProjectCoreDetailsSnapshot],
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
        } catch let failure as ProjectCoreDetailsFailure {
            throw failure
        } catch ListQueryContractFailure.invalidVisibleRowCount {
            throw ProjectCoreDetailsFailure.visibleCountMismatch
        } catch ListQueryContractFailure.incompleteAuthoritativeEmpty {
            throw ProjectCoreDetailsFailure.invalidCompleteness
        } catch {
            throw ProjectCoreDetailsFailure.invalidEncodedLocalSnapshot
        }
    }

    public init(
        request: ProjectCoreDetailsRequest,
        local: ListLocalSnapshot<ProjectCoreDetailsSnapshot>
    ) throws {
        guard local.asOf.timeIntervalSinceReferenceDate.isFinite else {
            throw ProjectCoreDetailsFailure.invalidSnapshotAsOf
        }
        guard local.queryFingerprint == request.queryFingerprint else {
            throw ProjectCoreDetailsFailure.queryFingerprintMismatch
        }
        guard local.rows.count <= 1 else {
            throw ProjectCoreDetailsFailure.multipleRows
        }
        guard local.visibleRowCountBeforeFiltering == local.rows.count else {
            throw ProjectCoreDetailsFailure.visibleCountMismatch
        }
        guard local.rows.allSatisfy({ $0.project.accountId == request.accountId }) else {
            throw ProjectCoreDetailsFailure.accountScopeMismatch
        }
        guard local.rows.allSatisfy({ $0.project.id == request.projectId }) else {
            throw ProjectCoreDetailsFailure.projectIdentityMismatch
        }
        self.request = request
        self.local = local
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                request: container.decode(ProjectCoreDetailsRequest.self, forKey: .request),
                local: container.decode(
                    ListLocalSnapshot<ProjectCoreDetailsSnapshot>.self,
                    forKey: .local
                )
            )
        } catch let failure as ProjectCoreDetailsFailure {
            throw failure
        } catch ListQueryContractFailure.incompleteAuthoritativeEmpty {
            throw ProjectCoreDetailsFailure.invalidCompleteness
        } catch ListQueryContractFailure.invalidVisibleRowCount {
            throw ProjectCoreDetailsFailure.visibleCountMismatch
        } catch {
            throw ProjectCoreDetailsFailure.invalidEncodedLocalSnapshot
        }
    }

    private enum CodingKeys: String, CodingKey {
        case request
        case local
    }
}

public enum ProjectCoreDetailsUpdateState: Codable, Equatable, Sendable {
    case waiting(ListReadiness)
    case snapshot(ProjectCoreDetailsLocalSnapshot)
    case failed(failure: ListFailureState, cached: ProjectCoreDetailsLocalSnapshot?)
}

public struct ProjectCoreDetailsUpdate: Codable, Equatable, Sendable {
    public let request: ProjectCoreDetailsRequest
    public let state: ProjectCoreDetailsUpdateState

    public init(
        request: ProjectCoreDetailsRequest,
        state: ProjectCoreDetailsUpdateState
    ) throws {
        switch state {
        case .waiting(let readiness):
            guard [.notRequested, .loading, .blocked].contains(readiness) else {
                throw ProjectCoreDetailsFailure.invalidWaitingState
            }
        case .snapshot(let snapshot):
            guard snapshot.request == request else {
                throw ProjectCoreDetailsFailure.updateRequestMismatch
            }
        case .failed(let failure, let cached):
            guard failure != .unavailable || cached == nil else {
                throw ProjectCoreDetailsFailure.unavailableCachedEvidence
            }
            guard cached?.request == request || cached == nil else {
                throw ProjectCoreDetailsFailure.updateRequestMismatch
            }
        }
        self.request = request
        self.state = state
    }

    public func validating(request expectedRequest: ProjectCoreDetailsRequest) throws -> Self {
        guard request == expectedRequest else {
            throw ProjectCoreDetailsFailure.updateRequestMismatch
        }
        return self
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                request: container.decode(ProjectCoreDetailsRequest.self, forKey: .request),
                state: container.decode(ProjectCoreDetailsUpdateState.self, forKey: .state)
            )
        } catch let failure as ProjectCoreDetailsFailure {
            throw failure
        } catch {
            throw ProjectCoreDetailsFailure.invalidEncodedUpdate
        }
    }

    private enum CodingKeys: String, CodingKey {
        case request
        case state
    }
}

public protocol ProjectCoreDetailsQuerying: Sendable {
    func watchProjectCoreDetails(
        _ request: ProjectCoreDetailsRequest
    ) -> AsyncThrowingStream<ProjectCoreDetailsUpdate, Error>
}
