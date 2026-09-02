import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Space Core Details Read Contracts")
struct SpaceCoreDetailsDataTests {
    @Test("Project and inventory Spaces preserve exact core detail and derived progress")
    func projectAndInventoryDetails() throws {
        let request = try Self.request()
        let accountChanged = try Self.request(account: "other-account")
        let spaceChanged = try Self.request(space: "other-space")
        #expect(Set([
            request.queryFingerprint,
            accountChanged.queryFingerprint,
            spaceChanged.queryFingerprint
        ]).count == 3)

        let sharedItemID = try SpaceChecklistItemID(validating: "shared-item")
        let laterChecklist = try Self.checklist(
            "installation",
            name: "Install",
            order: 20,
            items: [
                Self.item(sharedItemID, text: "Hang art", checked: true, order: 2),
                Self.item("level", text: "Hang art", checked: false, order: 1)
            ]
        )
        let earlierChecklist = try Self.checklist(
            "quality",
            name: "Install",
            order: 10,
            items: [Self.item(sharedItemID, text: "Hang art", checked: true, order: 1)]
        )
        let emptyChecklist = try Self.checklist("empty", order: 30, items: [])
        let project = try Self.space(
            scope: .project(ProjectID(validating: "project-one")),
            name: "  Living Room  ",
            notes: "  Preserve interior   spacing  ",
            revision: 0,
            createdAt: Self.t2,
            updatedAt: Self.t1,
            checklists: [laterChecklist, emptyChecklist, earlierChecklist]
        )
        let found = try Self.local([project])

        #expect(project.displayName.rawValue == "Living Room")
        #expect(project.notes.value == "Preserve interior   spacing")
        #expect(project.revision == 0)
        #expect(project.createdAt == Self.t2 && project.updatedAt == Self.t1)
        #expect(project.checklists.checklists.map(\.id.rawValue) == ["quality", "installation", "empty"])
        #expect(project.checklists.checklists[1].items.map(\.id.rawValue) == ["level", "shared-item"])
        #expect(project.checklists.checklists.map(\.completedItemCount) == [1, 1, 0])
        #expect(project.checklists.checklists.map(\.totalItemCount) == [1, 2, 0])
        #expect(project.completedItemCount == 2 && project.totalItemCount == 3)
        #expect(found.row == project && found.progressCountsAreAuthoritative)
        #expect(!found.isAuthoritativeAbsence)

        let inventoryRequest = try Self.request(space: "inventory-space")
        let inventory = try Self.space(
            id: "inventory-space",
            scope: .businessInventory,
            name: "Warehouse",
            notes: nil,
            lifecycle: .archived,
            revision: .max,
            checklists: []
        )
        let archived = try Self.local([inventory], request: inventoryRequest)
        #expect(inventory.scope == .businessInventory)
        #expect(inventory.lifecycle == .archived)
        #expect(inventory.notes.value == nil)
        #expect(inventory.completedItemCount == 0 && inventory.totalItemCount == 0)
        #expect(archived.row == inventory && !archived.isAuthoritativeAbsence)
    }

    @Test("All found and empty readiness variants restart canonically without upgrading evidence")
    func canonicalRestartAndOfflineTruth() throws {
        let request = try Self.request()
        let archived = try Self.space(lifecycle: .archived)
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
                try SpaceCoreDetailsUpdate(request: request, state: .snapshot($0))
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
        #expect(states.map(\.progressCountsAreAuthoritative) == [true, false, false, false, false, false, false, false])
        #expect(states[0].row?.lifecycle == .archived)
        #expect(states[2].row?.lifecycle == .archived)
    }

    @Test("Malformed, rebound, noncanonical, and hidden evidence is refused atomically")
    func refusalAndTamperCases() throws {
        let request = try Self.request()
        let row = try Self.space()
        #expect(Self.failure {
            try Self.local([try Self.space(account: "other-account")])
        } == .accountScopeMismatch)
        #expect(Self.failure {
            try Self.local([try Self.space(id: "other-space")])
        } == .spaceIdentityMismatch)
        #expect(Self.failure { try Self.local([row, row]) } == .multipleRows)
        #expect(Self.failure { try Self.local([row], visibleCount: 2) } == .visibleCountMismatch)
        #expect(Self.failure {
            try Self.local([row], date: Date(timeIntervalSinceReferenceDate: .infinity))
        } == .invalidSnapshotAsOf)
        #expect(Self.failure {
            try Self.local([row], quality: .partial, complete: true)
        } == .invalidCompleteness)
        #expect(Self.failure {
            try SpaceCoreDetailsSnapshot(
                id: row.id,
                accountId: row.accountId,
                scope: row.scope,
                displayName: row.displayName,
                notes: row.notes,
                lifecycle: row.lifecycle,
                revision: row.revision,
                createdAt: Date(timeIntervalSinceReferenceDate: .nan),
                updatedAt: row.updatedAt,
                checklists: row.checklists
            )
        } == .invalidSpaceTimestamp)

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
            try SpaceCoreDetailsLocalSnapshot(request: request, local: reboundLocal)
        } == .queryFingerprintMismatch)

        let requestBytes = try OperationContractCodec.encode(request)
        let badFingerprint = try Self.mutate(requestBytes) {
            $0["queryFingerprint"] = String(repeating: "b", count: 64)
        }
        #expect(Self.decodeFailure(SpaceCoreDetailsRequest.self, badFingerprint) == .requestFingerprintMismatch)

        let localBytes = try OperationContractCodec.encode(try Self.local([row]))
        let reboundAccount = try Self.mutateFirstRow(localBytes) { row in
            row["accountId"] = "other-account"
        }
        #expect(Self.decodeFailure(SpaceCoreDetailsLocalSnapshot.self, reboundAccount) == .accountScopeMismatch)
        let noncanonicalName = try Self.mutateFirstRow(localBytes) { row in
            row["displayName"] = " Living Room "
        }
        #expect(Self.decodeFailure(SpaceCoreDetailsLocalSnapshot.self, noncanonicalName) == .invalidEncodedSpace)
        let noncanonicalNotes = try Self.mutateFirstRow(localBytes) { row in
            row["notes"] = ["value": " Operational notes "]
        }
        #expect(Self.decodeFailure(SpaceCoreDetailsLocalSnapshot.self, noncanonicalNotes) == .invalidEncodedSpace)
        let invalidScope = try Self.mutateFirstRow(localBytes) { row in
            row["scope"] = ["kind": "businessInventory", "projectId": "not-allowed"]
        }
        #expect(Self.decodeFailure(SpaceCoreDetailsLocalSnapshot.self, invalidScope) == .invalidSpaceScope)

        let checklistRow = try Self.space(checklists: [
            Self.checklist("one", order: 1, items: [
                Self.item("item", text: "First", checked: false, order: 1),
                Self.item("item-two", text: "Second", checked: false, order: 2)
            ]),
            Self.checklist("two", order: 2, items: [Self.item("other", text: "Second", checked: true, order: 1)])
        ])
        let checklistBytes = try OperationContractCodec.encode(try Self.local([checklistRow]))
        let noncanonicalChecklistName = try Self.mutateChecklists(checklistBytes) { checklists in
            checklists[0]["name"] = " One "
        }
        #expect(Self.decodeFailure(SpaceCoreDetailsLocalSnapshot.self, noncanonicalChecklistName) == .invalidEncodedSpace)
        let noncanonicalChecklistItemText = try Self.mutateChecklists(checklistBytes) { checklists in
            var items = checklists[0]["items"] as! [[String: Any]]
            items[0]["text"] = " First "
            checklists[0]["items"] = items
        }
        #expect(Self.decodeFailure(SpaceCoreDetailsLocalSnapshot.self, noncanonicalChecklistItemText) == .invalidEncodedSpace)
        let duplicateChecklist = try Self.mutateChecklists(checklistBytes) { checklists in
            checklists[1]["id"] = checklists[0]["id"]
        }
        #expect(Self.decodeFailure(SpaceCoreDetailsLocalSnapshot.self, duplicateChecklist) == .invalidEncodedSpace)
        let duplicateChecklistOrder = try Self.mutateChecklists(checklistBytes) { checklists in
            checklists[1]["presentationOrder"] = checklists[0]["presentationOrder"]
        }
        #expect(Self.decodeFailure(SpaceCoreDetailsLocalSnapshot.self, duplicateChecklistOrder) == .invalidEncodedSpace)
        let duplicateItem = try Self.mutateChecklists(checklistBytes) { checklists in
            var items = checklists[0]["items"] as! [[String: Any]]
            items[1]["id"] = items[0]["id"]
            checklists[0]["items"] = items
        }
        #expect(Self.decodeFailure(SpaceCoreDetailsLocalSnapshot.self, duplicateItem) == .invalidEncodedSpace)
        let duplicateItemOrder = try Self.mutateChecklists(checklistBytes) { checklists in
            var items = checklists[0]["items"] as! [[String: Any]]
            items[1]["presentationOrder"] = items[0]["presentationOrder"]
            checklists[0]["items"] = items
        }
        #expect(Self.decodeFailure(SpaceCoreDetailsLocalSnapshot.self, duplicateItemOrder) == .invalidEncodedSpace)
        let noncanonicalOrder = try Self.mutateChecklists(checklistBytes) { checklists in
            checklists.reverse()
        }
        #expect(Self.decodeFailure(SpaceCoreDetailsLocalSnapshot.self, noncanonicalOrder) == .invalidEncodedSpace)
    }

    @Test("Waiting and bounded failure states retain truth without enumerating unavailable Spaces")
    func updateFailureSemantics() throws {
        let request = try Self.request()
        let incomplete = try Self.local([try Self.space()], complete: false)
        let waiting = try SpaceCoreDetailsUpdate(request: request, state: .waiting(.loading))
        let unavailable = try SpaceCoreDetailsUpdate(
            request: request,
            state: .failed(failure: .unavailable, cached: nil)
        )
        let retryable = try SpaceCoreDetailsUpdate(
            request: request,
            state: .failed(failure: .retryable, cached: incomplete)
        )
        let requiredUpdate = try SpaceCoreDetailsUpdate(
            request: request,
            state: .failed(failure: .requiredUpdate, cached: incomplete)
        )
        #expect(waiting.state == .waiting(.loading))
        #expect(retryable.state != requiredUpdate.state)
        #expect(!incomplete.progressCountsAreAuthoritative)
        #expect(Self.failure {
            try SpaceCoreDetailsUpdate(request: request, state: .waiting(.ready))
        } == .invalidWaitingState)
        #expect(Self.failure {
            try SpaceCoreDetailsUpdate(
                request: request,
                state: .failed(failure: .unavailable, cached: incomplete)
            )
        } == .unavailableCachedEvidence)
        let otherRequest = try Self.request(space: "other-space")
        #expect(Self.failure {
            try SpaceCoreDetailsUpdate(
                request: otherRequest,
                state: .failed(failure: .retryable, cached: incomplete)
            )
        } == .updateRequestMismatch)

        let unavailableBytes = try OperationContractCodec.encode(unavailable)
        let unavailableText = String(decoding: unavailableBytes, as: UTF8.self)
        #expect(!unavailableText.contains("Living Room"))
        #expect(!unavailableText.contains("authoritativeAbsence"))
        #expect(!unavailableText.contains("cached"))

        let diagnostics: [(SpaceCoreDetailsFailure, String)] = [
            (.accountScopeMismatch, "space_core_details_account_scope_mismatch"),
            (.spaceIdentityMismatch, "space_core_details_identity_mismatch"),
            (.invalidSpaceScope, "space_core_details_scope_invalid"),
            (.invalidSpaceTimestamp, "space_core_details_timestamp_invalid"),
            (.multipleRows, "space_core_details_multiple_rows"),
            (.visibleCountMismatch, "space_core_details_visible_count_mismatch"),
            (.invalidSnapshotAsOf, "space_core_details_as_of_invalid"),
            (.invalidCompleteness, "space_core_details_completeness_invalid"),
            (.requestFingerprintMismatch, "space_core_details_request_fingerprint_mismatch"),
            (.queryFingerprintMismatch, "space_core_details_query_fingerprint_mismatch"),
            (.updateRequestMismatch, "space_core_details_update_request_mismatch"),
            (.invalidWaitingState, "space_core_details_waiting_state_invalid"),
            (.unavailableCachedEvidence, "space_core_details_unavailable_cache_invalid"),
            (.localReadFailed, "space_core_details_local_read_failed"),
            (.invalidEncodedRequest, "space_core_details_request_encoding_invalid"),
            (.invalidEncodedSpace, "space_core_details_space_encoding_invalid"),
            (.invalidEncodedLocalSnapshot, "space_core_details_snapshot_encoding_invalid"),
            (.invalidEncodedUpdate, "space_core_details_update_encoding_invalid")
        ]
        let codes = diagnostics.map { failure, expectedCode in
            #expect(failure.diagnosticCode == expectedCode)
            #expect(expectedCode.utf8.count <= 80)
            #expect(!expectedCode.contains("firebase"))
            #expect(!expectedCode.contains("supabase"))
            return expectedCode
        }
        #expect(Set(codes).count == diagnostics.count)
    }

    @Test("The query port streams only exact request updates and propagates failure and cancellation")
    func exactPortFailureAndCancellation() async throws {
        let request = try Self.request()
        let local = try Self.local([try Self.space()])
        let exactUpdates = try [
            SpaceCoreDetailsUpdate(request: request, state: .waiting(.loading)),
            SpaceCoreDetailsUpdate(request: request, state: .snapshot(local))
        ]
        let exact = await Self.collect(FixturePort(updates: exactUpdates), request)
        #expect(exact.updates == exactUpdates && exact.failure == nil)

        let otherRequest = try Self.request(space: "other-space")
        let rebound = await Self.collectWithoutConsumerValidation(
            FixturePort(updates: exactUpdates),
            otherRequest
        )
        #expect(rebound.updates.isEmpty && rebound.failure == .updateRequestMismatch)
        let failed = await Self.collect(FailingPort(), request)
        #expect(failed.updates.isEmpty && failed.failure == .localReadFailed)

        let probe = SpaceCoreCancellationProbe()
        let cancellable = CancellablePort(updates: exactUpdates, probe: probe)
        let consumer = Task { () -> [SpaceCoreDetailsUpdate] in
            var updates: [SpaceCoreDetailsUpdate] = []
            do {
                for try await update in cancellable.watchSpaceCoreDetails(request) {
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

    @Test("Encoded contracts contain only the frozen provider-free boundary")
    func encodedBoundary() throws {
        let request = try Self.request()
        let snapshot = try Self.local([try Self.space()])
        let update = try SpaceCoreDetailsUpdate(request: request, state: .snapshot(snapshot))
        let bytes = try OperationContractCodec.encode(update)
        let root = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        #expect(Set(root.keys) == ["request", "state"])
        let encodedRequest = try #require(root["request"] as? [String: Any])
        #expect(Set(encodedRequest.keys) == ["accountId", "spaceId", "queryFingerprint"])
        let text = String(decoding: bytes, as: UTF8.self).lowercased()
        for forbidden in [
            "firebase", "firestore", "supabase", "powersync", "url", "attachment",
            "image", "pdf", "marker", "itemid", "assignment", "review", "template",
            "transaction", "invoice", "purchase", "occurrence", "budget",
            "accounting", "percentage", "authorized", "permission", "path", "sql"
        ] {
            #expect(!text.contains(forbidden))
        }
        #expect(!text.contains("\"iscomplete\":"))
        #expect(try OperationContractCodec.encode(
            OperationContractCodec.decode(SpaceCoreDetailsUpdate.self, from: bytes)
        ) == bytes)
    }

    private static let t0 = Date(timeIntervalSince1970: 1_802_100_000)
    private static let t1 = Date(timeIntervalSince1970: 1_802_100_001)
    private static let t2 = Date(timeIntervalSince1970: 1_802_100_002)
    private static let t3 = Date(timeIntervalSince1970: 1_802_100_003)
    private static let t4 = Date(timeIntervalSince1970: 1_802_100_004)
    private static let t5 = Date(timeIntervalSince1970: 1_802_100_005)
    private static let t6 = Date(timeIntervalSince1970: 1_802_100_006)
    private static let t7 = Date(timeIntervalSince1970: 1_802_100_007)

    private struct RestartFixture: Codable, Equatable, Sendable {
        let updates: [SpaceCoreDetailsUpdate]
    }

    private static func request(
        account: String = "space-account",
        space: String = "space-one"
    ) throws -> SpaceCoreDetailsRequest {
        try SpaceCoreDetailsRequest(
            accountId: AccountID(validating: account),
            spaceId: SpaceID(validating: space)
        )
    }

    private static func item(
        _ id: SpaceChecklistItemID,
        text: String,
        checked: Bool,
        order: UInt32
    ) throws -> SpaceChecklistItemState {
        SpaceChecklistItemState(
            id: id,
            text: try SpaceChecklistItemText(validating: text),
            isChecked: checked,
            presentationOrder: order
        )
    }

    private static func item(
        _ id: String,
        text: String,
        checked: Bool,
        order: UInt32
    ) throws -> SpaceChecklistItemState {
        try item(
            SpaceChecklistItemID(validating: id),
            text: text,
            checked: checked,
            order: order
        )
    }

    private static func checklist(
        _ id: String,
        name: String? = nil,
        order: UInt32,
        items: [SpaceChecklistItemState]
    ) throws -> SpaceChecklistState {
        try SpaceChecklistState(
            id: SpaceChecklistID(validating: id),
            name: SpaceChecklistName(validating: "  \(name ?? id.capitalized)  "),
            presentationOrder: order,
            items: items
        )
    }

    private static func space(
        id: String = "space-one",
        account: String = "space-account",
        scope: SpaceCreationScope? = nil,
        name: String = "Living Room",
        notes: String? = "Operational notes",
        lifecycle: DirectoryLifecycleState = .active,
        revision: UInt64 = 9,
        createdAt: Date = t0,
        updatedAt: Date = t1,
        checklists: [SpaceChecklistState] = []
    ) throws -> SpaceCoreDetailsSnapshot {
        let resolvedScope = try scope ?? .project(ProjectID(validating: "project-one"))
        return try SpaceCoreDetailsSnapshot(
            id: SpaceID(validating: id),
            accountId: AccountID(validating: account),
            scope: resolvedScope,
            displayName: SpaceDisplayName(validating: name),
            notes: SpaceCreationNotes(notes),
            lifecycle: lifecycle,
            revision: revision,
            createdAt: createdAt,
            updatedAt: updatedAt,
            checklists: SpaceChecklistCollection(checklists: checklists)
        )
    }

    private static func local(
        _ rows: [SpaceCoreDetailsSnapshot],
        request: SpaceCoreDetailsRequest? = nil,
        visibleCount: Int? = nil,
        quality: ListSnapshotQuality = .ready,
        complete: Bool = true,
        version: String = "test",
        date: Date = t0
    ) throws -> SpaceCoreDetailsLocalSnapshot {
        let request = try request ?? Self.request()
        return try SpaceCoreDetailsLocalSnapshot(
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
    ) -> SpaceCoreDetailsFailure? {
        do { _ = try body(); return nil }
        catch let failure as SpaceCoreDetailsFailure { return failure }
        catch { return nil }
    }

    private static func decodeFailure<Value: Decodable>(
        _ type: Value.Type,
        _ bytes: Data
    ) -> SpaceCoreDetailsFailure? {
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

    private static func mutateChecklists(
        _ bytes: Data,
        _ body: (inout [[String: Any]]) -> Void
    ) throws -> Data {
        try mutateFirstRow(bytes) { row in
            var collection = row["checklists"] as! [String: Any]
            var checklists = collection["checklists"] as! [[String: Any]]
            body(&checklists)
            collection["checklists"] = checklists
            row["checklists"] = collection
        }
    }

    private static func collect<Port: SpaceCoreDetailsQuerying>(
        _ port: Port,
        _ request: SpaceCoreDetailsRequest
    ) async -> (updates: [SpaceCoreDetailsUpdate], failure: SpaceCoreDetailsFailure?) {
        var updates: [SpaceCoreDetailsUpdate] = []
        do {
            for try await update in port.watchSpaceCoreDetails(request) {
                updates.append(try update.validating(request: request))
            }
            return (updates, nil)
        } catch let failure as SpaceCoreDetailsFailure {
            return (updates, failure)
        } catch {
            return (updates, nil)
        }
    }

    private static func collectWithoutConsumerValidation<Port: SpaceCoreDetailsQuerying>(
        _ port: Port,
        _ request: SpaceCoreDetailsRequest
    ) async -> (updates: [SpaceCoreDetailsUpdate], failure: SpaceCoreDetailsFailure?) {
        var updates: [SpaceCoreDetailsUpdate] = []
        do {
            for try await update in port.watchSpaceCoreDetails(request) {
                updates.append(update)
            }
            return (updates, nil)
        } catch let failure as SpaceCoreDetailsFailure {
            return (updates, failure)
        } catch {
            return (updates, nil)
        }
    }
}

private struct FixturePort: SpaceCoreDetailsQuerying {
    let updates: [SpaceCoreDetailsUpdate]

    func watchSpaceCoreDetails(
        _ request: SpaceCoreDetailsRequest
    ) -> AsyncThrowingStream<SpaceCoreDetailsUpdate, Error> {
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

private struct FailingPort: SpaceCoreDetailsQuerying {
    func watchSpaceCoreDetails(
        _ request: SpaceCoreDetailsRequest
    ) -> AsyncThrowingStream<SpaceCoreDetailsUpdate, Error> {
        AsyncThrowingStream { $0.finish(throwing: SpaceCoreDetailsFailure.localReadFailed) }
    }
}

private struct CancellablePort: SpaceCoreDetailsQuerying {
    let updates: [SpaceCoreDetailsUpdate]
    let probe: SpaceCoreCancellationProbe

    func watchSpaceCoreDetails(
        _ request: SpaceCoreDetailsRequest
    ) -> AsyncThrowingStream<SpaceCoreDetailsUpdate, Error> {
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

private actor SpaceCoreCancellationProbe {
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
