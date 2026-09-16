import Foundation
import LedgerTargetCore
@testable import LedgerTargetPowerSync
import PowerSync
import Testing

private struct LocalOperationGuardInjectedFailure: Error {}

@Suite("Global local OperationID ownership guard", .serialized)
struct LocalOperationIdentityGuardTests {
    // Frozen coverage: LOCALOPID-TEST-001, LOCALOPID-TEST-002,
    // LOCALOPID-TEST-003, LOCALOPID-TEST-004, LOCALOPID-TEST-005,
    // LOCALOPID-TEST-006, LOCALOPID-TEST-007, LOCALOPID-TEST-008,
    // LOCALOPID-TEST-009, LOCALOPID-TEST-010, LOCALOPID-TEST-011,
    // LOCALOPID-TEST-012.

    @Test("Inventory is exact and insert-only commands have only one ps_crud representation")
    func exactInventoryAndInsertOnlyRepresentation() async throws {
        #expect(LocalOperationIdentityGuard.commandFamilies == LocalOperationCommandFamily.allCases)
        #expect(Set(LocalOperationIdentityGuard.operationBearingRelations) == Set([
            LedgerPowerSyncTable.localOperations, LedgerPowerSyncTable.operationResults,
            LedgerPowerSyncTable.pendingClients, LedgerPowerSyncTable.pendingProjects,
            LedgerPowerSyncTable.pendingProjectCategoryAllocations,
            LedgerPowerSyncTable.projectArchiveOverlays,
            LedgerPowerSyncTable.clientArchiveOverlays,
            LedgerPowerSyncTable.spaceChecklistRevisionOverlays,
            LedgerPowerSyncTable.itemSpaceAssignmentCommands,
            LedgerPowerSyncTable.itemSpaceClearingCommands
        ]))
        #expect(LocalOperationIdentityGuard.insertOnlyCommandTables == [
            LedgerPowerSyncTable.clientCommands, LedgerPowerSyncTable.projectCommands,
            LedgerPowerSyncTable.projectArchiveCommands,
            LedgerPowerSyncTable.clientArchiveCommands,
            LedgerPowerSyncTable.spaceChecklistRevisionCommands,
            LedgerPowerSyncTable.categoryCommands,
            LedgerPowerSyncTable.inventorySaleCommands,
            LedgerPowerSyncTable.expenseCommands,
            LedgerPowerSyncTable.invoiceCommands
        ])
        #expect(LocalOperationIdentityGuard.forbiddenMutationTables == [
            LedgerPowerSyncTable.operationResults
        ])

        for family in LocalOperationCommandFamily.allCases where family.insertOnlyCommandTable != nil {
            let fixture = try LocalOperationGuardDatabaseFixture()
            defer { fixture.remove() }
            let database = try fixture.open()
            try await Self.insertCommand(family, id: "representation", database: database)
            #expect(try await Self.count("ps_crud", database) == 1)
            #expect(try await Self.count(family.insertOnlyCommandTable!, database) == 0)
            let type = try await database.get(
                "SELECT json_extract(data, '$.type') FROM ps_crud"
            ) { try $0.getString(index: 0) }
            #expect(type == family.insertOnlyCommandTable)
            try await database.close(deleteDatabase: true)
        }
    }

    @Test("Every ordered family pair uses OperationID alone and equal hashes never rebind")
    func orderedFamilyMatrix() async throws {
        for source in LocalOperationCommandFamily.allCases {
            let fixture = try LocalOperationGuardDatabaseFixture()
            defer { fixture.remove() }
            let database = try fixture.open()
            let id = try OperationID(validating: "ordered-\(source.rawValue)")
            try await Self.seedComplete(source, id: id.rawValue, database: database)
            for destination in LocalOperationCommandFamily.allCases {
                if destination == source {
                    let value = try await Self.inspect(
                        database, id: id, family: destination, fingerprint: Self.fingerprint
                    )
                    #expect(value == .matchingOwner)
                } else {
                    await #expect(throws: LocalOperationIdentityGuardFailure.payloadMismatch) {
                        _ = try await Self.inspect(
                            database, id: id, family: destination,
                            fingerprint: Self.fingerprint
                        )
                    }
                }
            }
            try await database.close(deleteDatabase: true)
        }
    }

    @Test("Every isolated relation and command-only graph reserves the ID")
    func orphanInventoryMatrix() async throws {
        for source in LocalOperationCommandFamily.allCases {
            let fixture = try LocalOperationGuardDatabaseFixture()
            defer { fixture.remove() }
            let database = try fixture.open()
            let id = "orphan-\(source.rawValue)"
            try await Self.insertCommand(source, id: id, database: database)
            for destination in LocalOperationCommandFamily.allCases {
                await #expect(throws: LocalOperationIdentityGuardFailure.malformedEvidence) {
                    _ = try await Self.inspect(
                        database,
                        id: OperationID(validating: id),
                        family: destination,
                        fingerprint: Self.fingerprint
                    )
                }
            }
            #expect(try await Self.count(LedgerPowerSyncTable.localOperations, database) == 0)
            try await database.close(deleteDatabase: true)
        }

        for relation in ["pending_client", "pending_project", "pending_allocation",
                         "project_overlay", "client_overlay", "result_mutation",
                         "result_mutation_queue"] {
            let fixture = try LocalOperationGuardDatabaseFixture()
            defer { fixture.remove() }
            let database = try fixture.open()
            let id = try OperationID(validating: "orphan-\(relation)")
            try await Self.insertIsolatedRelation(relation, id: id.rawValue, database: database)
            for destination in LocalOperationCommandFamily.allCases {
                await #expect(throws: LocalOperationIdentityGuardFailure.malformedEvidence) {
                    _ = try await Self.inspect(
                        database, id: id, family: destination,
                        fingerprint: Self.fingerprint
                    )
                }
            }
            #expect(try await Self.count(LedgerPowerSyncTable.localOperations, database) == 0)
            try await database.close(deleteDatabase: true)
        }

        let malformedFixture = try LocalOperationGuardDatabaseFixture()
        let malformedDatabase = try malformedFixture.open()
        let malformedID = try OperationID(validating: "orphan-invalid-json")
        try await Self.insertCommand(
            .createClient, id: malformedID.rawValue, database: malformedDatabase
        )
        _ = try await malformedDatabase.execute(
            "UPDATE ps_crud SET data = substr(data, 1, length(data) - 1)"
        )
        for destination in LocalOperationCommandFamily.allCases {
            await #expect(throws: LocalOperationIdentityGuardFailure.malformedEvidence) {
                _ = try await Self.inspect(
                    malformedDatabase, id: malformedID, family: destination,
                    fingerprint: Self.fingerprint
                )
            }
        }
        #expect(try await Self.count(
            LedgerPowerSyncTable.localOperations, malformedDatabase
        ) == 0)
        try await malformedDatabase.close(deleteDatabase: true)
        malformedFixture.remove()

        for isolatedKind in ["operation", "synchronized_result"] {
            let fixture = try LocalOperationGuardDatabaseFixture()
            let database = try fixture.open()
            let id = try OperationID(validating: "orphan-\(isolatedKind)")
            if isolatedKind == "operation" {
                try await Self.insertOperation(
                    .createClient, id: id.rawValue, state: "queued", typed: true,
                    database: database
                )
            } else {
                try await Self.insertSynchronizedResult(
                    id: id.rawValue, database: database
                )
            }
            for destination in LocalOperationCommandFamily.allCases {
                await #expect(throws: LocalOperationIdentityGuardFailure.malformedEvidence) {
                    _ = try await Self.inspect(
                        database, id: id, family: destination,
                        fingerprint: Self.fingerprint
                    )
                }
            }
            #expect(try await Self.count("ps_crud", database) == 0)
            try await database.close(deleteDatabase: true)
            fixture.remove()
        }

        for corruption in ["unknown_type", "malformed_envelope", "foreign_scope",
                           "multiple_family"] {
            let fixture = try LocalOperationGuardDatabaseFixture()
            let database = try fixture.open()
            let id = try OperationID(validating: "corrupt-\(corruption)")
            try await Self.seedComplete(
                .createClient, id: id.rawValue, database: database
            )
            switch corruption {
            case "unknown_type":
                _ = try await database.execute(
                    sql: "UPDATE ps_crud SET data = json_remove(json_set(data, '$.type', 'spike_future_commands'), '$.data.actor_principal_id') WHERE json_extract(data, '$.id') = ?",
                    parameters: [id.rawValue]
                )
            case "malformed_envelope":
                _ = try await database.execute(
                    sql: "UPDATE \(LedgerPowerSyncTable.localOperations) SET command_envelope_json = '{' WHERE id = ?",
                    parameters: [id.rawValue]
                )
                _ = try await database.execute(
                    sql: "UPDATE ps_crud SET data = json_set(data, '$.data.envelope_json', '{') WHERE json_extract(data, '$.id') = ?",
                    parameters: [id.rawValue]
                )
            case "foreign_scope":
                _ = try await database.execute(
                    sql: "UPDATE \(LedgerPowerSyncTable.pendingClients) SET account_id = 'foreign-account' WHERE operation_id = ?",
                    parameters: [id.rawValue]
                )
            default:
                try await Self.insertCommand(
                    .createProject, id: id.rawValue, database: database
                )
            }
            await #expect(throws: LocalOperationIdentityGuardFailure.malformedEvidence) {
                _ = try await Self.inspect(
                    database, id: id, family: .createClient,
                    fingerprint: Self.fingerprint
                )
            }
            #expect(try await Self.count(LedgerPowerSyncTable.localOperations, database) == 1)
            try await database.close(deleteDatabase: true)
            fixture.remove()
        }
    }

    @Test("Typed terminal creation survives drainage; legacy derives only unambiguously")
    func terminalAndLegacyClassification() async throws {
        for family in [LocalOperationCommandFamily.createClient, .createProject] {
            let fixture = try LocalOperationGuardDatabaseFixture()
            defer { fixture.remove() }
            let database = try fixture.open()
            let terminal = try OperationID(validating: "terminal-\(family.rawValue)")
            try await Self.insertOperation(
                family, id: terminal.rawValue, state: "applied", typed: true,
                database: database
            )
            #expect(try await Self.inspect(
                database, id: terminal, family: family, fingerprint: Self.fingerprint
            ) == .matchingOwner)

            let legacy = try OperationID(validating: "legacy-\(family.rawValue)")
            try await Self.insertOperation(
                family, id: legacy.rawValue, state: "queued", typed: false,
                database: database
            )
            try await Self.insertCommand(family, id: legacy.rawValue, database: database)
            try await Self.insertRequiredAuxiliary(family, id: legacy.rawValue, database: database)
            #expect(try await Self.inspect(
                database, id: legacy, family: family, fingerprint: Self.fingerprint
            ) == .matchingOwner)

            let ambiguous = try OperationID(validating: "ambiguous-\(family.rawValue)")
            try await Self.insertOperation(
                family, id: ambiguous.rawValue, state: "queued", typed: false,
                database: database
            )
            await #expect(throws: LocalOperationIdentityGuardFailure.malformedEvidence) {
                _ = try await Self.inspect(
                    database, id: ambiguous, family: family, fingerprint: Self.fingerprint
                )
            }
            try await database.close(deleteDatabase: true)
        }

        let clientFixture = try LocalOperationGuardDatabaseFixture()
        let clientDatabase = try clientFixture.open()
        let client = try Self.clientCommand(
            id: "legacy-provider-client", client: "legacy-provider-client"
        )
        _ = try await ClientCreationPowerSyncStore(database: clientDatabase).create(client)
        _ = try await clientDatabase.execute(
            sql: "UPDATE \(LedgerPowerSyncTable.localOperations) SET command_type = NULL, command_envelope_json = NULL WHERE id = ?",
            parameters: [client.envelope.operationId.rawValue]
        )
        #expect(try await ClientCreationPowerSyncStore(database: clientDatabase)
            .create(client).localState == .queued)
        try await clientDatabase.close(deleteDatabase: true)
        clientFixture.remove()

        let projectFixture = try LocalOperationGuardDatabaseFixture()
        let projectDatabase = try projectFixture.open()
        let project = try Self.projectCommand(id: "legacy-provider-project")
        _ = try await ProjectSetupPowerSyncStore(database: projectDatabase).create(project)
        _ = try await projectDatabase.execute(
            sql: "UPDATE \(LedgerPowerSyncTable.localOperations) SET command_type = NULL, command_envelope_json = NULL WHERE id = ?",
            parameters: [project.envelope.operationId.rawValue]
        )
        #expect(try await ProjectSetupPowerSyncStore(database: projectDatabase)
            .create(project).localState == .queued)
        try await projectDatabase.close(deleteDatabase: true)
        projectFixture.remove()

        try await Self.verifyCreationTerminalReconciliation()
    }

    @Test("Owner and surviving auxiliary tampering fails closed without repair")
    func ownerAndAuxiliaryTamperMatrix() async throws {
        for mutation in ["family", "account", "principal", "contract", "fingerprint",
                         "subject", "envelope", "state", "result", "auxiliary"] {
            let fixture = try LocalOperationGuardDatabaseFixture()
            let database = try fixture.open()
            let command = try Self.clientCommand(
                id: "tamper-\(mutation)", client: "client-tamper-\(mutation)"
            )
            _ = try await ClientCreationPowerSyncStore(database: database).create(command)
            switch mutation {
            case "family":
                _ = try await database.execute(
                    sql: "UPDATE \(LedgerPowerSyncTable.localOperations) SET command_type = 'create_project' WHERE id = ?",
                    parameters: [command.envelope.operationId.rawValue]
                )
            case "account":
                _ = try await database.execute(
                    sql: "UPDATE \(LedgerPowerSyncTable.localOperations) SET account_id = 'foreign' WHERE id = ?",
                    parameters: [command.envelope.operationId.rawValue]
                )
            case "principal":
                _ = try await database.execute(
                    sql: "UPDATE \(LedgerPowerSyncTable.localOperations) SET actor_principal_id = 'foreign' WHERE id = ?",
                    parameters: [command.envelope.operationId.rawValue]
                )
            case "contract":
                _ = try await database.execute(
                    sql: "UPDATE \(LedgerPowerSyncTable.localOperations) SET contract_version = 'other' WHERE id = ?",
                    parameters: [command.envelope.operationId.rawValue]
                )
            case "fingerprint":
                _ = try await database.execute(
                    sql: "UPDATE \(LedgerPowerSyncTable.localOperations) SET fingerprint = ? WHERE id = ?",
                    parameters: [String(repeating: "b", count: 64), command.envelope.operationId.rawValue]
                )
            case "subject":
                _ = try await database.execute(
                    sql: "UPDATE \(LedgerPowerSyncTable.localOperations) SET subject_id = 'other' WHERE id = ?",
                    parameters: [command.envelope.operationId.rawValue]
                )
            case "envelope":
                _ = try await database.execute(
                    sql: "UPDATE \(LedgerPowerSyncTable.localOperations) SET command_envelope_json = '{}' WHERE id = ?",
                    parameters: [command.envelope.operationId.rawValue]
                )
            case "state":
                _ = try await database.execute(
                    sql: "UPDATE \(LedgerPowerSyncTable.localOperations) SET local_state = 'future' WHERE id = ?",
                    parameters: [command.envelope.operationId.rawValue]
                )
            case "result":
                try await Self.insertSynchronizedResult(
                    id: command.envelope.operationId.rawValue, database: database
                )
            default:
                _ = try await database.execute(
                    sql: "UPDATE \(LedgerPowerSyncTable.pendingClients) SET display_name = 'Tampered' WHERE operation_id = ?",
                    parameters: [command.envelope.operationId.rawValue]
                )
            }
            let baseline = try await Self.reservationCounts(database)
            await #expect(throws: ClientCreationFailure.localAcceptanceFailed) {
                _ = try await ClientCreationPowerSyncStore(database: database).create(command)
            }
            #expect(try await Self.reservationCounts(database) == baseline)
            try await database.close(deleteDatabase: true)
            fixture.remove()
        }
    }

    @Test("Independent stores serialize same and cross-family claims")
    func concurrentClaims() async throws {
        for (index, family) in LocalOperationCommandFamily.allCases.enumerated() {
            let fixture = try LocalOperationGuardDatabaseFixture()
            let database = try fixture.open()
            try await Self.seedAuthorityIfNeeded(for: [family], database: database)
            let baselineCRUD = try await Self.count("ps_crud", database)
            let operationId = try Self.concurrentOperationId(for: [family], index: index)
            async let first = Self.submit(family, operationId: operationId, database: database)
            async let second = Self.submit(family, operationId: operationId, database: database)
            let receipts = try await [first, second]
            #expect(receipts[0] == receipts[1])
            #expect(try await Self.count(LedgerPowerSyncTable.localOperations, database) == 1)
            let insertOnlyEntries = try await Self.count("ps_crud", database) - baselineCRUD
            let assignmentEntries = try await Self.count(
                LedgerPowerSyncTable.itemSpaceAssignmentCommands, database
            )
            let clearingEntries = try await Self.count(
                LedgerPowerSyncTable.itemSpaceClearingCommands, database
            )
            let localOnlyEntries = assignmentEntries + clearingEntries
            #expect(insertOnlyEntries + localOnlyEntries == 1)
            try await database.close(deleteDatabase: true)
            fixture.remove()
        }

        for (index, family) in LocalOperationCommandFamily.allCases.enumerated() {
            let fixture = try LocalOperationGuardDatabaseFixture()
            let database = try fixture.open()
            try await Self.seedAuthorityIfNeeded(for: [family], database: database)
            let baselineCRUD = try await Self.count("ps_crud", database)
            let operationId = try Self.concurrentOperationId(
                for: [family], index: 500 + index
            )
            let outcomes = await withTaskGroup(of: String.self, returning: [String].self) {
                group in
                group.addTask {
                    await Self.submitRaceOutcome(
                        family, operationId: operationId, changed: false,
                        database: database
                    )
                }
                group.addTask {
                    await Self.submitRaceOutcome(
                        family, operationId: operationId, changed: true,
                        database: database
                    )
                }
                var values: [String] = []
                for await value in group { values.append(value) }
                return values
            }
            #expect(outcomes.filter { $0 == "success" }.count == 1)
            #expect(outcomes.filter { $0 == "payloadMismatch" }.count == 1)
            #expect(try await Self.count(LedgerPowerSyncTable.localOperations, database) == 1)
            let insertOnlyEntries = try await Self.count("ps_crud", database) - baselineCRUD
            let assignmentEntries = try await Self.count(
                LedgerPowerSyncTable.itemSpaceAssignmentCommands, database
            )
            let clearingEntries = try await Self.count(
                LedgerPowerSyncTable.itemSpaceClearingCommands, database
            )
            let localOnlyEntries = assignmentEntries + clearingEntries
            #expect(insertOnlyEntries + localOnlyEntries == 1)
            try await database.close(deleteDatabase: true)
            fixture.remove()
        }

        let families = LocalOperationCommandFamily.allCases
        var pairIndex = 100
        for firstIndex in families.indices {
            for secondIndex in families.indices where secondIndex > firstIndex {
                let pair = [families[firstIndex], families[secondIndex]]
                if pair.contains(.archiveProject) && pair.contains(.archiveClient) {
                    let invalidProjectId = try ClientArchiveOperationIdentity.make(
                        accountId: Self.guardAccountId,
                        uuid: Self.checkpointUUID(index: pairIndex)
                    )
                    let project = try Self.projectArchiveCommand(
                        operationId: invalidProjectId
                    )
                    let fixture = try LocalOperationGuardDatabaseFixture()
                    let database = try fixture.open()
                    try await Self.seedArchiveProject(database)
                    await #expect(throws: ProjectArchivePowerSyncFailure.invalidOperationIdentity) {
                        _ = try await ProjectArchivePowerSyncStore(
                            database: database, accountId: Self.guardAccountId,
                            principalId: Self.guardPrincipalId
                        ).archive(project)
                    }
                    let invalidClientId = try ProjectArchiveOperationIdentity.make(
                        accountId: Self.guardAccountId,
                        uuid: Self.checkpointUUID(index: pairIndex + 1_000)
                    )
                    let client = try Self.clientArchiveCommand(
                        operationId: invalidClientId
                    )
                    await #expect(throws: ClientArchivePowerSyncFailure.invalidOperationIdentity) {
                        _ = try await ClientArchivePowerSyncStore(
                            database: database, accountId: Self.guardAccountId,
                            principalId: Self.guardPrincipalId
                        ).archive(client)
                    }
                    #expect(try await Self.count(LedgerPowerSyncTable.localOperations, database) == 0)
                    try await database.close(deleteDatabase: true)
                    fixture.remove()
                    pairIndex += 1
                    continue
                }
                // Account-bound command families intentionally cannot share an
                // operation ID. Their cross-family rejection is covered by each
                // family's identity-contract tests rather than the shared-ID race.
                if pair.filter({ [.reviseSpaceChecklists, .archiveProject, .archiveClient, .manageCategories, .sellInventoryItems, .createExpense, .editExpense, .createInvoice].contains($0) }).count > 1
                {
                    pairIndex += 1
                    continue
                }

                let fixture = try LocalOperationGuardDatabaseFixture()
                let database = try fixture.open()
                try await Self.seedAuthorityIfNeeded(for: pair, database: database)
                let operationId = try Self.concurrentOperationId(for: pair, index: pairIndex)
                let baselineCRUD = try await Self.count("ps_crud", database)
                let outcomes = await withTaskGroup(
                    of: String.self, returning: [String].self
                ) { group in
                    for family in pair {
                        group.addTask {
                            await Self.submitRaceOutcome(
                                family, operationId: operationId, changed: false,
                                database: database
                            )
                        }
                    }
                    var values: [String] = []
                    for await value in group { values.append(value) }
                    return values
                }
                #expect(outcomes.filter { $0 == "success" }.count == 1)
                #expect(outcomes.filter { $0 == "payloadMismatch" }.count == 1)
                #expect(try await Self.count(LedgerPowerSyncTable.localOperations, database) == 1)
                let insertOnlyEntries = try await Self.count("ps_crud", database)
                    - baselineCRUD
                let assignmentEntries = try await Self.count(
                    LedgerPowerSyncTable.itemSpaceAssignmentCommands, database
                )
                let clearingEntries = try await Self.count(
                    LedgerPowerSyncTable.itemSpaceClearingCommands, database
                )
                let localOnlyEntries = assignmentEntries + clearingEntries
                #expect(insertOnlyEntries + localOnlyEntries == 1)
                try await Self.expectOneCompleteGraph(
                    operationId: operationId, database: database
                )
                try await database.close(deleteDatabase: true)
                fixture.remove()
                pairIndex += 1
            }
        }
    }

    @Test("Inventory and precommit cancellation roll back; postcommit remains durable")
    func checkpointAtomicityAndCancellation() async throws {
        for point in [ClientCreationPowerSyncStoreCheckpoint.inventoryConstruction,
                      .inventoryRead, .afterOwnershipInspection,
                      .operationWrite, .projectionWrite,
                      .commandWrite, .beforeCommit] {
            let fixture = try LocalOperationGuardDatabaseFixture()
            defer { fixture.remove() }
            let database = try fixture.open()
            let command = try Self.clientCommand(id: "cancel-\(point)", client: "client-\(point)")
            let store = ClientCreationPowerSyncStore(
                database: database,
                checkpoint: { if $0 == point { throw CancellationError() } }
            )
            await #expect(throws: CancellationError.self) { _ = try await store.create(command) }
            #expect(try await Self.count(LedgerPowerSyncTable.localOperations, database) == 0)
            #expect(try await Self.count("ps_crud", database) == 0)
            try await database.close(deleteDatabase: true)
        }

        let fixture = try LocalOperationGuardDatabaseFixture()
        defer { fixture.remove() }
        let database = try fixture.open()
        let command = try Self.clientCommand(id: "cancel-after", client: "client-after")
        let store = ClientCreationPowerSyncStore(
            database: database,
            checkpoint: { if $0 == .afterCommit { throw CancellationError() } }
        )
        await #expect(throws: CancellationError.self) { _ = try await store.create(command) }
        #expect(try await Self.count(LedgerPowerSyncTable.localOperations, database) == 1)
        #expect(try await Self.count("ps_crud", database) == 1)
        try await database.close(deleteDatabase: true)

        try await Self.verifyProjectSetupCheckpoints()
        try await Self.verifyProjectArchiveCheckpoints()
        try await Self.verifyClientArchiveCheckpoints()
        try await Self.verifyAssignmentCheckpoints()
        try await Self.verifyClearingCheckpoints()
        try await Self.verifyBoundedRawErrorMapping()
        try await Self.verifyMalformedGuardErrorMapping()
    }

    @Test("Valid and malformed reservations are stable across encrypted restart")
    func encryptedRestartStability() async throws {
        let fixture = try LocalOperationGuardDatabaseFixture()
        defer { fixture.remove() }
        var database = try fixture.open()
        let valid = try Self.clientCommand(id: "restart-valid", client: "client-restart")
        _ = try await ClientCreationPowerSyncStore(database: database).create(valid)
        var malformed: [OperationID] = []
        for relation in ["pending_client", "pending_project", "pending_allocation",
                         "project_overlay", "client_overlay", "result_mutation",
                         "result_mutation_queue"] {
            let id = try OperationID(validating: "restart-\(relation)")
            try await Self.insertIsolatedRelation(relation, id: id.rawValue, database: database)
            malformed.append(id)
        }
        let operationOnly = try OperationID(validating: "restart-operation-only")
        try await Self.insertOperation(
            .createClient, id: operationOnly.rawValue, state: "queued", typed: true,
            database: database
        )
        malformed.append(operationOnly)
        let synchronizedResult = try OperationID(validating: "restart-synchronized-result")
        try await Self.insertSynchronizedResult(
            id: synchronizedResult.rawValue, database: database
        )
        malformed.append(synchronizedResult)
        for family in LocalOperationCommandFamily.allCases {
            let commandOnly = try OperationID(
                validating: "restart-command-only-\(family.rawValue)"
            )
            try await Self.insertCommand(
                family, id: commandOnly.rawValue, database: database
            )
            malformed.append(commandOnly)
        }
        let invalidJSON = try OperationID(validating: "restart-invalid-json")
        try await Self.insertCommand(.createClient, id: invalidJSON.rawValue, database: database)
        _ = try await database.execute(
            sql: "UPDATE ps_crud SET data = substr(data, 1, length(data) - 1) WHERE instr(data, ?) > 0",
            parameters: [invalidJSON.rawValue]
        )
        malformed.append(invalidJSON)
        let multipleFamily = try OperationID(validating: "restart-multiple-family")
        try await Self.insertOperation(
            .createClient, id: multipleFamily.rawValue, state: "queued", typed: true,
            database: database
        )
        try await Self.insertCommand(.createClient, id: multipleFamily.rawValue, database: database)
        try await Self.insertCommand(
            .createProject, id: multipleFamily.rawValue, database: database
        )
        malformed.append(multipleFamily)
        for corruption in ["unknown-type", "malformed-envelope", "foreign-scope"] {
            let id = try OperationID(validating: "restart-\(corruption)")
            let family: LocalOperationCommandFamily = corruption == "malformed-envelope"
                ? .archiveClient
                : .archiveProject
            try await Self.seedComplete(family, id: id.rawValue, database: database)
            switch corruption {
            case "unknown-type":
                _ = try await database.execute(
                    sql: "UPDATE ps_crud SET data = json_set(data, '$.type', 'spike_future_commands') WHERE json_valid(data) = 1 AND json_extract(data, '$.id') = ?",
                    parameters: [id.rawValue]
                )
            case "malformed-envelope":
                _ = try await database.execute(
                    sql: "UPDATE \(LedgerPowerSyncTable.localOperations) SET command_envelope_json = '{' WHERE id = ?",
                    parameters: [id.rawValue]
                )
                _ = try await database.execute(
                    sql: "UPDATE ps_crud SET data = json_set(data, '$.data.envelope_json', '{') WHERE json_valid(data) = 1 AND json_extract(data, '$.id') = ?",
                    parameters: [id.rawValue]
                )
            default:
                _ = try await database.execute(
                    sql: "UPDATE \(LedgerPowerSyncTable.projectArchiveOverlays) SET account_id = 'foreign' WHERE operation_id = ?",
                    parameters: [id.rawValue]
                )
            }
            malformed.append(id)
        }
        let baselineCounts = try await Self.reservationCounts(database)
        try await database.close(deleteDatabase: false)

        for _ in 0..<2 {
            database = try fixture.open()
            #expect(try await ClientCreationPowerSyncStore(database: database).create(valid).localState == .queued)
            for id in malformed {
                await #expect(throws: LocalOperationIdentityGuardFailure.malformedEvidence) {
                    _ = try await Self.inspect(
                        database, id: id, family: .createClient,
                        fingerprint: Self.fingerprint
                    )
                }
            }
            #expect(try await Self.reservationCounts(database) == baselineCounts)
            try await database.close(deleteDatabase: false)
        }
        database = try fixture.open()
        try await database.close(deleteDatabase: true)
    }

    @Test("Guard failures are finite and never mutate unrelated work")
    func privacyAndNoMutation() async throws {
        let fixture = try LocalOperationGuardDatabaseFixture()
        defer { fixture.remove() }
        let database = try fixture.open()
        let foreignId = try OperationID(validating: "caller-visible-id")
        try await Self.seedComplete(.createProject, id: foreignId.rawValue, database: database)
        do {
            _ = try await Self.inspect(
                database, id: foreignId, family: .createClient,
                fingerprint: Self.fingerprint
            )
            Issue.record("Foreign owner was accepted")
        } catch {
            #expect(error as? LocalOperationIdentityGuardFailure == .payloadMismatch)
            #expect(String(describing: error) == "payloadMismatch")
        }
        #expect(try await Self.count(LedgerPowerSyncTable.localOperations, database) == 1)
        #expect(try await Self.count("ps_crud", database) == 1)
        try await database.close(deleteDatabase: true)
    }

    private static let fingerprint = String(repeating: "a", count: 64)
    private static let envelope = "{\"schema\":\"guard\"}"

    private static func verifyProjectSetupCheckpoints() async throws {
        let precommit: [ProjectSetupPowerSyncStoreCheckpoint] = [
            .inventoryConstruction, .inventoryRead, .afterOwnershipInspection,
            .operationWrite, .projectionWrite, .commandWrite, .beforeCommit
        ]
        for (index, point) in precommit.enumerated() {
            let fixture = try LocalOperationGuardDatabaseFixture()
            defer { fixture.remove() }
            let database = try fixture.open()
            let command = try projectCommand(id: "project-checkpoint-\(index)")
            let store = ProjectSetupPowerSyncStore(
                database: database,
                checkpoint: { if $0 == point { throw CancellationError() } }
            )
            await #expect(throws: CancellationError.self) {
                _ = try await store.create(command)
            }
            #expect(try await count(LedgerPowerSyncTable.localOperations, database) == 0)
            #expect(try await count(LedgerPowerSyncTable.pendingProjects, database) == 0)
            #expect(try await count("ps_crud", database) == 0)
            try await database.close(deleteDatabase: true)
        }

        let fixture = try LocalOperationGuardDatabaseFixture()
        defer { fixture.remove() }
        let database = try fixture.open()
        let command = try projectCommand(id: "project-checkpoint-after")
        let store = ProjectSetupPowerSyncStore(
            database: database,
            checkpoint: { if $0 == .afterCommit { throw CancellationError() } }
        )
        await #expect(throws: CancellationError.self) { _ = try await store.create(command) }
        #expect(try await count(LedgerPowerSyncTable.localOperations, database) == 1)
        #expect(try await count(LedgerPowerSyncTable.pendingProjects, database) == 1)
        #expect(try await count("ps_crud", database) == 1)
        try await database.close(deleteDatabase: true)
    }

    private static func verifyProjectArchiveCheckpoints() async throws {
        let precommit: [ProjectArchivePowerSyncStoreCheckpoint] = [
            .inventoryConstruction, .inventoryRead, .afterOwnershipInspection,
            .operationWrite, .projectionWrite, .commandWrite, .beforeCommit
        ]
        for (index, point) in precommit.enumerated() {
            let fixture = try LocalOperationGuardDatabaseFixture()
            defer { fixture.remove() }
            let database = try fixture.open()
            try await seedArchiveProject(database)
            let baselineCRUD = try await count("ps_crud", database)
            let command = try projectArchiveCommand(index: index)
            let store = ProjectArchivePowerSyncStore(
                database: database, accountId: guardAccountId,
                principalId: guardPrincipalId,
                now: { guardAcceptedAt },
                checkpoint: { if $0 == point { throw CancellationError() } }
            )
            await #expect(throws: CancellationError.self) {
                _ = try await store.archive(command)
            }
            #expect(try await count(LedgerPowerSyncTable.localOperations, database) == 0)
            #expect(try await count(LedgerPowerSyncTable.projectArchiveOverlays, database) == 0)
            #expect(try await count("ps_crud", database) == baselineCRUD)
            try await database.close(deleteDatabase: true)
        }

        let fixture = try LocalOperationGuardDatabaseFixture()
        defer { fixture.remove() }
        let database = try fixture.open()
        try await seedArchiveProject(database)
        let baselineCRUD = try await count("ps_crud", database)
        let command = try projectArchiveCommand(index: 90)
        let store = ProjectArchivePowerSyncStore(
            database: database, accountId: guardAccountId,
            principalId: guardPrincipalId,
            now: { guardAcceptedAt },
            checkpoint: { if $0 == .afterCommit { throw CancellationError() } }
        )
        await #expect(throws: CancellationError.self) { _ = try await store.archive(command) }
        #expect(try await count(LedgerPowerSyncTable.localOperations, database) == 1)
        #expect(try await count(LedgerPowerSyncTable.projectArchiveOverlays, database) == 1)
        #expect(try await count("ps_crud", database) == baselineCRUD + 1)
        try await database.close(deleteDatabase: true)
    }

    private static func verifyClientArchiveCheckpoints() async throws {
        let precommit: [ClientArchivePowerSyncStoreCheckpoint] = [
            .inventoryConstruction, .inventoryRead, .afterOwnershipInspection,
            .operationWrite, .projectionWrite, .commandWrite, .beforeCommit
        ]
        for (index, point) in precommit.enumerated() {
            let fixture = try LocalOperationGuardDatabaseFixture()
            defer { fixture.remove() }
            let database = try fixture.open()
            try await seedArchiveClient(database)
            let baselineCRUD = try await count("ps_crud", database)
            let command = try clientArchiveCommand(index: index)
            let store = ClientArchivePowerSyncStore(
                database: database, accountId: guardAccountId,
                principalId: guardPrincipalId,
                now: { guardAcceptedAt },
                checkpoint: { if $0 == point { throw CancellationError() } }
            )
            await #expect(throws: CancellationError.self) {
                _ = try await store.archive(command)
            }
            #expect(try await count(LedgerPowerSyncTable.localOperations, database) == 0)
            #expect(try await count(LedgerPowerSyncTable.clientArchiveOverlays, database) == 0)
            #expect(try await count("ps_crud", database) == baselineCRUD)
            try await database.close(deleteDatabase: true)
        }

        let fixture = try LocalOperationGuardDatabaseFixture()
        defer { fixture.remove() }
        let database = try fixture.open()
        try await seedArchiveClient(database)
        let baselineCRUD = try await count("ps_crud", database)
        let command = try clientArchiveCommand(index: 91)
        let store = ClientArchivePowerSyncStore(
            database: database, accountId: guardAccountId,
            principalId: guardPrincipalId,
            now: { guardAcceptedAt },
            checkpoint: { if $0 == .afterCommit { throw CancellationError() } }
        )
        await #expect(throws: CancellationError.self) { _ = try await store.archive(command) }
        #expect(try await count(LedgerPowerSyncTable.localOperations, database) == 1)
        #expect(try await count(LedgerPowerSyncTable.clientArchiveOverlays, database) == 1)
        #expect(try await count("ps_crud", database) == baselineCRUD + 1)
        try await database.close(deleteDatabase: true)
    }

    private static func verifyAssignmentCheckpoints() async throws {
        let precommit: [ItemSpaceAssignmentPowerSyncStoreCheckpoint] = [
            .inventoryConstruction, .inventoryRead, .afterOwnershipInspection,
            .existingRead, .commandWrite, .operationWrite, .beforeCommit
        ]
        for (index, point) in precommit.enumerated() {
            let fixture = try LocalOperationGuardDatabaseFixture()
            defer { fixture.remove() }
            let database = try fixture.open()
            let command = try assignmentCommand(id: "assignment-checkpoint-\(index)")
            let store = ItemSpaceAssignmentPowerSyncStore(
                database: database, accountId: guardAccountId,
                principalId: guardPrincipalId,
                now: { guardAcceptedAt },
                checkpoint: { if $0 == point { throw CancellationError() } }
            )
            await #expect(throws: CancellationError.self) {
                _ = try await store.assignItemsToSpace(command)
            }
            #expect(try await count(LedgerPowerSyncTable.localOperations, database) == 0)
            #expect(try await count(LedgerPowerSyncTable.itemSpaceAssignmentCommands, database) == 0)
            #expect(try await count("ps_crud", database) == 0)
            try await database.close(deleteDatabase: true)
        }

        let fixture = try LocalOperationGuardDatabaseFixture()
        defer { fixture.remove() }
        let database = try fixture.open()
        let command = try assignmentCommand(id: "assignment-checkpoint-after")
        let store = ItemSpaceAssignmentPowerSyncStore(
            database: database, accountId: guardAccountId,
            principalId: guardPrincipalId,
            now: { guardAcceptedAt },
            checkpoint: { if $0 == .afterCommit { throw CancellationError() } }
        )
        await #expect(throws: CancellationError.self) {
            _ = try await store.assignItemsToSpace(command)
        }
        #expect(try await count(LedgerPowerSyncTable.localOperations, database) == 1)
        #expect(try await count(LedgerPowerSyncTable.itemSpaceAssignmentCommands, database) == 1)
        #expect(try await count("ps_crud", database) == 0)
        try await database.close(deleteDatabase: true)
    }

    private static func verifyClearingCheckpoints() async throws {
        let precommit: [ItemSpaceClearingPowerSyncStoreCheckpoint] = [
            .beforeTransaction, .inventoryConstruction, .inventoryRead,
            .afterOwnershipInspection,
            .existingRead, .commandWrite, .operationWrite, .beforeCommit
        ]
        for (index, point) in precommit.enumerated() {
            let fixture = try LocalOperationGuardDatabaseFixture()
            defer { fixture.remove() }
            let database = try fixture.open()
            let command = try clearingCommand(id: "clearing-checkpoint-\(index)")
            let store = ItemSpaceClearingPowerSyncStore(
                database: database, accountId: guardAccountId,
                principalId: guardPrincipalId,
                now: { guardAcceptedAt },
                checkpoint: { if $0 == point { throw CancellationError() } }
            )
            await #expect(throws: CancellationError.self) {
                _ = try await store.clearItemSpaceAssignments(command)
            }
            #expect(try await count(LedgerPowerSyncTable.localOperations, database) == 0)
            #expect(try await count(LedgerPowerSyncTable.itemSpaceClearingCommands, database) == 0)
            #expect(try await count("ps_crud", database) == 0)
            try await database.close(deleteDatabase: true)
        }

        let fixture = try LocalOperationGuardDatabaseFixture()
        defer { fixture.remove() }
        let database = try fixture.open()
        let command = try clearingCommand(id: "clearing-checkpoint-after")
        let store = ItemSpaceClearingPowerSyncStore(
            database: database, accountId: guardAccountId,
            principalId: guardPrincipalId,
            now: { guardAcceptedAt },
            checkpoint: { if $0 == .afterCommit { throw CancellationError() } }
        )
        await #expect(throws: CancellationError.self) {
            _ = try await store.clearItemSpaceAssignments(command)
        }
        #expect(try await count(LedgerPowerSyncTable.localOperations, database) == 1)
        #expect(try await count(LedgerPowerSyncTable.itemSpaceClearingCommands, database) == 1)
        #expect(try await count("ps_crud", database) == 0)
        try await database.close(deleteDatabase: true)
    }

    private static func inspect(
        _ database: any PowerSyncDatabaseProtocol,
        id: OperationID,
        family: LocalOperationCommandFamily,
        fingerprint: String
    ) async throws -> LocalOperationIdentityDisposition {
        try await database.writeTransaction { transaction in
            try LocalOperationIdentityGuard.inspect(
                transaction: transaction, operationId: id,
                expectedFamily: family, expectedFingerprint: fingerprint
            )
        }
    }

    private static func seedComplete(
        _ family: LocalOperationCommandFamily,
        id: String,
        database: any PowerSyncDatabaseProtocol
    ) async throws {
        try await insertOperation(family, id: id, state: "queued", typed: true, database: database)
        try await insertCommand(family, id: id, database: database)
        try await insertRequiredAuxiliary(family, id: id, database: database)
    }

    private static func insertOperation(
        _ family: LocalOperationCommandFamily,
        id: String,
        state: String,
        typed: Bool,
        database: any PowerSyncDatabaseProtocol
    ) async throws {
        _ = try await database.execute(sql: """
            INSERT INTO \(LedgerPowerSyncTable.localOperations) (
              id, account_id, actor_principal_id, contract_version, fingerprint,
              subject_id, local_state, accepted_at_ms, updated_at_ms,
              command_type, command_envelope_json
            ) VALUES (?, 'account', 'principal', 'contract', ?, ?, ?, 100, 100, ?, ?)
            """, parameters: [
                id, fingerprint, subject(family), state,
                typed ? family.rawValue : nil, typed ? envelope : nil
            ])
    }

    private static func insertCommand(
        _ family: LocalOperationCommandFamily,
        id: String,
        database: any PowerSyncDatabaseProtocol
    ) async throws {
        switch family {
        case .createInvoice:
            _ = try await database.execute(sql: """
                INSERT INTO spike_invoice_commands(id,account_id,actor_principal_id,invoice_id,contract_version,fingerprint,envelope_json)
                VALUES (?, 'account', 'principal', 'invoice', 'contract', ?, ?)
                """, parameters: [id, fingerprint, envelope])
        case .createExpense, .editExpense:
            _ = try await database.execute(sql: """
                INSERT INTO spike_expense_commands(id,account_id,actor_principal_id,expense_id,contract_version,fingerprint,envelope_json)
                VALUES (?, 'account', 'principal', 'expense', 'contract', ?, ?)
                """, parameters: [id, fingerprint, envelope])
        case .sellInventoryItems:
            _ = try await database.execute(sql: """
                INSERT INTO spike_inventory_sale_commands(id,account_id,actor_principal_id,project_id,contract_version,fingerprint,envelope_json)
                VALUES (?, 'account', 'principal', 'project', 'contract', ?, ?)
                """, parameters: [id, fingerprint, envelope])
        case .manageCategories:
            _ = try await database.execute(sql: """
                INSERT INTO spike_category_commands(id,account_id,actor_principal_id,contract_version,fingerprint,envelope_json)
                VALUES (?, 'account', 'principal', 'contract', ?, ?)
                """, parameters: [id, fingerprint, envelope])
        case .createClient:
            _ = try await database.execute(sql: """
                INSERT INTO \(LedgerPowerSyncTable.clientCommands)
                (id, account_id, actor_principal_id, contract_version, client_created_at_ms,
                 client_id, display_name, fingerprint, envelope_json)
                VALUES (?, 'account', 'principal', 'contract', 1, 'client', 'Client', ?, ?)
                """, parameters: [id, fingerprint, envelope])
        case .createProject:
            _ = try await database.execute(sql: """
                INSERT INTO \(LedgerPowerSyncTable.projectCommands)
                (id, account_id, actor_principal_id, contract_version, project_created_at_ms,
                 project_id, client_selection_kind, client_id, project_display_name,
                 category_allocations_json, fingerprint, envelope_json)
                VALUES (?, 'account', 'principal', 'contract', 1, 'project', 'existing',
                        'client', 'Project', '[]', ?, ?)
                """, parameters: [id, fingerprint, envelope])
        case .archiveProject:
            _ = try await database.execute(sql: """
                INSERT INTO \(LedgerPowerSyncTable.projectArchiveCommands)
                (id, account_id, actor_principal_id, contract_version, client_created_at_ms,
                 project_id, expected_revision, fingerprint, envelope_json)
                VALUES (?, 'account', 'principal', 'contract', 1, 'project', '1', ?, ?)
                """, parameters: [id, fingerprint, envelope])
        case .archiveClient:
            _ = try await database.execute(sql: """
                INSERT INTO \(LedgerPowerSyncTable.clientArchiveCommands)
                (id, account_id, actor_principal_id, contract_version, client_created_at_ms,
                 client_id, expected_revision, fingerprint, envelope_json)
                VALUES (?, 'account', 'principal', 'contract', 1, 'client', '1', ?, ?)
                """, parameters: [id, fingerprint, envelope])
        case .reviseSpaceChecklists:
            _ = try await database.execute(sql: """
                INSERT INTO \(LedgerPowerSyncTable.spaceChecklistRevisionCommands)
                (id, account_id, actor_principal_id, contract_version,
                 client_created_at_ms, space_id, expected_revision,
                 collection_json, fingerprint, envelope_json)
                VALUES (?, 'account', 'principal', 'contract', 1, 'space', '1',
                        '{"checklists":[]}', ?, ?)
                """, parameters: [id, fingerprint, envelope])
        case .assignItemsToSpace:
            _ = try await database.execute(sql: """
                INSERT INTO \(LedgerPowerSyncTable.itemSpaceAssignmentCommands)
                (id, account_id, actor_principal_id, contract_version, destination_space_id,
                 scope_kind, project_id, expected_space_revision, items_json, fingerprint,
                 command_json, accepted_at_ms)
                VALUES (?, 'account', 'principal', 'contract', 'space', 'business_inventory',
                        NULL, '1', '[]', ?, '{}', 100)
                """, parameters: [id, fingerprint])
        case .clearItemSpaceAssignments:
            _ = try await database.execute(sql: """
                INSERT INTO \(LedgerPowerSyncTable.itemSpaceClearingCommands)
                (id, account_id, actor_principal_id, contract_version, scope_kind,
                 project_id, items_json, fingerprint, command_json, accepted_at_ms)
                VALUES (?, 'account', 'principal', 'contract', 'business_inventory',
                        NULL, '[]', ?, '{}', 100)
                """, parameters: [id, fingerprint])
        }
    }

    private static func insertRequiredAuxiliary(
        _ family: LocalOperationCommandFamily,
        id: String,
        database: any PowerSyncDatabaseProtocol
    ) async throws {
        switch family {
        case .sellInventoryItems, .createExpense, .editExpense, .createInvoice: break
        case .manageCategories:
            _ = try await database.execute(sql: "UPDATE spike_local_operations SET category_projection_json = '[]' WHERE id = ?", parameters: [id])
        case .createClient:
            _ = try await database.execute(sql: """
                INSERT INTO \(LedgerPowerSyncTable.pendingClients)
                (id, account_id, display_name, lifecycle, revision, created_at_ms,
                 updated_at_ms, created_by_principal_id, operation_id)
                VALUES ('client', 'account', 'Client', 'active', 1, 100, 100, 'principal', ?)
                """, parameters: [id])
        case .createProject:
            _ = try await database.execute(sql: """
                INSERT INTO \(LedgerPowerSyncTable.pendingProjects)
                (id, account_id, client_id, display_name, lifecycle, revision,
                 category_configuration_revision, created_at_ms, updated_at_ms,
                 created_by_principal_id, operation_id)
                VALUES ('project', 'account', 'client', 'Project', 'active', 1, '1',
                        100, 100, 'principal', ?)
                """, parameters: [id])
        case .archiveProject:
            _ = try await database.execute(sql: """
                INSERT INTO \(LedgerPowerSyncTable.projectArchiveOverlays)
                (id, account_id, actor_principal_id, project_id, operation_id, fingerprint,
                 expected_revision, projected_revision, lifecycle, accepted_at_ms)
                VALUES (?, 'account', 'principal', 'project', ?, ?, '1', 2, 'archived', 100)
                """, parameters: [id, id, fingerprint])
        case .archiveClient:
            _ = try await database.execute(sql: """
                INSERT INTO \(LedgerPowerSyncTable.clientArchiveOverlays)
                (id, account_id, actor_principal_id, client_id, operation_id, fingerprint,
                 expected_revision, projected_revision, lifecycle, accepted_at_ms)
                VALUES (?, 'account', 'principal', 'client', ?, ?, '1', 2, 'archived', 100)
                """, parameters: [id, id, fingerprint])
        case .reviseSpaceChecklists:
            _ = try await database.execute(sql: """
                INSERT INTO \(LedgerPowerSyncTable.spaceChecklistRevisionOverlays)
                (id, account_id, actor_principal_id, space_id, operation_id,
                 fingerprint, expected_revision, projected_revision,
                 collection_json, accepted_at_ms)
                VALUES (?, 'account', 'principal', 'space', ?, ?, '1', 2,
                        '{"checklists":[]}', 100)
                """, parameters: [id, id, fingerprint])
        case .assignItemsToSpace, .clearItemSpaceAssignments:
            break
        }
    }

    private static func insertIsolatedRelation(
        _ relation: String,
        id: String,
        database: any PowerSyncDatabaseProtocol
    ) async throws {
        switch relation {
        case "pending_client":
            _ = try await database.execute(sql: """
                INSERT INTO \(LedgerPowerSyncTable.pendingClients)
                (id, account_id, display_name, lifecycle, revision, created_at_ms,
                 updated_at_ms, created_by_principal_id, operation_id)
                VALUES ('client', 'account', 'Client', 'active', 1, 1, 1, 'principal', ?)
                """, parameters: [id])
        case "pending_project":
            _ = try await database.execute(sql: """
                INSERT INTO \(LedgerPowerSyncTable.pendingProjects)
                (id, account_id, client_id, display_name, lifecycle, revision,
                 category_configuration_revision, created_at_ms, updated_at_ms,
                 created_by_principal_id, operation_id)
                VALUES ('project', 'account', 'client', 'Project', 'active', 1, '1',
                        1, 1, 'principal', ?)
                """, parameters: [id])
        case "pending_allocation":
            _ = try await database.execute(sql: """
                INSERT INTO \(LedgerPowerSyncTable.pendingProjectCategoryAllocations)
                (id, account_id, project_id, category_id, revision, created_at_ms,
                 updated_at_ms, created_by_principal_id, operation_id)
                VALUES ('allocation', 'account', 'project', 'category', 1, 1, 1, 'principal', ?)
                """, parameters: [id])
        case "project_overlay":
            _ = try await database.execute(sql: """
                INSERT INTO \(LedgerPowerSyncTable.projectArchiveOverlays)
                (id, account_id, actor_principal_id, project_id, operation_id, fingerprint,
                 expected_revision, projected_revision, lifecycle, accepted_at_ms)
                VALUES ('overlay', 'account', 'principal', 'project', ?, ?, '1', 2, 'archived', 1)
                """, parameters: [id, fingerprint])
        case "client_overlay":
            _ = try await database.execute(sql: """
                INSERT INTO \(LedgerPowerSyncTable.clientArchiveOverlays)
                (id, account_id, actor_principal_id, client_id, operation_id, fingerprint,
                 expected_revision, projected_revision, lifecycle, accepted_at_ms)
                VALUES ('overlay', 'account', 'principal', 'client', ?, ?, '1', 2, 'archived', 1)
                """, parameters: [id, fingerprint])
        default:
            _ = try await database.execute(sql: """
                INSERT INTO \(LedgerPowerSyncTable.operationResults)
                (id, account_id, actor_principal_id, command_type, contract_version,
                 command_fingerprint, envelope_sha256, request_sha256, subject_id,
                 phase, result_code, client_created_at_ms, server_received_at_ms,
                 completed_at_ms)
                VALUES (?, 'account', 'principal', 'create_client', 'contract', ?, ?, ?,
                        'client', 'applied', 'created', 1, 2, 3)
                """, parameters: [id, fingerprint, fingerprint, fingerprint])
            if relation == "result_mutation_queue" {
                _ = try await database.execute(
                    sql: "DELETE FROM ps_data__\(LedgerPowerSyncTable.operationResults) WHERE id = ?",
                    parameters: [id]
                )
            }
        }
    }

    private static func insertSynchronizedResult(
        id: String,
        database: any PowerSyncDatabaseProtocol
    ) async throws {
        let data = """
        {"account_id":"account","actor_principal_id":"principal",\
        "command_type":"create_client","contract_version":"contract",\
        "command_fingerprint":"\(fingerprint)","envelope_sha256":"\(fingerprint)",\
        "subject_id":"client","phase":"applied","result_code":"client_created",\
        "client_created_at_ms":1,\
        "server_received_at_ms":2,"completed_at_ms":3}
        """
        _ = try await database.execute(
            sql: "INSERT INTO ps_data__\(LedgerPowerSyncTable.operationResults) (id, data) VALUES (?, ?)",
            parameters: [id, data]
        )
    }

    private static func insertCreationResult(
        operationId: String,
        accountId: String,
        principalId: String,
        commandType: String,
        contractVersion: String,
        fingerprint: String,
        subjectId: String,
        clientCreatedAt: Int64,
        phase: String,
        code: String,
        database: any PowerSyncDatabaseProtocol
    ) async throws {
        let payload: [String: Any] = [
            "account_id": accountId,
            "actor_principal_id": principalId,
            "command_type": commandType,
            "contract_version": contractVersion,
            "command_fingerprint": fingerprint,
            "envelope_sha256": fingerprint,
            "subject_id": subjectId,
            "phase": phase,
            "result_code": phase == "applied" ? code : NSNull(),
            "error_code": phase == "rejected" ? code : NSNull(),
            "client_created_at_ms": clientCreatedAt,
            "server_received_at_ms": 2,
            "completed_at_ms": 3
        ]
        let bytes = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let json = try #require(String(data: bytes, encoding: .utf8))
        _ = try await database.execute(
            sql: "INSERT INTO ps_data__\(LedgerPowerSyncTable.operationResults) (id, data) VALUES (?, ?)",
            parameters: [operationId, json]
        )
    }

    private static func subject(_ family: LocalOperationCommandFamily) -> String {
        switch family {
        case .createInvoice: "invoice"
        case .createExpense, .editExpense: "expense"
        case .createClient, .archiveClient: "client"
        case .createProject, .archiveProject, .sellInventoryItems: "project"
        case .assignItemsToSpace, .reviseSpaceChecklists: "space"
        case .clearItemSpaceAssignments, .manageCategories: "account"
        }
    }

    private static func count(
        _ table: String,
        _ database: any PowerSyncDatabaseProtocol
    ) async throws -> Int64 {
        try await database.get("SELECT count(*) FROM \(table)") { try $0.getInt64(index: 0) }
    }

    private static func reservationCounts(
        _ database: any PowerSyncDatabaseProtocol
    ) async throws -> [Int64] {
        var counts: [Int64] = []
        for table in LocalOperationIdentityGuard.operationBearingRelations + ["ps_crud"] {
            counts.append(try await count(table, database))
        }
        return counts
    }

    private static func clientCommand(id: String, client: String) throws -> CreateClientCommand {
        try CreateClientCommand(
            operationId: OperationID(validating: id),
            draft: ClientCreationDraft(
                accountId: AccountID(validating: "account"),
                actorPrincipalId: PrincipalID(validating: "principal"),
                operationContractVersion: OperationContractVersion(validating: "client-create-v1"),
                clientId: ClientID(validating: client),
                displayName: ClientDisplayName(validating: "Client"),
                capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )
    }

    private static func projectCommand(
        id: String,
        withAllocation: Bool = false
    ) throws -> CreateProjectCommand {
        try CreateProjectCommand(
            operationId: OperationID(validating: id),
            draft: ProjectSetupDraft(
                accountId: AccountID(validating: "account"),
                actorPrincipalId: PrincipalID(validating: "principal"),
                operationContractVersion: OperationContractVersion(validating: "project-create-v1"),
                projectId: ProjectID(validating: "project-cross"),
                clientSelection: ProjectClientSelectionInput(existing: ClientID(validating: "client-existing")),
                displayName: ProjectDisplayName(validating: "Project"),
                description: nil,
                categoryAllocations: withAllocation ? [
                    try NullableCategoryAllocation(
                        categoryId: BudgetCategoryID(validating: "category-guard"),
                        allocation: Money(
                            minorUnits: 123,
                            currency: CurrencyCode(validating: "USD")
                        )
                    )
                ] : [],
                capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )
    }

    private static func verifyCreationTerminalReconciliation() async throws {
        let clientFixture = try LocalOperationGuardDatabaseFixture()
        let clientDatabase = try clientFixture.open()
        let client = try clientCommand(
            id: "terminal-client-reconciliation",
            client: "client-terminal-reconciliation"
        )
        _ = try await ClientCreationPowerSyncStore(database: clientDatabase).create(client)
        let clientCRUD = try #require(try await clientDatabase.getNextCrudTransaction())
        try await clientCRUD.complete()
        _ = try await clientDatabase.execute(
            sql: "UPDATE \(LedgerPowerSyncTable.localOperations) SET local_state = 'applied' WHERE id = ?",
            parameters: [client.envelope.operationId.rawValue]
        )
        try await insertCreationResult(
            operationId: client.envelope.operationId.rawValue,
            accountId: client.envelope.accountId.rawValue,
            principalId: client.envelope.actorPrincipalId.rawValue,
            commandType: "create_client",
            contractVersion: client.envelope.contractVersion.rawValue,
            fingerprint: client.fingerprint.sha256,
            subjectId: client.draft.clientId.rawValue,
            clientCreatedAt: Int64(
                (client.draft.capturedAt.timeIntervalSince1970 * 1_000).rounded(.towardZero)
            ),
            phase: "applied", code: "client_created", database: clientDatabase
        )
        #expect(try await ClientCreationPowerSyncStore(database: clientDatabase)
            .create(client).localState == .applied)
        _ = try await clientDatabase.execute(
            sql: "UPDATE ps_data__\(LedgerPowerSyncTable.operationResults) SET data = json_set(data, '$.result_code', 'tampered') WHERE id = ?",
            parameters: [client.envelope.operationId.rawValue]
        )
        await #expect(throws: ClientCreationFailure.localAcceptanceFailed) {
            _ = try await ClientCreationPowerSyncStore(database: clientDatabase).create(client)
        }
        _ = try await clientDatabase.execute(
            sql: "UPDATE ps_data__\(LedgerPowerSyncTable.operationResults) SET data = json_set(data, '$.result_code', 'client_created', '$.request_sha256', ?) WHERE id = ?",
            parameters: [String(repeating: "f", count: 64), client.envelope.operationId.rawValue]
        )
        await #expect(throws: ClientCreationFailure.localAcceptanceFailed) {
            _ = try await ClientCreationPowerSyncStore(database: clientDatabase).create(client)
        }
        _ = try await clientDatabase.execute(
            sql: "UPDATE ps_data__\(LedgerPowerSyncTable.operationResults) SET data = json_remove(data, '$.request_sha256') WHERE id = ?",
            parameters: [client.envelope.operationId.rawValue]
        )
        try await PowerSyncOverlayReconciler.reconcileClient(
            database: clientDatabase,
            clientId: client.draft.clientId.rawValue,
            accountId: client.envelope.accountId.rawValue,
            operationId: client.envelope.operationId.rawValue
        )
        #expect(try await ClientCreationPowerSyncStore(database: clientDatabase)
            .create(client).localState == .applied)
        try await clientDatabase.close(deleteDatabase: true)
        clientFixture.remove()

        let projectFixture = try LocalOperationGuardDatabaseFixture()
        let projectDatabase = try projectFixture.open()
        let project = try projectCommand(
            id: "terminal-project-reconciliation", withAllocation: true
        )
        _ = try await ProjectSetupPowerSyncStore(database: projectDatabase).create(project)
        let projectCRUD = try #require(try await projectDatabase.getNextCrudTransaction())
        try await projectCRUD.complete()
        _ = try await projectDatabase.execute(
            sql: "UPDATE \(LedgerPowerSyncTable.localOperations) SET local_state = 'applied' WHERE id = ?",
            parameters: [project.envelope.operationId.rawValue]
        )
        try await insertCreationResult(
            operationId: project.envelope.operationId.rawValue,
            accountId: project.envelope.accountId.rawValue,
            principalId: project.envelope.actorPrincipalId.rawValue,
            commandType: "create_project",
            contractVersion: project.envelope.contractVersion.rawValue,
            fingerprint: project.fingerprint.sha256,
            subjectId: project.draft.projectId.rawValue,
            clientCreatedAt: Int64(
                (project.draft.capturedAt.timeIntervalSince1970 * 1_000).rounded(.towardZero)
            ),
            phase: "applied", code: "project_created", database: projectDatabase
        )
        #expect(try await ProjectSetupPowerSyncStore(database: projectDatabase)
            .create(project).localState == .applied)
        _ = try await projectDatabase.execute(
            sql: "UPDATE ps_data__\(LedgerPowerSyncTable.operationResults) SET data = json_set(data, '$.client_created_at_ms', json_extract(data, '$.client_created_at_ms') + 1) WHERE id = ?",
            parameters: [project.envelope.operationId.rawValue]
        )
        await #expect(throws: ProjectSetupFailure.localAcceptanceFailed) {
            _ = try await ProjectSetupPowerSyncStore(database: projectDatabase).create(project)
        }
        _ = try await projectDatabase.execute(
            sql: "UPDATE ps_data__\(LedgerPowerSyncTable.operationResults) SET data = json_set(data, '$.client_created_at_ms', ?) WHERE id = ?",
            parameters: [
                Int64((project.draft.capturedAt.timeIntervalSince1970 * 1_000)
                    .rounded(.towardZero)),
                project.envelope.operationId.rawValue
            ]
        )
        try await PowerSyncOverlayReconciler.reconcileProjectCore(
            database: projectDatabase,
            projectId: project.draft.projectId.rawValue,
            accountId: project.envelope.accountId.rawValue,
            operationId: project.envelope.operationId.rawValue
        )
        #expect(try await ProjectSetupPowerSyncStore(database: projectDatabase)
            .create(project).localState == .applied)
        _ = try await projectDatabase.execute(
            sql: "DELETE FROM \(LedgerPowerSyncTable.pendingProjectCategoryAllocations) WHERE operation_id = ?",
            parameters: [project.envelope.operationId.rawValue]
        )
        #expect(try await ProjectSetupPowerSyncStore(database: projectDatabase)
            .create(project).localState == .applied)
        try await projectDatabase.close(deleteDatabase: true)
        projectFixture.remove()

        let rejectedClientFixture = try LocalOperationGuardDatabaseFixture()
        let rejectedClientDatabase = try rejectedClientFixture.open()
        let rejectedClient = try clientCommand(
            id: "terminal-client-rejected", client: "client-terminal-rejected"
        )
        _ = try await ClientCreationPowerSyncStore(database: rejectedClientDatabase)
            .create(rejectedClient)
        let rejectedClientCRUD = try #require(
            try await rejectedClientDatabase.getNextCrudTransaction()
        )
        try await rejectedClientCRUD.complete()
        _ = try await rejectedClientDatabase.execute(
            sql: "UPDATE \(LedgerPowerSyncTable.localOperations) SET local_state = 'rejected' WHERE id = ?",
            parameters: [rejectedClient.envelope.operationId.rawValue]
        )
        try await insertCreationResult(
            operationId: rejectedClient.envelope.operationId.rawValue,
            accountId: rejectedClient.envelope.accountId.rawValue,
            principalId: rejectedClient.envelope.actorPrincipalId.rawValue,
            commandType: "create_client",
            contractVersion: rejectedClient.envelope.contractVersion.rawValue,
            fingerprint: rejectedClient.fingerprint.sha256,
            subjectId: rejectedClient.draft.clientId.rawValue,
            clientCreatedAt: Int64(
                (rejectedClient.draft.capturedAt.timeIntervalSince1970 * 1_000)
                    .rounded(.towardZero)
            ),
            phase: "rejected", code: "client_creation_identity_conflict",
            database: rejectedClientDatabase
        )
        try await PowerSyncOverlayReconciler.reconcileClient(
            database: rejectedClientDatabase,
            clientId: rejectedClient.draft.clientId.rawValue,
            accountId: rejectedClient.envelope.accountId.rawValue,
            operationId: rejectedClient.envelope.operationId.rawValue
        )
        #expect(try await ClientCreationPowerSyncStore(database: rejectedClientDatabase)
            .create(rejectedClient).localState == .rejected)
        _ = try await rejectedClientDatabase.execute(
            sql: "UPDATE ps_data__\(LedgerPowerSyncTable.operationResults) SET data = json_set(data, '$.error_code', 'unknown_rejection') WHERE id = ?",
            parameters: [rejectedClient.envelope.operationId.rawValue]
        )
        await #expect(throws: ClientCreationFailure.localAcceptanceFailed) {
            _ = try await ClientCreationPowerSyncStore(database: rejectedClientDatabase)
                .create(rejectedClient)
        }
        try await rejectedClientDatabase.close(deleteDatabase: true)
        rejectedClientFixture.remove()

        let rejectedProjectFixture = try LocalOperationGuardDatabaseFixture()
        let rejectedProjectDatabase = try rejectedProjectFixture.open()
        let rejectedProject = try projectCommand(
            id: "terminal-project-rejected", withAllocation: true
        )
        _ = try await ProjectSetupPowerSyncStore(database: rejectedProjectDatabase)
            .create(rejectedProject)
        let rejectedProjectCRUD = try #require(
            try await rejectedProjectDatabase.getNextCrudTransaction()
        )
        try await rejectedProjectCRUD.complete()
        _ = try await rejectedProjectDatabase.execute(
            sql: "UPDATE \(LedgerPowerSyncTable.localOperations) SET local_state = 'rejected' WHERE id = ?",
            parameters: [rejectedProject.envelope.operationId.rawValue]
        )
        try await insertCreationResult(
            operationId: rejectedProject.envelope.operationId.rawValue,
            accountId: rejectedProject.envelope.accountId.rawValue,
            principalId: rejectedProject.envelope.actorPrincipalId.rawValue,
            commandType: "create_project",
            contractVersion: rejectedProject.envelope.contractVersion.rawValue,
            fingerprint: rejectedProject.fingerprint.sha256,
            subjectId: rejectedProject.draft.projectId.rawValue,
            clientCreatedAt: Int64(
                (rejectedProject.draft.capturedAt.timeIntervalSince1970 * 1_000)
                    .rounded(.towardZero)
            ),
            phase: "rejected", code: "project_setup_identity_conflict",
            database: rejectedProjectDatabase
        )
        try await PowerSyncOverlayReconciler.reconcileProjectCore(
            database: rejectedProjectDatabase,
            projectId: rejectedProject.draft.projectId.rawValue,
            accountId: rejectedProject.envelope.accountId.rawValue,
            operationId: rejectedProject.envelope.operationId.rawValue
        )
        _ = try await rejectedProjectDatabase.execute(
            sql: "DELETE FROM \(LedgerPowerSyncTable.pendingProjectCategoryAllocations) WHERE operation_id = ?",
            parameters: [rejectedProject.envelope.operationId.rawValue]
        )
        #expect(try await ProjectSetupPowerSyncStore(database: rejectedProjectDatabase)
            .create(rejectedProject).localState == .rejected)
        _ = try await rejectedProjectDatabase.execute(
            sql: "UPDATE ps_data__\(LedgerPowerSyncTable.operationResults) SET data = json_set(data, '$.error_code', 'unknown_rejection') WHERE id = ?",
            parameters: [rejectedProject.envelope.operationId.rawValue]
        )
        await #expect(throws: ProjectSetupFailure.localAcceptanceFailed) {
            _ = try await ProjectSetupPowerSyncStore(database: rejectedProjectDatabase)
                .create(rejectedProject)
        }
        try await rejectedProjectDatabase.close(deleteDatabase: true)
        rejectedProjectFixture.remove()
    }

    private static func verifyBoundedRawErrorMapping() async throws {
        let clientFixture = try LocalOperationGuardDatabaseFixture()
        let clientDatabase = try clientFixture.open()
        let client = try clientCommand(id: "raw-client", client: "raw-client")
        await #expect(throws: ClientCreationFailure.localAcceptanceFailed) {
            _ = try await ClientCreationPowerSyncStore(
                database: clientDatabase,
                checkpoint: { if $0 == .inventoryRead { throw LocalOperationGuardInjectedFailure() } }
            ).create(client)
        }
        #expect(try await count(LedgerPowerSyncTable.localOperations, clientDatabase) == 0)
        try await clientDatabase.close(deleteDatabase: true)
        clientFixture.remove()

        let projectFixture = try LocalOperationGuardDatabaseFixture()
        let projectDatabase = try projectFixture.open()
        let project = try projectCommand(id: "raw-project")
        await #expect(throws: ProjectSetupFailure.localAcceptanceFailed) {
            _ = try await ProjectSetupPowerSyncStore(
                database: projectDatabase,
                checkpoint: { if $0 == .inventoryRead { throw LocalOperationGuardInjectedFailure() } }
            ).create(project)
        }
        #expect(try await count(LedgerPowerSyncTable.localOperations, projectDatabase) == 0)
        try await projectDatabase.close(deleteDatabase: true)
        projectFixture.remove()

        let projectArchiveFixture = try LocalOperationGuardDatabaseFixture()
        let projectArchiveDatabase = try projectArchiveFixture.open()
        let projectArchive = try projectArchiveCommand(index: 810)
        await #expect(throws: ProjectArchiveFailure.localAcceptanceFailed) {
            _ = try await ProjectArchivePowerSyncStore(
                database: projectArchiveDatabase, accountId: guardAccountId,
                principalId: guardPrincipalId,
                checkpoint: { if $0 == .inventoryRead { throw LocalOperationGuardInjectedFailure() } }
            ).archive(projectArchive)
        }
        #expect(try await count(LedgerPowerSyncTable.localOperations, projectArchiveDatabase) == 0)
        try await projectArchiveDatabase.close(deleteDatabase: true)
        projectArchiveFixture.remove()

        let clientArchiveFixture = try LocalOperationGuardDatabaseFixture()
        let clientArchiveDatabase = try clientArchiveFixture.open()
        let clientArchive = try clientArchiveCommand(index: 811)
        await #expect(throws: ClientArchiveFailure.localAcceptanceFailed) {
            _ = try await ClientArchivePowerSyncStore(
                database: clientArchiveDatabase, accountId: guardAccountId,
                principalId: guardPrincipalId,
                checkpoint: { if $0 == .inventoryRead { throw LocalOperationGuardInjectedFailure() } }
            ).archive(clientArchive)
        }
        #expect(try await count(LedgerPowerSyncTable.localOperations, clientArchiveDatabase) == 0)
        try await clientArchiveDatabase.close(deleteDatabase: true)
        clientArchiveFixture.remove()

        let assignmentFixture = try LocalOperationGuardDatabaseFixture()
        let assignmentDatabase = try assignmentFixture.open()
        let assignment = try assignmentCommand(id: "raw-assignment")
        await #expect(throws: ItemSpaceAssignmentFailure.localAcceptanceFailed) {
            _ = try await ItemSpaceAssignmentPowerSyncStore(
                database: assignmentDatabase, accountId: guardAccountId,
                principalId: guardPrincipalId,
                checkpoint: { if $0 == .inventoryRead { throw LocalOperationGuardInjectedFailure() } }
            ).assignItemsToSpace(assignment)
        }
        #expect(try await count(LedgerPowerSyncTable.localOperations, assignmentDatabase) == 0)
        try await assignmentDatabase.close(deleteDatabase: true)
        assignmentFixture.remove()

        let clearingFixture = try LocalOperationGuardDatabaseFixture()
        let clearingDatabase = try clearingFixture.open()
        let clearing = try clearingCommand(id: "raw-clearing")
        await #expect(throws: ItemSpaceClearingFailure.localAcceptanceFailed) {
            _ = try await ItemSpaceClearingPowerSyncStore(
                database: clearingDatabase, accountId: guardAccountId,
                principalId: guardPrincipalId,
                checkpoint: { if $0 == .inventoryRead { throw LocalOperationGuardInjectedFailure() } }
            ).clearItemSpaceAssignments(clearing)
        }
        #expect(try await count(LedgerPowerSyncTable.localOperations, clearingDatabase) == 0)
        try await clearingDatabase.close(deleteDatabase: true)
        clearingFixture.remove()
    }

    private static func verifyMalformedGuardErrorMapping() async throws {
        let clientFixture = try LocalOperationGuardDatabaseFixture()
        let clientDatabase = try clientFixture.open()
        let client = try clientCommand(id: "malformed-client", client: "malformed-client")
        try await insertIsolatedRelation(
            "pending_allocation", id: client.envelope.operationId.rawValue,
            database: clientDatabase
        )
        let clientBaseline = try await reservationCounts(clientDatabase)
        await #expect(throws: ClientCreationFailure.localAcceptanceFailed) {
            _ = try await ClientCreationPowerSyncStore(database: clientDatabase).create(client)
        }
        #expect(try await reservationCounts(clientDatabase) == clientBaseline)
        try await clientDatabase.close(deleteDatabase: true)
        clientFixture.remove()

        let projectFixture = try LocalOperationGuardDatabaseFixture()
        let projectDatabase = try projectFixture.open()
        let project = try projectCommand(id: "malformed-project")
        try await insertIsolatedRelation(
            "pending_allocation", id: project.envelope.operationId.rawValue,
            database: projectDatabase
        )
        let projectBaseline = try await reservationCounts(projectDatabase)
        await #expect(throws: ProjectSetupFailure.localAcceptanceFailed) {
            _ = try await ProjectSetupPowerSyncStore(database: projectDatabase).create(project)
        }
        #expect(try await reservationCounts(projectDatabase) == projectBaseline)
        try await projectDatabase.close(deleteDatabase: true)
        projectFixture.remove()

        let projectArchiveFixture = try LocalOperationGuardDatabaseFixture()
        let projectArchiveDatabase = try projectArchiveFixture.open()
        let projectArchive = try projectArchiveCommand(index: 820)
        try await insertIsolatedRelation(
            "pending_allocation", id: projectArchive.envelope.operationId.rawValue,
            database: projectArchiveDatabase
        )
        let projectArchiveBaseline = try await reservationCounts(projectArchiveDatabase)
        await #expect(throws: ProjectArchivePowerSyncFailure.malformedLocalEvidence) {
            _ = try await ProjectArchivePowerSyncStore(
                database: projectArchiveDatabase, accountId: guardAccountId,
                principalId: guardPrincipalId
            ).archive(projectArchive)
        }
        #expect(try await reservationCounts(projectArchiveDatabase) == projectArchiveBaseline)
        try await projectArchiveDatabase.close(deleteDatabase: true)
        projectArchiveFixture.remove()

        let clientArchiveFixture = try LocalOperationGuardDatabaseFixture()
        let clientArchiveDatabase = try clientArchiveFixture.open()
        let clientArchive = try clientArchiveCommand(index: 821)
        try await insertIsolatedRelation(
            "pending_allocation", id: clientArchive.envelope.operationId.rawValue,
            database: clientArchiveDatabase
        )
        let clientArchiveBaseline = try await reservationCounts(clientArchiveDatabase)
        await #expect(throws: ClientArchivePowerSyncFailure.malformedLocalEvidence) {
            _ = try await ClientArchivePowerSyncStore(
                database: clientArchiveDatabase, accountId: guardAccountId,
                principalId: guardPrincipalId
            ).archive(clientArchive)
        }
        #expect(try await reservationCounts(clientArchiveDatabase) == clientArchiveBaseline)
        try await clientArchiveDatabase.close(deleteDatabase: true)
        clientArchiveFixture.remove()

        let assignmentFixture = try LocalOperationGuardDatabaseFixture()
        let assignmentDatabase = try assignmentFixture.open()
        let assignment = try assignmentCommand(id: "malformed-assignment")
        try await insertIsolatedRelation(
            "pending_allocation", id: assignment.envelope.operationId.rawValue,
            database: assignmentDatabase
        )
        let assignmentBaseline = try await reservationCounts(assignmentDatabase)
        await #expect(throws: ItemSpaceAssignmentPowerSyncStoreFailure.malformedLocalEvidence) {
            _ = try await ItemSpaceAssignmentPowerSyncStore(
                database: assignmentDatabase, accountId: guardAccountId,
                principalId: guardPrincipalId
            ).assignItemsToSpace(assignment)
        }
        #expect(try await reservationCounts(assignmentDatabase) == assignmentBaseline)
        try await assignmentDatabase.close(deleteDatabase: true)
        assignmentFixture.remove()

        let clearingFixture = try LocalOperationGuardDatabaseFixture()
        let clearingDatabase = try clearingFixture.open()
        let clearing = try clearingCommand(id: "malformed-clearing")
        try await insertIsolatedRelation(
            "pending_allocation", id: clearing.envelope.operationId.rawValue,
            database: clearingDatabase
        )
        let clearingBaseline = try await reservationCounts(clearingDatabase)
        await #expect(throws: ItemSpaceClearingPowerSyncStoreFailure.malformedLocalEvidence) {
            _ = try await ItemSpaceClearingPowerSyncStore(
                database: clearingDatabase, accountId: guardAccountId,
                principalId: guardPrincipalId
            ).clearItemSpaceAssignments(clearing)
        }
        #expect(try await reservationCounts(clearingDatabase) == clearingBaseline)
        try await clearingDatabase.close(deleteDatabase: true)
        clearingFixture.remove()
    }

    private static let guardAccountId = try! AccountID(validating: "account-guard")
    private static let guardPrincipalId = try! PrincipalID(validating: "principal-guard")
    private static let guardAcceptedAt = Date(timeIntervalSince1970: 1_800_000_000)
    private static let guardProjectId = try! ProjectID(validating: "project-guard")
    private static let guardClientId = try! ClientID(validating: "client-guard")

    private static func projectArchiveCommand(index: Int) throws -> ArchiveProjectCommand {
        try projectArchiveCommand(operationId: ProjectArchiveOperationIdentity.make(
            accountId: guardAccountId,
            uuid: checkpointUUID(index: index)
        ))
    }

    private static func projectArchiveCommand(
        operationId: OperationID
    ) throws -> ArchiveProjectCommand {
        try ArchiveProjectCommand(
            operationId: operationId,
            draft: ProjectArchiveDraft(
                accountId: guardAccountId,
                actorPrincipalId: guardPrincipalId,
                operationContractVersion: OperationContractVersion(
                    validating: "project-archive-v1"
                ),
                projectId: guardProjectId,
                expectedRevision: ExpectedProjectRevision(1),
                capturedAt: guardAcceptedAt
            )
        )
    }

    private static func clientArchiveCommand(index: Int) throws -> ArchiveClientCommand {
        try clientArchiveCommand(operationId: ClientArchiveOperationIdentity.make(
            accountId: guardAccountId,
            uuid: checkpointUUID(index: index)
        ))
    }

    private static func clientArchiveCommand(
        operationId: OperationID
    ) throws -> ArchiveClientCommand {
        try ArchiveClientCommand(
            operationId: operationId,
            draft: ClientArchiveDraft(
                accountId: guardAccountId,
                actorPrincipalId: guardPrincipalId,
                operationContractVersion: OperationContractVersion(
                    validating: "client-archive-v1"
                ),
                clientId: guardClientId,
                expectedRevision: ExpectedClientRevision(1),
                capturedAt: guardAcceptedAt
            )
        )
    }

    private static func assignmentCommand(id: String) throws -> AssignItemsToSpaceCommand {
        try AssignItemsToSpaceCommand(
            operationId: OperationID(validating: id),
            draft: ItemSpaceAssignmentDraft(
                accountId: guardAccountId,
                actorPrincipalId: guardPrincipalId,
                operationContractVersion: OperationContractVersion(
                    validating: "item-space-assignment-v1"
                ),
                destinationSpaceId: SpaceID(validating: "space-guard"),
                scope: .businessInventory,
                expectedSpaceRevision: ExpectedSpaceRevision(1),
                items: [
                    ItemSpaceAssignmentCandidate(
                        itemId: ItemID(validating: "item-guard"),
                        expectedRevision: ExpectedItemPlacementRevision(1)
                    )
                ],
                capturedAt: guardAcceptedAt
            )
        )
    }

    private static func clearingCommand(id: String) throws -> ClearItemSpaceAssignmentsCommand {
        try ClearItemSpaceAssignmentsCommand(
            operationId: OperationID(validating: id),
            draft: ItemSpaceClearingDraft(
                accountId: guardAccountId,
                actorPrincipalId: guardPrincipalId,
                operationContractVersion: OperationContractVersion(
                    validating: "item-space-clearing-v1"
                ),
                scope: .businessInventory,
                items: [
                    ItemSpaceClearingCandidate(
                        itemId: ItemID(validating: "item-clear-guard"),
                        expectedRevision: ExpectedItemPlacementRevision(1),
                        currentSpaceId: SpaceID(validating: "space-clear-guard")
                    )
                ],
                capturedAt: guardAcceptedAt
            )
        )
    }

    private static func concurrentOperationId(
        for families: [LocalOperationCommandFamily],
        index: Int
    ) throws -> OperationID {
        if families.contains(.createInvoice) {
            return try InvoiceCreationOperationIdentity.make(accountId: guardAccountId, uuid: checkpointUUID(index: index))
        }
        if families.contains(.editExpense) {
            return try AccountBoundOperationIdentity.make(family: .expenseEdit, accountId: guardAccountId, uuid: checkpointUUID(index: index))
        }
        if families.contains(.createExpense) {
            return try ExpenseCreationOperationIdentity.make(accountId: guardAccountId, uuid: checkpointUUID(index: index))
        }
        if families.contains(.sellInventoryItems) {
            return try InventorySaleOperationIdentity.make(accountId: guardAccountId, uuid: checkpointUUID(index: index))
        }
        if families.contains(.manageCategories) {
            return try CategoryManagementOperationIdentity.make(accountId: guardAccountId, uuid: checkpointUUID(index: index))
        }
        if families.contains(.archiveProject) {
            return try ProjectArchiveOperationIdentity.make(
                accountId: guardAccountId,
                uuid: checkpointUUID(index: index)
            )
        }
        if families.contains(.archiveClient) {
            return try ClientArchiveOperationIdentity.make(
                accountId: guardAccountId,
                uuid: checkpointUUID(index: index)
            )
        }
        if families.contains(.reviseSpaceChecklists) {
            return try SpaceChecklistRevisionOperationIdentity.make(
                accountId: guardAccountId,
                uuid: checkpointUUID(index: index)
            )
        }
        return try OperationID(validating: "concurrent-guard-\(index)")
    }

    private static func seedAuthorityIfNeeded(
        for families: [LocalOperationCommandFamily],
        database: any PowerSyncDatabaseProtocol
    ) async throws {
        if families.contains(.manageCategories) || families.contains(.sellInventoryItems) || families.contains(.createExpense) || families.contains(.editExpense) || families.contains(.createInvoice) {
            _ = try await database.execute(sql: """
                INSERT OR REPLACE INTO spike_account_memberships(id,account_id,principal_id,state,financial_access)
                VALUES ('category-test-member', ?, ?, 'active', 'full')
                """, parameters: [guardAccountId.rawValue, guardPrincipalId.rawValue])
        }
        if families.contains(.createExpense) || families.contains(.editExpense) {
            _ = try await database.execute(sql: "INSERT OR REPLACE INTO spike_budget_categories(id,account_id,kind,lifecycle) VALUES ('expense-category',?,'general','active')", parameters: [guardAccountId.rawValue])
        }
        if families.contains(.editExpense) || families.contains(.createInvoice) {
            _ = try await database.execute(sql: "INSERT OR REPLACE INTO expenses(id,account_id,project_id,revision,currency,final_amount_minor_units) VALUES ('expense',?,'project','1','USD','100')", parameters: [guardAccountId.rawValue])
        }
        if families.contains(.sellInventoryItems) || families.contains(.createExpense) || families.contains(.editExpense) || families.contains(.createInvoice) {
            _ = try await database.execute(sql: "INSERT OR REPLACE INTO spike_clients(id,account_id,display_name,lifecycle,revision,created_at_ms,updated_at_ms) VALUES ('sale-client',?,'Client','active',1,1,1)",
                parameters: [guardAccountId.rawValue])
            _ = try await database.execute(sql: "INSERT OR REPLACE INTO spike_projects(id,account_id,client_id,display_name,lifecycle,revision) VALUES ('project',?,'sale-client','Project','active',1)",
                parameters: [guardAccountId.rawValue])
            _ = try await database.execute(sql: """
                INSERT OR REPLACE INTO spike_item_placements(id,account_id,item_id,scope_kind)
                VALUES ('sale-old',?,'sale-item','business_inventory')
                """, parameters: [guardAccountId.rawValue])
        }
        if families.contains(.archiveProject) { try await seedArchiveProject(database) }
        if families.contains(.archiveClient) { try await seedArchiveClient(database) }
        if families.contains(.reviseSpaceChecklists) {
            try await seedChecklistSpace(database)
        }
    }

    private static func submit(
        _ family: LocalOperationCommandFamily,
        operationId: OperationID,
        database: any PowerSyncDatabaseProtocol
    ) async throws -> OperationReceipt {
        switch family {
        case .createInvoice:
            return try await submitInvoice(operationId, changed: false, database: database)
        case .editExpense:
            return try await submitExpense(operationId, changed: false, edit: true, database: database)
        case .createExpense:
            return try await submitExpense(operationId, changed: false, database: database)
        case .sellInventoryItems:
            return try await submitSale(operationId, changed: false, database: database)
        case .manageCategories:
            return try await submitCategory(operationId, changed: false, database: database)
        case .createClient:
            return try await ClientCreationPowerSyncStore(database: database).create(
                clientCommand(id: operationId.rawValue, client: "client-concurrent")
            )
        case .createProject:
            return try await ProjectSetupPowerSyncStore(database: database).create(
                projectCommand(id: operationId.rawValue)
            )
        case .archiveProject:
            return try await ProjectArchivePowerSyncStore(
                database: database, accountId: guardAccountId,
                principalId: guardPrincipalId, now: { guardAcceptedAt }
            ).archive(projectArchiveCommand(operationId: operationId))
        case .archiveClient:
            return try await ClientArchivePowerSyncStore(
                database: database, accountId: guardAccountId,
                principalId: guardPrincipalId, now: { guardAcceptedAt }
            ).archive(clientArchiveCommand(operationId: operationId))
        case .reviseSpaceChecklists:
            return try await SpaceChecklistRevisionPowerSyncStore(
                database: database, accountId: guardAccountId,
                principalId: guardPrincipalId, now: { guardAcceptedAt }
            ).reviseChecklists(checklistRevisionCommand(operationId: operationId))
        case .assignItemsToSpace:
            return try await ItemSpaceAssignmentPowerSyncStore(
                database: database, accountId: guardAccountId,
                principalId: guardPrincipalId, now: { guardAcceptedAt }
            ).assignItemsToSpace(assignmentCommand(id: operationId.rawValue))
        case .clearItemSpaceAssignments:
            return try await ItemSpaceClearingPowerSyncStore(
                database: database, accountId: guardAccountId,
                principalId: guardPrincipalId, now: { guardAcceptedAt }
            ).clearItemSpaceAssignments(clearingCommand(id: operationId.rawValue))
        }
    }

    private static func submitRaceOutcome(
        _ family: LocalOperationCommandFamily,
        operationId: OperationID,
        changed: Bool,
        database: any PowerSyncDatabaseProtocol
    ) async -> String {
        do {
            if changed {
                _ = try await submitChanged(
                    family, operationId: operationId, database: database
                )
            } else {
                _ = try await submit(
                    family, operationId: operationId, database: database
                )
            }
            return "success"
        } catch OperationContractFailure.payloadMismatch(let rejectedID) {
            return rejectedID == operationId ? "payloadMismatch" : "wrongOperationID"
        } catch {
            return "other:\(String(describing: type(of: error)))"
        }
    }

    private static func expectOneCompleteGraph(
        operationId: OperationID,
        database: any PowerSyncDatabaseProtocol
    ) async throws {
        let owner = try await database.get(
            sql: "SELECT command_type, fingerprint FROM \(LedgerPowerSyncTable.localOperations) WHERE id = ?",
            parameters: [operationId.rawValue]
        ) { cursor in
            (
                try cursor.getString(name: "command_type"),
                try cursor.getString(name: "fingerprint")
            )
        }
        let family = try #require(LocalOperationCommandFamily(rawValue: owner.0))
        #expect(try await Self.inspect(
            database, id: operationId, family: family, fingerprint: owner.1
        ) == .matchingOwner)
        #expect(try await Self.count(LedgerPowerSyncTable.operationResults, database) == 0)
    }

    private static func submitCategory(_ operationId: OperationID, changed: Bool,
                                      database: any PowerSyncDatabaseProtocol) async throws -> OperationReceipt {
        let command = try CategoryManagementCommand(operationId: operationId, accountId: guardAccountId,
            actorPrincipalId: guardPrincipalId, capturedAt: guardAcceptedAt,
            payload: CategoryManagementPayload(action: .create, categoryId: BudgetCategoryID(validating: "category-guard"),
                name: BudgetCategoryName(validating: changed ? "Changed" : "New category"),
                kind: .general, excludesFromOverallBudget: false))
        return try await CategoryManagementPowerSyncStore(database: database,
            accountId: guardAccountId, principalId: guardPrincipalId,
            accessFence: LedgerWorkspaceAccessFence(), isDirectoryComplete: { true },
            now: { guardAcceptedAt }).submit(command)
    }

    private static func submitSale(_ operationId: OperationID, changed: Bool,
                                   database: any PowerSyncDatabaseProtocol) async throws -> OperationReceipt {
        let command = try InventorySaleCommand(operationId: operationId, accountId: guardAccountId,
            actorPrincipalId: guardPrincipalId, capturedAt: guardAcceptedAt,
            payload: .init(projectId: .init(validating: "project"), currency: .init(validating: "USD"),
                items: [.init(itemId: .init(validating: "sale-item"), placementId: .init(validating: "sale-old"),
                    priceRevision: 0, reviewedPriceMinorUnits: changed ? 200 : 100,
                    newPlacementId: .init(validating: "sale-new"), occurrenceId: .init(validating: "sale-charge"))]))
        return try await InventorySalePowerSyncStore(database: database, accountId: guardAccountId,
            principalId: guardPrincipalId, accessFence: LedgerWorkspaceAccessFence(), now: { guardAcceptedAt }).submit(command)
    }

    @Test("Expense edit is atomic, survives encrypted reopen, and drains with a terminal receipt")
    func expenseEditDurability() async throws {
        let fixture = try LocalOperationGuardDatabaseFixture()
        defer { fixture.remove() }
        let first = try fixture.open()
        try await Self.seedAuthorityIfNeeded(for: [.editExpense], database: first)
        let id = try Self.concurrentOperationId(for: [.editExpense], index: 901)
        _ = try await first.execute(sql: "UPDATE expenses SET revision='2' WHERE id='expense'", parameters: nil)
        await #expect(throws: ExpenseCreationPowerSyncStore.Failure.self) {
            try await Self.submitExpense(id, changed: false, edit: true, database: first)
        }
        _ = try await first.execute(sql: "UPDATE expenses SET revision='1' WHERE id='expense'", parameters: nil)
        _ = try await first.execute(sql: "INSERT INTO collected_invoice_lines(id,account_id,source_kind,source_id) VALUES ('paid',?,'expense','expense')", parameters: [Self.guardAccountId.rawValue])
        await #expect(throws: ExpenseCreationPowerSyncStore.Failure.self) {
            try await Self.submitExpense(id, changed: false, edit: true, database: first)
        }
        #expect(try await Self.count(LedgerPowerSyncTable.localOperations, first) == 0)
        _ = try await first.execute(sql: "DELETE FROM collected_invoice_lines WHERE id='paid'", parameters: nil)
        // Direct fixture seeding queues writes; discard only those synthetic setup writes.
        while let setup = try await first.getNextCrudTransaction() { try await setup.complete() }
        _ = try await Self.submitExpense(id, changed: false, edit: true, database: first)
        try await first.close()
        let reopened = try fixture.open()
        let receipt = try await Self.submitExpense(id, changed: false, edit: true, database: reopened)
        #expect(receipt.localState == .queued)
        let transaction = try #require(try await reopened.getNextCrudTransaction())
        let entry = try #require(transaction.crud.first)
        #expect(transaction.crud.count == 1)
        try await ExpenseCreationUpload.applyEdit(entry, database: reopened, accessFence: .init(), applier: ExpenseEditReply())
        try await transaction.complete()
        let terminal = try await Self.submitExpense(id, changed: false, edit: true, database: reopened)
        #expect(terminal.localState == .applied)
        #expect(try await reopened.getNextCrudTransaction() == nil)
        let revision = try await reopened.get("SELECT revision FROM expenses WHERE id='expense'") { try $0.getString(index: 0) }
        #expect(revision == "1", "Uploading must not fabricate synced Expense facts")
        try await reopened.close()
    }

    private struct ExpenseEditReply: EditExpenseCommandApplying {
        func apply(_ command: EditExpenseCommand) async throws -> EditExpenseServerResult {
            let e = command.envelope, fingerprint = try EditExpenseUploadRequest(command).fingerprint
            let time = Int64(e.clientCreatedAt.timeIntervalSince1970 * 1000)
            return ExpenseServerResult(operation_id: e.operationId.rawValue, account_id: e.accountId.rawValue,
                actor_principal_id: e.actorPrincipalId.rawValue, command_type: "edit_expense", contract_version: "expense-edit-v1",
                command_fingerprint: fingerprint, envelope_sha256: fingerprint, subject_id: e.payload.entry.expenseId.rawValue,
                phase: "applied", request_sha256: nil, result_code: "expense_edited", error_code: nil,
                client_created_at_ms: time, server_received_at_ms: time, completed_at_ms: time)
        }
    }

    @Test("Invoice acceptance is atomic and survives encrypted restart")
    func invoiceAcceptanceDurability() async throws {
        let fixture = try LocalOperationGuardDatabaseFixture()
        defer { fixture.remove() }
        let first = try fixture.open()
        try await Self.seedAuthorityIfNeeded(for: [.createInvoice], database: first)
        let id = try Self.concurrentOperationId(for: [.createInvoice], index: 902)
        let foreignID = try ExpenseCreationOperationIdentity.make(accountId: Self.guardAccountId, uuid: Self.checkpointUUID(index: 903))
        await #expect(throws: InvoiceCreationPowerSyncStore.Failure.invalidIdentity) {
            try await Self.submitInvoice(foreignID, changed: false, database: first)
        }
        let baseline = try await Self.count("ps_crud", first)
        await #expect(throws: LocalOperationGuardInjectedFailure.self) {
            try await Self.submitInvoice(id, changed: false, database: first,
                checkpoint: { throw LocalOperationGuardInjectedFailure() })
        }
        #expect(try await Self.count("spike_local_operations", first) == 0)
        #expect(try await Self.count("ps_crud", first) == baseline)
        let receipt = try await Self.submitInvoice(id, changed: false, database: first)
        #expect(receipt.localState == .queued)
        #expect(try await Self.count("live_invoices", first) == 0)
        try await first.close()
        let reopened = try fixture.open()
        #expect(try await Self.submitInvoice(id, changed: false, database: reopened) == receipt)
        await #expect(throws: OperationContractFailure.payloadMismatch(id)) {
            try await Self.submitInvoice(id, changed: true, database: reopened)
        }
        #expect(try await Self.count("spike_local_operations", reopened) == 1)
        _ = try await reopened.execute(sql: "UPDATE spike_account_memberships SET financial_access='none'", parameters: nil)
        await #expect(throws: ProjectInvoicingItemLocalReader.Failure.self) {
            try await Self.submitInvoice(id, changed: false, database: reopened)
        }
        try await reopened.close()
    }

    @Test("Invoice upload retains retry and rejection evidence", arguments: [false, true])
    func invoiceUploadTerminalEvidence(rejected: Bool) async throws {
        let fixture = try LocalOperationGuardDatabaseFixture()
        defer { fixture.remove() }
        let db = try fixture.open()
        try await Self.seedAuthorityIfNeeded(for: [.createInvoice], database: db)
        while let setup = try await db.getNextCrudTransaction() { try await setup.complete() }
        let id = try Self.concurrentOperationId(for: [.createInvoice], index: rejected ? 905 : 904)
        _ = try await Self.submitInvoice(id, changed: false, database: db)
        let transaction = try #require(try await db.getNextCrudTransaction())
        let entry = try #require(transaction.crud.first)
        #expect(transaction.crud.count == 1)
        let query = LiveInvoicePowerSyncQuery(database: db)
        let project = try ProjectID(validating: "project")
        let pending = try await query.readPendingCreations(accountId: Self.guardAccountId,
            principalId: Self.guardPrincipalId, projectId: project)
        #expect(pending.count == 1)
        #expect(pending.first?.state == .queued)
        await #expect(throws: LocalOperationGuardInjectedFailure.self) {
            try await InvoiceCreationUpload.apply(entry, database: db, accessFence: .init(),
                applier: InvoiceReply(rejected: rejected, transportFailure: true))
        }
        #expect(try await Self.submitInvoice(id, changed: false, database: db).localState == .applying)
        await #expect(throws: CreateInvoiceServerResult.Failure.receiptMismatch) {
            try await InvoiceCreationUpload.apply(entry, database: db, accessFence: .init(),
                applier: InvoiceReply(rejected: rejected, wrongSubject: true))
        }
        try await InvoiceCreationUpload.apply(entry, database: db, accessFence: .init(), applier: InvoiceReply(rejected: rejected))
        // A crash after result persistence but before CRUD acknowledgement replays safely.
        try await InvoiceCreationUpload.apply(entry, database: db, accessFence: .init(), applier: InvoiceReply(rejected: rejected))
        try await transaction.complete()
        #expect(try await Self.submitInvoice(id, changed: false, database: db).localState == (rejected ? .rejected : .applied))
        #expect(try await db.getNextCrudTransaction() == nil)
        #expect(try await Self.count("live_invoices", db) == 0, "Result handling does not invent downloaded facts")
        #expect(try await query.readPendingCreations(accountId: Self.guardAccountId,
            principalId: Self.guardPrincipalId, projectId: project).first?.state == (rejected ? .rejected : .applied))
        try await db.close()
        let reopened = try fixture.open()
        #expect(try await Self.submitInvoice(id, changed: false, database: reopened).localState == (rejected ? .rejected : .applied))
        let reopenedQuery = LiveInvoicePowerSyncQuery(database: reopened)
        #expect(try await reopenedQuery.readPendingCreations(accountId: Self.guardAccountId,
            principalId: Self.guardPrincipalId, projectId: project).count == 1)
        _ = try await reopened.execute(sql: "INSERT INTO live_invoices(id,account_id,project_id) VALUES ('invoice',?,'project')",
            parameters: [Self.guardAccountId.rawValue])
        #expect(try await reopenedQuery.readPendingCreations(accountId: Self.guardAccountId,
            principalId: Self.guardPrincipalId, projectId: project).count == (rejected ? 1 : 0),
            "Only a successful creation may disappear when its authoritative Invoice arrives")
        _ = try await reopened.execute(sql: "UPDATE spike_account_memberships SET financial_access='none'", parameters: nil)
        await #expect(throws: ProjectInvoicingItemLocalReader.Failure.self) {
            try await reopenedQuery.readPendingCreations(accountId: Self.guardAccountId,
                principalId: Self.guardPrincipalId, projectId: project)
        }
        try await reopened.close()
    }

    @Test("Invoice upload cannot acknowledge a result after financial access is withdrawn")
    func invoiceUploadAccessWithdrawal() async throws {
        let fixture = try LocalOperationGuardDatabaseFixture()
        defer { fixture.remove() }
        let db = try fixture.open()
        try await Self.seedAuthorityIfNeeded(for: [.createInvoice], database: db)
        while let setup = try await db.getNextCrudTransaction() { try await setup.complete() }
        let id = try Self.concurrentOperationId(for: [.createInvoice], index: 906)
        _ = try await Self.submitInvoice(id, changed: false, database: db)
        let transaction = try #require(try await db.getNextCrudTransaction())
        let entry = try #require(transaction.crud.first)
        await #expect(throws: ProjectInvoicingItemLocalReader.Failure.self) {
            try await InvoiceCreationUpload.apply(entry, database: db, accessFence: .init(),
                applier: InvoiceReply(rejected: false, beforeReply: {
                    _ = try await db.execute(sql: "UPDATE spike_account_memberships SET financial_access='none'", parameters: nil)
                }))
        }
        let state = try await db.get(sql: "SELECT local_state FROM spike_local_operations WHERE id=?",
            parameters: [id.rawValue]) { try $0.getString(index: 0) }
        #expect(state == "applying", "Keep the operation for authorized recovery; do not claim a terminal result")
        #expect(try await db.getNextCrudTransaction() != nil)
        #expect(try await Self.count("live_invoices", db) == 0)
        try await db.close()
    }

    private struct InvoiceReply: CreateInvoiceCommandApplying {
        let rejected: Bool
        var transportFailure = false
        var wrongSubject = false
        var beforeReply: @Sendable () async throws -> Void = {}
        func apply(_ command: CreateInvoiceCommand) async throws -> CreateInvoiceServerResult {
            if transportFailure { throw LocalOperationGuardInjectedFailure() }
            try await beforeReply()
            let e = command.envelope, fingerprint = try CreateInvoiceUploadRequest(command).fingerprint
            let time = Int64((e.clientCreatedAt.timeIntervalSince1970 * 1000).rounded())
            return .init(operation_id: e.operationId.rawValue, account_id: e.accountId.rawValue,
                actor_principal_id: e.actorPrincipalId.rawValue, command_type: "create_invoice", contract_version: "invoice-create-v1",
                command_fingerprint: fingerprint, envelope_sha256: fingerprint,
                subject_id: wrongSubject ? "wrong" : e.payload.invoiceId.rawValue, phase: rejected ? "rejected" : "applied",
                request_sha256: nil, result_code: rejected ? nil : "invoice_created",
                error_code: rejected ? "invoice_source_changed" : nil,
                client_created_at_ms: time, server_received_at_ms: time, completed_at_ms: time)
        }
    }

    private static func submitInvoice(_ operationId: OperationID, changed: Bool, database: any PowerSyncDatabaseProtocol,
                                      checkpoint: @escaping @Sendable () throws -> Void = {}) async throws -> OperationReceipt {
        let command = try CreateInvoiceCommand(operationId: operationId, actorPrincipalId: guardPrincipalId,
            capturedAt: guardAcceptedAt, payload: .init(invoiceId: .init(validating: "invoice"),
                selection: .init(scope: .project(accountId: guardAccountId, projectId: .init(validating: "project"),
                    clientId: .init(validating: "sale-client")), lines: [
                        .init(source: .expense(.init(validating: "expense")), expectedRevision: 1,
                            reviewedAmount: .init(minorUnits: 100, currency: .init(validating: "USD")))]),
                name: changed ? "Changed" : "Invoice", notes: ""))
        return try await InvoiceCreationPowerSyncStore(database: database, accountId: guardAccountId,
            principalId: guardPrincipalId, accessFence: .init(), now: { guardAcceptedAt }, afterOperationWrite: checkpoint).submit(command)
    }

    private static func submitExpense(_ operationId: OperationID, changed: Bool, edit: Bool = false, database: any PowerSyncDatabaseProtocol) async throws -> OperationReceipt {
        let command = try CreateExpenseCommand(operationId: operationId, actorPrincipalId: guardPrincipalId,
            capturedAt: guardAcceptedAt, draft: .init(accountId: guardAccountId, projectId: .init(validating: "project"),
                expenseId: .init(validating: "expense"), vendor: "Vendor", date: "2024-02-29",
                finalAmount: .init(minorUnits: changed ? 200 : 100, currency: .init(validating: "USD")),
                categoryId: .init(validating: "expense-category"), notes: ""))
        let store = ExpenseCreationPowerSyncStore(database: database, accountId: guardAccountId,
            principalId: guardPrincipalId, accessFence: .init(), now: { guardAcceptedAt })
        if edit {
            return try await store.submit(EditExpenseCommand(operationId: operationId, actorPrincipalId: guardPrincipalId,
                capturedAt: guardAcceptedAt, expectedRevision: 1, entry: command.envelope.payload))
        }
        return try await store.submit(command)
    }

    private static func submitChanged(
        _ family: LocalOperationCommandFamily,
        operationId: OperationID,
        database: any PowerSyncDatabaseProtocol
    ) async throws -> OperationReceipt {
        switch family {
        case .createInvoice:
            return try await submitInvoice(operationId, changed: true, database: database)
        case .editExpense:
            return try await submitExpense(operationId, changed: true, edit: true, database: database)
        case .createExpense:
            return try await submitExpense(operationId, changed: true, database: database)
        case .sellInventoryItems:
            return try await submitSale(operationId, changed: true, database: database)
        case .manageCategories:
            return try await submitCategory(operationId, changed: true, database: database)
        case .createClient:
            let command = try CreateClientCommand(
                operationId: operationId,
                draft: ClientCreationDraft(
                    accountId: AccountID(validating: "account"),
                    actorPrincipalId: PrincipalID(validating: "principal"),
                    operationContractVersion: OperationContractVersion(
                        validating: "client-create-v1"
                    ),
                    clientId: ClientID(validating: "client-concurrent"),
                    displayName: ClientDisplayName(validating: "Changed Client"),
                    capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
                )
            )
            return try await ClientCreationPowerSyncStore(database: database).create(command)
        case .createProject:
            let base = try projectCommand(id: operationId.rawValue)
            let command = try CreateProjectCommand(
                operationId: operationId,
                draft: ProjectSetupDraft(
                    accountId: base.envelope.accountId,
                    actorPrincipalId: base.envelope.actorPrincipalId,
                    operationContractVersion: base.envelope.contractVersion,
                    projectId: base.draft.projectId,
                    clientSelection: base.draft.clientSelection,
                    displayName: ProjectDisplayName(validating: "Changed Project"),
                    description: base.draft.description,
                    categoryAllocations: base.draft.categoryAllocations,
                    capturedAt: base.draft.capturedAt
                )
            )
            return try await ProjectSetupPowerSyncStore(database: database).create(command)
        case .archiveProject:
            let base = try projectArchiveCommand(operationId: operationId)
            let command = try ArchiveProjectCommand(
                operationId: operationId,
                draft: ProjectArchiveDraft(
                    accountId: base.envelope.accountId,
                    actorPrincipalId: base.envelope.actorPrincipalId,
                    operationContractVersion: base.envelope.contractVersion,
                    projectId: base.draft.projectId,
                    expectedRevision: base.draft.expectedRevision,
                    capturedAt: guardAcceptedAt.addingTimeInterval(1)
                )
            )
            return try await ProjectArchivePowerSyncStore(
                database: database, accountId: guardAccountId,
                principalId: guardPrincipalId, now: { guardAcceptedAt }
            ).archive(command)
        case .archiveClient:
            let base = try clientArchiveCommand(operationId: operationId)
            let command = try ArchiveClientCommand(
                operationId: operationId,
                draft: ClientArchiveDraft(
                    accountId: base.envelope.accountId,
                    actorPrincipalId: base.envelope.actorPrincipalId,
                    operationContractVersion: base.envelope.contractVersion,
                    clientId: base.draft.clientId,
                    expectedRevision: base.draft.expectedRevision,
                    capturedAt: guardAcceptedAt.addingTimeInterval(1)
                )
            )
            return try await ClientArchivePowerSyncStore(
                database: database, accountId: guardAccountId,
                principalId: guardPrincipalId, now: { guardAcceptedAt }
            ).archive(command)
        case .reviseSpaceChecklists:
            let base = try checklistRevisionCommand(operationId: operationId)
            let command = try ReviseSpaceChecklistsCommand(
                operationId: operationId,
                draft: SpaceChecklistRevisionDraft(
                    accountId: base.envelope.accountId,
                    actorPrincipalId: base.envelope.actorPrincipalId,
                    operationContractVersion: base.envelope.contractVersion,
                    spaceId: base.draft.spaceId,
                    collection: SpaceChecklistCollection(checklists: [
                        SpaceChecklistState(
                            id: SpaceChecklistID(validating: "changed-checklist"),
                            name: SpaceChecklistName(validating: "Changed"),
                            presentationOrder: 1,
                            items: []
                        )
                    ]),
                    expectedRevision: base.draft.expectedRevision,
                    capturedAt: base.draft.capturedAt
                )
            )
            return try await SpaceChecklistRevisionPowerSyncStore(
                database: database, accountId: guardAccountId,
                principalId: guardPrincipalId, now: { guardAcceptedAt }
            ).reviseChecklists(command)
        case .assignItemsToSpace:
            let base = try assignmentCommand(id: operationId.rawValue)
            let command = try AssignItemsToSpaceCommand(
                operationId: operationId,
                draft: ItemSpaceAssignmentDraft(
                    accountId: base.envelope.accountId,
                    actorPrincipalId: base.envelope.actorPrincipalId,
                    operationContractVersion: base.envelope.contractVersion,
                    destinationSpaceId: base.draft.destinationSpaceId,
                    scope: base.draft.scope,
                    expectedSpaceRevision: base.draft.expectedSpaceRevision,
                    items: [
                        ItemSpaceAssignmentCandidate(
                            itemId: ItemID(validating: "item-guard-changed"),
                            expectedRevision: ExpectedItemPlacementRevision(1)
                        )
                    ],
                    capturedAt: base.draft.capturedAt
                )
            )
            return try await ItemSpaceAssignmentPowerSyncStore(
                database: database, accountId: guardAccountId,
                principalId: guardPrincipalId, now: { guardAcceptedAt }
            ).assignItemsToSpace(command)
        case .clearItemSpaceAssignments:
            let base = try clearingCommand(id: operationId.rawValue)
            let command = try ClearItemSpaceAssignmentsCommand(
                operationId: operationId,
                draft: ItemSpaceClearingDraft(
                    accountId: base.envelope.accountId,
                    actorPrincipalId: base.envelope.actorPrincipalId,
                    operationContractVersion: base.envelope.contractVersion,
                    scope: base.draft.scope,
                    items: [
                        ItemSpaceClearingCandidate(
                            itemId: ItemID(validating: "item-clear-guard-changed"),
                            expectedRevision: ExpectedItemPlacementRevision(1),
                            currentSpaceId: SpaceID(validating: "space-clear-guard")
                        )
                    ],
                    capturedAt: base.draft.capturedAt
                )
            )
            return try await ItemSpaceClearingPowerSyncStore(
                database: database, accountId: guardAccountId,
                principalId: guardPrincipalId, now: { guardAcceptedAt }
            ).clearItemSpaceAssignments(command)
        }
    }

    private static func checkpointUUID(index: Int) -> UUID {
        UUID(uuidString: String(
            format: "00000000-0000-4000-8000-%012x",
            index + 1
        ))!
    }

    private static func seedArchiveProject(
        _ database: any PowerSyncDatabaseProtocol
    ) async throws {
        _ = try await database.execute(sql: """
            INSERT INTO \(LedgerPowerSyncTable.projects) (
              id, account_id, client_id, display_name, lifecycle, revision,
              category_configuration_revision, created_at_ms, updated_at_ms,
              created_by_principal_id
            ) VALUES (?, ?, ?, 'Project', 'active', 1, '1', 1, 1, ?)
            """, parameters: [
                guardProjectId.rawValue, guardAccountId.rawValue,
                guardClientId.rawValue, guardPrincipalId.rawValue
            ])
    }

    private static func seedChecklistSpace(
        _ database: any PowerSyncDatabaseProtocol
    ) async throws {
        _ = try await database.execute(sql: """
            INSERT OR IGNORE INTO \(LedgerPowerSyncTable.spaces) (
              id, account_id, scope_kind, project_id, display_name, lifecycle, revision
            ) VALUES ('space-guard', ?, 'business_inventory', NULL,
                      'Guard Space', 'active', 1)
            """, parameters: [guardAccountId.rawValue])
    }

    private static func checklistRevisionCommand(
        operationId: OperationID
    ) throws -> ReviseSpaceChecklistsCommand {
        try ReviseSpaceChecklistsCommand(
            operationId: operationId,
            draft: SpaceChecklistRevisionDraft(
                accountId: guardAccountId,
                actorPrincipalId: guardPrincipalId,
                operationContractVersion: OperationContractVersion(
                    validating: "space-checklist-revision-v1"
                ),
                spaceId: SpaceID(validating: "space-guard"),
                collection: SpaceChecklistCollection(checklists: []),
                expectedRevision: ExpectedSpaceRevision(1),
                capturedAt: guardAcceptedAt
            )
        )
    }

    private static func seedArchiveClient(
        _ database: any PowerSyncDatabaseProtocol
    ) async throws {
        _ = try await database.execute(sql: """
            INSERT INTO \(LedgerPowerSyncTable.clients) (
              id, account_id, display_name, lifecycle, revision,
              created_at_ms, updated_at_ms, created_by_principal_id
            ) VALUES (?, ?, 'Client', 'active', 1, 1, 1, ?)
            """, parameters: [
                guardClientId.rawValue, guardAccountId.rawValue,
                guardPrincipalId.rawValue
            ])
    }
}

private final class LocalOperationGuardDatabaseFixture: @unchecked Sendable {
    private let directoryURL: URL
    private let databaseURL: URL
    private let key = try! LedgerPowerSyncEncryptionKey(
        hexadecimal: String(repeating: "4c", count: 32)
    )
    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-local-operation-guard-\(UUID().uuidString)")
        databaseURL = directoryURL.appendingPathComponent("ledger.sqlite")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }
    func open() throws -> any PowerSyncDatabaseProtocol {
        try LedgerPowerSyncDatabaseFactory.open(absolutePath: databaseURL.path, encryptionKey: key)
    }
    func remove() { try? FileManager.default.removeItem(at: directoryURL) }
}
