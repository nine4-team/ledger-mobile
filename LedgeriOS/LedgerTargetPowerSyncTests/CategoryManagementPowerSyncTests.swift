import Foundation
import LedgerTargetCore
import PowerSync
import Testing
@testable import LedgerTargetPowerSync

@Suite("Category management durable acceptance", .serialized)
struct CategoryManagementPowerSyncTests {
    private static let account = try! AccountID(validating: "category-account")
    private static let principal = try! PrincipalID(validating: "category-member")
    private static let time = Date(timeIntervalSince1970: 1_800_000_000)

    @Test(.timeLimit(.minutes(1)))
    func exactCategoryDownloadProofSurvivesOfflineReopen() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let seedDatabase = try fixture.open()
        try await seed(seedDatabase)
        #expect(!BudgetCategorySyncCompleteness.isComplete(seedDatabase.currentStatus))

        // Persist the metadata that the pinned SDK writes after downloading a
        // stream. No network connection or injected completeness closure is used.
        _ = try await seedDatabase.execute(sql: """
            INSERT INTO ps_stream_subscriptions
                (stream_name, active, is_default, local_params, last_synced_at)
            VALUES ('another_stream', 1, 1, 'null', 1000000),
                   ('spike_projects', 1, 1, 'null', NULL)
            """, parameters: nil)
        try await seedDatabase.close()
        // Direct fixture SQL does not emit live server status events. Reopen
        // through the SDK's real offline-status initialization instead.
        let incomplete = try fixture.open()
        #expect(try await count("spike_account_memberships", incomplete) == 1)
        #expect(incomplete.currentStatus.syncStreams?.count == 2)
        #expect(!BudgetCategorySyncCompleteness.isComplete(incomplete.currentStatus))
        let incompleteWriter = CategoryManagementPowerSyncStore(database: incomplete, accountId: Self.account,
            principalId: Self.principal, accessFence: LedgerWorkspaceAccessFence(),
            isDirectoryComplete: { BudgetCategorySyncCompleteness.isComplete(incomplete.currentStatus) })
        await #expect(throws: CategoryManagementFailure.incompleteDirectory) {
            try await incompleteWriter.submit(create())
        }
        _ = try await incomplete.execute(sql: """
            UPDATE ps_stream_subscriptions SET last_synced_at=1000000
            WHERE stream_name='spike_projects'
            """, parameters: nil)
        await incompleteWriter.cancelAndDrainWatches()
        try await incomplete.close()
        let db = try fixture.open()
        #expect(try await count("spike_account_memberships", db) == 1)
        try #require(BudgetCategorySyncCompleteness.isComplete(db.currentStatus))
        #expect(!db.currentStatus.connected)
        let writer = CategoryManagementPowerSyncStore(database: db, accountId: Self.account,
            principalId: Self.principal, accessFence: LedgerWorkspaceAccessFence(),
            isDirectoryComplete: { BudgetCategorySyncCompleteness.isComplete(db.currentStatus) })
        let original = try create()
        _ = try await writer.submit(original)
        await writer.cancelAndDrainWatches()
        try await db.close()

        let reopened = try fixture.open()
        #expect(try await count("spike_account_memberships", reopened) == 1)
        try #require(BudgetCategorySyncCompleteness.isComplete(reopened.currentStatus))
        #expect(!reopened.currentStatus.connected)
        let query = BudgetCategoryReferencePowerSyncQuery(database: reopened,
            principalId: Self.principal, accountId: Self.account)
        var updates = query.watchBudgetCategories(accountId: Self.account).makeAsyncIterator()
        let retained = try #require(try await updates.next())
        #expect(retained.local.isCompleteForQuery)
        #expect(retained.local.rows.first?.name.rawValue == "Art & Décor")
        let reopenedWriter = CategoryManagementPowerSyncStore(database: reopened,
            accountId: Self.account, principalId: Self.principal, accessFence: LedgerWorkspaceAccessFence(),
            isDirectoryComplete: { BudgetCategorySyncCompleteness.isComplete(reopened.currentStatus) })
        let spelling = "Art & De\u{0301}cor"
        _ = try await reopenedWriter.submit(command(.init(action: .edit,
            categoryId: BudgetCategoryID(validating: "new-category"), expectedRevision: 1,
            name: BudgetCategoryName(validating: spelling),
            kind: .general, excludesFromOverallBudget: false)))
        #expect(try await count("ps_crud", reopened) == 2)
        let revised = try #require(try await projected(reopened).first)
        #expect(revised.revision == 2)
        #expect(Array(revised.name.rawValue.utf8) == Array(spelling.utf8))
        _ = try await reopenedWriter.submit(command(.init(action: .edit,
            categoryId: revised.id, expectedRevision: revised.revision,
            name: BudgetCategoryName(validating: "Edited after offline reopen"),
            kind: .general, excludesFromOverallBudget: false)))
        #expect(try await count("ps_crud", reopened) == 3)
        #expect(try await projected(reopened).first?.revision == 3)
        await query.cancelAndDrainWatches()
        await reopenedWriter.cancelAndDrainWatches()
        try await reopened.close(deleteDatabase: true)
    }

    @Test(.timeLimit(.minutes(1)))
    func statusWatchReportsLateResultsSurvivesRestartAndStopsOnRemoval() async throws {
        for rejected in [false, true] {
            let fixture = try Fixture()
            defer { fixture.remove() }
            let db = try fixture.open()
            try await seed(db)
            let writer = store(db)
            let command = try create()
            _ = try await writer.submit(command)
            var updates = writer.watchOperations().makeAsyncIterator()
            let initial = try #require(try await updates.next())
            #expect(initial.count == 1)
            #expect(initial.first?.operationId == command.envelope.operationId)
            #expect(initial.first?.state.phase == .queued)
            try await connector(applier: Applier(rejected: rejected)).uploadData(database: db)
            let terminal: OperationPhase = rejected ? .rejected : .applied
            var observedTerminal = false
            while let rows = try await updates.next() {
                if rows.first?.state.phase == terminal { observedTerminal = true; break }
            }
            #expect(observedTerminal)
            await writer.cancelAndDrainWatches()
            try await db.close()

            let reopened = try fixture.open()
            let reopenedWriter = store(reopened)
            var retained = reopenedWriter.watchOperations().makeAsyncIterator()
            let restored = try #require(try await retained.next())
            #expect(restored.first?.state.phase == terminal)
            if case .rejected(let failure) = restored.first?.state {
                #expect(failure.error.code.rawValue == "category_name_unavailable")
            }
            _ = try await reopened.execute(sql: "UPDATE spike_account_memberships SET state = 'removed'", parameters: nil)
            await #expect(throws: CategoryManagementFailure.categoryUnavailable) {
                while try await retained.next() != nil { }
            }
            await reopenedWriter.cancelAndDrainWatches()
            var closed = reopenedWriter.watchOperations().makeAsyncIterator()
            #expect(try await closed.next() == nil)
            try await reopened.close(deleteDatabase: true)
        }
    }

    @Test func acceptanceIsEncryptedAtomicAndReplayableAfterRestart() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let db = try fixture.open()
        try await seed(db)
        let command = try create()
        let receipt = try await store(db).submit(command)
        #expect(receipt.localState == .queued)
        #expect(try await count("spike_local_operations", db) == 1)
        #expect(try await count("ps_crud", db) == 1)
        #expect(try await count("spike_budget_categories", db) == 0)
        #expect(try await projected(db).first?.name.rawValue == "Art & Décor")
        #expect(try await store(db).submit(command) == receipt)
        #expect(try await count("ps_crud", db) == 1)
        try await db.close()
        let bytes = try Data(contentsOf: fixture.file)
        #expect(!String(decoding: bytes, as: UTF8.self).contains("Art & Décor"))
        let reopened = try fixture.open()
        #expect(try await store(reopened).submit(command) == receipt)
        #expect(try await projected(reopened).first?.id.rawValue == "new-category")
        #expect(try await count("ps_crud", reopened) == 1)
        try await reopened.close(deleteDatabase: true)
    }

    @Test func chainedOfflineEditsUsePendingDefinitionWithoutOverwritingDownloadedData() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let db = try fixture.open()
        try await seed(db)
        _ = try await store(db).submit(create())
        let edit = try command(.init(action: .edit, categoryId: BudgetCategoryID(validating: "new-category"),
            expectedRevision: 1, name: BudgetCategoryName(validating: "Updated offline"),
            kind: .itemized, excludesFromOverallBudget: true))
        _ = try await store(db).submit(edit)
        let rows = try await projected(db)
        #expect(rows.count == 1)
        #expect(rows.first?.name.rawValue == "Updated offline")
        #expect(rows.first?.kind == .itemized)
        #expect(rows.first?.revision == 2)
        #expect(try await count("spike_budget_categories", db) == 0)
        #expect(try await count("ps_crud", db) == 2)
        let timestamps = try await db.getAll("SELECT accepted_at_ms FROM spike_local_operations ORDER BY accepted_at_ms") {
            try $0.getInt64(name: "accepted_at_ms")
        }
        #expect(timestamps[1] > timestamps[0])
        try await db.close(deleteDatabase: true)
    }

    @Test func failureAtAnyAcceptanceBoundaryRollsBackBothLedgerAndUpload() async throws {
        for point in [CategoryManagementPowerSyncStore.Checkpoint.operationWritten, .commandWritten, .beforeCommit] {
            let fixture = try Fixture()
            defer { fixture.remove() }
            let db = try fixture.open()
            try await seed(db)
            let failing = CategoryManagementPowerSyncStore(database: db, accountId: Self.account,
                principalId: Self.principal, accessFence: LedgerWorkspaceAccessFence(),
                isDirectoryComplete: { true }, now: { Self.time }, checkpoint: {
                    if $0 == point { throw InjectedFailure() }
                })
            await #expect(throws: InjectedFailure.self) { try await failing.submit(create()) }
            #expect(try await count("spike_local_operations", db) == 0)
            #expect(try await count("ps_crud", db) == 0)
            try await db.close(deleteDatabase: true)
        }
    }

    @Test func scopeCompletenessAndRevocationAreCheckedBeforeAcceptance() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let db = try fixture.open()
        try await seed(db)
        let incomplete = CategoryManagementPowerSyncStore(database: db, accountId: Self.account,
            principalId: Self.principal, accessFence: LedgerWorkspaceAccessFence(),
            isDirectoryComplete: { false })
        await #expect(throws: CategoryManagementFailure.incompleteDirectory) { try await incomplete.submit(create()) }
        let foreign = try CategoryManagementCommand(
            operationId: CategoryManagementOperationIdentity.make(accountId: Self.account, uuid: UUID()),
            accountId: AccountID(validating: "foreign"), actorPrincipalId: Self.principal,
            capturedAt: Self.time, payload: create().envelope.payload)
        await #expect(throws: CategoryManagementFailure.wrongAccount) { try await store(db).submit(foreign) }
        let fence = LedgerWorkspaceAccessFence()
        fence.markRemoved()
        let removed = CategoryManagementPowerSyncStore(database: db, accountId: Self.account,
            principalId: Self.principal, accessFence: fence, isDirectoryComplete: { true })
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) { try await removed.submit(create()) }
        #expect(try await count("spike_local_operations", db) == 0)
        _ = try await db.execute(sql: "UPDATE spike_account_memberships SET state = 'removed'", parameters: nil)
        await #expect(throws: CategoryManagementFailure.categoryUnavailable) { try await store(db).submit(create()) }
        try await db.close(deleteDatabase: true)
    }

    @Test func changedPayloadCannotReuseOperationIdentity() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let db = try fixture.open()
        try await seed(db)
        let original = try create()
        _ = try await store(db).submit(original)
        let changed = try CategoryManagementCommand(operationId: original.envelope.operationId,
            accountId: Self.account, actorPrincipalId: Self.principal, capturedAt: Self.time,
            payload: .init(action: .create, categoryId: BudgetCategoryID(validating: "changed-id"),
                name: BudgetCategoryName(validating: "Changed"), kind: .general, excludesFromOverallBudget: false))
        await #expect(throws: OperationContractFailure.payloadMismatch(original.envelope.operationId)) { try await store(db).submit(changed) }
        #expect(try await count("spike_local_operations", db) == 1)
        #expect(try await count("ps_crud", db) == 1)
        try await db.close(deleteDatabase: true)
    }

    @Test func successfulUploadRetainsProjectionUntilReadbackAndCanReplayTerminalReceipt() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let db = try fixture.open()
        try await seed(db)
        let command = try create()
        _ = try await store(db).submit(command)
        try await connector(applier: Applier()).uploadData(database: db)
        #expect(try await count("ps_crud", db) == 0)
        #expect(try await store(db).submit(command).localState == .applied)
        #expect(try await projected(db).first?.name.rawValue == "Art & Décor")
        // Later authoritative readback wins, including a subsequent server edit.
        _ = try await db.execute(sql: """
            INSERT INTO spike_budget_categories(id,account_id,display_name,kind,lifecycle,is_system,
                excludes_from_overall_budget,presentation_order,revision)
            VALUES ('new-category',?,'Later authoritative name','general','active',0,0,11,2)
            """, parameters: [Self.account.rawValue])
        #expect(try await projected(db).first?.name.rawValue == "Later authoritative name")
        #expect(try await projected(db).first?.presentationOrder == 11)
        try await db.close(deleteDatabase: true)
    }

    @Test func offlineCreationCanBeEditedWithoutDownloadedBaseline() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let db = try fixture.open()
        try await seed(db)
        let original = try command(create().envelope.payload,
            uuid: UUID(uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff")!)
        _ = try await store(db).submit(original)
        let edit = try command(.init(action: .edit, categoryId: original.envelope.payload.categoryId,
            expectedRevision: 1, name: BudgetCategoryName(validating: "Updated offline"),
            kind: .itemized, excludesFromOverallBudget: false),
            uuid: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
        _ = try await store(db).submit(edit)
        #expect(try await projected(db).first?.name.rawValue == "Updated offline")
        #expect(try await projected(db).first?.revision == 2)
        #expect(try await count("spike_local_operations", db) == 2)
        try await db.close(deleteDatabase: true)
    }

    @Test(.timeLimit(.minutes(1)))
    func replicatedCreationDoesNotReviveWithdrawnCategoryAndNotifiesReader() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let db = try fixture.open()
        try await seed(db)
        let command = try create()
        _ = try await store(db).submit(command)
        try await connector(applier: Applier()).uploadData(database: db)
        let query = BudgetCategoryReferencePowerSyncQuery(database: db, principalId: Self.principal,
            accountId: Self.account, completenessObservation: { _ in AsyncStream { $0.yield(true); $0.finish() } })
        var iterator = query.watchBudgetCategories(accountId: Self.account).makeAsyncIterator()
        #expect(try await iterator.next()?.local.rows.first?.id == command.envelope.payload.categoryId)
        let result = try await Applier().apply(command)
        let json = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        let columns = ["account_id", "actor_principal_id", "command_type", "contract_version",
            "command_fingerprint", "envelope_sha256", "request_sha256", "subject_id", "phase",
            "result_code", "error_code", "client_created_at_ms", "server_received_at_ms", "completed_at_ms"]
        let values = columns.map { "json_extract(?, '$.\($0)')" }.joined(separator: ",")
        _ = try await db.execute(sql: "INSERT INTO spike_operation_results(id,\(columns.joined(separator: ","))) VALUES(?,\(values))",
            parameters: [result.operation_id] + columns.map { _ in json })
        // A result alone cannot authorize a missing category. Reader must also
        // react when only the operation-results table changes.
        var snapshot = try await iterator.next()
        while snapshot?.local.rows.isEmpty == false { snapshot = try await iterator.next() }
        #expect(snapshot?.local.rows.isEmpty == true)
        _ = try await db.execute(sql: """
            INSERT INTO spike_budget_categories(id,account_id,display_name,kind,lifecycle,is_system,
                excludes_from_overall_budget,presentation_order,revision)
            VALUES ('new-category',?,'Current General name','general','active',0,0,0,2)
            """, parameters: [Self.account.rawValue])
        #expect(try await projected(db).first?.name.rawValue == "Current General name")
        _ = try await db.execute(sql: "DELETE FROM spike_budget_categories WHERE id='new-category'", parameters: nil)
        #expect(try await projected(db).isEmpty)
        #expect(try await count("spike_local_operations", db) == 1)
        await query.cancelAndDrainWatches()
        try await db.close()
        let reopened = try fixture.open()
        #expect(try await projected(reopened).isEmpty)
        #expect(try await count("spike_local_operations", reopened) == 1)
        try await reopened.close(deleteDatabase: true)
    }

    @Test func rejectionRemovesOptimisticEffectButRetainsCommandAndRetryReceipt() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let db = try fixture.open()
        try await seed(db)
        let command = try create()
        _ = try await store(db).submit(command)
        try await connector(applier: Applier(rejected: true)).uploadData(database: db)
        #expect(try await projected(db).isEmpty)
        #expect(try await count("ps_crud", db) == 0)
        #expect(try await store(db).submit(command).localState == .rejected)
        let retained = try await db.get("SELECT command_envelope_json FROM spike_local_operations") {
            try $0.getString(name: "command_envelope_json")
        }
        #expect(retained.contains("Art & Décor"))
        try await db.close(deleteDatabase: true)
    }

    @Test func transportFailureOrLearnedRemovalKeepsUploadForAuthorizedRetry() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let db = try fixture.open()
        try await seed(db)
        let command = try create()
        _ = try await store(db).submit(command)
        await #expect(throws: InjectedFailure.self) {
            try await connector(applier: Applier(fails: true)).uploadData(database: db)
        }
        #expect(try await count("ps_crud", db) == 1)
        #expect(try await store(db).submit(command).localState == .applying)
        let fence = LedgerWorkspaceAccessFence()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            try await connector(applier: Applier(removes: fence), fence: fence).uploadData(database: db)
        }
        #expect(try await count("ps_crud", db) == 1)
        #expect(try await count("spike_local_operations", db) == 1)
        try await db.close(deleteDatabase: true)
    }

    @Test func pendingTypeEditDoesNotBypassLearnedFinancialDowngrade() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let db = try fixture.open()
        try await seed(db)
        _ = try await db.execute(sql: "UPDATE spike_account_memberships SET financial_access='full'", parameters: nil)
        _ = try await db.execute(sql: """
            INSERT INTO spike_budget_categories(id,account_id,display_name,kind,lifecycle,is_system,
                excludes_from_overall_budget,presentation_order,revision)
            VALUES ('fee',?,'Design Fee','fee','active',0,1,0,1)
            """, parameters: [Self.account.rawValue])
        while let pending = try await db.getNextCrudTransaction() { try await pending.complete() }
        let edit = try command(.init(action: .edit, categoryId: BudgetCategoryID(validating: "fee"),
            expectedRevision: 1, name: BudgetCategoryName(validating: "Design Fee"),
            kind: .general, excludesFromOverallBudget: true))
        _ = try await store(db).submit(edit)
        #expect(try await projected(db).first?.kind == .general)
        _ = try await db.execute(sql: "UPDATE spike_account_memberships SET financial_access='none'", parameters: nil)
        #expect(try await projected(db).isEmpty)
        // Authorized sync removes Fee rows entirely after a downgrade; it does
        // not leave a hidden Fee row for the optimistic reader to consult.
        _ = try await db.execute(sql: "DELETE FROM spike_budget_categories WHERE id='fee'", parameters: nil)
        #expect(try await projected(db).isEmpty)
        // When downloaded current classification becomes General, ordinary
        // visibility resumes. There is no previous-type sticky restriction.
        _ = try await db.execute(sql: """
            INSERT INTO spike_budget_categories(id,account_id,display_name,kind,lifecycle,is_system,
                excludes_from_overall_budget,presentation_order,revision)
            VALUES ('fee',?,'Design Fee','general','active',0,1,0,2)
            """, parameters: [Self.account.rawValue])
        #expect(try await projected(db).first?.kind == .general)
        try await db.close(deleteDatabase: true)
    }

    @Test func existingCategoryQueryObservesOfflineCreationSameCountEditAndMembershipRemoval() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let db = try fixture.open()
        try await seed(db)
        let query = BudgetCategoryReferencePowerSyncQuery(database: db, principalId: Self.principal,
            accountId: Self.account, completenessObservation: { _ in AsyncStream { $0.yield(true); $0.finish() } })
        var iterator = query.watchBudgetCategories(accountId: Self.account).makeAsyncIterator()
        #expect(try await iterator.next()?.local.rows.isEmpty == true)
        _ = try await store(db).submit(create())
        var snapshot = try await iterator.next()
        while snapshot?.local.rows.isEmpty == true { snapshot = try await iterator.next() }
        #expect(snapshot?.local.rows.first?.name.rawValue == "Art & Décor")
        let edit = try command(.init(action: .edit, categoryId: BudgetCategoryID(validating: "new-category"),
            expectedRevision: 1, name: BudgetCategoryName(validating: "Renamed offline"),
            kind: .general, excludesFromOverallBudget: false))
        _ = try await store(db).submit(edit)
        snapshot = try await iterator.next()
        while let current = snapshot, current.local.rows.first?.name.rawValue != "Renamed offline" {
            snapshot = try await iterator.next()
        }
        #expect(snapshot?.local.rows.first?.name.rawValue == "Renamed offline")
        _ = try await db.execute(sql: "UPDATE spike_account_memberships SET state='removed'", parameters: nil)
        snapshot = try await iterator.next()
        while let current = snapshot, !current.local.rows.isEmpty { snapshot = try await iterator.next() }
        #expect(snapshot?.local.rows.isEmpty == true)
        #expect(snapshot?.local.isCompleteForQuery == false)
        await query.cancelAndDrainWatches()
        try await db.close(deleteDatabase: true)
    }

    private func connector(applier: any CategoryManagementCommandApplying,
                           fence: LedgerWorkspaceAccessFence = LedgerWorkspaceAccessFence()) -> LedgerPowerSyncUploadConnector {
        LedgerPowerSyncUploadConnector(accessFence: fence, credentialProvider: { nil },
            clientCreationApplier: UnusedClientApplier(), categoryManagementApplier: applier)
    }
    private struct UnusedClientApplier: ClientCreationCommandApplying {
        func apply(_ request: ClientCreationUploadRequest) async throws -> ClientCreationServerResult { throw InjectedFailure() }
    }
    private struct Applier: CategoryManagementCommandApplying {
        var rejected = false
        var fails = false
        var removes: LedgerWorkspaceAccessFence? = nil
        func apply(_ command: CategoryManagementCommand) async throws -> CategoryManagementServerResult {
            if fails { throw InjectedFailure() }
            removes?.markRemoved()
            let e = command.envelope
            let hash = try command.fingerprint.sha256
            return CategoryManagementServerResult(operation_id: e.operationId.rawValue,
                account_id: e.accountId.rawValue, actor_principal_id: e.actorPrincipalId.rawValue,
                command_type: "manage_categories", contract_version: "category-management-v1",
                command_fingerprint: hash, envelope_sha256: hash, request_sha256: nil,
                subject_id: e.accountId.rawValue, phase: rejected ? "rejected" : "applied",
                result_code: rejected ? nil : "categories_updated", error_code: rejected ? "category_name_unavailable" : nil,
                client_created_at_ms: 1_800_000_000_000, server_received_at_ms: 1_800_000_000_100,
                completed_at_ms: 1_800_000_000_200)
        }
    }

    private func create() throws -> CategoryManagementCommand {
        try command(.init(action: .create, categoryId: BudgetCategoryID(validating: "new-category"),
            name: BudgetCategoryName(validating: "Art & Décor"), kind: .general, excludesFromOverallBudget: false))
    }
    private func command(_ payload: CategoryManagementPayload, uuid: UUID = UUID()) throws -> CategoryManagementCommand {
        try CategoryManagementCommand(operationId: CategoryManagementOperationIdentity.make(accountId: Self.account, uuid: uuid),
            accountId: Self.account, actorPrincipalId: Self.principal, capturedAt: Self.time, payload: payload)
    }
    private func store(_ db: any PowerSyncDatabaseProtocol) -> CategoryManagementPowerSyncStore {
        CategoryManagementPowerSyncStore(database: db, accountId: Self.account, principalId: Self.principal,
            accessFence: LedgerWorkspaceAccessFence(), isDirectoryComplete: { true }, now: { Self.time })
    }
    private func projected(_ db: any PowerSyncDatabaseProtocol) async throws -> [BudgetCategoryDefinitionSnapshot] {
        try await db.readTransaction {
            let full = try CategoryManagementLocalProjection.requireMembership($0, account: Self.account, principal: Self.principal)
            return try CategoryManagementLocalProjection.read($0, account: Self.account, principal: Self.principal, fullFinancialAccess: full)
        }
    }
    private func count(_ table: String, _ db: any PowerSyncDatabaseProtocol) async throws -> Int64 {
        try await db.get("SELECT count(*) FROM \(table)") { try $0.getInt64(index: 0) }
    }
    private func seed(_ db: any PowerSyncDatabaseProtocol) async throws {
        _ = try await db.execute(sql: """
            INSERT INTO spike_account_memberships(id, account_id, principal_id, state, financial_access)
            VALUES ('member', ?, ?, 'active', 'none')
            """, parameters: [Self.account.rawValue, Self.principal.rawValue])
        while let pending = try await db.getNextCrudTransaction() { try await pending.complete() }
    }
    private struct InjectedFailure: Error {}
    private struct Fixture {
        let directory: URL
        let file: URL
        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-category-\(UUID().uuidString)")
            file = directory.appendingPathComponent("ledger.sqlite")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        func open() throws -> any PowerSyncDatabaseProtocol {
            try LedgerPowerSyncDatabaseFactory.open(absolutePath: file.path,
                encryptionKey: LedgerPowerSyncEncryptionKey(hexadecimal: String(repeating: "3a", count: 32)))
        }
        func remove() { try? FileManager.default.removeItem(at: directory) }
    }
}
