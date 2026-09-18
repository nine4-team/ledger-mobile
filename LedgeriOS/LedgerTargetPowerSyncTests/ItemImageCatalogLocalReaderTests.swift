import Foundation
import LedgerTargetCore
import PowerSync
import Testing
@testable import LedgerTargetPowerSync

@Suite("Downloaded Item image catalog", .serialized)
struct ItemImageCatalogLocalReaderTests {
    let account = try! AccountID(validating: "image-account")
    let principal = try! PrincipalID(validating: "image-principal")
    let item = try! ItemID(validating: "image-item")

    @Test("Image subscriptions follow downloaded Project moves, share SDK scope and drain offline")
    func subscriptionRouting() async throws {
        try await withDatabase { db in
            let lifetime = AsyncStream<Void>.makeStream()
            let first = Task {
                try await withOwnedItemImageStreamWatch(database: db, accountId: account.rawValue, itemId: item.rawValue) {
                    for await _ in lifetime.stream {}
                }
            }
            do {
                try await awaitSubscription(db, name: "item_images", field: "item_id", value: item.rawValue)
                _ = try await db.execute(sql: """
                    INSERT INTO spike_item_placements(id,account_id,item_id,scope_kind,project_id)
                    VALUES('image-placement','image-account','image-item','project','project-a')
                    """, parameters: nil)
                try await awaitSubscription(db, name: "project_item_images", field: "project_id", value: "project-a")
                let secondLifetime = AsyncStream<Void>.makeStream()
                let second = Task {
                    try await withOwnedItemImageStreamWatch(database: db, accountId: account.rawValue, itemId: item.rawValue) {
                        for await _ in secondLifetime.stream {}
                    }
                }
                do {
                    _ = try await db.execute(sql: "UPDATE spike_item_placements SET project_id='project-b' WHERE id='image-placement'", parameters: nil)
                    try await awaitSubscription(db, name: "project_item_images", field: "project_id", value: "project-b")
                    #expect(db.currentStatus.syncStreams?.filter {
                        $0.subscription.name == "project_item_images" && $0.subscription.parameters?["project_id"] == .string("project-b")
                    }.count == 1)
                    second.cancel(); secondLifetime.continuation.finish()
                    do { try await second.value } catch is CancellationError {}
                } catch {
                    second.cancel(); secondLifetime.continuation.finish()
                    _ = try? await second.value
                    throw error
                }
                _ = try await db.execute(sql: "UPDATE spike_item_placements SET ended_at='2026-09-18' WHERE id='image-placement'", parameters: nil)
                try await awaitSubscription(db, name: "item_images", field: "item_id", value: item.rawValue)
                first.cancel(); lifetime.continuation.finish()
                do { try await first.value } catch is CancellationError {}
            } catch {
                first.cancel(); lifetime.continuation.finish()
                _ = try? await first.value
                throw error
            }
        }
    }

    private func awaitSubscription(_ db: any PowerSyncDatabaseProtocol, name: String, field: String, value: String) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for await status in db.currentStatus.asFlow() {
                    if status.syncStreams?.contains(where: {
                        $0.subscription.name == name && $0.subscription.parameters?[field] == .string(value)
                    }) == true { return }
                }
                throw CancellationError()
            }
            group.addTask { try await Task.sleep(for: .seconds(5)); throw CancellationError() }
            defer { group.cancelAll() }
            try await group.next()
        }
    }

    @Test("Absent marker is unknown; explicit zero is empty; object arrival completes exact set")
    func completeness() async throws {
        try await withDatabase { db in
            #expect(try await read(db).isComplete == false)
            _ = try await db.execute(sql: "INSERT INTO item_image_sets(id,account_id,item_id,revision,expected_count) VALUES('image-item','image-account','image-item','1',0)", parameters: nil)
            #expect(try await read(db).isComplete)
            let empty = try await read(db)
            #expect(empty.revision == 1)
            _ = try await db.execute(sql: "UPDATE item_image_sets SET revision='2'", parameters: nil)
            let changedEmpty = try await read(db)
            #expect(changedEmpty.isComplete && changedEmpty.images.isEmpty)
            #expect(changedEmpty.revision == 2)
            #expect(changedEmpty != empty)
            _ = try await db.execute(sql: "UPDATE item_image_sets SET revision='1'", parameters: nil)
            _ = try await db.execute(sql: "UPDATE item_image_sets SET expected_count=1", parameters: nil)
            _ = try await db.execute(sql: "INSERT INTO item_image_references(id,account_id,item_id,attachment_id,set_revision,position,is_primary) VALUES('reference','image-account','image-item','object','1',0,1)", parameters: nil)
            #expect(try await read(db).isComplete == false)
            try await addObject(db)
            let complete = try await read(db)
            #expect(complete.isComplete && complete.images.count == 1)
            #expect(complete.images.first?.object.attachmentId.rawValue == "object")
            _ = try await db.execute(sql: "UPDATE item_image_sets SET revision='2'", parameters: nil)
            #expect(try await read(db).isComplete == false)
            #expect(try await read(db).images.isEmpty)
        }
    }

    @Test("Malformed duplicates, wrong object scope and revoked membership fail closed")
    func integrityAndScope() async throws {
        try await withDatabase { db in
            try await seed(db)
            _ = try await db.execute(sql: "INSERT INTO item_image_references(id,account_id,item_id,attachment_id,set_revision,position,is_primary) VALUES('duplicate','image-account','image-item','object','1',0,1)", parameters: nil)
            #expect(try await read(db).images.isEmpty)
            #expect(try await read(db).isComplete == false)
            _ = try await db.execute(sql: "DELETE FROM item_image_references WHERE id='duplicate'", parameters: nil)
            _ = try await db.execute(sql: "UPDATE item_image_objects SET account_id='foreign'", parameters: nil)
            #expect(try await read(db).images.isEmpty)
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET state='removed'", parameters: nil)
            await #expect(throws: ItemImageCatalogReadFailure.unavailable) { try await read(db) }
        }
    }

    @Test("Catalog survives encrypted restart and current Item identity is mandatory")
    func restart() async throws {
        try await withDatabase(reopen: { db in
            #expect(try await read(db).isComplete)
            await #expect(throws: ItemImageCatalogReadFailure.unavailable) {
                try await ItemImageCatalogLocalReader(database: db).read(accountId: account,principalId: principal,
                    itemId: ItemID(validating: "other-item"))
            }
            _ = try await db.execute(sql: "DELETE FROM spike_items", parameters: nil)
            await #expect(throws: ItemImageCatalogReadFailure.unavailable) { try await read(db) }
        }) { db in try await seed(db) }
    }

    @Test("Reactive reader rereads object arrival and removal and terminates after revocation")
    func reactive() async throws {
        try await withDatabase { db in
            let values = AsyncThrowingStream<DownloadedItemImageCatalog,Error>.makeStream()
            let task = Task {
                do {
                    try await ItemImageCatalogLocalReader(database: db).run(accountId: account,principalId: principal,itemId: item) {
                        values.continuation.yield($0);return true
                    }
                    values.continuation.finish()
                } catch { values.continuation.finish(throwing: error) }
            }
            let timeout = Task { try await Task.sleep(for: .seconds(10));task.cancel() }
            defer { task.cancel();timeout.cancel() }
            var iterator = values.stream.makeAsyncIterator()
            #expect(try await iterator.next()?.isComplete == false)
            try await seed(db)
            while try #require(try await iterator.next()).isComplete == false {}
            _ = try await db.execute(sql: "DELETE FROM item_image_objects", parameters: nil)
            while try #require(try await iterator.next()).isComplete {}
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET state='removed'", parameters: nil)
            await #expect(throws: ItemImageCatalogReadFailure.unavailable) { while try await iterator.next() != nil {} }
            await task.value
        }
    }

    func read(_ db: any PowerSyncDatabaseProtocol) async throws -> DownloadedItemImageCatalog {
        try await ItemImageCatalogLocalReader(database: db).read(accountId: account,principalId: principal,itemId: item)
    }
    @Test("Item gallery observes its separate attachment database and drains both watches")
    func separateCaptureDatabase() async throws {
        try await withDatabase { db in
            try await seed(db)
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("item-capture-watch-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let attachments = try AttachmentCapturePowerSyncDatabaseFactory.open(
                absolutePath: root.appendingPathComponent("attachments.sqlite").path,
                encryptionKey: .init(hexadecimal: String(repeating: "4a", count: 32)))
            do {
                let values = AsyncThrowingStream<Bool,Error>.makeStream()
                let task = Task {
                    do {
                        try await ItemImageCatalogLocalReader(database: db).run(accountId: account,
                            principalId: principal, itemId: item, attachmentDatabase: attachments) {
                            guard $0.isComplete else { return false }
                            do {
                                let present = try await attachments.get(sql:
                                    "SELECT EXISTS(SELECT 1 FROM local_attachment_durability_queue WHERE id='pending') AS present",
                                    parameters: nil) { try $0.getInt(name: "present") == 1 }
                                values.continuation.yield(present)
                                return true
                            } catch { values.continuation.finish(throwing: error); return false }
                        }
                        values.continuation.finish()
                    } catch { values.continuation.finish(throwing: error) }
                }
                let timeout = Task { try await Task.sleep(for: .seconds(10)); task.cancel() }
                defer { task.cancel(); timeout.cancel() }
                var iterator = values.stream.makeAsyncIterator()
                #expect(try await iterator.next() == false)
                _ = try await attachments.execute(sql: """
                    INSERT INTO local_attachment_durability_queue(id,account_id,parent_kind,parent_id,state)
                    VALUES('pending','image-account','item','image-item','pending')
                    """, parameters: nil)
                while try #require(try await iterator.next()) == false {}
                task.cancel()
                await task.value
                try await attachments.close()
            } catch { try? await attachments.close(); throw error }
        }
    }
    @Test("Explicit derivative arrival does not change original completeness; malformed and foreign links fail closed")
    func thumbnails() async throws {
        try await withDatabase { db in
            try await seed(db)
            #expect(try await read(db).images.first?.thumbnail == nil)
            let hash = String(repeating: "b",count: 64)
            _ = try await db.execute(sql: "INSERT INTO item_card_thumbnails(id,account_id,original_attachment_id,thumbnail_attachment_id,recipe,pixel_width,pixel_height) VALUES('small-link','image-account','object','small','item-card-300-jpeg-v1',300,200)",parameters: nil)
            #expect(try await read(db).isComplete)
            #expect(try await read(db).images.first?.thumbnail == nil)
            _ = try await db.execute(sql: "INSERT INTO item_image_objects(id,account_id,content_sha256,byte_count,media_type,storage_path) VALUES('small','image-account',?,'100','image/jpeg',?)",
                parameters: [hash,"accounts/image-account/attachments/small/\(hash)"])
            let image = try #require(try await read(db).primaryImage)
            #expect(image.object.attachmentId.rawValue == "object")
            #expect(image.thumbnail?.object.attachmentId.rawValue == "small")
            #expect(image.thumbnail?.width == 300)
            for mutation in ["UPDATE item_card_thumbnails SET pixel_width=301",
                             "UPDATE item_card_thumbnails SET pixel_width=300,account_id='foreign'",
                             "UPDATE item_card_thumbnails SET account_id='image-account',original_attachment_id='another'",
                             "UPDATE item_card_thumbnails SET original_attachment_id='object'; UPDATE item_image_objects SET media_type='image/png' WHERE id='small'"] {
                for sql in mutation.components(separatedBy: "; ") {
                    _ = try await db.execute(sql: sql,parameters: nil)
                }
                let catalog = try await read(db)
                #expect(catalog.isComplete)
                #expect(catalog.primaryImage?.thumbnail == nil)
            }
        }
    }
    func addObject(_ db: any PowerSyncDatabaseProtocol) async throws {
        let hash = String(repeating: "a",count: 64)
        _ = try await db.execute(sql: "INSERT INTO item_image_objects(id,account_id,content_sha256,byte_count,media_type,storage_path) VALUES('object','image-account',?,'123','image/png',?)",
            parameters: [hash,"accounts/image-account/attachments/object/\(hash)"])
    }
    func seed(_ db: any PowerSyncDatabaseProtocol) async throws {
        _ = try await db.execute(sql: "INSERT INTO item_image_sets(id,account_id,item_id,revision,expected_count) VALUES('image-item','image-account','image-item','1',1)", parameters: nil)
        _ = try await db.execute(sql: "INSERT INTO item_image_references(id,account_id,item_id,attachment_id,set_revision,position,is_primary) VALUES('reference','image-account','image-item','object','1',0,1)", parameters: nil)
        try await addObject(db)
    }
    func withDatabase(reopen: ((any PowerSyncDatabaseProtocol) async throws -> Void)? = nil,
                      _ body: (any PowerSyncDatabaseProtocol) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("item-images-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("ledger.sqlite").path
        let key = try LedgerPowerSyncEncryptionKey(hexadecimal: String(repeating: "4a",count: 32))
        let db = try LedgerPowerSyncDatabaseFactory.open(absolutePath: path,encryptionKey: key)
        do {
            _ = try await db.execute(sql: "INSERT INTO spike_items(id,account_id,description,revision) VALUES('image-item','image-account','Image Item',1)", parameters: nil)
            _ = try await db.execute(sql: "INSERT INTO spike_account_memberships(id,account_id,principal_id,state) VALUES('member','image-account','image-principal','active')", parameters: nil)
            try await body(db);try await db.close()
            if let reopen {
                let reopened = try LedgerPowerSyncDatabaseFactory.open(absolutePath: path,encryptionKey: key)
                do { try await reopen(reopened);try await reopened.close() }
                catch { try? await reopened.close();throw error }
            }
        } catch { try? await db.close();throw error }
    }
}
