import Foundation
import PowerSync
import Testing
@testable import LedgerTargetCore
@testable import LedgerTargetPowerSync

@Suite("LedgerPowerSync attachment local byte durability provider", .serialized)
struct LedgerPowerSyncAttachmentDurabilityProviderTests {
    @Test("ATTACHDUR-TEST-001 ciphertext and queue reverify before path-free success")
    func encryptedAcceptance() async throws {
        let fixture = try Fixture()
        defer { fixture.removeDirectory() }
        let database = try fixture.openDatabase()
        let cipher = try await database.get("PRAGMA cipher") { cursor in
            try cursor.getString(index: 0)
        }
        #expect(!cipher.isEmpty)
        let vault = try fixture.makeVault()
        let store = fixture.makeStore(database: database, vault: vault)
        let capture = try fixture.capture()

        let receipt = try await store.enqueue(capture)
        #expect(receipt.attachmentId == capture.attachmentId)
        #expect(receipt.scope == capture.scope)
        #expect(receipt.byteCount == UInt64(Fixture.bytes.count))
        #expect(try await store.pendingCount() == 1)
        let candidate = try #require(try await store.nextVerifiedCandidate())
        #expect(candidate.receipt == receipt)
        #expect(candidate.bytes == Fixture.bytes)

        let objectURL = try await vault.objectFileURLForTesting(receipt.localObjectId)
        let ciphertext = try Data(contentsOf: objectURL)
        #expect(ciphertext != Fixture.bytes)
        #expect(!ciphertext.contains(Fixture.bytes))
        let rowText = try await database.get(
            "SELECT receipt_json FROM \(AttachmentCapturePowerSyncTable.queue)"
        ) { try $0.getString(index: 0) }
        for forbidden in [
            Fixture.bytes.base64EncodedString(), "file://", objectURL.path,
            "supabase", "firebase", "gs://", "https://"
        ] {
            #expect(!rowText.lowercased().contains(forbidden.lowercased()))
        }
        try await database.close()
        let rawDatabase = try Data(contentsOf: fixture.databaseURL)
        for forbidden in [
            Fixture.bytes,
            Data(receipt.attachmentId.rawValue.utf8),
            Data(receipt.scope.principalId.rawValue.utf8),
            Data(receipt.scope.accountId.rawValue.utf8),
            Data(receipt.scope.parent.id.rawValue.utf8),
            Data(receipt.contentSHA256.rawValue.utf8),
            Data(receipt.fingerprint.rawValue.utf8)
        ] {
            #expect(!rawDatabase.contains(forbidden))
        }
    }

    @Test("ATTACHDUR-TEST-002 receipt, order, count and bytes survive recreation")
    func restartDurability() async throws {
        let fixture = try Fixture()
        defer { fixture.removeDirectory() }
        let firstDatabase = try fixture.openDatabase()
        let firstStore = fixture.makeStore(database: firstDatabase, vault: try fixture.makeVault())
        let first = try await firstStore.enqueue(fixture.capture(id: "attachment-002-a"))
        let second = try await firstStore.enqueue(fixture.capture(id: "attachment-002-b"))
        try await firstDatabase.close()

        let reopened = try fixture.openDatabase()
        let restored = fixture.makeStore(database: reopened, vault: try fixture.makeVault())
        #expect(try await restored.pendingCount() == 2)
        let evidence = try await restored.pendingEvidence()
        #expect(evidence.compactMap(\.receipt) == [first, second])
        #expect(evidence.map(\.state) == [.pending, .pending])
        let candidate = try #require(try await restored.nextVerifiedCandidate())
        #expect(candidate.receipt == first)
        #expect(candidate.bytes == Fixture.bytes)
        #expect(try await restored.pendingCount() == 2)
        try await reopened.close()
    }

