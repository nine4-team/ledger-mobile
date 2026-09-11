import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Transfer Destination Selection Contracts")
struct TransferDestinationSelectionTests {
    @Test("Only other active exact same-Client Projects become candidates")
    func exactDestinationFiltering() throws {
        let fixture = try Self.fixture()
        let directory = try Self.directory(
            accountId: fixture.accountId,
            rows: [
                fixture.sameNameOtherClientProject,
                fixture.destinationB,
                fixture.source,
                fixture.archivedDestination,
                fixture.destinationA
            ],
            fingerprintScalar: "a",
            isComplete: true,
            quality: .ready,
            version: "directory-filter-v1"
        )
        let snapshot = try TransferDestinationSelectionSnapshot(
            source: fixture.source,
            directory: directory
        )

        #expect(snapshot.accountId == fixture.accountId)
        #expect(snapshot.source == fixture.source)
        #expect(snapshot.candidates.map(\.destination.id) == [
            fixture.destinationB.id,
            fixture.destinationA.id
        ])
        #expect(snapshot.candidates.allSatisfy {
            $0.destination.clientId == fixture.client.id &&
                $0.destination.lifecycle == .active &&
                $0.destination.id != fixture.source.id &&
                $0.route.source.projectId == fixture.source.id &&
                $0.route.destination.projectId == $0.destination.id
        })
        #expect(!snapshot.candidates.contains {
            $0.destination.id == fixture.sameNameOtherClientProject.id
        })
        #expect(snapshot.availability == .available)
        #expect(snapshot.readiness == .ready)
        #expect(snapshot.isCompleteForSelection)
        #expect(snapshot.sourceDirectoryFingerprint == directory.local.queryFingerprint)
        #expect(snapshot.queryFingerprint != snapshot.sourceDirectoryFingerprint)

        let otherSource = try TransferDestinationSelectionSnapshot(
            source: fixture.destinationA,
            directory: directory
        )
        #expect(otherSource.queryFingerprint != snapshot.queryFingerprint)

        let otherDirectoryFingerprint = try Self.directory(
            accountId: fixture.accountId,
            rows: directory.local.rows,
            fingerprintScalar: "b",
            isComplete: true,
            quality: .ready,
            version: "directory-filter-v1"
        )
        let rebound = try TransferDestinationSelectionSnapshot(
            source: fixture.source,
            directory: otherDirectoryFingerprint
        )
        #expect(rebound.queryFingerprint != snapshot.queryFingerprint)
    }

    @Test("Available, authoritative-empty, and incomplete states remain distinct")
    func localAvailabilityAndReadiness() throws {
        let fixture = try Self.fixture()
        let authoritativeEmpty = try TransferDestinationSelectionSnapshot(
            source: fixture.source,
            directory: Self.directory(
                accountId: fixture.accountId,
                rows: [fixture.source, fixture.archivedDestination],
                fingerprintScalar: "c",
                isComplete: true,
                quality: .ready,
                version: "directory-empty-v1"
            )
        )
        let incompleteEmpty = try TransferDestinationSelectionSnapshot(
            source: fixture.source,
            directory: Self.directory(
                accountId: fixture.accountId,
                rows: [fixture.source],
                fingerprintScalar: "d",
                isComplete: false,
                quality: .partial,
                version: "directory-partial-v1"
            )
        )
        let incompleteAvailable = try TransferDestinationSelectionSnapshot(
            source: fixture.source,
            directory: Self.directory(
                accountId: fixture.accountId,
                rows: [fixture.source, fixture.destinationA],
                fingerprintScalar: "e",
                isComplete: false,
                quality: .stale,
                version: "directory-stale-v1"
            )
        )

        #expect(authoritativeEmpty.candidates.isEmpty)
        #expect(authoritativeEmpty.availability == .noEligibleDestination)
        #expect(authoritativeEmpty.readiness == .ready)
        #expect(authoritativeEmpty.isCompleteForSelection)

        #expect(incompleteEmpty.candidates.isEmpty)
        #expect(incompleteEmpty.availability == .directoryIncomplete)
        #expect(incompleteEmpty.readiness == .partial)
        #expect(!incompleteEmpty.isCompleteForSelection)

        #expect(incompleteAvailable.candidates.map(\.destination.id) == [
            fixture.destinationA.id
        ])
        #expect(incompleteAvailable.availability == .available)
        #expect(incompleteAvailable.readiness == .stale)
        #expect(!incompleteAvailable.isCompleteForSelection)
        #expect(
            incompleteAvailable.visibleProjectCountBeforeFiltering == 2
        )
    }

    @Test("Selection evidence and the local read port survive canonical restart")
    func canonicalRestartAndPort() async throws {
        let fixture = try Self.fixture()
        let available = try TransferDestinationSelectionSnapshot(
            source: fixture.source,
            directory: Self.directory(
                accountId: fixture.accountId,
                rows: [fixture.source, fixture.destinationA, fixture.destinationB],
                fingerprintScalar: "1",
                isComplete: true,
                quality: .ready,
                version: "directory-restart-ready"
            )
        )
        let incomplete = try TransferDestinationSelectionSnapshot(
            source: fixture.source,
            directory: Self.directory(
                accountId: fixture.accountId,
                rows: [fixture.source],
                fingerprintScalar: "2",
                isComplete: false,
                quality: .partial,
                version: "directory-restart-partial"
            )
        )
        let evidence = RestartEvidence(snapshots: [available, incomplete])
        let bytes = try OperationContractCodec.encode(evidence)
        let restored = try OperationContractCodec.decode(
            RestartEvidence.self,
            from: bytes
        )

        #expect(restored == evidence)
        #expect(try OperationContractCodec.encode(restored) == bytes)

        let port = InMemoryDestinationPort(
            sourceProjectId: fixture.source.id,
            snapshots: restored.snapshots
        )
        var iterator = port
            .watchTransferDestinations(source: fixture.source)
            .makeAsyncIterator()
        let first = try await iterator.next()
        let second = try await iterator.next()
        let terminal = try await iterator.next()
        #expect(first == available)
        #expect(second == incomplete)
        #expect(terminal == nil)
    }

    @Test("Mismatched, duplicate, incomplete, malformed, and tampered evidence fails")
    func invalidSelectionEvidence() throws {
        let fixture = try Self.fixture()
        let validDirectory = try Self.directory(
            accountId: fixture.accountId,
            rows: [fixture.source, fixture.destinationA],
            fingerprintScalar: "3",
            isComplete: true,
            quality: .ready,
            version: "directory-invalid-v1"
        )
        let valid = try TransferDestinationSelectionSnapshot(
            source: fixture.source,
            directory: validDirectory
        )

        let otherAccountId = try AccountID(validating: "account-other")
        let otherClient = try Self.client(
            id: "client-other-account",
            accountId: otherAccountId,
            displayName: fixture.client.displayName
        )
        let otherProject = try Self.project(
            id: "project-other-account",
            accountId: otherAccountId,
            client: otherClient,
            displayName: "Other Account Project",
            lifecycle: .active
        )
        let otherDirectory = try Self.directory(
            accountId: otherAccountId,
            rows: [otherProject],
            fingerprintScalar: "4",
            isComplete: true,
            quality: .ready,
            version: "directory-other-account"
        )
        #expect(Self.captureFailure {
            _ = try TransferDestinationSelectionSnapshot(
                source: fixture.source,
                directory: otherDirectory
            )
        } == .sourceDirectoryAccountMismatch)

        let routeA = try ProjectTransferRoute(
            source: fixture.source,
            destination: fixture.destinationA
        )
        let mismatchedCandidate = CandidateWire(
            destination: fixture.destinationB,
            route: routeA
        )
        #expect(Self.captureFailure {
            _ = try OperationContractCodec.decode(
                TransferDestinationCandidate.self,
                from: OperationContractCodec.encode(mismatchedCandidate)
            )
        } == .invalidCandidateRoute)

        #expect(Self.captureFailure {
            _ = try OperationContractCodec.decode(
                TransferDestinationCandidate.self,
                from: Data("{}".utf8)
            )
        } == .invalidEncodedCandidate)

        let duplicateWire = SelectionWire(
            snapshot: valid,
            candidates: [valid.candidates[0], valid.candidates[0]],
            visibleProjectCountBeforeFiltering: 2
        )
        #expect(Self.captureFailure {
            _ = try OperationContractCodec.decode(
                TransferDestinationSelectionSnapshot.self,
                from: OperationContractCodec.encode(duplicateWire)
            )
        } == .duplicateDestinationIdentity)

        let incompleteWire = SelectionWire(
            snapshot: valid,
            isCompleteForSelection: true,
            quality: .partial
        )
        #expect(Self.captureFailure {
            _ = try OperationContractCodec.decode(
                TransferDestinationSelectionSnapshot.self,
                from: OperationContractCodec.encode(incompleteWire)
            )
        } == .invalidSelectionCompleteness)

        let tamperedFingerprint = try ListQueryFingerprint(
            validating: String(repeating: "f", count: 64)
        )
        let sourceWire = SelectionWire(
            snapshot: valid,
            source: fixture.destinationB
        )
        #expect(Self.captureFailure {
            _ = try OperationContractCodec.decode(
                TransferDestinationSelectionSnapshot.self,
                from: OperationContractCodec.encode(sourceWire)
            )
        } == .invalidCandidateRoute)

        let directoryFingerprintWire = SelectionWire(
            snapshot: valid,
            sourceDirectoryFingerprint: tamperedFingerprint
        )
        #expect(Self.captureFailure {
            _ = try OperationContractCodec.decode(
                TransferDestinationSelectionSnapshot.self,
                from: OperationContractCodec.encode(directoryFingerprintWire)
            )
        } == .selectionFingerprintMismatch)

        let fingerprintWire = SelectionWire(
            snapshot: valid,
            queryFingerprint: tamperedFingerprint
        )
        #expect(Self.captureFailure {
            _ = try OperationContractCodec.decode(
                TransferDestinationSelectionSnapshot.self,
                from: OperationContractCodec.encode(fingerprintWire)
            )
        } == .selectionFingerprintMismatch)

        #expect(Self.captureFailure {
            _ = try OperationContractCodec.decode(
                TransferDestinationSelectionSnapshot.self,
                from: Data("{}".utf8)
            )
        } == .invalidEncodedSelection)

        let diagnostics: [(TransferDestinationSelectionFailure, String)] = [
            (
                .sourceDirectoryAccountMismatch,
                "transfer_destination_directory_account_mismatch"
            ),
            (.invalidCandidateRoute, "transfer_destination_candidate_route_invalid"),
            (.duplicateDestinationIdentity, "transfer_destination_identity_duplicate"),
            (.invalidSelectionCompleteness, "transfer_destination_completeness_invalid"),
            (.selectionFingerprintMismatch, "transfer_destination_fingerprint_mismatch"),
            (
                .invalidEncodedCandidate,
                "transfer_destination_candidate_encoding_invalid"
            ),
            (
                .invalidEncodedSelection,
                "transfer_destination_selection_encoding_invalid"
            )
        ]
        for (failure, code) in diagnostics {
            #expect(failure.diagnosticCode == code)
        }
    }

    private struct Fixture: Sendable {
        let accountId: AccountID
        let client: ClientSummary
        let source: ProjectSummary
        let destinationA: ProjectSummary
        let destinationB: ProjectSummary
        let archivedDestination: ProjectSummary
        let sameNameOtherClientProject: ProjectSummary
    }

    private struct RestartEvidence: Codable, Equatable, Sendable {
        let snapshots: [TransferDestinationSelectionSnapshot]
    }

    private struct CandidateWire: Codable {
        let destination: ProjectSummary
        let route: ProjectTransferRoute
    }

    private struct SelectionWire: Codable {
        let accountId: AccountID
        let source: ProjectSummary
        let candidates: [TransferDestinationCandidate]
        let availability: TransferDestinationAvailability
        let sourceDirectoryFingerprint: ListQueryFingerprint
        let queryFingerprint: ListQueryFingerprint
        let visibleProjectCountBeforeFiltering: Int
        let isCompleteForSelection: Bool
        let quality: ListSnapshotQuality
        let localDataVersion: LocalDataVersion
        let asOf: Date

        init(
            snapshot: TransferDestinationSelectionSnapshot,
            source: ProjectSummary? = nil,
            candidates: [TransferDestinationCandidate]? = nil,
            sourceDirectoryFingerprint: ListQueryFingerprint? = nil,
            queryFingerprint: ListQueryFingerprint? = nil,
            visibleProjectCountBeforeFiltering: Int? = nil,
            isCompleteForSelection: Bool? = nil,
            quality: ListSnapshotQuality? = nil
        ) {
            accountId = snapshot.accountId
            self.source = source ?? snapshot.source
            self.candidates = candidates ?? snapshot.candidates
            availability = snapshot.availability
            self.sourceDirectoryFingerprint =
                sourceDirectoryFingerprint ?? snapshot.sourceDirectoryFingerprint
            self.queryFingerprint = queryFingerprint ?? snapshot.queryFingerprint
            self.visibleProjectCountBeforeFiltering =
                visibleProjectCountBeforeFiltering ??
                snapshot.visibleProjectCountBeforeFiltering
            self.isCompleteForSelection =
                isCompleteForSelection ?? snapshot.isCompleteForSelection
            self.quality = quality ?? snapshot.quality
            localDataVersion = snapshot.localDataVersion
            asOf = snapshot.asOf
        }
    }

    private struct InMemoryDestinationPort: TransferDestinationSelectionQuerying {
        let sourceProjectId: ProjectID
        let snapshots: [TransferDestinationSelectionSnapshot]

        func watchTransferDestinations(
            source: ProjectSummary
        ) -> AsyncThrowingStream<TransferDestinationSelectionSnapshot, Error> {
            AsyncThrowingStream(
                TransferDestinationSelectionSnapshot.self,
                bufferingPolicy: .unbounded
            ) { continuation in
                guard source.id == sourceProjectId else {
                    continuation.finish(
                        throwing: TransferDestinationSelectionFailure.invalidCandidateRoute
                    )
                    return
                }
                for snapshot in snapshots {
                    continuation.yield(snapshot)
                }
                continuation.finish()
            }
        }
    }

    private static func fixture() throws -> Fixture {
        let accountId = try AccountID(validating: "account-main")
        let displayName = try ClientDisplayName(validating: "Same Display Name")
        let client = try Self.client(
            id: "client-primary",
            accountId: accountId,
            displayName: displayName
        )
        let otherClient = try Self.client(
            id: "client-other",
            accountId: accountId,
            displayName: displayName
        )
        return try Fixture(
            accountId: accountId,
            client: client,
            source: Self.project(
                id: "project-source",
                accountId: accountId,
                client: client,
                displayName: "Source Project",
                lifecycle: .active
            ),
            destinationA: Self.project(
                id: "project-destination-a",
                accountId: accountId,
                client: client,
                displayName: "Destination A",
                lifecycle: .active
            ),
            destinationB: Self.project(
                id: "project-destination-b",
                accountId: accountId,
                client: client,
                displayName: "Destination B",
                lifecycle: .active
            ),
            archivedDestination: Self.project(
                id: "project-archived",
                accountId: accountId,
                client: client,
                displayName: "Archived Destination",
                lifecycle: .archived
            ),
            sameNameOtherClientProject: Self.project(
                id: "project-other-client",
                accountId: accountId,
                client: otherClient,
                displayName: "Destination A",
                lifecycle: .active
            )
        )
    }

    private static func client(
        id: String,
        accountId: AccountID,
        displayName: ClientDisplayName
    ) throws -> ClientSummary {
        try ClientSummary(
            id: ClientID(validating: id),
            accountId: accountId,
            displayName: displayName,
            lifecycle: .active,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
    }

    private static func project(
        id: String,
        accountId: AccountID,
        client: ClientSummary,
        displayName: String,
        lifecycle: DirectoryLifecycleState
    ) throws -> ProjectSummary {
        try ProjectSummary(
            id: ProjectID(validating: id),
            accountId: accountId,
            clientId: client.id,
            client: client,
            displayName: ProjectDisplayName(validating: displayName),
            description: nil,
            lifecycle: lifecycle
        )
    }

    private static func directory(
        accountId: AccountID,
        rows: [ProjectSummary],
        fingerprintScalar: Character,
        isComplete: Bool,
        quality: ListSnapshotQuality,
        version: String
    ) throws -> ProjectListSnapshot {
        let local = try ListLocalSnapshot(
            queryFingerprint: ListQueryFingerprint(
                validating: String(repeating: fingerprintScalar, count: 64)
            ),
            rows: rows,
            visibleRowCountBeforeFiltering: rows.count,
            isCompleteForQuery: isComplete,
            quality: quality,
            localDataVersion: LocalDataVersion(validating: version),
            asOf: Date(timeIntervalSince1970: 1_800_000_200)
        )
        return try ProjectListSnapshot(accountId: accountId, local: local)
    }

    private static func captureFailure<Value>(
        _ body: () throws -> Value
    ) -> TransferDestinationSelectionFailure? {
        do {
            _ = try body()
            return nil
        } catch let failure as TransferDestinationSelectionFailure {
            return failure
        } catch {
            return nil
        }
    }
}
