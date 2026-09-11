import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Client Browsing Presentation Contracts")
struct ClientBrowsingPresentationTests {
    @Test("One projection atomically segments lifecycle and preserves upstream order and identity")
    func atomicLifecycleProjection() throws {
        let clients = try [
            Self.client("archived-z", name: "Same", lifecycle: .archived),
            Self.client("active-b", name: "  Same  "),
            Self.client("active-a", name: "  Same  "),
            Self.client("archived-a", name: "Archived", lifecycle: .archived)
        ]
        let source = try Self.snapshot(clients, visibleCount: 6)
        let presentation = try ClientDirectoryPresentationProjector.project(source)

        #expect(presentation.active.rows.map(\.clientId) == [clients[1].id, clients[2].id])
        #expect(presentation.archived.rows.map(\.clientId) == [clients[0].id, clients[3].id])
        #expect(presentation.active.rows.map(\.displayName.rawValue) == ["  Same  ", "  Same  "])
        #expect(presentation.active.rows[0].createdAt == clients[1].createdAt)
        #expect(presentation.active.rows[0].updatedAt == clients[1].updatedAt)
        #expect(presentation.active.localDataVersion == presentation.archived.localDataVersion)
        #expect(presentation.active.evidenceFingerprint != presentation.archived.evidenceFingerprint)
        #expect(!presentation.isSourceExhaustive)
        #expect(presentation.active.readiness == .ready)
    }

    @Test("Each segment requires ready complete source-exhaustive evidence for empty authority")
    func reciprocalEmptyAuthority() throws {
        let active = try Self.client("active")
        let archived = try Self.client("archived", lifecycle: .archived)
        let cases: [(ListSnapshotQuality, Bool, Int, Bool)] = [
            (.partial, false, 1, false),
            (.stale, false, 1, false),
            (.ready, false, 2, false),
            (.ready, true, 2, false),
            (.ready, true, 1, true)
        ]
        for (index, item) in cases.enumerated() {
            let onlyArchived = try ClientDirectoryPresentationProjector.project(Self.snapshot(
                [archived],
                visibleCount: item.2,
                complete: item.1,
                quality: item.0,
                version: "archived-\(index)"
            ))
            #expect(onlyArchived.active.rows.isEmpty)
            #expect(onlyArchived.active.isAuthoritativeEmpty == item.3)
            #expect(!onlyArchived.archived.isAuthoritativeEmpty)

            let onlyActive = try ClientDirectoryPresentationProjector.project(Self.snapshot(
                [active],
                visibleCount: item.2,
                complete: item.1,
                quality: item.0,
                version: "active-\(index)"
            ))
            #expect(onlyActive.archived.rows.isEmpty)
            #expect(onlyActive.archived.isAuthoritativeEmpty == item.3)
            #expect(!onlyActive.active.isAuthoritativeEmpty)
        }
    }