    @Test("ATTACHDUR-TEST-003 interruption is either committed or inventoried")
    func interruptionRecovery() async throws {
        for checkpoint in AttachmentVaultCheckpoint.allCases {
            let fixture = try Fixture(suffix: checkpoint.rawValue)
            defer { fixture.removeDirectory() }
            let database = try fixture.openDatabase()
            let vault = try fixture.makeVault { observed in
                if observed == checkpoint { throw InjectedFailure() }
            }
            let store = fixture.makeStore(database: database, vault: vault)
            if checkpoint == .beforeOrphanInventory {
                await #expect(throws: AttachmentCapturePowerSyncStoreFailure.mediaFailure(
                    .interrupted(.beforeOrphanInventory)
                )) {
                    _ = try await store.pendingWorkObservation()
                }
                try await database.close()
                continue
            }
            #expect(try await store.orphanInventory().isEmpty)
            await #expect(throws: (any Error).self) {
                try await store.enqueue(fixture.capture())
            }
            #expect(try await store.pendingCount() == 0)
            let orphans = try await store.orphanInventory()
            if checkpoint != .beforeStagingWrite {
                #expect(orphans.count == 1)
                #expect(
                    orphans[0].kind == (checkpoint == .afterPromotion ? .finalObject : .staging)
                )
            }
            try await database.close()
        }

        for checkpoint in AttachmentStoreCheckpoint.allCases {
            let fixture = try Fixture(suffix: checkpoint.rawValue)
            defer { fixture.removeDirectory() }
            let database = try fixture.openDatabase()
            let vault = try fixture.makeVault()
            let interrupted = fixture.makeStore(
                database: database,
                vault: vault,
                storeFault: { observed in
                    if observed == checkpoint { throw InjectedFailure() }
                }
            )
            await #expect(throws: (any Error).self) {
                try await interrupted.enqueue(fixture.capture())
            }
            let count = try await interrupted.pendingCount()
            if checkpoint == .beforeQueueCommit {
                #expect(count == 0)
                #expect(try await interrupted.orphanInventory().count == 1)
            } else {
                #expect(count == 1)
                let recovered = fixture.makeStore(database: database, vault: vault)
                #expect(try await recovered.enqueue(fixture.capture()).attachmentId == Fixture.attachmentID)
            }
            try await database.close()
        }
    }

    @Test("ATTACHDUR-TEST-004 missing, truncated, wrong-key and malformed evidence fail closed")
    func mediaFaultsRemainExplicit() async throws {
        let fixture = try Fixture()
        defer { fixture.removeDirectory() }
        let database = try fixture.openDatabase()
        let vault = try fixture.makeVault()
        let store = fixture.makeStore(database: database, vault: vault)
        let missingCapture = try fixture.capture(id: "attachment-004-missing")
        let missingReceipt = try await store.enqueue(missingCapture)
        let objectURL = try await vault.objectFileURLForTesting(missingReceipt.localObjectId)
        try FileManager.default.removeItem(at: objectURL)
        await #expect(throws: AttachmentCapturePowerSyncStoreFailure.missingBytes) {
            try await store.enqueue(missingCapture)
        }
        let directReplayState = try await database.get(
            sql: "SELECT state FROM \(AttachmentCapturePowerSyncTable.queue) WHERE id = ?",
            parameters: [missingReceipt.attachmentId.rawValue]
        ) { try $0.getString(index: 0) }
        #expect(directReplayState == AttachmentPendingState.missing.rawValue)
        var evidence = try await store.pendingEvidence()
        #expect(evidence.count == 1)
        #expect(evidence[0].state == .missing)
        #expect(try await store.nextVerifiedCandidate() == nil)
        #expect(try await store.pendingCount() == 1)

        let truncated = try await store.enqueue(fixture.capture(id: "attachment-004-truncated"))
        let truncatedURL = try await vault.objectFileURLForTesting(truncated.localObjectId)
        let truncatedCiphertext = try Data(contentsOf: truncatedURL).prefix(8)
        try Data(truncatedCiphertext).write(to: truncatedURL)
        evidence = try await store.pendingEvidence()
        #expect(
            evidence.first { $0.attachmentIdentifier == truncated.attachmentId.rawValue }?.state == .corrupt
        )

        let wrongKey = try await store.enqueue(fixture.capture(id: "attachment-004-wrong-key"))
        let wrongKeyURL = try await vault.objectFileURLForTesting(wrongKey.localObjectId)
        #expect(try Data(contentsOf: wrongKeyURL).count == Fixture.bytes.count + 28)
        #expect(throws: AttachmentLocalByteVaultFailure.invalidMediaKey) {
            try fixture.makeVault(keyByte: 0x99)
        }
        let wrongKeyState = try await database.get(
            sql: "SELECT state FROM \(AttachmentCapturePowerSyncTable.queue) WHERE id = ?",
            parameters: [wrongKey.attachmentId.rawValue]
        ) { try $0.getString(index: 0) }
        #expect(wrongKeyState == AttachmentPendingState.pending.rawValue)
        #expect(try await store.nextVerifiedCandidate()?.receipt.attachmentId == wrongKey.attachmentId)

        let countMismatch = try await store.enqueue(fixture.capture(id: "attachment-004-count"))
        _ = try await database.execute(
            sql: "UPDATE \(AttachmentCapturePowerSyncTable.queue) SET byte_count = 999 WHERE id = ?",
            parameters: [countMismatch.attachmentId.rawValue]
        )
        let digestMismatch = try await store.enqueue(fixture.capture(id: "attachment-004-digest"))
        _ = try await database.execute(
            sql: "UPDATE \(AttachmentCapturePowerSyncTable.queue) SET content_sha256 = ? WHERE id = ?",
            parameters: [String(repeating: "0", count: 64), digestMismatch.attachmentId.rawValue]
        )
        let nullEvidence = try await store.enqueue(fixture.capture(id: "attachment-004-null"))
        _ = try await database.execute(
            sql: "UPDATE \(AttachmentCapturePowerSyncTable.queue) SET receipt_json = NULL WHERE id = ?",
            parameters: [nullEvidence.attachmentId.rawValue]
        )
        evidence = try await store.pendingEvidence()
        for malformedID in [countMismatch, digestMismatch, nullEvidence].map(\.attachmentId.rawValue) {
            let malformed = evidence.first { $0.attachmentIdentifier == malformedID }
            #expect(malformed?.receipt == nil)
            #expect(malformed?.state == .corrupt)
        }
        #expect(try await store.pendingCount() == 6)
        try await database.close()
    }

    @Test("ATTACHDUR-TEST-005 exact replay deduplicates and rebinding refuses")
    func replayAndIdentityRules() async throws {
        let fixture = try Fixture()
        defer { fixture.removeDirectory() }
        let database = try fixture.openDatabase()
        let store = fixture.makeStore(database: database, vault: try fixture.makeVault())
        let capture = try fixture.capture()
        async let first = store.enqueue(capture)
        async let replay = store.enqueue(capture)
        let receipts = try await [first, replay]
        #expect(receipts[0] == receipts[1])
        #expect(try await store.pendingCount() == 1)

        let changed = try fixture.capture(bytes: Data("changed bytes".utf8))
        await #expect(throws: AttachmentCapturePowerSyncStoreFailure.replayMismatch) {
            try await store.enqueue(changed)
        }
        let changedParentScope = AttachmentCaptureScope(
            environment: Fixture.captureScope.environment,
            principalId: Fixture.captureScope.principalId,
            accountId: Fixture.captureScope.accountId,
            parent: LedgerEntityReference(
                kind: .item,
                id: try EntityID(validating: "item-attachment-provider-other")
            )
        )
        let changedParent = try LocalAttachmentCapture(
            attachmentId: capture.attachmentId,
            scope: changedParentScope,
            capturedAt: capture.capturedAt,
            bytes: capture.bytes
        )
        await #expect(throws: AttachmentCapturePowerSyncStoreFailure.replayMismatch) {
            try await store.enqueue(changedParent)
        }
        let changedCaptureTime = try LocalAttachmentCapture(
            attachmentId: capture.attachmentId,
            scope: capture.scope,
            capturedAt: try AttachmentEpochMilliseconds(validating: 1_001),
            bytes: capture.bytes
        )
        await #expect(throws: AttachmentCapturePowerSyncStoreFailure.replayMismatch) {
            try await store.enqueue(changedCaptureTime)
        }
        let distinct = try await store.enqueue(fixture.capture(id: "attachment-005-distinct"))
        #expect(distinct.localObjectId != receipts[0].localObjectId)
        let conflictA = try fixture.capture(
            id: "attachment-005-concurrent-conflict",
            bytes: Data("conflict-a".utf8)
        )
        let conflictB = try fixture.capture(
            id: "attachment-005-concurrent-conflict",
            bytes: Data("conflict-b".utf8)
        )
        async let outcomeA = enqueueOutcome(store, conflictA)
        async let outcomeB = enqueueOutcome(store, conflictB)
        let conflictOutcomes = await [outcomeA, outcomeB]
        #expect(conflictOutcomes.filter { $0 == .accepted }.count == 1)
        #expect(conflictOutcomes.filter { $0 == .replayMismatch }.count == 1)
        #expect(try await store.pendingCount() == 3)
        #expect(try await store.orphanInventory().isEmpty)
        try await database.close()
    }

    @Test("ATTACHDUR-TEST-006 injected storage and queue-boundary failures preserve older work")
    func storageFailurePreservesAcceptedWork() async throws {
        let fixture = try Fixture()
        defer { fixture.removeDirectory() }
        let database = try fixture.openDatabase()
        let healthyVault = try fixture.makeVault()
        let healthy = fixture.makeStore(database: database, vault: healthyVault)
        let accepted = try await healthy.enqueue(fixture.capture(id: "attachment-006-accepted"))

        let persistenceCheckpoints = AttachmentVaultCheckpoint.allCases.filter {
            $0 != .beforeOrphanInventory
        }
        for (index, checkpoint) in persistenceCheckpoints.enumerated() {
            let failingVault = try fixture.makeVault { observed in
                if observed == checkpoint { throw InjectedFailure() }
            }
            let failingStore = fixture.makeStore(database: database, vault: failingVault)
            await #expect(throws: (any Error).self) {
                try await failingStore.enqueue(
                    fixture.capture(id: "attachment-006-failed-\(index)")
                )
            }
            #expect(try await healthy.pendingCount() == 1)
            #expect(try await healthy.nextVerifiedCandidate()?.receipt == accepted)
        }
        let queueBoundaryFailure = fixture.makeStore(
            database: database,
            vault: healthyVault,
            storeFault: { point in
                if point == .beforeQueueCommit { throw InjectedFailure() }
            }
        )
        await #expect(throws: (any Error).self) {
            try await queueBoundaryFailure.enqueue(fixture.capture(id: "attachment-006-queue"))
        }
        #expect(try await healthy.pendingCount() == 1)
        #expect(try await healthy.nextVerifiedCandidate()?.bytes == Fixture.bytes)
        try await database.close()
    }

    @Test("ATTACHDUR-TEST-007 environment Principal and Account namespaces isolate")
    func namespaceIsolation() async throws {
        let fixture = try Fixture()
        defer { fixture.removeDirectory() }
        let database = try fixture.openDatabase()
        let primaryVault = try fixture.makeVault()
        let primary = fixture.makeStore(database: database, vault: primaryVault)
        _ = try await primary.enqueue(fixture.capture())

        let otherScopes = [
            try Fixture.scope(principal: "principal-other"),
            try Fixture.scope(account: "account-other"),
            try Fixture.scope(environment: .targetStaging)
        ]
        for (index, otherScope) in otherScopes.enumerated() {
            let otherVault = try AttachmentLocalByteVault(
                trustedRoot: fixture.vaultRoot,
                scope: otherScope,
                mediaKey: try AttachmentMediaEncryptionKey(
                    bytes: Data(repeating: 0x42, count: 32)
                )
            )
            let wrongScopeForBoundDatabase = AttachmentCapturePowerSyncStore(
                database: database,
                vault: otherVault,
                scope: otherScope,
                now: { Fixture.persistedDate }
            )
            await #expect(throws: AttachmentCapturePowerSyncStoreFailure.scopeMismatch) {
                _ = try await wrongScopeForBoundDatabase.pendingCount()
            }

            let isolatedDatabase = try fixture.openDatabase(
                fileName: "attachment-isolated-\(index).sqlite"
            )
            let isolatedStore = AttachmentCapturePowerSyncStore(
                database: isolatedDatabase,
                vault: otherVault,
                scope: otherScope,
                now: { Fixture.persistedDate }
            )
            #expect(try await isolatedStore.pendingCount() == 0)
            #expect(try await isolatedStore.pendingEvidence().isEmpty)
            #expect(try await isolatedStore.nextVerifiedCandidate() == nil)
            await #expect(throws: AttachmentCapturePowerSyncStoreFailure.scopeMismatch) {
                try await isolatedStore.enqueue(fixture.capture())
            }
            try await isolatedDatabase.close()
        }
        #expect(try await primary.pendingCount() == 1)

        _ = try await database.execute(
            sql: "UPDATE \(AttachmentCapturePowerSyncTable.queue) SET principal_id = 'forged-principal'",
            parameters: nil
        )
        #expect(try await primary.pendingCount() == 1)
        let corruptedScopeEvidence = try await primary.pendingEvidence()
        #expect(corruptedScopeEvidence.count == 1)
        #expect(corruptedScopeEvidence[0].state == .corrupt)

        _ = try await database.execute(
            sql: "DELETE FROM \(AttachmentCapturePowerSyncTable.scopeBinding)",
            parameters: nil
        )
        let reboundScope = otherScopes[0]
        let reboundVault = try AttachmentLocalByteVault(
            trustedRoot: fixture.vaultRoot,
            scope: reboundScope,
            mediaKey: fixture.mediaKey
        )
        let reboundStore = AttachmentCapturePowerSyncStore(
            database: database,
            vault: reboundVault,
            scope: reboundScope,
            now: { Fixture.persistedDate }
        )
        await #expect(throws: AttachmentCapturePowerSyncStoreFailure.scopeMismatch) {
            _ = try await reboundStore.pendingCount()
        }
        await #expect(throws: AttachmentCapturePowerSyncStoreFailure.scopeMismatch) {
            _ = try await primary.pendingCount()
        }
        try await database.close()
    }

    @Test("ATTACHDUR-TEST-008 order and count are stable and reads never consume")
    func nonConsumingPendingReads() async throws {
        let fixture = try Fixture()
        defer { fixture.removeDirectory() }
        let database = try fixture.openDatabase()
        let store = fixture.makeStore(database: database, vault: try fixture.makeVault())
        let b = try await store.enqueue(fixture.capture(id: "attachment-b"))
        let a = try await store.enqueue(fixture.capture(id: "attachment-a"))
        let evidence = try await store.pendingEvidence()
        #expect(evidence.compactMap(\.receipt) == [a, b])
        for _ in 0..<3 {
            #expect(try await store.nextVerifiedCandidate()?.receipt == a)
            #expect(try await store.pendingCount() == 2)
        }
        let columns = try await database.getAll(
            "PRAGMA table_info(\(AttachmentCapturePowerSyncTable.queue))"
        ) { try $0.getString(name: "name") }
        #expect(!columns.contains("bytes"))
        #expect(!columns.contains("path"))
        #expect(!columns.contains("provider"))
        try await database.close()
    }

    @Test("ATTACHDUR-TEST-010 localOnly writes never enter ps_crud")
    func localOnlyQueueNeverUploads() async throws {
        let fixture = try Fixture()
        defer { fixture.removeDirectory() }
        try AttachmentCapturePowerSyncSchema.schema.validate()
        let database = try fixture.openDatabase()
        let store = fixture.makeStore(database: database, vault: try fixture.makeVault())
        _ = try await store.enqueue(fixture.capture())
        let crudCount = try await database.get("SELECT count(*) FROM ps_crud") {
            try $0.getInt64(index: 0)
        }
        #expect(crudCount == 0)
        #expect(try await database.getNextCrudTransaction() == nil)
        let sharedRuntimeTables = [
            LedgerPowerSyncTable.principals, LedgerPowerSyncTable.accounts,
            LedgerPowerSyncTable.memberships, LedgerPowerSyncTable.clients,
            LedgerPowerSyncTable.pendingClients, LedgerPowerSyncTable.clientCommands,
            LedgerPowerSyncTable.budgetCategories, LedgerPowerSyncTable.projects,
            LedgerPowerSyncTable.pendingProjects,
            LedgerPowerSyncTable.projectCategoryAllocations,
            LedgerPowerSyncTable.pendingProjectCategoryAllocations,
            LedgerPowerSyncTable.projectCommands, LedgerPowerSyncTable.localOperations,
            LedgerPowerSyncTable.operationResults
        ]
        #expect(!sharedRuntimeTables.contains(AttachmentCapturePowerSyncTable.queue))
        #expect(!sharedRuntimeTables.contains(AttachmentCapturePowerSyncTable.scopeBinding))
        try await database.close()
    }

    @Test("ATTACHDUR-TEST-011 paths, links and diagnostics fail closed without leakage")
    func pathAndLinkDefense() async throws {
        let fixture = try Fixture()
        defer { fixture.removeDirectory() }
        let redirectedRoot = fixture.directory.appendingPathComponent("redirected-root")
        try FileManager.default.createDirectory(at: redirectedRoot, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: fixture.vaultRoot,
            withDestinationURL: redirectedRoot
        )
        #expect(throws: AttachmentLocalByteVaultFailure.linkSubstitution) {
            try fixture.makeVault()
        }
        try FileManager.default.removeItem(at: fixture.vaultRoot)
        #expect(throws: AttachmentLocalByteVaultFailure.invalidNamespace) {
            try AttachmentLocalByteVault(
                trustedRoot: fixture.vaultRoot,
                scope: try Fixture.scope(namespacePrefix: "../escape"),
                mediaKey: fixture.mediaKey
            )
        }
        let vault = try fixture.makeVault()
        let capture = try fixture.capture()
        let evidence = try await vault.persist(
            capture,
            persistedAt: try AttachmentEpochMilliseconds(validating: 2_000)
        )
        for unsafeIdentity in [".", "..", "con", "nul", "lpt1"] {
            let unsafeEvidence = try AttachmentPersistedLocalObjectEvidence(
                attachmentId: capture.attachmentId,
                scope: capture.scope,
                localObjectId: try AttachmentLocalObjectID(validating: unsafeIdentity),
                byteCount: capture.byteCount,
                contentSHA256: capture.contentSHA256,
                persistedAt: evidence.persistedAt
            )
            await #expect(throws: AttachmentLocalByteVaultFailure.invalidLocalObjectIdentity) {
                try await vault.verifiedBytes(for: unsafeEvidence)
            }
        }

        let objectURL = try await vault.objectFileURLForTesting(evidence.localObjectId)
        let hardLinkURL = fixture.directory.appendingPathComponent("hard-linked-ciphertext")
        try FileManager.default.linkItem(at: objectURL, to: hardLinkURL)
        await #expect(throws: AttachmentLocalByteVaultFailure.linkSubstitution) {
            try await vault.verifiedBytes(for: evidence)
        }
        try FileManager.default.removeItem(at: hardLinkURL)
        #expect(try await vault.verifiedBytes(for: evidence) == Fixture.bytes)

        let movedURL = fixture.directory.appendingPathComponent("moved-ciphertext")
        try FileManager.default.moveItem(at: objectURL, to: movedURL)
        try FileManager.default.createSymbolicLink(at: objectURL, withDestinationURL: movedURL)
        await #expect(throws: AttachmentLocalByteVaultFailure.linkSubstitution) {
            try await vault.verifiedBytes(for: evidence)
        }
        let diagnostics = [
            AttachmentLocalByteVaultFailure.linkSubstitution.diagnosticCode,
            AttachmentCapturePowerSyncStoreFailure.corruptBytes.diagnosticCode
        ].joined(separator: " ")
        #expect(!diagnostics.contains(fixture.directory.path))
        #expect(!diagnostics.contains(Fixture.bytes.base64EncodedString()))
        #expect(!diagnostics.contains("key"))
        let values = try movedURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
