import CryptoKit
import Foundation

public enum SpaceAssignmentDestinationFailure: Error, Equatable, Sendable {
    case accountScopeMismatch
    case placementScopeMismatch
    case inactiveDestination
    case duplicateSpaceIdentity
    case visibleCountMismatch
    case invalidSnapshotAsOf
    case requestFingerprintMismatch
    case queryFingerprintMismatch
    case localReadFailed
    case invalidEncodedRequest
    case invalidEncodedDestination
    case invalidEncodedDirectory

    public var diagnosticCode: String {
        switch self {
        case .accountScopeMismatch:
            "space_assignment_destination_account_scope_mismatch"
        case .placementScopeMismatch:
            "space_assignment_destination_placement_scope_mismatch"
        case .inactiveDestination:
            "space_assignment_destination_inactive"
        case .duplicateSpaceIdentity:
            "space_assignment_destination_identity_duplicate"
        case .visibleCountMismatch:
            "space_assignment_destination_visible_count_mismatch"
        case .invalidSnapshotAsOf:
            "space_assignment_destination_as_of_invalid"
        case .requestFingerprintMismatch:
            "space_assignment_destination_request_fingerprint_mismatch"
        case .queryFingerprintMismatch:
            "space_assignment_destination_query_fingerprint_mismatch"
        case .localReadFailed:
            "space_assignment_destination_local_read_failed"
        case .invalidEncodedRequest:
            "space_assignment_destination_request_encoding_invalid"
        case .invalidEncodedDestination:
            "space_assignment_destination_row_encoding_invalid"
        case .invalidEncodedDirectory:
            "space_assignment_destination_directory_encoding_invalid"
        }
    }
}

public struct SpaceAssignmentDestinationRequest: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let scope: ItemPlacementScope
    public let queryFingerprint: ListQueryFingerprint

    public init(accountId: AccountID, scope: ItemPlacementScope) throws {
        self.accountId = accountId
        self.scope = scope
        queryFingerprint = try Self.makeFingerprint(accountId: accountId, scope: scope)
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let accountId = try container.decode(AccountID.self, forKey: .accountId)
            let scope = try container.decode(ItemPlacementScope.self, forKey: .scope)
            let encodedFingerprint = try container.decode(
                ListQueryFingerprint.self,
                forKey: .queryFingerprint
            )
            try self.init(accountId: accountId, scope: scope)
            guard queryFingerprint == encodedFingerprint else {
                throw SpaceAssignmentDestinationFailure.requestFingerprintMismatch
            }
        } catch let failure as SpaceAssignmentDestinationFailure {
            throw failure
        } catch {
            throw SpaceAssignmentDestinationFailure.invalidEncodedRequest
        }
    }

    private static func makeFingerprint(
        accountId: AccountID,
        scope: ItemPlacementScope
    ) throws -> ListQueryFingerprint {
        do {
            let basis = FingerprintBasis(
                contractVersion: "space-assignment-destination-v1",
                accountId: accountId,
                scope: scope
            )
            let bytes = try OperationContractCodec.encode(basis)
            let digest = SHA256.hash(data: bytes)
                .map { String(format: "%02x", $0) }
                .joined()
            return try ListQueryFingerprint(validating: digest)
        } catch let failure as SpaceAssignmentDestinationFailure {
            throw failure
        } catch {
            throw SpaceAssignmentDestinationFailure.invalidEncodedRequest
        }
    }

    private struct FingerprintBasis: Codable {
        let contractVersion: String
        let accountId: AccountID
        let scope: ItemPlacementScope
    }

    private enum CodingKeys: String, CodingKey {
        case accountId
        case scope
        case queryFingerprint
    }
}

public struct SpaceAssignmentDestinationSnapshot: Codable, Equatable, Sendable {
    public let id: SpaceID
    public let accountId: AccountID
    public let scope: ItemPlacementScope
    public let displayName: SpaceDisplayName
    public let lifecycle: DirectoryLifecycleState
    public let revision: UInt64

