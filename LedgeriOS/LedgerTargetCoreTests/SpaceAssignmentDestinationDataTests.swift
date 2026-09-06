import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Space Assignment Destination Read Contracts")
struct SpaceAssignmentDestinationDataTests {
    @Test("Project and Inventory directories expose only exact active destination evidence")
    func exactScopeRowsAndCanonicalOrdering() throws {
        let fixture = try Self.fixture()
        let projectRows = fixture.project.local.rows

        #expect(projectRows.map(\.id.rawValue) == [
            "space-kitchen",
            "space-loft-uppercase",
            "space-loft-a",
            "space-loft-z"
        ])
        #expect(projectRows.map(\.displayName.rawValue) == [
            "Kitchen", "Loft", "loft", "loft"
        ])
        #expect(projectRows.map(\.revision) == [7, 8, 9, 10])
        #expect(projectRows.allSatisfy { $0.accountId == fixture.accountId })
        #expect(projectRows.allSatisfy { $0.scope == fixture.projectRequest.scope })
        #expect(projectRows.allSatisfy { $0.lifecycle == .active })
        #expect(fixture.project.request == fixture.projectRequest)
        #expect(fixture.project.local.queryFingerprint == fixture.projectRequest.queryFingerprint)
        #expect(fixture.inventory.request == fixture.inventoryRequest)
        #expect(fixture.inventory.local.rows.map(\.id.rawValue) == ["space-warehouse"])
        #expect(fixture.inventory.local.rows[0].scope == .businessInventory)

        let bytes = try OperationContractCodec.encode(fixture.project)
        let root = try #require(
            JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        )
        #expect(Set(root.keys) == Set(["request", "local"]))
        let request = try #require(root["request"] as? [String: Any])
        #expect(Set(request.keys) == Set(["accountId", "scope", "queryFingerprint"]))
        let local = try #require(root["local"] as? [String: Any])
        let encodedRows = try #require(local["rows"] as? [[String: Any]])
        let first = try #require(encodedRows.first)
        #expect(Set(first.keys) == Set([
            "id", "accountId", "scope", "displayName", "lifecycle", "revision"
        ]))

        let text = String(decoding: bytes, as: UTF8.self).lowercased()
        for forbidden in [
            "firebase", "firestore", "supabase", "powersync", "https://", "file://",
            "bearer", "token", "secret", "serviceaccount", "service_account",
            "authorized", "authorization", "attachment", "marker", "media", "image",
            "transaction", "invoice", "budget", "amount", "price", "sql"
        ] {
            #expect(!text.contains(forbidden))
        }
    }

    @Test("Ready, authoritative-empty, partial, and stale directories restart canonically")
    func readinessAndEquivalentInputSurviveRestart() throws {
        let fixture = try Self.fixture()
        let first = fixture.project.local.rows[0]
        let authoritativeEmpty = try Self.directory(
            request: fixture.projectRequest,
            rows: [],
            quality: .ready,
            isComplete: true,
            version: "space-dest-empty",
            asOf: Self.t1
        )
        let partial = try Self.directory(
            request: fixture.projectRequest,
            rows: [first],
            quality: .partial,
            isComplete: false,
            version: "space-dest-partial",
            asOf: Self.t2
        )
        let stale = try Self.directory(
            request: fixture.inventoryRequest,
            rows: fixture.inventory.local.rows,
            quality: .stale,
            isComplete: false,
            version: "space-dest-stale",
            asOf: Self.t3
        )
        let equivalentProject = try Self.directory(
            request: fixture.projectRequest,
            rows: fixture.project.local.rows.reversed(),
            quality: .ready,
            isComplete: true,
            version: "space-dest-project",
            asOf: Self.t0
        )
        #expect(equivalentProject == fixture.project)
        #expect(
            try OperationContractCodec.encode(equivalentProject)
                == OperationContractCodec.encode(fixture.project)
        )

        let restart = RestartFixture(
            projectReady: fixture.project,
            inventoryReady: fixture.inventory,
            authoritativeEmpty: authoritativeEmpty,
            partial: partial,
            stale: stale
        )
        let bytes = try OperationContractCodec.encode(restart)
        let restored = try OperationContractCodec.decode(RestartFixture.self, from: bytes)

        #expect(restored == restart)
        #expect(try OperationContractCodec.encode(restored) == bytes)
        #expect(restored.projectReady.local.quality == .ready)
        #expect(restored.projectReady.local.isCompleteForQuery)
        #expect(restored.inventoryReady.request.scope == .businessInventory)
        #expect(restored.authoritativeEmpty.local.rows.isEmpty)
        #expect(restored.authoritativeEmpty.local.isCompleteForQuery)
        #expect(restored.authoritativeEmpty.local.visibleRowCountBeforeFiltering == 0)
        #expect(restored.partial.local.quality == .partial)
        #expect(!restored.partial.local.isCompleteForQuery)
        #expect(restored.stale.local.quality == .stale)
        #expect(!restored.stale.local.isCompleteForQuery)
        #expect(restored.stale.local.rows[0].revision == 41)
    }

    @Test("Cross-scope, inactive, duplicate, hidden, malformed, and rebound evidence fails")
    func invalidAndReboundEvidenceFailsClosed() throws {
        let fixture = try Self.fixture()
        let row = fixture.project.local.rows[0]
        let otherAccount = try AccountID(validating: "account-other")
        let otherProject = try ProjectID(validating: "project-other")

        let crossAccount = try Self.destination(
            id: "space-cross-account",
            accountId: otherAccount,
            scope: fixture.projectRequest.scope,
            name: "Cross Account",
            revision: 1
        )
        #expect(Self.destinationFailure {
            try Self.directory(request: fixture.projectRequest, rows: [crossAccount])
        } == .accountScopeMismatch)

        let crossScope = try Self.destination(
            id: "space-cross-scope",
            accountId: fixture.accountId,
            scope: .project(otherProject),
            name: "Cross Scope",
            revision: 1
        )
        #expect(Self.destinationFailure {
            try Self.directory(request: fixture.projectRequest, rows: [crossScope])
        } == .placementScopeMismatch)

        #expect(Self.destinationFailure {
            try Self.destination(
                id: "space-archived",
                accountId: fixture.accountId,
                scope: fixture.projectRequest.scope,
                name: "Archived",
                lifecycle: .archived,
                revision: 2
            )
        } == .inactiveDestination)

        #expect(Self.destinationFailure {
            try Self.directory(request: fixture.projectRequest, rows: [row, row])
        } == .duplicateSpaceIdentity)
        #expect(Self.destinationFailure {
            try Self.directory(
                request: fixture.projectRequest,
                rows: [row],
                visibleCount: 2
            )
        } == .visibleCountMismatch)
        #expect(Self.destinationFailure {
            try Self.directory(
                request: fixture.projectRequest,
                rows: [row],
                asOf: Date(timeIntervalSinceReferenceDate: .infinity)
            )
        } == .invalidSnapshotAsOf)

        let wrongFingerprint = try ListQueryFingerprint(
            validating: String(repeating: "a", count: 64)
        )
        #expect(wrongFingerprint != fixture.projectRequest.queryFingerprint)
        #expect(Self.destinationFailure {
            try SpaceAssignmentDestinationDirectorySnapshot(
                request: fixture.projectRequest,
                local: ListLocalSnapshot(
                    queryFingerprint: wrongFingerprint,
                    rows: [row],
                    visibleRowCountBeforeFiltering: 1,
                    isCompleteForQuery: true,
                    quality: .ready,
                    localDataVersion: LocalDataVersion(validating: "space-dest-wrong-query"),
                    asOf: Self.t0
                )
            )
        } == .queryFingerprintMismatch)

        #expect(Self.listFailure {
            try ListLocalSnapshot<SpaceAssignmentDestinationSnapshot>(
                queryFingerprint: fixture.projectRequest.queryFingerprint,
                rows: [],
                visibleRowCountBeforeFiltering: 0,
                isCompleteForQuery: true,
                quality: .partial,
                localDataVersion: LocalDataVersion(validating: "space-dest-incomplete-ready"),
                asOf: Self.t0
            )
        } == .incompleteAuthoritativeEmpty)

        #expect(Self.destinationFailure {
            try OperationContractCodec.decode(
                SpaceAssignmentDestinationRequest.self,
                from: Data("{}".utf8)
            )
        } == .invalidEncodedRequest)
        #expect(Self.destinationFailure {
            try OperationContractCodec.decode(
                SpaceAssignmentDestinationSnapshot.self,
                from: Data("{}".utf8)
            )
        } == .invalidEncodedDestination)
        #expect(Self.destinationFailure {
            try OperationContractCodec.decode(
                SpaceAssignmentDestinationDirectorySnapshot.self,
                from: Data("{}".utf8)
            )
        } == .invalidEncodedDirectory)

        let requestBytes = try OperationContractCodec.encode(fixture.projectRequest)
        let tamperedRequest = try Self.mutatingObject(requestBytes) { root in
            root["queryFingerprint"] = String(repeating: "b", count: 64)
        }
        #expect(Self.destinationFailure {
            try OperationContractCodec.decode(
                SpaceAssignmentDestinationRequest.self,
                from: tamperedRequest
            )
        } == .requestFingerprintMismatch)

        let directoryBytes = try OperationContractCodec.encode(fixture.project)
        let reboundDirectory = try Self.mutatingObject(directoryBytes) { root in
            var request = root["request"] as! [String: Any]
            request["accountId"] = "account-rebound"
            root["request"] = request
        }
        #expect(Self.destinationFailure {
            try OperationContractCodec.decode(
                SpaceAssignmentDestinationDirectorySnapshot.self,
                from: reboundDirectory
            )
        } == .requestFingerprintMismatch)

        let archivedRowBytes = try Self.mutatingObject(
            OperationContractCodec.encode(row)
        ) { root in
            root["lifecycle"] = "archived"
        }
        #expect(Self.destinationFailure {
            try OperationContractCodec.decode(
                SpaceAssignmentDestinationSnapshot.self,
                from: archivedRowBytes
            )
        } == .inactiveDestination)

        let malformedRowBytes = try Self.mutatingObject(
            OperationContractCodec.encode(row)
        ) { root in
            root["revision"] = -1
        }
        #expect(Self.destinationFailure {
            try OperationContractCodec.decode(
                SpaceAssignmentDestinationSnapshot.self,
                from: malformedRowBytes
            )
        } == .invalidEncodedDestination)

        let diagnostics: [(SpaceAssignmentDestinationFailure, String)] = [
            (.accountScopeMismatch, "space_assignment_destination_account_scope_mismatch"),
            (.placementScopeMismatch, "space_assignment_destination_placement_scope_mismatch"),
            (.inactiveDestination, "space_assignment_destination_inactive"),
            (.duplicateSpaceIdentity, "space_assignment_destination_identity_duplicate"),
            (.visibleCountMismatch, "space_assignment_destination_visible_count_mismatch"),
            (.invalidSnapshotAsOf, "space_assignment_destination_as_of_invalid"),
            (
                .requestFingerprintMismatch,
                "space_assignment_destination_request_fingerprint_mismatch"
            ),
            (
                .queryFingerprintMismatch,
                "space_assignment_destination_query_fingerprint_mismatch"
            ),
            (.localReadFailed, "space_assignment_destination_local_read_failed"),
            (.invalidEncodedRequest, "space_assignment_destination_request_encoding_invalid"),
            (.invalidEncodedDestination, "space_assignment_destination_row_encoding_invalid"),
            (
                .invalidEncodedDirectory,
                "space_assignment_destination_directory_encoding_invalid"
            )
        ]
        for (failure, code) in diagnostics {
            #expect(failure.diagnosticCode == code)
        }
    }

    @Test("The query port emits only its exact request and exposes bounded local failure")
    func queryPortIsScopeExactAndFailureSafe() async throws {
        let fixture = try Self.fixture()
        let port = FixtureSpaceAssignmentDestinationPort(snapshot: fixture.project)
        var received: [SpaceAssignmentDestinationDirectorySnapshot] = []
        for try await snapshot in port.watchEligibleDestinations(fixture.projectRequest) {
            received.append(snapshot)
        }
        #expect(received == [fixture.project])

        let otherAccountRequest = try SpaceAssignmentDestinationRequest(
            accountId: AccountID(validating: "account-other"),
            scope: fixture.projectRequest.scope
        )
        var accountLeak: [SpaceAssignmentDestinationDirectorySnapshot] = []
        var accountFailure: SpaceAssignmentDestinationFailure?
        do {
            for try await snapshot in port.watchEligibleDestinations(otherAccountRequest) {
                accountLeak.append(snapshot)
            }
        } catch let failure as SpaceAssignmentDestinationFailure {
            accountFailure = failure
        }
        #expect(accountLeak.isEmpty)
        #expect(accountFailure == .accountScopeMismatch)

        let otherScopeRequest = try SpaceAssignmentDestinationRequest(
            accountId: fixture.accountId,
            scope: .businessInventory
        )
        var scopeLeak: [SpaceAssignmentDestinationDirectorySnapshot] = []
        var scopeFailure: SpaceAssignmentDestinationFailure?
        do {
            for try await snapshot in port.watchEligibleDestinations(otherScopeRequest) {
                scopeLeak.append(snapshot)
            }
        } catch let failure as SpaceAssignmentDestinationFailure {
            scopeFailure = failure
        }
        #expect(scopeLeak.isEmpty)
        #expect(scopeFailure == .placementScopeMismatch)

        let failing = FailingSpaceAssignmentDestinationPort()
        var falseSnapshots: [SpaceAssignmentDestinationDirectorySnapshot] = []
        var localFailure: SpaceAssignmentDestinationFailure?
        do {
            for try await snapshot in failing.watchEligibleDestinations(
                fixture.projectRequest
            ) {
                falseSnapshots.append(snapshot)
            }
        } catch let failure as SpaceAssignmentDestinationFailure {
            localFailure = failure
        }
        #expect(falseSnapshots.isEmpty)
        #expect(localFailure == .localReadFailed)
    }

    private static let t0 = Date(timeIntervalSince1970: 1_801_000_000)
    private static let t1 = Date(timeIntervalSince1970: 1_801_000_001)
    private static let t2 = Date(timeIntervalSince1970: 1_801_000_002)
    private static let t3 = Date(timeIntervalSince1970: 1_801_000_003)

    private struct Fixture {
        let accountId: AccountID
        let projectRequest: SpaceAssignmentDestinationRequest
        let inventoryRequest: SpaceAssignmentDestinationRequest
        let project: SpaceAssignmentDestinationDirectorySnapshot
        let inventory: SpaceAssignmentDestinationDirectorySnapshot
    }

    private struct RestartFixture: Codable, Equatable, Sendable {
        let projectReady: SpaceAssignmentDestinationDirectorySnapshot
        let inventoryReady: SpaceAssignmentDestinationDirectorySnapshot
        let authoritativeEmpty: SpaceAssignmentDestinationDirectorySnapshot
        let partial: SpaceAssignmentDestinationDirectorySnapshot
        let stale: SpaceAssignmentDestinationDirectorySnapshot
    }

    private static func fixture() throws -> Fixture {
        let accountId = try AccountID(validating: "account-space-destinations")
        let projectId = try ProjectID(validating: "project-showhouse")
        let projectRequest = try SpaceAssignmentDestinationRequest(
            accountId: accountId,
            scope: .project(projectId)
        )
        let inventoryRequest = try SpaceAssignmentDestinationRequest(
            accountId: accountId,
            scope: .businessInventory
        )
        let projectRows = [
            try destination(
                id: "space-loft-z",
                accountId: accountId,
                scope: projectRequest.scope,
                name: "loft",
                revision: 10
            ),
            try destination(
                id: "space-kitchen",
                accountId: accountId,
                scope: projectRequest.scope,
                name: "  Kitchen  ",
                revision: 7
            ),
            try destination(
                id: "space-loft-uppercase",
                accountId: accountId,
                scope: projectRequest.scope,
                name: "Loft",
                revision: 8
            ),
            try destination(
                id: "space-loft-a",
                accountId: accountId,
                scope: projectRequest.scope,
                name: "loft",
                revision: 9
            )
        ]
        let inventoryRows = [
            try destination(
                id: "space-warehouse",
                accountId: accountId,
                scope: inventoryRequest.scope,
                name: "Warehouse",
                revision: 41
            )
        ]
        return Fixture(
            accountId: accountId,
            projectRequest: projectRequest,
            inventoryRequest: inventoryRequest,
            project: try directory(
                request: projectRequest,
                rows: projectRows,
                version: "space-dest-project",
                asOf: t0
            ),
            inventory: try directory(
                request: inventoryRequest,
                rows: inventoryRows,
                version: "space-dest-inventory",
                asOf: t0
            )
        )
    }

    private static func destination(
        id: String,
        accountId: AccountID,
        scope: ItemPlacementScope,
        name: String,
        lifecycle: DirectoryLifecycleState = .active,
        revision: UInt64
    ) throws -> SpaceAssignmentDestinationSnapshot {
        try SpaceAssignmentDestinationSnapshot(
            id: SpaceID(validating: id),
            accountId: accountId,
            scope: scope,
            displayName: SpaceDisplayName(validating: name),
            lifecycle: lifecycle,
            revision: revision
        )
    }

    private static func directory<S: Sequence>(
        request: SpaceAssignmentDestinationRequest,
        rows: S,
        visibleCount: Int? = nil,
        quality: ListSnapshotQuality = .ready,
        isComplete: Bool = true,
        version: String = "space-dest-test",
        asOf: Date = t0
    ) throws -> SpaceAssignmentDestinationDirectorySnapshot
    where S.Element == SpaceAssignmentDestinationSnapshot {
        let rows = Array(rows)
        return try SpaceAssignmentDestinationDirectorySnapshot(
            request: request,
            local: ListLocalSnapshot(
                queryFingerprint: request.queryFingerprint,
                rows: rows,
                visibleRowCountBeforeFiltering: visibleCount ?? rows.count,
                isCompleteForQuery: isComplete,
                quality: quality,
                localDataVersion: LocalDataVersion(validating: version),
                asOf: asOf
            )
        )
    }

    private static func mutatingObject(
        _ bytes: Data,
        mutate: (inout [String: Any]) -> Void
    ) throws -> Data {
        var root = try #require(
            JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        )
        mutate(&root)
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    private static func destinationFailure<T>(
        _ operation: () throws -> T
    ) -> SpaceAssignmentDestinationFailure? {
        do {
            _ = try operation()
            return nil
        } catch let failure as SpaceAssignmentDestinationFailure {
            return failure
        } catch {
            return nil
        }
    }

    private static func listFailure<T>(
        _ operation: () throws -> T
    ) -> ListQueryContractFailure? {
        do {
            _ = try operation()
            return nil
        } catch let failure as ListQueryContractFailure {
            return failure
        } catch {
            return nil
        }
    }
}