#if os(iOS) || os(tvOS) || os(watchOS)
        let attributes = try FileManager.default.attributesOfItem(atPath: movedURL.path)
        #expect(attributes[.protectionKey] as? FileProtectionType == .complete)
#endif

        let database = try fixture.openDatabase()
        let store = fixture.makeStore(database: database, vault: vault)
        let metadataReceipt = try await store.enqueue(
            fixture.capture(id: "attachment-011-local-object-metadata")
        )
        _ = try await database.execute(
            sql: "UPDATE \(AttachmentCapturePowerSyncTable.queue) SET local_object_id = ? WHERE id = ?",
            parameters: [
                String(repeating: "0", count: 64),
                metadataReceipt.attachmentId.rawValue
            ]
        )
        let metadataEvidence = try await store.pendingEvidence()
        #expect(metadataEvidence.count == 1)
        #expect(metadataEvidence[0].receipt == nil)
        #expect(metadataEvidence[0].state == .corrupt)
        try await database.close()
    }

    @Test("ATTACHDUR-TEST-012 pending-work observation validates queue and inventories orphans")
    func pendingWorkObservation() async throws {
        let fixture = try Fixture()
        defer { fixture.removeDirectory() }
        let database = try fixture.openDatabase()
        let vault = try fixture.makeVault()
        let store = fixture.makeStore(database: database, vault: vault)

        let pending = try await store.enqueue(
            fixture.capture(id: "attachment-012-a-pending")
        )
        let missing = try await store.enqueue(
            fixture.capture(id: "attachment-012-b-missing")
        )
        let missingURL = try await vault.objectFileURLForTesting(missing.localObjectId)
        try FileManager.default.removeItem(at: missingURL)
        let corrupt = try await store.enqueue(
            fixture.capture(id: "attachment-012-c-corrupt")
        )
        let corruptURL = try await vault.objectFileURLForTesting(corrupt.localObjectId)
        try Data(try Data(contentsOf: corruptURL).prefix(8)).write(to: corruptURL)

        let stagingVault = try fixture.makeVault { checkpoint in
            if checkpoint == .afterStagingWrite { throw InjectedFailure() }
        }
        let stagingStore = fixture.makeStore(database: database, vault: stagingVault)
        await #expect(throws: (any Error).self) {
            _ = try await stagingStore.enqueue(
                fixture.capture(id: "attachment-012-d-staging-orphan")
            )
        }
        let finalVault = try fixture.makeVault { checkpoint in
            if checkpoint == .afterPromotion { throw InjectedFailure() }
        }
        let finalStore = fixture.makeStore(database: database, vault: finalVault)
        await #expect(throws: (any Error).self) {
            _ = try await finalStore.enqueue(
                fixture.capture(id: "attachment-012-e-final-orphan")
            )
        }

        let observation = try await store.pendingWorkObservation()
        #expect(observation.queue.map(\.receipt) == [pending, missing, corrupt])
        #expect(observation.queue.map(\.state) == [.pending, .missing, .corrupt])
        #expect(observation.orphans.map(\.kind) == [.finalObject, .staging])
        #expect(observation.orphans.allSatisfy { !$0.opaqueIdentity.isEmpty })
        #expect(observation.orphans.allSatisfy { !$0.opaqueIdentity.contains("/") })

        let repeated = try await store.pendingWorkObservation()
        #expect(repeated == observation)
        try await database.close()

        let reopened = try fixture.openDatabase()
        let restored = fixture.makeStore(database: reopened, vault: try fixture.makeVault())
        let afterRestart = try await restored.pendingWorkObservation()
        #expect(afterRestart == observation)
        try await reopened.close()
    }

    @Test("ATTACHDUR-TEST-013 pending-work observation refuses foreign and malformed rows")
    func pendingWorkObservationRefusesInvalidRows() async throws {
        let foreignFixture = try Fixture()
        defer { foreignFixture.removeDirectory() }
        let foreignDatabase = try foreignFixture.openDatabase()
        let foreignStore = foreignFixture.makeStore(
            database: foreignDatabase,
            vault: try foreignFixture.makeVault()
        )
        _ = try await foreignStore.enqueue(
            foreignFixture.capture(id: "attachment-013-foreign")
        )
        _ = try await foreignDatabase.execute(
            sql: "UPDATE \(AttachmentCapturePowerSyncTable.queue) SET principal_id = ?",
            parameters: ["principal-foreign"]
        )
        await #expect(throws: AttachmentCapturePowerSyncStoreFailure.scopeMismatch) {
            _ = try await foreignStore.pendingWorkObservation()
        }
        try await foreignDatabase.close()

        let malformedFixture = try Fixture()
        defer { malformedFixture.removeDirectory() }
        let malformedDatabase = try malformedFixture.openDatabase()
        let malformedStore = malformedFixture.makeStore(
            database: malformedDatabase,
            vault: try malformedFixture.makeVault()
        )
        _ = try await malformedStore.enqueue(
            malformedFixture.capture(id: "attachment-013-malformed")
        )
        _ = try await malformedDatabase.execute(
            sql: "UPDATE \(AttachmentCapturePowerSyncTable.queue) SET receipt_json = NULL",
            parameters: nil
        )
        await #expect(throws: AttachmentCapturePowerSyncStoreFailure.malformedQueueEvidence) {
            _ = try await malformedStore.pendingWorkObservation()
        }
        try await malformedDatabase.close()
    }

    @Test("ATTACHDUR-TEST-014 pending-work observation propagates state-write failure")
    func pendingWorkObservationPropagatesStateWriteFailure() async throws {
        let fixture = try Fixture()
        defer { fixture.removeDirectory() }
        let database = try fixture.openDatabase()
        let vault = try fixture.makeVault()
        let store = fixture.makeStore(database: database, vault: vault)
        let receipt = try await store.enqueue(
            fixture.capture(id: "attachment-014-state-write")
        )
        let objectURL = try await vault.objectFileURLForTesting(receipt.localObjectId)
        try FileManager.default.removeItem(at: objectURL)
        _ = try await database.execute(
            """
            CREATE TRIGGER fail_attachment_state_update
            INSTEAD OF UPDATE OF state ON \(AttachmentCapturePowerSyncTable.queue)
            BEGIN
              SELECT RAISE(ABORT, 'injected state write failure');
            END
            """
        )

        await #expect(throws: AttachmentCapturePowerSyncStoreFailure.queuePersistenceFailed) {
            _ = try await store.pendingWorkObservation()
        }
        let state = try await database.get(
            "SELECT state FROM \(AttachmentCapturePowerSyncTable.queue)"
        ) { try $0.getString(index: 0) }
        #expect(state == AttachmentPendingState.pending.rawValue)
        try await database.close()
    }
}

