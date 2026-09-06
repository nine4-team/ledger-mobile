import Foundation
import LedgerTargetCore
import PowerSync
import Testing
@testable import LedgerTargetPowerSync

// Frozen coverage: ITEMSPACELOCAL-TEST-001, ITEMSPACELOCAL-TEST-002,
// ITEMSPACELOCAL-TEST-003, ITEMSPACELOCAL-TEST-004, ITEMSPACELOCAL-TEST-005,
// ITEMSPACELOCAL-TEST-006, ITEMSPACELOCAL-TEST-007, ITEMSPACELOCAL-TEST-008,
// ITEMSPACELOCAL-TEST-009, ITEMSPACELOCAL-TEST-010, ITEMSPACELOCAL-TEST-011,
// ITEMSPACELOCAL-TEST-012, ITEMSPACELOCAL-TEST-013.
@Suite("Item-to-Space local durability provider", .serialized)
struct ItemSpaceAssignmentPowerSyncStoreTests {
    @Test("Project and Business Inventory persist the exact two-row local contract")
    func exactProjectAndInventoryRows() async throws {
        let fixture = try ItemSpaceAssignmentDatabaseFixture()
        defer { fixture.remove() }
        let database = try fixture.open()
        try await Self.drainCRUD(database)

        let project = try Self.command(
            operation: "assignment-project",
            scope: .project(Self.projectId),
            spaceRevision: UInt64.max,
            items: [("item-zeta", UInt64.max), ("item-alpha", UInt64(Int64.max) + 1)]
        )
        let inventory = try Self.command(
            operation: "assignment-inventory",
            scope: .businessInventory,
            destination: "space-inventory",
            spaceRevision: 0,
            items: [("item-zero", 0), ("item-signed-max", UInt64(Int64.max))]
        )
        let store = Self.store(database)

        #expect(try await store.assignItemsToSpace(project) == Self.queuedReceipt(project))
        #expect(try await store.assignItemsToSpace(inventory) == Self.queuedReceipt(inventory))
        try await Self.expectCommandRow(project, database: database)
        try await Self.expectCommandRow(inventory, database: database)
        try await Self.expectOperationRow(project, database: database)
        try await Self.expectOperationRow(inventory, database: database)
        #expect(try await Self.count(Self.commandTable, database) == 2)
        #expect(try await Self.count(LedgerPowerSyncTable.localOperations, database) == 2)
        #expect(try await Self.count(LedgerPowerSyncTable.operationResults, database) == 0)
        #expect(try await Self.count(LedgerPowerSyncTable.spaces, database) == 0)
        #expect(try await database.get("SELECT count(*) FROM ps_crud") { try $0.getInt64(index: 0) } == 0)
        #expect(try await database.getNextCrudTransaction() == nil)
        try await database.close(deleteDatabase: true)
    }

    @Test("Full UInt64 text and command-valid negative/fractional times replay byte-identically")
    func numericAndClientTimeBoundaries() async throws {
        let fixture = try ItemSpaceAssignmentDatabaseFixture()
        defer { fixture.remove() }
        let database = try fixture.open()
        let store = Self.store(database)
        let cases: [(String, Date, UInt64)] = [
            ("zero", Date(timeIntervalSince1970: -0.000_5), 0),
            ("signed-max", Date(timeIntervalSince1970: -1_234.567_89), UInt64(Int64.max)),
            ("signed-plus-one", Date(timeIntervalSince1970: 0.000_5), UInt64(Int64.max) + 1),
            ("unsigned-max", Date(timeIntervalSince1970: 1_234.567_89), UInt64.max),
            (
                "binary-date-roundtrip",
                Date(timeIntervalSinceReferenceDate: 114_839_371_410.68262),
                42
            )
        ]

        for (name, capturedAt, revision) in cases {
            let command = try Self.command(
                operation: "assignment-time-\(name)",
                capturedAt: capturedAt,
                spaceRevision: revision,
                items: [("item-\(name)", revision)]
            )
            let expectedCommand = Self.json(command)
            let expectedEnvelope = Self.json(command.envelope)
            _ = try await store.assignItemsToSpace(command)
            #expect(try await Self.text("command_json", table: Self.commandTable, id: command.envelope.operationId, database: database) == expectedCommand)
            #expect(try await Self.text("command_envelope_json", table: LedgerPowerSyncTable.localOperations, id: command.envelope.operationId, database: database) == expectedEnvelope)
            #expect(try await store.assignItemsToSpace(command) == Self.queuedReceipt(command))
            #expect(try await Self.text("expected_space_revision", table: Self.commandTable, id: command.envelope.operationId, database: database) == String(revision))
            #expect(try await Self.text("command_expected_revision", table: LedgerPowerSyncTable.localOperations, id: command.envelope.operationId, database: database) == String(revision))
        }
        try await database.close(deleteDatabase: true)
    }

    @Test("Provider time is narrowed only for new admission and never blocks exact replay")
    func providerTimeBoundaryAndPreDatabaseSentinel() async throws {
        let fixture = try ItemSpaceAssignmentDatabaseFixture()
        defer { fixture.remove() }
        let database = try fixture.open()
        let validProbe = ItemSpaceAssignmentCheckpointProbe()
        let valid = ItemSpaceAssignmentPowerSyncStore(
            database: database,
            accountId: Self.accountId,
            principalId: Self.principalId,
            now: { Date(timeIntervalSince1970: 1_234.567_89) },
            checkpoint: { checkpoint in
                if case .beforeTransaction = checkpoint { validProbe.record() }
            }
        )
        let validCommand = try Self.command(operation: "assignment-valid-provider-time")
        _ = try await valid.assignItemsToSpace(validCommand)
        #expect(validProbe.count == 1)
        #expect(try await Self.integer("accepted_at_ms", table: Self.commandTable, id: validCommand.envelope.operationId, database: database) == 1_234_567)

        let replayClockProbe = ItemSpaceAssignmentCheckpointProbe()
        let replayReadProbe = ItemSpaceAssignmentCheckpointProbe()
        let invalidClockReplay = ItemSpaceAssignmentPowerSyncStore(
            database: database,
            accountId: Self.accountId,
            principalId: Self.principalId,
            now: {
                replayClockProbe.record()
                return Date(timeIntervalSince1970: .nan)
            },
            checkpoint: { checkpoint in
                if case .existingRead = checkpoint { replayReadProbe.record() }
            }
        )
        #expect(
            try await invalidClockReplay.assignItemsToSpace(validCommand) ==
                Self.queuedReceipt(validCommand)
        )
        #expect(replayReadProbe.count == 1)
        #expect(replayClockProbe.count == 0)
        #expect(try await Self.integer("accepted_at_ms", table: Self.commandTable, id: validCommand.envelope.operationId, database: database) == 1_234_567)
        #expect(try await Self.integer("accepted_at_ms", table: LedgerPowerSyncTable.localOperations, id: validCommand.envelope.operationId, database: database) == 1_234_567)

