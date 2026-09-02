import CryptoKit
import Foundation

public enum ProjectPreferenceDataFailure: Error, Equatable, Sendable {
    case duplicatePinnedCategoryIdentity
    case accountScopeMismatch
    case principalScopeMismatch
    case duplicateProjectIdentity
    case visibleCountMismatch
    case invalidSnapshotAsOf
    case queryFingerprintMismatch
    case requestMismatch
    case localReadFailed
    case invalidEncodedPreference
    case invalidEncodedRequest
    case invalidEncodedDirectory

    public var diagnosticCode: String {
        switch self {
        case .duplicatePinnedCategoryIdentity:
            "project_preference_pinned_category_duplicate"
        case .accountScopeMismatch:
            "project_preference_account_scope_mismatch"
        case .principalScopeMismatch:
            "project_preference_principal_scope_mismatch"
        case .duplicateProjectIdentity:
            "project_preference_project_identity_duplicate"
        case .visibleCountMismatch:
            "project_preference_visible_count_mismatch"
        case .invalidSnapshotAsOf:
            "project_preference_as_of_invalid"
        case .queryFingerprintMismatch:
            "project_preference_query_fingerprint_mismatch"
        case .requestMismatch:
            "project_preference_request_mismatch"
        case .localReadFailed:
            "project_preference_local_read_failed"
        case .invalidEncodedPreference:
            "project_preference_encoding_invalid"
        case .invalidEncodedRequest:
            "project_preference_request_encoding_invalid"
        case .invalidEncodedDirectory:
            "project_preference_directory_encoding_invalid"
        }
    }
}

public struct ProjectPreferenceSnapshot: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let principalId: PrincipalID
    public let projectId: ProjectID
    public let pinnedCategoryIds: [BudgetCategoryID]
    public let revision: UInt64

    public init(
        accountId: AccountID,
        principalId: PrincipalID,
        projectId: ProjectID,
        pinnedCategoryIds: [BudgetCategoryID],
        revision: UInt64
    ) throws {
        guard Set(pinnedCategoryIds).count == pinnedCategoryIds.count else {
            throw ProjectPreferenceDataFailure.duplicatePinnedCategoryIdentity
        }
        self.accountId = accountId
        self.principalId = principalId
        self.projectId = projectId
        self.pinnedCategoryIds = pinnedCategoryIds
        self.revision = revision
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                accountId: container.decode(AccountID.self, forKey: .accountId),
                principalId: container.decode(PrincipalID.self, forKey: .principalId),
                projectId: container.decode(ProjectID.self, forKey: .projectId),
                pinnedCategoryIds: container.decode(
                    [BudgetCategoryID].self,
                    forKey: .pinnedCategoryIds
                ),
                revision: container.decode(UInt64.self, forKey: .revision)
            )
        } catch let failure as ProjectPreferenceDataFailure {
            throw failure
        } catch {
            throw ProjectPreferenceDataFailure.invalidEncodedPreference
        }
    }

    private enum CodingKeys: String, CodingKey {
        case accountId
        case principalId
        case projectId
        case pinnedCategoryIds
        case revision
    }
}