private struct InjectedFailure: Error {}

private enum EnqueueOutcome: Equatable, Sendable {
    case accepted
    case replayMismatch
    case unexpectedFailure
}

private func enqueueOutcome(
    _ store: AttachmentCapturePowerSyncStore,
    _ capture: LocalAttachmentCapture
) async -> EnqueueOutcome {
    do {
        _ = try await store.enqueue(capture)
        return .accepted
    } catch let failure as AttachmentCapturePowerSyncStoreFailure where failure == .replayMismatch {
        return .replayMismatch
    } catch {
        return .unexpectedFailure
    }
}

private final class Fixture: @unchecked Sendable {
    static let bytes = Data("synthetic attachment bytes: 01 02 03".utf8)
    static let attachmentID = try! AttachmentID(validating: "attachment-provider-test")
    static let capturedAt = try! AttachmentEpochMilliseconds(validating: 1_000)
    static let persistedDate = Date(timeIntervalSince1970: 2)
    static let scope = try! scope()

    let directory: URL
    let databaseURL: URL
    let vaultRoot: URL
    let mediaKey = try! AttachmentMediaEncryptionKey(bytes: Data(repeating: 0x42, count: 32))
    private let databaseKey = try! LedgerPowerSyncEncryptionKey(
        hexadecimal: String(repeating: "1a", count: 32)
    )

