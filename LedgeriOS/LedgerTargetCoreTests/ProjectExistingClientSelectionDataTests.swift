import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Project Existing-Client Selection Read Contracts")
struct ProjectExistingClientSelectionDataTests {
    @Test("Mixed directory evidence projects exact active order, identity, and source truth")
    func activeProjectionAndFingerprintBinding() throws {
        let paddedName = "  Same   Client  "
        let rows = try [
            Self.client("archived-first", lifecycle: .archived),
            Self.client("active-a", name: paddedName),
            Self.client("archived-middle", lifecycle: .archived),
            Self.client("active-b", name: paddedName)
        ]
        let directory = try Self.directory(
            rows,
            visibleCount: 7,
            version: "directory-v1",
            asOf: Self.t1
        )
        let snapshot = try ProjectExistingClientSelectionSnapshot(directory: directory)

        #expect(snapshot.accountId == directory.accountId)
        #expect(snapshot.activeClients.map(\.id) == [rows[1].id, rows[3].id])
        #expect(snapshot.activeClients.map(\.displayName.rawValue) == [paddedName, paddedName])
        #expect(snapshot.availability == .available)
        #expect(snapshot.sourceDirectoryFingerprint == directory.local.queryFingerprint)
        #expect(snapshot.visibleRowCountBeforeFiltering == 7)
        #expect(snapshot.isCompleteForQuery)
        #expect(snapshot.quality == .ready)
        #expect(snapshot.readiness == .ready)
        #expect(snapshot.localDataVersion.rawValue == "directory-v1")
        #expect(snapshot.asOf == Self.t1)

        let otherAccountRows = try [Self.client("active-a", account: "other-account")]
        let otherAccount = try ProjectExistingClientSelectionSnapshot(
            directory: Self.directory(otherAccountRows, account: "other-account")
        )
        let otherSource = try ProjectExistingClientSelectionSnapshot(
            directory: Self.directory(rows, sourceHash: String(repeating: "2", count: 64))
        )
        #expect(snapshot.queryFingerprint != otherAccount.queryFingerprint)
        #expect(snapshot.queryFingerprint != otherSource.queryFingerprint)
        #expect(snapshot.evidenceFingerprint != otherSource.evidenceFingerprint)
    }

    @Test("Availability exhaustively distinguishes active, no-active, and incomplete evidence")
    func availabilityAndCandidateShapes() throws {
        let activeA = try Self.client("active-a")
        let activeB = try Self.client("active-b")
        let archived = try Self.client("archived", lifecycle: .archived)

        let trueEmpty = try Self.snapshot([])
        let archivedOnly = try Self.snapshot([archived])
        #expect(trueEmpty.activeClients.isEmpty)
        #expect(archivedOnly.activeClients.isEmpty)
        #expect(trueEmpty.availability == .noActiveClient)
        #expect(archivedOnly.availability == .noActiveClient)

        let readyIncomplete = try Self.snapshot([], complete: false)
        let partialEmpty = try Self.snapshot([], quality: .partial, complete: false)
        let staleEmpty = try Self.snapshot([], quality: .stale, complete: false)
        #expect(readyIncomplete.availability == .directoryIncomplete)
        #expect(partialEmpty.availability == .directoryIncomplete)
        #expect(staleEmpty.availability == .directoryIncomplete)
        #expect(readyIncomplete.readiness == .ready)
        #expect(partialEmpty.readiness == .partial)
        #expect(staleEmpty.readiness == .stale)

        let one = try Self.snapshot([activeA])
        let many = try Self.snapshot([activeA, archived, activeB])
        let readyIncompleteActive = try Self.snapshot([activeA], complete: false)
        let partialActive = try Self.snapshot(
            [activeA], quality: .partial, complete: false
        )
        let staleActive = try Self.snapshot(
            [activeA], quality: .stale, complete: false
        )
        for available in [one, many, readyIncompleteActive, partialActive, staleActive] {
            #expect(available.availability == .available)
        }
        #expect(try partialActive.selection(clientId: activeA.id) == .existing(activeA.id))
        #expect(try staleActive.selection(clientId: activeA.id) == .existing(activeA.id))
        #expect(one.activeClients.map(\.id) == [activeA.id])
        #expect(many.activeClients.map(\.id) == [activeA.id, activeB.id])

        for shape in [trueEmpty, archivedOnly, readyIncomplete, partialEmpty, staleEmpty, one, many] {
            let text = String(decoding: try OperationContractCodec.encode(shape), as: UTF8.self)
            #expect(!text.lowercased().contains("selected"))
            #expect(!text.lowercased().contains("default"))
        }
    }