public struct ProjectPreferenceDirectoryRequest: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let principalId: PrincipalID
    public let queryFingerprint: ListQueryFingerprint

    public init(accountId: AccountID, principalId: PrincipalID) throws {
        self.accountId = accountId
        self.principalId = principalId
        queryFingerprint = try Self.makeFingerprint(
            accountId: accountId,
            principalId: principalId
        )
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                accountId: container.decode(AccountID.self, forKey: .accountId),
                principalId: container.decode(PrincipalID.self, forKey: .principalId)
            )
        } catch let failure as ProjectPreferenceDataFailure {
            throw failure
        } catch {
            throw ProjectPreferenceDataFailure.invalidEncodedRequest
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accountId, forKey: .accountId)
        try container.encode(principalId, forKey: .principalId)
    }

    public func validate(
        _ snapshot: ProjectPreferenceDirectorySnapshot
    ) throws -> ProjectPreferenceDirectorySnapshot {
        guard snapshot.request == self else {
            throw ProjectPreferenceDataFailure.requestMismatch
        }
        return snapshot
    }

    private static func makeFingerprint(
        accountId: AccountID,
        principalId: PrincipalID
    ) throws -> ListQueryFingerprint {
        let basis = FingerprintBasis(accountId: accountId, principalId: principalId)
        let bytes = try OperationContractCodec.encode(basis)
        let digest = SHA256.hash(data: bytes)
            .map { String(format: "%02x", $0) }
            .joined()
        return try ListQueryFingerprint(validating: digest)
    }

    private struct FingerprintBasis: Codable {
        let accountId: AccountID
        let principalId: PrincipalID
    }

    private enum CodingKeys: String, CodingKey {
        case accountId
        case principalId
    }
}

public enum ProjectPreferenceLookupState: Equatable, Sendable {
    case stored(ProjectPreferenceSnapshot)
    case notStored
    case notAvailable
}

public struct ProjectPreferenceDirectorySnapshot: Codable, Equatable, Sendable {
    public let request: ProjectPreferenceDirectoryRequest
    public let local: ListLocalSnapshot<ProjectPreferenceSnapshot>

    public init(
        request: ProjectPreferenceDirectoryRequest,
        local: ListLocalSnapshot<ProjectPreferenceSnapshot>
    ) throws {
        guard local.asOf.timeIntervalSinceReferenceDate.isFinite else {
            throw ProjectPreferenceDataFailure.invalidSnapshotAsOf
        }
        guard local.queryFingerprint == request.queryFingerprint else {
            throw ProjectPreferenceDataFailure.queryFingerprintMismatch
        }
        guard local.rows.allSatisfy({ $0.accountId == request.accountId }) else {
            throw ProjectPreferenceDataFailure.accountScopeMismatch
        }
        guard local.rows.allSatisfy({ $0.principalId == request.principalId }) else {
            throw ProjectPreferenceDataFailure.principalScopeMismatch
        }
        guard Set(local.rows.map(\.projectId)).count == local.rows.count else {
            throw ProjectPreferenceDataFailure.duplicateProjectIdentity
        }
        guard local.visibleRowCountBeforeFiltering == local.rows.count else {
            throw ProjectPreferenceDataFailure.visibleCountMismatch
        }

        let rows = local.rows.sorted { $0.projectId.rawValue < $1.projectId.rawValue }
        self.request = request
        self.local = try ListLocalSnapshot(
            queryFingerprint: local.queryFingerprint,
            rows: rows,
            visibleRowCountBeforeFiltering: local.visibleRowCountBeforeFiltering,
            isCompleteForQuery: local.isCompleteForQuery,
            quality: local.quality,
            localDataVersion: local.localDataVersion,
            asOf: local.asOf
        )
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                request: container.decode(
                    ProjectPreferenceDirectoryRequest.self,
                    forKey: .request
                ),
                local: container.decode(
                    ListLocalSnapshot<ProjectPreferenceSnapshot>.self,
                    forKey: .local
                )
            )
        } catch let failure as ProjectPreferenceDataFailure {
            throw failure
        } catch {
            throw ProjectPreferenceDataFailure.invalidEncodedDirectory
        }
    }

    public func preference(for projectId: ProjectID) -> ProjectPreferenceLookupState {
        if let preference = local.rows.first(where: { $0.projectId == projectId }) {
            return .stored(preference)
        }
        return local.isCompleteForQuery ? .notStored : .notAvailable
    }

    private enum CodingKeys: String, CodingKey {
        case request
        case local
    }
}

public protocol ProjectPreferenceQuerying: Sendable {
    func watchProjectPreferences(
        _ request: ProjectPreferenceDirectoryRequest
    ) -> AsyncThrowingStream<ProjectPreferenceDirectorySnapshot, Error>
}
