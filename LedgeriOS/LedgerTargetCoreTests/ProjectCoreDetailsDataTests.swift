import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Project Core Details Read Contracts")
struct ProjectCoreDetailsDataTests {
    @Test("Active and archived Projects preserve exact core identity, relationship, and revision")
    func coreDetailsAndFingerprintBinding() throws {
        let request = try Self.request()
        let accountChanged = try Self.request(account: "other-account")
        let projectChanged = try Self.request(project: "other-project")
        #expect(Set([
            request.queryFingerprint,
            accountChanged.queryFingerprint,
            projectChanged.queryFingerprint
        ]).count == 3)

        let active = try Self.row(description: nil, revision: 0)
        let activeLocal = try Self.local([active])
        #expect(active.project.id == request.projectId)
        #expect(active.project.accountId == request.accountId)
        #expect(active.project.clientId == active.project.client.id)
        #expect(active.project.description == nil)
        #expect(active.project.lifecycle == .active)
        #expect(active.locallyObservedRevision.rawValue == 0)
        #expect(activeLocal.row == active)
        #expect(activeLocal.observedRevisionIsFromCompleteReadySnapshot)
        #expect(!activeLocal.isAuthoritativeAbsence)

        let archived = try Self.row(
            description: "Preserve interior   spacing",
            projectLifecycle: .archived,
            revision: .max
        )
        #expect(archived.project.description == "Preserve interior   spacing")
        #expect(archived.project.lifecycle == .archived)
        #expect(archived.locallyObservedRevision.rawValue == .max)
        #expect(try Self.local([archived]).row == archived)

        let archivedClient = try Self.row(clientLifecycle: .archived)
        #expect(archivedClient.project.lifecycle == .active)
        #expect(archivedClient.project.client.lifecycle == .archived)
        #expect(try Self.local([archivedClient]).row == archivedClient)
    }

    @Test("All local readiness variants restart without upgrading absence or revision evidence")
    func canonicalRestartAndOfflineTruth() throws {
        let request = try Self.request()
        let archived = try Self.row(projectLifecycle: .archived, revision: .max)
        let states = try [
            Self.local([archived], version: "ready-found", date: Self.t0),
            Self.local([], version: "ready-absent", date: Self.t1),
            Self.local([archived], complete: false, version: "incomplete-found", date: Self.t2),
            Self.local([], complete: false, version: "incomplete-empty", date: Self.t3),
            Self.local([archived], quality: .partial, complete: false, version: "partial-found", date: Self.t4),
            Self.local([], quality: .partial, complete: false, version: "partial-empty", date: Self.t5),
            Self.local([archived], quality: .stale, complete: false, version: "stale-found", date: Self.t6),
            Self.local([], quality: .stale, complete: false, version: "stale-empty", date: Self.t7)
        ]
        let fixture = try RestartFixture(
            updates: states.map {
                try ProjectCoreDetailsUpdate(request: request, state: .snapshot($0))
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
        #expect(states.map(\.isAuthoritativeAbsence) == [false, true, false, false, false, false, false, false])
        #expect(states.map(\.observedRevisionIsFromCompleteReadySnapshot) == [true, false, false, false, false, false, false, false])
        #expect(states.map(\.local.asOf) == [Self.t0, Self.t1, Self.t2, Self.t3, Self.t4, Self.t5, Self.t6, Self.t7])
        #expect(states[0].row?.locallyObservedRevision.rawValue == .max)
        #expect(states[2].row?.locallyObservedRevision.rawValue == .max)
        #expect(states[4].row?.locallyObservedRevision.rawValue == .max)
        #expect(states[6].row?.locallyObservedRevision.rawValue == .max)
        #expect(states[0].local.localDataVersion.rawValue != String(states[0].row!.locallyObservedRevision.rawValue))
    }

    @Test("Malformed, rebound, noncanonical, and hidden Project evidence is refused atomically")
    func refusalAndTamperCases() throws {
        let request = try Self.request()
        let row = try Self.row()
        #expect(Self.failure {
            try Self.local([try Self.row(account: "other-account")])
        } == .accountScopeMismatch)
        #expect(Self.failure {
            try Self.local([try Self.row(project: "other-project")])
        } == .projectIdentityMismatch)
        #expect(Self.failure { try Self.local([row, row]) } == .multipleRows)
        #expect(Self.failure {
            try Self.local([
                row,
                try Self.row(project: "other-project", client: "other-client")
            ])
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
        #expect(Self.failure {
            try Self.row(description: "  noncanonical  ")
        } == .noncanonicalDescription)
        #expect(Self.failure {
            try Self.row(description: "   \n ")
        } == .noncanonicalDescription)

        let wrongFingerprint = try ListQueryFingerprint(validating: String(repeating: "a", count: 64))
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
            try ProjectCoreDetailsLocalSnapshot(request: request, local: reboundLocal)
        } == .queryFingerprintMismatch)

        let requestBytes = try OperationContractCodec.encode(request)
        let fingerprintTamper = try Self.mutate(requestBytes) {
            $0["queryFingerprint"] = String(repeating: "b", count: 64)
        }
        #expect(Self.decodeFailure(ProjectCoreDetailsRequest.self, fingerprintTamper) == .requestFingerprintMismatch)
        let accountTamper = try Self.mutate(requestBytes) { $0["accountId"] = "other-account" }
        #expect(Self.decodeFailure(ProjectCoreDetailsRequest.self, accountTamper) == .requestFingerprintMismatch)
        let projectTamper = try Self.mutate(requestBytes) { $0["projectId"] = "other-project" }
        #expect(Self.decodeFailure(ProjectCoreDetailsRequest.self, projectTamper) == .requestFingerprintMismatch)
        let invalidAccount = try Self.mutate(requestBytes) { $0["accountId"] = "   " }
        #expect(Self.decodeFailure(ProjectCoreDetailsRequest.self, invalidAccount) == .invalidEncodedRequest)

        let localBytes = try OperationContractCodec.encode(try Self.local([row]))
        let reboundAccount = try Self.mutateProject(localBytes) { $0["accountId"] = "other-account" }
        #expect(Self.decodeFailure(ProjectCoreDetailsLocalSnapshot.self, reboundAccount) == .accountScopeMismatch)
        let reboundProject = try Self.mutateProject(localBytes) { $0["id"] = "other-project" }
        #expect(Self.decodeFailure(ProjectCoreDetailsLocalSnapshot.self, reboundProject) == .projectIdentityMismatch)
        let badRelationship = try Self.mutateProject(localBytes) { $0["clientId"] = "other-client" }
        #expect(Self.decodeFailure(ProjectCoreDetailsLocalSnapshot.self, badRelationship) == .clientRelationshipMismatch)
        let badClientAccount = try Self.mutateProject(localBytes) { project in
            var client = project["client"] as! [String: Any]
            client["accountId"] = "other-account"
            project["client"] = client
        }
        #expect(Self.decodeFailure(ProjectCoreDetailsLocalSnapshot.self, badClientAccount) == .accountScopeMismatch)
        let badProjectName = try Self.mutateProject(localBytes) { $0["displayName"] = "   " }
        #expect(Self.decodeFailure(ProjectCoreDetailsLocalSnapshot.self, badProjectName) == .invalidEncodedProject)
        let paddedDescription = try Self.mutateProject(localBytes) { $0["description"] = " Core description " }
        #expect(Self.decodeFailure(ProjectCoreDetailsLocalSnapshot.self, paddedDescription) == .noncanonicalDescription)
        let blankDescription = try Self.mutateProject(localBytes) { $0["description"] = "  \n " }
        #expect(Self.decodeFailure(ProjectCoreDetailsLocalSnapshot.self, blankDescription) == .noncanonicalDescription)
        let malformedRevision = try Self.mutateFirstRow(localBytes) { row in
            row["locallyObservedRevision"] = ["rawValue": -1]
        }
        #expect(Self.decodeFailure(ProjectCoreDetailsLocalSnapshot.self, malformedRevision) == .invalidEncodedRevision)
        let missingRevision = try Self.mutateFirstRow(localBytes) { $0.removeValue(forKey: "locallyObservedRevision") }
        #expect(Self.decodeFailure(ProjectCoreDetailsLocalSnapshot.self, missingRevision) == .invalidEncodedRevision)
        let hiddenCount = try Self.mutate(localBytes) { root in
            var local = root["local"] as! [String: Any]
            local["visibleRowCountBeforeFiltering"] = 2
            root["local"] = local
        }
        #expect(Self.decodeFailure(ProjectCoreDetailsLocalSnapshot.self, hiddenCount) == .visibleCountMismatch)
        let reboundQuery = try Self.mutate(localBytes) { root in
            var local = root["local"] as! [String: Any]
            local["queryFingerprint"] = String(repeating: "c", count: 64)
            root["local"] = local
        }
        #expect(Self.decodeFailure(ProjectCoreDetailsLocalSnapshot.self, reboundQuery) == .queryFingerprintMismatch)
        let invalidCompleteness = try Self.mutate(localBytes) { root in
            var local = root["local"] as! [String: Any]
            local["quality"] = "partial"
            root["local"] = local
        }
        #expect(Self.decodeFailure(ProjectCoreDetailsLocalSnapshot.self, invalidCompleteness) == .invalidCompleteness)
    }

    @Test("Waiting and bounded failures retain truth without enumerating inaccessible Projects")
    func updateFailureSemanticsAndDiagnostics() throws {
        let request = try Self.request()
        let incomplete = try Self.local([try Self.row(revision: .max)], complete: false)
        let unavailable = try ProjectCoreDetailsUpdate(
            request: request,
            state: .failed(failure: .unavailable, cached: nil)
        )
        let retryable = try ProjectCoreDetailsUpdate(
            request: request,
            state: .failed(failure: .retryable, cached: incomplete)
        )
        let requiredUpdate = try ProjectCoreDetailsUpdate(
            request: request,
            state: .failed(failure: .requiredUpdate, cached: incomplete)
        )
        for readiness in [ListReadiness.notRequested, .loading, .blocked] {
            let waiting = try ProjectCoreDetailsUpdate(
                request: request,
                state: .waiting(readiness)
            )
            #expect(waiting.state == .waiting(readiness))
        }
        #expect(retryable.state != requiredUpdate.state)
        #expect(!incomplete.isAuthoritativeAbsence)
        #expect(!incomplete.observedRevisionIsFromCompleteReadySnapshot)
        for readiness in [ListReadiness.ready, .partial, .stale] {
            #expect(Self.failure {
                try ProjectCoreDetailsUpdate(request: request, state: .waiting(readiness))
            } == .invalidWaitingState)
        }
        #expect(Self.failure {
            try ProjectCoreDetailsUpdate(
                request: request,
                state: .failed(failure: .unavailable, cached: incomplete)
            )
        } == .unavailableCachedEvidence)
        let otherRequest = try Self.request(project: "other-project")
        #expect(Self.failure {
            try ProjectCoreDetailsUpdate(
                request: otherRequest,
                state: .failed(failure: .retryable, cached: incomplete)
            )
        } == .updateRequestMismatch)

        let unavailableBytes = try OperationContractCodec.encode(unavailable)
        let unavailableText = String(decoding: unavailableBytes, as: UTF8.self)
        #expect(!unavailableText.contains("Primary Project"))
        #expect(!unavailableText.contains("client-one"))
        #expect(!unavailableText.contains("Core description"))
        #expect(!unavailableText.contains("cached"))

        let diagnostics: [(ProjectCoreDetailsFailure, String)] = [
            (.accountScopeMismatch, "project_core_details_account_scope_mismatch"),
            (.projectIdentityMismatch, "project_core_details_identity_mismatch"),
            (.clientRelationshipMismatch, "project_core_details_client_relationship_mismatch"),
            (.noncanonicalDescription, "project_core_details_description_noncanonical"),
            (.multipleRows, "project_core_details_multiple_rows"),
            (.visibleCountMismatch, "project_core_details_visible_count_mismatch"),
            (.invalidSnapshotAsOf, "project_core_details_as_of_invalid"),
            (.invalidCompleteness, "project_core_details_completeness_invalid"),
            (.requestFingerprintMismatch, "project_core_details_request_fingerprint_mismatch"),
            (.queryFingerprintMismatch, "project_core_details_query_fingerprint_mismatch"),
            (.updateRequestMismatch, "project_core_details_update_request_mismatch"),
            (.invalidWaitingState, "project_core_details_waiting_state_invalid"),
            (.unavailableCachedEvidence, "project_core_details_unavailable_cache_invalid"),
            (.localReadFailed, "project_core_details_local_read_failed"),
            (.invalidEncodedRequest, "project_core_details_request_encoding_invalid"),
            (.invalidEncodedProject, "project_core_details_project_encoding_invalid"),
            (.invalidEncodedRevision, "project_core_details_revision_encoding_invalid"),
            (.invalidEncodedLocalSnapshot, "project_core_details_snapshot_encoding_invalid"),
            (.invalidEncodedUpdate, "project_core_details_update_encoding_invalid")
        ]
        let codes = diagnostics.map { failure, expectedCode in
            #expect(failure.diagnosticCode == expectedCode)
            #expect(expectedCode.utf8.count <= 80)
            #expect(expectedCode.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "_" })
            #expect(!expectedCode.contains("firebase"))
            #expect(!expectedCode.contains("supabase"))
            #expect(!expectedCode.contains("powersync"))
            return expectedCode
        }
        #expect(Set(codes).count == diagnostics.count)
    }

    @Test("The query port validates before yield and propagates failure and cancellation")
    func exactPortFailureAndCancellation() async throws {
        let request = try Self.request()
        let local = try Self.local([try Self.row()])
        let exactUpdates = try [
            ProjectCoreDetailsUpdate(request: request, state: .waiting(.loading)),
            ProjectCoreDetailsUpdate(request: request, state: .snapshot(local))
        ]
        let exact = await Self.collect(FixturePort(updates: exactUpdates), request)
        #expect(exact.updates == exactUpdates && exact.failure == nil)

        let otherRequest = try Self.request(project: "other-project")
        let rebound = await Self.collectWithoutConsumerValidation(
            FixturePort(updates: exactUpdates),
            otherRequest
        )
        #expect(rebound.updates.isEmpty && rebound.failure == .updateRequestMismatch)

        let failed = await Self.collect(FailingPort(), request)
        #expect(failed.updates.isEmpty && failed.failure == .localReadFailed)

        let probe = ProjectCoreCancellationProbe()
        let cancellable = CancellablePort(updates: exactUpdates, probe: probe)
        let consumer = Task { () -> [ProjectCoreDetailsUpdate] in
            var updates: [ProjectCoreDetailsUpdate] = []
            do {
                for try await update in cancellable.watchProjectCoreDetails(request) {
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

    @Test("Encoded contracts contain only the frozen provider-free core-record boundary")
    func encodedBoundary() throws {
        let request = try Self.request()
        let snapshot = try Self.local([try Self.row()])
        let update = try ProjectCoreDetailsUpdate(request: request, state: .snapshot(snapshot))
        let bytes = try OperationContractCodec.encode(update)
        let root = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        #expect(Set(root.keys) == ["request", "state"])
        let encodedRequest = try #require(root["request"] as? [String: Any])
        #expect(Set(encodedRequest.keys) == ["accountId", "projectId", "queryFingerprint"])

        let snapshotState = try #require(root["state"] as? [String: Any])
        let snapshotCase = try #require(snapshotState["snapshot"] as? [String: Any])
        let wrappedSnapshot = try #require(snapshotCase["_0"] as? [String: Any])
        let local = try #require(wrappedSnapshot["local"] as? [String: Any])
        let rows = try #require(local["rows"] as? [[String: Any]])
        let encodedRow = try #require(rows.first)
        #expect(Set(encodedRow.keys) == ["project", "locallyObservedRevision"])
        let encodedProject = try #require(encodedRow["project"] as? [String: Any])
        #expect(Set(encodedProject.keys) == [
            "id", "accountId", "clientId", "client", "displayName", "description", "lifecycle"
        ])

        let text = String(decoding: bytes, as: UTF8.self).lowercased()
        for forbidden in [
            "firebase", "firestore", "supabase", "powersync", "url", "attachment",
            "image", "pdf", "itemid", "transaction", "spaceid", "noteid", "preference",
            "category", "invoice", "purchase", "occurrence", "budget", "accounting",
            "authorized", "permission", "path", "sql", "mutation", "report", "history",
            "currentserverrevision"
        ] {
            #expect(!text.contains(forbidden))
        }
        #expect(try OperationContractCodec.encode(
            OperationContractCodec.decode(ProjectCoreDetailsUpdate.self, from: bytes)
        ) == bytes)
    }

    private static let t0 = Date(timeIntervalSince1970: 1_802_200_000)
    private static let t1 = Date(timeIntervalSince1970: 1_802_200_001)
    private static let t2 = Date(timeIntervalSince1970: 1_802_200_002)
    private static let t3 = Date(timeIntervalSince1970: 1_802_200_003)
    private static let t4 = Date(timeIntervalSince1970: 1_802_200_004)
    private static let t5 = Date(timeIntervalSince1970: 1_802_200_005)
    private static let t6 = Date(timeIntervalSince1970: 1_802_200_006)
    private static let t7 = Date(timeIntervalSince1970: 1_802_200_007)

    private struct RestartFixture: Codable, Equatable, Sendable {
        let updates: [ProjectCoreDetailsUpdate]
    }

    private static func request(
        account: String = "project-account",
        project: String = "project-one"
    ) throws -> ProjectCoreDetailsRequest {
        try ProjectCoreDetailsRequest(
            accountId: AccountID(validating: account),
            projectId: ProjectID(validating: project)
        )
    }

    private static func row(
        account: String = "project-account",
        project: String = "project-one",
        client: String = "client-one",
        description: String? = "Core description",
        projectLifecycle: DirectoryLifecycleState = .active,
        clientLifecycle: DirectoryLifecycleState = .active,
        revision: UInt64 = 9
    ) throws -> ProjectCoreDetailsSnapshot {
        let accountId = try AccountID(validating: account)
        let clientId = try ClientID(validating: client)
        let clientSummary = try ClientSummary(
            id: clientId,
            accountId: accountId,
            displayName: ClientDisplayName(validating: "Design Client"),
            lifecycle: clientLifecycle,
            createdAt: t0,
            updatedAt: t1
        )
        let projectSummary = try ProjectSummary(
            id: ProjectID(validating: project),
            accountId: accountId,
            clientId: clientId,
            client: clientSummary,
            displayName: ProjectDisplayName(validating: "Primary Project"),
            description: description,
            lifecycle: projectLifecycle
        )
        return try ProjectCoreDetailsSnapshot(
            project: projectSummary,
            locallyObservedRevision: ExpectedProjectRevision(revision)
        )
    }

    private static func local(
        _ rows: [ProjectCoreDetailsSnapshot],
        request: ProjectCoreDetailsRequest? = nil,
        visibleCount: Int? = nil,
        quality: ListSnapshotQuality = .ready,
        complete: Bool = true,
        version: String = "test",
        date: Date = t0
    ) throws -> ProjectCoreDetailsLocalSnapshot {
        let request = try request ?? Self.request()
        return try ProjectCoreDetailsLocalSnapshot(
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
    ) -> ProjectCoreDetailsFailure? {
        do { _ = try body(); return nil }
        catch let failure as ProjectCoreDetailsFailure { return failure }
        catch { return nil }
    }

    private static func decodeFailure<Value: Decodable>(
        _ type: Value.Type,
        _ bytes: Data
    ) -> ProjectCoreDetailsFailure? {
        failure { try OperationContractCodec.decode(type, from: bytes) }
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

    private static func mutateProject(
        _ bytes: Data,
        _ body: (inout [String: Any]) -> Void
    ) throws -> Data {
        try mutateFirstRow(bytes) { row in
            var project = row["project"] as! [String: Any]
            body(&project)
            row["project"] = project
        }
    }

    private static func collect<Port: ProjectCoreDetailsQuerying>(
        _ port: Port,
        _ request: ProjectCoreDetailsRequest
    ) async -> (updates: [ProjectCoreDetailsUpdate], failure: ProjectCoreDetailsFailure?) {
        var updates: [ProjectCoreDetailsUpdate] = []
        do {
            for try await update in port.watchProjectCoreDetails(request) {
                updates.append(try update.validating(request: request))
            }
            return (updates, nil)
        } catch let failure as ProjectCoreDetailsFailure {
            return (updates, failure)
        } catch {
            return (updates, nil)
        }
    }

    private static func collectWithoutConsumerValidation<Port: ProjectCoreDetailsQuerying>(
        _ port: Port,
        _ request: ProjectCoreDetailsRequest
    ) async -> (updates: [ProjectCoreDetailsUpdate], failure: ProjectCoreDetailsFailure?) {
        var updates: [ProjectCoreDetailsUpdate] = []
        do {
            for try await update in port.watchProjectCoreDetails(request) {
                updates.append(update)
            }
            return (updates, nil)
        } catch let failure as ProjectCoreDetailsFailure {
            return (updates, failure)
        } catch {
            return (updates, nil)
        }
    }
}

private struct FixturePort: ProjectCoreDetailsQuerying {
    let updates: [ProjectCoreDetailsUpdate]

    func watchProjectCoreDetails(
        _ request: ProjectCoreDetailsRequest
    ) -> AsyncThrowingStream<ProjectCoreDetailsUpdate, Error> {
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

private struct FailingPort: ProjectCoreDetailsQuerying {
    func watchProjectCoreDetails(
        _ request: ProjectCoreDetailsRequest
    ) -> AsyncThrowingStream<ProjectCoreDetailsUpdate, Error> {
        AsyncThrowingStream { $0.finish(throwing: ProjectCoreDetailsFailure.localReadFailed) }
    }
}

private struct CancellablePort: ProjectCoreDetailsQuerying {
    let updates: [ProjectCoreDetailsUpdate]
    let probe: ProjectCoreCancellationProbe

    func watchProjectCoreDetails(
        _ request: ProjectCoreDetailsRequest
    ) -> AsyncThrowingStream<ProjectCoreDetailsUpdate, Error> {
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

private actor ProjectCoreCancellationProbe {
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
