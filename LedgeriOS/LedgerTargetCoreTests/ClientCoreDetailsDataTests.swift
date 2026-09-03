import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Client Core Details Read Contracts")
struct ClientCoreDetailsDataTests {
    @Test("Active and archived Clients preserve exact identity, audit evidence, names, and revision")
    func coreDetailsAndFingerprintBinding() throws {
        let request = try Self.request()
        let accountChanged = try Self.request(account: "other-account")
        let clientChanged = try Self.request(client: "other-client")
        #expect(Set([
            request.queryFingerprint,
            accountChanged.queryFingerprint,
            clientChanged.queryFingerprint
        ]).count == 3)

        let paddedName = "  Design   Client  "
        let active = try Self.row(
            name: paddedName,
            lifecycle: .active,
            createdAt: Self.t0,
            updatedAt: Self.t0,
            revision: 0
        )
        let activeLocal = try Self.local([active])
        #expect(active.client.id == request.clientId)
        #expect(active.client.accountId == request.accountId)
        #expect(active.client.displayName.rawValue == paddedName)
        #expect(active.client.lifecycle == .active)
        #expect(active.client.createdAt == Self.t0)
        #expect(active.client.updatedAt == Self.t0)
        #expect(active.locallyObservedRevision.rawValue == 0)
        #expect(activeLocal.row == active)
        #expect(activeLocal.observedRevisionIsFromCompleteReadySnapshot)
        #expect(!activeLocal.isAuthoritativeAbsence)

        let archived = try Self.row(
            name: "Archived Client",
            lifecycle: .archived,
            createdAt: Self.t1,
            updatedAt: Self.t2,
            revision: .max
        )
        #expect(archived.client.lifecycle == .archived)
        #expect(archived.locallyObservedRevision.rawValue == .max)
        #expect(try Self.local([archived]).row == archived)

        let laterName = try Self.row(name: "A Later Valid Name")
        let laterTime = try Self.row(createdAt: Self.t2, updatedAt: Self.t3)
        let laterLifecycle = try Self.row(lifecycle: .archived)
        let laterRevision = try Self.row(revision: 10)
        for later in [laterName, laterTime, laterLifecycle, laterRevision] {
            #expect(try Self.local([later]).row == later)
        }
    }

    @Test("Every local truth variant restarts without upgrading absence or revision authority")
    func canonicalRestartAndOfflineTruth() throws {
        let request = try Self.request()
        let archived = try Self.row(lifecycle: .archived, revision: .max)
        let states = try [
            Self.local([archived], version: "ready-found", date: Self.t0),
            Self.local([], version: "ready-absent", date: Self.t1),
            Self.local([archived], complete: false, version: "incomplete-found", date: Self.t2),
            Self.local([], complete: false, version: "incomplete-empty", date: Self.t3),
            Self.local(
                [archived], quality: .partial, complete: false,
                version: "partial-found", date: Self.t4
            ),
            Self.local(
                [], quality: .partial, complete: false,
                version: "partial-empty", date: Self.t5
            ),
            Self.local(
                [archived], quality: .stale, complete: false,
                version: "stale-found", date: Self.t6
            ),
            Self.local(
                [], quality: .stale, complete: false,
                version: "stale-empty", date: Self.t7
            )
        ]
        let fixture = try RestartFixture(
            updates: states.map {
                try ClientCoreDetailsUpdate(request: request, state: .snapshot($0))
            }
        )
        let bytes = try OperationContractCodec.encode(fixture)
        let restored = try OperationContractCodec.decode(RestartFixture.self, from: bytes)

        #expect(restored == fixture)
        #expect(try OperationContractCodec.encode(restored) == bytes)
        #expect(states.map { $0.local.localDataVersion.rawValue } == [
            "ready-found", "ready-absent", "incomplete-found", "incomplete-empty",
            "partial-found", "partial-empty", "stale-found", "stale-empty"
        ])
        #expect(states.map(\.isAuthoritativeAbsence) == [
            false, true, false, false, false, false, false, false
        ])
        #expect(states.map(\.observedRevisionIsFromCompleteReadySnapshot) == [
            true, false, false, false, false, false, false, false
        ])
        #expect(states.map(\.local.asOf) == [
            Self.t0, Self.t1, Self.t2, Self.t3,
            Self.t4, Self.t5, Self.t6, Self.t7
        ])
        #expect(states[0].row?.client.lifecycle == .archived)
        #expect(states[0].row?.locallyObservedRevision.rawValue == .max)
        #expect(states[2].row?.locallyObservedRevision.rawValue == .max)
        #expect(states[4].row?.locallyObservedRevision.rawValue == .max)
        #expect(states[6].row?.locallyObservedRevision.rawValue == .max)
        #expect(
            states[0].local.localDataVersion.rawValue
                != String(states[0].row!.locallyObservedRevision.rawValue)
        )
    }

    @Test("Malformed, rebound, hidden, and internally inconsistent Client evidence is refused")
    func refusalAndTamperCases() throws {
        let request = try Self.request()
        let row = try Self.row()

        #expect(Self.failure {
            try Self.local([try Self.row(account: "other-account")])
        } == .accountScopeMismatch)
        #expect(Self.failure {
            try Self.local([try Self.row(client: "other-client", name: "Primary Client")])
        } == .clientIdentityMismatch)
        #expect(Self.failure { try Self.local([row, row]) } == .multipleRows)
        #expect(Self.failure {
            try Self.local([row, try Self.row(client: "different-client")])
        } == .multipleRows)
        #expect(Self.failure { try Self.local([], visibleCount: -1) } == .visibleCountMismatch)
        #expect(Self.failure { try Self.local([row], visibleCount: 2) } == .visibleCountMismatch)
        #expect(Self.failure {
            try Self.local([row], date: Date(timeIntervalSinceReferenceDate: .infinity))
        } == .invalidSnapshotAsOf)
        #expect(Self.failure {
            try Self.local([row], quality: .partial, complete: true)
        } == .invalidCompleteness)
        #expect(Self.failure {
            try Self.local([row], quality: .stale, complete: true)
        } == .invalidCompleteness)
        #expect(Self.directoryFailure {
            try ClientDisplayName(validating: "  \n  ")
        } == .invalidClientDisplayName)
        #expect(Self.directoryFailure {
            try ClientSummary(
                id: ClientID(validating: "client-one"),
                accountId: AccountID(validating: "client-account"),
                displayName: ClientDisplayName(validating: "Client"),
                lifecycle: .active,
                createdAt: Date(timeIntervalSinceReferenceDate: .infinity),
                updatedAt: Self.t0
            )
        } == .invalidClientAuditOrder)
        #expect(Self.directoryFailure {
            try ClientSummary(
                id: ClientID(validating: "client-one"),
                accountId: AccountID(validating: "client-account"),
                displayName: ClientDisplayName(validating: "Client"),
                lifecycle: .active,
                createdAt: Self.t1,
                updatedAt: Self.t0
            )
        } == .invalidClientAuditOrder)

        let wrongFingerprint = try ListQueryFingerprint(
            validating: String(repeating: "a", count: 64)
        )
        let reboundLocal = try ListLocalSnapshot(
            queryFingerprint: wrongFingerprint,
            rows: [row],
            visibleRowCountBeforeFiltering: 1,
            isCompleteForQuery: true,
            quality: .ready,
            localDataVersion: LocalDataVersion(validating: "rebound"),
            asOf: Self.t0
        )
        #expect(Self.failure {
            try ClientCoreDetailsLocalSnapshot(request: request, local: reboundLocal)
        } == .queryFingerprintMismatch)

        let requestBytes = try OperationContractCodec.encode(request)
        let fingerprintTamper = try Self.mutate(requestBytes) {
            $0["queryFingerprint"] = String(repeating: "b", count: 64)
        }
        #expect(Self.decodeFailure(
            ClientCoreDetailsRequest.self, fingerprintTamper
        ) == .requestFingerprintMismatch)
        let accountTamper = try Self.mutate(requestBytes) { $0["accountId"] = "other-account" }
        #expect(Self.decodeFailure(
            ClientCoreDetailsRequest.self, accountTamper
        ) == .requestFingerprintMismatch)
        let clientTamper = try Self.mutate(requestBytes) { $0["clientId"] = "other-client" }
        #expect(Self.decodeFailure(
            ClientCoreDetailsRequest.self, clientTamper
        ) == .requestFingerprintMismatch)
        let invalidAccount = try Self.mutate(requestBytes) { $0["accountId"] = "   " }
        #expect(Self.decodeFailure(
            ClientCoreDetailsRequest.self, invalidAccount
        ) == .invalidEncodedRequest)
        let missingClientID = try Self.mutate(requestBytes) { $0.removeValue(forKey: "clientId") }
        #expect(Self.decodeFailure(
            ClientCoreDetailsRequest.self, missingClientID
        ) == .invalidEncodedRequest)

        let localBytes = try OperationContractCodec.encode(try Self.local([row]))
        let reboundAccount = try Self.mutateClient(localBytes) { $0["accountId"] = "other-account" }
        #expect(Self.decodeFailure(
            ClientCoreDetailsLocalSnapshot.self, reboundAccount
        ) == .accountScopeMismatch)
        let reboundClient = try Self.mutateClient(localBytes) { client in
            client["id"] = "other-client"
            client["displayName"] = "Primary Client"
        }
        #expect(Self.decodeFailure(
            ClientCoreDetailsLocalSnapshot.self, reboundClient
        ) == .clientIdentityMismatch)
        let badName = try Self.mutateClient(localBytes) { $0["displayName"] = "   \n " }
        #expect(Self.decodeFailure(
            ClientCoreDetailsLocalSnapshot.self, badName
        ) == .invalidEncodedClient)
        let missingName = try Self.mutateClient(localBytes) { $0.removeValue(forKey: "displayName") }
        #expect(Self.decodeFailure(
            ClientCoreDetailsLocalSnapshot.self, missingName
        ) == .invalidEncodedClient)
        let reversedAudit = try Self.mutateClient(localBytes) { client in
            let createdAt = client["createdAt"]
            client["createdAt"] = client["updatedAt"]
            client["updatedAt"] = createdAt
        }
        #expect(Self.decodeFailure(
            ClientCoreDetailsLocalSnapshot.self, reversedAudit
        ) == .invalidEncodedClient)
        let malformedAudit = try Self.mutateClient(localBytes) { $0["createdAt"] = "not-a-date" }
        #expect(Self.decodeFailure(
            ClientCoreDetailsLocalSnapshot.self, malformedAudit
        ) == .invalidEncodedClient)
        let invalidLifecycle = try Self.mutateClient(localBytes) { $0["lifecycle"] = "deleted" }
        #expect(Self.decodeFailure(
            ClientCoreDetailsLocalSnapshot.self, invalidLifecycle
        ) == .invalidEncodedClient)
        let malformedRevision = try Self.mutateFirstRow(localBytes) { row in
            row["locallyObservedRevision"] = ["rawValue": -1]
        }
        #expect(Self.decodeFailure(
            ClientCoreDetailsLocalSnapshot.self, malformedRevision
        ) == .invalidEncodedRevision)
        let missingRevision = try Self.mutateFirstRow(localBytes) {
            $0.removeValue(forKey: "locallyObservedRevision")
        }
        #expect(Self.decodeFailure(
            ClientCoreDetailsLocalSnapshot.self, missingRevision
        ) == .invalidEncodedRevision)
        let negativeCount = try Self.mutate(localBytes) { root in
            var local = root["local"] as! [String: Any]
            local["visibleRowCountBeforeFiltering"] = -1
            root["local"] = local
        }
        #expect(Self.decodeFailure(
            ClientCoreDetailsLocalSnapshot.self, negativeCount
        ) == .visibleCountMismatch)
        let hiddenCount = try Self.mutate(localBytes) { root in
            var local = root["local"] as! [String: Any]
            local["visibleRowCountBeforeFiltering"] = 2
            root["local"] = local
        }
        #expect(Self.decodeFailure(
            ClientCoreDetailsLocalSnapshot.self, hiddenCount
        ) == .visibleCountMismatch)
        let reboundQuery = try Self.mutate(localBytes) { root in
            var local = root["local"] as! [String: Any]
            local["queryFingerprint"] = String(repeating: "c", count: 64)
            root["local"] = local
        }
        #expect(Self.decodeFailure(
            ClientCoreDetailsLocalSnapshot.self, reboundQuery
        ) == .queryFingerprintMismatch)
        for quality in ["partial", "stale"] {
            let invalidCompleteness = try Self.mutate(localBytes) { root in
                var local = root["local"] as! [String: Any]
                local["quality"] = quality
                root["local"] = local
            }
            #expect(Self.decodeFailure(
                ClientCoreDetailsLocalSnapshot.self, invalidCompleteness
            ) == .invalidCompleteness)
        }
        let missingLocal = try Self.mutate(localBytes) { $0.removeValue(forKey: "local") }
        #expect(Self.decodeFailure(
            ClientCoreDetailsLocalSnapshot.self, missingLocal
        ) == .invalidEncodedLocalSnapshot)
    }

    @Test("Waiting and failures preserve exact local truth without enumerating inaccessible Clients")
    func updateFailureSemanticsAndDiagnostics() throws {
        let request = try Self.request()
        let incomplete = try Self.local([try Self.row(revision: .max)], complete: false)
        let unavailable = try ClientCoreDetailsUpdate(
            request: request,
            state: .failed(failure: .unavailable, cached: nil)
        )
        let retryable = try ClientCoreDetailsUpdate(
            request: request,
            state: .failed(failure: .retryable, cached: incomplete)
        )
        let requiredUpdate = try ClientCoreDetailsUpdate(
            request: request,
            state: .failed(failure: .requiredUpdate, cached: incomplete)
        )

        let acceptedWaiting = ListReadiness.allCases.filter { readiness in
            Self.failure {
                try ClientCoreDetailsUpdate(request: request, state: .waiting(readiness))
            } == nil
        }
        let rejectedWaiting = ListReadiness.allCases.filter { readiness in
            Self.failure {
                try ClientCoreDetailsUpdate(request: request, state: .waiting(readiness))
            } == .invalidWaitingState
        }
        #expect(acceptedWaiting == [.notRequested, .loading, .blocked])
        #expect(rejectedWaiting == [.ready, .partial, .stale])
        #expect(retryable.state != requiredUpdate.state)
        #expect(!incomplete.isAuthoritativeAbsence)
        #expect(!incomplete.observedRevisionIsFromCompleteReadySnapshot)
        #expect(incomplete.row?.locallyObservedRevision.rawValue == .max)

        #expect(Self.failure {
            try ClientCoreDetailsUpdate(
                request: request,
                state: .failed(failure: .unavailable, cached: incomplete)
            )
        } == .unavailableCachedEvidence)
        let otherRequest = try Self.request(client: "other-client")
        #expect(Self.failure {
            try ClientCoreDetailsUpdate(
                request: otherRequest,
                state: .failed(failure: .retryable, cached: incomplete)
            )
        } == .updateRequestMismatch)
        #expect(Self.failure {
            try ClientCoreDetailsUpdate(
                request: otherRequest,
                state: .snapshot(incomplete)
            )
        } == .updateRequestMismatch)
        #expect(Self.failure {
            try retryable.validating(request: otherRequest)
        } == .updateRequestMismatch)

        let unavailableBytes = try OperationContractCodec.encode(unavailable)
        let unavailableText = String(decoding: unavailableBytes, as: UTF8.self)
        #expect(!unavailableText.contains("Primary Client"))
        #expect(!unavailableText.contains("cached"))

        let diagnostics: [(ClientCoreDetailsFailure, String)] = [
            (.accountScopeMismatch, "client_core_details_account_scope_mismatch"),
            (.clientIdentityMismatch, "client_core_details_identity_mismatch"),
            (.multipleRows, "client_core_details_multiple_rows"),
            (.visibleCountMismatch, "client_core_details_visible_count_mismatch"),
            (.invalidSnapshotAsOf, "client_core_details_as_of_invalid"),
            (.invalidCompleteness, "client_core_details_completeness_invalid"),
            (.requestFingerprintMismatch, "client_core_details_request_fingerprint_mismatch"),
            (.queryFingerprintMismatch, "client_core_details_query_fingerprint_mismatch"),
            (.updateRequestMismatch, "client_core_details_update_request_mismatch"),
            (.invalidWaitingState, "client_core_details_waiting_state_invalid"),
            (.unavailableCachedEvidence, "client_core_details_unavailable_cache_invalid"),
            (.localReadFailed, "client_core_details_local_read_failed"),
            (.invalidEncodedRequest, "client_core_details_request_encoding_invalid"),
            (.invalidEncodedClient, "client_core_details_client_encoding_invalid"),
            (.invalidEncodedRevision, "client_core_details_revision_encoding_invalid"),
            (.invalidEncodedLocalSnapshot, "client_core_details_snapshot_encoding_invalid"),
            (.invalidEncodedUpdate, "client_core_details_update_encoding_invalid")
        ]
        let codes = diagnostics.map { failure, expectedCode in
            #expect(failure.diagnosticCode == expectedCode)
            #expect(expectedCode.utf8.count <= 80)
            #expect(expectedCode.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "_" })
            #expect(!expectedCode.contains("Primary Client"))
            #expect(!expectedCode.contains("client-one"))
            #expect(!expectedCode.contains("firebase"))
            #expect(!expectedCode.contains("supabase"))
            #expect(!expectedCode.contains("powersync"))
            return expectedCode
        }
        #expect(Set(codes).count == diagnostics.count)
    }

    @Test("The reference port validates before yield and propagates failure and cancellation")
    func exactPortFailureAndCancellation() async throws {
        let request = try Self.request()
        let local = try Self.local([try Self.row()])
        let exactUpdates = try [
            ClientCoreDetailsUpdate(request: request, state: .waiting(.loading)),
            ClientCoreDetailsUpdate(request: request, state: .snapshot(local))
        ]
        let exact = await Self.collect(FixturePort(updates: exactUpdates), request)
        #expect(exact.updates == exactUpdates && exact.failure == nil)

        let otherRequest = try Self.request(client: "other-client")
        let rebound = await Self.collectWithoutConsumerValidation(
            FixturePort(updates: exactUpdates),
            otherRequest
        )
        #expect(rebound.updates.isEmpty && rebound.failure == .updateRequestMismatch)

        let failed = await Self.collect(FailingPort(), request)
        #expect(failed.updates.isEmpty && failed.failure == .localReadFailed)

        let probe = ClientCoreCancellationProbe()
        let cancellable = CancellablePort(updates: exactUpdates, probe: probe)
        let consumer = Task { () -> [ClientCoreDetailsUpdate] in
            var updates: [ClientCoreDetailsUpdate] = []
            do {
                for try await update in cancellable.watchClientCoreDetails(request) {
                    updates.append(try update.validating(request: request))
                    await probe.markFirstDelivery()
                }
            } catch {}
            return updates
        }
        await probe.waitForFirstDelivery()
        consumer.cancel()
        #expect(await consumer.value == [exactUpdates[0]])
        await probe.waitForCancellation()
    }

    @Test("Every encoded value has only the frozen provider-free core-record keys")
    func encodedBoundary() throws {
        let request = try Self.request()
        let row = try Self.row(name: "  Primary Client  ")
        let snapshot = try Self.local([row])
        let update = try ClientCoreDetailsUpdate(request: request, state: .snapshot(snapshot))

        let requestObject = try Self.object(request)
        #expect(Set(requestObject.keys) == ["accountId", "clientId", "queryFingerprint"])

        let rowObject = try Self.object(row)
        #expect(Set(rowObject.keys) == ["client", "locallyObservedRevision"])
        let encodedClient = try #require(rowObject["client"] as? [String: Any])
        #expect(Set(encodedClient.keys) == [
            "id", "accountId", "displayName", "lifecycle", "createdAt", "updatedAt"
        ])
        let encodedRevision = try #require(
            rowObject["locallyObservedRevision"] as? [String: Any]
        )
        #expect(Set(encodedRevision.keys) == ["rawValue"])

        let snapshotObject = try Self.object(snapshot)
        #expect(Set(snapshotObject.keys) == ["request", "local"])
        let encodedLocal = try #require(snapshotObject["local"] as? [String: Any])
        #expect(Set(encodedLocal.keys) == [
            "queryFingerprint", "rows", "visibleRowCountBeforeFiltering",
            "isCompleteForQuery", "quality", "localDataVersion", "asOf"
        ])

        let updateObject = try Self.object(update)
        #expect(Set(updateObject.keys) == ["request", "state"])
        let snapshotState = try #require(updateObject["state"] as? [String: Any])
        #expect(Set(snapshotState.keys) == ["snapshot"])
        let snapshotCase = try #require(snapshotState["snapshot"] as? [String: Any])
        #expect(Set(snapshotCase.keys) == ["_0"])

        let waitingState = try Self.object(ClientCoreDetailsUpdateState.waiting(.loading))
        #expect(Set(waitingState.keys) == ["waiting"])
        let waitingCase = try #require(waitingState["waiting"] as? [String: Any])
        #expect(Set(waitingCase.keys) == ["_0"])

        let failedState = try Self.object(
            ClientCoreDetailsUpdateState.failed(failure: .retryable, cached: snapshot)
        )
        #expect(Set(failedState.keys) == ["failed"])
        let failedCase = try #require(failedState["failed"] as? [String: Any])
        #expect(Set(failedCase.keys) == ["failure", "cached"])

        let bytes = try OperationContractCodec.encode(update)
        let text = String(decoding: bytes, as: UTF8.self).lowercased()
        for forbidden in [
            "firebase", "firestore", "supabase", "powersync", "url", "attachment",
            "image", "pdf", "projectid", "projectcount", "transaction", "transfer",
            "spaceid", "noteid", "preference", "contact", "email", "phone", "address",
            "billing", "financial", "category", "invoice", "purchase", "occurrence",
            "budget", "accounting", "authorized", "permission", "path", "sql",
            "mutation", "report", "history", "producer", "actor", "serverrevision",
            "merge", "reassign", "restore", "delete"
        ] {
            #expect(!text.contains(forbidden))
        }
        #expect(try OperationContractCodec.encode(
            OperationContractCodec.decode(ClientCoreDetailsUpdate.self, from: bytes)
        ) == bytes)

        let malformedUpdate = try Self.mutate(bytes) { $0.removeValue(forKey: "state") }
        #expect(Self.decodeFailure(
            ClientCoreDetailsUpdate.self, malformedUpdate
        ) == .invalidEncodedUpdate)
    }

    private static let t0 = Date(timeIntervalSince1970: 1_802_300_000)
    private static let t1 = Date(timeIntervalSince1970: 1_802_300_001)
    private static let t2 = Date(timeIntervalSince1970: 1_802_300_002)
    private static let t3 = Date(timeIntervalSince1970: 1_802_300_003)
    private static let t4 = Date(timeIntervalSince1970: 1_802_300_004)
    private static let t5 = Date(timeIntervalSince1970: 1_802_300_005)
    private static let t6 = Date(timeIntervalSince1970: 1_802_300_006)
    private static let t7 = Date(timeIntervalSince1970: 1_802_300_007)

    private struct RestartFixture: Codable, Equatable, Sendable {
        let updates: [ClientCoreDetailsUpdate]
    }

    private static func request(
        account: String = "client-account",
        client: String = "client-one"
    ) throws -> ClientCoreDetailsRequest {
        try ClientCoreDetailsRequest(
            accountId: AccountID(validating: account),
            clientId: ClientID(validating: client)
        )
    }

    private static func row(
        account: String = "client-account",
        client: String = "client-one",
        name: String = "Primary Client",
        lifecycle: DirectoryLifecycleState = .active,
        createdAt: Date = t0,
        updatedAt: Date = t1,
        revision: UInt64 = 9
    ) throws -> ClientCoreDetailsSnapshot {
        let summary = try ClientSummary(
            id: ClientID(validating: client),
            accountId: AccountID(validating: account),
            displayName: ClientDisplayName(validating: name),
            lifecycle: lifecycle,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        return ClientCoreDetailsSnapshot(
            client: summary,
            locallyObservedRevision: ExpectedClientRevision(revision)
        )
    }

    private static func local(
        _ rows: [ClientCoreDetailsSnapshot],
        request: ClientCoreDetailsRequest? = nil,
        visibleCount: Int? = nil,
        quality: ListSnapshotQuality = .ready,
        complete: Bool = true,
        version: String = "test",
        date: Date = t0
    ) throws -> ClientCoreDetailsLocalSnapshot {
        let request = try request ?? Self.request()
        return try ClientCoreDetailsLocalSnapshot(
            request: request,
            rows: rows,
            visibleRowCountBeforeFiltering: visibleCount ?? rows.count,
            isCompleteForQuery: complete,
            quality: quality,
            localDataVersion: LocalDataVersion(validating: version),
            asOf: date
        )
    }

    private static func failure<Value>(
        _ body: () throws -> Value
    ) -> ClientCoreDetailsFailure? {
        do { _ = try body(); return nil }
        catch let failure as ClientCoreDetailsFailure { return failure }
        catch { return nil }
    }

    private static func directoryFailure<Value>(
        _ body: () throws -> Value
    ) -> ClientProjectDirectoryFailure? {
        do { _ = try body(); return nil }
        catch let failure as ClientProjectDirectoryFailure { return failure }
        catch { return nil }
    }

    private static func decodeFailure<Value: Decodable>(
        _ type: Value.Type,
        _ bytes: Data
    ) -> ClientCoreDetailsFailure? {
        failure { try OperationContractCodec.decode(type, from: bytes) }
    }

    private static func object<Value: Encodable>(_ value: Value) throws -> [String: Any] {
        let bytes = try OperationContractCodec.encode(value)
        return try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    }

    private static func mutate(
        _ bytes: Data,
        _ body: (inout [String: Any]) -> Void
    ) throws -> Data {
        var root = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        body(&root)
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    private static func mutateFirstRow(
        _ bytes: Data,
        _ body: (inout [String: Any]) -> Void
    ) throws -> Data {
        try mutate(bytes) { root in
            var local = root["local"] as! [String: Any]
            var rows = local["rows"] as! [[String: Any]]
            body(&rows[0])
            local["rows"] = rows
            root["local"] = local
        }
    }

    private static func mutateClient(
        _ bytes: Data,
        _ body: (inout [String: Any]) -> Void
    ) throws -> Data {
        try mutateFirstRow(bytes) { row in
            var client = row["client"] as! [String: Any]
            body(&client)
            row["client"] = client
        }
    }

    private static func collect<Port: ClientCoreDetailsQuerying>(
        _ port: Port,
        _ request: ClientCoreDetailsRequest
    ) async -> (updates: [ClientCoreDetailsUpdate], failure: ClientCoreDetailsFailure?) {
        var updates: [ClientCoreDetailsUpdate] = []
        do {
            for try await update in port.watchClientCoreDetails(request) {
                updates.append(try update.validating(request: request))
            }
            return (updates, nil)
        } catch let failure as ClientCoreDetailsFailure {
            return (updates, failure)
        } catch {
            return (updates, nil)
        }
    }

    private static func collectWithoutConsumerValidation<Port: ClientCoreDetailsQuerying>(
        _ port: Port,
        _ request: ClientCoreDetailsRequest
    ) async -> (updates: [ClientCoreDetailsUpdate], failure: ClientCoreDetailsFailure?) {
        var updates: [ClientCoreDetailsUpdate] = []
        do {
            for try await update in port.watchClientCoreDetails(request) {
                updates.append(update)
            }
            return (updates, nil)
        } catch let failure as ClientCoreDetailsFailure {
            return (updates, failure)
        } catch {
            return (updates, nil)
        }
    }
}

private struct FixturePort: ClientCoreDetailsQuerying {
    let updates: [ClientCoreDetailsUpdate]

    func watchClientCoreDetails(
        _ request: ClientCoreDetailsRequest
    ) -> AsyncThrowingStream<ClientCoreDetailsUpdate, Error> {
        AsyncThrowingStream { continuation in
            do {
                for update in updates {
                    continuation.yield(try update.validating(request: request))
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}

private struct FailingPort: ClientCoreDetailsQuerying {
    func watchClientCoreDetails(
        _ request: ClientCoreDetailsRequest
    ) -> AsyncThrowingStream<ClientCoreDetailsUpdate, Error> {
        AsyncThrowingStream { $0.finish(throwing: ClientCoreDetailsFailure.localReadFailed) }
    }
}

private struct CancellablePort: ClientCoreDetailsQuerying {
    let updates: [ClientCoreDetailsUpdate]
    let probe: ClientCoreCancellationProbe

    func watchClientCoreDetails(
        _ request: ClientCoreDetailsRequest
    ) -> AsyncThrowingStream<ClientCoreDetailsUpdate, Error> {
        AsyncThrowingStream { continuation in
            let producer = Task {
                continuation.yield(updates[0])
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                guard !Task.isCancelled else { return }
                for update in updates.dropFirst() { continuation.yield(update) }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                producer.cancel()
                Task { await probe.markCancelled() }
            }
        }
    }
}

private actor ClientCoreCancellationProbe {
    private var deliveredFirst = false
    private var cancelled = false
    private var firstWaiter: CheckedContinuation<Void, Never>?
    private var cancellationWaiter: CheckedContinuation<Void, Never>?

    func markFirstDelivery() {
        deliveredFirst = true
        firstWaiter?.resume()
        firstWaiter = nil
    }

    func waitForFirstDelivery() async {
        guard !deliveredFirst else { return }
        await withCheckedContinuation { firstWaiter = $0 }
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