    public init(
        id: SpaceID,
        accountId: AccountID,
        scope: ItemPlacementScope,
        displayName: SpaceDisplayName,
        lifecycle: DirectoryLifecycleState,
        revision: UInt64
    ) throws {
        guard lifecycle == .active else {
            throw SpaceAssignmentDestinationFailure.inactiveDestination
        }
        self.id = id
        self.accountId = accountId
        self.scope = scope
        self.displayName = displayName
        self.lifecycle = lifecycle
        self.revision = revision
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                id: container.decode(SpaceID.self, forKey: .id),
                accountId: container.decode(AccountID.self, forKey: .accountId),
                scope: container.decode(ItemPlacementScope.self, forKey: .scope),
                displayName: container.decode(SpaceDisplayName.self, forKey: .displayName),
                lifecycle: container.decode(
                    DirectoryLifecycleState.self,
                    forKey: .lifecycle
                ),
                revision: container.decode(UInt64.self, forKey: .revision)
            )
        } catch let failure as SpaceAssignmentDestinationFailure {
            throw failure
        } catch {
            throw SpaceAssignmentDestinationFailure.invalidEncodedDestination
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case accountId
        case scope
        case displayName
        case lifecycle
        case revision
    }
}

public struct SpaceAssignmentDestinationDirectorySnapshot: Codable, Equatable, Sendable {
    public let request: SpaceAssignmentDestinationRequest
    public let local: ListLocalSnapshot<SpaceAssignmentDestinationSnapshot>

    public init(
        request: SpaceAssignmentDestinationRequest,
        local: ListLocalSnapshot<SpaceAssignmentDestinationSnapshot>
    ) throws {
        guard local.asOf.timeIntervalSinceReferenceDate.isFinite else {
            throw SpaceAssignmentDestinationFailure.invalidSnapshotAsOf
        }
        guard local.queryFingerprint == request.queryFingerprint else {
            throw SpaceAssignmentDestinationFailure.queryFingerprintMismatch
        }
        guard local.rows.allSatisfy({ $0.accountId == request.accountId }) else {
            throw SpaceAssignmentDestinationFailure.accountScopeMismatch
        }
        guard local.rows.allSatisfy({ $0.scope == request.scope }) else {
            throw SpaceAssignmentDestinationFailure.placementScopeMismatch
        }
        guard local.rows.allSatisfy({ $0.lifecycle == .active }) else {
            throw SpaceAssignmentDestinationFailure.inactiveDestination
        }
        guard local.visibleRowCountBeforeFiltering == local.rows.count else {
            throw SpaceAssignmentDestinationFailure.visibleCountMismatch
        }
        guard Self.firstDuplicate(local.rows.map(\.id)) == nil else {
            throw SpaceAssignmentDestinationFailure.duplicateSpaceIdentity
        }

        let rows = local.rows.sorted(by: Self.precedes)
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
                    SpaceAssignmentDestinationRequest.self,
                    forKey: .request
                ),
                local: container.decode(
                    ListLocalSnapshot<SpaceAssignmentDestinationSnapshot>.self,
                    forKey: .local
                )
            )
        } catch let failure as SpaceAssignmentDestinationFailure {
            throw failure
        } catch {
            throw SpaceAssignmentDestinationFailure.invalidEncodedDirectory
        }
    }

    private static func precedes(
        _ lhs: SpaceAssignmentDestinationSnapshot,
        _ rhs: SpaceAssignmentDestinationSnapshot
    ) -> Bool {
        let lhsFolded = lhs.displayName.rawValue.lowercased()
        let rhsFolded = rhs.displayName.rawValue.lowercased()
        if lhsFolded != rhsFolded {
            return lhsFolded < rhsFolded
        }
        if lhs.displayName.rawValue != rhs.displayName.rawValue {
            return lhs.displayName.rawValue < rhs.displayName.rawValue
        }
        return lhs.id.rawValue < rhs.id.rawValue
    }

    private static func firstDuplicate<Value: Hashable>(_ values: [Value]) -> Value? {
        var seen: Set<Value> = []
        return values.first { !seen.insert($0).inserted }
    }

    private enum CodingKeys: String, CodingKey {
        case request
        case local
    }
}

public protocol SpaceAssignmentDestinationQuerying: Sendable {
    func watchEligibleDestinations(
        _ request: SpaceAssignmentDestinationRequest
    ) -> AsyncThrowingStream<SpaceAssignmentDestinationDirectorySnapshot, Error>
}