private struct FixtureSpaceAssignmentDestinationPort: SpaceAssignmentDestinationQuerying {
    let snapshot: SpaceAssignmentDestinationDirectorySnapshot

    func watchEligibleDestinations(
        _ request: SpaceAssignmentDestinationRequest
    ) -> AsyncThrowingStream<SpaceAssignmentDestinationDirectorySnapshot, Error> {
        AsyncThrowingStream { continuation in
            guard request.accountId == snapshot.request.accountId else {
                continuation.finish(
                    throwing: SpaceAssignmentDestinationFailure.accountScopeMismatch
                )
                return
            }
            guard request.scope == snapshot.request.scope else {
                continuation.finish(
                    throwing: SpaceAssignmentDestinationFailure.placementScopeMismatch
                )
                return
            }
            guard request == snapshot.request else {
                continuation.finish(
                    throwing: SpaceAssignmentDestinationFailure.requestFingerprintMismatch
                )
                return
            }
            continuation.yield(snapshot)
            continuation.finish()
        }
    }
}

private struct FailingSpaceAssignmentDestinationPort: SpaceAssignmentDestinationQuerying {
    func watchEligibleDestinations(
        _ request: SpaceAssignmentDestinationRequest
    ) -> AsyncThrowingStream<SpaceAssignmentDestinationDirectorySnapshot, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(
                throwing: SpaceAssignmentDestinationFailure.localReadFailed
            )
        }
    }
}
