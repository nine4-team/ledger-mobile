import Foundation
import LedgerTargetCore
import PowerSync
import Testing
@testable import LedgerTargetPowerSync

// Frozen coverage: ITEMSPACECLEARLOCAL-TEST-001, ITEMSPACECLEARLOCAL-TEST-002,
// ITEMSPACECLEARLOCAL-TEST-003, ITEMSPACECLEARLOCAL-TEST-004,
// ITEMSPACECLEARLOCAL-TEST-005, ITEMSPACECLEARLOCAL-TEST-006,
// ITEMSPACECLEARLOCAL-TEST-007, ITEMSPACECLEARLOCAL-TEST-008,
// ITEMSPACECLEARLOCAL-TEST-009, ITEMSPACECLEARLOCAL-TEST-010,
// ITEMSPACECLEARLOCAL-TEST-011, ITEMSPACECLEARLOCAL-TEST-012,
// ITEMSPACECLEARLOCAL-TEST-013.
@Suite("Item-to-Space clearing local durability provider", .serialized)
struct ItemSpaceClearingPowerSyncStoreTests {
    @Test("Project and Business Inventory persist the exact two-row local contract")
    func exactProjectAndInventoryRows() async throws {
        let fixture = try ItemSpaceClearingDatabaseFixture()
        defer { fixture.remove() }
        let database = try fixture.open()
        try await Self.drainCRUD(database)

        let project = try Self.command(
            operation: "clearing-project",
            scope: .project(Self.projectId),
            items: [
                ("item-zeta", UInt64.max, "space-current-zeta"),
                ("item-alpha", UInt64(Int64.max) + 1, "space-current-alpha")
            ]
        )
        let inventory = try Self.command(
            operation: "clearing-inventory",
            scope: .businessInventory,
            items: [
                ("item-zero", 0, "space-current-zero"),
                ("item-signed-max", UInt64(Int64.max), "space-current-max")
            ]
        )
        let store = Self.store(database)

        #expect(try await store.clearItemSpaceAssignments(project) == Self.queuedReceipt(project))
        #expect(try await store.clearItemSpaceAssignments(inventory) == Self.queuedReceipt(inventory))
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
        let fixture = try ItemSpaceClearingDatabaseFixture()
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
                operation: "clearing-time-\(name)",
                capturedAt: capturedAt,
                items: [("item-\(name)", revision, "space-\(name)")]
            )
            let expectedCommand = Self.json(command)
            let expectedEnvelope = Self.json(command.envelope)
            _ = try await store.clearItemSpaceAssignments(command)
            #expect(try await Self.text("command_json", table: Self.commandTable, id: command.envelope.operationId, database: database) == expectedCommand)
            #expect(try await Self.text("command_envelope_json", table: LedgerPowerSyncTable.localOperations, id: command.envelope.operationId, database: database) == expectedEnvelope)
            #expect(try await Self.text("items_json", table: Self.commandTable, id: command.envelope.operationId, database: database) == Self.itemsJSON(command))
            #expect(try await store.clearItemSpaceAssignments(command) == Self.queuedReceipt(command))
            #expect(try Self.itemsJSON(command).contains(String(revision)))
            #expect(try await Self.optionalText("command_expected_revision", table: LedgerPowerSyncTable.localOperations, id: command.envelope.operationId, database: database) == nil)
        }
        try await database.close(deleteDatabase: true)
    }

    @Test("Provider time is narrowed only for new admission and never blocks exact replay")
    func providerTimeBoundaryAndPreDatabaseSentinel() async throws {
        let fixture = try ItemSpaceClearingDatabaseFixture()
        defer { fixture.remove() }
        let database = try fixture.open()
        let validProbe = ItemSpaceClearingCheckpointProbe()
        let valid = ItemSpaceClearingPowerSyncStore(
            database: database,
            accountId: Self.accountId,
            principalId: Self.principalId,
            now: { Date(timeIntervalSince1970: 1_234.567_89) },
            checkpoint: { checkpoint in
                if case .beforeTransaction = checkpoint { validProbe.record() }
            }
        )
        let validCommand = try Self.command(operation: "clearing-valid-provider-time")
        _ = try await valid.clearItemSpaceAssignments(validCommand)
        #expect(validProbe.count == 1)
        #expect(try await Self.integer("accepted_at_ms", table: Self.commandTable, id: validCommand.envelope.operationId, database: database) == 1_234_567)

        let replayClockProbe = ItemSpaceClearingCheckpointProbe()
        let replayReadProbe = ItemSpaceClearingCheckpointProbe()
        let invalidClockReplay = ItemSpaceClearingPowerSyncStore(
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
            try await invalidClockReplay.clearItemSpaceAssignments(validCommand) ==
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
            let readProbe = ItemSpaceClearingCheckpointProbe()
            let writeProbe = ItemSpaceClearingCheckpointProbe()
            let invalid = ItemSpaceClearingPowerSyncStore(
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
            await #expect(throws: ItemSpaceClearingPowerSyncStoreFailure.invalidAcceptanceTime) {
                _ = try await invalid.clearItemSpaceAssignments(
                    Self.command(operation: "clearing-invalid-provider-time-\(index)")
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
        let fixture = try ItemSpaceClearingDatabaseFixture()
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

        let safeCommand = try Self.command(operation: "clearing-safe-high-time")
        let safeStore = Self.store(database, now: { safeDate })
        #expect(
            try await safeStore.clearItemSpaceAssignments(safeCommand) ==
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

        let unsafeCommand = try Self.command(operation: "clearing-unsafe-high-time")
        let unsafeStore = Self.store(database, now: { unsafeDate })
        await #expect(throws: ItemSpaceClearingPowerSyncStoreFailure.invalidAcceptanceTime) {
            _ = try await unsafeStore.clearItemSpaceAssignments(unsafeCommand)
        }
        #expect(try await Self.count(Self.commandTable, database) == 1)
        #expect(try await Self.count(LedgerPowerSyncTable.localOperations, database) == 1)

        let malformedCommand = try Self.command(operation: "clearing-malformed-high-time")
        let malformedStore = Self.store(database)
        _ = try await malformedStore.clearItemSpaceAssignments(malformedCommand)
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
        await #expect(throws: ItemSpaceClearingPowerSyncStoreFailure.malformedLocalEvidence) {
            _ = try await malformedStore.clearItemSpaceAssignments(malformedCommand)
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
        let fixture = try ItemSpaceClearingDatabaseFixture()
        defer { fixture.remove() }
        let database = try fixture.open()
        let store = ItemSpaceClearingPowerSyncStore(
            database: database,
            accountId: Self.accountId,
            principalId: Self.principalId,
            now: { Self.acceptedAt },
            checkpoint: { checkpoint in
                if case .beforeTransaction = checkpoint {
                    throw ItemSpaceClearingInjectedFailure()
                }
            }
        )
        await #expect(throws: LedgerOfflineClientRuntimeFailure.accountScopeMismatch) {
            _ = try await store.clearItemSpaceAssignments(Self.command(
                operation: "clearing-foreign-account",
                accountId: try AccountID(validating: "account-foreign")
            ))
        }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.principalScopeMismatch) {
            _ = try await store.clearItemSpaceAssignments(Self.command(
                operation: "clearing-foreign-principal",
                principalId: try PrincipalID(validating: "principal-foreign")
            ))
        }
        await #expect(throws: ItemSpaceClearingFailure.localAcceptanceFailed) {
            _ = try await store.clearItemSpaceAssignments(
                Self.command(operation: "clearing-matching-scope-probe")
            )
        }
        #expect(try await Self.count(Self.commandTable, database) == 0)
        #expect(try await Self.count(LedgerPowerSyncTable.localOperations, database) == 0)
        try await database.close(deleteDatabase: true)
    }

    @Test("Encrypted close and repeated reopen retain exact evidence")
    func encryptedRestartRetention() async throws {
        let fixture = try ItemSpaceClearingDatabaseFixture()
        defer { fixture.remove() }
        let command = try Self.command(operation: "clearing-restart")
        let expectedCommand = Self.json(command)
        let expectedEnvelope = Self.json(command.envelope)

        var database = try fixture.open()
        _ = try await Self.store(database).clearItemSpaceAssignments(command)
        try await database.close(deleteDatabase: false)
        let encryptedBytes = try Data(contentsOf: fixture.databaseURL)
        #expect(!String(decoding: encryptedBytes, as: UTF8.self).contains(command.envelope.operationId.rawValue))

        for _ in 0..<2 {
            database = try fixture.open()
            #expect(try await Self.text("command_json", table: Self.commandTable, id: command.envelope.operationId, database: database) == expectedCommand)
            #expect(try await Self.text("command_envelope_json", table: LedgerPowerSyncTable.localOperations, id: command.envelope.operationId, database: database) == expectedEnvelope)
            #expect(try await Self.store(database).clearItemSpaceAssignments(command) == Self.queuedReceipt(command))
            try await database.close(deleteDatabase: false)
        }
        database = try fixture.open()
        try await database.close(deleteDatabase: true)
    }

    @Test("Partial evidence remains malformed across encrypted restart and never upgrades")
    func malformedRestartNeverUpgrades() async throws {
        let fixture = try ItemSpaceClearingDatabaseFixture()
        defer { fixture.remove() }
        let command = try Self.command(operation: "clearing-malformed-restart")
        var database = try fixture.open()
        _ = try await Self.store(database).clearItemSpaceAssignments(command)
        _ = try await database.execute(
            sql: "DELETE FROM \(LedgerPowerSyncTable.localOperations) WHERE id = ?",
            parameters: [command.envelope.operationId.rawValue]
        )
        try await database.close(deleteDatabase: false)

        for _ in 0..<2 {
            database = try fixture.open()
            await #expect(throws: ItemSpaceClearingPowerSyncStoreFailure.malformedLocalEvidence) {
                _ = try await Self.store(database).clearItemSpaceAssignments(command)
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
        let fixture = try ItemSpaceClearingDatabaseFixture()
        defer { fixture.remove() }
        let database = try fixture.open()
        let original = try Self.command(operation: "clearing-replay")
        let changed = try Self.command(
            operation: original.envelope.operationId.rawValue,
            items: [("item-zeta", 9, "space-changed"),
                    ("item-alpha", 4, "space-current-alpha")]
        )
        let store = Self.store(database)
        _ = try await store.clearItemSpaceAssignments(original)
        #expect(try await store.clearItemSpaceAssignments(original) == Self.queuedReceipt(original))
        do {
            _ = try await store.clearItemSpaceAssignments(changed)
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
            ("scope_kind", "wrong_scope"),
            ("project_id", "project-tampered"),
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
                await #expect(throws: ItemSpaceClearingPowerSyncStoreFailure.malformedLocalEvidence) {
                    _ = try await store.clearItemSpaceAssignments(command)
                }
                await Self.expectWatchFailure(
                    .malformedLocalEvidence,
                    store: store,
                    operationId: command.envelope.operationId
                )
                await store.cancelAndDrainWatches()
                #expect(try await Self.text(entry.0, table: Self.commandTable, id: command.envelope.operationId, database: database) == entry.1)
            }
        }
        for (index, column) in cases.map(\.0).enumerated() {
            try await Self.withAcceptedCommand("command-null-\(index)") { command, store, database in
                _ = try await database.execute(
                    sql: "UPDATE \(Self.commandTable) SET \(column) = NULL WHERE id = ?",
                    parameters: [command.envelope.operationId.rawValue]
                )
                await #expect(throws: ItemSpaceClearingPowerSyncStoreFailure.malformedLocalEvidence) {
                    _ = try await store.clearItemSpaceAssignments(command)
                }
                await Self.expectWatchFailure(
                    .malformedLocalEvidence,
                    store: store,
                    operationId: command.envelope.operationId
                )
                await store.cancelAndDrainWatches()
                #expect(try await Self.optionalText(column, table: Self.commandTable, id: command.envelope.operationId, database: database) == nil)
            }
        }
        try await Self.withAcceptedCommand(
            "inventory-project-id",
            scope: .businessInventory
        ) { command, store, database in
            _ = try await database.execute(
                sql: "UPDATE \(Self.commandTable) SET project_id = 'project-forbidden' WHERE id = ?",
                parameters: [command.envelope.operationId.rawValue]
            )
            await #expect(throws: ItemSpaceClearingPowerSyncStoreFailure.malformedLocalEvidence) {
                _ = try await store.clearItemSpaceAssignments(command)
            }
            await Self.expectWatchFailure(
                .malformedLocalEvidence,
                store: store,
                operationId: command.envelope.operationId
            )
            await store.cancelAndDrainWatches()
        }
        try await Self.withAcceptedCommand("orphan-command") { command, store, database in
            _ = try await database.execute(
                sql: "DELETE FROM \(Self.commandTable) WHERE id = ?",
                parameters: [command.envelope.operationId.rawValue]
            )
            await #expect(throws: ItemSpaceClearingPowerSyncStoreFailure.malformedLocalEvidence) {
                _ = try await store.clearItemSpaceAssignments(command)
            }
            await Self.expectWatchFailure(
                .malformedLocalEvidence,
                store: store,
                operationId: command.envelope.operationId
            )
            await store.cancelAndDrainWatches()
        }
        try await Self.withAcceptedCommand("orphan-operation") { command, store, database in
            _ = try await database.execute(
                sql: "DELETE FROM \(LedgerPowerSyncTable.localOperations) WHERE id = ?",
                parameters: [command.envelope.operationId.rawValue]
            )
            await #expect(throws: ItemSpaceClearingPowerSyncStoreFailure.malformedLocalEvidence) {
                _ = try await store.clearItemSpaceAssignments(command)
            }
            await Self.expectWatchFailure(
                .operationNotFound,
                store: store,
                operationId: command.envelope.operationId
            )
            await store.cancelAndDrainWatches()
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
            ("command_envelope_json", "{}")
        ]
        for (index, entry) in requiredCases.enumerated() {
            try await Self.withAcceptedCommand("operation-tamper-\(index)") { command, store, database in
                _ = try await database.execute(
                    sql: "UPDATE \(LedgerPowerSyncTable.localOperations) SET \(entry.0) = ? WHERE id = ?",
                    parameters: [entry.1, command.envelope.operationId.rawValue]
                )
                await #expect(throws: ItemSpaceClearingPowerSyncStoreFailure.malformedLocalEvidence) {
                    _ = try await store.clearItemSpaceAssignments(command)
                }
                let expectedWatchFailure: ItemSpaceClearingPowerSyncStoreFailure =
                    entry.0 == "account_id" || entry.0 == "actor_principal_id"
                        ? .operationNotFound
                        : .malformedLocalEvidence
                await Self.expectWatchFailure(
                    expectedWatchFailure,
                    store: store,
                    operationId: command.envelope.operationId
                )
                await store.cancelAndDrainWatches()
            }
        }
        for (index, column) in requiredCases.map(\.0).enumerated() {
            try await Self.withAcceptedCommand("operation-null-\(index)") { command, store, database in
                _ = try await database.execute(
                    sql: "UPDATE \(LedgerPowerSyncTable.localOperations) SET \(column) = NULL WHERE id = ?",
                    parameters: [command.envelope.operationId.rawValue]
                )
                await #expect(throws: ItemSpaceClearingPowerSyncStoreFailure.malformedLocalEvidence) {
                    _ = try await store.clearItemSpaceAssignments(command)
                }
                let expectedWatchFailure: ItemSpaceClearingPowerSyncStoreFailure =
                    column == "account_id" || column == "actor_principal_id"
                        ? .operationNotFound
                        : .malformedLocalEvidence
                await Self.expectWatchFailure(
                    expectedWatchFailure,
                    store: store,
                    operationId: command.envelope.operationId
                )
                await store.cancelAndDrainWatches()
            }
        }
        try await Self.withAcceptedCommand("unexpected-expected-revision") {
            command, store, database in
            _ = try await database.execute(
                sql: "UPDATE \(LedgerPowerSyncTable.localOperations) SET command_expected_revision = '1' WHERE id = ?",
                parameters: [command.envelope.operationId.rawValue]
            )
            await #expect(throws: ItemSpaceClearingPowerSyncStoreFailure.malformedLocalEvidence) {
                _ = try await store.clearItemSpaceAssignments(command)
            }
            await Self.expectWatchFailure(
                .malformedLocalEvidence,
                store: store,
                operationId: command.envelope.operationId
            )
            await store.cancelAndDrainWatches()
        }
        let terminalColumns = [
            "terminal_phase", "terminal_result_code", "terminal_error_code",
            "terminal_envelope_sha256", "terminal_request_sha256",
            "terminal_server_received_at_ms", "terminal_completed_at_ms"
        ]
        for (index, column) in terminalColumns.enumerated() {
            try await Self.withAcceptedCommand("terminal-tamper-\(index)") { command, store, database in
                if column.hasSuffix("_ms") {
                    _ = try await database.execute(
                        sql: "UPDATE \(LedgerPowerSyncTable.localOperations) SET \(column) = ? WHERE id = ?",
                        parameters: [Int64(1), command.envelope.operationId.rawValue]
                    )
                } else {
                    _ = try await database.execute(
                        sql: "UPDATE \(LedgerPowerSyncTable.localOperations) SET \(column) = ? WHERE id = ?",
                        parameters: ["terminal", command.envelope.operationId.rawValue]
                    )
                }
                await #expect(throws: ItemSpaceClearingPowerSyncStoreFailure.malformedLocalEvidence) {
                    _ = try await store.clearItemSpaceAssignments(command)
                }
                await Self.expectWatchFailure(
                    .malformedLocalEvidence,
                    store: store,
                    operationId: command.envelope.operationId
                )
                await store.cancelAndDrainWatches()
            }
        }
        try await Self.withAcceptedCommand("unexpected-result") { command, store, database in
            _ = try await database.execute(
                sql: "INSERT INTO \(LedgerPowerSyncTable.operationResults) (id) VALUES (?)",
                parameters: [command.envelope.operationId.rawValue]
            )
            await #expect(throws: ItemSpaceClearingPowerSyncStoreFailure.malformedLocalEvidence) {
                _ = try await store.clearItemSpaceAssignments(command)
            }
            await Self.expectWatchFailure(
                .malformedLocalEvidence,
                store: store,
                operationId: command.envelope.operationId
            )
            await store.cancelAndDrainWatches()
        }
    }

    @Test("Concurrent same-ID admission converges and conflicting payload has one winner")
    func concurrentAdmission() async throws {
        let fixture = try ItemSpaceClearingDatabaseFixture()
        defer { fixture.remove() }
        let database = try fixture.open()
        let store = Self.store(database)
        let command = try Self.command(operation: "clearing-concurrent-same")
        async let first = store.clearItemSpaceAssignments(command)
        async let second = store.clearItemSpaceAssignments(command)
        #expect(try await first == Self.queuedReceipt(command))
        #expect(try await second == Self.queuedReceipt(command))
        #expect(try await Self.count(Self.commandTable, database) == 1)

        let winner = try Self.command(operation: "clearing-concurrent-conflict")
        let challenger = try Self.command(
            operation: winner.envelope.operationId.rawValue,
            items: [("item-zeta", 9, "space-concurrent-other"),
                    ("item-alpha", 4, "space-current-alpha")]
        )
        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            group.addTask { (try? await store.clearItemSpaceAssignments(winner)) != nil }
            group.addTask { (try? await store.clearItemSpaceAssignments(challenger)) != nil }
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
        #expect(try await store.clearItemSpaceAssignments(accepted) == Self.queuedReceipt(accepted))
        do {
            _ = try await store.clearItemSpaceAssignments(refused)
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
        let checkpoints: [ItemSpaceClearingPowerSyncStoreCheckpoint] = [
            .beforeTransaction, .inventoryConstruction, .inventoryRead,
            .afterOwnershipInspection, .existingRead, .commandWrite,
            .operationWrite, .beforeCommit
        ]
        for (index, failingCheckpoint) in checkpoints.enumerated() {
            let fixture = try ItemSpaceClearingDatabaseFixture()
            let database = try fixture.open()
            let store = ItemSpaceClearingPowerSyncStore(
                database: database,
                accountId: Self.accountId,
                principalId: Self.principalId,
                now: { Self.acceptedAt },
                checkpoint: { checkpoint in
                    if Self.sameCheckpoint(checkpoint, failingCheckpoint) {
                        throw ItemSpaceClearingInjectedFailure()
                    }
                }
            )
            await #expect(throws: ItemSpaceClearingFailure.localAcceptanceFailed) {
                _ = try await store.clearItemSpaceAssignments(
                    Self.command(operation: "clearing-write-failure-\(index)")
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
        let fixture = try ItemSpaceClearingDatabaseFixture()
        defer { fixture.remove() }
        let database = try fixture.open()
        let preCommit = ItemSpaceClearingPowerSyncStore(
            database: database,
            accountId: Self.accountId,
            principalId: Self.principalId,
            now: { Self.acceptedAt },
            checkpoint: { checkpoint in
                if case .beforeCommit = checkpoint { throw CancellationError() }
            }
        )
        await #expect(throws: CancellationError.self) {
            _ = try await preCommit.clearItemSpaceAssignments(
                Self.command(operation: "clearing-cancel-precommit")
            )
        }
        #expect(try await Self.count(Self.commandTable, database) == 0)
        #expect(try await Self.count(LedgerPowerSyncTable.localOperations, database) == 0)

        let postCommitCommand = try Self.command(operation: "clearing-cancel-postcommit")
        let postCommit = ItemSpaceClearingPowerSyncStore(
            database: database,
            accountId: Self.accountId,
            principalId: Self.principalId,
            now: { Self.acceptedAt },
            checkpoint: { checkpoint in
                if case .afterCommit = checkpoint { throw CancellationError() }
            }
        )
        await #expect(throws: CancellationError.self) {
            _ = try await postCommit.clearItemSpaceAssignments(postCommitCommand)
        }
        #expect(try await Self.count(Self.commandTable, database) == 1)
        #expect(try await Self.count(LedgerPowerSyncTable.localOperations, database) == 1)
        #expect(try await Self.store(database).clearItemSpaceAssignments(postCommitCommand) == Self.queuedReceipt(postCommitCommand))
        try await database.close(deleteDatabase: true)
    }

    @Test("Queued-only watch is exact, scoped, and drains")
    func queuedOnlyWatchAndDrainage() async throws {
        let fixture = try ItemSpaceClearingDatabaseFixture()
        defer { fixture.remove() }
        let database = try fixture.open()
        let command = try Self.command(operation: "opaque.run:42")
        let otherCommand = try Self.command(
            operation: "other-operation",
            items: [("item-zeta", 99, "space-other-operation")]
        )
        let store = Self.store(database)
        _ = try await store.clearItemSpaceAssignments(command)
        _ = try await store.clearItemSpaceAssignments(otherCommand)
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
            Issue.record("Clearing watch emitted a non-queued state")
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
        let checkpoints: [ItemSpaceClearingPowerSyncStoreCheckpoint] = [
            .watchConstruction, .watchRead, .watchIteration
        ]
        for (index, failingCheckpoint) in checkpoints.enumerated() {
            let fixture = try ItemSpaceClearingDatabaseFixture()
            let database = try fixture.open()
            let command = try Self.command(operation: "clearing-watch-failure-\(index)")
            _ = try await Self.store(database).clearItemSpaceAssignments(command)
            let store = ItemSpaceClearingPowerSyncStore(
                database: database,
                accountId: Self.accountId,
                principalId: Self.principalId,
                now: { Self.acceptedAt },
                checkpoint: { checkpoint in
                    if Self.sameCheckpoint(checkpoint, failingCheckpoint) {
                        throw ItemSpaceClearingInjectedFailure()
                    }
                }
            )
            var iterator = store.watchOperation(command.envelope.operationId).makeAsyncIterator()
            await #expect(throws: ItemSpaceClearingFailure.localAcceptanceFailed) {
                _ = try await iterator.next()
            }
            await store.cancelAndDrainWatches()
            try await database.close(deleteDatabase: true)
            fixture.remove()
        }

        let fixture = try ItemSpaceClearingDatabaseFixture()
        let database = try fixture.open()
        let command = try Self.command(operation: "clearing-watch-cancellation")
        _ = try await Self.store(database).clearItemSpaceAssignments(command)
        let cancelling = ItemSpaceClearingPowerSyncStore(
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
        let fixture = try ItemSpaceClearingDatabaseFixture()
        defer { fixture.remove() }
        let database = try fixture.open()
        let missing = try OperationID(validating: "clearing-watch-missing")
        let store = Self.store(database)
        await Self.expectWatchFailure(.operationNotFound, store: store, operationId: missing)

        let command = try Self.command(operation: "clearing-watch-malformed")
        _ = try await store.clearItemSpaceAssignments(command)
        _ = try await database.execute(
            sql: "UPDATE \(LedgerPowerSyncTable.localOperations) SET local_state = 'applying' WHERE id = ?",
            parameters: [command.envelope.operationId.rawValue]
        )
        await Self.expectWatchFailure(.malformedLocalEvidence, store: store, operationId: command.envelope.operationId)

        let foreign = try Self.command(operation: "clearing-watch-foreign")
        _ = try await store.clearItemSpaceAssignments(foreign)
        _ = try await database.execute(
            sql: "UPDATE \(LedgerPowerSyncTable.localOperations) SET account_id = 'account-foreign' WHERE id = ?",
            parameters: [foreign.envelope.operationId.rawValue]
        )
        await Self.expectWatchFailure(.operationNotFound, store: store, operationId: foreign.envelope.operationId)

        let foreignPrincipal = try Self.command(
            operation: "clearing-watch-foreign-principal"
        )
        _ = try await store.clearItemSpaceAssignments(foreignPrincipal)
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

    @Test("Pending summary counts the local clearing once and ps_crud remains empty")
    func pendingSummaryAndNoUploadWork() async throws {
        let fixture = try ItemSpaceClearingDatabaseFixture()
        defer { fixture.remove() }
        let database = try fixture.open()
        try await Self.drainCRUD(database)
        let command = try Self.command(operation: "clearing-pending-summary")
        _ = try await Self.store(database).clearItemSpaceAssignments(command)
        let query = PendingWorkPowerSyncQuery(
            database: database,
            attachmentObserver: ItemSpaceClearingEmptyAttachmentObserver(),
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

    @Test("Runtime close drains admitted clearing work and refuses later facade calls")
    func runtimeCloseDrainageAndTerminalRefusal() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-item-space-runtime-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let finiteGate = ItemSpaceClearingManualGate()
        let closeCompleted = ItemSpaceClearingAsyncFlag()
        let closeProbe = ItemSpaceClearingRuntimeCloseProbe()
        let clearingStore = ItemSpaceClearingRuntimeStoreSpy(probe: closeProbe)
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
            if operation == .clearItemSpaceAssignments { await finiteGate.wait() }
        }
        dependencies.makeItemSpaceClearingStore = { _, _, _, _ in
            clearingStore
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
        let command = try Self.command(operation: "clearing-runtime-close")
        let submission = Task { try await runtime.clearItemSpaceAssignments(command) }
        await finiteGate.waitUntilEntered()
        let consumer = Task {
            do {
                for try await _ in runtime.watchItemSpaceClearingOperation(
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
            _ = try await runtime.clearItemSpaceAssignments(command)
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
            _ = try await runtime.clearItemSpaceAssignments(command)
        }
        var closed = runtime.watchItemSpaceClearingOperation(
            command.envelope.operationId
        ).makeAsyncIterator()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await closed.next()
        }
    }

    @Test("Runtime nominally satisfies the clearing use-case port")
    func runtimeItemSpaceClearingUseCaseIntegration() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-item-space-use-case-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let clearingStore = ItemSpaceClearingRuntimeStoreSpy(
            probe: ItemSpaceClearingRuntimeCloseProbe()
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
        dependencies.makeItemSpaceClearingStore = { _, _, _, _ in clearingStore }
        let runtime = try await LedgerPowerSyncLocalBootstrap.open(
            validatedEnvironment: Self.runtimeEnvironment(),
            principalId: Self.principalId,
            accountId: Self.accountId,
            applicationSupportDirectory: root,
            dependencies: dependencies
        )
        let scope = ItemPlacementScope.project(Self.projectId)
        let intent = ItemSpaceClearingIntent(
            accountId: Self.accountId,
            scope: scope,
            items: [try ItemSpaceClearingCandidate(
                itemId: ItemID(validating: "item-use-case-runtime"),
                expectedRevision: ExpectedItemPlacementRevision(UInt64.max),
                currentSpaceId: SpaceID(validating: "space-use-case-runtime")
            )]
        )
        let operationId = try OperationID(validating: "clearing-use-case-runtime")
        let receipt = try await ItemSpaceClearingUseCase(clearer: runtime).execute(
            input: intent,
            operationId: operationId,
            actorPrincipalId: Self.principalId,
            operationContractVersion: OperationContractVersion(
                validating: "item-space-clearing-v1"
            ),
            capturedAt: Date(timeIntervalSince1970: -1_234.567_89)
        )
        #expect(receipt == OperationReceipt(operationId: operationId, localState: .queued))
        let submitted = clearingStore.submittedCommands
        #expect(submitted.count == 1)
        let command = try #require(submitted.first)
        #expect(command.envelope.operationId == operationId)
        #expect(command.draft.items == intent.items)
        try await runtime.close()
    }

    @Test("Live runtime factory binds clearing evidence to its structured workspace")
    func liveRuntimeItemSpaceClearingBinding() async throws {
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
            operation: "clearing-live-runtime-binding",
            items: [("item-live-runtime", UInt64.max, "space-live-runtime")]
        )
        #expect(
            try await runtime.clearItemSpaceAssignments(command) ==
                Self.queuedReceipt(command)
        )
        do {
            var iterator = runtime.watchItemSpaceClearingOperation(
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
                Issue.record("Live runtime clearing watch was not queued")
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
        let failures: [(ItemSpaceClearingPowerSyncStoreFailure, String)] = [
            (.invalidAcceptanceTime, "item_space_clearing_acceptance_time_invalid"),
            (.malformedLocalEvidence, "item_space_clearing_local_evidence_malformed"),
            (.operationNotFound, "item_space_clearing_operation_not_found")
        ]
        for (failure, code) in failures {
            #expect(failure.diagnosticCode == code)
            for secret in [
                Self.accountId.rawValue, Self.principalId.rawValue, "clearing-secret",
                "SELECT", "sqlite", "/tmp/", "credential", "token", "remote_success"
            ] {
                #expect(!failure.diagnosticCode.contains(secret))
            }
        }
    }

    private static let commandTable = "spike_item_space_clearing_commands"
    private static let accountId = try! AccountID(validating: "account-item-space")
    private static let principalId = try! PrincipalID(validating: "principal-item-space")
    private static let projectId = try! ProjectID(validating: "project-item-space")
    private static let acceptedAt = Date(timeIntervalSince1970: 1_800_000_000)

    private static func store(
        _ database: any PowerSyncDatabaseProtocol,
        now: @Sendable @escaping () -> Date = { acceptedAt }
    ) -> ItemSpaceClearingPowerSyncStore {
        ItemSpaceClearingPowerSyncStore(
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
        capturedAt: Date = Date(timeIntervalSince1970: 1_799_999_999.123_456),
        items: [(String, UInt64, String)] = [
            ("item-zeta", 9, "space-current-zeta"),
            ("item-alpha", 4, "space-current-alpha")
        ]
    ) throws -> ClearItemSpaceAssignmentsCommand {
        try ClearItemSpaceAssignmentsCommand(
            operationId: OperationID(validating: operation),
            draft: ItemSpaceClearingDraft(
                accountId: accountId,
                actorPrincipalId: principalId,
                operationContractVersion: OperationContractVersion(
                    validating: "item-space-clearing-v1"
                ),
                scope: scope,
                items: try items.map {
                    try ItemSpaceClearingCandidate(
                        itemId: ItemID(validating: $0.0),
                        expectedRevision: ExpectedItemPlacementRevision($0.1),
                        currentSpaceId: SpaceID(validating: $0.2)
                    )
                },
                capturedAt: capturedAt
            )
        )
    }

    private static func queuedReceipt(_ command: ClearItemSpaceAssignmentsCommand) -> OperationReceipt {
        OperationReceipt(operationId: command.envelope.operationId, localState: .queued)
    }

    private static func json<Value: Encodable>(_ value: Value) -> String {
        String(decoding: try! OperationContractCodec.encode(value), as: UTF8.self)
    }

    private static func itemsJSON(_ command: ClearItemSpaceAssignmentsCommand) throws -> String {
        let payload = ItemSpaceClearingItemsEvidence(
            schemaVersion: "item_space_clearing_items_v1",
            items: command.draft.items.map {
                ItemSpaceClearingItemEvidence(
                    itemId: $0.itemId.rawValue,
                    expectedRevision: String($0.expectedRevision.rawValue),
                    currentSpaceId: $0.currentSpaceId.rawValue
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(payload), as: UTF8.self)
    }

    private static func expectCommandRow(
        _ command: ClearItemSpaceAssignmentsCommand,
        database: any PowerSyncDatabaseProtocol
    ) async throws {
        let id = command.envelope.operationId
        #expect(try await text("account_id", table: commandTable, id: id, database: database) == command.envelope.accountId.rawValue)
        #expect(try await text("actor_principal_id", table: commandTable, id: id, database: database) == command.envelope.actorPrincipalId.rawValue)
        #expect(try await text("contract_version", table: commandTable, id: id, database: database) == command.envelope.contractVersion.rawValue)
        switch command.draft.scope {
        case .project(let projectId):
            #expect(try await text("scope_kind", table: commandTable, id: id, database: database) == "project")
            #expect(try await optionalText("project_id", table: commandTable, id: id, database: database) == projectId.rawValue)
        case .businessInventory:
            #expect(try await text("scope_kind", table: commandTable, id: id, database: database) == "business_inventory")
            #expect(try await optionalText("project_id", table: commandTable, id: id, database: database) == nil)
        }
        #expect(try await text("items_json", table: commandTable, id: id, database: database) == itemsJSON(command))
        #expect(try await text("fingerprint", table: commandTable, id: id, database: database) == command.fingerprint.sha256)
        #expect(try await text("command_json", table: commandTable, id: id, database: database) == json(command))
        #expect(try await integer("accepted_at_ms", table: commandTable, id: id, database: database) == 1_800_000_000_000)
    }

    private static func expectOperationRow(
        _ command: ClearItemSpaceAssignmentsCommand,
        database: any PowerSyncDatabaseProtocol
    ) async throws {
        let id = command.envelope.operationId
        #expect(try await text("account_id", table: LedgerPowerSyncTable.localOperations, id: id, database: database) == accountId.rawValue)
        #expect(try await text("actor_principal_id", table: LedgerPowerSyncTable.localOperations, id: id, database: database) == principalId.rawValue)
        #expect(try await text("contract_version", table: LedgerPowerSyncTable.localOperations, id: id, database: database) == command.envelope.contractVersion.rawValue)
        #expect(try await text("fingerprint", table: LedgerPowerSyncTable.localOperations, id: id, database: database) == command.fingerprint.sha256)
        #expect(try await text("subject_id", table: LedgerPowerSyncTable.localOperations, id: id, database: database) == command.subject.id.rawValue)
        #expect(try await text("local_state", table: LedgerPowerSyncTable.localOperations, id: id, database: database) == "queued")
        #expect(try await integer("accepted_at_ms", table: LedgerPowerSyncTable.localOperations, id: id, database: database) == 1_800_000_000_000)
        #expect(try await integer("updated_at_ms", table: LedgerPowerSyncTable.localOperations, id: id, database: database) == 1_800_000_000_000)
        #expect(try await text("command_type", table: LedgerPowerSyncTable.localOperations, id: id, database: database) == "clear_item_space_assignments")
        #expect(try await optionalText("command_expected_revision", table: LedgerPowerSyncTable.localOperations, id: id, database: database) == nil)
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
        scope: ItemPlacementScope = .project(projectId),
        body: (
            ClearItemSpaceAssignmentsCommand,
            ItemSpaceClearingPowerSyncStore,
            any PowerSyncDatabaseProtocol
        ) async throws -> Void
    ) async throws {
        let fixture = try ItemSpaceClearingDatabaseFixture()
        defer { fixture.remove() }
        let database = try fixture.open()
        let command = try Self.command(
            operation: "clearing-\(suffix)",
            scope: scope
        )
        let store = Self.store(database)
        _ = try await store.clearItemSpaceAssignments(command)
        do {
            try await body(command, store, database)
            try await database.close(deleteDatabase: true)
        } catch {
            try? await database.close(deleteDatabase: true)
            throw error
        }
    }

    private static func expectWatchFailure(
        _ expected: ItemSpaceClearingPowerSyncStoreFailure,
        store: ItemSpaceClearingPowerSyncStore,
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
        _ lhs: ItemSpaceClearingPowerSyncStoreCheckpoint,
        _ rhs: ItemSpaceClearingPowerSyncStoreCheckpoint
    ) -> Bool {
        switch (lhs, rhs) {
        case (.beforeTransaction, .beforeTransaction),
             (.inventoryConstruction, .inventoryConstruction),
             (.inventoryRead, .inventoryRead),
             (.afterOwnershipInspection, .afterOwnershipInspection),
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

private struct ItemSpaceClearingItemsEvidence: Encodable {
    let schemaVersion: String
    let items: [ItemSpaceClearingItemEvidence]
}

private struct ItemSpaceClearingItemEvidence: Encodable {
    let itemId: String
    let expectedRevision: String
    let currentSpaceId: String
}

private struct ItemSpaceClearingInjectedFailure: Error {}

private enum ItemSpaceClearingRuntimeCloseEvent: Equatable, Sendable {
    case providerWatchAdmitted
    case providerWatchCancelled
    case providerDrainStarted
    case providerDrainCompleted
    case structuredDatabaseCloseAttempted
}

private final class ItemSpaceClearingRuntimeCloseProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [ItemSpaceClearingRuntimeCloseEvent] = []

    var values: [ItemSpaceClearingRuntimeCloseEvent] {
        lock.withLock { recorded }
    }

    func record(_ event: ItemSpaceClearingRuntimeCloseEvent) {
        lock.withLock { recorded.append(event) }
    }

    func waitUntil(_ event: ItemSpaceClearingRuntimeCloseEvent) async throws {
        for _ in 0..<1_000 {
            if lock.withLock({ recorded.contains(event) }) { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw ItemSpaceClearingInjectedFailure()
    }
}

private final class ItemSpaceClearingRuntimeStoreSpy:
    AccountWorkspaceItemSpaceClearingStoring,
    @unchecked Sendable
{
    private let lock = NSLock()
    private let probe: ItemSpaceClearingRuntimeCloseProbe
    private var continuations:
        [UUID: AsyncThrowingStream<OperationSnapshot, Error>.Continuation] = [:]
    private var submitted: [ClearItemSpaceAssignmentsCommand] = []

    var submittedCommands: [ClearItemSpaceAssignmentsCommand] {
        lock.withLock { submitted }
    }

    init(probe: ItemSpaceClearingRuntimeCloseProbe) {
        self.probe = probe
    }

    func clearItemSpaceAssignments(
        _ command: ClearItemSpaceAssignmentsCommand
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

private final class ItemSpaceClearingCheckpointProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var observations = 0

    var count: Int { lock.withLock { observations } }

    func record() {
        lock.withLock { observations += 1 }
    }
}

private actor ItemSpaceClearingManualGate {
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

private actor ItemSpaceClearingAsyncFlag {
    private var isSet = false
    var value: Bool { isSet }
    func set() { isSet = true }
}

private final class ItemSpaceClearingDatabaseFixture: @unchecked Sendable {
    let directoryURL: URL
    let databaseURL: URL
    private let key = try! LedgerPowerSyncEncryptionKey(
        hexadecimal: String(repeating: "6d", count: 32)
    )

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-item-space-clearing-\(UUID().uuidString)")
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

private struct ItemSpaceClearingEmptyAttachmentObserver: AttachmentPendingWorkObserving {
    func pendingWorkObservation() async throws -> AttachmentPendingWorkObservation {
        AttachmentPendingWorkObservation(queue: [], orphans: [])
    }
}
