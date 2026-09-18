import Foundation
import PowerSync
import Testing
@testable import LedgerTargetCore
@testable import LedgerTargetPowerSync

@Suite("LedgerPowerSync attachment local byte durability provider", .serialized)
struct LedgerPowerSyncAttachmentDurabilityProviderTests {
    @Test("Expense publication survives interruption and restart without losing bytes or project binding")
    func expensePublicationRestart() async throws {
        let fixture = try Fixture()
        defer { fixture.removeDirectory() }
        let capture = try LocalAttachmentCapture(attachmentId: Fixture.attachmentID,
            scope: .init(environment: Fixture.scope.environment, principalId: Fixture.scope.principalId,
                accountId: Fixture.scope.accountId, parent: .init(kind: .expense,
                    id: EntityID(validating: "expense-upload"))), capturedAt: Fixture.capturedAt,
            bytes: Fixture.bytes, metadata: .init(mediaType: "image/png", fileName: "Receipt.png"))
        let project = try EntityID(validating: "expense-project")
        let checkpoint = TransactionAttachmentUploadCheckpoint(
            uploadURL: URL(string: "https://example.test/storage/v1/upload/resumable/expense")!, offset: 1)
        let database = try fixture.openDatabase()
        let store = fixture.makeStore(database: database, vault: try fixture.makeVault())
        let receipt = try await store.enqueue(capture)
        await #expect(throws: InjectedFailure.self) {
            try await store.publishExpenseAttachment(receipt, projectId: project) { candidate, prior, save in
                #expect(candidate.bytes == Fixture.bytes && prior == nil)
                try await save(checkpoint)
                throw InjectedFailure()
            }
        }
        try await database.close()
        let reopened = try fixture.openDatabase()
        let restored = fixture.makeStore(database: reopened, vault: try fixture.makeVault())
        await #expect(throws: AttachmentCapturePowerSyncStoreFailure.replayMismatch) {
            try await restored.publishExpenseAttachment(receipt, projectId: EntityID(validating: "different-project")) { _, _, _ in
                Issue.record("A changed project must not reach publication")
                return .verified
            }
        }
        let published = try await restored.publishExpenseAttachment(receipt, projectId: project) { candidate, prior, _ in
            #expect(candidate.bytes == Fixture.bytes && prior == checkpoint)
            return .verified
        }
        #expect(published == .verified)
        try await reopened.close()
        let finalDB = try fixture.openDatabase()
        let finalStore = fixture.makeStore(database: finalDB, vault: try fixture.makeVault())
        let retained = try await finalStore.publishExpenseAttachment(receipt, projectId: project) { _, _, _ in
            Issue.record("Verified retry must not upload again")
            throw InjectedFailure()
        }
        #expect(retained == .verified)
        #expect(try await finalStore.nextVerifiedCandidate() == nil)
        #expect(try await finalStore.pendingCount() == 1)
        #expect(try await finalStore.resolveLocalAttachmentBytes(for: receipt) == Fixture.bytes)
        let draft = try BusinessPaidExpenseDraft(accountId: receipt.scope.accountId,
            projectId: .init(validating: project.rawValue), expenseId: .init(validating: receipt.scope.parent.id.rawValue),
            vendor: "Vendor", date: "2026-09-15", finalAmount: .init(minorUnits: 12, currency: .init(validating: "USD")),
            categoryId: .init(validating: "general"), notes: "", receiptAttachmentIds: [receipt.attachmentId])
        let command = try CreateExpenseCommand(operationId: ExpenseCreationOperationIdentity.make(accountId: receipt.scope.accountId, uuid: UUID()),
            actorPrincipalId: receipt.scope.principalId, capturedAt: Date(timeIntervalSince1970: 1_789_459_200), draft: draft)
        #expect(try await finalStore.verifiedExpenseReceipts(for: command) == [receipt.attachmentId])
        let edit = try EditExpenseCommand(operationId: AccountBoundOperationIdentity.make(family: .expenseEdit,
            accountId: receipt.scope.accountId, uuid: UUID()), actorPrincipalId: receipt.scope.principalId,
            capturedAt: Date(timeIntervalSince1970: 1_789_459_200), expectedRevision: 1, entry: draft)
        #expect(try await finalStore.verifiedExpenseReceipts(for: edit) == [receipt.attachmentId])
        let wrongActor = try EditExpenseCommand(operationId: edit.envelope.operationId,
            actorPrincipalId: .init(validating: "other-principal"), capturedAt: edit.envelope.clientCreatedAt,
            expectedRevision: 1, entry: draft)
        await #expect(throws: AttachmentCapturePowerSyncStoreFailure.scopeMismatch) {
            try await finalStore.verifiedExpenseReceipts(for: wrongActor)
        }
        await #expect(throws: AttachmentCapturePowerSyncStoreFailure.replayMismatch) {
            try await finalStore.saveUploadProgress(.init(checkpoint: checkpoint, publication: nil), for: receipt)
        }
        let object = try DownloadedMediaObjectReference(accountId: receipt.scope.accountId,
            attachmentId: receipt.attachmentId.rawValue, sha256: receipt.contentSHA256.rawValue,
            byteCount: String(receipt.byteCount), mediaType: "image/png",
            storagePath: "accounts/\(receipt.scope.accountId.rawValue)/attachments/\(receipt.attachmentId.rawValue)/\(receipt.contentSHA256.rawValue)")
        #expect(try await finalStore.reconcileExpenseAttachment(receipt, projectId: .init(validating: "wrong-project"), object: object) == false)
        #expect(try await finalStore.pendingCount() == 1)
        #expect(try await finalStore.reconcileExpenseAttachment(receipt, projectId: project, object: object))
        #expect(try await finalStore.pendingCount() == 0)
        #expect(try await finalStore.cachedDownloadedImage(object) == Fixture.bytes)
        try await finalDB.close()
    }

    @Test("Item publication waits for exact synced reference and retains bytes through restart")
    func itemPublicationReadback() async throws {
        let fixture = try Fixture()
        defer { fixture.removeDirectory() }
        let capture = try LocalAttachmentCapture(attachmentId: Fixture.attachmentID,
            scope: .init(environment: Fixture.scope.environment, principalId: Fixture.scope.principalId,
                accountId: Fixture.scope.accountId, parent: .init(kind: .item, id: .init(validating: "item-upload"))),
            capturedAt: Fixture.capturedAt, bytes: Fixture.bytes,
            metadata: .init(mediaType: "image/png", fileName: "Original.png",
                placement: .init(localPosition: 0, makePrimaryIfEmpty: true)))
        let db = try fixture.openDatabase()
        let store = fixture.makeStore(database: db, vault: try fixture.makeVault())
        let receipt = try await store.enqueue(capture)
        #expect(try await store.pendingItemUploads() == [receipt])
        #expect(try await store.publishItemAttachment(receipt) { _, _, _ in .applied(revision: 2, position: 0) }
            == .applied(revision: 2, position: 0))
        try await db.close()
        let reopened = try fixture.openDatabase()
        let restored = fixture.makeStore(database: reopened, vault: try fixture.makeVault())
        #expect(try await restored.publishItemAttachment(receipt) { _, _, _ in
            Issue.record("Do not retransmit an applied Item photo"); throw InjectedFailure()
        } == .applied(revision: 2, position: 0))
        let item = try ItemID(validating: "item-upload")
        let empty = try DownloadedItemImageCatalog(accountId: receipt.scope.accountId, itemId: item,
            isComplete: true, images: [], revision: 2)
        #expect(try await restored.reconcileItemAttachment(receipt, catalog: empty) == false)
        #expect(try await restored.pendingCount() == 1)
        let projected = try empty.includingPending([receipt], scope: receipt.scope)
        #expect(try await restored.reconcileItemAttachment(receipt, catalog: projected) == false)
        let pending = try #require(projected.images.first)
        let synced = try DownloadedItemImage(referenceId: pending.referenceId, itemId: item, object: pending.object,
            position: 0, isPrimary: true, setRevision: 2)
        let catalog = try DownloadedItemImageCatalog(accountId: receipt.scope.accountId, itemId: item,
            isComplete: true, images: [synced], revision: 2)
        #expect(try await restored.reconcileItemAttachment(receipt, catalog: catalog))
        #expect(try await restored.pendingCount() == 0)
        #expect(try await restored.cachedDownloadedImage(synced.object) == Fixture.bytes)
        #expect(try await restored.orphanInventory().isEmpty)
        try await reopened.close()
    }

    @Test("Transaction publisher resumes saved progress after interruption and retains confirmed bytes")
    func publicationRunnerRestart() async throws {
        let fixture = try Fixture()
        defer { fixture.removeDirectory() }
        let capture = try LocalAttachmentCapture(attachmentId: Fixture.attachmentID,
            scope: .init(environment: Fixture.scope.environment, principalId: Fixture.scope.principalId,
                accountId: Fixture.scope.accountId, parent: .init(kind: .transaction,
                    id: EntityID(validating: "transaction-upload"))), capturedAt: Fixture.capturedAt,
            bytes: Fixture.bytes, metadata: .init(mediaType: "image/png", fileName: "Receipt.png",
                transactionSection: .receipts, placement: .init(localPosition: 0, makePrimaryIfEmpty: true)))
        let checkpoint = TransactionAttachmentUploadCheckpoint(
            uploadURL: URL(string: "https://example.test/storage/v1/upload/resumable/session")!, offset: 1)
        let database = try fixture.openDatabase()
        let store = fixture.makeStore(database: database, vault: try fixture.makeVault())
        let receipt = try await store.enqueue(capture)
        await #expect(throws: InjectedFailure.self) {
            try await store.publishTransactionAttachment(receipt) { candidate, prior, save in
                #expect(candidate.receipt == receipt && candidate.bytes == Fixture.bytes)
                #expect(prior == nil)
                try await save(checkpoint)
                throw InjectedFailure()
            }
        }
        try await database.close()
        let reopened = try fixture.openDatabase()
        let restored = fixture.makeStore(database: reopened, vault: try fixture.makeVault())
        let result = try await restored.publishTransactionAttachment(receipt) { _, prior, save in
            #expect(prior == checkpoint)
            try await save(.init(uploadURL: checkpoint.uploadURL, offset: receipt.byteCount))
            return .applied(revision: 3, position: 0)
        }
        #expect(result == .applied(revision: 3, position: 0))
        #expect(try await restored.uploadProgress(for: receipt)?.checkpoint?.offset == receipt.byteCount)
        #expect(try await restored.publishTransactionAttachment(receipt) { _, _, _ in
            Issue.record("Confirmed result must not invoke transport again")
            throw InjectedFailure()
        } == result)
        #expect(try await restored.resolveLocalAttachmentBytes(for: receipt) == Fixture.bytes)
        #expect(try await restored.pendingCount() == 1)
        // Publication committed, but no synced reference has arrived. Reopen in
        // that exact gap; neither a second transfer nor queue drainage is allowed.
        try await reopened.close()
        let waitingDB = try fixture.openDatabase()
        let waiting = fixture.makeStore(database: waitingDB, vault: try fixture.makeVault())
        #expect(try await waiting.publishTransactionAttachment(receipt) { _, _, _ in
            Issue.record("Delayed sync must not restart a confirmed upload")
            throw InjectedFailure()
        } == result)
        #expect(try await waiting.resolveLocalAttachmentBytes(for: receipt) == Fixture.bytes)
        let object = try DownloadedMediaObjectReference(accountId: receipt.scope.accountId,
            attachmentId: receipt.attachmentId.rawValue, sha256: receipt.contentSHA256.rawValue,
            byteCount: String(receipt.byteCount), mediaType: "image/png",
            storagePath: "accounts/\(receipt.scope.accountId.rawValue)/attachments/\(receipt.attachmentId.rawValue)/\(receipt.contentSHA256.rawValue)")
        func catalog(revision: Int64 = 3, complete: Bool = true, pending: Bool = false,
                     section: TransactionAttachmentSection = .receipts) throws -> DownloadedTransactionAttachments {
            try .init(scope: .businessInventory(accountId: receipt.scope.accountId),
                transactionId: TransactionID(validating: receipt.scope.parent.id.rawValue), section: section,
                revision: revision, isComplete: complete,
                attachments: [.init(id: EntityID(validating: receipt.attachmentId.rawValue), object: object,
                    position: 0, isPrimary: true, fileName: "Receipt.png", localReceipt: pending ? receipt : nil)])
        }
        let empty = try DownloadedTransactionAttachments(scope: .businessInventory(accountId: receipt.scope.accountId),
            transactionId: TransactionID(validating: receipt.scope.parent.id.rawValue), section: .receipts,
            revision: 3, isComplete: true, attachments: [])
        for invalid in [empty, try catalog(revision: 2), try catalog(complete: false),
                        try catalog(pending: true), try catalog(section: .other)] {
            #expect(try await waiting.reconcileTransactionAttachment(receipt, catalog: invalid) == false)
            #expect(try await waiting.pendingCount() == 1)
            #expect(try await waiting.resolveLocalAttachmentBytes(for: receipt) == Fixture.bytes)
        }
        #expect(try await waiting.reconcileTransactionAttachment(receipt, catalog: catalog()))
        #expect(try await waiting.pendingCount() == 0)
        #expect(try await waiting.cachedDownloadedImage(object) == Fixture.bytes)
        #expect(try await waiting.orphanInventory().isEmpty)
        try await waitingDB.close()
        let finalDB = try fixture.openDatabase()
        let finalStore = fixture.makeStore(database: finalDB, vault: try fixture.makeVault())
        #expect(try await finalStore.cachedDownloadedImage(object) == Fixture.bytes)
        let observation = try await finalStore.pendingWorkObservation()
        #expect(observation.queue.isEmpty && observation.orphans.isEmpty)
        try await finalDB.close()
    }

    @Test("Upload checkpoint and terminal result survive restart without losing pending bytes",
          arguments: [TransactionAttachmentPublication.applied(revision: 12, position: 0), .rejected(code: "access_removed")])
    func uploadProgressRestart(publication: TransactionAttachmentPublication) async throws {
        let fixture = try Fixture()
        defer { fixture.removeDirectory() }
        let database = try fixture.openDatabase()
        let store = fixture.makeStore(database: database, vault: try fixture.makeVault())
        let receipt = try await store.enqueue(fixture.capture())
        #expect(try await store.uploadProgress(for: receipt) == nil)
        let checkpoint = TransactionAttachmentUploadCheckpoint(
            uploadURL: URL(string: "https://example.test/storage/v1/upload/resumable/session")!, offset: 1)
        let pending = AttachmentUploadProgress(checkpoint: checkpoint, publication: nil)
        try await store.saveUploadProgress(pending, for: receipt)
        try await database.close()
        #expect(!(try Data(contentsOf: fixture.databaseURL)).contains(Data("example.test".utf8)))
        let reopened = try fixture.openDatabase()
        let restored = fixture.makeStore(database: reopened, vault: try fixture.makeVault())
        #expect(try await restored.uploadProgress(for: receipt) == pending)
        #expect(try await restored.nextVerifiedCandidate()?.receipt == receipt)
        let terminal = AttachmentUploadProgress(checkpoint: checkpoint, publication: publication)
        try await restored.saveUploadProgress(terminal, for: receipt)
        try await restored.saveUploadProgress(terminal, for: receipt)
        await #expect(throws: AttachmentCapturePowerSyncStoreFailure.replayMismatch) {
            try await restored.saveUploadProgress(pending, for: receipt)
        }
        try await reopened.close()
        let finalDB = try fixture.openDatabase()
        let finalStore = fixture.makeStore(database: finalDB, vault: try fixture.makeVault())
        #expect(try await finalStore.uploadProgress(for: receipt) == terminal)
        let rejections = try await finalStore.pendingCaptureRejections(parent: receipt.scope.parent)
        if case let .rejected(code) = publication {
            #expect(rejections == [receipt.attachmentId: code])
        } else { #expect(rejections.isEmpty) }
        #expect(try await finalStore.pendingCaptureRejections(parent: .init(kind: .transaction,
            id: EntityID(validating: "unrelated-parent"))).isEmpty)
        #expect(try await finalStore.nextVerifiedCandidate() == nil)
        #expect(try await finalStore.pendingCount() == 1)
        #expect(try await finalStore.pendingWorkObservation().queue.count == 1)
        #expect(try await finalStore.resolveLocalAttachmentBytes(for: receipt) == Fixture.bytes)
        let second = try await finalStore.enqueue(fixture.capture(id: "attachment-next-upload"))
        #expect(try await finalStore.nextVerifiedCandidate()?.receipt == second)
        await #expect(throws: SupabaseTransactionAttachmentUploadFailure.invalidCheckpoint) {
            try await finalStore.saveUploadProgress(.init(checkpoint: .init(uploadURL: checkpoint.uploadURL,
                offset: receipt.byteCount + 1), publication: nil), for: receipt)
        }
        try await finalDB.close()
    }

    @Test("Learned denial after byte staging prevents receipt acceptance; retry retains the original")
    func authorizationBeforeCaptureCommit() async throws {
        let fixture = try Fixture()
        defer { fixture.removeDirectory() }
        let database = try fixture.openDatabase()
        let gate = LogoMutationGate()
        let authority = CaptureTestAuthority()
        let store = AttachmentCapturePowerSyncStore(database: database, vault: try fixture.makeVault(),
            scope: Fixture.scope, enqueueCommitCheckpoint: { await gate.pauseOnce() })
        let capture = try fixture.capture()
        let task = Task { try await store.enqueue(capture, authorize: { try await authority.requireAccess() }) }
        await gate.waitForPause()
        await authority.setAllowed(false)
        await gate.release()
        await #expect(throws: InjectedFailure.self) { try await task.value }
        #expect(try await store.pendingCount() == 0)
        #expect(try await store.pendingCaptureReceipts(parent: capture.scope.parent).isEmpty)
        #expect(!(try await store.orphanInventory()).isEmpty)
        await authority.setAllowed(true)
        let accepted = try await store.enqueue(capture, authorize: { try await authority.requireAccess() })
        #expect(try await store.pendingCaptureReceipts(parent: capture.scope.parent) == [accepted])
        #expect(try await store.resolveLocalAttachmentBytes(for: accepted) == Fixture.bytes)
        try await database.close()
    }

    @Test("Concurrent capture with changed metadata cannot borrow an in-flight receipt")
    func concurrentMetadataConflict() async throws {
        let fixture = try Fixture()
        defer { fixture.removeDirectory() }
        let database = try fixture.openDatabase()
        let gate = LogoMutationGate()
        let store = AttachmentCapturePowerSyncStore(database: database, vault: try fixture.makeVault(),
            scope: Fixture.scope, enqueueCommitCheckpoint: { await gate.pauseOnce() })
        let capture = try LocalAttachmentCapture(attachmentId: Fixture.attachmentID, scope: Fixture.captureScope,
            capturedAt: Fixture.capturedAt, bytes: Fixture.bytes,
            metadata: AttachmentCaptureMetadata(mediaType: "image/png", fileName: "Original.png"))
        let first = Task { try await store.enqueue(capture) }
        await gate.waitForPause()
        let changed = try LocalAttachmentCapture(attachmentId: capture.attachmentId, scope: capture.scope,
            capturedAt: capture.capturedAt, bytes: capture.bytes,
            metadata: AttachmentCaptureMetadata(mediaType: "image/png", fileName: "Changed.png"))
        await #expect(throws: AttachmentCapturePowerSyncStoreFailure.replayMismatch) {
            try await store.enqueue(changed)
        }
        await gate.release()
        let receipt = try await first.value
        #expect(receipt.metadata == capture.metadata)
        #expect(try await store.enqueue(capture) == receipt)
        try await database.close()
    }

    @Test("Capture metadata and original bytes survive encrypted queue restart; conflicting metadata cannot replay")
    func captureMetadataRestart() async throws {
        let fixture = try Fixture()
        defer { fixture.removeDirectory() }
        let metadata = try AttachmentCaptureMetadata(mediaType: "image/png", fileName: "Original image.png")
        let capture = try LocalAttachmentCapture(attachmentId: Fixture.attachmentID, scope: Fixture.captureScope,
            capturedAt: Fixture.capturedAt, bytes: Fixture.bytes, metadata: metadata)
        let database = try fixture.openDatabase()
        let store = fixture.makeStore(database: database, vault: try fixture.makeVault())
        let receipt = try await store.enqueue(capture)
        #expect(receipt.metadata == metadata)
        try await database.close()
        #expect(!(try Data(contentsOf: fixture.databaseURL)).contains(Data("Original image.png".utf8)))
        let reopened = try fixture.openDatabase()
        let restored = fixture.makeStore(database: reopened, vault: try fixture.makeVault())
        #expect(try await restored.enqueue(capture) == receipt)
        let candidate = try #require(try await restored.nextVerifiedCandidate())
        #expect(candidate.receipt.metadata == metadata)
        #expect(candidate.bytes == Fixture.bytes)
        #expect(try await restored.pendingCount() == 1)
        let changed = try LocalAttachmentCapture(attachmentId: capture.attachmentId, scope: capture.scope,
            capturedAt: capture.capturedAt, bytes: capture.bytes,
            metadata: AttachmentCaptureMetadata(mediaType: "image/png", fileName: "Different.png"))
        await #expect(throws: AttachmentCapturePowerSyncStoreFailure.replayMismatch) {
            try await restored.enqueue(changed)
        }
        try await reopened.close()
    }

    @Test("Upload and logo mutation exclude each other across suspended commit", arguments: [false, true])
    func downloadedLogoMutationExclusion(uploadFirst: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.removeDirectory() }
        let database = try fixture.openDatabase()
        let gate = LogoMutationGate()
        let store = AttachmentCapturePowerSyncStore(database: database, vault: try fixture.makeVault(),
            scope: Fixture.scope,
            resolutionDatabaseAccessCheckpoint: { if !uploadFirst { await gate.pauseOnce() } },
            enqueueCommitCheckpoint: { if uploadFirst { await gate.pauseOnce() } })
        let reference = try logoReference()
        let capture = try fixture.capture(id: reference.attachmentId.rawValue)
        let first = Task {
            if uploadFirst { _ = try await store.enqueue(capture) }
            else { try await store.cacheAccountLogo(Fixture.bytes, reference: reference) }
        }
        await gate.waitForPause()
        if uploadFirst {
            await #expect(throws: AttachmentCapturePowerSyncStoreFailure.attachmentBusy) {
                try await store.cacheAccountLogo(Fixture.bytes, reference: reference)
            }
        } else {
            await #expect(throws: AttachmentCapturePowerSyncStoreFailure.attachmentBusy) {
                try await store.enqueue(capture)
            }
        }
        await gate.release()
        try await first.value
        #expect(try await store.pendingCount() == (uploadFirst ? 1 : 0))
        if uploadFirst {
            #expect(try await store.nextVerifiedCandidate()?.bytes == Fixture.bytes)
        } else { #expect(try await store.cachedAccountLogo(reference) == Fixture.bytes) }
        try await database.close()
    }

    @Test("Downloaded images and legacy logos share encrypted restart without pending uploads or orphans", arguments: [false, true])
    func downloadedLogoRestart(generic: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.removeDirectory() }
        let reference = try logoReference()
        let database = try fixture.openDatabase()
        let store = fixture.makeStore(database: database, vault: try fixture.makeVault())
        #expect(try await store.cachedAccountLogo(reference) == nil)
        if generic {
            let cache: any DownloadedImageCaching = store
            try await cache.cacheDownloadedImage(Fixture.bytes, reference: reference.downloadedImageReference)
        } else {
            try await store.cacheAccountLogo(Fixture.bytes, reference: reference)
        }
        try await store.cacheAccountLogo(Fixture.bytes, reference: reference)
        #expect(try await store.cachedAccountLogo(reference) == Fixture.bytes)
        #expect(try await store.pendingCount() == 0)
        #expect(try await store.orphanInventory().isEmpty)
        let pending = try await store.pendingWorkObservation()
        #expect(pending.queue.isEmpty && pending.orphans.isEmpty)
        #expect(try await database.get("SELECT count(*) FROM ps_crud") { try $0.getInt64(index: 0) } == 0)
        try await database.close()
        #expect(!(try Data(contentsOf: fixture.databaseURL)).contains(Fixture.bytes))
        let reopened = try fixture.openDatabase()
        let restored = fixture.makeStore(database: reopened, vault: try fixture.makeVault())
        #expect(try await restored.cachedAccountLogo(reference) == Fixture.bytes)
        #expect(try await restored.cachedDownloadedImage(reference.downloadedImageReference) == Fixture.bytes)
        #expect(try await restored.pendingCount() == 0)
        #expect(try await restored.orphanInventory().isEmpty)
        try await reopened.close()
    }

    @Test("Receipt PDF uses existing encrypted cache and survives restart without becoming a pending upload")
    func downloadedPDFRestart() async throws {
        let fixture = try Fixture()
        defer { fixture.removeDirectory() }
        let bytes = Data("%PDF-1.4\nRetained receipt bytes\n%%EOF".utf8)
        let hash = try AttachmentContentSHA256.make(bytes: bytes).rawValue
        func reference(_ account: AccountID) throws -> DownloadedMediaObjectReference {
            try .init(accountId: account, attachmentId: "receipt-pdf", sha256: hash,
                byteCount: String(bytes.count), mediaType: "application/pdf",
                storagePath: "accounts/\(account.rawValue)/attachments/receipt-pdf/\(hash)", kind: .pdf)
        }
        let expected = try reference(Fixture.scope.accountId)
        let database = try fixture.openDatabase()
        let store = fixture.makeStore(database: database, vault: try fixture.makeVault())
        await #expect(throws: AttachmentCapturePowerSyncStoreFailure.self) {
            try await store.cacheDownloadedImage(Data("wrong".utf8), reference: expected)
        }
        await #expect(throws: AttachmentCapturePowerSyncStoreFailure.self) {
            try await store.cacheDownloadedImage(bytes, reference: reference(AccountID(validating: "foreign")))
        }
        try await store.cacheDownloadedImage(bytes, reference: expected)
        try await store.cacheDownloadedImage(bytes, reference: expected)
        #expect(try await store.pendingCount() == 0)
        #expect(try await store.orphanInventory().isEmpty)
        try await database.close()
        #expect(!(try Data(contentsOf: fixture.databaseURL)).contains(bytes))
        let reopened = try fixture.openDatabase()
        let restored = fixture.makeStore(database: reopened, vault: try fixture.makeVault())
        #expect(try await restored.cachedDownloadedImage(expected) == bytes)
        #expect(try await restored.pendingCount() == 0)
        #expect(try await restored.orphanInventory().isEmpty)
        try await reopened.close()
    }

    @Test("Downloaded logo rejects wrong bytes, Account, and substituted manifest")
    func downloadedLogoValidation() async throws {
        let fixture = try Fixture()
        defer { fixture.removeDirectory() }
        let database = try fixture.openDatabase()
        let store = fixture.makeStore(database: database, vault: try fixture.makeVault())
        let reference = try logoReference()
        await #expect(throws: AttachmentCapturePowerSyncStoreFailure.self) {
            try await store.cacheAccountLogo(Data("wrong".utf8), reference: reference)
        }
        let foreign = try logoReference(account: AccountID(validating: "foreign"))
        await #expect(throws: AttachmentCapturePowerSyncStoreFailure.self) {
            try await store.cacheAccountLogo(Fixture.bytes, reference: foreign)
        }
        try await store.cacheAccountLogo(Fixture.bytes, reference: reference)
        _ = try await database.execute(sql: "INSERT INTO local_downloaded_account_logos(id,evidence_json) SELECT 'substituted',evidence_json FROM local_downloaded_account_logos", parameters: nil)
        await #expect(throws: AttachmentCapturePowerSyncStoreFailure.self) {
            try await store.orphanInventory()
        }
        _ = try await database.execute(sql: "DELETE FROM local_attachment_durability_scope_binding", parameters: nil)
        await #expect(throws: AttachmentCapturePowerSyncStoreFailure.self) {
            try await store.cachedAccountLogo(reference)
        }
        #expect(try await database.get("SELECT count(*) FROM local_attachment_durability_scope_binding") {
            try $0.getInt64(index: 0)
        } == 0)
        try await database.close()
    }

    private func logoReference(account: AccountID = Fixture.scope.accountId) throws -> AccountBusinessLogoReference {
        let hash = try AttachmentContentSHA256.make(bytes: Fixture.bytes).rawValue
        return try AccountBusinessLogoReference(accountId: account, attachmentId: "logo-test",
            sha256: hash, byteCount: String(Fixture.bytes.count), mediaType: "image/png",
            storagePath: "accounts/\(account.rawValue)/attachments/logo-test/\(hash)")
    }

    @Test("Corrupt downloaded cache repairs atomically but never overwrites upload-owned bytes", arguments: [false, true])
    func downloadedLogoRepair(uploadOwned: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.removeDirectory() }
        let database = try fixture.openDatabase()
        let vault = try fixture.makeVault()
        let store = fixture.makeStore(database: database, vault: vault)
        let reference = try logoReference()
        try await store.cacheAccountLogo(Fixture.bytes, reference: reference)
        let json = try await database.get("SELECT evidence_json FROM local_downloaded_account_logos") {
            try $0.getString(index: 0)
        }
        let evidence = try OperationContractCodec.decode(AttachmentPersistedLocalObjectEvidence.self, from: Data(json.utf8))
        if uploadOwned {
            _ = try await store.enqueue(LocalAttachmentCapture(attachmentId: reference.attachmentId,
                scope: evidence.scope, capturedAt: Fixture.capturedAt, bytes: Fixture.bytes))
        }
        let url = try await vault.objectFileURLForTesting(evidence.localObjectId)
        let original = try Data(contentsOf: url)
        var corrupt = original
        corrupt[corrupt.startIndex] ^= 1
        try corrupt.write(to: url)
        await #expect(throws: AttachmentLocalByteVaultFailure.self) { try await store.cachedAccountLogo(reference) }
        if uploadOwned {
            await #expect(throws: AttachmentCapturePowerSyncStoreFailure.self) {
                try await store.cacheAccountLogo(Fixture.bytes, reference: reference)
            }
            #expect(try Data(contentsOf: url) == corrupt)
        } else {
            try await store.cacheAccountLogo(Fixture.bytes, reference: reference)
            #expect(try await store.cachedAccountLogo(reference) == Fixture.bytes)
            #expect(try await store.pendingCount() == 0)
            #expect(try await store.orphanInventory().isEmpty)
        }
        try await database.close()
    }

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

    @Test("ATTACHRESOLVE-TEST-001 exact requested receipt resolves without FIFO substitution or consumption")
    func exactReceiptResolutionIsNonConsuming() async throws {
        let fixture = try Fixture()
        defer { fixture.removeDirectory() }
        let database = try fixture.openDatabase()
        let store = fixture.makeStore(database: database, vault: try fixture.makeVault())
        let firstBytes = Data("first attachment bytes".utf8)
        let secondBytes = Data("second attachment bytes".utf8)
        _ = try await store.enqueue(
            fixture.capture(id: "attachment-resolve-a", bytes: firstBytes)
        )
        let second = try await store.enqueue(
            fixture.capture(id: "attachment-resolve-b", bytes: secondBytes)
        )
        let before = try await Self.queueIdentityAndState(database)

        let resolved = try await store.resolveLocalAttachmentBytes(for: second)

        #expect(resolved == secondBytes)
        #expect(try await Self.queueIdentityAndState(database) == before)
        #expect(try await store.pendingCount() == 2)
        #expect(try await database.get("SELECT count(*) FROM ps_crud") {
            try $0.getInt64(index: 0)
        } == 0)
        try await database.close()
    }

    @Test("ATTACHRESOLVE-TEST-002 exact receipt and bytes survive close and reopen")
    func exactReceiptResolutionSurvivesRestart() async throws {
        let fixture = try Fixture()
        defer { fixture.removeDirectory() }
        let firstDatabase = try fixture.openDatabase()
        let firstStore = fixture.makeStore(
            database: firstDatabase,
            vault: try fixture.makeVault()
        )
        let bytes = Data("restart-resolved attachment".utf8)
        let receipt = try await firstStore.enqueue(
            fixture.capture(id: "attachment-resolve-restart", bytes: bytes)
        )
        let before = try await Self.queueIdentityAndState(firstDatabase)
        try await firstDatabase.close()

        let reopened = try fixture.openDatabase()
        let restored = fixture.makeStore(database: reopened, vault: try fixture.makeVault())
        #expect(try await restored.resolveLocalAttachmentBytes(for: receipt) == bytes)
        #expect(try await Self.queueIdentityAndState(reopened) == before)
        try await reopened.close()
    }

    @Test("ATTACHRESOLVE-TEST-003 scope, identity, receipt, and malformed evidence fail exactly")
    func exactReceiptResolutionRejectsRebinding() async throws {
        let fixture = try Fixture()
        defer { fixture.removeDirectory() }
        let database = try fixture.openDatabase()
        let store = fixture.makeStore(database: database, vault: try fixture.makeVault())
        let receipt = try await store.enqueue(
            fixture.capture(id: "attachment-resolve-identity")
        )

        let unknown = try fixture.receipt(id: "attachment-resolve-unknown")
        await #expect(throws: AttachmentLocalByteResolutionFailure.receiptNotFound) {
            _ = try await store.resolveLocalAttachmentBytes(for: unknown)
        }

        let changedParent = try fixture.receipt(
            id: receipt.attachmentId.rawValue,
            parentID: "item-attachment-resolver-other"
        )
        await #expect(throws: AttachmentLocalByteResolutionFailure.receiptMismatch) {
            _ = try await store.resolveLocalAttachmentBytes(for: changedParent)
        }

        let foreignScopes = [
            try Fixture.captureScope(environment: .targetStaging),
            try Fixture.captureScope(principal: "principal-resolver-foreign"),
            try Fixture.captureScope(account: "account-resolver-foreign")
        ]
        for foreignScope in foreignScopes {
            let foreign = try fixture.receipt(
                id: receipt.attachmentId.rawValue,
                scope: foreignScope
            )
            await #expect(throws: AttachmentLocalByteResolutionFailure.scopeMismatch) {
                _ = try await store.resolveLocalAttachmentBytes(for: foreign)
            }
        }

        let scopeFirstStore = fixture.makeStore(
            database: database,
            vault: try fixture.makeVault(),
            resolutionDatabaseAccessCheckpoint: { throw InjectedFailure() },
            resolutionLookupCheckpoint: { throw InjectedFailure() }
        )
        let foreignBeforeLookup = try fixture.receipt(
            id: receipt.attachmentId.rawValue,
            scope: foreignScopes[0]
        )
        await #expect(throws: AttachmentLocalByteResolutionFailure.scopeMismatch) {
            _ = try await scopeFirstStore.resolveLocalAttachmentBytes(
                for: foreignBeforeLookup
            )
        }
        await #expect(throws: AttachmentLocalByteResolutionFailure.localReadUnavailable) {
            _ = try await scopeFirstStore.resolveLocalAttachmentBytes(for: receipt)
        }

        _ = try await database.execute(
            sql: "UPDATE \(AttachmentCapturePowerSyncTable.queue) SET account_id = ? WHERE id = ?",
            parameters: ["account-rebound-row", receipt.attachmentId.rawValue]
        )
        await #expect(throws: AttachmentLocalByteResolutionFailure.malformedLocalEvidence) {
            _ = try await store.resolveLocalAttachmentBytes(for: receipt)
        }
        _ = try await database.execute(
            sql: "UPDATE \(AttachmentCapturePowerSyncTable.queue) SET account_id = ? WHERE id = ?",
            parameters: [Fixture.scope.accountId.rawValue, receipt.attachmentId.rawValue]
        )

        _ = try await database.execute(
            sql: "UPDATE \(AttachmentCapturePowerSyncTable.queue) SET receipt_json = NULL WHERE id = ?",
            parameters: [receipt.attachmentId.rawValue]
        )
        await #expect(throws: AttachmentLocalByteResolutionFailure.malformedLocalEvidence) {
            _ = try await store.resolveLocalAttachmentBytes(for: receipt)
        }
        try await database.close()
    }

    @Test("ATTACHRESOLVE-TEST-004 media and live read faults return no bytes and mutate no queue state")
    func exactReceiptResolutionFaultsRemainReadOnly() async throws {
        let fixture = try Fixture()
        defer { fixture.removeDirectory() }
        let database = try fixture.openDatabase()
        let vault = try fixture.makeVault()
        let store = fixture.makeStore(database: database, vault: vault)
        let missing = try await store.enqueue(
            fixture.capture(id: "attachment-resolve-a-missing")
        )
        let corrupt = try await store.enqueue(
            fixture.capture(id: "attachment-resolve-b-corrupt")
        )
        let tampered = try await store.enqueue(
            fixture.capture(id: "attachment-resolve-c-tampered")
        )
        let linked = try await store.enqueue(
            fixture.capture(id: "attachment-resolve-d-linked")
        )
        let symlinked = try await store.enqueue(
            fixture.capture(id: "attachment-resolve-e-symlinked")
        )
        let malformedCount = try await store.enqueue(
            fixture.capture(id: "attachment-resolve-f-count")
        )
        let malformedDigest = try await store.enqueue(
            fixture.capture(id: "attachment-resolve-g-digest")
        )
        let malformedFingerprint = try await store.enqueue(
            fixture.capture(id: "attachment-resolve-h-fingerprint")
        )
        let before = try await Self.queueIdentityAndState(database)

        try FileManager.default.removeItem(
            at: try await vault.objectFileURLForTesting(missing.localObjectId)
        )
        let corruptURL = try await vault.objectFileURLForTesting(corrupt.localObjectId)
        try Data(try Data(contentsOf: corruptURL).prefix(8)).write(to: corruptURL)
        let tamperedURL = try await vault.objectFileURLForTesting(tampered.localObjectId)
        var tamperedCiphertext = try Data(contentsOf: tamperedURL)
        let tamperIndex = tamperedCiphertext.index(
            tamperedCiphertext.startIndex,
            offsetBy: tamperedCiphertext.count / 2
        )
        tamperedCiphertext[tamperIndex] ^= 0x01
        try tamperedCiphertext.write(to: tamperedURL)
        let linkedURL = try await vault.objectFileURLForTesting(linked.localObjectId)
        let extraLink = fixture.directory.appendingPathComponent("resolver-extra-link")
        try FileManager.default.linkItem(at: linkedURL, to: extraLink)
        let symlinkedURL = try await vault.objectFileURLForTesting(
            symlinked.localObjectId
        )
        let movedSymlinkTarget = fixture.directory.appendingPathComponent(
            "resolver-moved-symlink-target"
        )
        try FileManager.default.moveItem(at: symlinkedURL, to: movedSymlinkTarget)
        try FileManager.default.createSymbolicLink(
            at: symlinkedURL,
            withDestinationURL: movedSymlinkTarget
        )
        _ = try await database.execute(
            sql: "UPDATE \(AttachmentCapturePowerSyncTable.queue) SET byte_count = byte_count + 1 WHERE id = ?",
            parameters: [malformedCount.attachmentId.rawValue]
        )
        _ = try await database.execute(
            sql: "UPDATE \(AttachmentCapturePowerSyncTable.queue) SET content_sha256 = ? WHERE id = ?",
            parameters: [
                String(repeating: "0", count: 64),
                malformedDigest.attachmentId.rawValue
            ]
        )
        _ = try await database.execute(
            sql: "UPDATE \(AttachmentCapturePowerSyncTable.queue) SET receipt_fingerprint = ? WHERE id = ?",
            parameters: [
                String(repeating: "0", count: 64),
                malformedFingerprint.attachmentId.rawValue
            ]
        )

        await #expect(throws: AttachmentLocalByteResolutionFailure.missingBytes) {
            _ = try await store.resolveLocalAttachmentBytes(for: missing)
        }
        await #expect(throws: AttachmentLocalByteResolutionFailure.corruptBytes) {
            _ = try await store.resolveLocalAttachmentBytes(for: corrupt)
        }
        await #expect(throws: AttachmentLocalByteResolutionFailure.corruptBytes) {
            _ = try await store.resolveLocalAttachmentBytes(for: tampered)
        }
        await #expect(throws: AttachmentLocalByteResolutionFailure.corruptBytes) {
            _ = try await store.resolveLocalAttachmentBytes(for: linked)
        }
        await #expect(throws: AttachmentLocalByteResolutionFailure.corruptBytes) {
            _ = try await store.resolveLocalAttachmentBytes(for: symlinked)
        }
        for malformed in [malformedCount, malformedDigest, malformedFingerprint] {
            await #expect(throws: AttachmentLocalByteResolutionFailure.malformedLocalEvidence) {
                _ = try await store.resolveLocalAttachmentBytes(for: malformed)
            }
        }

        let lookupFailure = fixture.makeStore(
            database: database,
            vault: vault,
            resolutionLookupCheckpoint: { throw InjectedFailure() }
        )
        await #expect(throws: AttachmentLocalByteResolutionFailure.localReadUnavailable) {
            _ = try await lookupFailure.resolveLocalAttachmentBytes(for: linked)
        }
        let vaultReadFailure = fixture.makeStore(
            database: database,
            vault: vault,
            resolutionRead: { _ in throw AttachmentLocalByteVaultFailure.storageFailure }
        )
        await #expect(throws: AttachmentLocalByteResolutionFailure.localReadUnavailable) {
            _ = try await vaultReadFailure.resolveLocalAttachmentBytes(for: linked)
        }
        let lookupCancellation = fixture.makeStore(
            database: database,
            vault: vault,
            resolutionLookupCheckpoint: { throw CancellationError() }
        )
        await #expect(throws: CancellationError.self) {
            _ = try await lookupCancellation.resolveLocalAttachmentBytes(for: linked)
        }
        let vaultCancellation = fixture.makeStore(
            database: database,
            vault: vault,
            resolutionRead: { _ in throw CancellationError() }
        )
        await #expect(throws: CancellationError.self) {
            _ = try await vaultCancellation.resolveLocalAttachmentBytes(for: linked)
        }
        #expect(
            AttachmentLocalByteResolutionFailure.localReadUnavailable.diagnosticCode
                == "attachment_local_byte_read_unavailable"
        )
        #expect(try await Self.queueIdentityAndState(database) == before)
        #expect(try await store.pendingCount() == Int64(before.count))
        #expect(try await database.get("SELECT count(*) FROM ps_crud") {
            try $0.getInt64(index: 0)
        } == 0)
        #expect(throws: AttachmentLocalByteVaultFailure.invalidMediaKey) {
            try fixture.makeVault(keyByte: 0x99)
        }
        try await database.close()
    }

    private static func queueIdentityAndState(
        _ database: any PowerSyncDatabaseProtocol
    ) async throws -> [String] {
        try await database.getAll(
            "SELECT id, state FROM \(AttachmentCapturePowerSyncTable.queue) ORDER BY persisted_at_ms ASC, id ASC"
        ) { cursor in
            "\(try cursor.getString(name: "id")):\(try cursor.getString(name: "state"))"
        }
    }
}

