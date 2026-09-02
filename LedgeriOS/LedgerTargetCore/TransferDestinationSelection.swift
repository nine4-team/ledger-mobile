import CryptoKit
import Foundation

public enum TransferDestinationSelectionFailure: Error, Equatable, Sendable {
    case sourceDirectoryAccountMismatch
    case invalidCandidateRoute
    case duplicateDestinationIdentity
    case invalidSelectionCompleteness
    case selectionFingerprintMismatch
    case invalidEncodedCandidate
    case invalidEncodedSelection

    public var diagnosticCode: String {
        switch self {
        case .sourceDirectoryAccountMismatch:
            "transfer_destination_directory_account_mismatch"
        case .invalidCandidateRoute:
            "transfer_destination_candidate_route_invalid"
        case .duplicateDestinationIdentity:
            "transfer_destination_identity_duplicate"
        case .invalidSelectionCompleteness:
            "transfer_destination_completeness_invalid"
        case .selectionFingerprintMismatch:
            "transfer_destination_fingerprint_mismatch"
        case .invalidEncodedCandidate:
            "transfer_destination_candidate_encoding_invalid"
        case .invalidEncodedSelection:
            "transfer_destination_selection_encoding_invalid"
        }
    }
}

public enum TransferDestinationAvailability: String, Codable, CaseIterable, Sendable {
    case available
    case noEligibleDestination
    case directoryIncomplete
}

public struct TransferDestinationCandidate: Codable, Equatable, Sendable {
    public let destination: ProjectSummary
    public let route: ProjectTransferRoute

    public init(source: ProjectSummary, destination: ProjectSummary) throws {
        do {
            try self.init(
                destination: destination,
                route: ProjectTransferRoute(source: source, destination: destination)
            )
        } catch {
            throw TransferDestinationSelectionFailure.invalidCandidateRoute
        }
    }

    private init(
        destination: ProjectSummary,
        route: ProjectTransferRoute
    ) throws {
        guard destination.lifecycle == .active,
              route.destinationLifecycle == destination.lifecycle,
              route.destination.accountId == destination.accountId,
              route.destination.projectId == destination.id,
              route.destination.clientId == destination.clientId else {
            throw TransferDestinationSelectionFailure.invalidCandidateRoute
        }
        self.destination = destination
        self.route = route
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                destination: container.decode(ProjectSummary.self, forKey: .destination),
                route: container.decode(ProjectTransferRoute.self, forKey: .route)
            )
        } catch let failure as TransferDestinationSelectionFailure {
            throw failure
        } catch {
            throw TransferDestinationSelectionFailure.invalidEncodedCandidate
        }
    }

    private enum CodingKeys: String, CodingKey {
        case destination
        case route
    }
}