    init(suffix: String = UUID().uuidString) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("attachment-provider-\(suffix)", isDirectory: true)
            .standardizedFileURL
        databaseURL = directory.appendingPathComponent("attachment.sqlite")
        vaultRoot = directory.appendingPathComponent("vault", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func openDatabase(fileName: String = "attachment.sqlite") throws -> any PowerSyncDatabaseProtocol {
        try AttachmentCapturePowerSyncDatabaseFactory.open(
            absolutePath: directory.appendingPathComponent(fileName).path,
            encryptionKey: databaseKey
        )
    }

    func makeVault(
        keyByte: UInt8 = 0x42,
        fault: @Sendable @escaping (AttachmentVaultCheckpoint) throws -> Void = { _ in }
    ) throws -> AttachmentLocalByteVault {
        try AttachmentLocalByteVault(
            trustedRoot: vaultRoot,
            scope: Self.scope,
            mediaKey: try AttachmentMediaEncryptionKey(bytes: Data(repeating: keyByte, count: 32)),
            fault: fault
        )
    }

    func makeStore(
        database: any PowerSyncDatabaseProtocol,
        vault: AttachmentLocalByteVault,
        storeFault: @Sendable @escaping (AttachmentStoreCheckpoint) throws -> Void = { _ in }
    ) -> AttachmentCapturePowerSyncStore {
        AttachmentCapturePowerSyncStore(
            database: database,
            vault: vault,
            scope: Self.scope,
            now: { Self.persistedDate },
            fault: storeFault
        )
    }

    func capture(
        id: String = Fixture.attachmentID.rawValue,
        bytes: Data = Fixture.bytes
    ) throws -> LocalAttachmentCapture {
        try LocalAttachmentCapture(
            attachmentId: AttachmentID(validating: id),
            scope: Self.captureScope,
            capturedAt: Self.capturedAt,
            bytes: bytes
        )
    }

    func removeDirectory() {
        try? FileManager.default.removeItem(at: directory)
    }

    static func scope(
        environment: LedgerEnvironmentKind = .targetLocal,
        principal: String = "principal-attachment-provider",
        account: String = "account-attachment-provider",
        namespacePrefix: String = "apps.nine4.ledger.attachment-tests"
    ) throws -> AttachmentDurabilityNamespaceScope {
        try AttachmentDurabilityNamespaceScope(
            validatedEnvironment: validatedEnvironment(
                environment: environment,
                namespacePrefix: namespacePrefix
            ),
            principalId: try PrincipalID(validating: principal),
            accountId: try AccountID(validating: account)
        )
    }

    private static func validatedEnvironment(
        environment: LedgerEnvironmentKind,
        namespacePrefix: String
    ) throws -> ValidatedLedgerEnvironment {
        let buildProfile: LedgerBuildProfile = environment == .targetStaging
            ? .targetStaging
            : .targetLocalDevelopment
        let suffix = environment.rawValue
        let bundleIdentifier = "apps.nine4.ledger.attachment-tests.\(suffix)"
        let displayName = environment == .targetStaging
            ? "Ledger Attachment Tests STAGING"
            : "Ledger Attachment Tests"
        let versions = LedgerContractVersions(
            schema: "1", query: "1", operation: "1", sync: "1"
        )
        let identifiers = Dictionary(
            uniqueKeysWithValues: LedgerTargetComponent.allCases.map {
                ($0, "attachment-tests-\($0.rawValue)-\(suffix)")
            }
        )
        let manifest = LedgerEnvironmentManifest(
            environment: environment,
            buildProfile: buildProfile,
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            localDataNamespacePrefix: namespacePrefix,
            contractVersions: versions,
            resources: LedgerTargetComponent.allCases.map {
                LedgerEnvironmentResource(
                    component: $0,
                    environment: environment,
                    publicIdentifier: identifiers[$0]!
                )
            }
        )
        return try LedgerEnvironmentValidator.validate(
            manifest,
            policy: LedgerEnvironmentPolicy(
                expectedEnvironment: environment,
                expectedBuildProfile: buildProfile,
                expectedBundleIdentifier: bundleIdentifier,
                expectedContractVersions: versions,
                allowedResourceIdentifiers: identifiers.mapValues { [$0] },
                forbiddenResourceIdentifiers: [],
                forbiddenBundleIdentifiers: []
            )
        )
    }

    static var captureScope: AttachmentCaptureScope {
        AttachmentCaptureScope(
            environment: scope.environment,
            principalId: scope.principalId,
            accountId: scope.accountId,
            parent: LedgerEntityReference(
                kind: .item,
                id: try! EntityID(validating: "item-attachment-provider")
            )
        )
    }
}
