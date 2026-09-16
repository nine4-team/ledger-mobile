import Foundation
import Auth
import LedgerTargetCore
import PowerSync
import Testing
#if canImport(CoreGraphics)
import CoreGraphics
#endif

@testable import LedgerTargetPowerSync

@Suite("Account workspace pending-work runtime", .serialized)
struct AccountWorkspacePendingWorkRuntimeTests {
    @Test("Actual local attachment scheduling publishes, syncs and retains offline bytes after restart",
          .enabled(if: ProcessInfo.processInfo.environment["LEDGER_ATTACHMENT_RUNTIME"] == "1",
                   "Run test-local-transaction-attachment-upload.mjs with LEDGER_ATTACHMENT_RUNTIME=1"),
          .timeLimit(.minutes(1)))
    func attachmentLiveReplication() async throws {
        let input = ProcessInfo.processInfo.environment
        guard input["LEDGER_ATTACHMENT_LOCAL_URL"] == "http://127.0.0.1:54321",
              let account = input["LEDGER_ATTACHMENT_LOCAL_ACCOUNT"], account == "account-primary",
              let principal = input["LEDGER_ATTACHMENT_LOCAL_PRINCIPAL"], principal.hasPrefix("upload-http-owner-"),
              let parent = input["LEDGER_ATTACHMENT_LOCAL_TRANSACTION"], parent.hasPrefix("upload-http-transaction-"),
              let attachment = input["LEDGER_ATTACHMENT_LOCAL_ATTACHMENT"], attachment.hasPrefix("upload-http-attachment-"),
              let key = input["LEDGER_ATTACHMENT_LOCAL_KEY"], let email = input["LEDGER_ATTACHMENT_LOCAL_EMAIL"],
              let password = input["LEDGER_ATTACHMENT_LOCAL_PASSWORD"] else { throw RuntimeInjectedFailure() }
        let context = try RuntimeTestContext(suffix: "attachment-live-\(UUID())",
            accountId: AccountID(validating: account), principalId: PrincipalID(validating: principal))
        defer { context.remove() }
        let url = URL(string: "http://127.0.0.1:54321")!
        let auth = AuthClient(configuration: .init(url: url.appendingPathComponent("auth/v1"),
            headers: ["apikey": key], storageKey: "attachment-live-\(UUID())", localStorage: CategoryAuthTestStorage(),
            fetch: { try await URLSession.shared.data(for: $0) }, autoRefreshToken: false,
            emitLocalSessionAsInitialSession: true))
        let entry = await SupabaseOnlineSignIn(client: auth, supabaseURL: url, publishableKey: key)
        try await entry.signIn(email: email, password: password)
        let directory = try await entry.accounts(environment: context.environment.manifest.environment)
        let authorization = try await entry.authorize(AccountSelectionPolicy.makeIntent(selecting: context.accountId,
            from: directory.snapshot, requestedAt: Date()))
        let scope = TransactionScope.businessInventory(accountId: context.accountId)
        let transactionId = try TransactionID(validating: parent)
        var originals: [(bytes: Data, mediaType: String, fileName: String)] = (0..<2).map {
            (Data(repeating: UInt8(40 + $0), count: 1024 + $0), "image/png", "Local proof \($0).png")
        }
        #if canImport(CoreGraphics)
        let pdf = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: pdf))
        var page = CGRect(x: 0, y: 0, width: 100, height: 100)
        let document = try #require(CGContext(consumer: consumer, mediaBox: &page, nil))
        document.beginPDFPage(nil); document.fill(CGRect(x: 10, y: 10, width: 20, height: 20))
        document.endPDFPage(); document.closePDF()
        originals.append((pdf as Data, "application/pdf", "Original receipt.pdf"))
        #else
        throw RuntimeInjectedFailure()
        #endif
        let runtime = try await context.openRuntime()
        do {
            try await entry.startWorkspaceSync(runtime, authorization: authorization,
                powerSyncURL: URL(string: "http://127.0.0.1:5590")!)
            var updates = runtime.watchDownloadedTransactionAttachments(scope: scope,
                transactionId: transactionId, section: .receipts).makeAsyncIterator()
            while let value = try await updates.next() {
                if value?.isComplete == true { break }
            }
            let captureScope = try await runtime.transactionAttachmentCaptureScope(scope: scope, transactionId: transactionId)
            for (index, original) in originals.enumerated() {
                let bytes = original.bytes
                let capture = try LocalAttachmentCapture(attachmentId: AttachmentID(validating: "\(attachment)-\(index)"),
                    scope: captureScope, capturedAt: AttachmentEpochMilliseconds(validating: Int64(Date().timeIntervalSince1970 * 1000)),
                    bytes: bytes, metadata: .init(mediaType: original.mediaType,
                        fileName: original.fileName, transactionSection: .receipts))
                _ = try await runtime.captureTransactionAttachment(capture, scope: scope)
                var published = false
                var pendingPresentation: (DownloadedTransactionAttachments, DownloadedTransactionAttachment)?
                while let value = try await updates.next() {
                    guard let value, value.isComplete,
                          let reference = value.attachments.first(where: { $0.object.attachmentId == capture.attachmentId }) else { continue }
                    if reference.localReceipt != nil {
                        pendingPresentation = (value, reference)
                        continue
                    }
                    guard try await runtime.pendingWorkSummary().unverifiedAttachmentCount == 0 else { continue }
                    let (pendingCatalog, pendingReference) = try #require(pendingPresentation)
                    #expect(value.publishedReplacement(for: pendingReference, from: pendingCatalog) == reference)
                    #expect(!value.retains(pendingReference, from: pendingCatalog))
                    #expect(try await runtime.loadDownloadedTransactionAttachment(catalog: value,
                        attachment: reference, allowDownload: false) == bytes)
                    published = true
                    break
                }
                #expect(published)
            }
            try await runtime.close()
            let reopened = try await context.openRuntime()
            let catalog = try await reopened.readDownloadedTransactionAttachments(scope: scope,
                transactionId: transactionId, section: .receipts)
            #expect(catalog.attachments.count == originals.count)
            for (index, reference) in catalog.attachments.enumerated() {
                let original = originals[index]
                #expect(reference.localReceipt == nil)
                #expect(reference.object.mediaType == original.mediaType)
                #expect(reference.fileName == original.fileName)
                #expect(reference.position == index)
                #expect(reference.isPrimary == (index == 0))
                #expect(try await reopened.loadDownloadedTransactionAttachment(catalog: catalog, attachment: reference,
                    allowDownload: false) == original.bytes)
            }
            #expect(try await reopened.pendingWorkSummary().unverifiedAttachmentCount == 0)
            try await reopened.close()
            try await auth.signOut(scope: .local)
        } catch {
            try? await runtime.close()
            throw error
        }
    }

    @Test("Item original and thumbnail bytes require the same live reference after download",
          arguments: ["unchanged", "reference", "removed", "thumbnail-link"], [false,true])
    func itemImageDownloadAuthorization(change: String, thumbnail: Bool) async throws {
        let context = try RuntimeTestContext(suffix: "item-image-\(change)-\(thumbnail)")
        let databases = LockedRecorder<any PowerSyncDatabaseProtocol>()
        let gate = ManualGate()
        let bytes = Data([1, 2, 3])
        let hash = try AttachmentContentSHA256.make(bytes: bytes).rawValue
        let itemId = try ItemID(validating: "physical-chair")
        var dependencies = physicalItemDependencies(context)
        let validate = dependencies.validateStructuredDatabase
        dependencies.validateStructuredDatabase = { database in
            try await validate(database)
            _ = try await database.execute(sql: "INSERT INTO item_image_objects(id,account_id,content_sha256,byte_count,media_type,storage_path) VALUES('image','account-runtime',?,'3','image/png',?)",
                parameters: [hash, "accounts/account-runtime/attachments/image/\(hash)"])
            _ = try await database.execute(sql: "INSERT INTO item_image_sets(id,account_id,item_id,revision,expected_count) VALUES('physical-chair','account-runtime','physical-chair','1',1)", parameters: nil)
            _ = try await database.execute(sql: "INSERT INTO item_image_references(id,account_id,item_id,attachment_id,set_revision,position,is_primary) VALUES('image-ref','account-runtime','physical-chair','image','1',0,1)", parameters: nil)
            if thumbnail {
                _ = try await database.execute(sql: "INSERT INTO item_image_objects(id,account_id,content_sha256,byte_count,media_type,storage_path) VALUES('small','account-runtime',?,'3','image/jpeg',?)",
                    parameters: [hash,"accounts/account-runtime/attachments/small/\(hash)"])
                _ = try await database.execute(sql: "INSERT INTO item_card_thumbnails(id,account_id,original_attachment_id,thumbnail_attachment_id,recipe,pixel_width,pixel_height) VALUES('small-link','account-runtime','image','small','item-card-300-jpeg-v1',300,200)",parameters: nil)
            }
            databases.append(database)
        }
        dependencies.downloadImage = { object in
            #expect(object.attachmentId.rawValue == (thumbnail ? "small" : "image"))
            await gate.wait(); return bytes
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let database = try #require(databases.values.first)
        var images = runtime.watchDownloadedItemImages(accountId: context.accountId, itemId: itemId).makeAsyncIterator()
        let catalog = try #require(await images.next())
        #expect(catalog.isComplete)
        let image = try #require(catalog.images.first)
        @Sendable func load(_ allowDownload: Bool) async throws -> Data? {
            if thumbnail {
                return try await runtime.loadDownloadedItemThumbnail(accountId: context.accountId,itemId: itemId,
                    image: image,allowDownload: allowDownload)
            }
            return try await runtime.loadDownloadedItemImage(accountId: context.accountId,itemId: itemId,
                image: image,allowDownload: allowDownload)
        }
        #expect(try await load(false) == nil)
        let download = Task { try await load(true) }
        await gate.waitUntilEntered()
        if change == "reference" {
            _ = try await database.execute(sql: "UPDATE item_image_sets SET revision='2',expected_count=0", parameters: nil)
        } else if change == "removed" {
            _ = try await database.execute(sql: "UPDATE spike_account_memberships SET state='removed'", parameters: nil)
        } else if change == "thumbnail-link", thumbnail {
            _ = try await database.execute(sql: "DELETE FROM item_card_thumbnails",parameters: nil)
        }
        await gate.release()
        if change == "unchanged" || (change == "thumbnail-link" && !thumbnail) {
            #expect(try await download.value == bytes)
            #expect(try await load(false) == bytes)
        } else {
            await #expect(throws: (any Error).self) { try await download.value }
        }
        try await runtime.close()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            try await load(false)
        }
        if change == "unchanged" || (change == "thumbnail-link" && !thumbnail) {
            // Reopen the actual encrypted workspace without reseeding its rows.
            // The gallery normally permits downloads; an offline cache hit must
            // still succeed with that option enabled, without calling transport.
            var offline = context.dependencies()
            offline.downloadImage = { _ in
                Issue.record("Reopened authorized cache must not require the network")
                throw RuntimeInjectedFailure()
            }
            let restored = try await context.openRuntime(dependencies: offline)
            var restoredImages = restored.watchDownloadedItemImages(accountId: context.accountId, itemId: itemId).makeAsyncIterator()
            let restoredCatalog = try #require(await restoredImages.next())
            #expect(restoredCatalog.isComplete)
            let restoredImage = try #require(restoredCatalog.images.first)
            if thumbnail {
                #expect(try await restored.loadDownloadedItemThumbnail(accountId: context.accountId,
                    itemId: itemId, image: restoredImage, allowDownload: true) == bytes)
            } else {
                #expect(try await restored.loadDownloadedItemImage(accountId: context.accountId,
                    itemId: itemId, image: restoredImage, allowDownload: true) == bytes)
            }
            try await restored.close()
        }
        context.remove()
    }

    @Test("Removing a logo while its bytes download never restores the old image")
    func accountProfileChangedLogoDuringDownload() async throws {
        let context = try RuntimeTestContext(suffix: "profile-changed-logo")
        let databases = LockedRecorder<any PowerSyncDatabaseProtocol>()
        let gate = ManualGate()
        let bytes = Data([1, 2, 3])
        let hash = try AttachmentContentSHA256.make(bytes: bytes).rawValue
        var dependencies = physicalItemDependencies(context)
        let validate = dependencies.validateStructuredDatabase
        dependencies.validateStructuredDatabase = { database in
            try await validate(database)
            _ = try await database.execute(sql: "INSERT INTO spike_accounts(id,display_name) VALUES('account-runtime','Design studio')", parameters: nil)
            _ = try await database.execute(sql: """
                INSERT INTO spike_account_business_profiles(id,account_id,logo_attachment_id,
                logo_content_sha256,logo_byte_count,logo_media_type,logo_storage_path)
                VALUES('account-runtime','account-runtime','old-logo',?,'3','image/png',?)
                """, parameters: [hash, "accounts/account-runtime/attachments/old-logo/\(hash)"])
            databases.append(database)
        }
        dependencies.downloadImage = { _ in await gate.wait(); return bytes }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        var iterator = runtime.watchAccountBusinessProfile(accountId: context.accountId).makeAsyncIterator()
        #expect(try await iterator.next()?.logo == .notDownloaded)
        await gate.waitUntilEntered()
        let database = try #require(databases.values.first)
        _ = try await database.execute(sql: """
            UPDATE spike_account_business_profiles SET logo_attachment_id=NULL,
            logo_content_sha256=NULL,logo_byte_count=NULL,logo_media_type=NULL,logo_storage_path=NULL
            WHERE id='account-runtime'
            """, parameters: nil)
        await gate.release()
        #expect(try await iterator.next()?.logo == .absent)
        #expect(try await runtime.readAccountBusinessProfile(accountId: context.accountId).logo == .absent)
        try await runtime.close()
        context.remove()
    }

    @Test("Profile first download arrives through selected subscription; disappearing evidence ends access")
    func accountProfileFirstDownloadAndDisappearance() async throws {
        let context = try RuntimeTestContext(suffix: "profile-first-download")
        let databases = LockedRecorder<any PowerSyncDatabaseProtocol>()
        var dependencies = physicalItemDependencies(context)
        let validate = dependencies.validateStructuredDatabase
        dependencies.validateStructuredDatabase = { database in
            try await validate(database)
            _ = try await database.execute(sql: "INSERT INTO spike_accounts(id,display_name) VALUES('account-runtime','Design studio')", parameters: nil)
            databases.append(database)
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let database = try #require(databases.values.first)
        let stream = runtime.watchAccountBusinessProfile(accountId: context.accountId)
        var registrations: [String] = []
        for _ in 0..<500 {
            registrations = try await database.getAll(sql: "SELECT local_params FROM ps_stream_subscriptions WHERE stream_name='account_business_profile'",
                parameters: nil, mapper: { try $0.getString(name: "local_params") })
            if !registrations.isEmpty { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        let parameters = try #require(registrations.first)
        let decoded = try JSONSerialization.jsonObject(with: Data(parameters.utf8)) as? [String: String]
        #expect(decoded == ["account_id": context.accountId.rawValue])
        _ = try await database.execute(sql: "INSERT INTO spike_account_business_profiles(id,account_id) VALUES('account-runtime','account-runtime')", parameters: nil)
        var iterator = stream.makeAsyncIterator()
        let profile = try #require(await iterator.next())
        #expect(profile.name.rawValue == "Design studio" && profile.logo == .absent)
        _ = try await database.execute(sql: "DELETE FROM spike_account_business_profiles WHERE id='account-runtime'", parameters: nil)
        await #expect(throws: AccountBusinessProfileReadFailure.self) {
            _ = try await iterator.next()
        }
        try await runtime.close()
        context.remove()
    }

    @Test("Account close and removal drain a cancelled logo download before database teardown", arguments: [false, true])
    func accountProfileDownloadDrain(removing: Bool) async throws {
        let context = try RuntimeTestContext(suffix: "profile-download-drain-\(removing)")
        let databases = LockedRecorder<any PowerSyncDatabaseProtocol>()
        let events = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        let downloadGate = ManualGate()
        let cancellation = AsyncStream<Void>.makeStream()
        var dependencies = physicalItemDependencies(context)
        dependencies.lifecycleEvent = { events.append($0) }
        let validate = dependencies.validateStructuredDatabase
        dependencies.validateStructuredDatabase = { database in
            try await validate(database)
            let hash = String(repeating: "a", count: 64)
            _ = try await database.execute(sql: "INSERT INTO spike_accounts(id,display_name) VALUES('account-runtime','Design studio')", parameters: nil)
            _ = try await database.execute(sql: """
                INSERT INTO spike_account_business_profiles(id,account_id,logo_attachment_id,
                logo_content_sha256,logo_byte_count,logo_media_type,logo_storage_path)
                VALUES('account-runtime','account-runtime','logo',?,'1','image/png',?)
                """, parameters: [hash, "accounts/account-runtime/attachments/logo/\(hash)"])
            databases.append(database)
        }
        dependencies.downloadImage = { _ in
            await withTaskCancellationHandler {
                await downloadGate.wait()
            } onCancel: {
                cancellation.continuation.yield(())
            }
            // Even a dependency returning bytes after cancellation must not cache them.
            return Data([1])
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let consumer = Task {
            do {
                for try await profile in runtime.watchAccountBusinessProfile(accountId: context.accountId) {
                    #expect(profile.logo == .notDownloaded)
                }
            } catch { }
        }
        await downloadGate.waitUntilEntered()
        let database = try #require(databases.values.first)
        _ = try await database.execute(sql: "UPDATE spike_accounts SET display_name='Renamed studio' WHERE id='account-runtime'", parameters: nil)
        let current = try await runtime.readAccountBusinessProfile(accountId: context.accountId)
        #expect(current.name.rawValue == "Renamed studio")
        #expect(current.logo == .notDownloaded)
        _ = try await database.execute(sql: "DELETE FROM spike_account_business_profiles WHERE id='account-runtime'", parameters: nil)
        await #expect(throws: AccountBusinessProfileReadFailure.self) {
            try await runtime.readAccountBusinessProfile(accountId: context.accountId)
        }
        let closing = Task {
            if removing { try await runtime.lockAccessPreservingPendingWork() }
            else { try await runtime.close() }
        }
        var cancelled = cancellation.stream.makeAsyncIterator()
        _ = await cancelled.next()
        #expect(!events.values.contains(.structuredDatabaseCloseAttempted))
        #expect(!events.values.contains(.attachmentDatabaseCloseAttempted))
        await downloadGate.release()
        try await closing.value
        await consumer.value
        #expect(events.values.filter { $0 == .structuredDatabaseCloseAttempted }.count == 1)
        #expect(events.values.filter { $0 == .attachmentDatabaseCloseAttempted }.count == 1)
        cancellation.continuation.finish()
        context.remove()
    }

    @Test("Account profile facade reopens downloaded branding and denies foreign or locked workspaces")
    func accountProfileRestartAndIsolation() async throws {
        let context = try RuntimeTestContext(suffix: "profile-restart")
        var dependencies = physicalItemDependencies(context)
        let validate = dependencies.validateStructuredDatabase
        dependencies.validateStructuredDatabase = { database in
            try await validate(database)
            _ = try await database.execute(sql: "INSERT INTO spike_accounts(id,display_name) VALUES('account-runtime','Design studio')", parameters: nil)
            _ = try await database.execute(sql: "INSERT INTO spike_account_business_profiles(id,account_id) VALUES('account-runtime','account-runtime')", parameters: nil)
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        var first = runtime.watchAccountBusinessProfile(accountId: context.accountId).makeAsyncIterator()
        let profile = try #require(await first.next())
        #expect(profile.accountId == context.accountId)
        #expect(profile.logo == .absent)
        #expect(profile.isStale)
        await #expect(throws: LedgerOfflineClientRuntimeFailure.accountScopeMismatch) {
            var foreign = runtime.watchAccountBusinessProfile(accountId: try AccountID(validating: "foreign-account")).makeAsyncIterator()
            _ = try await foreign.next()
        }
        try await runtime.close()
        let reopened = try await context.openRuntime()
        var restored = reopened.watchAccountBusinessProfile(accountId: context.accountId).makeAsyncIterator()
        let saved = try #require(await restored.next())
        #expect(saved.name == profile.name && saved.logo == profile.logo)
        try await reopened.lockAccessPreservingPendingWork()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            var denied = reopened.watchAccountBusinessProfile(accountId: context.accountId).makeAsyncIterator()
            _ = try await denied.next()
        }
        context.remove()
    }

    @Test("Client physical report uses runtime access and retains incomplete evidence across encrypted restart")
    func clientPhysicalReportFacade() async throws {
        let context = try RuntimeTestContext(suffix: "client-physical-report")
        var dependencies = physicalItemDependencies(context)
        let validate = dependencies.validateStructuredDatabase
        dependencies.validateStructuredDatabase = { database in
            try await validate(database)
            _ = try await database.execute(sql: "UPDATE spike_projects SET client_id='report-client',display_name='Property',lifecycle='active',revision=1 WHERE id='project-physical'", parameters: nil)
            _ = try await database.execute(sql: "INSERT INTO spike_clients(id,account_id,display_name,lifecycle,revision) VALUES('report-client','account-runtime','Client','active',1)", parameters: nil)
            _ = try await database.execute(sql: "INSERT INTO ps_stream_subscriptions(stream_name,active,is_default,local_params,last_synced_at) VALUES('property_management_report',1,0,?,1000000)", parameters: [#"{"account_id":"account-runtime","project_id":"project-physical"}"#])
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let project = try ProjectID(validating: "project-physical")
        let asOf = try ProtectedArtifactEpochMilliseconds(validating: 1_800_000_000_000)
        let snapshot = try await runtime.readDownloadedClientSummaryPhysicalReport(accountId: context.accountId,
            projectId: project, asOf: asOf)
        #expect(!snapshot.isComplete && snapshot.items.count == 1)
        #expect(snapshot.items.first?.name == "Chair")
        await #expect(throws: LedgerOfflineClientRuntimeFailure.accountScopeMismatch) {
            try await runtime.readDownloadedClientSummaryPhysicalReport(accountId: AccountID(validating: "foreign-account"),
                projectId: project, asOf: asOf)
        }
        try await runtime.close()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            try await runtime.readDownloadedClientSummaryPhysicalReport(accountId: context.accountId,
                projectId: project, asOf: asOf)
        }
        let reopened = try await context.openRuntime()
        let restored = try await reopened.readDownloadedClientSummaryPhysicalReport(accountId: context.accountId,
            projectId: project, asOf: asOf)
        #expect(restored.reference == snapshot.reference && !restored.isComplete)
        try await reopened.lockAccessPreservingPendingWork()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            try await reopened.readDownloadedClientSummaryPhysicalReport(accountId: context.accountId,
                projectId: project, asOf: asOf)
        }
        context.remove()
    }

    @Test("Property report facade preserves downloaded snapshot across encrypted restart and denies foreign or closed access")
    func propertyReportFacade() async throws {
        let context = try RuntimeTestContext(suffix: "property-report")
        var dependencies = physicalItemDependencies(context)
        let validate = dependencies.validateStructuredDatabase
        dependencies.validateStructuredDatabase = { database in
            try await validate(database)
            _ = try await database.execute(sql: "UPDATE spike_projects SET client_id='report-client',display_name='Property',lifecycle='active',revision=1 WHERE id='project-physical'", parameters: nil)
            _ = try await database.execute(sql: "UPDATE spike_account_memberships SET financial_access='full' WHERE account_id='account-runtime'", parameters: nil)
            _ = try await database.execute(sql: "INSERT INTO item_client_payment_connections(id,account_id,project_id,client_id,item_id,placement_id,transaction_id,transaction_type,transaction_role) SELECT 'runtime-payment-link',account_id,project_id,'report-client',item_id,id,'report-purchase','purchase','standalone' FROM spike_item_placements WHERE project_id='project-physical' AND ended_at IS NULL", parameters: nil)
            _ = try await database.execute(sql: "INSERT INTO ps_stream_subscriptions(stream_name,active,is_default,local_params,last_synced_at) VALUES('property_management_report',1,0,?,1000000)", parameters: [#"{"account_id":"account-runtime","project_id":"project-physical"}"#])
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let project = try ProjectID(validating: "project-physical")
        let currency = try CurrencyCode(validating: "USD")
        let asOf = try ProtectedArtifactEpochMilliseconds(validating: 1_800_000_000_000)
        let snapshot = try await runtime.readDownloadedPropertyManagementReport(accountId: context.accountId,
            projectId: project, currency: currency, asOf: asOf)
        #expect(snapshot.totals.itemCount == 1 && snapshot.totals.unknownMarketValueCount == 1)
        #expect(snapshot.groups.first?.rows.first?.name == "Chair")
        await #expect(throws: LedgerOfflineClientRuntimeFailure.accountScopeMismatch) {
            try await runtime.readDownloadedPropertyManagementReport(accountId: AccountID(validating: "foreign-account"),
                projectId: project, currency: currency, asOf: asOf)
        }
        try await runtime.close()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            try await runtime.readDownloadedPropertyManagementReport(accountId: context.accountId,
                projectId: project, currency: currency, asOf: asOf)
        }
        let reopened = try await context.openRuntime()
        let restored = try await reopened.readDownloadedPropertyManagementReport(accountId: context.accountId,
            projectId: project, currency: currency, asOf: asOf)
        #expect(restored.reference == snapshot.reference)
        try await reopened.lockAccessPreservingPendingWork()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            try await reopened.readDownloadedPropertyManagementReport(accountId: context.accountId,
                projectId: project, currency: currency, asOf: asOf)
        }
        context.remove()
    }

    @Test("Physical Item watch cleanup drains before workspace close or learned-removal teardown", arguments: [false, true])
    func physicalItemWatchCleanupDrain(removing: Bool) async throws {
        let context = try RuntimeTestContext(suffix: "physical-watch-cleanup-\(removing)")
        let events = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        let cleanup = ManualGate()
        let subscription = RuntimePhysicalSubscription(cleanup: cleanup)
        let subscribed = AsyncStream<Void>.makeStream()
        let values = AsyncStream<DownloadedItemPlacements>.makeStream()
        var dependencies = physicalItemDependencies(context)
        dependencies.lifecycleEvent = { events.append($0) }
        dependencies.subscribePhysicalItems = { account in
            #expect(account == context.accountId)
            subscribed.continuation.yield(())
            return subscription
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let consumer = Task {
            do {
                for try await value in runtime.watchDownloadedItemPlacements(accountId: context.accountId, scope: .businessInventory) {
                    values.continuation.yield(value)
                }
            } catch { }
        }
        var subscriptionIterator = subscribed.stream.makeAsyncIterator()
        _ = await subscriptionIterator.next()
        var valueIterator = values.stream.makeAsyncIterator()
        #expect(try #require(await valueIterator.next()).rows.isEmpty)
        let closing = Task {
            if removing { try await runtime.lockAccessPreservingPendingWork() }
            else { try await runtime.close() }
        }
        await cleanup.waitUntilEntered()
        #expect(!events.values.contains(.structuredDatabaseCloseAttempted))
        #expect(!events.values.contains(.attachmentDatabaseCloseAttempted))
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            try await runtime.readDownloadedItemPlacements(accountId: context.accountId, scope: .businessInventory)
        }
        await cleanup.release()
        try await closing.value
        await consumer.value
        #expect(await subscription.unsubscribeCount == 1)
        #expect(events.values.filter { $0 == .structuredDatabaseCloseAttempted }.count == 1)
        subscribed.continuation.finish(); values.continuation.finish()
        context.remove()
    }

    @Test("Concurrent physical Item watches release only their own subscription handles")
    func physicalItemConcurrentWatchOwnership() async throws {
        let context = try RuntimeTestContext(suffix: "physical-watch-peers")
        let cleanup = ManualGate()
        await cleanup.release()
        let subscriptions = AsyncStream<RuntimePhysicalSubscription>.makeStream()
        var dependencies = physicalItemDependencies(context)
        dependencies.subscribePhysicalItems = { _ in
            let subscription = RuntimePhysicalSubscription(cleanup: cleanup)
            subscriptions.continuation.yield(subscription)
            return subscription
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let first = Task {
            do { for try await _ in runtime.watchDownloadedItemPlacements(accountId: context.accountId, scope: .businessInventory) { } }
            catch { }
        }
        let second = Task {
            do { for try await _ in runtime.watchDownloadedItemPlacements(accountId: context.accountId, scope: .businessInventory) { } }
            catch { }
        }
        var iterator = subscriptions.stream.makeAsyncIterator()
        let a = try #require(await iterator.next())
        let b = try #require(await iterator.next())
        first.cancel()
        await first.value
        var count = 0
        for _ in 0..<2_000 {
            count = await a.unsubscribeCount + b.unsubscribeCount
            if count == 1 { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(count == 1)
        try await runtime.close()
        await second.value
        #expect(await a.unsubscribeCount == 1)
        #expect(await b.unsubscribeCount == 1)
        subscriptions.continuation.finish()
        context.remove()
    }

    @Test("Downloaded physical Item facade binds Account, reads owned storage and survives restart")
    func downloadedItemPlacementsFacade() async throws {
        let context = try RuntimeTestContext(suffix: "downloaded-items")
        let runtime = try await context.openRuntime(dependencies: physicalItemDependencies(context))
        let project = try ProjectID(validating: "project-physical")
        let empty = try await runtime.readDownloadedItemPlacements(accountId: context.accountId, scope: .businessInventory)
        #expect(empty.accountId == context.accountId)
        #expect(empty.scope == .businessInventory)
        #expect(empty.rows.isEmpty) // Downloaded rows only, not completeness.
        let snapshot = try await runtime.readDownloadedItemPlacements(accountId: context.accountId, scope: .project(project))
        #expect(snapshot.accountId == context.accountId)
        #expect(snapshot.scope == .project(project))
        #expect(snapshot.rows.count == 1)
        #expect(snapshot.rows.first?.itemId.rawValue == "physical-chair")
        #expect(snapshot.rows.first?.placementId.rawValue == "physical-placement")
        #expect(snapshot.rows.first?.itemRevision == 3)
        let itemId = try ItemID(validating: "physical-chair")
        let history = try await runtime.readDownloadedItemPlacementHistory(accountId: context.accountId, itemId: itemId)
        #expect(history.isPartial && history.intervals.map(\.placementId.rawValue) == ["physical-placement"])
        await #expect(throws: LedgerOfflineClientRuntimeFailure.accountScopeMismatch) {
            try await runtime.readDownloadedItemPlacementHistory(accountId: AccountID(validating: "account-other"), itemId: itemId)
        }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.accountScopeMismatch) {
            try await runtime.readDownloadedItemPlacements(accountId: AccountID(validating: "account-other"), scope: .project(project))
        }
        try await runtime.close()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            try await runtime.readDownloadedItemPlacements(accountId: context.accountId, scope: .project(project))
        }
        let reopened = try await context.openRuntime()
        let restored = try await reopened.readDownloadedItemPlacements(accountId: context.accountId, scope: .project(project))
        #expect(try await reopened.readDownloadedItemPlacementHistory(accountId: context.accountId, itemId: itemId) == history)
        #expect(restored.rows.map(\.placementId) == snapshot.rows.map(\.placementId))
        #expect(restored.rows.map(\.itemRevision) == snapshot.rows.map(\.itemRevision))
        try await reopened.close()
        context.remove()
    }

    @Test("Downloaded physical Item reads drain before close; learned removal suppresses admitted reads",
          arguments: [false, true], [false, true])
    func downloadedItemPlacementsDrain(removing: Bool, history: Bool) async throws {
        let context = try RuntimeTestContext(suffix: "downloaded-items-drain-\(removing)-\(history)")
        let gate = ManualGate()
        let events = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        let locked = AsyncStream<Void>.makeStream()
        var dependencies = physicalItemDependencies(context)
        dependencies.lifecycleEvent = { event in
            events.append(event)
            if event == .accessLocked { locked.continuation.yield(()) }
        }
        dependencies.finiteOperationCheckpoint = { operation in
            if operation == .readDownloadedItemPlacements { await gate.wait() }
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let itemId = try ItemID(validating: "physical-chair")
        let read = Task {
            if history {
                let value = try await runtime.readDownloadedItemPlacementHistory(accountId: context.accountId, itemId: itemId)
                #expect(value.intervals.count == 1)
            } else {
                let value = try await runtime.readDownloadedItemPlacements(accountId: context.accountId, scope: .businessInventory)
                #expect(value.rows.isEmpty)
            }
        }
        await gate.waitUntilEntered()
        let closing = Task {
            if removing { try await runtime.lockAccessPreservingPendingWork() }
            else { try await runtime.close() }
        }
        if removing {
            var iterator = locked.stream.makeAsyncIterator()
            _ = await iterator.next()
        } else {
            try await Task.sleep(for: .milliseconds(30))
        }
        #expect(!events.values.contains(.structuredDatabaseCloseAttempted))
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            if history {
                _ = try await runtime.readDownloadedItemPlacementHistory(accountId: context.accountId, itemId: itemId)
            } else {
                _ = try await runtime.readDownloadedItemPlacements(accountId: context.accountId, scope: .businessInventory)
            }
        }
        await gate.release()
        if removing {
            await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) { try await read.value }
        } else {
            try await read.value
        }
        try await closing.value
        #expect(events.values.filter { $0 == .structuredDatabaseCloseAttempted }.count == 1)
        locked.continuation.finish()
        context.remove()
    }

    @Test("Item history runtime watch terminates on close or learned removal and rejects further access",
          arguments: [false, true])
    func downloadedItemHistoryWatchLifecycle(removing: Bool) async throws {
        let context = try RuntimeTestContext(suffix: "history-watch-lifecycle-\(removing)")
        let runtime = try await context.openRuntime(dependencies: physicalItemDependencies(context))
        let itemId = try ItemID(validating: "physical-chair")
        let first = AsyncStream<Void>.makeStream()
        let consumer = Task {
            var count = 0
            do {
                for try await value in runtime.watchDownloadedItemPlacementHistory(accountId: context.accountId, itemId: itemId) {
                    #expect(value.accountId == context.accountId && value.itemId == itemId)
                    #expect(value.intervals.map(\.placementId.rawValue) == ["physical-placement"])
                    count += 1
                    first.continuation.yield(())
                }
            } catch is CancellationError {
                // Closing a tracked watch is cancellation, not missing history.
            } catch let failure as LedgerOfflineClientRuntimeFailure {
                #expect(failure == .runtimeClosed)
            } catch { Issue.record("Unexpected history stream failure: \(error)") }
            first.continuation.finish()
            return count
        }
        var iterator = first.stream.makeAsyncIterator()
        #expect(await iterator.next() != nil)
        var foreign = runtime.watchDownloadedItemPlacementHistory(
            accountId: try AccountID(validating: "account-other"), itemId: itemId).makeAsyncIterator()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.accountScopeMismatch) { try await foreign.next() }
        if removing { try await runtime.lockAccessPreservingPendingWork() }
        else { try await runtime.close() }
        #expect(await consumer.value >= 1)
        try await Self.expectClosed(runtime.watchDownloadedItemPlacementHistory(accountId: context.accountId, itemId: itemId))
        context.remove()
    }

    @Test("Invoice report public runtime retains download evidence and enforces access")
    func collectedInvoiceReportPublicRead() async throws {
        let context = try RuntimeTestContext(suffix: "invoice-report-read")
        defer { context.remove() }
        let databases = LockedRecorder<any PowerSyncDatabaseProtocol>()
        var dependencies = physicalItemDependencies(context)
        let validate = dependencies.validateStructuredDatabase
        dependencies.validateStructuredDatabase = { database in
            try await validate(database)
            for sql in [
                "UPDATE spike_account_memberships SET financial_access='full'",
                "INSERT INTO collected_invoices(id,account_id,project_id,client_id,sealed,purchase_id,invoice_revision,currency,total_minor_units) VALUES('invoice','account-runtime','project-physical','client',1,'payment',1,'USD','99')",
                "INSERT INTO collected_invoice_lines(id,account_id,invoice_id,line_position,source_kind,source_id,source_revision,category_id,signed_amount_minor_units,currency,description,source_snapshot_json) VALUES('line','account-runtime','invoice',0,'fee_installment','fee',1,'category','99','USD','Frozen fee','{\"feeInstallment\":{\"installmentId\":\"fee\"}}')"
            ] { _ = try await database.execute(sql: sql, parameters: nil) }
            databases.append(database)
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let database = try #require(databases.values.first)
        let project = try ProjectID(validating: "project-physical")
        @Sendable func read(_ account: AccountID) async throws -> CollectedInvoiceReportSnapshot {
            try await runtime.readCollectedInvoiceReport(accountId: account, projectId: project,
                invoiceId: .init(validating: "invoice"), asOf: .init(validating: 2000))
        }
        await #expect(throws: PropertyManagementReportFailure.incompleteReadiness) { try await read(context.accountId) }
        _ = try await database.execute(sql: "INSERT INTO ps_stream_subscriptions(stream_name,active,is_default,local_params,last_synced_at) VALUES('project_expenses',1,0,?,1000000)",
            parameters: [#"{"account_id":"account-runtime","project_id":"project-physical"}"#])
        let report = try await read(context.accountId)
        #expect(report.invoice.total.minorUnits == 99)
        #expect(report.provenance.lastSyncedAt?.rawValue == 1000)
        _ = try await database.execute(sql: "INSERT INTO collected_invoices(id,account_id,project_id,client_id,sealed,purchase_id,invoice_revision,currency,total_minor_units) VALUES('unrelated-incomplete','account-runtime','project-physical','client',1,'other-payment',1,'USD','42')", parameters: nil)
        var receivedSelectedInvoice = false
        for try await values in runtime.watchCollectedInvoices(accountId: context.accountId,
            projectId: project, invoiceId: try .init(validating: "invoice")) {
            guard let values else { continue }
            #expect(values == [report.invoice])
            receivedSelectedInvoice = true
            break
        }
        #expect(receivedSelectedInvoice)
        await #expect(throws: LedgerOfflineClientRuntimeFailure.accountScopeMismatch) {
            try await read(.init(validating: "other-account"))
        }
        _ = try await database.execute(sql: "UPDATE spike_account_memberships SET financial_access='none'", parameters: nil)
        await #expect(throws: ProjectInvoicingItemLocalReader.Failure.unavailable) { try await read(context.accountId) }
        try await runtime.close()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) { try await read(context.accountId) }
    }

    @Test("Expense edit requires downloaded scope and preserves pending intent separately")
    func expenseEditAdmissionAndPendingRead() async throws {
        let context = try RuntimeTestContext(suffix: "expense-edit-admission")
        defer { context.remove() }
        let databases = LockedRecorder<any PowerSyncDatabaseProtocol>()
        var dependencies = physicalItemDependencies(context)
        let validate = dependencies.validateStructuredDatabase
        dependencies.validateStructuredDatabase = { database in
            try await validate(database)
            for sql in [
                "UPDATE spike_account_memberships SET financial_access='full'",
                "INSERT INTO spike_budget_categories(id,account_id,kind,lifecycle) VALUES('category','account-runtime','general','active')",
                "INSERT INTO spike_clients(id,account_id,display_name,lifecycle,revision,created_at_ms,updated_at_ms) VALUES('expense-client','account-runtime','Client','active',1,1,1)",
                "UPDATE spike_projects SET client_id='expense-client',display_name='Project',lifecycle='active',revision=1 WHERE id='project-physical'",
                "INSERT INTO expenses(id,account_id,project_id,category_id,vendor,expense_date,final_amount_minor_units,currency,notes,revision) VALUES('expense','account-runtime','project-physical','category','Original','2026-09-15','100','USD','','1')"
            ] { _ = try await database.execute(sql: sql, parameters: nil) }
            databases.append(database)
        }
        var runtime = try await context.openRuntime(dependencies: dependencies)
        var database = try #require(databases.values.first)
        let project = try ProjectID(validating: "project-physical")
        let entry = try BusinessPaidExpenseDraft(accountId: context.accountId, projectId: project,
            expenseId: .init(validating: "expense"), vendor: "Edited", date: "2026-09-15",
            finalAmount: .init(minorUnits: 200, currency: .init(validating: "USD")),
            categoryId: .init(validating: "category"), notes: "Edit")
        let uuid = UUID(), time = Date()
        await #expect(throws: PropertyManagementReportFailure.incompleteReadiness) {
            try await runtime.editExpense(entry, expectedRevision: 1, operationUUID: uuid, capturedAt: time)
        }
        _ = try await database.execute(sql: "INSERT INTO ps_stream_subscriptions(stream_name,active,is_default,local_params,last_synced_at) VALUES('project_expenses',1,0,?,1000000)",
            parameters: [#"{"account_id":"account-runtime","project_id":"project-physical"}"#])
        let recovery = ExpenseEntryRecovery(accountId: context.accountId, projectId: project,
            expenseId: entry.expenseId, operationUUID: uuid, capturedAt: time,
            vendor: entry.vendor, date: time, amountText: "2.00", notes: entry.notes,
            categoryId: entry.categoryId, lines: [], attachmentIds: [],
            editContext: try .init(expectedRevision: 1, retainedAttachmentIds: []))
        try await runtime.saveExpenseEntry(recovery)
        try await runtime.close()
        var reopening = context.dependencies()
        let reopenValidation = reopening.validateStructuredDatabase
        reopening.validateStructuredDatabase = { reopened in
            try await reopenValidation(reopened)
            databases.append(reopened)
        }
        runtime = try await context.openRuntime(dependencies: reopening)
        database = try #require(databases.values.last)
        let unfinished = try await runtime.readExpenses(accountId: context.accountId, projectId: project)
        #expect(unfinished.unfinishedEntries.isEmpty)
        #expect(unfinished.unfinishedEdits == [recovery])
        #expect(try await runtime.pendingWorkSummary().unfinishedEntryCount == 1)
        #expect(try await runtime.restoreExpenseEntryCaptures(recovery).isEmpty)
        var staleRecovery = recovery
        staleRecovery.notes = "Old draft"
        await #expect(throws: ExpenseEntryRecoveryFailure.staleEntry) {
            try await runtime.editExpense(entry, expectedRevision: 1, operationUUID: uuid, capturedAt: time, recovery: staleRecovery)
        }
        let accepted = try await runtime.editExpense(entry, expectedRevision: 1, operationUUID: uuid, capturedAt: time, recovery: recovery)
        #expect(try await runtime.readExpenses(accountId: context.accountId, projectId: project).unfinishedEdits.isEmpty)
        await #expect(throws: ExpenseEntryRecoveryFailure.staleEntry) {
            try await runtime.saveExpenseEntry(recovery, replacing: recovery)
        }
        #expect(accepted.localState == .queued)
        #expect(try await runtime.editExpense(entry, expectedRevision: 1, operationUUID: uuid, capturedAt: time) == accepted)
        let snapshot = try await runtime.readExpenses(accountId: context.accountId, projectId: project)
        #expect(snapshot.expenses[0].entry.vendor == "Original")
        #expect(snapshot.expenses[0].entry.finalAmount.minorUnits == 100)
        #expect(snapshot.pendingCreations.isEmpty)
        #expect(snapshot.pendingEdits.count == 1)
        #expect(snapshot.pendingEdits[0].entry == entry)
        #expect(snapshot.pendingEdits[0].expectedRevision == 1)
        // Projection-only simulation: an applied receipt does not replace downloaded facts.
        _ = try await database.execute(sql: "UPDATE spike_local_operations SET local_state='applied' WHERE id=?", parameters: [accepted.operationId.rawValue])
        #expect(try await runtime.readExpenses(accountId: context.accountId, projectId: project).pendingEdits.count == 1)
        _ = try await database.execute(sql: "UPDATE expenses SET revision='2',vendor='Edited',final_amount_minor_units='200' WHERE id='expense'", parameters: nil)
        #expect(try await runtime.readExpenses(accountId: context.accountId, projectId: project).pendingEdits.isEmpty)
        // A newer downloaded revision does not erase a rejected user's proposal.
        _ = try await database.execute(sql: "UPDATE spike_local_operations SET local_state='rejected' WHERE id=?", parameters: [accepted.operationId.rawValue])
        let rejected = try await runtime.readExpenses(accountId: context.accountId, projectId: project)
        #expect(rejected.pendingEdits.count == 1 && rejected.pendingEdits[0].state == .rejected)
        #expect(rejected.pendingEdits[0].entry == entry)
        let receiptId = try AttachmentID(validating: "expense-edit-new-receipt")
        let receiptBytes = Data("%PDF-1.4\nExpense edit retained receipt\n%%EOF\n".utf8)
        let captured = try LocalAttachmentCapture(attachmentId: receiptId,
            scope: await runtime.expenseAttachmentCaptureScope(projectId: project, expenseId: entry.expenseId),
            capturedAt: .init(validating: 1_789_459_200_000), bytes: receiptBytes,
            metadata: .init(mediaType: "application/pdf", fileName: "Expense edit.pdf"))
        let laterRecovery = ExpenseEntryRecovery(accountId: context.accountId, projectId: project,
            expenseId: entry.expenseId, operationUUID: UUID(), capturedAt: time,
            vendor: "Unsubmitted later edit", date: time, amountText: "2.00", notes: "Keep this draft",
            categoryId: entry.categoryId, lines: [], attachmentIds: [receiptId],
            editContext: try .init(expectedRevision: 2, retainedAttachmentIds: []))
        // A new edit may replace the recovery already consumed by an accepted
        // command, but must not overwrite another still-unsubmitted draft.
        try await runtime.saveExpenseEntry(laterRecovery)
        var conflictingRecovery = laterRecovery
        conflictingRecovery.notes = "Stale second form"
        await #expect(throws: ExpenseEntryRecoveryFailure.staleEntry) {
            try await runtime.saveExpenseEntry(conflictingRecovery)
        }
        let withReceipt = try BusinessPaidExpenseDraft(accountId: entry.accountId, projectId: entry.projectId,
            expenseId: entry.expenseId, vendor: entry.vendor, date: entry.date, finalAmount: entry.finalAmount,
            categoryId: entry.categoryId, notes: entry.notes, receiptAttachmentIds: [receiptId])
        await #expect(throws: AttachmentLocalByteResolutionFailure.receiptNotFound) {
            try await runtime.editExpense(withReceipt, expectedRevision: 2, operationUUID: UUID(), capturedAt: time)
        }
        _ = try await runtime.captureAttachment(captured)
        try await runtime.close()
        runtime = try await context.openRuntime(dependencies: reopening)
        database = try #require(databases.values.last)
        let restoredCaptures = try await runtime.restoreExpenseEntryCaptures(laterRecovery)
        #expect(restoredCaptures.count == 1)
        #expect(restoredCaptures.first?.bytes == receiptBytes)
        #expect(restoredCaptures.first?.scope == captured.scope)
        _ = try await database.execute(sql: "UPDATE expenses SET revision='3',vendor='Remote change' WHERE id='expense'", parameters: nil)
        #expect(try await runtime.readExpenses(accountId: context.accountId, projectId: project).unfinishedEdits == [laterRecovery])
        #expect(try await runtime.pendingWorkSummary().unfinishedEntryCount == 1)
        await #expect(throws: ExpenseEntryRecoveryFailure.staleEntry) {
            try await runtime.saveExpenseEntry(laterRecovery, replacing: laterRecovery)
        }
        #expect(try await runtime.restoreExpenseEntryCaptures(laterRecovery).first?.bytes == receiptBytes)
        let receiptEditUUID = UUID()
        let receiptEdit = try await runtime.editExpense(withReceipt, expectedRevision: 3,
            operationUUID: receiptEditUUID, capturedAt: time)
        #expect(receiptEdit.localState == .queued)
        #expect(try await runtime.editExpense(withReceipt, expectedRevision: 3,
            operationUUID: receiptEditUUID, capturedAt: time) == receiptEdit)
        _ = try await database.execute(sql: "UPDATE spike_account_memberships SET financial_access='none'", parameters: nil)
        await #expect(throws: ProjectInvoicingItemLocalReader.Failure.unavailable) {
            try await runtime.editExpense(entry, expectedRevision: 1, operationUUID: uuid, capturedAt: time)
        }
        try await runtime.close()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            try await runtime.editExpense(entry, expectedRevision: 1, operationUUID: uuid, capturedAt: time)
        }
    }

    @Test("Expense public save refuses receipt IDs without local bytes")
    func expenseMissingReceiptCannotQueue() async throws {
        let context = try RuntimeTestContext(suffix: "expense-missing-receipt")
        defer { context.remove() }
        let runtime = try await context.openRuntime(dependencies: physicalItemDependencies(context))
        let draft = try BusinessPaidExpenseDraft(accountId: context.accountId,
            projectId: .init(validating: "project-physical"), expenseId: .init(validating: "expense-missing"),
            vendor: "Vendor", date: "2026-09-15", finalAmount: .init(minorUnits: 100, currency: .init(validating: "USD")),
            categoryId: .init(validating: "category"), notes: "",
            receiptAttachmentIds: [.init(validating: "receipt-not-captured")])
        await #expect(throws: AttachmentLocalByteResolutionFailure.receiptNotFound) {
            try await runtime.createExpense(draft, operationUUID: UUID(), capturedAt: Date())
        }
        #expect(try await runtime.pendingWorkSummary().queuedOperationCount == 0)
        try await runtime.close()
    }

    private func physicalItemDependencies(_ context: RuntimeTestContext) -> LedgerPowerSyncLocalBootstrapDependencies {
        var dependencies = context.dependencies()
        let validate = dependencies.validateStructuredDatabase
        dependencies.validateStructuredDatabase = { database in
            try await validate(database)
            for sql in [
                "INSERT INTO spike_account_memberships(id,account_id,principal_id,state) VALUES('physical-member','account-runtime','principal-runtime','active')",
                "INSERT INTO spike_projects(id,account_id) VALUES('project-physical','account-runtime')",
                "INSERT INTO spike_items(id,account_id,description,revision) VALUES('physical-chair','account-runtime','Chair',3)",
                "INSERT INTO spike_item_placements(id,account_id,item_id,scope_kind,project_id,started_at) VALUES('physical-placement','account-runtime','physical-chair','project','project-physical','2026-09-01')"
            ] { _ = try await database.execute(sql: sql, parameters: nil) }
        }
        return dependencies
    }

    @Test("WORKRUNTIME-TEST-001 exact composition returns clean and all pending classes")
    func exactCompositionAndPendingClasses() async throws {
        let cleanContext = try RuntimeTestContext(suffix: "clean")
        let cleanRecorder = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        let cleanRuntime = try await cleanContext.openRuntime(events: cleanRecorder)
        let clean = try await cleanRuntime.pendingWorkSummary()
        #expect(clean.environment == .targetLocal)
        #expect(clean.principalId == cleanContext.principalId)
        #expect(clean.accountId == cleanContext.accountId)
        #expect(clean.queuedOperationCount == 0)
        #expect(clean.applyingOperationCount == 0)
        #expect(clean.unresolvedRejectedOperationCount == 0)
        #expect(clean.unverifiedAttachmentCount == 0)
        Self.expectExactConstructionCounts(cleanRecorder.values)
        try await cleanRuntime.close()
        cleanContext.remove()

        let context = try RuntimeTestContext(suffix: "all-classes")
        let recorder = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        var dependencies = context.dependencies(events: recorder)
        let validate = dependencies.validateStructuredDatabase
        dependencies.validateStructuredDatabase = { database in
            try await validate(database)
            try await Self.insertOperation(database, id: "operation-applying", state: .applying)
            try await Self.insertOperation(database, id: "operation-rejected", state: .rejected)
        }
        let runtime = try await context.openRuntime(
            dependencies: dependencies
        )
        _ = try await runtime.createClient(context.clientCommand(id: "queued"))
        let capture = try context.capture(id: "attachment-all-classes")
        let receipt = try await runtime.captureAttachment(capture)
        #expect(receipt.attachmentId == capture.attachmentId)

        let summary = try await runtime.pendingWorkSummary()
        #expect(summary.queuedOperationCount == 1)
        #expect(summary.applyingOperationCount == 1)
        #expect(summary.unresolvedRejectedOperationCount == 1)
        #expect(summary.unverifiedAttachmentCount == 1)
        Self.expectExactConstructionCounts(recorder.values)
        try await runtime.close()
        context.remove()
    }

    @Test("Transaction capture uses live member/financial scope and survives encrypted runtime reopen",
        arguments: ["allowed", "foreign-account", "foreign-principal", "removed", "hidden-fee", "unknown-section"])
    func transactionCaptureAdmission(scenario: String) async throws {
        let context = try RuntimeTestContext(suffix: "transaction-capture-\(scenario)")
        defer { context.remove() }
        let databases = LockedRecorder<any PowerSyncDatabaseProtocol>()
        var dependencies = context.dependencies()
        let clock = LockedRecorder<Date>()
        let startedAt = Date(timeIntervalSince1970: 1_788_600_000)
        clock.append(startedAt)
        dependencies.now = { clock.values.last! }
        let validate = dependencies.validateStructuredDatabase
        dependencies.validateStructuredDatabase = { database in
            try await validate(database)
            databases.append(database)
            _ = try await database.execute(sql: """
                INSERT INTO spike_account_memberships(id,account_id,principal_id,state,financial_access)
                VALUES('capture-member',?,?,?,?)
                """, parameters: [context.accountId.rawValue, context.principalId.rawValue,
                    scenario == "removed" ? "removed" : "active", scenario == "hidden-fee" ? "restricted" : "full"])
            _ = try await database.execute(sql: """
                INSERT INTO spike_budget_categories(id,account_id,display_name,kind,lifecycle,is_system,
                    excludes_from_overall_budget,presentation_order,revision)
                VALUES('capture-category',?,'Capture',?,'active',0,0,0,1)
                """, parameters: [context.accountId.rawValue, scenario == "hidden-fee" ? "fee" : "general"])
            _ = try await database.execute(sql: """
                INSERT INTO spike_transactions(id,account_id,scope_kind,origin,type,role,amount_minor_units,currency,category_id,
                    non_item_receipt_lines,has_email_receipt)
                VALUES('capture-parent',?,'business_inventory','vendor_payment','purchase','standalone','100','USD','capture-category','[]',0)
                """, parameters: [context.accountId.rawValue])
            let identity = TransactionReceiptStreamIdentity(scope: .businessInventory(accountId: context.accountId))
            _ = try await database.syncStream(name: identity.name, params: identity.parameters).subscribe()
            // Seed service acknowledgment/completion, as existing watch tests do.
            // Let the SDK own canonical
            // parameter encoding and registration identity, as the live watch does.
            _ = try await database.execute(sql: "UPDATE ps_stream_subscriptions SET active=1,last_synced_at=1000000 WHERE stream_name='transaction_receipts'", parameters: nil)
            if scenario != "unknown-section" {
                _ = try await database.execute(sql: """
                    INSERT INTO transaction_attachment_sets(id,account_id,transaction_id,section,revision,expected_count)
                    VALUES('capture-set',?,'capture-parent','receipts','1',0)
                    """, parameters: [context.accountId.rawValue])
            }
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let original = try context.capture(id: "z-first-transaction-image")
        let capture = try LocalAttachmentCapture(attachmentId: original.attachmentId,
            scope: AttachmentCaptureScope(environment: original.scope.environment,
                principalId: scenario == "foreign-principal" ? PrincipalID(validating: "foreign") : original.scope.principalId,
                accountId: scenario == "foreign-account" ? AccountID(validating: "foreign") : original.scope.accountId,
                parent: .init(kind: .transaction, id: EntityID(validating: "capture-parent"))),
            capturedAt: original.capturedAt, bytes: original.bytes,
            metadata: AttachmentCaptureMetadata(mediaType: "image/png", fileName: "Original.png", transactionSection: .receipts))
        let scope = TransactionScope.businessInventory(accountId: context.accountId)
        if scenario == "allowed" {
            let observations = LockedRecorder<DownloadedTransactionAttachments?>()
            let transactionId = try TransactionID(validating: "capture-parent")
            #expect(try await runtime.transactionAttachmentCaptureScope(scope: scope,
                transactionId: transactionId) == capture.scope)
            let stream = runtime.watchDownloadedTransactionAttachments(scope: scope,
                transactionId: transactionId, section: .receipts)
            let consumer = Task {
                do { for try await value in stream { observations.append(value) } }
                catch is CancellationError { }
                catch LedgerOfflineClientRuntimeFailure.runtimeClosed { }
            }
            for _ in 0..<1000 {
                if observations.values.contains(where: { $0?.isComplete == true }) { break }
                try await Task.sleep(for: .milliseconds(2))
            }
            #expect(observations.values.contains(where: { $0?.isComplete == true && $0?.attachments.isEmpty == true }))
            let receipt = try await runtime.captureTransactionAttachment(capture, scope: scope)
            #expect(receipt.metadata?.mediaType == capture.metadata?.mediaType)
            #expect(receipt.metadata?.fileName == capture.metadata?.fileName)
            #expect(receipt.metadata?.placement == .init(localPosition: 0, makePrimaryIfEmpty: true))
            for _ in 0..<1000 {
                if observations.values.last??.attachments.first?.localReceipt == receipt { break }
                try await Task.sleep(for: .milliseconds(2))
            }
            #expect(observations.values.last??.attachments.first?.localReceipt == receipt)
            // Equal capture timestamps and reverse lexical IDs must not reorder
            // sequential picker selections or assign two primary attachments.
            let secondCapture = try LocalAttachmentCapture(
                attachmentId: AttachmentID(validating: "a-second-transaction-image"), scope: capture.scope,
                capturedAt: capture.capturedAt, bytes: Data("second original".utf8),
                metadata: AttachmentCaptureMetadata(mediaType: "image/png", fileName: "Second.png", transactionSection: .receipts))
            let secondReceipt = try await runtime.captureTransactionAttachment(secondCapture, scope: scope)
            #expect(secondReceipt.metadata?.placement == .init(localPosition: 1, makePrimaryIfEmpty: false))
            for _ in 0..<1000 {
                if observations.values.last??.attachments.count == 2 { break }
                try await Task.sleep(for: .milliseconds(2))
            }
            #expect(observations.values.last??.attachments.map(\.id.rawValue)
                == [capture.attachmentId.rawValue, secondCapture.attachmentId.rawValue])
            let catalog = try await runtime.readDownloadedTransactionAttachments(scope: scope,
                transactionId: transactionId, section: .receipts)
            #expect(catalog.attachments.map(\.isPrimary) == [true, false])
            let pending = try #require(catalog.attachments.first)
            #expect(pending.fileName == "Original.png" && pending.localReceipt == receipt)
            #expect(try await runtime.loadDownloadedTransactionAttachment(catalog: catalog,
                attachment: pending, allowDownload: false) == capture.bytes)
            let database = try #require(databases.values.first)
            _ = try await database.execute(sql: "UPDATE spike_account_memberships SET state='removed'", parameters: nil)
            for _ in 0..<1000 {
                if let last = observations.values.last, last == nil { break }
                try await Task.sleep(for: .milliseconds(2))
            }
            #expect(observations.values.last != nil && observations.values.last! == nil)
            await #expect(throws: CategoryManagementFailure.categoryUnavailable) {
                try await runtime.loadDownloadedTransactionAttachment(catalog: catalog, attachment: pending, allowDownload: false)
            }
            let upload = try SupabaseTransactionAttachmentUpload(
                supabaseURL: URL(string: "http://127.0.0.1:54321")!, publishableKey: "sb_publishable_test",
                accessToken: {
                    Issue.record("Removed member must not request upload credentials or reach the network")
                    throw CancellationError()
                })
            await #expect(throws: CategoryManagementFailure.categoryUnavailable) {
                try await runtime.publishTransactionAttachment(receipt, scope: scope, using: upload)
            }
            _ = try await database.execute(sql: "UPDATE spike_account_memberships SET state='active'", parameters: nil)
            #expect(try await runtime.pendingWorkSummary().unverifiedAttachmentCount == 2)
            let uploadAttempts = LockedRecorder<String>()
            let failingUpload = try SupabaseTransactionAttachmentUpload(
                supabaseURL: URL(string: "http://127.0.0.1:54321")!, publishableKey: "sb_publishable_test",
                accessToken: {
                    uploadAttempts.append("attempt")
                    throw CancellationError() // Exercise retry retention without making an HTTP request.
                })
            await runtime.lifecycleOwner.uploadPendingTransactionAttachments(using: failingUpload)
            #expect(uploadAttempts.values.count == 2)
            clock.append(startedAt.addingTimeInterval(29))
            await runtime.lifecycleOwner.uploadPendingTransactionAttachments(using: failingUpload)
            #expect(uploadAttempts.values.count == 2) // Events during cooldown cannot retry.
            clock.append(startedAt.addingTimeInterval(30))
            await runtime.lifecycleOwner.uploadPendingTransactionAttachments(using: failingUpload)
            #expect(uploadAttempts.values.count == 4) // Exactly due; no real thirty-second test sleep.
            clock.append(startedAt.addingTimeInterval(60))
            try await runtime.lifecycleOwner.startTransactionAttachmentUploads(using: failingUpload)
            try await runtime.lifecycleOwner.startTransactionAttachmentUploads(using: failingUpload)
            for _ in 0..<1000 {
                if uploadAttempts.values.count >= 6 { break }
                try await Task.sleep(for: .milliseconds(2))
            }
            #expect(uploadAttempts.values.count == 6) // Both files attempted, duplicate start/events coalesced.
            try await runtime.close()
            #expect(uploadAttempts.values.count == 6)
            try await consumer.value
            let reopened = try await context.openRuntime()
            #expect(try await reopened.resolveLocalAttachmentBytes(for: receipt) == capture.bytes)
            let reopenedCatalog = try await reopened.readDownloadedTransactionAttachments(scope: scope,
                transactionId: transactionId, section: .receipts)
            let reopenedPending = try #require(reopenedCatalog.attachments.first)
            #expect(reopenedCatalog.attachments.map(\.id.rawValue)
                == [capture.attachmentId.rawValue, secondCapture.attachmentId.rawValue])
            #expect(reopenedCatalog.attachments.map(\.isPrimary) == [true, false])
            let reopenedSecond = try #require(reopenedCatalog.attachments.last)
            #expect(reopenedSecond.localReceipt == secondReceipt)
            #expect(try await reopened.loadDownloadedTransactionAttachment(catalog: reopenedCatalog,
                attachment: reopenedSecond, allowDownload: false) == secondCapture.bytes)
            #expect(reopenedPending.localReceipt == receipt)
            #expect(try await reopened.loadDownloadedTransactionAttachment(catalog: reopenedCatalog,
                attachment: reopenedPending, allowDownload: false) == capture.bytes)
            #expect(try await reopened.captureTransactionAttachment(capture, scope: scope) == receipt)
            #expect(try await reopened.captureTransactionAttachment(secondCapture, scope: scope) == secondReceipt)
            #expect(try await reopened.pendingWorkSummary().unverifiedAttachmentCount == 2)
            try await reopened.close()
        } else {
            do {
                _ = try await runtime.captureTransactionAttachment(capture, scope: scope)
                Issue.record("Expected capture refusal for \(scenario)")
            } catch {
                switch scenario {
                case "foreign-account", "foreign-principal":
                    #expect(error as? AttachmentCapturePowerSyncStoreFailure == .scopeMismatch)
                case "removed": #expect(error as? CategoryManagementFailure == .categoryUnavailable)
                case "hidden-fee": #expect(error as? DownloadedTransactionAttachments.Failure == .unavailable)
                case "unknown-section": #expect(error as? TransactionAttachmentCaptureFailure == .unavailable)
                default: Issue.record("Unexpected scenario \(scenario)")
                }
            }
            #expect(try await runtime.pendingWorkSummary().unverifiedAttachmentCount == 0)
            try await runtime.close()
        }
    }

    @Test("WORKRUNTIME-TEST-002 invalid scope and equal keys refuse before storage")
    func invalidScopeAndEqualKeysRefuseBeforeStorage() async throws {
        let invalid = try RuntimeTestContext(suffix: "invalid-scope", namespace: "../escape")
        let invalidRecorder = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        do {
            _ = try await invalid.openRuntime(events: invalidRecorder)
            Issue.record("Expected invalid namespace failure")
        } catch let failure as LedgerPowerSyncLocalBootstrapFailure {
            #expect(failure.stage == .workspaceLocationResolution)
            #expect(failure.attachmentDatabaseCleanup == .notOpened)
            #expect(failure.structuredDatabaseCleanup == .notOpened)
        }
        #expect(invalidRecorder.values.isEmpty)

        let equal = try RuntimeTestContext(suffix: "equal-keys")
        let equalRecorder = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        var dependencies = equal.dependencies(events: equalRecorder)
        dependencies.loadMediaKeyBytes = { _, _ in Data(repeating: 0x1a, count: 32) }
        do {
            _ = try await equal.openRuntime(dependencies: dependencies)
            Issue.record("Expected equal key values to refuse bootstrap")
        } catch let failure as LedgerPowerSyncLocalBootstrapFailure {
            #expect(failure.stage == .keyValidation)
            #expect(failure.attachmentDatabaseCleanup == .notOpened)
            #expect(failure.structuredDatabaseCleanup == .notOpened)
        }
        #expect(!FileManager.default.fileExists(atPath: equal.root.path))

        let scoped = try RuntimeTestContext(suffix: "cross-scope")
        let scopedRuntime = try await scoped.openRuntime()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.accountScopeMismatch) {
            _ = try await scopedRuntime.createClient(
                scoped.clientCommand(
                    id: "wrong-account",
                    accountId: AccountID(validating: "account-other")
                )
            )
        }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.principalScopeMismatch) {
            _ = try await scopedRuntime.createProject(
                scoped.projectCommand(
                    id: "wrong-principal",
                    principalId: PrincipalID(validating: "principal-other")
                )
            )
        }
        await #expect(throws: AttachmentCapturePowerSyncStoreFailure.scopeMismatch) {
            _ = try await scopedRuntime.captureAttachment(
                scoped.capture(
                    id: "attachment-cross-scope",
                    accountId: AccountID(validating: "account-other")
                )
            )
        }
        let scopedSummary = try await scopedRuntime.pendingWorkSummary()
        #expect(scopedSummary.unverifiedAttachmentCount == 0)
        try await scopedRuntime.close()
        scoped.remove()
    }

    @Test("WORKRUNTIME-TEST-003 paths and keys isolate while database key bytes match")
    func locationsAndKeySeparation() async throws {
        let context = try RuntimeTestContext(suffix: "key-capture")
        let keyRecorder = LockedRecorder<String>()
        var dependencies = context.dependencies()
        let openStructured = dependencies.openStructuredDatabase
        let openAttachment = dependencies.openAttachmentDatabase
        dependencies.openStructuredDatabase = { path, key in
            keyRecorder.append(
                "structured:\(key.hexadecimal):\(URL(fileURLWithPath: path).lastPathComponent)")
            return try openStructured(path, key)
        }
        dependencies.openAttachmentDatabase = { path, key in
            keyRecorder.append(
                "attachment:\(key.hexadecimal):\(URL(fileURLWithPath: path).lastPathComponent)")
            return try openAttachment(path, key)
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        #expect(
            keyRecorder.values == [
                "structured:\(context.databaseKey.hexadecimal):ledger.sqlite",
                "attachment:\(context.databaseKey.hexadecimal):attachments.sqlite",
            ])

        let location = try context.location()
        #expect(
            location.structuredDatabaseURL.deletingLastPathComponent()
                == location.attachmentDatabaseURL.deletingLastPathComponent())
        #expect(
            location.mediaVaultRootURL.deletingLastPathComponent()
                == location.structuredDatabaseURL.deletingLastPathComponent())
        #expect(location.databaseKeychainService == "ledger.target.powersync.workspace-key.v1")
        #expect(location.databaseKeychainService != location.mediaKeychainService)
        #expect(!location.structuredDatabaseURL.path.contains(context.principalId.rawValue))
        #expect(!location.structuredDatabaseURL.path.contains(context.accountId.rawValue))
        try await runtime.close()

        let otherPrincipal = try context.location(
            principalId: PrincipalID(validating: "principal-other")
        )
        let otherAccount = try context.location(accountId: AccountID(validating: "account-other"))
        #expect(otherPrincipal.structuredDatabaseURL != location.structuredDatabaseURL)
        #expect(otherPrincipal.attachmentDatabaseURL != location.attachmentDatabaseURL)
        #expect(otherPrincipal.mediaVaultRootURL != location.mediaVaultRootURL)
        #expect(otherAccount.structuredDatabaseURL != location.structuredDatabaseURL)
        #expect(otherAccount.databaseKeychainAccount != location.databaseKeychainAccount)
        #expect(otherAccount.mediaKeychainAccount != location.mediaKeychainAccount)
        context.remove()
    }

    @Test("WORKRUNTIME-TEST-004 close and reopen preserve summary, receipt, and evidence revision")
    func closeReopenAndEqualCountReplacement() async throws {
        let context = try RuntimeTestContext(suffix: "restart")
        let first = try await context.openRuntime()
        _ = try await first.createClient(context.clientCommand(id: "restart-a"))
        let capture = try context.capture(id: "attachment-restart")
        let receipt = try await first.captureAttachment(capture)
        let initial = try await first.pendingWorkSummary()
        try await first.close()

        let reopened = try await context.openRuntime()
        let replayed = try await reopened.captureAttachment(capture)
        let unchanged = try await reopened.pendingWorkSummary()
        #expect(replayed == receipt)
        #expect(unchanged == initial)
        try await reopened.close()

        var changedDependencies = context.dependencies()
        let validate = changedDependencies.validateStructuredDatabase
        changedDependencies.validateStructuredDatabase = { database in
            try await validate(database)
            _ = try await database.execute(
                sql: "DELETE FROM \(LedgerPowerSyncTable.localOperations) WHERE id = ?",
                parameters: ["operation-runtime-restart-a"]
            )
            try await Self.insertOperation(
                database,
                id: "operation-replacement",
                state: .queued,
                timestamp: 9
            )
        }
        let changedRuntime = try await context.openRuntime(dependencies: changedDependencies)
        let changed = try await changedRuntime.pendingWorkSummary()
        #expect(changed.queuedOperationCount == initial.queuedOperationCount)
        #expect(changed.unverifiedAttachmentCount == initial.unverifiedAttachmentCount)
        #expect(changed.snapshotRevision == initial.snapshotRevision + 1)
        #expect(changed.fingerprint != initial.fingerprint)
        try await changedRuntime.close()
        context.remove()
    }

    @Test("Historical Invoicing downloads both sale cycles and survives offline restart",
          .enabled(if: ProcessInfo.processInfo.environment["LEDGER_SALE_LOCAL_ACCOUNT"] != nil), .timeLimit(.minutes(1)))
    func invoicingHistoricalLiveReplication() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let account = env["LEDGER_SALE_LOCAL_ACCOUNT"], account.hasPrefix("sale-http-"),
              let principal = env["LEDGER_SALE_LOCAL_PRINCIPAL"], let source = env["LEDGER_SALE_LOCAL_PROJECT"],
              let destination = env["LEDGER_SALE_LOCAL_DESTINATION_PROJECT"], let item = env["LEDGER_SALE_LOCAL_ITEM"],
              let key = env["LEDGER_SALE_LOCAL_KEY"], let email = env["LEDGER_SALE_LOCAL_EMAIL"],
              let password = env["LEDGER_SALE_LOCAL_PASSWORD"], env["LEDGER_SALE_LOCAL_FINANCIAL_ACCESS"] == "full" else { throw RuntimeInjectedFailure() }
        let context = try RuntimeTestContext(suffix: "invoicing-live", accountId: .init(validating: account), principalId: .init(validating: principal))
        defer { context.remove() }
        let url = URL(string: "http://127.0.0.1:54321")!
        let auth = AuthClient(configuration: .init(url: url.appendingPathComponent("auth/v1"), headers: ["apikey": key],
            storageKey: "invoicing-live", localStorage: CategoryAuthTestStorage(), fetch: { try await URLSession.shared.data(for: $0) },
            autoRefreshToken: false, emitLocalSessionAsInitialSession: true))
        let entry = await SupabaseOnlineSignIn(client: auth, supabaseURL: url, publishableKey: key)
        try await entry.signIn(email: email, password: password)
        let directory = try await entry.accounts(environment: context.environment.manifest.environment)
        let authorization = try await entry.authorize(AccountSelectionPolicy.makeIntent(selecting: context.accountId,
            from: directory.snapshot, requestedAt: Date()))
        let runtime = try await context.openRuntime()
        try await entry.startWorkspaceSync(runtime, authorization: authorization, powerSyncURL: URL(string: "http://127.0.0.1:5590")!)
        for try await snapshot in runtime.watchProjects() {
            if Set(snapshot.local.rows.map { $0.id.rawValue }).isSuperset(of: [source, destination]) { break }
        }
        var originals: [ProjectInvoicingItems] = []
        for (project, expected, amount) in [(source, InvoicingAvailability.paid, Int64(900)), (destination, .available, Int64(200))] {
            var found = false
            let projectId = try ProjectID(validating: project)
            for try await snapshot in runtime.watchInvoicingCharges(accountId: context.accountId, projectId: projectId) {
                guard let snapshot, let row = snapshot.rows.first(where: { $0.occurrence.itemId.rawValue == item }) else { continue }
                #expect(row.amount.minorUnits == amount && row.availability == expected)
                originals.append(snapshot); found = true; break
            }
            #expect(found)
        }
        try await runtime.close()
        let offline = try await context.openRuntime()
        for original in originals {
            #expect(try await offline.readInvoicingCharges(accountId: context.accountId, projectId: original.projectId) == original)
        }
        #expect(originals.count == 2)
        try await offline.close()
    }

    @Test("Expense offline commands converge through actual Auth, RPC and PowerSync",
          .enabled(if: ProcessInfo.processInfo.environment["LEDGER_SALE_LOCAL_ACCOUNT"] != nil), .timeLimit(.minutes(1)))
    func expenseLiveReplication() async throws {
        let env = ProcessInfo.processInfo.environment
        func liveStage(_ value: String) {
            if env["LEDGER_LIVE_INVOICE_LOCAL"] == "1" {
                FileHandle.standardError.write(Data("Live Invoice integration: \(value)\n".utf8))
            }
        }
        let hostedQA = env["LEDGER_EXPENSE_HOSTED_QA"] == "1"
        guard let account = env["LEDGER_SALE_LOCAL_ACCOUNT"],
              let principal = env["LEDGER_SALE_LOCAL_PRINCIPAL"],
              let expense = env["LEDGER_SALE_LOCAL_ITEM"],
              let project = env["LEDGER_SALE_LOCAL_PROJECT"],
              let key = env["LEDGER_SALE_LOCAL_KEY"], let email = env["LEDGER_SALE_LOCAL_EMAIL"],
              let password = env["LEDGER_SALE_LOCAL_PASSWORD"] else { throw RuntimeInjectedFailure() }
        if hostedQA {
            guard account == "realcopy-b9d236394770-account",
                  principal == "upload-http-owner-4b1e9766-5791-48a9-a7b1-15a541807e64",
                  expense.hasPrefix("hosted-expense-flow-"), project.hasPrefix("hosted-expense-flow-"),
                  email.hasSuffix("@ledger-tests.invalid") else { throw RuntimeInjectedFailure() }
        } else {
            guard [account, principal, expense, project].allSatisfy({ $0.hasPrefix("sale-http-") }) else {
                throw RuntimeInjectedFailure()
            }
        }
        let context = try RuntimeTestContext(suffix: "expense-live", accountId: .init(validating: account), principalId: .init(validating: principal))
        defer { context.remove() }
        let url = URL(string: hostedQA ? "https://ybwviepljilrkrjoahbl.supabase.co" : "http://127.0.0.1:54321")!
        let sync = URL(string: hostedQA ? "https://6aa8966802481fb31b96942c.powersync.journeyapps.com" : "http://127.0.0.1:5590")!
        let auth = AuthClient(configuration: .init(url: url.appendingPathComponent("auth/v1"), headers: ["apikey": key],
            storageKey: "expense-live", localStorage: CategoryAuthTestStorage(), fetch: { try await URLSession.shared.data(for: $0) },
            autoRefreshToken: false, emitLocalSessionAsInitialSession: true))
        let entry = await SupabaseOnlineSignIn(client: auth, supabaseURL: url, publishableKey: key)
        try await entry.signIn(email: email, password: password)
        let directory = try await entry.accounts(environment: context.environment.manifest.environment)
        let authorization = try await entry.authorize(AccountSelectionPolicy.makeIntent(selecting: context.accountId,
            from: directory.snapshot, requestedAt: Date()))
        let first = try await context.openRuntime(), projectId = try ProjectID(validating: project)
        try await entry.startWorkspaceSync(first, authorization: authorization, powerSyncURL: sync)
        liveStage("sync started")
        for try await value in first.watchProjects() { if value.local.rows.contains(where: { $0.id == projectId }) { break } }
        liveStage("Project downloaded")
        var original: BusinessPaidExpenseDraft?
        for try await value in first.watchExpenses(accountId: context.accountId, projectId: projectId) {
            if let row = value?.expenses.first(where: { $0.id.rawValue == expense }) {
                if env["LEDGER_EXPENSE_LOCAL_PAID"] == "1" {
                    let paid = try #require(row.collectedInvoice)
                    #expect(paid.total.minorUnits == (hostedQA ? 12_345 : Int64.max))
                    #expect(paid.lines[0].description == "Frozen Expense description")
                    #expect(paid.displayMetadata?.invoiceNumber == "INV-LIVE-001")
                    #expect(paid.displayMetadata?.notes == "Original Invoice notes")
                    #expect(paid.displayMetadata?.paidAtMilliseconds == "-1")
                }
                original = row.entry; break
            }
        }
        let source = try #require(original)
        liveStage("Expense downloaded")
        #expect(source.finalAmount.minorUnits == (hostedQA ? 12_345 : Int64.max))
        #expect(source.receiptLines.count == 1)
        if env["LEDGER_FEE_LOCAL_CREATE"] == "1" {
            guard !hostedQA, let category = env["LEDGER_FEE_LOCAL_CATEGORY"] else { throw RuntimeInjectedFailure() }
            for try await invoices in first.watchLiveInvoices(accountId: context.accountId, projectId: projectId) {
                if invoices != nil { break }
            }
            let draft = try FeeInstallmentDraft(accountId: context.accountId, projectId: projectId,
                installmentId: .init(validating: expense + "-fee"), categoryId: .init(validating: category),
                label: "Design fee", amount: .init(minorUnits: 12345, currency: .init(validating: "USD")))
            let operationUUID = UUID(), capturedAt = Date()
            try await first.close()
            let disconnected = try await context.openRuntime()
            let receipt = try await disconnected.createFeeInstallment(draft, operationUUID: operationUUID, capturedAt: capturedAt)
            #expect(receipt.localState == .queued)
            try await disconnected.close()
            let online = try await context.openRuntime()
            #expect(try await online.createFeeInstallment(draft, operationUUID: operationUUID, capturedAt: capturedAt) == receipt)
            try await entry.startWorkspaceSync(online, authorization: authorization, powerSyncURL: sync)
            var found = false
            for try await invoices in online.watchLiveInvoices(accountId: context.accountId, projectId: projectId) {
                guard invoices != nil else { continue }
                let review = try await online.readInvoiceCreationReview(accountId: context.accountId, projectId: projectId)
                if let fee = review.candidates.first(where: { $0.selection.source == .feeInstallment(draft.installmentId) }) {
                    #expect(fee.selection.reviewedAmount == draft.amount)
                    found = true; break
                }
            }
            #expect(found)
            try await online.close()
            let offline = try await context.openRuntime()
            let review = try await offline.readInvoiceCreationReview(accountId: context.accountId, projectId: projectId)
            #expect(review.candidates.contains { $0.selection.source == .feeInstallment(draft.installmentId) && $0.selection.reviewedAmount == draft.amount })
            try await offline.close()
            return
        }
        if env["LEDGER_LIVE_INVOICE_LOCAL"] == "1" {
            guard !hostedQA else { throw RuntimeInjectedFailure() }
            var invoiceRuntime = first
            if env["LEDGER_INVOICE_LOCAL_CREATE"] == "1" {
                for try await invoices in first.watchLiveInvoices(accountId: context.accountId, projectId: projectId) {
                    if invoices != nil { break }
                }
                let review = try await first.readInvoiceCreationReview(accountId: context.accountId, projectId: projectId)
                #expect(review.candidates.count == 1)
                #expect(review.candidates.first?.selection.source == .expense(source.expenseId))
                let payload = try CreateInvoiceCommand.Payload(invoiceId: .init(validating: expense + "-invoice"),
                    selection: .init(scope: review.scope, lines: review.candidates.map(\.selection)),
                    name: "Live sync Invoice", notes: "External delivery")
                let operationUUID = UUID(), capturedAt = Date()
                try await first.close()
                let disconnected = try await context.openRuntime()
                let receipt = try await disconnected.createInvoice(payload, operationUUID: operationUUID, capturedAt: capturedAt)
                #expect(receipt.localState == .queued)
                try await disconnected.close()
                invoiceRuntime = try await context.openRuntime()
                #expect(try await invoiceRuntime.createInvoice(payload, operationUUID: operationUUID, capturedAt: capturedAt) == receipt)
                liveStage("offline creation survived restart")
                try await entry.startWorkspaceSync(invoiceRuntime, authorization: authorization, powerSyncURL: sync)
            }
            var downloaded: [LiveInvoiceContents]?
            for try await invoices in invoiceRuntime.watchLiveInvoices(accountId: context.accountId, projectId: projectId) {
                guard let invoices, !invoices.isEmpty else { continue }
                downloaded = invoices; break
            }
            let expected = try #require(downloaded)
            liveStage("live Invoice downloaded")
            #expect(expected.count == 1)
            #expect(expected[0].total == source.finalAmount)
            #expect(expected[0].lines[0].selection.source == .expense(source.expenseId))
            #expect(expected[0].name == "Live sync Invoice")
            try await invoiceRuntime.close()
            liveStage("first runtime closed")
            let offline = try await context.openRuntime()
            #expect(try await offline.readLiveInvoices(accountId: context.accountId, projectId: projectId) == expected)
            liveStage("offline reopened contents match")
            try await offline.close()
            return
        }
        if env["LEDGER_EXPENSE_HOSTED_WITHDRAWAL"] == "1" {
            guard hostedQA, env["LEDGER_EXPENSE_LOCAL_PAID"] == "1" else { throw RuntimeInjectedFailure() }
            let invoice = try #require(try await first.readCollectedInvoices(accountId: context.accountId,
                projectId: projectId).first)
            _ = try await first.readCollectedInvoiceReport(accountId: context.accountId, projectId: projectId,
                invoiceId: invoice.invoiceId, asOf: .init(validating: 2000))
            FileHandle.standardOutput.write(Data("LEDGER_INVOICE_WITHDRAWAL_READY\n".utf8))
            var withdrawn = false
            do {
                for try await value in first.watchCollectedInvoices(accountId: context.accountId,
                    projectId: projectId, invoiceId: invoice.invoiceId) {
                    if value == nil { withdrawn = true; break }
                }
            } catch ProjectInvoicingItemLocalReader.Failure.unavailable {
                withdrawn = true
            }
            #expect(withdrawn)
            await #expect(throws: ProjectInvoicingItemLocalReader.Failure.unavailable) {
                try await first.readCollectedInvoiceReport(accountId: context.accountId, projectId: projectId,
                    invoiceId: invoice.invoiceId, asOf: .init(validating: 2001))
            }
            try await first.close()
            let reopened = try await context.openRuntime()
            await #expect(throws: ProjectInvoicingItemLocalReader.Failure.unavailable) {
                try await reopened.readCollectedInvoiceReport(accountId: context.accountId, projectId: projectId,
                    invoiceId: invoice.invoiceId, asOf: .init(validating: 2002))
            }
            try await reopened.close()
            return
        }
        try await first.close()
        if env["LEDGER_EXPENSE_LOCAL_EDIT"] == "1" {
            guard env["LEDGER_EXPENSE_LOCAL_PAID"] != "1" else { throw RuntimeInjectedFailure() }
            let offline = try await context.openRuntime()
            var receiptIds = source.receiptAttachmentIds
            var addedReceipt: AttachmentID?
            let mediaBytes = Data("%PDF-1.4\nOffline added Expense receipt\n%%EOF\n".utf8)
            if env["LEDGER_EXPENSE_LOCAL_EDIT_MEDIA"] == "1" {
                let id = try AttachmentID(validating: expense + "-edit-native-receipt")
                let capture = try LocalAttachmentCapture(attachmentId: id,
                    scope: await offline.expenseAttachmentCaptureScope(projectId: projectId, expenseId: source.expenseId),
                    capturedAt: .init(validating: 1_789_459_200_000), bytes: mediaBytes,
                    metadata: .init(mediaType: "application/pdf", fileName: "Added receipt.pdf"))
                _ = try await offline.captureAttachment(capture)
                receiptIds.append(id); addedReceipt = id
            }
            let changed = try BusinessPaidExpenseDraft(accountId: context.accountId, projectId: projectId,
                expenseId: source.expenseId, vendor: "Offline edited vendor", date: source.date,
                finalAmount: source.finalAmount, categoryId: source.categoryId, notes: "Offline edit",
                receiptAttachmentIds: receiptIds, receiptLines: source.receiptLines)
            let uuid = UUID(), capturedAt = Date()
            let receipt = try await offline.editExpense(changed, expectedRevision: 1, operationUUID: uuid, capturedAt: capturedAt)
            #expect(receipt.localState == .queued)
            #expect(try await offline.readExpenses(accountId: context.accountId, projectId: projectId).expenses.first?.entry == source)
            try await offline.close()
            let resumed = try await context.openRuntime()
            #expect(try await resumed.readExpenses(accountId: context.accountId, projectId: projectId).pendingEdits.first?.entry == changed)
            #expect(try await resumed.editExpense(changed, expectedRevision: 1, operationUUID: uuid, capturedAt: capturedAt) == receipt)
            let conflict = env["LEDGER_EXPENSE_LOCAL_EDIT_CONFLICT"] == "1"
            var expected = changed
            if conflict {
                expected = try BusinessPaidExpenseDraft(accountId: context.accountId, projectId: projectId,
                    expenseId: source.expenseId, vendor: "Newer server vendor", date: source.date,
                    finalAmount: source.finalAmount, categoryId: source.categoryId, notes: "Second device edit",
                    receiptAttachmentIds: source.receiptAttachmentIds, receiptLines: source.receiptLines)
                let rpc = try SupabaseWorkspaceCommandRPC(url: url, key: key, authorization: authorization,
                    identity: .init(client: auth, userId: authorization.authUserId))
                let winner = try EditExpenseCommand(operationId: AccountBoundOperationIdentity.make(
                    family: .expenseEdit, accountId: context.accountId, uuid: UUID()),
                    actorPrincipalId: context.principalId, capturedAt: Date(), expectedRevision: 1, entry: expected)
                #expect(try await rpc.apply(winner).phase == "applied")
            }
            try await entry.startWorkspaceSync(resumed, authorization: authorization, powerSyncURL: sync)
            var converged = false
            for try await value in resumed.watchExpenses(accountId: context.accountId, projectId: projectId) {
                if let row = value?.expenses.first(where: { $0.id == source.expenseId }), row.revision == 2,
                   conflict ? value?.pendingEdits.first?.state == .rejected : value?.pendingEdits.isEmpty == true {
                    #expect(row.entry == expected)
                    if conflict { #expect(value?.pendingEdits.first?.entry == changed) }
                    converged = true; break
                }
            }
            #expect(converged)
            if let addedReceipt, !conflict {
                #expect(try await resumed.loadExpenseReceipt(projectId: projectId, expenseId: source.expenseId,
                    attachmentId: addedReceipt, allowDownload: true) == mediaBytes)
            }
            try await resumed.close()
            let verified = try await context.openRuntime()
            let snapshot = try await verified.readExpenses(accountId: context.accountId, projectId: projectId)
            #expect(snapshot.expenses.first?.entry == expected)
            if conflict {
                #expect(snapshot.pendingEdits.first?.entry == changed)
                #expect(snapshot.pendingEdits.first?.state == .rejected)
                #expect(try await verified.pendingWorkSummary().unresolvedRejectedOperationCount == 1)
            } else { #expect(snapshot.pendingEdits.isEmpty) }
            try await verified.close()
            return
        }
        let attachmentId = try AttachmentID(validating: expense + "-offline-receipt")
        let draft = try BusinessPaidExpenseDraft(accountId: context.accountId, projectId: projectId,
            expenseId: .init(validating: expense + "-native"), vendor: source.vendor, date: source.date,
            finalAmount: source.finalAmount, categoryId: source.categoryId, notes: "Offline native creation",
            receiptAttachmentIds: [attachmentId], receiptLines: source.receiptLines)
        let uuid = UUID(), capturedAt = Date(), offline = try await context.openRuntime()
        let bytes = Data("%PDF-1.4\nOffline Expense receipt\n%%EOF\n".utf8)
        let capture = try LocalAttachmentCapture(attachmentId: attachmentId,
            scope: await offline.expenseAttachmentCaptureScope(projectId: projectId, expenseId: draft.expenseId),
            capturedAt: .init(validating: 1_789_459_200_000), bytes: bytes,
            metadata: .init(mediaType: "application/pdf", fileName: "Expense.pdf"))
        let recovery = ExpenseEntryRecovery(accountId: context.accountId, projectId: projectId,
            expenseId: draft.expenseId, operationUUID: uuid, capturedAt: capturedAt,
            vendor: "Unfinished vendor", date: capturedAt, amountText: "", notes: "Still entering",
            categoryId: nil, lines: [], attachmentIds: [attachmentId])
        try await offline.saveExpenseEntry(recovery)
        let beforeCapture = try await offline.pendingWorkSummary()
        #expect(beforeCapture.unfinishedEntryCount == 1)
        #expect(beforeCapture.unverifiedAttachmentCount == 0)
        #expect(beforeCapture.hasBlockingWork)
        let mediaReceipt = try await offline.captureAttachment(capture)
        try await offline.close()
        let recoveryRuntime = try await context.openRuntime()
        let restoredEntries = try await recoveryRuntime.readExpenses(accountId: context.accountId, projectId: projectId).unfinishedEntries
        #expect(restoredEntries == [recovery])
        #expect(try await recoveryRuntime.pendingWorkSummary().unfinishedEntryCount == 1)
        #expect(try await recoveryRuntime.restoreExpenseEntryCaptures(recovery) == [capture])
        var newer = recovery
        newer.notes = "Newer editor's saved details"
        try await recoveryRuntime.saveExpenseEntry(newer, replacing: recovery)
        var stale = recovery
        stale.notes = "Stale editor's details"
        await #expect(throws: ExpenseEntryRecoveryFailure.staleEntry) {
            try await recoveryRuntime.saveExpenseEntry(stale, replacing: recovery)
        }
        await #expect(throws: ExpenseEntryRecoveryFailure.staleEntry) {
            try await recoveryRuntime.createExpense(draft, operationUUID: uuid, capturedAt: capturedAt, recovery: recovery)
        }
        try await recoveryRuntime.close()
        let savingRuntime = try await context.openRuntime()
        let receipt = try await savingRuntime.createExpense(draft, operationUUID: uuid, capturedAt: capturedAt, recovery: newer)
        #expect(receipt.localState == .queued)
        #expect(try await savingRuntime.pendingWorkSummary().unfinishedEntryCount == 0)
        #expect(try await savingRuntime.readExpenses(accountId: context.accountId, projectId: projectId).unfinishedEntries.isEmpty)
        await #expect(throws: ExpenseCreationPowerSyncStore.Failure.duplicateExpense) {
            try await savingRuntime.saveExpenseEntry(recovery)
        }
        try await savingRuntime.close()
        let resumed = try await context.openRuntime()
        #expect(try await resumed.createExpense(draft, operationUUID: uuid, capturedAt: capturedAt).operationId == receipt.operationId)
        #expect(try await resumed.loadExpenseReceipt(projectId: projectId,
            expenseId: draft.expenseId, attachmentId: attachmentId, allowDownload: false) == bytes)
        await #expect(throws: ProjectExpenses.Failure.invalidEvidence) {
            try await resumed.loadExpenseReceipt(projectId: projectId,
                expenseId: source.expenseId, attachmentId: attachmentId, allowDownload: false)
        }
        try await entry.startWorkspaceSync(resumed, authorization: authorization, powerSyncURL: sync)
        var converged: ProjectExpenses?
        for try await value in resumed.watchExpenses(accountId: context.accountId, projectId: projectId) {
            if let row = value?.expenses.first(where: { $0.id == draft.expenseId }),
               row.receiptObjects.map(\.attachmentId) == draft.receiptAttachmentIds {
                #expect(row.entry == draft); converged = value; break
            }
        }
        let expected = try #require(converged)
        #expect(expected.expenses.count == 2)
        if env["LEDGER_EXPENSE_LOCAL_PAID"] == "1" {
            #expect(expected.expenses.first(where: { $0.id == source.expenseId })?.collectedInvoice != nil)
            #expect(expected.expenses.first(where: { $0.id == draft.expenseId })?.collectedInvoice == nil)
            let invoices = try await resumed.readCollectedInvoices(accountId: context.accountId, projectId: projectId)
            #expect(invoices == expected.expenses.compactMap(\.collectedInvoice))
            for try await downloaded in resumed.watchCollectedInvoices(accountId: context.accountId, projectId: projectId) {
                guard let downloaded else { continue }
                #expect(downloaded == invoices)
                break
            }
        }
        await resumed.lifecycleOwner.reconcilePendingExpenseAttachments()
        #expect(try await resumed.pendingWorkSummary().unverifiedAttachmentCount == 0)
        try await resumed.close()
        let reopened = try await context.openRuntime()
        #expect(try await reopened.readExpenses(accountId: context.accountId, projectId: projectId) == expected)
        if env["LEDGER_EXPENSE_LOCAL_PAID"] == "1" {
            let invoice = try #require(expected.expenses.first(where: { $0.id == source.expenseId })?.collectedInvoice)
            // Use the public report boundary after reopening without starting
            // sync, not just the Expense relationship or raw Invoice list.
            let report = try await reopened.readCollectedInvoiceReport(accountId: context.accountId,
                projectId: projectId, invoiceId: invoice.invoiceId,
                asOf: .init(validating: Int64(Date().timeIntervalSince1970 * 1000)))
            #expect(report.invoice == invoice)
            #expect(report.provenance.lastSyncedAt != nil)
            #expect(report.provenance.localDataVersion != nil)
        }
        #expect(try await reopened.loadExpenseReceipt(projectId: projectId,
            expenseId: draft.expenseId, attachmentId: mediaReceipt.attachmentId, allowDownload: false) == bytes)
        #expect(try await reopened.pendingWorkSummary().unverifiedAttachmentCount == 0)
        // Exact retries remain valid after upload reconciliation retires the
        // pending capture; they must not require a second capture or command.
        #expect(try await reopened.createExpense(draft, operationUUID: uuid,
            capturedAt: capturedAt).operationId == receipt.operationId)
        try await reopened.close()
    }

    @Test("Offline sale converges through actual local Auth, RPC and PowerSync",
          .enabled(if: ProcessInfo.processInfo.environment["LEDGER_SALE_LOCAL_ACCOUNT"] != nil), .timeLimit(.minutes(1)))
    func inventorySaleLiveReplication() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let account = env["LEDGER_SALE_LOCAL_ACCOUNT"], account.hasPrefix("sale-http-"),
              let principal = env["LEDGER_SALE_LOCAL_PRINCIPAL"], principal.hasPrefix("sale-http-"),
              let item = env["LEDGER_SALE_LOCAL_ITEM"], item.hasPrefix("sale-http-"),
              let project = env["LEDGER_SALE_LOCAL_PROJECT"], project.hasPrefix("sale-http-"),
              let key = env["LEDGER_SALE_LOCAL_KEY"], let email = env["LEDGER_SALE_LOCAL_EMAIL"],
              let password = env["LEDGER_SALE_LOCAL_PASSWORD"] else { throw RuntimeInjectedFailure() }
        let context = try RuntimeTestContext(suffix: "sale-live",accountId: .init(validating: account),principalId: .init(validating: principal))
        defer { context.remove() }
        let url = URL(string: "http://127.0.0.1:54321")!, sync = URL(string: "http://127.0.0.1:5590")!
        let auth = AuthClient(configuration: .init(url: url.appendingPathComponent("auth/v1"),headers: ["apikey": key],
            storageKey: "sale-live",localStorage: CategoryAuthTestStorage(),fetch: { try await URLSession.shared.data(for: $0) },
            autoRefreshToken: false,emitLocalSessionAsInitialSession: true))
        let entry = await SupabaseOnlineSignIn(client: auth,supabaseURL: url,publishableKey: key)
        try await entry.signIn(email: email,password: password)
        let directory = try await entry.accounts(environment: context.environment.manifest.environment)
        let authorization = try await entry.authorize(AccountSelectionPolicy.makeIntent(selecting: context.accountId,
            from: directory.snapshot,requestedAt: Date()))
        let first = try await context.openRuntime()
        try await entry.startWorkspaceSync(first,authorization: authorization,powerSyncURL: sync)
        let projectId = try ProjectID(validating: project), itemId = try ItemID(validating: item)
        var projectLoaded = false
        for try await value in first.watchProjects() {
            if value.local.rows.contains(where: { $0.id == projectId }) { projectLoaded = true; break }
        }
        #expect(projectLoaded)
        var downloaded: InventorySaleReview?
        for try await value in first.watchInventorySaleReview(itemIds: [itemId]) {
            if let value { downloaded = value; break }
        }
        _ = try #require(downloaded)
        try await first.close()
        let offline = try await context.openRuntime()
        let review = try await offline.readInventorySaleReview(itemIds: [itemId])
        let payload = try review.makePayload(projectId: projectId,currency: .init(validating: "USD"),
            enteredPrices: [itemId: Money(minorUnits: Int64.max,currency: .init(validating: "USD"))])
        let uuid = UUID(), captured = Date()
        let receipt = try await offline.sellInventoryItems(payload,operationUUID: uuid,capturedAt: captured)
        #expect(try await offline.readDownloadedItemPlacements(accountId: context.accountId,scope: .businessInventory).rows.isEmpty)
        #expect(try await offline.readDownloadedItemPlacements(accountId: context.accountId,scope: .project(projectId)).rows.first?.pendingSale != nil)
        try await offline.close()
        let resumed = try await context.openRuntime()
        #expect(try await resumed.sellInventoryItems(payload,operationUUID: uuid,capturedAt: captured).operationId == receipt.operationId)
        try await entry.startWorkspaceSync(resumed,authorization: authorization,powerSyncURL: sync)
        var applied = false
        for try await status in resumed.watchInventorySale(receipt.operationId) {
            if status?.state.phase == .rejected { throw RuntimeInjectedFailure() }
            if status?.state.phase == .applied { applied = true; break }
        }
        #expect(applied)
        var reconciled = false
        for try await value in resumed.watchDownloadedItemPlacements(accountId: context.accountId,scope: .project(projectId)) {
            if let row = value.rows.first, row.placementId == payload.items[0].newPlacementId, row.pendingSale == nil {
                #expect(value.rows.count == 1); reconciled = true; break
            }
        }
        #expect(reconciled)
        #expect(try await resumed.readDownloadedItemPlacements(accountId: context.accountId,scope: .businessInventory).rows.isEmpty)
        var chargeRecognized = false
        for try await history in resumed.watchDownloadedItemPlacementHistory(accountId: context.accountId,itemId: itemId) {
            let expected: ProjectItemAccountingResolution = env["LEDGER_SALE_LOCAL_FINANCIAL_ACCESS"] == "full"
                ? .accountedFor : .relationshipEvidenceIncomplete
            if history.currentAccountingResolution == expected {
                #expect(history.intervals.count == 2 && history.pendingSale == nil)
                #expect(history.currentClientPaidPurchases.isEmpty)
                chargeRecognized = true
                break
            }
        }
        #expect(chargeRecognized)
        try await resumed.close()
    }

    @Test("Sale acceptance drains, survives restart and remains retained after access removal", .timeLimit(.minutes(1)), arguments: [false, true])
    func inventorySaleUsesWorkspaceLifecycle(removing: Bool) async throws {
        let context = try RuntimeTestContext(suffix: "sale-lifecycle-\(removing)")
        defer { context.remove() }
        let events = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        let gate = ManualGate()
        var dependencies = context.dependencies(events: events)
        let validate = dependencies.validateStructuredDatabase
        dependencies.validateStructuredDatabase = { database in
            try await validate(database)
            _ = try await database.execute(sql: "INSERT INTO spike_account_memberships(id,account_id,principal_id,state,financial_access) VALUES ('sale-member',?,?,'active','none')",
                parameters: [context.accountId.rawValue,context.principalId.rawValue])
            for sql in [
                "INSERT INTO spike_clients(id,account_id,display_name,lifecycle,revision,created_at_ms,updated_at_ms) VALUES ('sale-client',?,'Client','active',1,1,1)",
                "INSERT INTO spike_projects(id,account_id,client_id,display_name,lifecycle,revision) VALUES ('sale-project',?,'sale-client','Project','active',1)",
                "INSERT INTO spike_item_placements(id,account_id,item_id,scope_kind) VALUES ('sale-old',?,'sale-item','business_inventory')"
            ] { _ = try await database.execute(sql: sql,parameters: [context.accountId.rawValue]) }
        }
        dependencies.finiteOperationCheckpoint = { operation in
            if operation == .sellInventoryItems { await gate.wait() }
        }
        let uuid = UUID(), capturedAt = Date(timeIntervalSince1970: 1_788_600_000)
        let id = try InventorySaleOperationIdentity.make(accountId: context.accountId,uuid: uuid)
        let payload = try InventorySalePayload(projectId: .init(validating: "sale-project"),currency: .init(validating: "USD"),
            items: [.init(itemId: .init(validating: "sale-item"),placementId: .init(validating: "sale-old"),
                priceRevision: 0,reviewedPriceMinorUnits: 100,newPlacementId: .init(validating: "sale-new"),
                occurrenceId: .init(validating: "sale-charge"))])
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let seeded = try await runtime.pendingUploadCount()
        let acceptance = Task { try await runtime.sellInventoryItems(payload,operationUUID: uuid,capturedAt: capturedAt) }
        await gate.waitUntilEntered()
        let close = Task { try await runtime.close() }
        try await Task.sleep(for: .milliseconds(30))
        #expect(!events.values.contains(.structuredDatabaseCloseAttempted))
        await gate.release()
        #expect(try await acceptance.value.localState == .queued)
        try await close.value
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            try await runtime.sellInventoryItems(payload,operationUUID: uuid,capturedAt: capturedAt)
        }
        let reopened = try await context.openRuntime()
        #expect(try await reopened.sellInventoryItems(payload,operationUUID: uuid,capturedAt: capturedAt).localState == .queued)
        #expect(try await reopened.pendingUploadCount() == seeded + 1)
        var updates = reopened.watchInventorySale(id).makeAsyncIterator()
        #expect(try await updates.next()??.state.phase == .queued)
        if removing { try await reopened.lockAccessPreservingPendingWork() }
        else { try await reopened.close() }
        try await Self.expectClosed(reopened.watchInventorySale(id))
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            try await reopened.sellInventoryItems(payload,operationUUID: uuid,capturedAt: capturedAt)
        }
        if removing {
            await #expect(throws: LedgerPowerSyncLocalBootstrapFailure(stage: .workspaceAccessRemoved)) {
                try await context.openRuntime()
            }
            // Test-only inspection of retained bytes, not permission to reopen
            // this Account in the app after learning of membership removal.
            var inspection = context.dependencies()
            inspection.accessCoordinator = LedgerWorkspaceAccessCoordinator()
            let retained = try await context.openRuntime(dependencies: inspection)
            #expect(try await retained.pendingUploadCount() == seeded + 1)
            #expect(try await retained.pendingWorkSummary().queuedOperationCount == 1)
            try await retained.close()
        }
    }

    @Test("Category acceptance shares workspace drainage, restart and scope enforcement")
    func categoryManagementUsesWorkspaceLifecycle() async throws {
        let context = try RuntimeTestContext(suffix: "category-management-lifecycle")
        defer { context.remove() }
        let events = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        let gate = ManualGate()
        var dependencies = context.dependencies(events: events)
        let validate = dependencies.validateStructuredDatabase
        dependencies.validateStructuredDatabase = { database in
            try await validate(database)
            _ = try await database.execute(sql: """
                INSERT INTO spike_account_memberships(id, account_id, principal_id,
                    role, state, financial_access)
                VALUES ('category-member', ?, ?, 'member', 'active', 'full')
                """, parameters: [context.accountId.rawValue, context.principalId.rawValue])
        }
        dependencies.categoryDirectoryIsComplete = { _ in true }
        dependencies.finiteOperationCheckpoint = { operation in
            if operation == .manageCategories { await gate.wait() }
        }
        let operationUUID = UUID()
        let command = try CategoryManagementCommand(
            operationId: CategoryManagementOperationIdentity.make(accountId: context.accountId, uuid: operationUUID),
            accountId: context.accountId, actorPrincipalId: context.principalId,
            capturedAt: Date(timeIntervalSince1970: 1_788_600_000),
            payload: .init(action: .create, categoryId: BudgetCategoryID(validating: "created-category"),
                name: BudgetCategoryName(validating: "Lighting"), kind: .general,
                excludesFromOverallBudget: false))
        let runtime = try await context.openRuntime(dependencies: dependencies)
        // The fixture inserts membership through SQLite, which itself creates
        // synthetic CRUD. Count the one category command relative to that seed.
        let seededUploadCount = try await runtime.pendingUploadCount()
        let acceptance = Task {
            try await runtime.submitCategoryChange(command.envelope.payload,
                operationUUID: operationUUID, capturedAt: command.envelope.clientCreatedAt)
        }
        await gate.waitUntilEntered()
        let close = Task { try await runtime.close() }
        try await Task.sleep(for: .milliseconds(30))
        #expect(!events.values.contains(.structuredDatabaseCloseAttempted))
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            try await runtime.submit(command)
        }
        await gate.release()
        #expect(try await acceptance.value.localState == .queued)
        try await close.value
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            try await runtime.submit(command)
        }

        // Exact retries remain possible after restart even without new complete-
        // directory evidence; they cannot enqueue or mutate a second operation.
        let reopened = try await context.openRuntime()
        #expect(try await reopened.submit(command).localState == .queued)
        #expect(try await reopened.pendingUploadCount() == seededUploadCount + 1)
        var categories = reopened.watchBudgetCategories().makeAsyncIterator()
        let snapshot = try #require(try await categories.next())
        #expect(snapshot.local.rows.map(\.name.rawValue) == ["Lighting"])
        var statuses = reopened.watchCategoryOperations().makeAsyncIterator()
        let status = try #require(try await statuses.next())
        #expect(status.map(\.operationId) == [command.envelope.operationId])
        #expect(status.first?.state.phase == .queued)
        let foreign = try CategoryManagementCommand(operationId: command.envelope.operationId,
            accountId: AccountID(validating: "another-account"), actorPrincipalId: context.principalId,
            capturedAt: command.envelope.clientCreatedAt, payload: command.envelope.payload)
        await #expect(throws: LedgerOfflineClientRuntimeFailure.accountScopeMismatch) {
            try await reopened.submit(foreign)
        }
        try await reopened.close()
    }

    @Test("CATPOWER-TEST-005 runtime close and reopen preserve local category rows")
    func categoryRowsSurviveRuntimeRestartWithoutCompletenessClaim() async throws {
        let context = try RuntimeTestContext(suffix: "category-restart")
        var dependencies = context.dependencies()
        let validate = dependencies.validateStructuredDatabase
        dependencies.validateStructuredDatabase = { database in
            try await validate(database)
            _ = try await database.execute(
                sql: """
                INSERT INTO spike_account_memberships (
                  id, account_id, principal_id, role, state,
                  can_manage_clients, can_manage_projects,
                  can_manage_project_budgets, financial_access
                ) VALUES (?, ?, ?, 'owner', 'active', 1, 1, 1, 'full')
                """,
                parameters: [
                    "membership-category-runtime",
                    context.accountId.rawValue,
                    context.principalId.rawValue,
                ]
            )
            _ = try await database.execute(
                sql: """
                INSERT INTO spike_budget_categories (
                  id, account_id, display_name, kind, lifecycle, is_system,
                  excludes_from_overall_budget, visibility_class,
                  presentation_order, revision, created_at_ms, updated_at_ms
                ) VALUES (?, ?, 'Furnishings', 'itemized', 'active', 0,
                          0, 'ordinary', 1, 3, 1788500000000, 1788500001000)
                """,
                parameters: ["category-runtime", context.accountId.rawValue]
            )
        }

        let first = try await context.openRuntime(dependencies: dependencies)
        var firstIterator = first.watchBudgetCategories().makeAsyncIterator()
        let beforeRestart = try #require(try await firstIterator.next())
        #expect(beforeRestart.local.rows.map(\.id.rawValue) == ["category-runtime"])
        #expect(beforeRestart.local.quality == .partial)
        #expect(!beforeRestart.local.isCompleteForQuery)
        try await first.close()

        let reopened = try await context.openRuntime()
        var reopenedIterator = reopened.watchBudgetCategories().makeAsyncIterator()
        let afterRestart = try #require(try await reopenedIterator.next())
        #expect(afterRestart.local.rows == beforeRestart.local.rows)
        #expect(afterRestart.local.quality == .partial)
        #expect(!afterRestart.local.isCompleteForQuery)
        #expect(afterRestart.local.queryFingerprint == beforeRestart.local.queryFingerprint)
        #expect(afterRestart.local.localDataVersion == beforeRestart.local.localDataVersion)
        try await reopened.close()
        context.remove()
    }

    @Test("WORKRUNTIME-TEST-005 every staged bootstrap failure closes opened stores in order")
    func stagedBootstrapCleanupMatrix() async throws {
        let cases:
            [(
                LedgerPowerSyncLocalBootstrapStage,
                LedgerPowerSyncLocalCleanupOutcome,
                LedgerPowerSyncLocalCleanupOutcome
            )] = [
                (.databaseKeyLoad, .notOpened, .notOpened),
                (.mediaKeyLoad, .notOpened, .notOpened),
                (.keyValidation, .notOpened, .notOpened),
                (.directoryPreparation, .notOpened, .notOpened),
                (.structuredDatabaseOpen, .notOpened, .notOpened),
                (.structuredDatabaseValidation, .notOpened, .succeeded),
                (.attachmentDatabaseOpen, .notOpened, .succeeded),
                (.attachmentDatabaseValidation, .succeeded, .succeeded),
                (.mediaVaultOpen, .succeeded, .succeeded),
                (.attachmentStoreConstruction, .succeeded, .succeeded),
                (.pendingWorkQueryConstruction, .succeeded, .succeeded),
                (.budgetCategoryQueryConstruction, .succeeded, .succeeded),
                (.spaceAssignmentDestinationQueryConstruction, .succeeded, .succeeded),
                (.projectNoteQueryConstruction, .succeeded, .succeeded),
                (.spaceBrowserQueryConstruction, .succeeded, .succeeded),
                (.runtimeConstruction, .succeeded, .succeeded),
            ]

        for (stage, expectedAttachment, expectedStructured) in cases {
            let context = try RuntimeTestContext(suffix: "stage-\(stage.rawValue)")
            let recorder = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
            let weakVault = WeakVaultRecorder()
            var dependencies = Self.faultedDependencies(
                stage: stage,
                context: context,
                recorder: recorder
            )
            let makeVault = dependencies.makeVault
            dependencies.makeVault = { root, scope, key in
                let vault = try makeVault(root, scope, key)
                weakVault.capture(vault)
                return vault
            }
            do {
                _ = try await context.openRuntime(dependencies: dependencies)
                Issue.record("Expected failure at \(stage.rawValue)")
            } catch let failure as LedgerPowerSyncLocalBootstrapFailure {
                #expect(failure.stage == stage)
                #expect(failure.attachmentDatabaseCleanup == expectedAttachment)
                #expect(failure.structuredDatabaseCleanup == expectedStructured)
            }
            let closeEvents = recorder.values.filter {
                $0 == .attachmentDatabaseCloseAttempted
                    || $0 == .structuredDatabaseCloseAttempted
            }
            let expectedEvents: [AccountWorkspaceRuntimeLifecycleEvent] =
                switch (
                    expectedAttachment,
                    expectedStructured
                ) {
                case (.notOpened, .notOpened): []
                case (.notOpened, _): [.structuredDatabaseCloseAttempted]
                default: [.attachmentDatabaseCloseAttempted, .structuredDatabaseCloseAttempted]
            }
            #expect(closeEvents == expectedEvents)
            if recorder.values.contains(.vaultConstructed) {
                #expect(weakVault.value == nil)
            }
            let recovered = try await context.openRuntime()
            _ = try await recovered.pendingWorkSummary()
            try await recovered.close()
            context.remove()
        }

        let dual = try RuntimeTestContext(suffix: "dual-bootstrap-cleanup")
        let dualRecorder = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        var dualDependencies = Self.faultedDependencies(
            stage: .runtimeConstruction,
            context: dual,
            recorder: dualRecorder
        )
        let openStructured = dualDependencies.openStructuredDatabase
        let openAttachment = dualDependencies.openAttachmentDatabase
        dualDependencies.openStructuredDatabase = { path, key in
            let opened = try openStructured(path, key)
            return AccountWorkspaceOpenedDatabase(
                database: opened.database,
                closePreservingData: {
                    try? await opened.closePreservingData()
                    throw RuntimeInjectedFailure()
                }
            )
        }
        dualDependencies.openAttachmentDatabase = { path, key in
            let opened = try openAttachment(path, key)
            return AccountWorkspaceOpenedDatabase(
                database: opened.database,
                closePreservingData: {
                    try? await opened.closePreservingData()
                    throw RuntimeInjectedFailure()
                }
            )
        }
        do {
            _ = try await dual.openRuntime(dependencies: dualDependencies)
            Issue.record("Expected dual cleanup failure")
        } catch let failure as LedgerPowerSyncLocalBootstrapFailure {
            #expect(failure.stage == .runtimeConstruction)
            #expect(failure.attachmentDatabaseCleanup == .failed)
            #expect(failure.structuredDatabaseCleanup == .failed)
        }
        #expect(
            dualRecorder.values.filter {
                $0 == .attachmentDatabaseCloseAttempted || $0 == .structuredDatabaseCloseAttempted
            }.suffix(2) == [.attachmentDatabaseCloseAttempted, .structuredDatabaseCloseAttempted])
        dual.remove()
    }

    @Test("WORKRUNTIME-TEST-006 wrong database and media keys never report false clean")
    func wrongKeysFailClosedIndependently() async throws {
        let context = try RuntimeTestContext(suffix: "wrong-keys")
        let capture = try context.capture(id: "attachment-wrong-key")
        let initial = try await context.openRuntime()
        _ = try await initial.createClient(context.clientCommand(id: "wrong-key"))
        _ = try await initial.captureAttachment(capture)
        try await initial.close()

        var wrongStructured = context.dependencies()
        wrongStructured.loadDatabaseKey = { _, _ in
            try LedgerPowerSyncEncryptionKey(hexadecimal: String(repeating: "7b", count: 32))
        }
        do {
            _ = try await context.openRuntime(dependencies: wrongStructured)
            Issue.record("Expected wrong structured key failure")
        } catch let failure as LedgerPowerSyncLocalBootstrapFailure {
            #expect(failure.stage == .structuredDatabaseValidation)
            #expect(failure.attachmentDatabaseCleanup == .notOpened)
            #expect(failure.structuredDatabaseCleanup == .failed)
        }

        var wrongAttachment = context.dependencies()
        let openWrongAttachment = wrongAttachment.openAttachmentDatabase
        wrongAttachment.openAttachmentDatabase = { path, _ in
            try openWrongAttachment(
                path,
                LedgerPowerSyncEncryptionKey(hexadecimal: String(repeating: "6c", count: 32))
            )
        }
        do {
            _ = try await context.openRuntime(dependencies: wrongAttachment)
            Issue.record("Expected wrong attachment database key failure")
        } catch let failure as LedgerPowerSyncLocalBootstrapFailure {
            #expect(failure.stage == .attachmentDatabaseValidation)
            #expect(failure.attachmentDatabaseCleanup == .failed)
            #expect(failure.structuredDatabaseCleanup == .succeeded)
        }

        var wrongMedia = context.dependencies()
        wrongMedia.loadMediaKeyBytes = { _, _ in Data(repeating: 0x55, count: 32) }
        do {
            _ = try await context.openRuntime(dependencies: wrongMedia)
            Issue.record("Expected wrong media key to refuse bootstrap")
        } catch let failure as LedgerPowerSyncLocalBootstrapFailure {
            #expect(failure.stage == .mediaVaultOpen)
            #expect(failure.attachmentDatabaseCleanup == .succeeded)
            #expect(failure.structuredDatabaseCleanup == .succeeded)
        }
        let recovered = try await context.openRuntime()
        let summary = try await recovered.pendingWorkSummary()
        #expect(summary.queuedOperationCount == 1)
        #expect(summary.unverifiedAttachmentCount == 1)
        #expect(try await recovered.captureAttachment(capture).attachmentId == capture.attachmentId)
        try await recovered.close()
        context.remove()
    }

    @Test("WORKRUNTIME-TEST-006 missing, corrupt, orphaned, and unavailable media stay explicit")
    func mediaAndObservationFailuresNeverBecomeClean() async throws {
        for mode in ["missing", "corrupt"] {
            let context = try RuntimeTestContext(suffix: mode)
            let capture = try context.capture(id: "attachment-\(mode)")
            let initial = try await context.openRuntime()
            let receipt = try await initial.captureAttachment(capture)
            try await initial.close()
            let objectURL = try Self.objectURL(context: context, receipt: receipt)
            if mode == "missing" {
                try FileManager.default.removeItem(at: objectURL)
            } else {
                try Data("corrupted ciphertext".utf8).write(to: objectURL, options: .atomic)
            }

            let reopened = try await context.openRuntime()
            let summary = try await reopened.pendingWorkSummary()
            #expect(summary.unverifiedAttachmentCount == 1)
            try await reopened.close()
            context.remove()
        }

        let orphanContext = try RuntimeTestContext(suffix: "orphan")
        let orphanRuntime = try await orphanContext.openRuntime()
        let receipt = try await orphanRuntime.captureAttachment(
            orphanContext.capture(id: "attachment-orphan-anchor")
        )
        try await orphanRuntime.close()
        let objectDirectory = try Self.objectURL(
            context: orphanContext,
            receipt: receipt
        ).deletingLastPathComponent()
        try Data("unreferenced encrypted object".utf8).write(
            to: objectDirectory.appendingPathComponent(String(repeating: "f", count: 64)),
            options: .atomic
        )
        let orphanReopened = try await orphanContext.openRuntime()
        await #expect(throws: PendingWorkPowerSyncQueryFailure.orphanedAttachmentEvidence) {
            _ = try await orphanReopened.pendingWorkSummary()
        }
        try await orphanReopened.close()
        orphanContext.remove()

        let unavailableContext = try RuntimeTestContext(suffix: "observation-unavailable")
        var unavailableDependencies = unavailableContext.dependencies()
        unavailableDependencies.makePendingWorkQuery = { _, _, _, _, _, _ in
            FailingPendingWorkSummary()
        }
        let unavailableRuntime = try await unavailableContext.openRuntime(
            dependencies: unavailableDependencies
        )
        await #expect(throws: RuntimeInjectedFailure.self) {
            _ = try await unavailableRuntime.pendingWorkSummary()
        }
        try await unavailableRuntime.close()
        unavailableContext.remove()
    }

    @Test("WORKRUNTIME-TEST-007 one gate drains finite work and all twelve streams")
    func lifecycleGateDrainsAndRejectsPostClose() async throws {
        let context = try RuntimeTestContext(suffix: "lifecycle")
        let finiteGate = ManualGate()
        let finiteOperations = LockedRecorder<AccountWorkspaceRuntimeFiniteOperation>()
        let streamCounter = EntryCounter()
        let events = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        var dependencies = context.dependencies(events: events)
        dependencies.finiteOperationCheckpoint = { operation in
            finiteOperations.append(operation)
            if operation == .pendingUploadCount { await finiteGate.wait() }
        }
        dependencies.streamOperationCheckpoint = { operation in
            await streamCounter.enter(operation)
            try await Task.sleep(for: .seconds(30))
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)

        _ = try await runtime.createClient(context.clientCommand(id: "gate"))
        let projectCommand = try context.projectCommand(id: "gate")
        _ = try await runtime.createProject(projectCommand)
        let archiveCommand = try context.archiveCommand(id: "gate")
        _ = try await runtime.archive(archiveCommand)
        _ = try await runtime.encryptionCipher()
        _ = try await runtime.captureAttachment(context.capture(id: "attachment-gate"))
        _ = try await runtime.pendingWorkSummary()

        let clientRequest = try ClientCoreDetailsRequest(
            accountId: context.accountId,
            clientId: ClientID(validating: "client-lifecycle")
        )
        let projectRequest = try ProjectCoreDetailsRequest(
            accountId: context.accountId,
            projectId: ProjectID(validating: "project-lifecycle")
        )
        let spaceScope = ItemPlacementScope.project(
            try ProjectID(validating: "project-lifecycle")
        )
        let transferSource = try Self.transferSource(
            accountId: context.accountId,
            id: "project-lifecycle",
            clientId: "client-lifecycle"
        )
        let noteRequest = try ProjectNotePageRequest(
            accountId: context.accountId,
            projectId: projectRequest.projectId,
            pageSize: 20
        )
        let spaceId = try SpaceID(validating: "space-lifecycle")
        let spaceListRequest = try SpaceListRequest(
            accountId: context.accountId,
            scope: .project(projectRequest.projectId)
        )
        let streams: [Any] = [
            runtime.watchClient(clientRequest),
            runtime.watchProject(projectRequest),
            runtime.watchClients(),
            runtime.watchProjects(),
            runtime.watchBudgetCategories(),
            runtime.watchSpaceAssignmentDestinations(scope: spaceScope),
            runtime.watchTransferDestinations(source: transferSource),
            runtime.watchProjectNotes(noteRequest),
            runtime.watchSpaceCoreDetails(spaceId: spaceId),
            runtime.watchSpaces(spaceListRequest),
            runtime.watchProjectCreationOperation(projectCommand.envelope.operationId),
            runtime.watchOperation(archiveCommand.envelope.operationId),
        ]
        _ = streams
        await streamCounter.waitUntilEntered(12)
        let enteredStreams = await streamCounter.values()
        for operation in [
            AccountWorkspaceRuntimeStreamOperation.clientDetails,
            .projectDetails,
            .clientDirectory,
            .projectDirectory,
            .budgetCategories,
            .spaceAssignmentDestinations,
            .transferDestinations,
            .projectNotes,
            .spaceCoreDetails,
            .spaceDirectory,
            .projectCreationOperation,
            .projectArchiveOperation,
        ] {
            #expect(enteredStreams.filter { $0 == operation }.count == 1)
        }

        let finite = Task { try await runtime.pendingUploadCount() }
        await finiteGate.waitUntilEntered()
        let close = Task { try await runtime.close() }
        try await Task.sleep(for: .milliseconds(50))
        #expect(!events.values.contains(.attachmentDatabaseCloseAttempted))
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.createClient(context.clientCommand(id: "while-closing"))
        }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.createProject(context.projectCommand(id: "while-closing"))
        }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.archive(context.archiveCommand(id: "while-closing"))
        }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.pendingUploadCount()
        }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.encryptionCipher()
        }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.captureAttachment(
                context.capture(id: "attachment-while-closing")
            )
        }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.pendingWorkSummary()
        }
        try await Self.expectClosed(runtime.watchClients())
        try await Self.expectClosed(runtime.watchProjects())
        try await Self.expectClosed(runtime.watchClient(clientRequest))
        try await Self.expectClosed(runtime.watchProject(projectRequest))
        try await Self.expectClosed(runtime.watchBudgetCategories())
        try await Self.expectClosed(runtime.watchSpaceAssignmentDestinations(scope: spaceScope))
        try await Self.expectClosed(
            runtime.watchTransferDestinations(source: transferSource)
        )
        try await Self.expectClosed(runtime.watchProjectNotes(noteRequest))
        try await Self.expectClosed(runtime.watchSpaceCoreDetails(spaceId: spaceId))
        try await Self.expectClosed(runtime.watchSpaces(spaceListRequest))
        try await Self.expectClosed(
            runtime.watchProjectCreationOperation(projectCommand.envelope.operationId)
        )
        try await Self.expectClosed(runtime.watchOperation(archiveCommand.envelope.operationId))
        await finiteGate.release()
        _ = try await finite.value
        try await close.value
        for operation in [
            AccountWorkspaceRuntimeFiniteOperation.createClient,
            .createProject,
            .archiveProject,
            .pendingUploadCount,
            .encryptionCipher,
            .captureAttachment,
            .pendingWorkSummary,
        ] {
            #expect(finiteOperations.values.filter { $0 == operation }.count == 1)
        }
        #expect(
            events.values.filter {
                $0 == .attachmentDatabaseCloseAttempted || $0 == .structuredDatabaseCloseAttempted
            }.suffix(2) == [.attachmentDatabaseCloseAttempted, .structuredDatabaseCloseAttempted])

        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.pendingUploadCount()
        }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.encryptionCipher()
        }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.createClient(context.clientCommand(id: "after-close"))
        }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.createProject(context.projectCommand(id: "after-close"))
        }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.archive(context.archiveCommand(id: "after-close"))
        }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.captureAttachment(
                context.capture(id: "attachment-after-close")
            )
        }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.pendingWorkSummary()
        }
        try await Self.expectClosed(runtime.watchClients())
        try await Self.expectClosed(runtime.watchProjects())
        try await Self.expectClosed(runtime.watchClient(clientRequest))
        try await Self.expectClosed(runtime.watchProject(projectRequest))
        try await Self.expectClosed(runtime.watchBudgetCategories())
        try await Self.expectClosed(runtime.watchSpaceAssignmentDestinations(scope: spaceScope))
        try await Self.expectClosed(
            runtime.watchTransferDestinations(source: transferSource)
        )
        try await Self.expectClosed(runtime.watchProjectNotes(noteRequest))
        try await Self.expectClosed(runtime.watchSpaceCoreDetails(spaceId: spaceId))
        try await Self.expectClosed(runtime.watchSpaces(spaceListRequest))
        try await Self.expectClosed(
            runtime.watchProjectCreationOperation(projectCommand.envelope.operationId)
        )
        try await Self.expectClosed(runtime.watchOperation(archiveCommand.envelope.operationId))
        context.remove()
    }

    @Test("WORKRUNTIME-TEST-007 consumer and close-caller cancellation cannot strand teardown")
    func cancellationCannotStrandLifecycle() async throws {
        let streamContext = try RuntimeTestContext(suffix: "consumer-cancel")
        let streamEntered = EntryCounter()
        var streamDependencies = streamContext.dependencies()
        streamDependencies.streamOperationCheckpoint = { operation in
            await streamEntered.enter(operation)
            try await Task.sleep(for: .seconds(30))
        }
        let streamRuntime = try await streamContext.openRuntime(
            dependencies: streamDependencies
        )
        let consumer = Task {
            do {
                var iterator = streamRuntime.watchClients().makeAsyncIterator()
                _ = try await iterator.next()
            } catch {
                // Cancellation is the expected terminal outcome.
            }
        }
        await streamEntered.waitUntilEntered(1)
        consumer.cancel()
        await consumer.value
        try await streamRuntime.close()
        streamContext.remove()

        let closeContext = try RuntimeTestContext(suffix: "close-caller-cancel")
        let finiteGate = ManualGate()
        var closeDependencies = closeContext.dependencies()
        closeDependencies.finiteOperationCheckpoint = { operation in
            if operation == .pendingUploadCount { await finiteGate.wait() }
        }
        let closeRuntime = try await closeContext.openRuntime(
            dependencies: closeDependencies
        )
        let finite = Task { try await closeRuntime.pendingUploadCount() }
        await finiteGate.waitUntilEntered()
        let closeCaller = Task { try await closeRuntime.close() }
        try await Task.sleep(for: .milliseconds(20))
        closeCaller.cancel()
        await finiteGate.release()
        _ = try await finite.value
        try await closeCaller.value
        try await closeRuntime.close()
        closeContext.remove()
    }

    @Test("Invoicing charge interface rejects foreign scope and drains on close")
    func invoicingChargesLifecycle() async throws {
        let context = try RuntimeTestContext(suffix: "invoicing-lifecycle")
        defer { context.remove() }
        let entered = EntryCounter()
        var dependencies = context.dependencies()
        dependencies.streamOperationCheckpoint = { operation in
            if operation == .invoicingCharges {
                await entered.enter(operation)
                try await Task.sleep(for: .seconds(30))
            }
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let project = try ProjectID(validating: "project")
        let foreign = try AccountID(validating: "foreign")
        await #expect(throws: LedgerOfflineClientRuntimeFailure.accountScopeMismatch) {
            try await runtime.readInvoicingCharges(accountId: foreign, projectId: project)
        }
        var wrong = runtime.watchInvoicingCharges(accountId: foreign, projectId: project).makeAsyncIterator()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.accountScopeMismatch) { try await wrong.next() }
        let consumer = Task {
            var values = runtime.watchInvoicingCharges(accountId: context.accountId, projectId: project).makeAsyncIterator()
            await #expect(throws: CancellationError.self) { try await values.next() }
        }
        await entered.waitUntilEntered(1)
        try await runtime.close()
        try await consumer.value
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            try await runtime.readInvoicingCharges(accountId: context.accountId, projectId: project)
        }
    }

    @Test("Project Items watch rejects foreign scope and drains on workspace close")
    func downloadedProjectItemsLifecycle() async throws {
        let context = try RuntimeTestContext(suffix: "project-items-lifecycle")
        let entered = EntryCounter()
        var dependencies = physicalItemDependencies(context)
        dependencies.streamOperationCheckpoint = { operation in
            if operation == .downloadedProjectItems {
                await entered.enter(operation)
                try await Task.sleep(for: .seconds(30))
            }
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        var foreign = runtime.watchDownloadedProjectItems(accountId: try AccountID(validating: "foreign"),
            projectId: try ProjectID(validating: "project-physical")).makeAsyncIterator()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.accountScopeMismatch) {
            try await foreign.next()
        }
        let consumer = Task {
            var values = runtime.watchDownloadedProjectItems(accountId: context.accountId,
                projectId: try ProjectID(validating: "project-physical")).makeAsyncIterator()
            await #expect(throws: CancellationError.self) { try await values.next() }
        }
        await entered.waitUntilEntered(1)
        try await runtime.close()
        try await consumer.value
        var closed = runtime.watchDownloadedProjectItems(accountId: context.accountId,
            projectId: try ProjectID(validating: "project-physical")).makeAsyncIterator()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) { try await closed.next() }
        context.remove()
    }

    @Test("Transaction browser rejects foreign scope and cancels before workspace database closure")
    func transactionBrowserLifecycle() async throws {
        let context = try RuntimeTestContext(suffix: "transaction-browser-lifecycle")
        defer { context.remove() }
        let entered = EntryCounter()
        var dependencies = context.dependencies()
        dependencies.streamOperationCheckpoint = { operation in
            if operation == .transactionBrowser {
                await entered.enter(operation)
                // Deliberate cancellation point, not a 30-second test wait.
                try await Task.sleep(for: .seconds(30))
            }
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        var foreign = runtime.watchTransactions(scope: .businessInventory(accountId: try AccountID(validating: "foreign")))
            .makeAsyncIterator()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.accountScopeMismatch) { try await foreign.next() }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.accountScopeMismatch) {
            try await runtime.readTransactionExport(scope: .project(accountId: AccountID(validating: "foreign"),
                projectId: ProjectID(validating: "project"), clientId: ClientID(validating: "client")),
                orderedTransactionIDs: nil, asOf: .init(validating: 1_800_000_000_000))
        }
        let foreignAccount = try AccountID(validating: "foreign")
        let hash = String(repeating: "a", count: 64)
        let attachment = try DownloadedTransactionAttachment(id: .init(validating: "reference"),
            object: .init(accountId: foreignAccount, attachmentId: "pdf", sha256: hash,
                byteCount: "123", mediaType: "application/pdf", storagePath: "accounts/foreign/attachments/pdf/\(hash)", kind: .pdf),
            position: 0, isPrimary: true, fileName: "Receipt.pdf")
        let foreignCatalog = try DownloadedTransactionAttachments(scope: .businessInventory(accountId: foreignAccount),
            transactionId: .init(validating: "transaction"), section: .receipts, revision: 1,
            isComplete: true, attachments: [attachment])
        var foreignAttachments = runtime.watchDownloadedTransactionAttachments(scope: foreignCatalog.scope,
            transactionId: foreignCatalog.transactionId, section: .receipts).makeAsyncIterator()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.accountScopeMismatch) { try await foreignAttachments.next() }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.accountScopeMismatch) {
            try await runtime.loadDownloadedTransactionAttachment(catalog: foreignCatalog,
                attachment: attachment, allowDownload: true)
        }
        let scope = TransactionScope.businessInventory(accountId: context.accountId)
        let consumer = Task {
            var values = runtime.watchTransactions(scope: scope).makeAsyncIterator()
            await #expect(throws: CancellationError.self) { try await values.next() }
        }
        let attachmentConsumer = Task {
            var values = runtime.watchDownloadedTransactionAttachments(scope: scope,
                transactionId: foreignCatalog.transactionId, section: .receipts).makeAsyncIterator()
            await #expect(throws: CancellationError.self) { try await values.next() }
        }
        await entered.waitUntilEntered(2)
        try await runtime.close()
        await consumer.value
        await attachmentConsumer.value
        var closed = runtime.watchTransactions(scope: scope).makeAsyncIterator()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) { try await closed.next() }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            try await runtime.readTransactionExport(scope: scope, orderedTransactionIDs: nil,
                asOf: .init(validating: 1_800_000_000_000))
        }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            try await runtime.loadDownloadedTransactionAttachment(catalog: foreignCatalog,
                attachment: attachment, allowDownload: true)
        }
    }

    @Test("Removal signal reaches current and late presentation observers without unlocking")
    func removalSignalIsMonotonic() async {
        let fence = LedgerWorkspaceAccessFence()
        var early = fence.watchRemoval().makeAsyncIterator()
        fence.markRemoved()
        #expect(await early.next() != nil)
        #expect(await early.next() == nil)
        var late = fence.watchRemoval().makeAsyncIterator()
        #expect(await late.next() != nil)
        #expect(await late.next() == nil)
        fence.markRemoved()
        #expect(fence.isRemoved)
    }

    @Test("Removal drains a live watcher even after its runtime facade is released")
    func removalClosesOrphanedWatcher() async throws {
        let context = try RuntimeTestContext(suffix: "removal-orphaned-watcher")
        let events = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        let entered = EntryCounter()
        var dependencies = context.dependencies(events: events)
        dependencies.streamOperationCheckpoint = { operation in
            await entered.enter(operation)
            try await Task.sleep(for: .seconds(30))
        }
        var runtime: LedgerOfflineClientRuntime? = try await context.openRuntime(dependencies: dependencies)
        weak var releasedRuntime = runtime
        let stream = runtime!.watchClients()
        let consumer = Task {
            do {
                var iterator = stream.makeAsyncIterator()
                _ = try await iterator.next()
            } catch { /* Removal cancels the watcher. */ }
        }
        await entered.waitUntilEntered(1)
        runtime = nil
        for _ in 0..<1000 {
            if releasedRuntime == nil { break }
            await Task.yield()
        }
        #expect(releasedRuntime == nil)
        let identity = try LedgerWorkspaceRemovalRegistry.identity(
            environment: context.environment.manifest.environment,
            principalId: context.principalId, accountId: context.accountId
        )
        try await context.accessCoordinator.remove(identity: identity, persist: {})
        await consumer.value
        #expect(events.values.contains(.attachmentDatabaseCloseAttempted))
        #expect(events.values.contains(.structuredDatabaseCloseAttempted))
        #expect(events.values.contains(.vaultReleased))
        context.remove()
    }

    @Test("Removal locks peer handles and rejects a late concurrent bootstrap")
    func removalWinsConcurrentOpen() async throws {
        let first = try RuntimeTestContext(suffix: "removal-first")
        let peer = try RuntimeTestContext(suffix: "removal-peer")
        let late = try RuntimeTestContext(suffix: "removal-late")
        let runtime = try await first.openRuntime()
        var peerDependencies = peer.dependencies()
        peerDependencies.accessCoordinator = first.accessCoordinator
        let peerRuntime = try await peer.openRuntime(dependencies: peerDependencies)
        let gate = ManualGate()
        var lateDependencies = late.dependencies()
        lateDependencies.accessCoordinator = first.accessCoordinator
        let validate = lateDependencies.validateStructuredDatabase
        lateDependencies.validateStructuredDatabase = { database in
            try await validate(database)
            await gate.wait()
        }
        let openingDependencies = lateDependencies
        let opening = Task { try await late.openRuntime(dependencies: openingDependencies) }
        await gate.waitUntilEntered()
        try await runtime.lockAccessPreservingPendingWork()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await peerRuntime.pendingWorkSummary()
        }
        await gate.release()
        await #expect(throws: LedgerPowerSyncLocalBootstrapFailure(stage: .workspaceAccessRemoved)) {
            _ = try await opening.value
        }
        await #expect(throws: LedgerPowerSyncLocalBootstrapFailure(stage: .workspaceAccessRemoved)) {
            _ = try await first.openRuntime()
        }
        first.remove()
        peer.remove()
        late.remove()
    }

    @Test("Injected persisted removal denies bootstrap before opening protected databases")
    func persistedRemovalDeniesReopen() async throws {
        let context = try RuntimeTestContext(suffix: "persisted-removal")
        let removed = LockedRecorder<String>()
        let events = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        var dependencies = context.dependencies(events: events)
        dependencies.requireWorkspaceNotRemoved = { environment, principal, account in
            let identity = try LedgerWorkspaceRemovalRegistry.identity(
                environment: environment, principalId: principal, accountId: account
            )
            if removed.values.contains(identity) { throw LedgerWorkspaceRemovalFailure.removed }
        }
        dependencies.recordWorkspaceRemoval = { environment, principal, account in
            removed.append(try LedgerWorkspaceRemovalRegistry.identity(
                environment: environment, principalId: principal, accountId: account
            ))
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        _ = try await runtime.captureAttachment(context.capture(id: "pending-removal"))
        try await runtime.lockAccessPreservingPendingWork()
        let eventsBeforeReopen = events.values
        // Simulate a fresh process owner; denial must come from retained store,
        // not solely from the previous coordinator's in-memory latch.
        dependencies.accessCoordinator = LedgerWorkspaceAccessCoordinator()
        await #expect(throws: LedgerPowerSyncLocalBootstrapFailure(stage: .workspaceAccessRemoved)) {
            _ = try await context.openRuntime(dependencies: dependencies)
        }
        #expect(events.values == eventsBeforeReopen)
        context.remove()
    }

    @Test("Unavailable removal registry fails closed without falsely reporting removal")
    func unavailableRemovalRegistryIsNotRemoval() async throws {
        let context = try RuntimeTestContext(suffix: "removal-read-unavailable")
        defer { context.remove() }
        let events = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        var dependencies = context.dependencies(events: events)
        dependencies.requireWorkspaceNotRemoved = { _, _, _ in
            throw LedgerWorkspaceRemovalFailure.unavailable
        }
        await #expect(throws: LedgerPowerSyncLocalBootstrapFailure(stage: .workspaceAccessCheck)) {
            _ = try await context.openRuntime(dependencies: dependencies)
        }
        #expect(events.values.isEmpty)
    }

    @Test("Removal-record failure still closes access and can retry without reopening")
    func removalPersistenceFailureStaysLocked() async throws {
        let context = try RuntimeTestContext(suffix: "removal-write-failure")
        let attempts = LockedRecorder<Int>()
        var dependencies = context.dependencies()
        dependencies.recordWorkspaceRemoval = { _, _, _ in
            attempts.append(1)
            if attempts.values.count == 1 { throw RuntimeInjectedFailure() }
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        await #expect(throws: LedgerOfflineClientRuntimeFailure.removalPersistenceFailed) {
            try await runtime.lockAccessPreservingPendingWork()
        }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.pendingWorkSummary()
        }
        await #expect(throws: LedgerPowerSyncLocalBootstrapFailure(stage: .workspaceAccessRemoved)) {
            _ = try await context.openRuntime(dependencies: dependencies)
        }
        try await runtime.lockAccessPreservingPendingWork()
        #expect(attempts.values.count == 2)
        context.remove()
    }

    @Test("Owned command upload completes using the workspace database")
    func ownedUploadCompletesThroughWorkspace() async throws {
        let context = try RuntimeTestContext(suffix: "owned-upload-success")
        let runtime = try await context.openRuntime()
        _ = try await runtime.createClient(context.clientCommand(id: "upload-success"))
        let gate = ManualGate()
        await gate.release()
        let cancelled = AsyncStream<Void>.makeStream()
        try await runtime.uploadPendingCommands(using: LedgerPowerSyncCommandAppliers(
            clientCreation: RuntimeGatedClientApplier(gate: gate, cancelled: cancelled.continuation)
        ))
        #expect(try await runtime.pendingWorkSummary().queuedOperationCount == 0)
        try await runtime.close()
        context.remove()
    }

    @Test("SDK automatically delivers category commands before and after connection",
          .timeLimit(.minutes(1)), arguments: [false, true], [false, true])
    func sdkDeliversCategoryCommands(queuedBeforeStart: Bool, rejected: Bool) async throws {
        let context = try RuntimeTestContext(suffix: "sdk-category-\(queuedBeforeStart)-\(rejected)")
        defer { context.remove() }
        var dependencies = context.dependencies()
        let validate = dependencies.validateStructuredDatabase
        dependencies.validateStructuredDatabase = { database in
            try await validate(database)
            _ = try await database.execute(sql: """
                INSERT INTO spike_account_memberships(id, account_id, principal_id, role, state, financial_access)
                VALUES ('sdk-category-member', ?, ?, 'member', 'active', 'full')
                """, parameters: [context.accountId.rawValue, context.principalId.rawValue])
            // This is downloaded fixture evidence, not an uploadable membership command.
            _ = try await database.execute(sql: "DELETE FROM ps_crud", parameters: nil)
        }
        dependencies.categoryDirectoryIsComplete = { _ in true }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let command = try CategoryManagementCommand(
            operationId: CategoryManagementOperationIdentity.make(accountId: context.accountId, uuid: UUID()),
            accountId: context.accountId, actorPrincipalId: context.principalId,
            capturedAt: Date(timeIntervalSince1970: 1_788_600_000),
            payload: .init(action: .create, categoryId: BudgetCategoryID(validating: "sdk-created"),
                name: BudgetCategoryName(validating: "Lighting"), kind: .general, excludesFromOverallBudget: false))
        let gate = ManualGate()
        await gate.release()
        let cancelled = AsyncStream<Void>.makeStream()
        let appliers = LedgerPowerSyncCommandAppliers(
            clientCreation: RuntimeGatedClientApplier(gate: gate, cancelled: cancelled.continuation),
            categoryManagement: RuntimeCategoryApplier(rejected: rejected))
        if queuedBeforeStart { _ = try await runtime.submit(command) }
        // Nil download credentials guarantee no hosted network connection.
        // The actual SDK still owns and triggers its independent upload loop.
        try await runtime.startSync(credentialProvider: { nil }, appliers: appliers)
        await #expect(throws: LedgerOfflineClientRuntimeFailure.syncAlreadyStarted) {
            try await runtime.startSync(credentialProvider: { nil }, appliers: appliers)
        }
        if !queuedBeforeStart { _ = try await runtime.submit(command) }
        var updates = runtime.watchCategoryOperations().makeAsyncIterator()
        var terminal: OperationSnapshot?
        while let rows = try await updates.next() {
            if let row = rows.first, row.state.phase == (rejected ? .rejected : .applied) {
                terminal = row
                break
            }
        }
        #expect(terminal?.operationId == command.envelope.operationId)
        try await runtime.close()
        let reopened = try await context.openRuntime()
        var retained = reopened.watchCategoryOperations().makeAsyncIterator()
        let rows = try #require(try await retained.next())
        #expect(rows.first?.state.phase == (rejected ? .rejected : .applied))
        #expect(try await reopened.pendingUploadCount() == 0)
        try await reopened.close()
    }

    @Test("Membership changes request server confirmation; outages do not remove offline access",
          .timeLimit(.minutes(1)))
    func membershipRevalidationObservation() async throws {
        let context = try RuntimeTestContext(suffix: "membership-observation")
        defer { context.remove() }
        let databases = AsyncStream<any PowerSyncDatabaseProtocol>.makeStream()
        let checks = AsyncStream<Void>.makeStream()
        defer { databases.continuation.finish(); checks.continuation.finish() }
        var dependencies = context.dependencies()
        let validate = dependencies.validateStructuredDatabase
        dependencies.validateStructuredDatabase = { database in
            try await validate(database)
            databases.continuation.yield(database)
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        var databaseIterator = databases.stream.makeAsyncIterator()
        let database = try #require(await databaseIterator.next())
        let authorization = WorkspaceMembershipAuthorization(environment: context.environment.manifest.environment,
            authUserId: UUID(), principalId: context.principalId, accountId: context.accountId,
            role: .owner, financialAccess: .full)
        try await runtime.lifecycleOwner.startMembershipRevalidation(authorization) {
            checks.continuation.yield(())
            throw RuntimeInjectedFailure()
        }
        var iterator = checks.stream.makeAsyncIterator()
        _ = try #require(await iterator.next())
        _ = try await database.execute(sql: """
            INSERT INTO spike_account_memberships(id,account_id,principal_id,role,state,financial_access)
            VALUES('watched-member',?,?,'owner','active','full')
            """, parameters: [context.accountId.rawValue, context.principalId.rawValue])
        _ = try #require(await iterator.next())
        _ = try await database.execute(sql: "DELETE FROM spike_account_memberships WHERE id='watched-member'", parameters: nil)
        _ = try #require(await iterator.next())
        // A failed confirmation must not convert missing rows into learned removal.
        try await runtime.lifecycleOwner.requireWorkspaceScope(authorization)
        try await runtime.close()
    }

    @Test("Media transport binding rejects foreign workspace identity and closed runtimes")
    func mediaDownloadBindingScope() async throws {
        let context = try RuntimeTestContext(suffix: "media-binding")
        defer { context.remove() }
        let runtime = try await context.openRuntime()
        let authorization = WorkspaceMembershipAuthorization(environment: context.environment.manifest.environment,
            authUserId: UUID(), principalId: context.principalId, accountId: context.accountId,
            role: .owner, financialAccess: .full)
        for foreignPrincipal in [false, true] {
            let foreign = WorkspaceMembershipAuthorization(environment: authorization.environment,
                authUserId: authorization.authUserId,
                principalId: foreignPrincipal ? try PrincipalID(validating: "foreign") : context.principalId,
                accountId: foreignPrincipal ? context.accountId : try AccountID(validating: "foreign"),
                role: .owner, financialAccess: .full)
            await #expect(throws: LedgerOfflineClientRuntimeFailure.accountScopeMismatch) {
                try await runtime.lifecycleOwner.bindMediaDownload(foreign) { _ in Data() }
            }
        }
        try await runtime.lifecycleOwner.bindMediaDownload(authorization) { _ in Data() }
        try await runtime.close()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            try await runtime.lifecycleOwner.bindMediaDownload(authorization) { _ in Data() }
        }
    }

    @Test(arguments: ["matching", "missing", "reduced", "removed", "foreign"])
    func onlineActivationDoesNotExposeMismatchedCachedPermissions(mode: String) async throws {
        let context = try RuntimeTestContext(suffix: "activation-\(mode)")
        defer { context.remove() }
        var dependencies = context.dependencies()
        let validate = dependencies.validateStructuredDatabase
        dependencies.validateStructuredDatabase = { database in
            try await validate(database)
            if mode != "missing" {
                _ = try await database.execute(sql: """
                    INSERT INTO spike_account_memberships(id,account_id,principal_id,role,state,financial_access)
                    VALUES('activation-member',?,?,'owner',?,'full')
                    """, parameters: [context.accountId.rawValue, context.principalId.rawValue,
                        mode == "removed" ? "removed" : "active"])
                _ = try await database.execute(sql: "DELETE FROM ps_crud", parameters: nil)
            }
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let authorization = WorkspaceMembershipAuthorization(environment: context.environment.manifest.environment,
            authUserId: UUID(), principalId: context.principalId,
            accountId: mode == "foreign" ? try AccountID(validating: "foreign") : context.accountId,
            role: .owner, financialAccess: mode == "reduced" ? .none : .full)
        if mode == "matching" {
            try await runtime.requireMatchingDownloadedMembership(authorization)
        } else {
            let expected: LedgerOfflineClientRuntimeFailure = mode == "foreign"
                ? .accountScopeMismatch : .workspaceMembershipNotReady
            await #expect(throws: expected) { try await runtime.requireMatchingDownloadedMembership(authorization) }
        }
        #expect(try await runtime.pendingUploadCount() == 0)
        try await runtime.close()
    }

    @Test("Category startup waits for directory readiness and respects cancellation/close",
          .timeLimit(.minutes(1)), arguments: ["ready", "reduced", "cancel", "close"])
    func categoryStartupReadiness(mode: String) async throws {
        let context = try RuntimeTestContext(suffix: "category-startup-\(mode)")
        defer { context.remove() }
        let subscribed = ManualGate()
        let completeness = AsyncStream<Bool>.makeStream()
        defer { completeness.continuation.finish() }
        var dependencies = context.dependencies()
        let validate = dependencies.validateStructuredDatabase
        dependencies.validateStructuredDatabase = { database in
            try await validate(database)
            _ = try await database.execute(sql: """
                INSERT INTO spike_account_memberships(id,account_id,principal_id,role,state,financial_access)
                VALUES('startup-member',?,?,'employee','active','full')
                """, parameters: [context.accountId.rawValue, context.principalId.rawValue])
            _ = try await database.execute(sql: "DELETE FROM ps_crud", parameters: nil)
        }
        dependencies.makeBudgetCategoryQuery = { database, principal, account, now in
            BudgetCategoryReferencePowerSyncQuery(database: database, principalId: principal, accountId: account,
                completenessObservation: { _ in
                    Task { await subscribed.release() }
                    return completeness.stream
                }, now: now)
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let authorization = WorkspaceMembershipAuthorization(environment: context.environment.manifest.environment,
            authUserId: UUID(), principalId: context.principalId, accountId: context.accountId,
            role: .employee, financialAccess: mode == "reduced" ? .none : .full)
        let waiting = Task { try await runtime.waitForCategoryWorkspaceReady(authorization) }
        await subscribed.wait()
        completeness.continuation.yield(false)
        if mode == "cancel" {
            waiting.cancel()
            await #expect(throws: CancellationError.self) { try await waiting.value }
        } else if mode == "close" {
            try await runtime.close()
            do {
                try await waiting.value
                Issue.record("Closed workspace must not become ready")
            } catch is CancellationError { }
            catch let error as LedgerOfflineClientRuntimeFailure { #expect(error == .runtimeClosed) }
        } else {
            completeness.continuation.yield(true)
            if mode == "reduced" {
                await #expect(throws: LedgerOfflineClientRuntimeFailure.workspaceMembershipNotReady) {
                    try await waiting.value
                }
            } else {
                try await waiting.value
            }
        }
        try await runtime.close()
    }

    @Test("Offline admission requires a completed download and survives a queued edit/restart",
          .timeLimit(.minutes(1)), arguments: ["ready", "reduced", "incomplete"])
    @MainActor func downloadedAdmissionUsesActualRuntime(mode: String) async throws {
        let context = try RuntimeTestContext(suffix: "admission-runtime-\(mode)")
        defer { context.remove() }
        let observed = ManualGate()
        var dependencies = context.dependencies()
        let validate = dependencies.validateStructuredDatabase
        dependencies.validateStructuredDatabase = { database in
            try await validate(database)
            _ = try await database.execute(sql: """
                INSERT INTO spike_account_memberships(id,account_id,principal_id,role,state,financial_access)
                VALUES('admission-member',?,?,'employee','active','full')
                """, parameters: [context.accountId.rawValue, context.principalId.rawValue])
            _ = try await database.execute(sql: "DELETE FROM ps_crud", parameters: nil)
        }
        dependencies.categoryDirectoryIsComplete = { _ in true }
        dependencies.makeBudgetCategoryQuery = { database, principal, account, now in
            BudgetCategoryReferencePowerSyncQuery(database: database, principalId: principal, accountId: account,
                completenessObservation: { _ in AsyncStream { continuation in
                    continuation.yield(mode != "incomplete")
                    Task { await observed.release() }
                } }, now: now)
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let userId = UUID()
        let memory = CategoryAuthTestStorage()
        let store = OfflineWorkspaceAdmissionStore(read: { memory.retrieve(key: "admissions") },
            write: { memory.store(key: "admissions", value: $0) }, requireNotRemoved: { _ in })
        let auth = AuthClient(configuration: .init(url: URL(string: "https://target.invalid/auth/v1")!,
            localStorage: CategoryAuthTestStorage(), fetch: { request in
                let session = Session(accessToken: "offline-expired-fixture", tokenType: "bearer", expiresIn: 3600,
                    expiresAt: 1_000, refreshToken: "fixture-refresh", user: User(id: userId,
                        appMetadata: [:], userMetadata: [:], aud: "authenticated", createdAt: Date(), updatedAt: Date()))
                return (try AuthClient.Configuration.jsonEncoder.encode(session),
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }, autoRefreshToken: false, emitLocalSessionAsInitialSession: true))
        let entry = SupabaseOnlineSignIn(client: auth, supabaseURL: URL(string: "https://target.invalid")!,
            publishableKey: "sb_publishable_fixture", offlineAdmissions: store)
        try await entry.signIn(email: "fixture@example.invalid", password: "fixture")
        let authorization = WorkspaceMembershipAuthorization(environment: context.environment.manifest.environment,
            authUserId: userId, principalId: context.principalId, accountId: context.accountId,
            role: .employee, financialAccess: mode == "reduced" ? .none : .full)
        let account = try AccountSummary(id: context.accountId, displayName: AccountDisplayName(validating: "Downloaded"))
        #expect(try entry.downloadedWorkspaces(environment: .targetLocal).isEmpty)
        let admission = Task { try await entry.rememberDownloadedWorkspace(authorization, account: account, runtime: runtime) }
        await observed.wait()
        if mode == "incomplete" {
            admission.cancel()
            await #expect(throws: CancellationError.self) { try await admission.value }
        } else if mode == "reduced" {
            await #expect(throws: LedgerOfflineClientRuntimeFailure.workspaceMembershipNotReady) { try await admission.value }
        } else {
            try await admission.value
            _ = try await runtime.submitCategoryChange(.init(action: .create,
                categoryId: BudgetCategoryID(validating: "offline-created"),
                name: BudgetCategoryName(validating: "Offline"), kind: .general, excludesFromOverallBudget: false),
                operationUUID: UUID(), capturedAt: Date())
        }
        try await runtime.close()
        let grants = try entry.downloadedWorkspaces(environment: .targetLocal)
        if mode == "ready" {
            let grant = try #require(grants.first)
            try entry.requireOfflineAdmission(grant)
            let reopened = try await context.openRuntime()
            try await reopened.requireMatchingDownloadedMembership(grant.authorization)
            #expect(try await reopened.pendingUploadCount() == 1)
            var categories = reopened.watchBudgetCategories().makeAsyncIterator()
            #expect(try await categories.next()?.local.rows.map(\.name.rawValue) == ["Offline"])
            try await reopened.close()
        } else {
            #expect(grants.isEmpty)
        }
    }

    @Test("App sync binding rejects a foreign database before credentials or network access",
          arguments: ["account", "principal", "environment"])
    @MainActor func appSyncRequiresMatchingWorkspace(mode: String) async throws {
        let context = try RuntimeTestContext(suffix: "app-sync-scope-\(mode)")
        defer { context.remove() }
        let runtime = try await context.openRuntime()
        let auth = AuthClient(configuration: .init(url: URL(string: "https://target.invalid/auth/v1")!,
            localStorage: CategoryAuthTestStorage(), fetch: { _ in
                Issue.record("Foreign workspace must not fetch credentials")
                throw RuntimeInjectedFailure()
            }, autoRefreshToken: false, emitLocalSessionAsInitialSession: true))
        let entry = SupabaseOnlineSignIn(client: auth, supabaseURL: URL(string: "https://target.invalid")!,
            publishableKey: "sb_publishable_fixture")
        let authorization = try WorkspaceMembershipAuthorization(
            environment: mode == "environment" ? .targetProduction : context.environment.manifest.environment,
            authUserId: UUID(), principalId: mode == "principal" ? PrincipalID(validating: "foreign") : context.principalId,
            accountId: mode == "account" ? AccountID(validating: "foreign") : context.accountId,
            role: .employee, financialAccess: .full)
        await #expect(throws: LedgerOfflineClientRuntimeFailure.accountScopeMismatch) {
            try await entry.startWorkspaceSync(runtime, authorization: authorization, powerSyncURL: nil)
        }
        try await runtime.close()
    }

    @Test("Encrypted offline category command reaches local Postgres through SDK scheduling",
          .enabled(if: ProcessInfo.processInfo.environment["LEDGER_CATEGORY_LOCAL_ACCOUNT"] != nil,
                   "Run test:categories:local -- --native-sdk against the isolated local stack"),
          .timeLimit(.minutes(1)), arguments: [false, true])
    func sdkCategoryLocalServer(lostResponse: Bool) async throws {
        let input = ProcessInfo.processInfo.environment
        guard let address = input["LEDGER_CATEGORY_LOCAL_URL"], let url = URL(string: address),
              url.scheme == "http", ["127.0.0.1", "localhost"].contains(url.host ?? ""),
              let key = input["LEDGER_CATEGORY_LOCAL_KEY"],
              let token = input["LEDGER_CATEGORY_LOCAL_TOKEN"],
              let account = input["LEDGER_CATEGORY_LOCAL_ACCOUNT"], account.hasPrefix("category-http-") else {
            throw RuntimeInjectedFailure()
        }
        let suffix = lostResponse ? "retry" : "normal"
        let context = try RuntimeTestContext(suffix: "category-http-\(suffix)",
            accountId: AccountID(validating: account),
            principalId: PrincipalID(validating: input["LEDGER_CATEGORY_AUTH_PRINCIPAL"] ?? "principal-owner"))
        defer { context.remove() }
        var dependencies = context.dependencies()
        let validate = dependencies.validateStructuredDatabase
        dependencies.validateStructuredDatabase = { database in
            try await validate(database)
            _ = try await database.execute(sql: """
                INSERT INTO spike_account_memberships(id,account_id,principal_id,role,state,financial_access,
                    can_manage_clients,can_manage_projects,can_manage_project_budgets)
                VALUES('local-http-member',?,?,'employee','active','full',1,1,1)
                """, parameters: [context.accountId.rawValue, context.principalId.rawValue])
            _ = try await database.execute(sql: "DELETE FROM ps_crud", parameters: nil)
        }
        // Only membership/directory fixture data is seeded locally; the command
        // and its terminal result must travel through the real runtime and RPC.
        dependencies.categoryDirectoryIsComplete = { _ in true }
        var runtime = try await context.openRuntime(dependencies: dependencies)
        do {
            let command = try CategoryManagementCommand(
                operationId: CategoryManagementOperationIdentity.make(accountId: context.accountId, uuid: UUID()),
                accountId: context.accountId, actorPrincipalId: context.principalId, capturedAt: Date(),
                payload: .init(action: .create,
                    categoryId: BudgetCategoryID(validating: "\(account)-sdk-\(suffix)"),
                    name: BudgetCategoryName(validating: "SDK \(suffix)"), kind: .general,
                    excludesFromOverallBudget: false))
            #expect(try await runtime.submit(command).localState == .queued)
            // Project setup's newly created category must be usable by the same
            // real connection, not just by a category-only test applier.
            let project: CreateProjectCommand?
            if !lostResponse, input["LEDGER_CATEGORY_AUTH_EMAIL"] != nil {
                let newClient = try CreateClientCommand(operationId: OperationID(validating: "\(account)-client-op"),
                    draft: ClientCreationDraft(accountId: context.accountId, actorPrincipalId: context.principalId,
                        operationContractVersion: OperationContractVersion(validating: "client-create-v1"),
                        clientId: ClientID(validating: "client-runtime-\(account)"),
                        displayName: ClientDisplayName(validating: "Inline project client"), capturedAt: Date()))
                project = try CreateProjectCommand(operationId: OperationID(validating: "\(account)-project-op"),
                    draft: ProjectSetupDraft(accountId: context.accountId, actorPrincipalId: context.principalId,
                        operationContractVersion: OperationContractVersion(validating: "project-create-v1"),
                        projectId: ProjectID(validating: "\(account)-project"),
                        clientSelection: .existing(newClient.envelope.payload.clientId),
                        displayName: ProjectDisplayName(validating: "Inline category project"), description: nil,
                        categoryAllocations: [.init(categoryId: BudgetCategoryID(validating: "\(account)-sdk-normal"),
                            allocation: nil)], capturedAt: Date()))
                #expect(try await runtime.createClient(newClient).localState == .queued)
                #expect(try await runtime.createProject(try #require(project)).localState == .queued)
            } else {
                project = nil
            }
            try await runtime.close()
            runtime = try await context.openRuntime()
            #expect(try await runtime.pendingUploadCount() == (project == nil ? 1 : 3))
            let rpc: SupabaseCategoryManagementRPC
            var signedInAuth: AuthClient?
            var actualEntry: SupabaseOnlineSignIn?
            var actualAuthorization: WorkspaceMembershipAuthorization?
            if let email = input["LEDGER_CATEGORY_AUTH_EMAIL"] {
                let password = try #require(input["LEDGER_CATEGORY_AUTH_PASSWORD"])
                let expectedUserText = try #require(input["LEDGER_CATEGORY_AUTH_USER"])
                let expectedUser = try #require(UUID(uuidString: expectedUserText))
                let auth = AuthClient(configuration: .init(url: url.appendingPathComponent("auth/v1"),
                    headers: ["apikey": key], storageKey: "category-local-auth-\(suffix)",
                    localStorage: CategoryAuthTestStorage(),
                    fetch: { request in try await URLSession.shared.data(for: request) },
                    autoRefreshToken: false,
                    emitLocalSessionAsInitialSession: true))
                let entry = await SupabaseOnlineSignIn(client: auth, supabaseURL: url, publishableKey: key)
                try await entry.signIn(email: email, password: password)
                #expect(auth.currentSession?.user.id == expectedUser)
                let refreshed = try await auth.refreshSession()
                #expect(refreshed.user.id == expectedUser)
                let directory = try await entry.accounts(environment: context.environment.manifest.environment)
                #expect(directory.identity.userId == expectedUser)
                #expect(directory.snapshot.principalId == context.principalId)
                #expect(directory.snapshot.accounts.map(\.id) == [context.accountId])
                #expect(directory.snapshot.isComplete && directory.snapshot.quality == .ready)
                let selection = try AccountSelectionPolicy.makeIntent(selecting: context.accountId,
                    from: directory.snapshot, requestedAt: Date())
                let authorization = try await entry.authorize(selection)
                #expect(authorization.authUserId == expectedUser)
                #expect(authorization.principalId == context.principalId && authorization.accountId == context.accountId)
                #expect(authorization.role == .employee && authorization.financialAccess == .full)
                if let receiptId = input["LEDGER_CATEGORY_LOCAL_RECEIPT"] {
                    let reader = try await entry.onlineTransactionReceipts(authorization)
                    let receipt = try await reader.read(transactionId: TransactionID(validating: receiptId))
                    #expect(receipt.accountId == context.accountId && receipt.principalId == context.principalId)
                    #expect(receipt.categoryKind == .general && receipt.auditStatus == .notApplicable)
                    #expect(receipt.reconstruction?.reconstructedTotal.minorUnits == 100)
                    #expect(receipt.items.count == 1 && receipt.items.first?.membership == .sold)
                }
                actualEntry = entry
                actualAuthorization = authorization
                rpc = try SupabaseCategoryManagementRPC(supabaseURL: url, publishableKey: key,
                    authClient: auth, authenticatedUserId: expectedUser)
                signedInAuth = auth
            } else {
                rpc = try SupabaseCategoryManagementRPC(supabaseURL: url, publishableKey: key,
                    accessToken: { token })
            }
            let applier = RuntimeLocalCategoryApplier(rpc: rpc, loseFirstResponse: lostResponse)
            let gate = ManualGate()
            await gate.release()
            let cancelled = AsyncStream<Void>.makeStream()
            if !lostResponse, let actualEntry, let actualAuthorization {
                try await actualEntry.startWorkspaceSync(runtime, authorization: actualAuthorization, powerSyncURL: nil)
            } else {
                try await runtime.startSync(credentialProvider: { nil }, appliers: .init(
                    clientCreation: RuntimeGatedClientApplier(gate: gate, cancelled: cancelled.continuation),
                    categoryManagement: applier))
            }
            var updates = runtime.watchCategoryOperations().makeAsyncIterator()
            var terminal: OperationSnapshot?
            while let rows = try await updates.next() {
                if let row = rows.first, row.state.phase == .applied { terminal = row; break }
            }
            #expect(terminal?.operationId == command.envelope.operationId)
            if let project {
                for try await result in runtime.watchProjectCreationOperation(project.envelope.operationId) {
                    if result.state.phase == .applied || result.state.phase == .rejected {
                        #expect(result.state.phase == .applied, "Project result: \(result.state)")
                        break
                    }
                }
            }
            // Server retries return the original result, not another category or
            // revision. The launcher also verifies authoritative rows via MCP.
            let replay = try await rpc.apply(command)
            let responses = await applier.responses
            if lostResponse || actualEntry == nil {
                #expect(responses.count >= (lostResponse ? 2 : 1))
                #expect(responses.allSatisfy { $0 == replay })
            } else {
                #expect(responses.isEmpty) // Actual app connection path, not the loss-injection wrapper.
            }
            try await runtime.close()
            runtime = try await context.openRuntime()
            var retained = runtime.watchCategoryOperations().makeAsyncIterator()
            #expect(try await retained.next()?.first?.state.phase == .applied)
            #expect(try await runtime.pendingUploadCount() == 0)
            try await runtime.close()
            try await signedInAuth?.signOut(scope: .local)
        } catch {
            try? await runtime.close()
            throw error
        }
    }

    @Test("Real local replication preserves category edits and receipt evidence across offline restart",
          .enabled(if: ProcessInfo.processInfo.environment["LEDGER_CATEGORY_SYNC_URL"] != nil,
                   "Run categoryManagement.local.ts --native-replication with Ledger's local PowerSync service"),
          .timeLimit(.minutes(1)))
    func sdkCategoryLiveReplication() async throws {
        let input = ProcessInfo.processInfo.environment
        guard input["LEDGER_CATEGORY_SYNC_URL"] == "http://127.0.0.1:5590",
              input["LEDGER_CATEGORY_LOCAL_URL"] == "http://127.0.0.1:54321",
              let account = input["LEDGER_CATEGORY_LOCAL_ACCOUNT"], account.hasPrefix("category-http-"),
              let principal = input["LEDGER_CATEGORY_AUTH_PRINCIPAL"],
              let key = input["LEDGER_CATEGORY_LOCAL_KEY"], let email = input["LEDGER_CATEGORY_AUTH_EMAIL"],
              let password = input["LEDGER_CATEGORY_AUTH_PASSWORD"], let receiptId = input["LEDGER_CATEGORY_LOCAL_RECEIPT"],
              let foreignAccount = input["LEDGER_CATEGORY_FOREIGN_ACCOUNT"], foreignAccount == account + "-foreign",
              let revokeText = input["LEDGER_CATEGORY_REVOKE_URL"], let revokeURL = URL(string: revokeText),
              revokeURL.scheme == "http", revokeURL.host == "127.0.0.1", revokeURL.path.hasPrefix("/revoke-") else {
            throw RuntimeInjectedFailure()
        }
        let url = URL(string: "http://127.0.0.1:54321")!
        let syncURL = URL(string: "http://127.0.0.1:5590")!
        let context = try RuntimeTestContext(suffix: "category-live-replication",
            accountId: AccountID(validating: account), principalId: PrincipalID(validating: principal))
        defer { context.remove() }
        let auth = AuthClient(configuration: .init(url: url.appendingPathComponent("auth/v1"),
            headers: ["apikey": key], storageKey: "category-live-replication",
            localStorage: CategoryAuthTestStorage(), fetch: { try await URLSession.shared.data(for: $0) },
            autoRefreshToken: false, emitLocalSessionAsInitialSession: true))
        let entry = await SupabaseOnlineSignIn(client: auth, supabaseURL: url, publishableKey: key)
        try await entry.signIn(email: email, password: password)
        let directory = try await entry.accounts(environment: context.environment.manifest.environment)
        let selection = try AccountSelectionPolicy.makeIntent(selecting: context.accountId,
            from: directory.snapshot, requestedAt: Date())
        let authorization = try await entry.authorize(selection)
        let scope = TransactionScope.businessInventory(accountId: context.accountId)
        let transactionId = try TransactionID(validating: receiptId)
        let projectScope = TransactionScope.project(accountId: context.accountId,
            projectId: try ProjectID(validating: "\(account)-receipt-project"),
            clientId: try ClientID(validating: "\(account)-receipt-client"))
        func projectBrowser(_ runtime: LedgerOfflineClientRuntime) async throws -> [TransactionDetailSnapshot] {
            for try await update in runtime.watchTransactions(scope: projectScope) {
                if case .ready = update { throw RuntimeInjectedFailure() }
                if case .partial(let rows) = update, rows.count == 3 {
                    #expect(rows.map(\.transactionId.rawValue) == ["\(receiptId)-linked-payment", "\(receiptId)-payment", "\(receiptId)-project"])
                    #expect(rows[1].amount.minorUnits == 9007199254740993 && rows[1].category == nil)
                    #expect(rows[0].currentItemCategories?.first?.itemId.rawValue == "\(account)-item")
                    #expect(rows[0].currentItemCategories?.first?.placementId.rawValue == "\(account)-item-project")
                    #expect(rows[0].currentItemCategories?.first?.categoryId?.rawValue == "\(account)-a")
                    #expect(rows[1].currentItemCategories == [] && rows[2].currentItemCategories == [])
                    let contents = try #require(rows[0].paymentContents)
                    #expect(contents.connections.count == 2 && contents.connections.contains { $0.endedAt != nil })
                    #expect(contents.itemIDs.map(\.rawValue) == ["\(account)-item", "\(account)-item-payment-only"])
                    let chair = try #require(contents.items?.first { $0.id.rawValue == "\(account)-item-payment-only" })
                    #expect(chair.name == "Renamed paid chair" && chair.currentSpaceName == "Inventory room" && chair.imageCount == 0)
                    #expect(contents.invoice?.lines.count == 3 && contents.invoice?.total.minorUnits == 123)
                    #expect(contents.invoice?.lines.map(\.description) == ["Frozen Item", "Frozen Expense", "Frozen Fee"])
                    #expect(rows[1].paymentContents?.connections == [] && rows[1].paymentContents?.invoice == nil)
                    #expect(rows[2].paymentContents == nil)
                    #expect(rows.allSatisfy { $0.classification.scope == projectScope && $0.principalId == context.principalId })
                    let media = try await runtime.readDownloadedTransactionAttachments(scope: projectScope,
                        transactionId: TransactionID(validating: "\(receiptId)-payment"), section: .receipts)
                    guard media.isComplete else { continue }
                    #expect(media.revision == 2 && media.attachments.count == 1)
                    #expect(media.attachments.first?.fileName == "Vendor receipt.pdf")
                    #expect(media.attachments.first?.object.byteCount == 9007199254740993)
                    #expect(media.attachments.first?.object.mediaType == "application/pdf")
                    let other = try await runtime.readDownloadedTransactionAttachments(scope: projectScope,
                        transactionId: TransactionID(validating: "\(receiptId)-payment"), section: .other)
                    #expect(other.isComplete && other.attachments.isEmpty)
                    do {
                        let exported = try await runtime.readTransactionExport(scope: projectScope,
                            orderedTransactionIDs: nil, asOf: .init(validating: 1_800_000_000_000))
                        #expect(exported.rows == rows)
                        let selected = try await runtime.readTransactionExport(scope: projectScope,
                            orderedTransactionIDs: rows.reversed().map(\.transactionId), asOf: exported.asOf)
                        #expect(selected.rows == rows.reversed())
                        #expect(try TransactionExportValues.cell(fieldID: "itemCategories", row: exported.rows[0]) == .text("\(account)-a"))
                    } catch PropertyManagementReportFailure.incompleteReadiness { continue }
                    return rows
                }
            }
            throw RuntimeInjectedFailure()
        }
        func relatedItemHistory(_ runtime: LedgerOfflineClientRuntime) async throws -> DownloadedItemPlacementHistory {
            let itemId = try ItemID(validating: "\(account)-item")
            for try await history in runtime.watchDownloadedItemPlacementHistory(accountId: context.accountId, itemId: itemId) {
                if history.intervals.count == 2 {
                    #expect(history.accountId == context.accountId && history.itemId == itemId)
                    #expect(history.intervals.first?.scope == .project(projectScope.projectId!))
                    #expect(history.intervals.last?.scope == .businessInventory)
                    #expect(history.intervals.last?.endedAt != nil)
                    #expect(history.isPartial) // Physical history is not a complete financial ledger.
                    return history
                }
            }
            throw RuntimeInjectedFailure()
        }
        func receipt(_ runtime: LedgerOfflineClientRuntime, kind: BudgetCategoryKind,
                     revision: Int64? = nil) async throws -> TransactionReceiptSnapshot {
            for try await update in runtime.watchTransactionReceipt(scope: scope, transactionId: transactionId) {
                if case .ready(let value) = update, value.categoryKind == kind,
                   revision == nil || value.categoryRevision == revision { return value }
            }
            throw RuntimeInjectedFailure()
        }
        func applied(_ runtime: LedgerOfflineClientRuntime, operationId: OperationID) async throws {
            for try await rows in runtime.watchCategoryOperations() {
                if let row = rows.first(where: { $0.operationId == operationId }) {
                    if row.state.phase == .applied { return }
                    if row.state.phase == .rejected { throw RuntimeInjectedFailure() }
                }
            }
            throw RuntimeInjectedFailure()
        }
        func browser(_ runtime: LedgerOfflineClientRuntime, kind: BudgetCategoryKind,
                     revision: Int64? = nil) async throws -> TransactionDetailSnapshot {
            for try await update in runtime.watchTransactions(scope: scope) {
                if case .ready = update { throw RuntimeInjectedFailure() } // Vendor coverage must remain explicitly partial.
                if case .partial(let rows) = update,
                   let row = rows.first(where: { $0.transactionId == transactionId }),
                   row.category?.kind == kind, revision == nil || row.category?.revision == revision {
                    #expect(rows.count == 1, "Inventory browser excludes Project and foreign Account Transactions")
                    #expect(rows.allSatisfy { $0.classification.scope == scope && $0.principalId == context.principalId })
                    return row
                }
            }
            throw RuntimeInjectedFailure()
        }
        func edit(_ value: TransactionReceiptSnapshot, kind: BudgetCategoryKind) throws -> CategoryManagementCommand {
            try CategoryManagementCommand(
                operationId: CategoryManagementOperationIdentity.make(accountId: context.accountId, uuid: UUID()),
                accountId: context.accountId, actorPrincipalId: context.principalId, capturedAt: Date(),
                payload: .init(action: .edit, categoryId: value.categoryId,
                    expectedRevision: UInt64(value.categoryRevision), name: BudgetCategoryName(validating: value.categoryName),
                    kind: kind, excludesFromOverallBudget: false))
        }
        // Observe real downloaded tables without seeding rows or completeness.
        let databases = LockedRecorder<any PowerSyncDatabaseProtocol>()
        func downloadedAcquisition() async throws {
            let database = try #require(databases.values.last)
            let stream = try database.watch(sql: "SELECT state,amount_minor_units,currency FROM item_acquisition_reviews WHERE id=? AND account_id=?",
                parameters: ["\(account)-item",account]) {
                    [try $0.getString(index: 0),$0.getStringOptional(index: 1),$0.getStringOptional(index: 2)]
                }
            for try await rows in stream where !rows.isEmpty {
                #expect(rows == [["known","99","USD"]]); return
            }
            throw RuntimeInjectedFailure()
        }
        func downloadedPrice() async throws {
            let database = try #require(databases.values.last)
            let stream = try database.watch(sql: """
                SELECT amount_minor_units,currency,revision FROM item_project_prices
                WHERE account_id=? AND item_id=?
                """, parameters: [account, "\(account)-item"]) {
                    [try $0.getString(index: 0), try $0.getString(index: 1), try $0.getString(index: 2)]
                }
            for try await rows in stream where !rows.isEmpty {
                #expect(rows == [["9223372036854775807", "USD", "1"]])
                return
            }
            throw RuntimeInjectedFailure()
        }
        var dependencies = context.dependencies()
        let validate = dependencies.validateStructuredDatabase
        dependencies.validateStructuredDatabase = { database in
            try await validate(database)
            databases.append(database)
        }
        var runtime = try await context.openRuntime(dependencies: dependencies)
        do {
            try await entry.startWorkspaceSync(runtime, authorization: authorization, powerSyncURL: syncURL)
            var downloadedDirectory = false
            for try await categories in runtime.watchBudgetCategories() {
                if categories.local.isCompleteForQuery, !categories.local.rows.isEmpty {
                    downloadedDirectory = true
                    break
                }
            }
            #expect(downloadedDirectory)
            let original = try await receipt(runtime, kind: .general)
            let originalBrowser = try await browser(runtime, kind: .general)
            #expect(originalBrowser.receipt == original)
            #expect(originalBrowser.linkedItemCount == 0 && originalBrowser.receipt?.items.count == 1)
            let originalProjectBrowser = try await projectBrowser(runtime)
            let originalItemHistory = try await relatedItemHistory(runtime)
            try await downloadedPrice()
            try await downloadedAcquisition()
            #expect(originalBrowser.source == "Café vendor")
            #expect(originalBrowser.legacySubtotal?.minorUnits == 9_007_199_254_740_993)
            #expect(originalBrowser.legacyTaxRatePct == "8.12345678901234567890")
            #expect(originalBrowser.transactionDate == "2024-02-29")
            #expect(originalBrowser.createdAtMilliseconds == 1709251200123)
            #expect(originalBrowser.notes == "Preserved notes" && originalBrowser.paymentMethod == "Company card")
            #expect(originalBrowser.hasEmailReceipt == false && originalBrowser.amount.minorUnits == 100)
            #expect(original.items.first?.name == "Receipt Item")
            #expect(original.items.first?.source == "Original vendor" && original.items.first?.currentSource == "Display vendor")
            #expect(original.items.first?.currentSpaceName == "Current room" && original.items.first?.imageCount == 1)
            #expect(original.items.first?.membership == .sold)
            #expect(original.reconstruction?.reconstructedTotal.minorUnits == 100)
            // Bypass the app's scope guard intentionally: the service itself
            // must reject a malicious subscription to a populated other Account.
            let database = try #require(databases.values.last)
            let foreignScope = TransactionReceiptStreamIdentity(scope: .businessInventory(
                accountId: try AccountID(validating: foreignAccount)))
            let denied = try await database.syncStream(name: foreignScope.name, params: foreignScope.parameters).subscribe()
            try await denied.waitForFirstSync()
            for table in ["spike_transactions", "transaction_receipt_items", "spike_items", "spike_budget_categories", "spike_account_memberships"] {
                let counts = try await database.getAll(sql: "SELECT count(*) FROM \(table) WHERE account_id=?",
                    parameters: [foreignAccount]) { try $0.getInt(index: 0) }
                #expect(counts == [0])
            }
            try await denied.unsubscribe()
            try await runtime.close()

            runtime = try await context.openRuntime(dependencies: dependencies)
            let offline = try await receipt(runtime, kind: .general)
            try await downloadedPrice()
            try await downloadedAcquisition()
            #expect(try await projectBrowser(runtime) == originalProjectBrowser)
            #expect(try await relatedItemHistory(runtime) == originalItemHistory)
            #expect(try await browser(runtime, kind: .general) == originalBrowser)
            #expect(offline.items == original.items)
            let change = try edit(offline, kind: .itemized)
            #expect(try await runtime.submit(change).localState == .queued)
            let optimistic = try await receipt(runtime, kind: .itemized)
            let optimisticBrowser = try await browser(runtime, kind: .itemized)
            #expect(optimisticBrowser.receipt == optimistic)
            #expect(optimisticBrowser.notes == originalBrowser.notes && optimisticBrowser.amount == originalBrowser.amount)
            #expect(optimistic.auditStatus == .balanced && optimistic.items == original.items)
            try await runtime.close()

            runtime = try await context.openRuntime(dependencies: dependencies)
            #expect(try await runtime.pendingUploadCount() == 1)
            let reopened = try await receipt(runtime, kind: .itemized)
            #expect(try await browser(runtime, kind: .itemized) == optimisticBrowser)
            #expect(reopened.items == original.items && reopened.auditStatus == .balanced)
            try await entry.startWorkspaceSync(runtime, authorization: authorization, powerSyncURL: syncURL)
            try await applied(runtime, operationId: change.envelope.operationId)
            let replicated = try await receipt(runtime, kind: .itemized, revision: original.categoryRevision + 1)
            let replicatedBrowser = try await browser(runtime, kind: .itemized, revision: original.categoryRevision + 1)
            #expect(replicatedBrowser.receipt == replicated)
            #expect(replicatedBrowser.category?.revision == replicated.categoryRevision)
            #expect(replicatedBrowser.notes == originalBrowser.notes && replicatedBrowser.amount == originalBrowser.amount)
            let onlineReader = try await entry.onlineTransactionReceipts(authorization)
            let server = try await onlineReader.read(transactionId: transactionId)
            #expect(replicated == server)
            #expect(replicated.items == original.items && replicated.reconstruction == original.reconstruction)
            let restore = try edit(replicated, kind: .general)
            #expect(try await runtime.submit(restore).localState == .queued)
            try await applied(runtime, operationId: restore.envelope.operationId)
            let restored = try await receipt(runtime, kind: .general, revision: replicated.categoryRevision + 1)
            #expect(restored.items == original.items && restored.auditStatus == .notApplicable)
            func changeReviewVisibility(_ mode: String) async throws {
                var parts = try #require(URLComponents(url: revokeURL, resolvingAgainstBaseURL: false))
                parts.queryItems = [URLQueryItem(name: "review",value: mode)]
                var request = URLRequest(url: try #require(parts.url)); request.httpMethod = "POST"
                let (_, response) = try await URLSession.shared.data(for: request)
                #expect((response as? HTTPURLResponse)?.statusCode == 204)
            }
            let visibilityDatabase = try #require(databases.values.last)
            try await changeReviewVisibility("ordinary")
            let membershipChanges = try visibilityDatabase.watch(sql: "SELECT financial_access FROM spike_account_memberships WHERE account_id=? AND principal_id=?",
                parameters: [account,principal]) { try $0.getString(index: 0) }
            var restrictedMembershipDownloaded = false
            for try await rows in membershipChanges where rows == ["none"] { restrictedMembershipDownloaded = true; break }
            #expect(restrictedMembershipDownloaded)
            try await downloadedAcquisition()
            try await changeReviewVisibility("restricted")
            let costChanges = try visibilityDatabase.watch(sql: "SELECT count(*) FROM item_acquisition_reviews WHERE id=?",
                parameters: ["\(account)-item"]) { try $0.getInt(index: 0) }
            var protectedCostWithdrawn = false
            for try await counts in costChanges where counts == [0] { protectedCostWithdrawn = true; break }
            #expect(protectedCostWithdrawn)
            #expect(try await visibilityDatabase.get(sql: "SELECT count(*) FROM spike_account_memberships WHERE account_id=? AND principal_id=? AND state='active'",
                parameters: [account,principal]) { try $0.getInt(index: 0) } == 1)
            try await changeReviewVisibility("ordinary")
            try await downloadedAcquisition()
            var revokeRequest = URLRequest(url: revokeURL)
            revokeRequest.httpMethod = "POST"
            let (_, revokeResponse) = try await URLSession.shared.data(for: revokeRequest)
            #expect((revokeResponse as? HTTPURLResponse)?.statusCode == 204)
            let currentDatabase = try #require(databases.values.last)
            let remaining = try currentDatabase.watch(sql: """
                SELECT count(*) FROM spike_account_memberships WHERE account_id=? AND principal_id=? AND state='active'
                UNION ALL SELECT count(*) FROM spike_transactions WHERE account_id=?
                UNION ALL SELECT count(*) FROM transaction_receipt_items WHERE account_id=?
                UNION ALL SELECT count(*) FROM spike_budget_categories WHERE account_id=?
                UNION ALL SELECT count(*) FROM item_project_prices WHERE account_id=?
                UNION ALL SELECT count(*) FROM item_acquisition_reviews WHERE account_id=?
                """, parameters: [account, principal, account, account, account, account, account]) { try $0.getInt(index: 0) }
            var withdrawn = false
            for try await counts in remaining {
                if counts == [0, 0, 0, 0, 0, 0] { withdrawn = true; break }
            }
            #expect(withdrawn)
            await #expect(throws: CurrentItemPlacementReadFailure.accountUnavailable) {
                try await runtime.readDownloadedItemPlacementHistory(accountId: context.accountId,
                    itemId: ItemID(validating: "\(account)-item"))
            }
            var deniedBrowser = runtime.watchTransactions(scope: scope).makeAsyncIterator()
            await #expect(throws: CategoryManagementFailure.categoryUnavailable) { try await deniedBrowser.next() }
            await #expect(throws: CategoryManagementFailure.categoryUnavailable) {
                try await runtime.readTransactionExport(scope: projectScope, orderedTransactionIDs: nil,
                    asOf: .init(validating: 1_800_000_000_000))
            }
            await #expect(throws: CategoryManagementFailure.categoryUnavailable) {
                try await runtime.readDownloadedTransactionReceipt(scope: scope, transactionId: transactionId)
            }
            await #expect(throws: CategoryManagementFailure.categoryUnavailable) {
                try await runtime.submit(edit(restored, kind: .itemized))
            }
            try await runtime.close()
            try await auth.signOut(scope: .local)
        } catch {
            try? await runtime.close()
            throw error
        }
    }

    @Test("SDK upload is cancelled and drained before workspace close or removal",
          .timeLimit(.minutes(1)), arguments: [false, true])
    func sdkUploadDrainsBeforeClose(removing: Bool) async throws {
        let context = try RuntimeTestContext(suffix: "sdk-upload-close-\(removing)")
        defer { context.remove() }
        let events = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        let runtime = try await context.openRuntime(events: events)
        _ = try await runtime.createClient(context.clientCommand(id: "sdk-close"))
        let gate = ManualGate()
        let cancelled = AsyncStream<Void>.makeStream()
        let appliers = LedgerPowerSyncCommandAppliers(
            clientCreation: RuntimeGatedClientApplier(gate: gate, cancelled: cancelled.continuation))
        try await runtime.startSync(credentialProvider: { nil }, appliers: appliers)
        await gate.waitUntilEntered()
        let close = Task {
            if removing { try await runtime.lockAccessPreservingPendingWork() }
            else { try await runtime.close() }
        }
        var signals = cancelled.stream.makeAsyncIterator()
        _ = await signals.next()
        #expect(!events.values.contains(.structuredDatabaseCloseAttempted))
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            try await runtime.startSync(credentialProvider: { nil }, appliers: appliers)
        }
        await gate.release()
        try await close.value
        if removing {
            await #expect(throws: LedgerPowerSyncLocalBootstrapFailure(stage: .workspaceAccessRemoved)) {
                _ = try await context.openRuntime()
            }
        } else {
            let reopened = try await context.openRuntime()
            #expect(try await reopened.pendingWorkSummary().queuedOperationCount == 1)
            try await reopened.close()
        }
    }

    @Test("One runtime owns SDK sync for a physical workspace database", .timeLimit(.minutes(1)))
    func sdkConnectionIsExclusiveAcrossWorkspaceHandles() async throws {
        let context = try RuntimeTestContext(suffix: "sdk-exclusive")
        defer { context.remove() }
        let runtime = try await context.openRuntime()
        // Both handles use the SAME encrypted database file, not parallel
        // fixtures. Close of either would disconnect a shared SDK coordinator.
        let peer = try await context.openRuntime()
        let gate = ManualGate()
        await gate.release()
        let cancelled = AsyncStream<Void>.makeStream()
        let appliers = LedgerPowerSyncCommandAppliers(
            clientCreation: RuntimeGatedClientApplier(gate: gate, cancelled: cancelled.continuation))
        await #expect(throws: LedgerOfflineClientRuntimeFailure.syncRequiresExclusiveWorkspace) {
            try await runtime.startSync(credentialProvider: { nil }, appliers: appliers)
        }
        try await peer.close()

        var failing = context.dependencies()
        failing.validateStructuredDatabase = { _ in throw RuntimeInjectedFailure() }
        await #expect(throws: LedgerPowerSyncLocalBootstrapFailure(
            stage: .structuredDatabaseValidation, structuredDatabaseCleanup: .succeeded)) {
            _ = try await context.openRuntime(dependencies: failing)
        }
        // A pending open reserves ownership before initialization can suspend.
        let openingGate = ManualGate()
        var openingDependencies = context.dependencies()
        let validate = openingDependencies.validateStructuredDatabase
        openingDependencies.validateStructuredDatabase = { database in
            await openingGate.wait()
            try await validate(database)
        }
        let opening = Task { try await context.openRuntime(dependencies: openingDependencies) }
        await openingGate.waitUntilEntered()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.syncRequiresExclusiveWorkspace) {
            try await runtime.startSync(credentialProvider: { nil }, appliers: appliers)
        }
        await openingGate.release()
        let latePeer = try await opening.value
        try await latePeer.close()

        try await runtime.startSync(credentialProvider: { nil }, appliers: appliers)
        await #expect(throws: LedgerOfflineClientRuntimeFailure.syncAlreadyStarted) {
            _ = try await context.openRuntime()
        }
        try await runtime.close()
        let reopened = try await context.openRuntime()
        try await reopened.startSync(credentialProvider: { nil }, appliers: appliers)
        try await reopened.close()
    }

    @Test("SDK credential refresh drains before workspace databases close", .timeLimit(.minutes(1)))
    func sdkCredentialRefreshDrainsBeforeClose() async throws {
        let context = try RuntimeTestContext(suffix: "sdk-credential-close")
        defer { context.remove() }
        let events = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        let runtime = try await context.openRuntime(events: events)
        let refresh = ManualGate()
        let cancelled = AsyncStream<Void>.makeStream()
        let uploadGate = ManualGate()
        await uploadGate.release()
        try await runtime.startSync(credentialProvider: {
            await withTaskCancellationHandler {
                await refresh.wait()
            } onCancel: { cancelled.continuation.yield(()) }
            return nil
        }, appliers: LedgerPowerSyncCommandAppliers(
            clientCreation: RuntimeGatedClientApplier(gate: uploadGate, cancelled: cancelled.continuation)))
        await refresh.waitUntilEntered()
        let close = Task { try await runtime.close() }
        var signals = cancelled.stream.makeAsyncIterator()
        _ = await signals.next()
        #expect(!events.values.contains(.structuredDatabaseCloseAttempted))
        #expect(!events.values.contains(.attachmentDatabaseCloseAttempted))
        await refresh.release()
        try await close.value
        #expect(events.values.contains(.structuredDatabaseCloseAttempted))
    }

    @Test("Removal from SDK credential callback drains outside that callback", .timeLimit(.minutes(1)))
    func reportedRemovalDuringSDKCredentialsDoesNotDeadlock() async throws {
        let context = try RuntimeTestContext(suffix: "sdk-credential-removal")
        defer { context.remove() }
        let events = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        let runtime = try await context.openRuntime(events: events)
        let scope = try LedgerWorkspaceRemovalRegistry.identity(environment: context.environment.manifest.environment,
            principalId: context.principalId, accountId: context.accountId)
        let gate = ManualGate()
        let cancelled = AsyncStream<Void>.makeStream()
        let uploadGate = ManualGate()
        await uploadGate.release()
        let start = Task {
            try await runtime.startSync(credentialProvider: {
                try await context.accessCoordinator.reportRemoval(identity: scope, persist: {})
                await withTaskCancellationHandler { await gate.wait() }
                    onCancel: { cancelled.continuation.yield(()) }
                throw SupabaseWorkspaceAuthorization.Failure.accessDenied
            }, appliers: .init(clientCreation: RuntimeGatedClientApplier(
                gate: uploadGate, cancelled: cancelled.continuation)))
        }
        await gate.waitUntilEntered()
        let cleanup = Task { try await context.accessCoordinator.finishReportedRemoval(identity: scope, persist: {}) }
        var signals = cancelled.stream.makeAsyncIterator()
        _ = await signals.next()
        #expect(!events.values.contains(.structuredDatabaseCloseAttempted))
        await gate.release()
        do { try await start.value }
        catch { #expect(error is CancellationError || error as? LedgerOfflineClientRuntimeFailure == .runtimeClosed) }
        try await cleanup.value
        #expect(events.values.contains(.structuredDatabaseCloseAttempted))
        #expect(events.values.contains(.attachmentDatabaseCloseAttempted))
    }

    @Test("Workspace close and removal cancel uploads and drain before closing databases", arguments: [false, true])
    func ownedUploadDrainsBeforeClose(removing: Bool) async throws {
        let context = try RuntimeTestContext(suffix: "owned-upload-drain-\(removing)")
        let events = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        let runtime = try await context.openRuntime(dependencies: context.dependencies(events: events))
        _ = try await runtime.createClient(context.clientCommand(id: "upload-drain"))
        let peerContext = try RuntimeTestContext(suffix: "owned-upload-peer-\(removing)")
        var peerDependencies = peerContext.dependencies()
        peerDependencies.accessCoordinator = context.accessCoordinator
        let peer = try await peerContext.openRuntime(dependencies: peerDependencies)
        let gate = ManualGate()
        let cancelled = AsyncStream<Void>.makeStream()
        let appliers = LedgerPowerSyncCommandAppliers(
            clientCreation: RuntimeGatedClientApplier(gate: gate, cancelled: cancelled.continuation)
        )
        let upload = Task { try await runtime.uploadPendingCommands(using: appliers) }
        await gate.waitUntilEntered()
        await #expect(throws: LedgerPowerSyncUploadFailure.uploadAlreadyRunning) {
            try await runtime.uploadPendingCommands(using: appliers)
        }
        await #expect(throws: LedgerPowerSyncUploadFailure.uploadAlreadyRunning) {
            try await peer.uploadPendingCommands(using: appliers)
        }
        let close = Task {
            if removing { try await runtime.lockAccessPreservingPendingWork() }
            else { try await runtime.close() }
        }
        var signal = cancelled.stream.makeAsyncIterator()
        _ = await signal.next()
        #expect(!events.values.contains(.structuredDatabaseCloseAttempted))
        #expect(!events.values.contains(.attachmentDatabaseCloseAttempted))
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            try await runtime.uploadPendingCommands(using: appliers)
        }
        await gate.release()
        do {
            try await upload.value
            Issue.record("Closing workspace must not acknowledge cancelled upload")
        } catch {
            if removing { #expect(error as? LedgerOfflineClientRuntimeFailure == .runtimeClosed) }
            else { #expect(error is CancellationError) }
        }
        try await close.value
        #expect(events.values.contains(.structuredDatabaseCloseAttempted))
        if !removing {
            let reopened = try await context.openRuntime()
            #expect(try await reopened.pendingWorkSummary().queuedOperationCount == 1)
            try await reopened.close()
            // A finished cancelled upload releases shared admission for peers.
            try await peer.uploadPendingCommands(using: appliers)
        }
        try await peer.close()
        peerContext.remove()
        context.remove()
    }

    @Test("Removal reported inside upload fences immediately; external cleanup drains and retains work", arguments: [false, true])
    func reportedRemovalDoesNotWaitForItsOwnUpload(persistenceFails: Bool) async throws {
        let context = try RuntimeTestContext(suffix: "reported-removal-\(persistenceFails)")
        let events = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        let runtime = try await context.openRuntime(events: events)
        let identity = try LedgerWorkspaceRemovalRegistry.identity(environment: context.environment.manifest.environment,
            principalId: context.principalId, accountId: context.accountId)
        await #expect(throws: LedgerOfflineClientRuntimeFailure.workspaceMembershipNotReady) {
            try await context.accessCoordinator.finishReportedRemoval(identity: identity, persist: {})
        }
        _ = try await runtime.createClient(context.clientCommand(id: "reported-removal"))
        let media = try context.capture(id: "reported-removal-media")
        let receipt = try await runtime.captureAttachment(media)
        let removals = runtime.watchAccessRemoval()
        let gate = ManualGate()
        let cancelled = AsyncStream<Void>.makeStream()
        let upload = Task {
            try await runtime.uploadPendingCommands(using: .init(clientCreation: RuntimeReportingClientApplier(
                coordinator: context.accessCoordinator, identity: identity, gate: gate,
                cancelled: cancelled.continuation, persistenceFails: persistenceFails)))
        }
        // Reaching this gate proves reporting returned from inside the owned
        // upload before that upload finished (the former self-drain hazard).
        await gate.waitUntilEntered()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) { try await runtime.pendingWorkSummary() }
        #expect(!events.values.contains(.structuredDatabaseCloseAttempted))
        let cleanup = Task {
            var iterator = removals.makeAsyncIterator()
            _ = await iterator.next()
            try await context.accessCoordinator.finishReportedRemoval(identity: identity, persist: {})
        }
        var cancellation = cancelled.stream.makeAsyncIterator()
        _ = await cancellation.next()
        #expect(!events.values.contains(.structuredDatabaseCloseAttempted))
        await gate.release()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) { try await upload.value }
        try await cleanup.value
        #expect(events.values.contains(.structuredDatabaseCloseAttempted))
        #expect(events.values.contains(.attachmentDatabaseCloseAttempted))
        await #expect(throws: LedgerPowerSyncLocalBootstrapFailure(stage: .workspaceAccessRemoved)) {
            try await context.openRuntime()
        }
        // Test-only inspection bypasses injected denial storage, not application
        // recovery authority. Neither pending command nor media was deleted.
        var inspection = context.dependencies()
        inspection.accessCoordinator = LedgerWorkspaceAccessCoordinator()
        let retained = try await context.openRuntime(dependencies: inspection)
        #expect(try await retained.pendingWorkSummary().queuedOperationCount == 1)
        #expect(try await retained.resolveLocalAttachmentBytes(for: receipt) == media.bytes)
        try await retained.close()
        context.remove()
    }

    @Test("Removal identity separates environment, Principal and Account without ambiguous concatenation")
    func removalIdentityIsolation() throws {
        func identity(_ principal: String, _ account: String) throws -> String {
            try LedgerWorkspaceRemovalRegistry.identity(
                environment: .targetStaging,
                principalId: PrincipalID(validating: principal), accountId: AccountID(validating: account)
            )
        }
        #expect(try identity("ab", "c") != identity("a", "bc"))
        #expect(try identity("a", "b") != identity("b", "a"))
        #expect(try identity("a", "b") == identity("a", "b"))
        #expect(try identity("a", "b") != LedgerWorkspaceRemovalRegistry.identity(
            environment: .targetProduction,
            principalId: PrincipalID(validating: "a"), accountId: AccountID(validating: "b")
        ))
    }

    @Test("Learned-removal lock denies paused read admission and preserves pending media")
    func removalLockSuppressesLateBytes() async throws {
        let context = try RuntimeTestContext(suffix: "removal-lock")
        let gate = ManualGate()
        let locked = AsyncStream<Void>.makeStream()
        var dependencies = context.dependencies()
        dependencies.lifecycleEvent = { event in
            if event == .accessLocked { locked.continuation.yield(()) }
        }
        dependencies.finiteOperationCheckpoint = { operation in
            if operation == .resolveAttachmentBytes { await gate.wait() }
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let capture = try context.capture(id: "retained-after-removal")
        let receipt = try await runtime.captureAttachment(capture)
        let resolution = Task { try await runtime.resolveLocalAttachmentBytes(for: receipt) }
        await gate.waitUntilEntered()
        let lock = Task { try await runtime.lockAccessPreservingPendingWork() }
        var notification = locked.stream.makeAsyncIterator()
        _ = await notification.next()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.pendingWorkSummary()
        }
        await gate.release()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await resolution.value
        }
        try await lock.value
        try await runtime.lockAccessPreservingPendingWork()
        locked.continuation.finish()

        // Storage inspection via the test-only bootstrap proves preservation,
        // not permission to reactivate a removed Account in the application.
        var inspectionDependencies = context.dependencies()
        inspectionDependencies.accessCoordinator = LedgerWorkspaceAccessCoordinator()
        let inspection = try await context.openRuntime(dependencies: inspectionDependencies)
        #expect(try await inspection.resolveLocalAttachmentBytes(for: receipt) == capture.bytes)
        #expect(try await inspection.pendingWorkSummary().unverifiedAttachmentCount == 1)
        try await inspection.close()
        context.remove()
    }

    @Test("Learned-removal lock suppresses a result from an already running read body")
    func removalLockSuppressesCompletedRead() async throws {
        let context = try RuntimeTestContext(suffix: "removal-in-read-body")
        let gate = ManualGate()
        let locked = AsyncStream<Void>.makeStream()
        var dependencies = context.dependencies()
        let makeQuery = dependencies.makePendingWorkQuery
        dependencies.makePendingWorkQuery = { database, attachments, environment, principal, account, now in
            let query = try makeQuery(database, attachments, environment, principal, account, now)
            return SuspendedPendingSummary(query: query, gate: gate)
        }
        dependencies.lifecycleEvent = { event in
            if event == .accessLocked { locked.continuation.yield(()) }
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let read = Task { try await runtime.pendingWorkSummary() }
        await gate.waitUntilEntered()
        let lock = Task { try await runtime.lockAccessPreservingPendingWork() }
        var notification = locked.stream.makeAsyncIterator()
        _ = await notification.next()
        await gate.release()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await read.value
        }
        try await lock.value
        locked.continuation.finish()
        context.remove()
    }

    @Test("ATTACHRESOLVE-TEST-005 public runtime resolves the requested receipt and close drains its lease")
    func publicAttachmentResolutionAndCloseDrainage() async throws {
        let successContext = try RuntimeTestContext(suffix: "attachment-resolve-success")
        let successRuntime = try await successContext.openRuntime()
        _ = try await successRuntime.captureAttachment(
            successContext.capture(id: "attachment-runtime-resolve-a")
        )
        let secondCapture = try successContext.capture(
            id: "attachment-runtime-resolve-b"
        )
        let secondReceipt = try await successRuntime.captureAttachment(secondCapture)

        #expect(
            try await successRuntime.resolveLocalAttachmentBytes(for: secondReceipt)
                == secondCapture.bytes
        )
        try await successRuntime.close()
        successContext.remove()

        let drainContext = try RuntimeTestContext(suffix: "attachment-resolve-drain")
        let events = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        let gate = ManualGate()
        var dependencies = drainContext.dependencies(events: events)
        dependencies.finiteOperationCheckpoint = { operation in
            if operation == .resolveAttachmentBytes { await gate.wait() }
        }
        let runtime = try await drainContext.openRuntime(dependencies: dependencies)
        let capture = try drainContext.capture(id: "attachment-runtime-resolve-drain")
        let receipt = try await runtime.captureAttachment(capture)
        let resolution = Task {
            try await runtime.resolveLocalAttachmentBytes(for: receipt)
        }
        await gate.waitUntilEntered()
        let close = Task { try await runtime.close() }
        try await Task.sleep(for: .milliseconds(30))
        #expect(!events.values.contains(.attachmentDatabaseCloseAttempted))
        #expect(!events.values.contains(.structuredDatabaseCloseAttempted))
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.resolveLocalAttachmentBytes(for: receipt)
        }

        await gate.release()
        #expect(try await resolution.value == capture.bytes)
        try await close.value
        #expect(
            events.values.filter {
                $0 == .attachmentDatabaseCloseAttempted
                    || $0 == .structuredDatabaseCloseAttempted
            }.suffix(2) == [
                .attachmentDatabaseCloseAttempted,
                .structuredDatabaseCloseAttempted
            ]
        )
        drainContext.remove()
    }

    @Test("ATTACHRESOLVE-TEST-006 cancellation releases the lease and terminal close refuses reads")
    func cancelledAttachmentResolutionCannotStrandClose() async throws {
        let context = try RuntimeTestContext(suffix: "attachment-resolve-cancel")
        let gate = ManualGate()
        var dependencies = context.dependencies()
        dependencies.finiteOperationCheckpoint = { operation in
            if operation == .resolveAttachmentBytes { await gate.wait() }
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let receipt = try await runtime.captureAttachment(
            context.capture(id: "attachment-runtime-resolve-cancel")
        )
        let resolution = Task {
            try await runtime.resolveLocalAttachmentBytes(for: receipt)
        }
        await gate.waitUntilEntered()
        resolution.cancel()
        let close = Task { try await runtime.close() }
        await gate.release()

        await #expect(throws: CancellationError.self) {
            _ = try await resolution.value
        }
        try await close.value
        try await runtime.close()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.resolveLocalAttachmentBytes(for: receipt)
        }
        context.remove()
    }

    @Test("WORKRUNTIME-TEST-007 close drains active real PowerSync watches")
    func closeDrainsActivePowerSyncWatches() async throws {
        let context = try RuntimeTestContext(suffix: "real-watch-close")
        let progress = EntryCounter()
        var dependencies = context.dependencies()
        dependencies.streamOperationCheckpoint = { operation in
            await progress.enter(operation)
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let clientRequest = try ClientCoreDetailsRequest(
            accountId: context.accountId,
            clientId: ClientID(validating: "client-real-watch")
        )
        let projectRequest = try ProjectCoreDetailsRequest(
            accountId: context.accountId,
            projectId: ProjectID(validating: "project-real-watch")
        )
        let consumers = [
            Self.consumeUntilTermination(
                runtime.watchClient(clientRequest),
                operation: .clientDetails,
                requiredEmissions: 2,
                progress: progress
            ),
            Self.consumeUntilTermination(
                runtime.watchProject(projectRequest),
                operation: .projectDetails,
                requiredEmissions: 2,
                progress: progress
            ),
            Self.consumeUntilTermination(
                runtime.watchClients(),
                operation: .clientDirectory,
                requiredEmissions: 1,
                progress: progress
            ),
            Self.consumeUntilTermination(
                runtime.watchProjects(),
                operation: .projectDirectory,
                requiredEmissions: 1,
                progress: progress
            ),
            Self.consumeUntilTermination(
                runtime.watchBudgetCategories(),
                operation: .budgetCategories,
                requiredEmissions: 1,
                progress: progress
            )
        ]

        await progress.waitUntilEntered(10)
        try await runtime.close()
        for consumer in consumers { await consumer.value }
        await progress.waitUntilEntered(15)
        let observations = await progress.values()
        for operation in [
            AccountWorkspaceRuntimeStreamOperation.clientDetails,
            .projectDetails,
            .clientDirectory,
            .projectDirectory,
            .budgetCategories,
        ] {
            #expect(observations.filter { $0 == operation }.count == 3)
        }
        context.remove()
    }

    @Test("Live Invoice read lease drains before workspace close")
    func liveInvoiceReadDrainsBeforeClose() async throws {
        let context = try RuntimeTestContext(suffix: "live-invoice-read-close")
        let events = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        let gate = ManualGate()
        var dependencies = context.dependencies(events: events)
        dependencies.finiteOperationCheckpoint = { operation in
            if operation == .readLiveInvoices { await gate.wait() }
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let project = try ProjectID(validating: "invoice-project")
        let read = Task { try await runtime.readLiveInvoices(accountId: context.accountId, projectId: project) }
        await gate.waitUntilEntered()
        let close = Task { try await runtime.close() }
        try await Task.sleep(for: .milliseconds(30))
        #expect(!events.values.contains(.structuredDatabaseCloseAttempted))
        read.cancel()
        await gate.release()
        await #expect(throws: CancellationError.self) { try await read.value }
        try await close.value
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            try await runtime.readLiveInvoices(accountId: context.accountId, projectId: project)
        }
        #expect(events.values.filter { $0 == .structuredDatabaseCloseAttempted }.count == 1)
        context.remove()
    }

    @Test("CATPOWER-TEST-005 provider drainage completes before database close")
    func categoryProviderDrainPrecedesDatabaseClose() async throws {
        let context = try RuntimeTestContext(suffix: "category-drain-order")
        let events = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        let streamStarted = EntryCounter()
        let drainGate = ManualGate()
        var dependencies = context.dependencies(events: events)
        dependencies.streamOperationCheckpoint = { operation in
            await streamStarted.enter(operation)
        }
        dependencies.makeBudgetCategoryQuery = { _, _, _, _ in
            BlockingDrainBudgetCategoryQuery(drainGate: drainGate)
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let consumer = Task {
            do {
                for try await _ in runtime.watchBudgetCategories() {}
            } catch {
                // Runtime close cancels the public stream.
            }
        }
        await streamStarted.waitUntilEntered(1)

        let close = Task { try await runtime.close() }
        await drainGate.waitUntilEntered()
        #expect(!events.values.contains(.attachmentDatabaseCloseAttempted))
        #expect(!events.values.contains(.structuredDatabaseCloseAttempted))

        await drainGate.release()
        try await close.value
        await consumer.value
        #expect(
            events.values.filter {
                $0 == .attachmentDatabaseCloseAttempted || $0 == .structuredDatabaseCloseAttempted
            }.suffix(2) == [.attachmentDatabaseCloseAttempted, .structuredDatabaseCloseAttempted]
        )
        context.remove()
    }

    @Test("Space-browser provider drainage completes before database close")
    func spaceBrowserProviderDrainPrecedesDatabaseClose() async throws {
        let context = try RuntimeTestContext(suffix: "space-browser-drain-order")
        let events = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        let drainGate = ManualGate()
        let query = BlockingDrainSpaceListQuery(drainGate: drainGate)
        var dependencies = context.dependencies(events: events)
        dependencies.makeSpaceBrowserQuery = { _, _, _, _ in query }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let request = try SpaceListRequest(
            accountId: context.accountId,
            scope: .businessInventory
        )
        let consumer = Task {
            do {
                for try await _ in runtime.watchSpaces(request) {}
            } catch {
                // Runtime close cancels the public stream.
            }
        }
        for _ in 0..<2_000 {
            if query.watchCount == 1 { break }
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(query.watchCount == 1)

        let close = Task { try await runtime.close() }
        await drainGate.waitUntilEntered()
        #expect(!events.values.contains(.attachmentDatabaseCloseAttempted))
        #expect(!events.values.contains(.structuredDatabaseCloseAttempted))

        await drainGate.release()
        try await close.value
        await consumer.value
        #expect(query.drainCount == 1)
        #expect(
            events.values.filter {
                $0 == .attachmentDatabaseCloseAttempted || $0 == .structuredDatabaseCloseAttempted
            }.suffix(2) == [.attachmentDatabaseCloseAttempted, .structuredDatabaseCloseAttempted]
        )
        context.remove()
    }

    @Test("Project setup provider drainage completes before database close")
    func projectSetupProviderDrainPrecedesDatabaseClose() async throws {
        let context = try RuntimeTestContext(suffix: "project-setup-drain-order")
        let events = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        let drainGate = ManualGate()
        let store = BlockingDrainProjectSetupStore(drainGate: drainGate)
        var dependencies = context.dependencies(events: events)
        dependencies.makeProjectSetupStore = { _, _, _, _ in store }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let operationId = try context.projectCommand(id: "drain-order")
            .envelope.operationId
        let consumer = Task {
            do {
                for try await _ in runtime.watchProjectCreationOperation(operationId) {}
            } catch {
                // Runtime close cancels the public stream.
            }
        }
        for _ in 0..<2_000 {
            if store.watchCount == 1 { break }
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(store.watchCount == 1)

        let close = Task { try await runtime.close() }
        await drainGate.waitUntilEntered()
        #expect(!events.values.contains(.attachmentDatabaseCloseAttempted))
        #expect(!events.values.contains(.structuredDatabaseCloseAttempted))

        await drainGate.release()
        try await close.value
        await consumer.value
        #expect(store.drainCount == 1)
        #expect(
            events.values.filter {
                $0 == .attachmentDatabaseCloseAttempted || $0 == .structuredDatabaseCloseAttempted
            }.suffix(2) == [.attachmentDatabaseCloseAttempted, .structuredDatabaseCloseAttempted]
        )
        context.remove()
    }

    @Test("Project archive provider drainage completes before database close")
    func projectArchiveProviderDrainPrecedesDatabaseClose() async throws {
        let context = try RuntimeTestContext(suffix: "project-archive-drain-order")
        let events = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        let drainGate = ManualGate()
        let store = BlockingDrainProjectArchiveStore(drainGate: drainGate)
        var dependencies = context.dependencies(events: events)
        dependencies.makeProjectArchiveStore = { _, _, _, _ in store }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let operationId = try context.archiveCommand(id: "drain-order").envelope.operationId
        let consumer = Task {
            do {
                for try await _ in runtime.watchOperation(operationId) {}
            } catch {
                // Runtime close cancels the public stream.
            }
        }
        for _ in 0..<2_000 {
            if store.watchCount == 1 { break }
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(store.watchCount == 1)

        let close = Task { try await runtime.close() }
        await drainGate.waitUntilEntered()
        #expect(!events.values.contains(.attachmentDatabaseCloseAttempted))
        #expect(!events.values.contains(.structuredDatabaseCloseAttempted))

        await drainGate.release()
        try await close.value
        await consumer.value
        #expect(store.drainCount == 1)
        #expect(
            events.values.filter {
                $0 == .attachmentDatabaseCloseAttempted || $0 == .structuredDatabaseCloseAttempted
            }.suffix(2) == [.attachmentDatabaseCloseAttempted, .structuredDatabaseCloseAttempted]
        )
        context.remove()
    }

    @Test("WORKRUNTIME-TEST-007 close failure is terminal, combined, and never retried")
    func terminalDualCloseFailureIsIdempotent() async throws {
        let context = try RuntimeTestContext(suffix: "terminal-close")
        let events = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        var dependencies = context.dependencies(events: events)
        let openStructured = dependencies.openStructuredDatabase
        let openAttachment = dependencies.openAttachmentDatabase
        dependencies.openStructuredDatabase = { path, key in
            let opened = try openStructured(path, key)
            return AccountWorkspaceOpenedDatabase(
                database: opened.database,
                closePreservingData: {
                    try? await opened.closePreservingData()
                    throw RuntimeInjectedFailure()
                }
            )
        }
        dependencies.openAttachmentDatabase = { path, key in
            let opened = try openAttachment(path, key)
            return AccountWorkspaceOpenedDatabase(
                database: opened.database,
                closePreservingData: {
                    try? await opened.closePreservingData()
                    throw RuntimeInjectedFailure()
                }
            )
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let first = Task { try await runtime.close() }
        let second = Task { try await runtime.close() }
        for task in [first, second] {
            do {
                try await task.value
                Issue.record("Expected combined close failure")
            } catch let failure as LedgerOfflineClientRuntimeFailure {
                #expect(
                    failure
                        == .databaseCloseFailed(
                            attachmentDatabase: true,
                            structuredDatabase: true
                        ))
            }
        }
        do {
            try await runtime.close()
            Issue.record("Expected stored close failure")
        } catch let failure as LedgerOfflineClientRuntimeFailure {
            #expect(
                failure
                    == .databaseCloseFailed(
                        attachmentDatabase: true,
                        structuredDatabase: true
                    ))
        }
        #expect(events.values.filter { $0 == .attachmentDatabaseCloseAttempted }.count == 1)
        #expect(events.values.filter { $0 == .structuredDatabaseCloseAttempted }.count == 1)
        context.remove()
    }

    @Test("WORKRUNTIME-TEST-008 public runtime remains a narrow non-destructive surface")
    func publicSurfaceCompilesWithoutResourceEscape() async throws {
        let context = try RuntimeTestContext(suffix: "public-surface")
        let runtime: LedgerOfflineClientRuntime = try await context.openRuntime()
        let _: any SpaceListQuerying = runtime
        let _: any SpaceCoreDetailsQuerying = runtime
        _ = runtime.watchClients()
        _ = runtime.watchProjects()
        _ = runtime.watchBudgetCategories()
        _ = runtime.watchSpaceAssignmentDestinations(
            scope: .project(try ProjectID(validating: "project-runtime"))
        )
        _ = runtime.watchTransferDestinations(
            source: try Self.transferSource(
                accountId: context.accountId,
                id: "project-runtime",
                clientId: "client-runtime"
            )
        )
        _ = runtime.watchProjectNotes(try ProjectNotePageRequest(
            accountId: context.accountId,
            projectId: ProjectID(validating: "project-runtime"),
            pageSize: 20
        ))
        _ = runtime.watchSpaceCoreDetails(
            spaceId: try SpaceID(validating: "space-runtime")
        )
        _ = runtime.watchSpaces(try SpaceListRequest(
            accountId: context.accountId,
            scope: .businessInventory
        ))
        _ = try await runtime.pendingUploadCount()
        _ = try await runtime.encryptionCipher()
        _ = try await runtime.pendingWorkSummary()
        try await runtime.close()
        context.remove()
    }

    @Test("Space destination facade binds Account and close cancels and drains its provider")
    func spaceDestinationFacadeAndDrain() async throws {
        let context = try RuntimeTestContext(suffix: "space-destination-facade")
        let query = RuntimeSpaceDestinationQuery()
        var dependencies = context.dependencies()
        dependencies.makeSpaceAssignmentDestinationQuery = { _, _, _, _ in query }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let scope = ItemPlacementScope.project(
            try ProjectID(validating: "project-runtime-space")
        )
        let consumer = Task {
            do {
                for try await _ in runtime.watchSpaceAssignmentDestinations(scope: scope) {}
            } catch { }
        }
        for _ in 0..<2_000 {
            if query.requests.count == 1 { break }
            try? await Task.sleep(for: .milliseconds(1))
        }
        let request = try #require(query.requests.first)
        #expect(request.accountId == context.accountId)
        #expect(request.scope == scope)

        try await runtime.close()
        await consumer.value
        #expect(query.cancelAndDrainCount == 1)
        #expect(query.terminationCount == 1)
        try await Self.expectClosed(
            runtime.watchSpaceAssignmentDestinations(scope: .businessInventory)
        )
        context.remove()
    }

    @Test("Transfer destination facade uses the current encrypted directory and drains on close")
    func transferDestinationFacadeAndDrain() async throws {
        let context = try RuntimeTestContext(suffix: "transfer-destination-facade")
        var dependencies = context.dependencies()
        let validate = dependencies.validateStructuredDatabase
        dependencies.validateStructuredDatabase = { database in
            try await validate(database)
            _ = try await database.execute(
                sql: """
                INSERT INTO spike_account_memberships (
                  id, account_id, principal_id, role, state,
                  can_manage_clients, can_manage_projects,
                  can_manage_project_budgets, financial_access
                ) VALUES (?, ?, ?, 'owner', 'active', 1, 1, 1, 'full')
                """,
                parameters: [
                    "membership-transfer-runtime",
                    context.accountId.rawValue,
                    context.principalId.rawValue,
                ]
            )
            for (id, name) in [
                ("client-current", "Current Client"),
                ("client-stale", "Stale Client"),
            ] {
                _ = try await database.execute(
                    sql: """
                    INSERT INTO spike_clients (
                      id, account_id, display_name, lifecycle, revision,
                      created_at_ms, updated_at_ms, created_by_principal_id
                    ) VALUES (?, ?, ?, 'active', 1,
                              1788500000000, 1788500001000, ?)
                    """,
                    parameters: [
                        id, context.accountId.rawValue, name,
                        context.principalId.rawValue,
                    ]
                )
            }
            for (id, clientId, name) in [
                ("project-source", "client-current", "Current Source"),
                ("project-destination", "client-current", "Destination"),
                ("project-stale-match", "client-stale", "Stale Match"),
            ] {
                _ = try await database.execute(
                    sql: """
                    INSERT INTO spike_projects (
                      id, account_id, client_id, display_name, description,
                      lifecycle, revision, created_at_ms, updated_at_ms,
                      created_by_principal_id
                    ) VALUES (?, ?, ?, ?, NULL, 'active', 1,
                              1788500000000, 1788500001000, ?)
                    """,
                    parameters: [
                        id, context.accountId.rawValue, clientId, name,
                        context.principalId.rawValue,
                    ]
                )
            }
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let staleCaller = try Self.transferSource(
            accountId: context.accountId,
            id: "project-source",
            clientId: "client-stale",
            name: "Caller Stale"
        )
        var iterator = runtime.watchTransferDestinations(
            source: staleCaller
        ).makeAsyncIterator()
        let snapshot = try #require(try await iterator.next())
        #expect(snapshot.source.clientId.rawValue == "client-current")
        #expect(snapshot.source.displayName.rawValue == "Current Source")
        #expect(snapshot.candidates.map(\.destination.id.rawValue) == [
            "project-destination"
        ])
        #expect(snapshot.quality == .partial)
        #expect(!snapshot.isCompleteForSelection)

        let blocked = Task { try await iterator.next() }
        try await runtime.close()
        _ = await blocked.result
        try await Self.expectClosed(
            runtime.watchTransferDestinations(source: staleCaller)
        )
        context.remove()
    }

    @Test("Project-note facade binds Account and close cancels and drains its provider")
    func projectNoteFacadeAndDrain() async throws {
        let context = try RuntimeTestContext(suffix: "project-note-facade")
        let query = RuntimeProjectNoteQuery()
        var dependencies = context.dependencies()
        dependencies.makeProjectNoteQuery = { _, _, _, _ in query }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let request = try ProjectNotePageRequest(
            accountId: context.accountId,
            projectId: ProjectID(validating: "project-runtime-note"),
            pageSize: 20
        )
        let consumer = Task {
            do {
                for try await _ in runtime.watchProjectNotes(request) {}
            } catch { }
        }
        for _ in 0..<2_000 {
            if query.requests.count == 1 { break }
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(query.requests == [request])

        try await runtime.close()
        await consumer.value
        #expect(query.cancelAndDrainCount == 1)
        #expect(query.terminationCount == 1)
        try await Self.expectClosed(runtime.watchProjectNotes(request))
        context.remove()
    }

    @Test("Space core-details facade binds exact Space and drains before close")
    func spaceCoreDetailsFacadeAndDrain() async throws {
        let context = try RuntimeTestContext(suffix: "space-core-details-facade")
        let query = RuntimeSpaceCoreDetailsQuery()
        var dependencies = context.dependencies()
        dependencies.makeSpaceCoreDetailsQuery = { _, _, _, _ in query }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let spaceId = try SpaceID(validating: "space-runtime-detail")
        let expected = try SpaceCoreDetailsRequest(
            accountId: context.accountId,
            spaceId: spaceId
        )
        let consumer = Task {
            do {
                for try await _ in runtime.watchSpaceCoreDetails(expected) {}
            } catch { }
        }
        for _ in 0..<2_000 {
            if query.requests.count == 1 { break }
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(query.requests == [expected])

        let wrongRequest = try SpaceCoreDetailsRequest(
            accountId: AccountID(validating: "account-other"),
            spaceId: spaceId
        )
        var wrongIterator = runtime.watchSpaceCoreDetails(wrongRequest).makeAsyncIterator()
        do {
            _ = try await wrongIterator.next()
            Issue.record("Expected immutable Account-scope refusal")
        } catch let failure as LedgerOfflineClientRuntimeFailure {
            #expect(failure == .accountScopeMismatch)
        }
        #expect(query.requests == [expected])

        try await runtime.close()
        await consumer.value
        #expect(query.cancelAndDrainCount == 1)
        #expect(query.terminationCount == 1)
        try await Self.expectClosed(runtime.watchSpaceCoreDetails(expected))
        context.remove()
    }

    @Test("Space browser facade preserves exact scope and drains before close")
    func spaceBrowserFacadeScopeAndDrain() async throws {
        let context = try RuntimeTestContext(suffix: "space-browser-facade")
        let query = RuntimeSpaceListQuery()
        var dependencies = context.dependencies()
        dependencies.makeSpaceBrowserQuery = { _, _, _, _ in query }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let request = try SpaceListRequest(
            accountId: context.accountId,
            scope: .project(ProjectID(validating: "project-runtime-space-browser"))
        )
        let consumer = Task {
            do {
                for try await _ in runtime.watchSpaces(request) {}
            } catch { }
        }
        for _ in 0..<2_000 {
            if query.requests.count == 1 { break }
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(query.requests == [request])

        let wrongRequest = try SpaceListRequest(
            accountId: AccountID(validating: "account-other"),
            scope: .businessInventory
        )
        var wrongIterator = runtime.watchSpaces(wrongRequest).makeAsyncIterator()
        do {
            _ = try await wrongIterator.next()
            Issue.record("Expected immutable Account-scope refusal")
        } catch let failure as LedgerOfflineClientRuntimeFailure {
            #expect(failure == .accountScopeMismatch)
        }
        #expect(query.requests == [request])

        try await runtime.close()
        await consumer.value
        #expect(query.cancelAndDrainCount == 1)
        #expect(query.terminationCount == 1)
        try await Self.expectClosed(runtime.watchSpaces(request))
        context.remove()
    }

    private static func expectExactConstructionCounts(
        _ events: [AccountWorkspaceRuntimeLifecycleEvent]
    ) {
        for event in [
            AccountWorkspaceRuntimeLifecycleEvent.structuredDatabaseOpened,
            .attachmentDatabaseOpened,
            .vaultConstructed,
            .attachmentStoreConstructed,
            .pendingWorkQueryConstructed,
            .budgetCategoryQueryConstructed,
            .spaceAssignmentDestinationQueryConstructed,
            .projectNoteQueryConstructed,
            .spaceBrowserQueryConstructed,
            .lifecycleOwnerConstructed,
        ] {
            #expect(events.filter { $0 == event }.count == 1)
        }
    }

    private static func insertOperation(
        _ database: any PowerSyncDatabaseProtocol,
        id: String,
        state: LocalOperationState,
        timestamp: Int64 = 1
    ) async throws {
        _ = try await database.execute(
            sql: """
                INSERT INTO \(LedgerPowerSyncTable.localOperations) (
                  id, account_id, actor_principal_id, contract_version, fingerprint,
                  subject_id, local_state, accepted_at_ms, updated_at_ms
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            parameters: [
                id, "account-runtime", "principal-runtime", "pending-work-v1",
                String(repeating: "a", count: 64), "subject-\(id)", state.rawValue,
                timestamp, timestamp,
            ]
        )
    }

    private static func objectURL(
        context: RuntimeTestContext,
        receipt: AttachmentLocalDurabilityReceipt
    ) throws -> URL {
        let root = try context.location().mediaVaultRootURL
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        else {
            throw RuntimeInjectedFailure()
        }
        for case let url as URL in enumerator
        where
            url.lastPathComponent == receipt.localObjectId.rawValue
        {
            return url
        }
        throw RuntimeInjectedFailure()
    }

    private static func faultedDependencies(
        stage: LedgerPowerSyncLocalBootstrapStage,
        context: RuntimeTestContext,
        recorder: LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>
    ) -> LedgerPowerSyncLocalBootstrapDependencies {
        var dependencies = context.dependencies(events: recorder)
        let validateStructured = dependencies.validateStructuredDatabase
        let validateAttachment = dependencies.validateAttachmentDatabase
        let makeVault = dependencies.makeVault
        let makeStore = dependencies.makeAttachmentStore
        let makeQuery = dependencies.makePendingWorkQuery
        let makeBudgetCategoryQuery = dependencies.makeBudgetCategoryQuery
        let makeSpaceAssignmentDestinationQuery =
            dependencies.makeSpaceAssignmentDestinationQuery
        let makeProjectNoteQuery = dependencies.makeProjectNoteQuery
        let makeSpaceBrowserQuery = dependencies.makeSpaceBrowserQuery

        if stage == .databaseKeyLoad {
            dependencies.loadDatabaseKey = { _, _ in throw RuntimeInjectedFailure() }
        }
        if stage == .mediaKeyLoad {
            dependencies.loadMediaKeyBytes = { _, _ in throw RuntimeInjectedFailure() }
        }
        if stage == .keyValidation {
            dependencies.loadMediaKeyBytes = { _, _ in Data(repeating: 0x1a, count: 32) }
        }
        if stage == .directoryPreparation {
            dependencies.createDirectory = { _ in throw RuntimeInjectedFailure() }
        }
        if stage == .structuredDatabaseOpen {
            dependencies.openStructuredDatabase = { _, _ in throw RuntimeInjectedFailure() }
        }
        if stage == .structuredDatabaseValidation {
            dependencies.validateStructuredDatabase = { database in
                try await validateStructured(database)
                throw RuntimeInjectedFailure()
            }
        }
        if stage == .attachmentDatabaseOpen {
            dependencies.openAttachmentDatabase = { _, _ in throw RuntimeInjectedFailure() }
        }
        if stage == .attachmentDatabaseValidation {
            dependencies.validateAttachmentDatabase = { database in
                try await validateAttachment(database)
                throw RuntimeInjectedFailure()
            }
        }
        if stage == .mediaVaultOpen {
            dependencies.makeVault = { _, _, _ in throw RuntimeInjectedFailure() }
        } else {
            dependencies.makeVault = makeVault
        }
        if stage == .attachmentStoreConstruction {
            dependencies.makeAttachmentStore = { _, _, _, _ in throw RuntimeInjectedFailure() }
        } else {
            dependencies.makeAttachmentStore = makeStore
        }
        if stage == .pendingWorkQueryConstruction {
            dependencies.makePendingWorkQuery = { _, _, _, _, _, _ in
                throw RuntimeInjectedFailure()
            }
        } else {
            dependencies.makePendingWorkQuery = makeQuery
        }
        if stage == .budgetCategoryQueryConstruction {
            dependencies.makeBudgetCategoryQuery = { _, _, _, _ in
                throw RuntimeInjectedFailure()
            }
        } else {
            dependencies.makeBudgetCategoryQuery = makeBudgetCategoryQuery
        }
        if stage == .spaceAssignmentDestinationQueryConstruction {
            dependencies.makeSpaceAssignmentDestinationQuery = { _, _, _, _ in
                throw RuntimeInjectedFailure()
            }
        } else {
            dependencies.makeSpaceAssignmentDestinationQuery =
                makeSpaceAssignmentDestinationQuery
        }
        if stage == .projectNoteQueryConstruction {
            dependencies.makeProjectNoteQuery = { _, _, _, _ in
                throw RuntimeInjectedFailure()
            }
        } else {
            dependencies.makeProjectNoteQuery = makeProjectNoteQuery
        }
        if stage == .spaceBrowserQueryConstruction {
            dependencies.makeSpaceBrowserQuery = { _, _, _, _ in
                throw RuntimeInjectedFailure()
            }
        } else {
            dependencies.makeSpaceBrowserQuery = makeSpaceBrowserQuery
        }
        if stage == .runtimeConstruction {
            dependencies.makeLifecycleOwner = { _ in throw RuntimeInjectedFailure() }
        }
        return dependencies
    }

    private static func expectClosed<Value: Sendable>(
        _ stream: AsyncThrowingStream<Value, Error>
    ) async throws {
        var iterator = stream.makeAsyncIterator()
        do {
            _ = try await iterator.next()
            Issue.record("Expected closed stream failure")
        } catch let failure as LedgerOfflineClientRuntimeFailure {
            #expect(failure == .runtimeClosed)
        }
    }

    private static func transferSource(
        accountId: AccountID,
        id: String,
        clientId: String,
        name: String = "Source"
    ) throws -> ProjectSummary {
        let clientID = try ClientID(validating: clientId)
        let observedAt = Date(timeIntervalSince1970: 1_788_600_000)
        return try ProjectSummary(
            id: ProjectID(validating: id),
            accountId: accountId,
            clientId: clientID,
            client: ClientSummary(
                id: clientID,
                accountId: accountId,
                displayName: ClientDisplayName(validating: "Client \(clientId)"),
                lifecycle: .active,
                createdAt: observedAt,
                updatedAt: observedAt
            ),
            displayName: ProjectDisplayName(validating: name),
            description: nil,
            lifecycle: .active
        )
    }

    private static func consumeUntilTermination<Value: Sendable>(
        _ stream: AsyncThrowingStream<Value, Error>,
        operation: AccountWorkspaceRuntimeStreamOperation,
        requiredEmissions: Int,
        progress: EntryCounter
    ) -> Task<Void, Never> {
        Task {
            var emissionCount = 0
            do {
                for try await _ in stream {
                    emissionCount += 1
                    if emissionCount == requiredEmissions {
                        await progress.enter(operation)
                    }
                }
            } catch {
                // Runtime close terminates the public stream with cancellation.
            }
            await progress.enter(operation)
        }
    }
}

private struct RuntimeInjectedFailure: Error {}

private final class BlockingDrainSpaceListQuery:
    AccountWorkspaceSpaceListQuerying, @unchecked Sendable
{
    private let lock = NSLock()
    private let drainGate: ManualGate
    private var watches = 0
    private var drains = 0

    init(drainGate: ManualGate) {
        self.drainGate = drainGate
    }

    var watchCount: Int { lock.withLock { watches } }
    var drainCount: Int { lock.withLock { drains } }

    func watchSpaces(
        _ request: SpaceListRequest
    ) -> AsyncThrowingStream<SpaceListUpdate, Error> {
        lock.withLock { watches += 1 }
        return AsyncThrowingStream { _ in }
    }

    func cancelAndDrainWatches() async {
        lock.withLock { drains += 1 }
        await drainGate.wait()
    }
}

private final class RuntimeSpaceListQuery:
    AccountWorkspaceSpaceListQuerying, @unchecked Sendable
{
    private let lock = NSLock()
    private var recordedRequests: [SpaceListRequest] = []
    private var drains = 0
    private var terminations = 0

    var requests: [SpaceListRequest] { lock.withLock { recordedRequests } }
    var cancelAndDrainCount: Int { lock.withLock { drains } }
    var terminationCount: Int { lock.withLock { terminations } }

    func watchSpaces(
        _ request: SpaceListRequest
    ) -> AsyncThrowingStream<SpaceListUpdate, Error> {
        lock.withLock { recordedRequests.append(request) }
        return AsyncThrowingStream { continuation in
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { self?.terminations += 1 }
            }
        }
    }

    func cancelAndDrainWatches() async {
        lock.withLock { drains += 1 }
    }
}

private final class RuntimeSpaceDestinationQuery:
    AccountWorkspaceSpaceAssignmentDestinationQuerying, @unchecked Sendable
{
    private let lock = NSLock()
    private var recordedRequests: [SpaceAssignmentDestinationRequest] = []
    private var drains = 0
    private var terminations = 0
    var requests: [SpaceAssignmentDestinationRequest] {
        lock.withLock { recordedRequests }
    }
    var cancelAndDrainCount: Int { lock.withLock { drains } }
    var terminationCount: Int { lock.withLock { terminations } }

    func watchEligibleDestinations(
        _ request: SpaceAssignmentDestinationRequest
    ) -> AsyncThrowingStream<SpaceAssignmentDestinationDirectorySnapshot, Error> {
        lock.withLock { recordedRequests.append(request) }
        return AsyncThrowingStream { continuation in
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { self?.terminations += 1 }
            }
        }
    }

    func cancelAndDrainWatches() async {
        lock.withLock { drains += 1 }
    }
}

private final class RuntimeProjectNoteQuery:
    AccountWorkspaceProjectNoteQuerying, @unchecked Sendable
{
    private let lock = NSLock()
    private var recordedRequests: [ProjectNotePageRequest] = []
    private var drains = 0
    private var terminations = 0
    var requests: [ProjectNotePageRequest] { lock.withLock { recordedRequests } }
    var cancelAndDrainCount: Int { lock.withLock { drains } }
    var terminationCount: Int { lock.withLock { terminations } }

    func watchNotes(
        _ request: ProjectNotePageRequest
    ) -> AsyncThrowingStream<ProjectNotePage, Error> {
        lock.withLock { recordedRequests.append(request) }
        return AsyncThrowingStream { continuation in
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { self?.terminations += 1 }
            }
        }
    }

    func cancelAndDrainWatches() async {
        lock.withLock { drains += 1 }
    }
}

private final class RuntimeSpaceCoreDetailsQuery:
    AccountWorkspaceSpaceCoreDetailsQuerying, @unchecked Sendable
{
    private let lock = NSLock()
    private var recordedRequests: [SpaceCoreDetailsRequest] = []
    private var drains = 0
    private var terminations = 0
    var requests: [SpaceCoreDetailsRequest] { lock.withLock { recordedRequests } }
    var cancelAndDrainCount: Int { lock.withLock { drains } }
    var terminationCount: Int { lock.withLock { terminations } }

    func watchSpaceCoreDetails(
        _ request: SpaceCoreDetailsRequest
    ) -> AsyncThrowingStream<SpaceCoreDetailsUpdate, Error> {
        lock.withLock { recordedRequests.append(request) }
        return AsyncThrowingStream { continuation in
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { self?.terminations += 1 }
            }
        }
    }

    func cancelAndDrainWatches() async {
        lock.withLock { drains += 1 }
    }
}

private final class BlockingDrainBudgetCategoryQuery:
    AccountWorkspaceBudgetCategoryQuerying, @unchecked Sendable
{
    private let drainGate: ManualGate

    init(drainGate: ManualGate) {
        self.drainGate = drainGate
    }

    func watchBudgetCategories(
        accountId: AccountID
    ) -> AsyncThrowingStream<BudgetCategoryReferenceSnapshot, Error> {
        AsyncThrowingStream { _ in }
    }

    func cancelAndDrainWatches() async {
        await drainGate.wait()
    }
}

private final class BlockingDrainProjectArchiveStore:
    AccountWorkspaceProjectArchiveStoring, @unchecked Sendable
{
    private let lock = NSLock()
    private let drainGate: ManualGate
    private var watches = 0
    private var drains = 0

    init(drainGate: ManualGate) {
        self.drainGate = drainGate
    }

    var watchCount: Int { lock.withLock { watches } }
    var drainCount: Int { lock.withLock { drains } }

    func archive(_ command: ArchiveProjectCommand) async throws -> OperationReceipt {
        throw RuntimeInjectedFailure()
    }

    func watchOperation(
        _ operationId: OperationID
    ) -> AsyncThrowingStream<OperationSnapshot, Error> {
        lock.withLock { watches += 1 }
        return AsyncThrowingStream { _ in }
    }

    func cancelAndDrainWatches() async {
        lock.withLock { drains += 1 }
        await drainGate.wait()
    }
}

private final class BlockingDrainProjectSetupStore:
    AccountWorkspaceProjectSetupStoring, @unchecked Sendable
{
    private let lock = NSLock()
    private let drainGate: ManualGate
    private var watches = 0
    private var drains = 0

    init(drainGate: ManualGate) {
        self.drainGate = drainGate
    }

    var watchCount: Int { lock.withLock { watches } }
    var drainCount: Int { lock.withLock { drains } }

    func create(_ command: CreateProjectCommand) async throws -> OperationReceipt {
        throw RuntimeInjectedFailure()
    }

    func watchOperation(
        _ operationId: OperationID
    ) -> AsyncThrowingStream<OperationSnapshot, Error> {
        lock.withLock { watches += 1 }
        return AsyncThrowingStream { _ in }
    }

    func cancelAndDrainWatches() async {
        lock.withLock { drains += 1 }
        await drainGate.wait()
    }
}

private actor FailingPendingWorkSummary: AccountWorkspacePendingWorkSummarizing {
    func summary() async throws -> PendingLocalWorkSummary {
        throw RuntimeInjectedFailure()
    }
}

private final class RuntimeTestContext: @unchecked Sendable {
    let root: URL
    let accessCoordinator = LedgerWorkspaceAccessCoordinator()
    let environment: ValidatedLedgerEnvironment
    let principalId: PrincipalID
    let accountId: AccountID
    let databaseKey = try! LedgerPowerSyncEncryptionKey(
        hexadecimal: String(repeating: "1a", count: 32)
    )
    let mediaKeyBytes = Data(repeating: 0x42, count: 32)

    init(suffix: String, namespace: String = "apps.nine4.ledger.runtime-tests",
         accountId: AccountID = try! AccountID(validating: "account-runtime"),
         principalId: PrincipalID = try! PrincipalID(validating: "principal-runtime")) throws {
        self.accountId = accountId
        self.principalId = principalId
        root =
            FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "workspace-runtime-\(suffix)-\(UUID().uuidString)", isDirectory: true
            )
            .standardizedFileURL
        environment = try Self.makeEnvironment(namespace: namespace)
    }

    func dependencies(
        events: LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>? = nil
    ) -> LedgerPowerSyncLocalBootstrapDependencies {
        var dependencies = LedgerPowerSyncLocalBootstrapDependencies.live
        dependencies.accessCoordinator = accessCoordinator
        // These tests use injected storage; removal persistence has dedicated
        // tests below and must not mutate the developer's real keychain.
        dependencies.requireWorkspaceNotRemoved = { _, _, _ in }
        dependencies.recordWorkspaceRemoval = { _, _, _ in }
        dependencies.loadDatabaseKey = { [databaseKey] _, _ in databaseKey }
        dependencies.loadMediaKeyBytes = { [mediaKeyBytes] _, _ in mediaKeyBytes }
        dependencies.createDirectory = { directory in
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        dependencies.lifecycleEvent = { events?.append($0) }
        dependencies.now = { Date(timeIntervalSince1970: 1_788_600_000) }
        return dependencies
    }

    func openRuntime(
        events: LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>? = nil
    ) async throws -> LedgerOfflineClientRuntime {
        try await openRuntime(dependencies: dependencies(events: events))
    }

    func openRuntime(
        dependencies: LedgerPowerSyncLocalBootstrapDependencies
    ) async throws -> LedgerOfflineClientRuntime {
        try await LedgerPowerSyncLocalBootstrap.open(
            validatedEnvironment: environment,
            principalId: principalId,
            accountId: accountId,
            applicationSupportDirectory: root,
            dependencies: dependencies
        )
    }

    func location(
        principalId: PrincipalID? = nil,
        accountId: AccountID? = nil
    ) throws -> LedgerWorkspaceRuntimeLocation {
        try LedgerWorkspaceRuntimeIsolation.resolve(
            validatedEnvironment: environment,
            principalId: principalId ?? self.principalId,
            accountId: accountId ?? self.accountId,
            applicationSupportDirectory: root
        )
    }

    func clientCommand(
        id: String,
        accountId: AccountID? = nil,
        principalId: PrincipalID? = nil
    ) throws -> CreateClientCommand {
        try CreateClientCommand(
            operationId: OperationID(validating: "operation-runtime-\(id)"),
            draft: ClientCreationDraft(
                accountId: accountId ?? self.accountId,
                actorPrincipalId: principalId ?? self.principalId,
                operationContractVersion: OperationContractVersion(validating: "client-create-v1"),
                clientId: ClientID(validating: "client-runtime-\(id)"),
                displayName: ClientDisplayName(validating: "Runtime \(id)"),
                capturedAt: Date(timeIntervalSince1970: 1_788_600_000)
            )
        )
    }

    func projectCommand(
        id: String,
        accountId: AccountID? = nil,
        principalId: PrincipalID? = nil
    ) throws -> CreateProjectCommand {
        try CreateProjectCommand(
            operationId: OperationID(validating: "operation-project-runtime-\(id)"),
            draft: ProjectSetupDraft(
                accountId: accountId ?? self.accountId,
                actorPrincipalId: principalId ?? self.principalId,
                operationContractVersion: OperationContractVersion(validating: "project-create-v1"),
                projectId: ProjectID(validating: "project-runtime-\(id)"),
                clientSelection: ProjectClientSelectionInput(
                    newClientId: ClientID(validating: "client-project-runtime-\(id)"),
                    displayName: ClientDisplayName(validating: "Project Client \(id)")
                ),
                displayName: ProjectDisplayName(validating: "Project Runtime \(id)"),
                description: nil,
                categoryAllocations: [],
                capturedAt: Date(timeIntervalSince1970: 1_788_600_000)
            )
        )
    }

    func archiveCommand(
        id: String,
        accountId: AccountID? = nil,
        principalId: PrincipalID? = nil
    ) throws -> ArchiveProjectCommand {
        let archiveAccountId = accountId ?? self.accountId
        let uuids: [String: String] = [
            "gate": "00000000-0000-4000-8000-000000000101",
            "while-closing": "00000000-0000-4000-8000-000000000102",
            "after-close": "00000000-0000-4000-8000-000000000103",
            "drain-order": "00000000-0000-4000-8000-000000000104"
        ]
        guard let uuidText = uuids[id], let uuid = UUID(uuidString: uuidText) else {
            throw RuntimeInjectedFailure()
        }
        return try ArchiveProjectCommand(
            operationId: ProjectArchiveOperationIdentity.make(
                accountId: archiveAccountId,
                uuid: uuid
            ),
            draft: ProjectArchiveDraft(
                accountId: archiveAccountId,
                actorPrincipalId: principalId ?? self.principalId,
                operationContractVersion: OperationContractVersion(
                    validating: "project-archive-v1"
                ),
                projectId: ProjectID(validating: "project-runtime-\(id)"),
                expectedRevision: ExpectedProjectRevision(1),
                capturedAt: Date(timeIntervalSince1970: 1_788_600_001)
            )
        )
    }

    func capture(
        id: String,
        accountId: AccountID? = nil
    ) throws -> LocalAttachmentCapture {
        try LocalAttachmentCapture(
            attachmentId: AttachmentID(validating: id),
            scope: AttachmentCaptureScope(
                environment: .targetLocal,
                principalId: principalId,
                accountId: accountId ?? self.accountId,
                parent: LedgerEntityReference(
                    kind: .item,
                    id: EntityID(validating: "item-runtime")
                )
            ),
            capturedAt: AttachmentEpochMilliseconds(validating: 1_000),
            bytes: Data("runtime bytes for \(id)".utf8)
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    private static func makeEnvironment(namespace: String) throws -> ValidatedLedgerEnvironment {
        let versions = LedgerContractVersions(schema: "1", query: "1", operation: "1", sync: "1")
        let resources = Dictionary(
            uniqueKeysWithValues: LedgerTargetComponent.allCases.map {
                ($0, "runtime-tests-\($0.rawValue)")
            }
        )
        let manifest = LedgerEnvironmentManifest(
            environment: .targetLocal,
            buildProfile: .targetLocalDevelopment,
            bundleIdentifier: "apps.nine4.ledger.runtime-tests",
            displayName: "Ledger Runtime Tests",
            localDataNamespacePrefix: namespace,
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

private struct SuspendedPendingSummary: AccountWorkspacePendingWorkSummarizing {
    let query: any AccountWorkspacePendingWorkSummarizing
    let gate: ManualGate

    func summary() async throws -> PendingLocalWorkSummary {
        let value = try await query.summary()
        await gate.wait()
        return value
    }
}

private final class LockedRecorder<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []

    var values: [Value] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: Value) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}

private final class WeakVaultRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private weak var storage: AttachmentLocalByteVault?

    var value: AttachmentLocalByteVault? {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func capture(_ vault: AttachmentLocalByteVault) {
        lock.lock()
        storage = vault
        lock.unlock()
    }
}

private actor RuntimeLocalCategoryApplier: CategoryManagementCommandApplying {
    let rpc: SupabaseCategoryManagementRPC
    let loseFirstResponse: Bool
    private(set) var responses: [CategoryManagementServerResult] = []

    init(rpc: SupabaseCategoryManagementRPC, loseFirstResponse: Bool) {
        self.rpc = rpc
        self.loseFirstResponse = loseFirstResponse
    }

    func apply(_ command: CategoryManagementCommand) async throws -> CategoryManagementServerResult {
        let result = try await rpc.apply(command)
        responses.append(result)
        if loseFirstResponse && responses.count == 1 { throw URLError(.networkConnectionLost) }
        return result
    }
}

private struct RuntimeCategoryApplier: CategoryManagementCommandApplying {
    let rejected: Bool
    func apply(_ command: CategoryManagementCommand) async throws -> CategoryManagementServerResult {
        let e = command.envelope
        let hash = try command.fingerprint.sha256
        return CategoryManagementServerResult(operation_id: e.operationId.rawValue,
            account_id: e.accountId.rawValue, actor_principal_id: e.actorPrincipalId.rawValue,
            command_type: "manage_categories", contract_version: "category-management-v1",
            command_fingerprint: hash, envelope_sha256: hash, request_sha256: nil,
            subject_id: e.accountId.rawValue, phase: rejected ? "rejected" : "applied",
            result_code: rejected ? nil : "categories_updated",
            error_code: rejected ? "category_name_unavailable" : nil,
            client_created_at_ms: 1_788_600_000_000, server_received_at_ms: 1_788_600_000_100,
            completed_at_ms: 1_788_600_000_200)
    }
}

private struct RuntimeReportingClientApplier: ClientCreationCommandApplying {
    let coordinator: LedgerWorkspaceAccessCoordinator
    let identity: String
    let gate: ManualGate
    let cancelled: AsyncStream<Void>.Continuation
    let persistenceFails: Bool

    func apply(_ request: ClientCreationUploadRequest) async throws -> ClientCreationServerResult {
        do {
            try await coordinator.reportRemoval(identity: identity) {
                if persistenceFails { throw RuntimeInjectedFailure() }
            }
            #expect(!persistenceFails)
        } catch {
            #expect(persistenceFails)
            #expect(error as? LedgerOfflineClientRuntimeFailure == .removalPersistenceFailed)
        }
        await withTaskCancellationHandler { await gate.wait() }
            onCancel: { cancelled.yield(()) }
        throw SupabaseWorkspaceAuthorization.Failure.accessDenied
    }
}

private struct RuntimeGatedClientApplier: ClientCreationCommandApplying {
    let gate: ManualGate
    let cancelled: AsyncStream<Void>.Continuation

    func apply(_ request: ClientCreationUploadRequest) async throws -> ClientCreationServerResult {
        await withTaskCancellationHandler {
            // Intentionally ignores cancellation until released, as an already
            // dispatched request may do. The owner must retain its database.
            await gate.wait()
        } onCancel: { cancelled.yield(()) }
        return ClientCreationServerResult(
            operationId: request.operationId, accountId: request.accountId,
            commandFingerprint: request.fingerprint, subjectId: request.clientId,
            phase: "applied", resultCode: "client_created", errorCode: nil
        )
    }
}

private actor RuntimePhysicalSubscription: SyncStreamSubscription {
    nonisolated let name = "physical_account_items"
    nonisolated let parameters: JsonParam? = ["account_id": .string("account-runtime")]
    let cleanup: ManualGate
    private(set) var unsubscribeCount = 0
    init(cleanup: ManualGate) { self.cleanup = cleanup }
    func waitForFirstSync() async throws { Issue.record("Physical watch must not gate local rows on first sync") }
    func unsubscribe() async throws {
        unsubscribeCount += 1
        await cleanup.wait()
    }
}

private actor ManualGate {
    private var entered = false
    private var released = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        entered = true
        let waiters = entryWaiters
        entryWaiters.removeAll()
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
        releaseWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}

private actor EntryCounter {
    private var operations: [AccountWorkspaceRuntimeStreamOperation] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func enter(_ operation: AccountWorkspaceRuntimeStreamOperation) {
        operations.append(operation)
        let ready = waiters.filter { operations.count >= $0.0 }
        waiters.removeAll { operations.count >= $0.0 }
        for (_, waiter) in ready { waiter.resume() }
    }

    func waitUntilEntered(_ count: Int) async {
        guard operations.count < count else { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    func values() -> [AccountWorkspaceRuntimeStreamOperation] {
        operations
    }
}