        let invalidTimes: [Date] = [
            Date(timeIntervalSince1970: -0.001),
            Date(timeIntervalSince1970: .nan),
            Date(timeIntervalSince1970: .infinity),
            Date(timeIntervalSince1970: -.infinity),
            Date(timeIntervalSince1970: Double(Int64.max) / 1_000 + 10_000)
        ]
        for (index, time) in invalidTimes.enumerated() {
            let readProbe = ItemSpaceAssignmentCheckpointProbe()
            let writeProbe = ItemSpaceAssignmentCheckpointProbe()
            let invalid = ItemSpaceAssignmentPowerSyncStore(
                database: database,
                accountId: Self.accountId,
                principalId: Self.principalId,
                now: { time },
                checkpoint: { checkpoint in
                    switch checkpoint {
                    case .existingRead:
                        readProbe.record()
                    case .commandWrite, .operationWrite:
                        writeProbe.record()
                    default:
                        break
                    }
                }
            )
            await #expect(throws: ItemSpaceAssignmentPowerSyncStoreFailure.invalidAcceptanceTime) {
                _ = try await invalid.assignItemsToSpace(
                    Self.command(operation: "assignment-invalid-provider-time-\(index)")
                )
            }
            #expect(readProbe.count == 1)
            #expect(writeProbe.count == 0)
        }
        #expect(try await Self.count(Self.commandTable, database) == 1)
        #expect(try await Self.count(LedgerPowerSyncTable.localOperations, database) == 1)
        try await database.close(deleteDatabase: true)
    }

    @Test("High provider milliseconds round-trip exactly or fail closed")
    func providerTimeExactRoundTripBoundary() async throws {
        let fixture = try ItemSpaceAssignmentDatabaseFixture()
        defer { fixture.remove() }
        let database = try fixture.open()
        let safeMilliseconds: Int64 = 4_463_963_422_584_948
        let unsafeMilliseconds: Int64 = safeMilliseconds - 1
        let safeDate = Date(
            timeIntervalSince1970: Double(safeMilliseconds) / 1_000
        )
        let unsafeDate = Date(
            timeIntervalSinceReferenceDate: Double(bitPattern: 0x42903c7a91dbe3ca)
        )
        #expect(
            Int64(exactly: (unsafeDate.timeIntervalSince1970 * 1_000).rounded(.towardZero)) ==
                unsafeMilliseconds
        )

        let safeCommand = try Self.command(operation: "assignment-safe-high-time")
        let safeStore = Self.store(database, now: { safeDate })
        #expect(
            try await safeStore.assignItemsToSpace(safeCommand) ==
                Self.queuedReceipt(safeCommand)
        )
        #expect(
            try await Self.integer(
                "accepted_at_ms",
                table: Self.commandTable,
                id: safeCommand.envelope.operationId,
                database: database
            ) == safeMilliseconds
        )
        var safeWatch = safeStore.watchOperation(
            safeCommand.envelope.operationId
        ).makeAsyncIterator()
        let safeSnapshot = try #require(try await safeWatch.next())
        #expect(safeSnapshot.acceptedAt == safeDate)
        #expect(safeSnapshot.updatedAt == safeDate)

        let unsafeCommand = try Self.command(operation: "assignment-unsafe-high-time")
        let unsafeStore = Self.store(database, now: { unsafeDate })
        await #expect(throws: ItemSpaceAssignmentPowerSyncStoreFailure.invalidAcceptanceTime) {
            _ = try await unsafeStore.assignItemsToSpace(unsafeCommand)
        }
        #expect(try await Self.count(Self.commandTable, database) == 1)
        #expect(try await Self.count(LedgerPowerSyncTable.localOperations, database) == 1)

        let malformedCommand = try Self.command(operation: "assignment-malformed-high-time")
        let malformedStore = Self.store(database)
        _ = try await malformedStore.assignItemsToSpace(malformedCommand)
        _ = try await database.execute(
            sql: "UPDATE \(Self.commandTable) SET accepted_at_ms = ? WHERE id = ?",
            parameters: [unsafeMilliseconds, malformedCommand.envelope.operationId.rawValue]
        )
        _ = try await database.execute(
            sql: "UPDATE \(LedgerPowerSyncTable.localOperations) SET accepted_at_ms = ?, updated_at_ms = ? WHERE id = ?",
            parameters: [
                unsafeMilliseconds,
                unsafeMilliseconds,
                malformedCommand.envelope.operationId.rawValue
            ]
        )
        await #expect(throws: ItemSpaceAssignmentPowerSyncStoreFailure.malformedLocalEvidence) {
            _ = try await malformedStore.assignItemsToSpace(malformedCommand)
        }
        await Self.expectWatchFailure(
            .malformedLocalEvidence,
            store: malformedStore,
            operationId: malformedCommand.envelope.operationId
        )
        await safeStore.cancelAndDrainWatches()
        await unsafeStore.cancelAndDrainWatches()
        await malformedStore.cancelAndDrainWatches()
        try await database.close(deleteDatabase: true)
    }

    @Test("Account and Principal mismatch refuse before access while matching scope reaches it")
    func scopeRefusalBeforeDatabaseAccess() async throws {
        let fixture = try ItemSpaceAssignmentDatabaseFixture()
        defer { fixture.remove() }
        let database = try fixture.open()
        let store = ItemSpaceAssignmentPowerSyncStore(
            database: database,
            accountId: Self.accountId,
            principalId: Self.principalId,
            now: { Self.acceptedAt },
            checkpoint: { checkpoint in
                if case .beforeTransaction = checkpoint {
                    throw ItemSpaceAssignmentInjectedFailure()
                }
            }
        )
        await #expect(throws: LedgerOfflineClientRuntimeFailure.accountScopeMismatch) {
            _ = try await store.assignItemsToSpace(Self.command(
                operation: "assignment-foreign-account",
                accountId: try AccountID(validating: "account-foreign")
            ))
        }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.principalScopeMismatch) {
            _ = try await store.assignItemsToSpace(Self.command(
                operation: "assignment-foreign-principal",
                principalId: try PrincipalID(validating: "principal-foreign")
            ))
        }
        await #expect(throws: ItemSpaceAssignmentFailure.localAcceptanceFailed) {
            _ = try await store.assignItemsToSpace(
                Self.command(operation: "assignment-matching-scope-probe")
            )
        }
        #expect(try await Self.count(Self.commandTable, database) == 0)
        #expect(try await Self.count(LedgerPowerSyncTable.localOperations, database) == 0)
        try await database.close(deleteDatabase: true)
    }

    @Test("Encrypted close and repeated reopen retain exact evidence")
    func encryptedRestartRetention() async throws {
        let fixture = try ItemSpaceAssignmentDatabaseFixture()
        defer { fixture.remove() }
        let command = try Self.command(operation: "assignment-restart")
        let expectedCommand = Self.json(command)
        let expectedEnvelope = Self.json(command.envelope)

        var database = try fixture.open()
        _ = try await Self.store(database).assignItemsToSpace(command)
        try await database.close(deleteDatabase: false)
        let encryptedBytes = try Data(contentsOf: fixture.databaseURL)
        #expect(!String(decoding: encryptedBytes, as: UTF8.self).contains(command.envelope.operationId.rawValue))

        for _ in 0..<2 {
            database = try fixture.open()
            #expect(try await Self.text("command_json", table: Self.commandTable, id: command.envelope.operationId, database: database) == expectedCommand)
            #expect(try await Self.text("command_envelope_json", table: LedgerPowerSyncTable.localOperations, id: command.envelope.operationId, database: database) == expectedEnvelope)
            #expect(try await Self.store(database).assignItemsToSpace(command) == Self.queuedReceipt(command))
            try await database.close(deleteDatabase: false)
        }
        database = try fixture.open()
        try await database.close(deleteDatabase: true)
    }

    @Test("Partial evidence remains malformed across encrypted restart and never upgrades")
    func malformedRestartNeverUpgrades() async throws {
        let fixture = try ItemSpaceAssignmentDatabaseFixture()
        defer { fixture.remove() }
        let command = try Self.command(operation: "assignment-malformed-restart")
        var database = try fixture.open()
        _ = try await Self.store(database).assignItemsToSpace(command)
        _ = try await database.execute(
            sql: "DELETE FROM \(LedgerPowerSyncTable.localOperations) WHERE id = ?",
            parameters: [command.envelope.operationId.rawValue]
        )
        try await database.close(deleteDatabase: false)

        for _ in 0..<2 {
            database = try fixture.open()
            await #expect(throws: ItemSpaceAssignmentPowerSyncStoreFailure.malformedLocalEvidence) {
                _ = try await Self.store(database).assignItemsToSpace(command)
            }
            #expect(try await Self.count(Self.commandTable, database) == 1)
            #expect(try await Self.count(LedgerPowerSyncTable.localOperations, database) == 0)
            try await database.close(deleteDatabase: false)
        }
        database = try fixture.open()
        try await database.close(deleteDatabase: true)
    }

    @Test("Exact replay succeeds and a changed command fails closed")
    func exactAndChangedReplay() async throws {
        let fixture = try ItemSpaceAssignmentDatabaseFixture()
        defer { fixture.remove() }
        let database = try fixture.open()
        let original = try Self.command(operation: "assignment-replay")
        let changed = try Self.command(
            operation: original.envelope.operationId.rawValue,
            destination: "space-changed"
        )
        let store = Self.store(database)
        _ = try await store.assignItemsToSpace(original)
        #expect(try await store.assignItemsToSpace(original) == Self.queuedReceipt(original))
        do {
            _ = try await store.assignItemsToSpace(changed)
            Issue.record("Changed replay was accepted")
        } catch let failure as OperationContractFailure {
            guard case .payloadMismatch(let operationId) = failure else {
                Issue.record("Wrong replay failure: \(failure)")
                return
            }
            #expect(operationId == original.envelope.operationId)
        }
        #expect(try await Self.count(Self.commandTable, database) == 1)
        #expect(try await Self.count(LedgerPowerSyncTable.localOperations, database) == 1)
        try await database.close(deleteDatabase: true)
    }

    @Test("Every command field and both orphan directions fail closed without repair")
    func commandTamperAndOrphans() async throws {
        let cases: [(String, String)] = [
            ("account_id", "account-tampered"),
            ("actor_principal_id", "principal-tampered"),
            ("contract_version", "contract-tampered"),
            ("destination_space_id", "space-tampered"),
            ("scope_kind", "wrong_scope"),
            ("project_id", "project-tampered"),
            ("expected_space_revision", "01"),
            ("items_json", "{}"),
            ("fingerprint", String(repeating: "0", count: 64)),
            ("command_json", "{}"),
            ("accepted_at_ms", "-1")
        ]
        for (index, entry) in cases.enumerated() {
            try await Self.withAcceptedCommand("command-tamper-\(index)") { command, store, database in
                _ = try await database.execute(
                    sql: "UPDATE \(Self.commandTable) SET \(entry.0) = ? WHERE id = ?",
                    parameters: [entry.1, command.envelope.operationId.rawValue]
                )
                await #expect(throws: ItemSpaceAssignmentPowerSyncStoreFailure.malformedLocalEvidence) {
                    _ = try await store.assignItemsToSpace(command)
                }
                #expect(try await Self.text(entry.0, table: Self.commandTable, id: command.envelope.operationId, database: database) == entry.1)
            }
        }
        for (index, column) in cases.map(\.0).enumerated() {
            try await Self.withAcceptedCommand("command-null-\(index)") { command, store, database in
                _ = try await database.execute(
                    sql: "UPDATE \(Self.commandTable) SET \(column) = NULL WHERE id = ?",
                    parameters: [command.envelope.operationId.rawValue]
                )
                await #expect(throws: ItemSpaceAssignmentPowerSyncStoreFailure.malformedLocalEvidence) {
                    _ = try await store.assignItemsToSpace(command)
                }
                #expect(try await Self.optionalText(column, table: Self.commandTable, id: command.envelope.operationId, database: database) == nil)
            }
        }
        try await Self.withAcceptedCommand("orphan-command") { command, store, database in
            _ = try await database.execute(
                sql: "DELETE FROM \(Self.commandTable) WHERE id = ?",
                parameters: [command.envelope.operationId.rawValue]
            )
            await #expect(throws: ItemSpaceAssignmentPowerSyncStoreFailure.malformedLocalEvidence) {
                _ = try await store.assignItemsToSpace(command)
            }
        }
        try await Self.withAcceptedCommand("orphan-operation") { command, store, database in
            _ = try await database.execute(
                sql: "DELETE FROM \(LedgerPowerSyncTable.localOperations) WHERE id = ?",
                parameters: [command.envelope.operationId.rawValue]
            )
            await #expect(throws: ItemSpaceAssignmentPowerSyncStoreFailure.malformedLocalEvidence) {
                _ = try await store.assignItemsToSpace(command)
            }
        }
    }

    @Test("Every operation field, terminal field, and unexpected result fails closed")
    func operationTamperAndTerminalEvidence() async throws {
        let requiredCases: [(String, String)] = [
            ("account_id", "account-tampered"),
            ("actor_principal_id", "principal-tampered"),
            ("contract_version", "contract-tampered"),
            ("fingerprint", String(repeating: "0", count: 64)),
            ("subject_id", "space-tampered"),
            ("local_state", "applying"),
            ("accepted_at_ms", "-1"),
            ("updated_at_ms", "1"),
            ("command_type", "wrong_command"),
            ("command_expected_revision", "01"),
            ("command_envelope_json", "{}")
        ]
        for (index, entry) in requiredCases.enumerated() {
            try await Self.withAcceptedCommand("operation-tamper-\(index)") { command, store, database in
                _ = try await database.execute(
                    sql: "UPDATE \(LedgerPowerSyncTable.localOperations) SET \(entry.0) = ? WHERE id = ?",
                    parameters: [entry.1, command.envelope.operationId.rawValue]
                )
                await #expect(throws: ItemSpaceAssignmentPowerSyncStoreFailure.malformedLocalEvidence) {
                    _ = try await store.assignItemsToSpace(command)
                }
            }
        }
        for (index, column) in requiredCases.map(\.0).enumerated() {
            try await Self.withAcceptedCommand("operation-null-\(index)") { command, store, database in
                _ = try await database.execute(
                    sql: "UPDATE \(LedgerPowerSyncTable.localOperations) SET \(column) = NULL WHERE id = ?",
                    parameters: [command.envelope.operationId.rawValue]
                )
                await #expect(throws: ItemSpaceAssignmentPowerSyncStoreFailure.malformedLocalEvidence) {
                    _ = try await store.assignItemsToSpace(command)
                }
            }
        }
        let terminalColumns = [
            "terminal_phase", "terminal_result_code", "terminal_error_code",
            "terminal_envelope_sha256", "terminal_request_sha256",
            "terminal_server_received_at_ms", "terminal_completed_at_ms"
        ]
        for (index, column) in terminalColumns.enumerated() {
            try await Self.withAcceptedCommand("terminal-tamper-\(index)") { command, store, database in
                _ = try await database.execute(
                    sql: "UPDATE \(LedgerPowerSyncTable.localOperations) SET \(column) = ? WHERE id = ?",
                    parameters: [column.hasSuffix("_ms") ? 1 : "terminal", command.envelope.operationId.rawValue]
                )
                await #expect(throws: ItemSpaceAssignmentPowerSyncStoreFailure.malformedLocalEvidence) {
                    _ = try await store.assignItemsToSpace(command)
                }
            }
        }
        try await Self.withAcceptedCommand("unexpected-result") { command, store, database in
            _ = try await database.execute(
                sql: "INSERT INTO \(LedgerPowerSyncTable.operationResults) (id) VALUES (?)",
                parameters: [command.envelope.operationId.rawValue]
            )
            await #expect(throws: ItemSpaceAssignmentPowerSyncStoreFailure.malformedLocalEvidence) {
                _ = try await store.assignItemsToSpace(command)
            }
        }
    }

    @Test("Concurrent same-ID admission converges and conflicting payload has one winner")
    func concurrentAdmission() async throws {
        let fixture = try ItemSpaceAssignmentDatabaseFixture()
        defer { fixture.remove() }
        let database = try fixture.open()
        let store = Self.store(database)
        let command = try Self.command(operation: "assignment-concurrent-same")
        async let first = store.assignItemsToSpace(command)
        async let second = store.assignItemsToSpace(command)
        #expect(try await first == Self.queuedReceipt(command))
        #expect(try await second == Self.queuedReceipt(command))
        #expect(try await Self.count(Self.commandTable, database) == 1)

        let winner = try Self.command(operation: "assignment-concurrent-conflict")
        let challenger = try Self.command(
            operation: winner.envelope.operationId.rawValue,
            destination: "space-concurrent-other"
        )
        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            group.addTask { (try? await store.assignItemsToSpace(winner)) != nil }
            group.addTask { (try? await store.assignItemsToSpace(challenger)) != nil }
            var values: [Bool] = []
            for await value in group { values.append(value) }
            return values
        }
        #expect(results.filter { $0 }.count == 1)
        #expect(try await Self.count(Self.commandTable, database) == 2)
        #expect(try await Self.count(LedgerPowerSyncTable.localOperations, database) == 2)
        let storedJSON = try await Self.text(
            "command_json",
            table: Self.commandTable,
            id: winner.envelope.operationId,
            database: database
        )
        let accepted = storedJSON == Self.json(winner) ? winner : challenger
        let refused = storedJSON == Self.json(winner) ? challenger : winner
        #expect(try await store.assignItemsToSpace(accepted) == Self.queuedReceipt(accepted))
        do {
            _ = try await store.assignItemsToSpace(refused)
            Issue.record("Conflicting concurrent payload replay was accepted")
        } catch let failure as OperationContractFailure {
            guard case .payloadMismatch(let operationId) = failure else {
                Issue.record("Wrong concurrent loser failure: \(failure)")
                return
            }
            #expect(operationId == winner.envelope.operationId)
        }
        try await database.close(deleteDatabase: true)
    }

    @Test("Raw transaction/read/write failures roll back and map to the bounded local failure")
    func writeFailureMappingAndRollback() async throws {
        let checkpoints: [ItemSpaceAssignmentPowerSyncStoreCheckpoint] = [
            .beforeTransaction, .existingRead, .commandWrite, .operationWrite,
            .beforeCommit
        ]
        for (index, failingCheckpoint) in checkpoints.enumerated() {
            let fixture = try ItemSpaceAssignmentDatabaseFixture()
            let database = try fixture.open()
            let store = ItemSpaceAssignmentPowerSyncStore(
                database: database,
                accountId: Self.accountId,
                principalId: Self.principalId,
                now: { Self.acceptedAt },
                checkpoint: { checkpoint in
                    if Self.sameCheckpoint(checkpoint, failingCheckpoint) {
                        throw ItemSpaceAssignmentInjectedFailure()
                    }
                }
            )
            await #expect(throws: ItemSpaceAssignmentFailure.localAcceptanceFailed) {
                _ = try await store.assignItemsToSpace(
                    Self.command(operation: "assignment-write-failure-\(index)")
                )
            }
            #expect(try await Self.count(Self.commandTable, database) == 0)
            #expect(try await Self.count(LedgerPowerSyncTable.localOperations, database) == 0)
            try await database.close(deleteDatabase: true)
            fixture.remove()
        }
    }

    @Test("Cancellation passes through on both sides of atomic commit")
    func cancellationBoundaries() async throws {
        let fixture = try ItemSpaceAssignmentDatabaseFixture()
        defer { fixture.remove() }
        let database = try fixture.open()
        let preCommit = ItemSpaceAssignmentPowerSyncStore(
            database: database,
            accountId: Self.accountId,
            principalId: Self.principalId,
            now: { Self.acceptedAt },
            checkpoint: { checkpoint in
                if case .beforeCommit = checkpoint { throw CancellationError() }
            }
        )
        await #expect(throws: CancellationError.self) {
            _ = try await preCommit.assignItemsToSpace(
                Self.command(operation: "assignment-cancel-precommit")
            )
        }
        #expect(try await Self.count(Self.commandTable, database) == 0)
        #expect(try await Self.count(LedgerPowerSyncTable.localOperations, database) == 0)

        let postCommitCommand = try Self.command(operation: "assignment-cancel-postcommit")
        let postCommit = ItemSpaceAssignmentPowerSyncStore(
            database: database,
            accountId: Self.accountId,
            principalId: Self.principalId,
            now: { Self.acceptedAt },
            checkpoint: { checkpoint in
                if case .afterCommit = checkpoint { throw CancellationError() }
            }
        )
        await #expect(throws: CancellationError.self) {
            _ = try await postCommit.assignItemsToSpace(postCommitCommand)
        }
        #expect(try await Self.count(Self.commandTable, database) == 1)
        #expect(try await Self.count(LedgerPowerSyncTable.localOperations, database) == 1)
        #expect(try await Self.store(database).assignItemsToSpace(postCommitCommand) == Self.queuedReceipt(postCommitCommand))
        try await database.close(deleteDatabase: true)
    }

    @Test("Queued-only watch is exact, scoped, and drains")
    func queuedOnlyWatchAndDrainage() async throws {
        let fixture = try ItemSpaceAssignmentDatabaseFixture()
        defer { fixture.remove() }
        let database = try fixture.open()
        let command = try Self.command(operation: "opaque.run:42")
        let otherCommand = try Self.command(
            operation: "other-operation",
            destination: "space-other-operation",
            spaceRevision: 99
        )
        let store = Self.store(database)
        _ = try await store.assignItemsToSpace(command)
        _ = try await store.assignItemsToSpace(otherCommand)
        var iterator = store.watchOperation(command.envelope.operationId).makeAsyncIterator()
        let snapshot = try #require(try await iterator.next())
        #expect(snapshot.operationId == command.envelope.operationId)
        #expect(snapshot.operationId != otherCommand.envelope.operationId)
        #expect(snapshot.accountId == Self.accountId)
        #expect(snapshot.contractVersion == command.envelope.contractVersion)
        #expect(snapshot.fingerprint == command.fingerprint)
        #expect(snapshot.fingerprint != otherCommand.fingerprint)
        #expect(snapshot.acceptedAt == Self.acceptedAt)
        #expect(snapshot.updatedAt == Self.acceptedAt)
        guard case .queued(let attempts, let lastError) = snapshot.state else {
            Issue.record("Assignment watch emitted a non-queued state")
            return
        }
        #expect(attempts == 0)
        #expect(lastError == nil)
        await store.cancelAndDrainWatches()
        do {
            #expect(try await iterator.next() == nil)
        } catch is CancellationError {
            // Cancellation is an allowed terminal signal for an admitted watch.
        }
        var refused = store.watchOperation(command.envelope.operationId).makeAsyncIterator()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await refused.next()
        }
        try await database.close(deleteDatabase: true)
    }

    @Test("Raw watch failures map without emission and cancellation remains control flow")
    func watchFailureMappingAndCancellation() async throws {
        let checkpoints: [ItemSpaceAssignmentPowerSyncStoreCheckpoint] = [
            .watchConstruction, .watchRead, .watchIteration
        ]
        for (index, failingCheckpoint) in checkpoints.enumerated() {
            let fixture = try ItemSpaceAssignmentDatabaseFixture()
            let database = try fixture.open()
            let command = try Self.command(operation: "assignment-watch-failure-\(index)")
            _ = try await Self.store(database).assignItemsToSpace(command)
            let store = ItemSpaceAssignmentPowerSyncStore(
                database: database,
                accountId: Self.accountId,
                principalId: Self.principalId,
                now: { Self.acceptedAt },
                checkpoint: { checkpoint in
                    if Self.sameCheckpoint(checkpoint, failingCheckpoint) {
                        throw ItemSpaceAssignmentInjectedFailure()
                    }
                }
            )
            var iterator = store.watchOperation(command.envelope.operationId).makeAsyncIterator()
            await #expect(throws: ItemSpaceAssignmentFailure.localAcceptanceFailed) {
                _ = try await iterator.next()
            }
            await store.cancelAndDrainWatches()
            try await database.close(deleteDatabase: true)
            fixture.remove()
        }

        let fixture = try ItemSpaceAssignmentDatabaseFixture()
        let database = try fixture.open()
        let command = try Self.command(operation: "assignment-watch-cancellation")
        _ = try await Self.store(database).assignItemsToSpace(command)
        let cancelling = ItemSpaceAssignmentPowerSyncStore(
            database: database,
            accountId: Self.accountId,
            principalId: Self.principalId,
            now: { Self.acceptedAt },
            checkpoint: { checkpoint in
                if case .watchIteration = checkpoint { throw CancellationError() }
            }
        )
        var iterator = cancelling.watchOperation(command.envelope.operationId).makeAsyncIterator()
        await #expect(throws: CancellationError.self) { _ = try await iterator.next() }
        await cancelling.cancelAndDrainWatches()
        try await database.close(deleteDatabase: true)
        fixture.remove()
    }

    @Test("Absent/foreign observations are not found; every nonqueued, terminal, and result shape is malformed")
    func watchRefusalMatrix() async throws {
        let fixture = try ItemSpaceAssignmentDatabaseFixture()
        defer { fixture.remove() }
        let database = try fixture.open()
        let missing = try OperationID(validating: "assignment-watch-missing")
        let store = Self.store(database)
        await Self.expectWatchFailure(.operationNotFound, store: store, operationId: missing)

        let command = try Self.command(operation: "assignment-watch-malformed")
        _ = try await store.assignItemsToSpace(command)
        _ = try await database.execute(
            sql: "UPDATE \(LedgerPowerSyncTable.localOperations) SET local_state = 'applying' WHERE id = ?",
            parameters: [command.envelope.operationId.rawValue]
        )
        await Self.expectWatchFailure(.malformedLocalEvidence, store: store, operationId: command.envelope.operationId)

        let foreign = try Self.command(operation: "assignment-watch-foreign")
        _ = try await store.assignItemsToSpace(foreign)
        _ = try await database.execute(
            sql: "UPDATE \(LedgerPowerSyncTable.localOperations) SET account_id = 'account-foreign' WHERE id = ?",
            parameters: [foreign.envelope.operationId.rawValue]
        )
        await Self.expectWatchFailure(.operationNotFound, store: store, operationId: foreign.envelope.operationId)

        let foreignPrincipal = try Self.command(
            operation: "assignment-watch-foreign-principal"
        )
        _ = try await store.assignItemsToSpace(foreignPrincipal)
        _ = try await database.execute(
            sql: "UPDATE \(LedgerPowerSyncTable.localOperations) SET actor_principal_id = 'principal-foreign' WHERE id = ?",
            parameters: [foreignPrincipal.envelope.operationId.rawValue]
        )
        await Self.expectWatchFailure(
            .operationNotFound,
            store: store,
            operationId: foreignPrincipal.envelope.operationId
        )
        await store.cancelAndDrainWatches()
        try await database.close(deleteDatabase: true)

        for state in LocalOperationState.allCases where state != .queued {
            try await Self.withAcceptedCommand("watch-state-\(state.rawValue)") { command, store, database in
                _ = try await database.execute(
                    sql: "UPDATE \(LedgerPowerSyncTable.localOperations) SET local_state = ? WHERE id = ?",
                    parameters: [state.rawValue, command.envelope.operationId.rawValue]
                )
                await Self.expectWatchFailure(
                    .malformedLocalEvidence,
                    store: store,
                    operationId: command.envelope.operationId
                )
                await store.cancelAndDrainWatches()
            }
        }
        try await Self.withAcceptedCommand("watch-terminal") { command, store, database in
            _ = try await database.execute(
                sql: "UPDATE \(LedgerPowerSyncTable.localOperations) SET terminal_phase = 'applied' WHERE id = ?",
                parameters: [command.envelope.operationId.rawValue]
            )
            await Self.expectWatchFailure(
                .malformedLocalEvidence,
                store: store,
                operationId: command.envelope.operationId
            )
            await store.cancelAndDrainWatches()
        }
        try await Self.withAcceptedCommand("watch-result") { command, store, database in
            _ = try await database.execute(
                sql: "INSERT INTO \(LedgerPowerSyncTable.operationResults) (id) VALUES (?)",
                parameters: [command.envelope.operationId.rawValue]
            )
            await Self.expectWatchFailure(
                .malformedLocalEvidence,
                store: store,
                operationId: command.envelope.operationId
            )
            await store.cancelAndDrainWatches()
        }
    }

    @Test("Pending summary counts the local assignment once and ps_crud remains empty")
    func pendingSummaryAndNoUploadWork() async throws {
        let fixture = try ItemSpaceAssignmentDatabaseFixture()
        defer { fixture.remove() }
        let database = try fixture.open()
        try await Self.drainCRUD(database)
        let command = try Self.command(operation: "assignment-pending-summary")
        _ = try await Self.store(database).assignItemsToSpace(command)
        let query = PendingWorkPowerSyncQuery(
            database: database,
            attachmentObserver: ItemSpaceAssignmentEmptyAttachmentObserver(),
            environment: .targetLocal,
            principalId: Self.principalId,
            accountId: Self.accountId,
            now: { Self.acceptedAt }
        )
        let summary = try await query.summary()
        #expect(summary.queuedOperationCount == 1)
        #expect(summary.applyingOperationCount == 0)
        #expect(summary.unresolvedRejectedOperationCount == 0)
        #expect(try await database.get("SELECT count(*) FROM ps_crud") { try $0.getInt64(index: 0) } == 0)
        #expect(try await database.getNextCrudTransaction() == nil)
        try await database.close(deleteDatabase: true)
    }

    @Test("Runtime close drains admitted assignment work and refuses later facade calls")
    func runtimeCloseDrainageAndTerminalRefusal() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-item-space-runtime-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let finiteGate = ItemSpaceAssignmentManualGate()
        let closeCompleted = ItemSpaceAssignmentAsyncFlag()
        let closeProbe = ItemSpaceAssignmentRuntimeCloseProbe()
        let assignmentStore = ItemSpaceAssignmentRuntimeStoreSpy(probe: closeProbe)
        var dependencies = LedgerPowerSyncLocalBootstrapDependencies.live
        dependencies.loadDatabaseKey = { _, _ in
            try LedgerPowerSyncEncryptionKey(hexadecimal: String(repeating: "21", count: 32))
        }
        dependencies.loadMediaKeyBytes = { _, _ in Data(repeating: 0x44, count: 32) }
        dependencies.createDirectory = {
            try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
        }
        dependencies.now = { Self.acceptedAt }
        dependencies.finiteOperationCheckpoint = { operation in
            if operation == .assignItemsToSpace { await finiteGate.wait() }
        }
        dependencies.makeItemSpaceAssignmentStore = { _, _, _, _ in
            assignmentStore
        }
        dependencies.lifecycleEvent = { event in
            if event == .structuredDatabaseCloseAttempted {
                closeProbe.record(.structuredDatabaseCloseAttempted)
            }
        }
        let runtime = try await LedgerPowerSyncLocalBootstrap.open(
            validatedEnvironment: Self.runtimeEnvironment(),
            principalId: Self.principalId,
            accountId: Self.accountId,
            applicationSupportDirectory: root,
            dependencies: dependencies
        )
        let command = try Self.command(operation: "assignment-runtime-close")
        let submission = Task { try await runtime.assignItemsToSpace(command) }
        await finiteGate.waitUntilEntered()
        let consumer = Task {
            do {
                for try await _ in runtime.watchItemSpaceAssignmentOperation(
                    command.envelope.operationId
                ) {}
            } catch {
                // Runtime close cancels an admitted stream.
            }
        }
        try await closeProbe.waitUntil(.providerWatchAdmitted)
        let close = Task {
            try await runtime.close()
            await closeCompleted.set()
        }
        try await Task.sleep(for: .milliseconds(30))
        #expect(!(await closeCompleted.value))
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.assignItemsToSpace(command)
        }

        await finiteGate.release()
        #expect(try await submission.value == Self.queuedReceipt(command))
        try await close.value
        await consumer.value
        #expect(await closeCompleted.value)
        let closeEvents = closeProbe.values
        let admittedIndex = try #require(
            closeEvents.firstIndex(of: .providerWatchAdmitted)
        )
        let cancelledIndex = try #require(
            closeEvents.firstIndex(of: .providerWatchCancelled)
        )
        let drainStartedIndex = try #require(
            closeEvents.firstIndex(of: .providerDrainStarted)
        )
        let drainCompletedIndex = try #require(
            closeEvents.firstIndex(of: .providerDrainCompleted)
        )
        let structuredCloseIndex = try #require(
            closeEvents.firstIndex(of: .structuredDatabaseCloseAttempted)
        )
        #expect(admittedIndex < cancelledIndex)
        #expect(drainStartedIndex < drainCompletedIndex)
        #expect(drainCompletedIndex < structuredCloseIndex)
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.assignItemsToSpace(command)
        }
        var closed = runtime.watchItemSpaceAssignmentOperation(
            command.envelope.operationId
        ).makeAsyncIterator()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await closed.next()
        }
    }

    @Test("Runtime nominally satisfies the assignment use-case port")
    func runtimeItemSpaceAssignmentUseCaseIntegration() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-item-space-use-case-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let assignmentStore = ItemSpaceAssignmentRuntimeStoreSpy(
            probe: ItemSpaceAssignmentRuntimeCloseProbe()
        )
        var dependencies = LedgerPowerSyncLocalBootstrapDependencies.live
        dependencies.loadDatabaseKey = { _, _ in
            try LedgerPowerSyncEncryptionKey(hexadecimal: String(repeating: "31", count: 32))
        }
        dependencies.loadMediaKeyBytes = { _, _ in Data(repeating: 0x54, count: 32) }
        dependencies.createDirectory = {
            try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
        }
        dependencies.now = { Self.acceptedAt }
        dependencies.makeItemSpaceAssignmentStore = { _, _, _, _ in assignmentStore }
        let runtime = try await LedgerPowerSyncLocalBootstrap.open(
            validatedEnvironment: Self.runtimeEnvironment(),
            principalId: Self.principalId,
            accountId: Self.accountId,
            applicationSupportDirectory: root,
            dependencies: dependencies
        )
        let destinationId = try SpaceID(validating: "space-use-case-runtime")
        let scope = ItemPlacementScope.project(Self.projectId)
        let request = try SpaceAssignmentDestinationRequest(
            accountId: Self.accountId,
            scope: scope
        )
        let destination = try SpaceAssignmentDestinationSnapshot(
            id: destinationId,
            accountId: Self.accountId,
            scope: scope,
            displayName: SpaceDisplayName(validating: "Runtime destination"),
            lifecycle: .active,
            revision: UInt64.max
        )
        let directory = try SpaceAssignmentDestinationDirectorySnapshot(
            request: request,
            local: ListLocalSnapshot(
                queryFingerprint: request.queryFingerprint,
                rows: [destination],
                visibleRowCountBeforeFiltering: 1,
                isCompleteForQuery: true,
                quality: .ready,
                localDataVersion: LocalDataVersion(validating: "runtime-use-case-directory"),
                asOf: Self.acceptedAt
            )
        )
        let intent = ItemSpaceAssignmentIntent(
            accountId: Self.accountId,
            scope: scope,
            destinationSpaceId: destinationId,
            items: [try ItemSpaceAssignmentCandidate(
                itemId: ItemID(validating: "item-use-case-runtime"),
                expectedRevision: ExpectedItemPlacementRevision(UInt64.max)
            )]
        )
        let operationId = try OperationID(validating: "assignment-use-case-runtime")
        let receipt = try await ItemSpaceAssignmentUseCase(assigner: runtime).execute(
            input: intent,
            currentDestinations: directory,
            operationId: operationId,
            actorPrincipalId: Self.principalId,
            operationContractVersion: OperationContractVersion(
                validating: "item-space-assignment-v1"
            ),
            capturedAt: Date(timeIntervalSince1970: -1_234.567_89)
        )
        #expect(receipt == OperationReceipt(operationId: operationId, localState: .queued))
        let submitted = assignmentStore.submittedCommands
        #expect(submitted.count == 1)
        let command = try #require(submitted.first)
        #expect(command.envelope.operationId == operationId)
        #expect(command.draft.expectedSpaceRevision.rawValue == UInt64.max)
        #expect(command.draft.items == intent.items)
        try await runtime.close()
    }

    @Test("Live runtime factory binds assignment evidence to its structured workspace")
    func liveRuntimeItemSpaceAssignmentBinding() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-item-space-live-runtime-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = try Self.runtimeEnvironment()
        let databaseKey = try LedgerPowerSyncEncryptionKey(
            hexadecimal: String(repeating: "41", count: 32)
        )
        let location = try LedgerWorkspaceRuntimeIsolation.resolve(
            validatedEnvironment: environment,
            principalId: Self.principalId,
            accountId: Self.accountId,
            applicationSupportDirectory: root
        )
        var dependencies = LedgerPowerSyncLocalBootstrapDependencies.live
        dependencies.loadDatabaseKey = { _, _ in databaseKey }
        dependencies.loadMediaKeyBytes = { _, _ in Data(repeating: 0x64, count: 32) }
        dependencies.createDirectory = {
            try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
        }
        dependencies.now = { Self.acceptedAt }
        let runtime = try await LedgerPowerSyncLocalBootstrap.open(
            validatedEnvironment: environment,
            principalId: Self.principalId,
            accountId: Self.accountId,
            applicationSupportDirectory: root,
            dependencies: dependencies
        )
        let command = try Self.command(
            operation: "assignment-live-runtime-binding",
            spaceRevision: UInt64.max,
            items: [("item-live-runtime", UInt64.max)]
        )
        #expect(
            try await runtime.assignItemsToSpace(command) ==
                Self.queuedReceipt(command)
        )
        do {
            var iterator = runtime.watchItemSpaceAssignmentOperation(
                command.envelope.operationId
            ).makeAsyncIterator()
            let snapshot = try #require(try await iterator.next())
            #expect(snapshot.operationId == command.envelope.operationId)
            #expect(snapshot.accountId == Self.accountId)
            #expect(snapshot.contractVersion == command.envelope.contractVersion)
            #expect(snapshot.fingerprint == command.fingerprint)
            #expect(snapshot.acceptedAt == Self.acceptedAt)
            #expect(snapshot.updatedAt == Self.acceptedAt)
            guard case .queued(let attempts, let lastError) = snapshot.state else {
                Issue.record("Live runtime assignment watch was not queued")
                return
            }
            #expect(attempts == 0)
            #expect(lastError == nil)
        }
        let pending = try await runtime.pendingWorkSummary()
        #expect(pending.queuedOperationCount == 1)
        #expect(pending.applyingOperationCount == 0)
        #expect(pending.unresolvedRejectedOperationCount == 0)
        #expect(try await runtime.pendingUploadCount() == 0)
        try await runtime.close()

        let reopened = try LedgerPowerSyncDatabaseFactory.open(
            absolutePath: location.structuredDatabaseURL.path,
            encryptionKey: databaseKey
        )
        try await Self.expectCommandRow(command, database: reopened)
        try await Self.expectOperationRow(command, database: reopened)
        #expect(try await Self.count(Self.commandTable, reopened) == 1)
        #expect(try await Self.count(LedgerPowerSyncTable.localOperations, reopened) == 1)
        #expect(try await Self.count(LedgerPowerSyncTable.operationResults, reopened) == 0)
        #expect(try await reopened.get("SELECT count(*) FROM ps_crud") { try $0.getInt64(index: 0) } == 0)
        #expect(try await reopened.getNextCrudTransaction() == nil)
        try await reopened.close(deleteDatabase: true)
    }

    @Test("Provider diagnostics are finite and privacy bounded")
    func boundedDiagnostics() throws {
        let failures: [(ItemSpaceAssignmentPowerSyncStoreFailure, String)] = [
            (.invalidAcceptanceTime, "item_space_assignment_acceptance_time_invalid"),
            (.malformedLocalEvidence, "item_space_assignment_local_evidence_malformed"),
            (.operationNotFound, "item_space_assignment_operation_not_found")
        ]
        for (failure, code) in failures {
            #expect(failure.diagnosticCode == code)
            for secret in [
                Self.accountId.rawValue, Self.principalId.rawValue, "assignment-secret",
                "SELECT", "sqlite", "/tmp/", "credential", "token", "remote_success"
            ] {
                #expect(!failure.diagnosticCode.contains(secret))
            }
        }
    }

    private static let commandTable = "spike_item_space_assignment_commands"
    private static let accountId = try! AccountID(validating: "account-item-space")
    private static let principalId = try! PrincipalID(validating: "principal-item-space")
    private static let projectId = try! ProjectID(validating: "project-item-space")
    private static let acceptedAt = Date(timeIntervalSince1970: 1_800_000_000)

    private static func store(
        _ database: any PowerSyncDatabaseProtocol,
        now: @Sendable @escaping () -> Date = { acceptedAt }
    ) -> ItemSpaceAssignmentPowerSyncStore {
        ItemSpaceAssignmentPowerSyncStore(
            database: database,
            accountId: accountId,
            principalId: principalId,
            now: now
        )
    }

    private static func command(
        operation: String,
        accountId: AccountID = accountId,
        principalId: PrincipalID = principalId,
        scope: ItemPlacementScope = .project(projectId),
        destination: String = "space-item-space",
        capturedAt: Date = Date(timeIntervalSince1970: 1_799_999_999.123_456),
        spaceRevision: UInt64 = 12,
        items: [(String, UInt64)] = [("item-zeta", 9), ("item-alpha", 4)]
    ) throws -> AssignItemsToSpaceCommand {
        try AssignItemsToSpaceCommand(
            operationId: OperationID(validating: operation),
            draft: ItemSpaceAssignmentDraft(
                accountId: accountId,
                actorPrincipalId: principalId,
                operationContractVersion: OperationContractVersion(
                    validating: "item-space-assignment-v1"
                ),
                destinationSpaceId: SpaceID(validating: destination),
                scope: scope,
                expectedSpaceRevision: ExpectedSpaceRevision(spaceRevision),
                items: try items.map {
                    try ItemSpaceAssignmentCandidate(
                        itemId: ItemID(validating: $0.0),
                        expectedRevision: ExpectedItemPlacementRevision($0.1)
                    )
                },
                capturedAt: capturedAt
            )
        )
    }

    private static func queuedReceipt(_ command: AssignItemsToSpaceCommand) -> OperationReceipt {
        OperationReceipt(operationId: command.envelope.operationId, localState: .queued)
    }

    private static func json<Value: Encodable>(_ value: Value) -> String {
        String(decoding: try! OperationContractCodec.encode(value), as: UTF8.self)
    }

    private static func itemsJSON(_ command: AssignItemsToSpaceCommand) throws -> String {
        let payload = ItemSpaceAssignmentItemsEvidence(
            schemaVersion: "item_space_assignment_items_v1",
            items: command.draft.items.map {
                ItemSpaceAssignmentItemEvidence(
                    itemId: $0.itemId.rawValue,
                    expectedRevision: String($0.expectedRevision.rawValue)
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(payload), as: UTF8.self)
    }

    private static func expectCommandRow(
        _ command: AssignItemsToSpaceCommand,
        database: any PowerSyncDatabaseProtocol
    ) async throws {
        let id = command.envelope.operationId
        #expect(try await text("account_id", table: commandTable, id: id, database: database) == command.envelope.accountId.rawValue)
        #expect(try await text("actor_principal_id", table: commandTable, id: id, database: database) == command.envelope.actorPrincipalId.rawValue)
        #expect(try await text("contract_version", table: commandTable, id: id, database: database) == command.envelope.contractVersion.rawValue)
        #expect(try await text("destination_space_id", table: commandTable, id: id, database: database) == command.draft.destinationSpaceId.rawValue)
        switch command.draft.scope {
        case .project(let projectId):
            #expect(try await text("scope_kind", table: commandTable, id: id, database: database) == "project")
            #expect(try await optionalText("project_id", table: commandTable, id: id, database: database) == projectId.rawValue)
        case .businessInventory:
            #expect(try await text("scope_kind", table: commandTable, id: id, database: database) == "business_inventory")
            #expect(try await optionalText("project_id", table: commandTable, id: id, database: database) == nil)
        }
        #expect(try await text("expected_space_revision", table: commandTable, id: id, database: database) == String(command.draft.expectedSpaceRevision.rawValue))
        #expect(try await text("items_json", table: commandTable, id: id, database: database) == itemsJSON(command))
        #expect(try await text("fingerprint", table: commandTable, id: id, database: database) == command.fingerprint.sha256)
        #expect(try await text("command_json", table: commandTable, id: id, database: database) == json(command))
        #expect(try await integer("accepted_at_ms", table: commandTable, id: id, database: database) == 1_800_000_000_000)
    }

    private static func expectOperationRow(
        _ command: AssignItemsToSpaceCommand,
        database: any PowerSyncDatabaseProtocol
    ) async throws {
        let id = command.envelope.operationId
        #expect(try await text("account_id", table: LedgerPowerSyncTable.localOperations, id: id, database: database) == accountId.rawValue)
        #expect(try await text("actor_principal_id", table: LedgerPowerSyncTable.localOperations, id: id, database: database) == principalId.rawValue)
        #expect(try await text("contract_version", table: LedgerPowerSyncTable.localOperations, id: id, database: database) == command.envelope.contractVersion.rawValue)
        #expect(try await text("fingerprint", table: LedgerPowerSyncTable.localOperations, id: id, database: database) == command.fingerprint.sha256)
        #expect(try await text("subject_id", table: LedgerPowerSyncTable.localOperations, id: id, database: database) == command.draft.destinationSpaceId.rawValue)
        #expect(try await text("local_state", table: LedgerPowerSyncTable.localOperations, id: id, database: database) == "queued")
        #expect(try await integer("accepted_at_ms", table: LedgerPowerSyncTable.localOperations, id: id, database: database) == 1_800_000_000_000)
        #expect(try await integer("updated_at_ms", table: LedgerPowerSyncTable.localOperations, id: id, database: database) == 1_800_000_000_000)
        #expect(try await text("command_type", table: LedgerPowerSyncTable.localOperations, id: id, database: database) == "assign_items_to_space")
        #expect(try await text("command_expected_revision", table: LedgerPowerSyncTable.localOperations, id: id, database: database) == String(command.draft.expectedSpaceRevision.rawValue))
        #expect(try await text("command_envelope_json", table: LedgerPowerSyncTable.localOperations, id: id, database: database) == json(command.envelope))
        for column in [
            "terminal_phase", "terminal_result_code", "terminal_error_code",
            "terminal_envelope_sha256", "terminal_request_sha256",
            "terminal_server_received_at_ms", "terminal_completed_at_ms"
        ] {
            #expect(try await optionalText(column, table: LedgerPowerSyncTable.localOperations, id: id, database: database) == nil)
        }
    }

    private static func withAcceptedCommand(
        _ suffix: String,
        body: (
            AssignItemsToSpaceCommand,
            ItemSpaceAssignmentPowerSyncStore,
            any PowerSyncDatabaseProtocol
        ) async throws -> Void
    ) async throws {
        let fixture = try ItemSpaceAssignmentDatabaseFixture()
        defer { fixture.remove() }
        let database = try fixture.open()
        let command = try Self.command(operation: "assignment-\(suffix)")
        let store = Self.store(database)
        _ = try await store.assignItemsToSpace(command)
        do {
            try await body(command, store, database)
            try await database.close(deleteDatabase: true)
        } catch {
            try? await database.close(deleteDatabase: true)
            throw error
        }
    }

    private static func expectWatchFailure(
        _ expected: ItemSpaceAssignmentPowerSyncStoreFailure,
        store: ItemSpaceAssignmentPowerSyncStore,
        operationId: OperationID
    ) async {
        var iterator = store.watchOperation(operationId).makeAsyncIterator()
        await #expect(throws: expected) { _ = try await iterator.next() }
    }

    private static func text(
        _ column: String,
        table: String,
        id: OperationID,
        database: any PowerSyncDatabaseProtocol
    ) async throws -> String {
        try await database.get(
            sql: "SELECT \(column) FROM \(table) WHERE id = ?",
            parameters: [id.rawValue]
        ) { try $0.getString(index: 0) }
    }

    private static func optionalText(
        _ column: String,
        table: String,
        id: OperationID,
        database: any PowerSyncDatabaseProtocol
    ) async throws -> String? {
        try await database.get(
            sql: "SELECT \(column) FROM \(table) WHERE id = ?",
            parameters: [id.rawValue]
        ) { $0.getStringOptional(index: 0) }
    }

    private static func integer(
        _ column: String,
        table: String,
        id: OperationID,
        database: any PowerSyncDatabaseProtocol
    ) async throws -> Int64 {
        try await database.get(
            sql: "SELECT \(column) FROM \(table) WHERE id = ?",
            parameters: [id.rawValue]
        ) { try $0.getInt64(index: 0) }
    }

    private static func count(
        _ table: String,
        _ database: any PowerSyncDatabaseProtocol
    ) async throws -> Int64 {
        try await database.get("SELECT count(*) FROM \(table)") { try $0.getInt64(index: 0) }
    }

    private static func drainCRUD(_ database: any PowerSyncDatabaseProtocol) async throws {
        while let transaction = try await database.getNextCrudTransaction() {
            try await transaction.complete()
        }
    }

    private static func sameCheckpoint(
        _ lhs: ItemSpaceAssignmentPowerSyncStoreCheckpoint,
        _ rhs: ItemSpaceAssignmentPowerSyncStoreCheckpoint
    ) -> Bool {
        switch (lhs, rhs) {
        case (.beforeTransaction, .beforeTransaction),
             (.existingRead, .existingRead),
             (.commandWrite, .commandWrite),
             (.operationWrite, .operationWrite),
             (.beforeCommit, .beforeCommit),
             (.afterCommit, .afterCommit),
             (.watchConstruction, .watchConstruction),
             (.watchRead, .watchRead),
             (.watchIteration, .watchIteration):
            true
        default:
            false
        }
    }

    private static func runtimeEnvironment() throws -> ValidatedLedgerEnvironment {
        let versions = LedgerContractVersions(schema: "1", query: "1", operation: "1", sync: "1")
        let resources = Dictionary(uniqueKeysWithValues: LedgerTargetComponent.allCases.map {
            ($0, "item-space-runtime-\($0.rawValue)")
        })
        let manifest = LedgerEnvironmentManifest(
            environment: .targetLocal,
            buildProfile: .targetLocalDevelopment,
            bundleIdentifier: "apps.nine4.ledger.item-space-runtime-tests",
            displayName: "Ledger Item Space Runtime Tests",
            localDataNamespacePrefix: "apps.nine4.ledger.item-space-runtime-tests",
            contractVersions: versions,
            resources: LedgerTargetComponent.allCases.map {
                LedgerEnvironmentResource(
                    component: $0,
                    environment: .targetLocal,
                    publicIdentifier: resources[$0]!
                )
            }
        )
        return try LedgerEnvironmentValidator.validate(
            manifest,
            policy: LedgerEnvironmentPolicy(
                expectedEnvironment: .targetLocal,
                expectedBuildProfile: .targetLocalDevelopment,
                expectedBundleIdentifier: manifest.bundleIdentifier,
                expectedContractVersions: versions,
                allowedResourceIdentifiers: resources.mapValues { [$0] },
                forbiddenResourceIdentifiers: [],
                forbiddenBundleIdentifiers: []
            )
        )
    }
}

private struct ItemSpaceAssignmentItemsEvidence: Encodable {
    let schemaVersion: String
    let items: [ItemSpaceAssignmentItemEvidence]
}

private struct ItemSpaceAssignmentItemEvidence: Encodable {
    let itemId: String
    let expectedRevision: String
}

private struct ItemSpaceAssignmentInjectedFailure: Error {}

private enum ItemSpaceAssignmentRuntimeCloseEvent: Equatable, Sendable {
    case providerWatchAdmitted
    case providerWatchCancelled
    case providerDrainStarted
    case providerDrainCompleted
    case structuredDatabaseCloseAttempted
}

private final class ItemSpaceAssignmentRuntimeCloseProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [ItemSpaceAssignmentRuntimeCloseEvent] = []

    var values: [ItemSpaceAssignmentRuntimeCloseEvent] {
        lock.withLock { recorded }
    }

    func record(_ event: ItemSpaceAssignmentRuntimeCloseEvent) {
        lock.withLock { recorded.append(event) }
    }

    func waitUntil(_ event: ItemSpaceAssignmentRuntimeCloseEvent) async throws {
        for _ in 0..<1_000 {
            if lock.withLock({ recorded.contains(event) }) { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw ItemSpaceAssignmentInjectedFailure()
    }
}

private final class ItemSpaceAssignmentRuntimeStoreSpy:
    AccountWorkspaceItemSpaceAssignmentStoring,
    @unchecked Sendable
{
    private let lock = NSLock()
    private let probe: ItemSpaceAssignmentRuntimeCloseProbe
    private var continuations:
        [UUID: AsyncThrowingStream<OperationSnapshot, Error>.Continuation] = [:]
    private var submitted: [AssignItemsToSpaceCommand] = []

    var submittedCommands: [AssignItemsToSpaceCommand] {
        lock.withLock { submitted }
    }

    init(probe: ItemSpaceAssignmentRuntimeCloseProbe) {
        self.probe = probe
    }

    func assignItemsToSpace(
        _ command: AssignItemsToSpaceCommand
    ) async throws -> OperationReceipt {
        lock.withLock { submitted.append(command) }
        return OperationReceipt(
            operationId: command.envelope.operationId,
            localState: .queued
        )
    }

    func watchOperation(
        _ operationId: OperationID
    ) -> AsyncThrowingStream<OperationSnapshot, Error> {
        AsyncThrowingStream { continuation in
            let id = UUID()
            lock.withLock { continuations[id] = continuation }
            probe.record(.providerWatchAdmitted)
            continuation.onTermination = { [weak self] termination in
                guard let self else { return }
                _ = self.lock.withLock { self.continuations.removeValue(forKey: id) }
                if case .cancelled = termination {
                    self.probe.record(.providerWatchCancelled)
                }
            }
        }
    }

    func cancelAndDrainWatches() async {
        probe.record(.providerDrainStarted)
        let admitted = lock.withLock { Array(continuations.values) }
        for continuation in admitted { continuation.finish() }
        probe.record(.providerDrainCompleted)
    }
}

private final class ItemSpaceAssignmentCheckpointProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var observations = 0

    var count: Int { lock.withLock { observations } }

    func record() {
        lock.withLock { observations += 1 }
    }
}

private actor ItemSpaceAssignmentManualGate {
    private var entered = false
    private var released = false
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        entered = true
        let waiters = entryWaiters
        entryWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters { waiter.resume() }
        guard !released else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func release() {
        released = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters { waiter.resume() }
    }
}

private actor ItemSpaceAssignmentAsyncFlag {
    private var isSet = false
    var value: Bool { isSet }
    func set() { isSet = true }
}

private final class ItemSpaceAssignmentDatabaseFixture: @unchecked Sendable {
    let directoryURL: URL
    let databaseURL: URL
    private let key = try! LedgerPowerSyncEncryptionKey(
        hexadecimal: String(repeating: "6d", count: 32)
    )

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-item-space-assignment-\(UUID().uuidString)")
        databaseURL = directoryURL.appendingPathComponent("ledger.sqlite")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func open() throws -> any PowerSyncDatabaseProtocol {
        try LedgerPowerSyncDatabaseFactory.open(
            absolutePath: databaseURL.path,
            encryptionKey: key
        )
    }

    func remove() { try? FileManager.default.removeItem(at: directoryURL) }
}

private struct ItemSpaceAssignmentEmptyAttachmentObserver: AttachmentPendingWorkObserving {
    func pendingWorkObservation() async throws -> AttachmentPendingWorkObservation {
        AttachmentPendingWorkObservation(queue: [], orphans: [])
    }
}