private struct InjectedFailure: Error {}

private actor CaptureTestAuthority {
    private var allowed = true
    func setAllowed(_ value: Bool) { allowed = value }
    func requireAccess() throws { if !allowed { throw InjectedFailure() } }
}

private actor LogoMutationGate {
    private var paused = false
    private var released = false
    private var pause: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    func pauseOnce() async {
        guard !paused else { return }
        paused = true
        observer?.resume(); observer = nil
        if !released { await withCheckedContinuation { pause = $0 } }
    }
    func waitForPause() async {
        if !paused { await withCheckedContinuation { observer = $0 } }
    }
    func release() { released = true; pause?.resume(); pause = nil }
}

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
        storeFault: @Sendable @escaping (AttachmentStoreCheckpoint) throws -> Void = { _ in },
        resolutionRead:
            (@Sendable (AttachmentPersistedLocalObjectEvidence) async throws -> Data)? = nil,
        resolutionDatabaseAccessCheckpoint: @Sendable @escaping () async throws -> Void = {},
        resolutionLookupCheckpoint: @Sendable @escaping () async throws -> Void = {}
    ) -> AttachmentCapturePowerSyncStore {
        AttachmentCapturePowerSyncStore(
            database: database,
            vault: vault,
            scope: Self.scope,
            now: { Self.persistedDate },
            fault: storeFault,
            resolutionRead: resolutionRead,
            resolutionDatabaseAccessCheckpoint: resolutionDatabaseAccessCheckpoint,
            resolutionLookupCheckpoint: resolutionLookupCheckpoint
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

    func receipt(
        id: String,
        scope: AttachmentCaptureScope = Fixture.captureScope,
        parentID: String? = nil,
        bytes: Data = Fixture.bytes
    ) throws -> AttachmentLocalDurabilityReceipt {
        let effectiveScope: AttachmentCaptureScope
        if let parentID {
            effectiveScope = AttachmentCaptureScope(
                environment: scope.environment,
                principalId: scope.principalId,
                accountId: scope.accountId,
                parent: LedgerEntityReference(
                    kind: .item,
                    id: try EntityID(validating: parentID)
                )
            )
        } else {
            effectiveScope = scope
        }
        let capture = try LocalAttachmentCapture(
            attachmentId: AttachmentID(validating: id),
            scope: effectiveScope,
            capturedAt: Self.capturedAt,
            bytes: bytes
        )
        let evidence = try AttachmentPersistedLocalObjectEvidence(
            attachmentId: capture.attachmentId,
            scope: effectiveScope,
            localObjectId: AttachmentLocalObjectID(
                validating: String(repeating: "d", count: 64)
            ),
            byteCount: capture.byteCount,
            contentSHA256: capture.contentSHA256,
            persistedAt: try AttachmentEpochMilliseconds(validating: 2_000)
        )
        return try AttachmentLocalDurabilityReceipt(
            accepting: capture,
            persistedEvidence: evidence
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

    static func captureScope(
        environment: LedgerEnvironmentKind = scope.environment,
        principal: String = scope.principalId.rawValue,
        account: String = scope.accountId.rawValue
    ) throws -> AttachmentCaptureScope {
        AttachmentCaptureScope(
            environment: environment,
            principalId: try PrincipalID(validating: principal),
            accountId: try AccountID(validating: account),
            parent: captureScope.parent
        )
    }
}