public struct TransferDestinationSelectionSnapshot: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let source: ProjectSummary
    public let candidates: [TransferDestinationCandidate]
    public let availability: TransferDestinationAvailability
    public let sourceDirectoryFingerprint: ListQueryFingerprint
    public let queryFingerprint: ListQueryFingerprint
    public let visibleProjectCountBeforeFiltering: Int
    public let isCompleteForSelection: Bool
    public let quality: ListSnapshotQuality
    public let localDataVersion: LocalDataVersion
    public let asOf: Date

    public var readiness: ListReadiness {
        quality.readiness
    }

    public init(source: ProjectSummary, directory: ProjectListSnapshot) throws {
        guard source.accountId == directory.accountId else {
            throw TransferDestinationSelectionFailure.sourceDirectoryAccountMismatch
        }

        let eligibleDestinations = directory.local.rows.filter {
            $0.id != source.id &&
                $0.lifecycle == .active &&
                $0.accountId == source.accountId &&
                $0.clientId == source.clientId
        }
        let candidates = try eligibleDestinations.map {
            try TransferDestinationCandidate(source: source, destination: $0)
        }
        let sourceDirectoryFingerprint = directory.local.queryFingerprint
        let queryFingerprint = try Self.makeQueryFingerprint(
            source: source,
            sourceDirectoryFingerprint: sourceDirectoryFingerprint
        )

        try self.init(
            accountId: directory.accountId,
            source: source,
            candidates: candidates,
            availability: Self.availability(
                candidateCount: candidates.count,
                isCompleteForSelection: directory.local.isCompleteForQuery,
                quality: directory.local.quality
            ),
            sourceDirectoryFingerprint: sourceDirectoryFingerprint,
            queryFingerprint: queryFingerprint,
            visibleProjectCountBeforeFiltering:
                directory.local.visibleRowCountBeforeFiltering,
            isCompleteForSelection: directory.local.isCompleteForQuery,
            quality: directory.local.quality,
            localDataVersion: directory.local.localDataVersion,
            asOf: directory.local.asOf
        )
    }

    private init(
        accountId: AccountID,
        source: ProjectSummary,
        candidates: [TransferDestinationCandidate],
        availability: TransferDestinationAvailability,
        sourceDirectoryFingerprint: ListQueryFingerprint,
        queryFingerprint: ListQueryFingerprint,
        visibleProjectCountBeforeFiltering: Int,
        isCompleteForSelection: Bool,
        quality: ListSnapshotQuality,
        localDataVersion: LocalDataVersion,
        asOf: Date
    ) throws {
        guard accountId == source.accountId else {
            throw TransferDestinationSelectionFailure.sourceDirectoryAccountMismatch
        }
        guard visibleProjectCountBeforeFiltering >= 0,
              visibleProjectCountBeforeFiltering >= candidates.count,
              !isCompleteForSelection || quality == .ready else {
            throw TransferDestinationSelectionFailure.invalidSelectionCompleteness
        }

        var destinationIds: Set<ProjectID> = []
        let expectedSourceScope = TransactionScope.project(
            accountId: source.accountId,
            projectId: source.id,
            clientId: source.clientId
        )
        for candidate in candidates {
            guard destinationIds.insert(candidate.destination.id).inserted else {
                throw TransferDestinationSelectionFailure.duplicateDestinationIdentity
            }
            guard candidate.route.source == expectedSourceScope,
                  candidate.destination.id != source.id,
                  candidate.destination.accountId == source.accountId,
                  candidate.destination.clientId == source.clientId,
                  candidate.destination.lifecycle == .active else {
                throw TransferDestinationSelectionFailure.invalidCandidateRoute
            }
        }

        let expectedAvailability = Self.availability(
            candidateCount: candidates.count,
            isCompleteForSelection: isCompleteForSelection,
            quality: quality
        )
        guard availability == expectedAvailability else {
            throw TransferDestinationSelectionFailure.invalidSelectionCompleteness
        }

        let expectedFingerprint = try Self.makeQueryFingerprint(
            source: source,
            sourceDirectoryFingerprint: sourceDirectoryFingerprint
        )
        guard queryFingerprint == expectedFingerprint else {
            throw TransferDestinationSelectionFailure.selectionFingerprintMismatch
        }

        self.accountId = accountId
        self.source = source
        self.candidates = candidates
        self.availability = availability
        self.sourceDirectoryFingerprint = sourceDirectoryFingerprint
        self.queryFingerprint = queryFingerprint
        self.visibleProjectCountBeforeFiltering = visibleProjectCountBeforeFiltering
        self.isCompleteForSelection = isCompleteForSelection
        self.quality = quality
        self.localDataVersion = localDataVersion
        self.asOf = asOf
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                accountId: container.decode(AccountID.self, forKey: .accountId),
                source: container.decode(ProjectSummary.self, forKey: .source),
                candidates: container.decode(
                    [TransferDestinationCandidate].self,
                    forKey: .candidates
                ),
                availability: container.decode(
                    TransferDestinationAvailability.self,
                    forKey: .availability
                ),
                sourceDirectoryFingerprint: container.decode(
                    ListQueryFingerprint.self,
                    forKey: .sourceDirectoryFingerprint
                ),
                queryFingerprint: container.decode(
                    ListQueryFingerprint.self,
                    forKey: .queryFingerprint
                ),
                visibleProjectCountBeforeFiltering: container.decode(
                    Int.self,
                    forKey: .visibleProjectCountBeforeFiltering
                ),
                isCompleteForSelection: container.decode(
                    Bool.self,
                    forKey: .isCompleteForSelection
                ),
                quality: container.decode(ListSnapshotQuality.self, forKey: .quality),
                localDataVersion: container.decode(
                    LocalDataVersion.self,
                    forKey: .localDataVersion
                ),
                asOf: container.decode(Date.self, forKey: .asOf)
            )
        } catch let failure as TransferDestinationSelectionFailure {
            throw failure
        } catch {
            throw TransferDestinationSelectionFailure.invalidEncodedSelection
        }
    }

    private static func availability(
        candidateCount: Int,
        isCompleteForSelection: Bool,
        quality: ListSnapshotQuality
    ) -> TransferDestinationAvailability {
        if candidateCount > 0 {
            return .available
        }
        if isCompleteForSelection && quality == .ready {
            return .noEligibleDestination
        }
        return .directoryIncomplete
    }

    private static func makeQueryFingerprint(
        source: ProjectSummary,
        sourceDirectoryFingerprint: ListQueryFingerprint
    ) throws -> ListQueryFingerprint {
        do {
            let basis = QueryFingerprintBasis(
                contractVersion: "transfer-destination-selection-v1",
                accountId: source.accountId,
                sourceProjectId: source.id,
                sourceClientId: source.clientId,
                sourceDirectoryFingerprint: sourceDirectoryFingerprint
            )
            let data = try OperationContractCodec.encode(basis)
            let digest = SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
            return try ListQueryFingerprint(validating: digest)
        } catch {
            throw TransferDestinationSelectionFailure.selectionFingerprintMismatch
        }
    }

    private struct QueryFingerprintBasis: Codable {
        let contractVersion: String
        let accountId: AccountID
        let sourceProjectId: ProjectID
        let sourceClientId: ClientID
        let sourceDirectoryFingerprint: ListQueryFingerprint
    }

    private enum CodingKeys: String, CodingKey {
        case accountId
        case source
        case candidates
        case availability
        case sourceDirectoryFingerprint
        case queryFingerprint
        case visibleProjectCountBeforeFiltering
        case isCompleteForSelection
        case quality
        case localDataVersion
        case asOf
    }
}

public protocol TransferDestinationSelectionQuerying: Sendable {
    func watchTransferDestinations(
        source: ProjectSummary
    ) -> AsyncThrowingStream<TransferDestinationSelectionSnapshot, Error>
}