    @Test("Only an explicit currently projected active Client ID produces existing selection")
    func explicitSelectionOnly() throws {
        let active = try Self.client("active-client", name: "Same Name")
        let archived = try Self.client(
            "archived-client", name: "Same Name", lifecycle: .archived
        )
        let snapshot = try Self.snapshot([active, archived])

        let selected = try snapshot.selection(clientId: active.id)
        #expect(selected == .existing(active.id))
        #expect(selected.clientId == active.id)
        #expect(selected.newClientDisplayName == nil)
        #expect(Self.failure {
            try snapshot.selection(clientId: archived.id)
        } == .clientNotSelectable)
        #expect(Self.failure {
            try snapshot.selection(clientId: ClientID(validating: "unknown-client"))
        } == .clientNotSelectable)

        let otherSnapshotClient = try Self.client("other-snapshot-client")
        let otherSnapshot = try Self.snapshot([otherSnapshotClient])
        #expect(Self.failure {
            try snapshot.selection(clientId: otherSnapshotClient.id)
        } == .clientNotSelectable)
        #expect(Self.failure {
            try otherSnapshot.selection(clientId: active.id)
        } == .clientNotSelectable)

        let removedSnapshot = try Self.snapshot([])
        #expect(Self.failure {
            try removedSnapshot.selection(clientId: active.id)
        } == .clientNotSelectable)
    }

    @Test("Rebound, duplicate, stale-fingerprint, malformed, and invalid evidence fails atomically")
    func corruptionAndRebindingRefusal() throws {
        let activeA = try Self.client("active-a", name: "Same Name")
        let activeB = try Self.client("active-b", name: "Same Name")
        let snapshot = try Self.snapshot(
            [activeA, activeB], visibleCount: 2, version: "original", asOf: Self.t1
        )
        let bytes = try OperationContractCodec.encode(snapshot)

        let accountRebind = try Self.mutate(bytes) { $0["accountId"] = "other-account" }
        #expect(Self.decodeFailure(accountRebind) == .accountScopeMismatch)

        let sourceRebind = try Self.mutate(bytes) {
            $0["sourceDirectoryFingerprint"] = String(repeating: "2", count: 64)
        }
        #expect(Self.decodeFailure(sourceRebind) == .queryFingerprintMismatch)
        let queryRebind = try Self.mutate(bytes) {
            $0["queryFingerprint"] = String(repeating: "a", count: 64)
        }
        #expect(Self.decodeFailure(queryRebind) == .queryFingerprintMismatch)
        let evidenceRebind = try Self.mutate(bytes) {
            $0["evidenceFingerprint"] = String(repeating: "b", count: 64)
        }
        #expect(Self.decodeFailure(evidenceRebind) == .evidenceFingerprintMismatch)
        let invalidQuery = try Self.mutate(bytes) { $0["queryFingerprint"] = "not-a-hash" }
        #expect(Self.decodeFailure(invalidQuery) == .invalidQueryFingerprint)
        let invalidEvidence = try Self.mutate(bytes) {
            $0["evidenceFingerprint"] = "not-a-hash"
        }
        #expect(Self.decodeFailure(invalidEvidence) == .invalidEvidenceFingerprint)

        let rowAccountRebind = try Self.mutateClient(bytes, at: 0) {
            $0["accountId"] = "other-account"
        }
        #expect(Self.decodeFailure(rowAccountRebind) == .accountScopeMismatch)
        let rowContentRebind = try Self.mutateClient(bytes, at: 0) {
            $0["displayName"] = "Changed Name"
        }
        #expect(Self.decodeFailure(rowContentRebind) == .evidenceFingerprintMismatch)
        let inactiveCandidate = try Self.mutateClient(bytes, at: 0) {
            $0["lifecycle"] = "archived"
        }
        #expect(Self.decodeFailure(inactiveCandidate) == .inactiveCandidate)

        let identicalDuplicate = try Self.mutateClients(bytes) { clients in
            clients.append(clients[0])
        }
        #expect(Self.decodeFailure(identicalDuplicate) == .duplicateClientIdentity)
        let conflictingDuplicate = try Self.mutateClients(bytes) { clients in
            var duplicate = clients[1]
            duplicate["id"] = clients[0]["id"]
            duplicate["displayName"] = "Conflicting Name"
            clients.append(duplicate)
        }
        #expect(Self.decodeFailure(conflictingDuplicate) == .duplicateClientIdentity)

        let removed = try Self.mutateClients(bytes) { $0.removeLast() }
        #expect(Self.decodeFailure(removed) == .evidenceFingerprintMismatch)
        let activeCObject = try Self.object(Self.client("active-c", name: "Third Name"))
        let inserted = try Self.mutate(bytes) { root in
            var clients = root["activeClients"] as! [[String: Any]]
            clients.append(activeCObject)
            root["activeClients"] = clients
            root["visibleRowCountBeforeFiltering"] = 3
        }
        #expect(Self.decodeFailure(inserted) == .evidenceFingerprintMismatch)
        let reordered = try Self.mutateClients(bytes) { $0.swapAt(0, 1) }
        #expect(Self.decodeFailure(reordered) == .evidenceFingerprintMismatch)
        let validCountChange = try Self.mutate(bytes) {
            $0["visibleRowCountBeforeFiltering"] = 3
        }
        #expect(Self.decodeFailure(validCountChange) == .evidenceFingerprintMismatch)
        let negativeCount = try Self.mutate(bytes) {
            $0["visibleRowCountBeforeFiltering"] = -1
        }
        #expect(Self.decodeFailure(negativeCount) == .visibleCountMismatch)
        let belowCandidateCount = try Self.mutate(bytes) {
            $0["visibleRowCountBeforeFiltering"] = 1
        }
        #expect(Self.decodeFailure(belowCandidateCount) == .visibleCountMismatch)

        let completenessRebind = try Self.mutate(bytes) {
            $0["isCompleteForQuery"] = false
        }
        #expect(Self.decodeFailure(completenessRebind) == .evidenceFingerprintMismatch)
        let qualityRebind = try Self.mutate(bytes) {
            $0["isCompleteForQuery"] = false
            $0["quality"] = "partial"
        }
        #expect(Self.decodeFailure(qualityRebind) == .evidenceFingerprintMismatch)
        let invalidPartialCompleteness = try Self.mutate(bytes) { $0["quality"] = "partial" }
        #expect(Self.decodeFailure(invalidPartialCompleteness) == .invalidCompleteness)
        let invalidStaleCompleteness = try Self.mutate(bytes) { $0["quality"] = "stale" }
        #expect(Self.decodeFailure(invalidStaleCompleteness) == .invalidCompleteness)
        let versionRebind = try Self.mutate(bytes) { $0["localDataVersion"] = "changed" }
        #expect(Self.decodeFailure(versionRebind) == .evidenceFingerprintMismatch)
        let timeRebind = try Self.mutate(bytes) { root in
            root["asOf"] = (root["asOf"] as! NSNumber).doubleValue + 1_000
        }
        #expect(Self.decodeFailure(timeRebind) == .evidenceFingerprintMismatch)
        let availabilityRebind = try Self.mutate(bytes) {
            $0["availability"] = "directoryIncomplete"
        }
        #expect(Self.decodeFailure(availabilityRebind) == .evidenceFingerprintMismatch)

        let malformedName = try Self.mutateClient(bytes, at: 0) {
            $0["displayName"] = "   \n "
        }
        #expect(Self.decodeFailure(malformedName) == .invalidEncodedSnapshot)
        let missingRows = try Self.mutate(bytes) { $0.removeValue(forKey: "activeClients") }
        #expect(Self.decodeFailure(missingRows) == .invalidEncodedSnapshot)
        let unknownField = try Self.mutate(bytes) { $0["inventoryId"] = "inventory-one" }
        #expect(Self.decodeFailure(unknownField) == .invalidEncodedSnapshot)
        let unknownClientField = try Self.mutateClient(bytes, at: 0) {
            $0["inventoryId"] = "inventory-one"
        }
        #expect(Self.decodeFailure(unknownClientField) == .invalidEncodedSnapshot)

        let nonfiniteDirectory = try Self.directory(
            [activeA],
            asOf: Date(timeIntervalSinceReferenceDate: .infinity)
        )
        #expect(Self.failure {
            try ProjectExistingClientSelectionSnapshot(directory: nonfiniteDirectory)
        } == .invalidAsOf)
    }

    @Test("Valid later directory content derives fresh evidence and restarts canonically")
    func laterEvidenceAndOfflineRestart() throws {
        let activeA = try Self.client("active-a", name: "  Padded Name  ")
        let activeB = try Self.client("active-b")
        let baseline = try Self.snapshot([activeA, activeB], version: "baseline", asOf: Self.t1)
        let laterName = try Self.snapshot([
            Self.client("active-a", name: "Later Name"), activeB
        ], version: "later-name", asOf: Self.t2)
        let laterAudit = try Self.snapshot([
            Self.client("active-a", createdAt: Self.t1, updatedAt: Self.t2), activeB
        ], version: "later-audit", asOf: Self.t3)
        let laterLifecycle = try Self.snapshot([
            Self.client("active-a", lifecycle: .archived), activeB
        ], version: "later-lifecycle", asOf: Self.t4)
        let laterOrder = try Self.snapshot(
            [activeB, activeA], version: "later-order", asOf: Self.t5
        )
        let laterCount = try Self.snapshot(
            [activeA, activeB], visibleCount: 4, version: "later-count", asOf: Self.t6
        )

        let laterSnapshots = [laterName, laterAudit, laterLifecycle, laterOrder, laterCount]
        for later in laterSnapshots {
            #expect(later.evidenceFingerprint != baseline.evidenceFingerprint)
        }
        #expect(laterName.queryFingerprint == baseline.queryFingerprint)
        #expect(baseline.activeClients[0].displayName.rawValue == "  Padded Name  ")
        #expect(laterLifecycle.activeClients.map(\.id) == [activeB.id])
        #expect(laterOrder.activeClients.map(\.id) == [activeB.id, activeA.id])
        #expect(laterCount.visibleRowCountBeforeFiltering == 4)

        let readyNoActive = try Self.snapshot([])
        let readyIncomplete = try Self.snapshot([], complete: false)
        let partial = try Self.snapshot(
            [activeA], quality: .partial, complete: false, version: "partial", asOf: Self.t2
        )
        let stale = try Self.snapshot(
            [activeA], quality: .stale, complete: false, version: "stale", asOf: Self.t3
        )
        let fixture = RestartFixture(
            snapshots: [baseline, readyNoActive, readyIncomplete, partial, stale]
        )
        let bytes = try OperationContractCodec.encode(fixture)
        let restored = try OperationContractCodec.decode(RestartFixture.self, from: bytes)
        #expect(restored == fixture)
        #expect(try OperationContractCodec.encode(restored) == bytes)
        #expect(restored.snapshots.map(\.availability) == [
            .available, .noActiveClient, .directoryIncomplete, .available, .available
        ])
        #expect(restored.snapshots.map(\.readiness) == [
            .ready, .ready, .ready, .partial, .stale
        ])
    }

    @Test("A test-only directory consumer propagates scope failure, upstream failure, and cancellation")
    func existingPortConsumer() async throws {
        let accountId = try AccountID(validating: "selection-account")
        let directory = try Self.directory([try Self.client("active")])
        let exact = await Self.consume(
            DirectoryFixturePort(clientSnapshots: [directory]),
            accountId: accountId
        )
        #expect(exact.snapshots.count == 1)
        #expect(exact.snapshots.first?.activeClients.map(\.id) == directory.local.rows.map(\.id))
        #expect(exact.failure == nil)

        let otherDirectory = try Self.directory(
            [try Self.client("other", account: "other-account")],
            account: "other-account"
        )
        let rebound = await Self.consume(
            DirectoryFixturePort(clientSnapshots: [otherDirectory]),
            accountId: accountId
        )
        #expect(rebound.snapshots.isEmpty)
        #expect(rebound.failure == .projection(.accountScopeMismatch))

        let failed = await Self.consume(DirectoryFailingPort(), accountId: accountId)
        #expect(failed.snapshots.isEmpty)
        #expect(failed.failure == .upstream)

        let probe = DirectoryCancellationProbe()
        let consumer = Task {
            await Self.consume(DirectoryCancellablePort(probe: probe), accountId: accountId)
        }
        await probe.waitForStart()
        consumer.cancel()
        let cancelled = await consumer.value
        #expect(cancelled.snapshots.isEmpty)
        #expect(cancelled.failure == .cancelled)
        await probe.waitForCancellation()
    }

    @Test("Encoded values expose only the frozen projection and bounded diagnostic contract")
    func encodedBoundaryAndDiagnostics() throws {
        let active = try Self.client("active", name: "  Display Name  ")
        let snapshot = try Self.snapshot([active])
        let object = try Self.object(snapshot)
        #expect(Set(object.keys) == [
            "accountId", "activeClients", "availability", "sourceDirectoryFingerprint",
            "visibleRowCountBeforeFiltering", "isCompleteForQuery", "quality",
            "localDataVersion", "asOf", "queryFingerprint", "evidenceFingerprint"
        ])
        let clients = try #require(object["activeClients"] as? [[String: Any]])
        #expect(clients.count == 1)
        #expect(Set(clients[0].keys) == [
            "id", "accountId", "displayName", "lifecycle", "createdAt", "updatedAt"
        ])
        #expect(object["queryFingerprint"] is String)
        #expect(object["evidenceFingerprint"] is String)
        #expect(object["sourceDirectoryFingerprint"] is String)
        #expect(object["availability"] as? String == "available")

        let selection = try snapshot.selection(clientId: active.id)
        let selectionObject = try Self.object(selection)
        #expect(Set(selectionObject.keys) == ["kind", "clientId"])
        #expect(selectionObject["kind"] as? String == "existing")

        let text = String(
            decoding: try OperationContractCodec.encode(snapshot), as: UTF8.self
        ).lowercased()
        for forbidden in [
            "selected", "default", "revision", "projectid", "projectcount", "history",
            "transfer", "contact", "email", "phone", "address", "crm", "category",
            "attachment", "media", "mutation", "principal", "authorized", "permission",
            "firebase", "firestore", "supabase", "powersync", "schema", "rls", "sql",
            "persist", "path", "url", "mcp", "migration", "hosted", "production",
            "inventory"
        ] {
            #expect(!text.contains(forbidden))
        }

        let diagnostics: [(ProjectExistingClientSelectionFailure, String)] = [
            (.accountScopeMismatch, "project_client_selection_account_scope_mismatch"),
            (.inactiveCandidate, "project_client_selection_candidate_inactive"),
            (.duplicateClientIdentity, "project_client_selection_client_identity_duplicate"),
            (.visibleCountMismatch, "project_client_selection_visible_count_mismatch"),
            (.invalidCompleteness, "project_client_selection_completeness_invalid"),
            (.invalidAsOf, "project_client_selection_as_of_invalid"),
            (.invalidQueryFingerprint, "project_client_selection_query_fingerprint_invalid"),
            (.invalidEvidenceFingerprint, "project_client_selection_evidence_fingerprint_invalid"),
            (.queryFingerprintMismatch, "project_client_selection_query_fingerprint_mismatch"),
            (.evidenceFingerprintMismatch, "project_client_selection_evidence_fingerprint_mismatch"),
            (.clientNotSelectable, "project_client_selection_client_not_selectable"),
            (.invalidEncodedSnapshot, "project_client_selection_snapshot_encoding_invalid")
        ]
        let codes = diagnostics.map { failure, expected in
            #expect(failure.diagnosticCode == expected)
            #expect(expected.utf8.count <= 80)
            #expect(expected.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "_" })
            #expect(!expected.contains("active-a"))
            #expect(!expected.contains("selection-account"))
            #expect(!expected.contains("firebase"))
            #expect(!expected.contains("supabase"))
            #expect(!expected.contains("powersync"))
            return expected
        }
        #expect(Set(codes).count == diagnostics.count)
    }

    private static let t0 = Date(timeIntervalSince1970: 1_802_400_000)
    private static let t1 = Date(timeIntervalSince1970: 1_802_400_001)
    private static let t2 = Date(timeIntervalSince1970: 1_802_400_002)
    private static let t3 = Date(timeIntervalSince1970: 1_802_400_003)
    private static let t4 = Date(timeIntervalSince1970: 1_802_400_004)
    private static let t5 = Date(timeIntervalSince1970: 1_802_400_005)
    private static let t6 = Date(timeIntervalSince1970: 1_802_400_006)

    private struct RestartFixture: Codable, Equatable, Sendable {
        let snapshots: [ProjectExistingClientSelectionSnapshot]
    }

    private static func client(
        _ id: String,
        account: String = "selection-account",
        name: String = "Client Name",
        lifecycle: DirectoryLifecycleState = .active,
        createdAt: Date = t0,
        updatedAt: Date = t1
    ) throws -> ClientSummary {
        try ClientSummary(
            id: ClientID(validating: id),
            accountId: AccountID(validating: account),
            displayName: ClientDisplayName(validating: name),
            lifecycle: lifecycle,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static func directory(
        _ rows: [ClientSummary],
        account: String = "selection-account",
        sourceHash: String = String(repeating: "1", count: 64),
        visibleCount: Int? = nil,
        quality: ListSnapshotQuality = .ready,
        complete: Bool = true,
        version: String = "directory",
        asOf: Date = t0
    ) throws -> ClientListSnapshot {
        let local = try ListLocalSnapshot(
            queryFingerprint: ListQueryFingerprint(validating: sourceHash),
            rows: rows,
            visibleRowCountBeforeFiltering: visibleCount ?? rows.count,
            isCompleteForQuery: complete,
            quality: quality,
            localDataVersion: LocalDataVersion(validating: version),
            asOf: asOf
        )
        return try ClientListSnapshot(
            accountId: AccountID(validating: account),
            local: local
        )
    }

    private static func snapshot(
        _ rows: [ClientSummary],
        account: String = "selection-account",
        sourceHash: String = String(repeating: "1", count: 64),
        visibleCount: Int? = nil,
        quality: ListSnapshotQuality = .ready,
        complete: Bool = true,
        version: String = "directory",
        asOf: Date = t0
    ) throws -> ProjectExistingClientSelectionSnapshot {
        try ProjectExistingClientSelectionSnapshot(
            directory: directory(
                rows,
                account: account,
                sourceHash: sourceHash,
                visibleCount: visibleCount,
                quality: quality,
                complete: complete,
                version: version,
                asOf: asOf
            )
        )
    }

    private static func failure<Value>(
        _ body: () throws -> Value
    ) -> ProjectExistingClientSelectionFailure? {
        do { _ = try body(); return nil }
        catch let failure as ProjectExistingClientSelectionFailure { return failure }
        catch { return nil }
    }

    private static func decodeFailure(
        _ bytes: Data
    ) -> ProjectExistingClientSelectionFailure? {
        failure {
            try OperationContractCodec.decode(
                ProjectExistingClientSelectionSnapshot.self,
                from: bytes
            )
        }
    }

    private static func object<Value: Encodable>(_ value: Value) throws -> [String: Any] {
        let bytes = try OperationContractCodec.encode(value)
        return try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    }

    private static func mutate(
        _ bytes: Data,
        _ body: (inout [String: Any]) -> Void
    ) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        body(&object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func mutateClients(
        _ bytes: Data,
        _ body: (inout [[String: Any]]) -> Void
    ) throws -> Data {
        try mutate(bytes) { root in
            var clients = root["activeClients"] as! [[String: Any]]
            body(&clients)
            root["activeClients"] = clients
        }
    }

    private static func mutateClient(
        _ bytes: Data,
        at index: Int,
        _ body: (inout [String: Any]) -> Void
    ) throws -> Data {
        try mutateClients(bytes) { clients in body(&clients[index]) }
    }

    private static func consume<Port: ClientProjectDirectoryQuerying>(
        _ port: Port,
        accountId: AccountID
    ) async -> (snapshots: [ProjectExistingClientSelectionSnapshot], failure: ConsumerFailure?) {
        var snapshots: [ProjectExistingClientSelectionSnapshot] = []
        do {
            for try await directory in port.watchClients(accountId: accountId) {
                guard directory.accountId == accountId else {
                    throw ProjectExistingClientSelectionFailure.accountScopeMismatch
                }
                snapshots.append(try ProjectExistingClientSelectionSnapshot(directory: directory))
            }
            return (snapshots, Task.isCancelled ? .cancelled : nil)
        } catch let failure as ProjectExistingClientSelectionFailure {
            return (snapshots, .projection(failure))
        } catch DirectoryProbeFailure.upstream {
            return (snapshots, .upstream)
        } catch is CancellationError {
            return (snapshots, .cancelled)
        } catch {
            return (snapshots, .unexpected)
        }
    }
}

private enum ConsumerFailure: Equatable {
    case projection(ProjectExistingClientSelectionFailure)
    case upstream
    case cancelled
    case unexpected
}

private enum DirectoryProbeFailure: Error {
    case upstream
}

private struct DirectoryFixturePort: ClientProjectDirectoryQuerying {
    let clientSnapshots: [ClientListSnapshot]

    func watchClients(
        accountId: AccountID
    ) -> AsyncThrowingStream<ClientListSnapshot, Error> {
        AsyncThrowingStream { continuation in
            for snapshot in clientSnapshots { continuation.yield(snapshot) }
            continuation.finish()
        }
    }

    func watchProjects(
        accountId: AccountID
    ) -> AsyncThrowingStream<ProjectListSnapshot, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private struct DirectoryFailingPort: ClientProjectDirectoryQuerying {
    func watchClients(
        accountId: AccountID
    ) -> AsyncThrowingStream<ClientListSnapshot, Error> {
        AsyncThrowingStream { $0.finish(throwing: DirectoryProbeFailure.upstream) }
    }

    func watchProjects(
        accountId: AccountID
    ) -> AsyncThrowingStream<ProjectListSnapshot, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private struct DirectoryCancellablePort: ClientProjectDirectoryQuerying {
    let probe: DirectoryCancellationProbe

    func watchClients(
        accountId: AccountID
    ) -> AsyncThrowingStream<ClientListSnapshot, Error> {
        AsyncThrowingStream { continuation in
            let producer = Task {
                await probe.markStarted()
                do {
                    try await Task.sleep(for: .seconds(60))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: CancellationError())
                }
            }
            continuation.onTermination = { @Sendable _ in
                producer.cancel()
                Task { await probe.markCancelled() }
            }
        }
    }

    func watchProjects(
        accountId: AccountID
    ) -> AsyncThrowingStream<ProjectListSnapshot, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private actor DirectoryCancellationProbe {
    private var started = false
    private var cancelled = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var cancellationWaiter: CheckedContinuation<Void, Never>?

    func markStarted() {
        started = true
        startWaiter?.resume()
        startWaiter = nil
    }

    func waitForStart() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func markCancelled() {
        cancelled = true
        cancellationWaiter?.resume()
        cancellationWaiter = nil
    }

    func waitForCancellation() async {
        guard !cancelled else { return }
        await withCheckedContinuation { cancellationWaiter = $0 }
    }
}