    @Test("Selection is stable-ID and current-snapshot bound with strict restart validation")
    func selectionAndTamperRefusal() throws {
        let first = try Self.client("client-a", name: "Same")
        let second = try Self.client("client-b", name: "Same")
        let archived = try Self.client("client-c", lifecycle: .archived)
        let current = try ClientDirectoryPresentationProjector.project(
            Self.snapshot([first, second, archived])
        )
        let selection = try current.active.selection(clientId: second.id)
        let request = try selection.detailRequest(validating: current.active)
        #expect(request.accountId == Self.accountId)
        #expect(request.clientId == second.id)
        #expect(selection.row.displayName.rawValue == "Same")

        let archivedSelection = try current.archived.selection(clientId: archived.id)
        let archivedRequest = try archivedSelection.detailRequest(validating: current.archived)
        #expect(archivedRequest.clientId == archived.id)

        #expect(Self.failure { try current.active.selection(clientId: archived.id) }
            == .clientNotSelectable)
        #expect(Self.failure { try current.archived.selection(clientId: second.id) }
            == .clientNotSelectable)

        let restored = try OperationContractCodec.decode(
            ClientBrowsingSelection.self,
            from: OperationContractCodec.encode(selection)
        )
        #expect(restored == selection)

        let changedName = try ClientDirectoryPresentationProjector.project(Self.snapshot(
            [first, Self.client("client-b", name: "Changed"), archived],
            version: "changed-name"
        ))
        let changedLifecycle = try ClientDirectoryPresentationProjector.project(Self.snapshot(
            [first, Self.client("client-b", name: "Same", lifecycle: .archived), archived],
            version: "changed-lifecycle"
        ))
        let changedAudit = try ClientDirectoryPresentationProjector.project(Self.snapshot(
            [first, Self.client("client-b", name: "Same", updatedAt: Self.t2), archived],
            version: "changed-audit"
        ))
        let changedOrder = try ClientDirectoryPresentationProjector.project(Self.snapshot(
            [second, first, archived],
            version: "changed-order"
        ))
        let otherAccount = try AccountID(validating: "other-account")
        let changedAccount = try ClientDirectoryPresentationProjector.project(Self.snapshot(
            [Self.client("client-b", name: "Same", account: otherAccount)],
            account: otherAccount,
            version: "changed-account"
        ))
        for changed in [
            changedName.active,
            changedLifecycle.archived,
            changedAudit.active,
            changedOrder.active,
            changedAccount.active,
            current.archived
        ] {
            #expect(Self.failure { try selection.detailRequest(validating: changed) }
                == .selectionSnapshotMismatch)
        }

        let presentationBytes = try OperationContractCodec.encode(current.active)
        let nameTamper = try Self.mutateRow(presentationBytes) { $0["displayName"] = "Other" }
        #expect(Self.decodeFailure(ClientDirectoryPresentationSnapshot.self, nameTamper)
            == .evidenceFingerprintMismatch)
        let auditTamper = try Self.mutateRow(presentationBytes) {
            $0["updatedAt"] = ($0["updatedAt"] as! NSNumber).doubleValue + 1
        }
        #expect(Self.decodeFailure(ClientDirectoryPresentationSnapshot.self, auditTamper)
            == .evidenceFingerprintMismatch)
        let orderTamper = try Self.mutate(presentationBytes) { root in
            var rows = root["rows"] as! [[String: Any]]
            rows.swapAt(0, 1)
            root["rows"] = rows
        }
        #expect(Self.decodeFailure(ClientDirectoryPresentationSnapshot.self, orderTamper)
            == .evidenceFingerprintMismatch)
        let unknown = try Self.mutate(presentationBytes) { $0["route"] = "client" }
        #expect(Self.decodeFailure(ClientDirectoryPresentationSnapshot.self, unknown)
            == .invalidEncodedPresentation)
        let unknownRow = try Self.mutateRow(presentationBytes) { $0["projects"] = [] }
        #expect(Self.decodeFailure(ClientDirectoryPresentationSnapshot.self, unknownRow)
            == .invalidEncodedRow)

        let selectionBytes = try OperationContractCodec.encode(selection)
        let rebound = try Self.mutate(selectionBytes) { root in
            var row = root["row"] as! [String: Any]
            row["clientId"] = "client-a"
            root["row"] = row
        }
        #expect(Self.decodeFailure(ClientBrowsingSelection.self, rebound)
            == .selectionFingerprintMismatch)
        let malformed = try Self.mutate(selectionBytes) { $0["selectionFingerprint"] = "bad" }
        #expect(Self.decodeFailure(ClientBrowsingSelection.self, malformed)
            == .invalidSelectionFingerprint)
    }

    @Test("Detail projection exhaustively preserves local truth and newer Client evidence")
    func detailStateMatrix() throws {
        let request = try ClientCoreDetailsRequest(
            accountId: Self.accountId,
            clientId: ClientID(validating: "client-a")
        )
        let updated = try Self.client(
            "client-a",
            name: "  New Name  ",
            lifecycle: .archived,
            createdAt: Self.t0,
            updatedAt: Self.t2
        )
        let ready = try Self.detailLocal(
            request,
            rows: [ClientCoreDetailsSnapshot(
                client: updated,
                locallyObservedRevision: ExpectedClientRevision(42)
            )],
            version: "ready"
        )
        let readyIncomplete = try Self.detailLocal(
            request,
            rows: [ClientCoreDetailsSnapshot(
                client: updated,
                locallyObservedRevision: ExpectedClientRevision(41)
            )],
            complete: false,
            version: "ready-incomplete"
        )
        let partial = try Self.detailLocal(
            request,
            rows: [ClientCoreDetailsSnapshot(
                client: updated,
                locallyObservedRevision: ExpectedClientRevision(40)
            )],
            quality: .partial,
            complete: false,
            version: "partial"
        )
        let updates = try [
            Self.update(request, .waiting(.notRequested)),
            Self.update(request, .waiting(.loading)),
            Self.update(request, .waiting(.blocked)),
            Self.update(request, .snapshot(ready)),
            Self.update(request, .snapshot(readyIncomplete)),
            Self.update(request, .snapshot(partial)),
            Self.update(request, .snapshot(Self.detailLocal(request, rows: [], complete: false, version: "empty-incomplete"))),
            Self.update(request, .snapshot(Self.detailLocal(request, rows: [], version: "absent"))),
            Self.update(request, .failed(failure: .unavailable, cached: nil)),
            Self.update(request, .failed(failure: .retryable, cached: ready)),
            Self.update(request, .failed(failure: .retryable, cached: nil)),
            Self.update(request, .failed(failure: .requiredUpdate, cached: partial)),
            Self.update(request, .failed(failure: .requiredUpdate, cached: nil))
        ]
        let expectedKinds = [
            "waiting", "waiting", "waiting", "found", "found", "found",
            "incomplete", "absence", "unavailable", "retryable-cached",
            "retryable-uncached", "update-cached", "update-uncached"
        ]
        for index in updates.indices {
            let presentation = try ClientDetailPresentationProjector.project(
                updates[index],
                validating: request
            )
            #expect(Self.kind(presentation.state) == expectedKinds[index])
        }

        let found = try ClientDetailPresentationProjector.project(
            updates[3], validating: request
        ).state.content
        #expect(found?.displayName.rawValue == "  New Name  ")
        #expect(found?.lifecycle == .archived)
        #expect(found?.createdAt == Self.t0)
        #expect(found?.updatedAt == Self.t2)
        #expect(found?.locallyObservedRevision == ExpectedClientRevision(42))
        #expect(found?.observedRevisionIsFromCompleteReadySnapshot == true)
        #expect(found?.readiness == .ready)

        let incompleteFound = try ClientDetailPresentationProjector.project(
            updates[4], validating: request
        ).state.content
        #expect(incompleteFound?.observedRevisionIsFromCompleteReadySnapshot == false)
        #expect(incompleteFound?.readiness == .ready)

        let cached = try ClientDetailPresentationProjector.project(
            updates[9], validating: request
        ).state.content
        #expect(cached?.readiness == .stale)
        #expect(cached?.sourceQuality == .ready)
        #expect(cached?.observedRevisionIsFromCompleteReadySnapshot == true)

        let wrong = try ClientCoreDetailsRequest(
            accountId: Self.accountId,
            clientId: ClientID(validating: "client-b")
        )
        #expect(Self.failure {
            try ClientDetailPresentationProjector.project(updates[0], validating: wrong)
        } == .updateRequestMismatch)
    }

    private static let accountId = try! AccountID(validating: "client-account")
    private static let t0 = Date(timeIntervalSince1970: 1_802_400_000)
    private static let t1 = Date(timeIntervalSince1970: 1_802_400_001)
    private static let t2 = Date(timeIntervalSince1970: 1_802_400_002)

    private static func client(
        _ id: String,
        name: String = "Client",
        lifecycle: DirectoryLifecycleState = .active,
        createdAt: Date = t0,
        updatedAt: Date = t1,
        account: AccountID = accountId
    ) throws -> ClientSummary {
        try ClientSummary(
            id: ClientID(validating: id),
            accountId: account,
            displayName: ClientDisplayName(validating: name),
            lifecycle: lifecycle,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static func snapshot(
        _ rows: [ClientSummary],
        account: AccountID = accountId,
        visibleCount: Int? = nil,
        complete: Bool = true,
        quality: ListSnapshotQuality = .ready,
        version: String = "client-directory-v1"
    ) throws -> ClientListSnapshot {
        try ClientListSnapshot(
            accountId: account,
            local: ListLocalSnapshot(
                queryFingerprint: ListQueryFingerprint(
                    validating: String(repeating: "c", count: 64)
                ),
                rows: rows,
                visibleRowCountBeforeFiltering: visibleCount ?? rows.count,
                isCompleteForQuery: complete,
                quality: quality,
                localDataVersion: LocalDataVersion(validating: version),
                asOf: t2
            )
        )
    }

    private static func detailLocal(
        _ request: ClientCoreDetailsRequest,
        rows: [ClientCoreDetailsSnapshot],
        quality: ListSnapshotQuality = .ready,
        complete: Bool = true,
        version: String
    ) throws -> ClientCoreDetailsLocalSnapshot {
        try ClientCoreDetailsLocalSnapshot(
            request: request,
            rows: rows,
            visibleRowCountBeforeFiltering: rows.count,
            isCompleteForQuery: complete,
            quality: quality,
            localDataVersion: LocalDataVersion(validating: version),
            asOf: t2
        )
    }

    private static func update(
        _ request: ClientCoreDetailsRequest,
        _ state: ClientCoreDetailsUpdateState
    ) throws -> ClientCoreDetailsUpdate {
        try ClientCoreDetailsUpdate(request: request, state: state)
    }

    private static func kind(_ state: ClientDetailPresentationState) -> String {
        switch state {
        case .waiting: "waiting"
        case .found: "found"
        case .incomplete: "incomplete"
        case .authoritativeAbsence: "absence"
        case .unavailable: "unavailable"
        case .retryable(cached: .some): "retryable-cached"
        case .retryable(cached: .none): "retryable-uncached"
        case .requiredUpdate(cached: .some): "update-cached"
        case .requiredUpdate(cached: .none): "update-uncached"
        }
    }

    private static func failure<Value>(
        _ body: () throws -> Value
    ) -> ClientBrowsingPresentationFailure? {
        do { _ = try body(); return nil }
        catch let failure as ClientBrowsingPresentationFailure { return failure }
        catch { return nil }
    }

    private static func decodeFailure<Value: Decodable>(
        _ type: Value.Type,
        _ bytes: Data
    ) -> ClientBrowsingPresentationFailure? {
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

    private static func mutateRow(
        _ bytes: Data,
        _ body: (inout [String: Any]) -> Void
    ) throws -> Data {
        try mutate(bytes) { root in
            var rows = root["rows"] as! [[String: Any]]
            body(&rows[0])
            root["rows"] = rows
        }
    }
}
