import Foundation
import LedgerTargetCore
import PowerSync
import Testing
@testable import LedgerTargetPowerSync

@Suite("Source return durable queue", .serialized)
struct InventorySourceReturnPowerSyncStoreTests {
    let account = try! AccountID(validating: "account")
    let principal = try! PrincipalID(validating: "member")
    struct Injected: Error {}
    @Test func sharedMCPWireFixture() throws {
        struct Fixture: Decodable {
            struct Input: Decodable {
                let operationUUID: UUID
                let clientCreatedAtMilliseconds: Int64
                let payload: ReturnInventoryItemsToSourcePayload
            }
            let accountId: AccountID, principalId: PrincipalID
            let input: Input
            let operationId: String, fingerprint: String
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: root.appendingPathComponent("LedgerTargetMCP/tests/fixtures/inventory-source-return.json")))
        let command = try ReturnInventoryItemsToSourceCommand(operationId: InventorySourceReturnOperationIdentity.make(
            accountId: fixture.accountId, uuid: fixture.input.operationUUID), accountId: fixture.accountId,
            actorPrincipalId: fixture.principalId, capturedAt: Date(timeIntervalSince1970: Double(fixture.input.clientCreatedAtMilliseconds)/1000),
            payload: fixture.input.payload)
        #expect(command.envelope.operationId.rawValue == fixture.operationId)
        #expect(try InventorySourceReturnUploadRequest(command).fingerprint == fixture.fingerprint)
    }
    struct Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-source-return-\(UUID().uuidString)")
        init() throws { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        func open() throws -> any PowerSyncDatabaseProtocol {
            try LedgerPowerSyncDatabaseFactory.open(absolutePath: directory.appendingPathComponent("ledger.sqlite").path,
                encryptionKey: LedgerPowerSyncEncryptionKey(hexadecimal: String(repeating: "3a", count: 32)))
        }
        func remove() { try? FileManager.default.removeItem(at: directory) }
    }
    func store(_ db: any PowerSyncDatabaseProtocol, fence: LedgerWorkspaceAccessFence = .init(), fail: Bool = false) -> InventorySourceReturnPowerSyncStore {
        .init(database: db, accountId: account, principalId: principal, accessFence: fence,
            now: { Date(timeIntervalSince1970: 1000) }, afterOperationWrite: { if fail { throw Injected() } })
    }
    func seed(_ db: any PowerSyncDatabaseProtocol) async throws {
        try await db.execute(sql: "INSERT INTO spike_account_memberships(id,account_id,principal_id,state,financial_access) VALUES('member','account','member','active','full')", parameters: nil)
        try await db.execute(sql: "INSERT INTO spike_clients(id,account_id,display_name,lifecycle,revision,created_at_ms,updated_at_ms) VALUES('client','account','Client','active',1,1,1)", parameters: nil)
        try await db.execute(sql: "INSERT INTO spike_projects(id,account_id,client_id,display_name,lifecycle,revision) VALUES('project','account','client','Source','active',1)", parameters: nil)
        try await db.execute(sql: "INSERT INTO spike_budget_categories(id,account_id,visibility_class) VALUES('category','account','ordinary')", parameters: nil)
        try await db.execute(sql: "INSERT INTO spike_item_placements(id,account_id,item_id,scope_kind) VALUES('old','account','item','business_inventory')", parameters: nil)
        try await db.execute(sql: "INSERT INTO inventory_source_entries(id,account_id,item_id,inventory_placement_id,source_project_id,source_category_id,amount_minor_units,currency) VALUES('entry','account','item','old','project','category','9007199254740993','USD')", parameters: nil)
        try await db.execute(sql: "INSERT INTO ps_stream_subscriptions(stream_name,active,is_default,local_params,last_synced_at) VALUES('physical_account_items',1,0,?,1000000)", parameters: [#"{"account_id":"account"}"#])
        while let pending = try await db.getNextCrudTransaction() { try await pending.complete() }
    }
    func command(uuid: UUID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!) throws -> ReturnInventoryItemsToSourceCommand {
        try .init(operationId: InventorySourceReturnOperationIdentity.make(accountId: account, uuid: uuid),
            accountId: account, actorPrincipalId: principal, capturedAt: Date(timeIntervalSince1970: 1000),
            payload: .init(projectId: .init(validating: "project"), items: [.init(itemId: .init(validating: "item"),
                placementId: .init(validating: "old"), inventoryEntryId: .init(validating: "entry"),
                projectPlacementId: .init(validating: "new"), occurrenceId: .init(validating: "charge"))]))
    }
    struct UnusedClient: ClientCreationCommandApplying {
        func apply(_ request: ClientCreationUploadRequest) async throws -> ClientCreationServerResult { throw Injected() }
    }
    struct Applier: InventorySourceReturnCommandApplying {
        var fails = false
        var rejected = false
        var wrongHash = false
        var removes: LedgerWorkspaceAccessFence?
        func apply(_ command: ReturnInventoryItemsToSourceCommand) async throws -> InventorySourceReturnServerResult {
            if fails { throw Injected() }
            removes?.markRemoved()
            let e = command.envelope, wire = try InventorySourceReturnUploadRequest(command)
            var values: [String: Any] = ["operation_id":e.operationId.rawValue,"account_id":e.accountId.rawValue,
                "actor_principal_id":e.actorPrincipalId.rawValue,"subject_id":e.payload.projectId.rawValue,
                "command_type":"return_inventory_to_source","contract_version":"return-inventory-to-source-v1",
                "command_fingerprint":wrongHash ? "wrong" : wire.fingerprint,"envelope_sha256":wire.fingerprint,
                "phase":rejected ? "rejected" : "applied","client_created_at_ms":1000000,
                "server_received_at_ms":2000000,"completed_at_ms":2000001]
            if rejected { values["error_code"] = "source_return_placement_stale" }
            else { values["result_code"] = "inventory_items_returned_to_source" }
            return try JSONDecoder().decode(InventorySourceReturnServerResult.self, from: JSONSerialization.data(withJSONObject: values))
        }
    }
    func connector(_ applier: Applier, fence: LedgerWorkspaceAccessFence = .init()) -> LedgerPowerSyncUploadConnector {
        .init(accessFence: fence, credentialProvider: { nil }, clientCreationApplier: UnusedClient(), sourceReturnApplier: applier)
    }
    @Test func restartRetainsExactIntentAndUploadRetry() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open(); try await seed(db)
        let command = try command(), owner = store(db)
        let review = try await owner.review(itemIds: [try .init(validating: "item")])
        #expect(review.items[0].sourceAmount.minorUnits == 9007199254740993)
        #expect(try await owner.submit(command).localState == .queued)
        #expect(try await owner.submit(command).localState == .queued)
        await #expect(throws: InventorySourceReturnPowerSyncStore.Failure.alreadyAccepted) {
            try await owner.submit(self.command(uuid: UUID()))
        }
        await #expect(throws: Injected.self) { try await connector(.init(fails: true)).uploadData(database: db) }
        #expect(try await owner.status(command.envelope.operationId)?.state.phase == .applying)
        try await db.close()
        let reopened = try fixture.open(), restored = store(reopened)
        #expect(try await restored.submit(command).localState == .applying)
        try await connector(.init()).uploadData(database: reopened)
        #expect(try await reopened.getNextCrudTransaction() == nil)
        #expect(try await restored.status(command.envelope.operationId)?.state.phase == .applied)
        #expect(try await reopened.get("SELECT count(*) FROM spike_item_placements WHERE id='old' AND ended_at IS NULL") { try $0.getInt(index: 0) } == 1)
        // Receipt is not readback; preserve source reservation until canonical sync.
        await #expect(throws: InventorySourceReturnPowerSyncStore.Failure.alreadyAccepted) {
            try await restored.submit(self.command(uuid: UUID()))
        }
        try await reopened.execute(sql: "UPDATE spike_item_placements SET ended_at='2026-01-01' WHERE id='old'", parameters: nil)
        await #expect(throws: InventorySourceReturnPowerSyncStore.Failure.unavailable) {
            try await restored.review(itemIds: [try .init(validating: "item")])
        }
        try await reopened.close()
    }
    @Test func atomicQueueFailureAndMembershipLoss() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open(); try await seed(db)
        await #expect(throws: Injected.self) { try await store(db, fail: true).submit(command()) }
        #expect(try await db.get("SELECT count(*) FROM spike_local_operations") { try $0.getInt(index: 0) } == 0)
        #expect(try await db.getNextCrudTransaction() == nil)
        try await db.execute(sql: "UPDATE spike_account_memberships SET state='removed'", parameters: nil)
        await #expect(throws: CategoryManagementFailure.categoryUnavailable) { try await store(db).submit(command()) }
        try await db.close()
    }
    @Test(arguments: [false,true]) func validTerminalAndMismatchedReceipt(rejected: Bool) async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open(); try await seed(db)
        let command = try command(), owner = store(db)
        _ = try await owner.submit(command)
        await #expect(throws: InventorySourceReturnServerResult.Failure.receiptMismatch) {
            try await connector(.init(wrongHash: true)).uploadData(database: db)
        }
        #expect(try await db.getNextCrudTransaction() != nil)
        try await connector(.init(rejected: rejected)).uploadData(database: db)
        #expect(try await owner.status(command.envelope.operationId)?.state.phase == (rejected ? .rejected : .applied))
        #expect(try await owner.submit(command).localState == (rejected ? .rejected : .applied))
        try await db.close()
    }
    @Test func removedWorkspaceCannotAcknowledgeLateUpload() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open(); try await seed(db)
        _ = try await store(db).submit(command())
        let fence = LedgerWorkspaceAccessFence()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            try await connector(.init(removes: fence), fence: fence).uploadData(database: db)
        }
        #expect(try await db.getNextCrudTransaction() != nil)
        try await db.close()
    }
    @Test func missingReturnEvidenceNeverChangesIndependentSaleAdmission() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open(); try await seed(db)
        try await db.execute(sql: "INSERT INTO spike_items(id,account_id) VALUES('item','account')", parameters: nil)
        try await db.execute(sql: "INSERT INTO item_acquisition_reviews(id,account_id,state) VALUES('item','account','absent')", parameters: nil)
        try await db.execute(sql: "DELETE FROM inventory_source_entries", parameters: nil)
        await #expect(throws: InventorySourceReturnPowerSyncStore.Failure.unavailable) {
            try await store(db).review(itemIds: [try .init(validating: "item")])
        }
        let sale = InventorySalePowerSyncStore(database: db, accountId: account, principalId: principal, accessFence: .init())
        #expect(try await sale.review(itemIds: [try .init(validating: "item")]).items.count == 1)
        try await db.close()
    }
}
