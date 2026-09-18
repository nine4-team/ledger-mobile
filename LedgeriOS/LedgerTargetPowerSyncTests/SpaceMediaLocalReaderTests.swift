import Foundation
import LedgerTargetCore
import PowerSync
import Testing
@testable import LedgerTargetPowerSync

@Suite("Space media local reader", .serialized)
struct SpaceMediaLocalReaderTests {
    private let account = try! AccountID(validating: "space-account")
    private let principal = try! PrincipalID(validating: "space-principal")
    private let space = try! SpaceID(validating: "space")
    private func reader(_ db: any PowerSyncDatabaseProtocol, scope: SpaceCreationScope = .businessInventory) -> SpaceMediaLocalReader {
        .init(database: db,principalId: principal,accountId: account,spaceId: space,scope: scope)
    }

    @Test func partialEmptyAndComplete() async throws {
        try await withDatabase { db in
            #expect(try await !reader(db).read().isComplete)
            _ = try await db.execute(sql: "INSERT INTO space_media_sets(id,account_id,space_id,revision,expected_count) VALUES('set','space-account','space','1',0)",parameters: nil)
            #expect(try await reader(db).read().isComplete)
            _ = try await db.execute(sql: "UPDATE space_media_sets SET expected_count=1",parameters: nil)
            _ = try await db.execute(sql: "INSERT INTO space_media_references(id,account_id,space_id,attachment_id,set_revision,position,is_primary,file_name) VALUES('ref','space-account','space','object','1',0,1,'Plan.pdf')",parameters: nil)
            #expect(try await !reader(db).read().isComplete)
            try await addObject(db)
            let complete = try await reader(db).read()
            #expect(complete.isComplete && complete.attachments.count == 1)
            #expect(complete.printableImages.isEmpty)
            _ = try await db.execute(sql: "UPDATE space_media_sets SET revision='2',expected_count=0",parameters: nil)
            let current = try await reader(db).read()
            #expect(current.isComplete && current.attachments.isEmpty)
        }
    }

    @Test func scopeAndRevocation() async throws {
        try await withDatabase { db in
            await #expect(throws: DownloadedSpaceMedia.Failure.unavailable) {
                try await reader(db,scope: .project(ProjectID(validating: "other"))).read()
            }
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET state='removed'",parameters: nil)
            await #expect(throws: DownloadedSpaceMedia.Failure.unavailable) { try await reader(db).read() }
        }
    }

    @Test func archivedParentNeedsExactCurrentPlacement() async throws {
        try await withDatabase { db in
            _ = try await db.execute(sql: "UPDATE spike_spaces SET lifecycle='archived'",parameters: nil)
            await #expect(throws: DownloadedSpaceMedia.Failure.unavailable) { try await reader(db).read() }
            _ = try await db.execute(sql: "INSERT INTO spike_item_placements(id,account_id,item_id,space_id,scope_kind) VALUES('placement','space-account','item','space','business_inventory')",parameters: nil)
            #expect(try await !reader(db).read().isComplete)
            _ = try await db.execute(sql: "UPDATE spike_item_placements SET ended_at='2026-09-18'",parameters: nil)
            await #expect(throws: DownloadedSpaceMedia.Failure.unavailable) { try await reader(db).read() }
        }
    }

    @Test func encryptedReopen() async throws {
        try await withDatabase(reopen: { db in
            let value = try await reader(db).read()
            #expect(value.isComplete && value.attachments.first?.fileName == "Plan.pdf")
        }) { db in try await seed(db) }
    }

    @Test func watcherWithdrawsRevokedMedia() async throws {
        try await withDatabase { db in
            try await seed(db)
            let values = AsyncThrowingStream<DownloadedSpaceMedia?,Error>.makeStream()
            let task = Task {
                do {
                    try await reader(db).run { value in values.continuation.yield(value); return true }
                    values.continuation.finish()
                } catch { values.continuation.finish(throwing: error) }
            }
            let timeout = Task { try await Task.sleep(for: .seconds(10)); task.cancel() }
            defer { task.cancel(); timeout.cancel() }
            var iterator = values.stream.makeAsyncIterator()
            let first = try #require(try await iterator.next())
            #expect(first?.isComplete == true)
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET state='removed'",parameters: nil)
            var withdrawn = false
            while let value = try await iterator.next() { if value == nil { withdrawn = true } }
            try await task.value
            #expect(withdrawn)
        }
    }

    @Test func staleCatalogCannotReadCachedBytes() async throws {
        try await withDatabase { db in
            try await seed(db)
            let catalog = try await reader(db).read(), attachment = try #require(catalog.attachments.first)
            _ = try await db.execute(sql: "UPDATE space_media_sets SET revision='2',expected_count=0",parameters: nil)
            let cache = SpaceMediaTestCache { Issue.record("Stale reference reached cache"); return nil }
            await #expect(throws: DownloadedSpaceMedia.Failure.unavailable) {
                try await reader(db).load(catalog: catalog,attachment: attachment,cache: cache,download: nil,authorizeAccess: {})
            }
        }
    }

    @Test func cachedBytesRevalidateAfterAwait() async throws {
        try await withDatabase { db in
            try await seed(db)
            let catalog = try await reader(db).read()
            let attachment = try #require(catalog.attachments.first)
            let empty = SpaceMediaTestCache { nil }
            #expect(try await reader(db).load(catalog: catalog,attachment: attachment,
                cache: empty,download: nil,authorizeAccess: {}) == nil)
            let cache = SpaceMediaTestCache {
                _ = try await db.execute(sql: "UPDATE spike_account_memberships SET state='removed'",parameters: nil)
                return Data([1,2,3,4])
            }
            await #expect(throws: DownloadedSpaceMedia.Failure.unavailable) {
                try await reader(db).load(catalog: catalog,attachment: attachment,
                    cache: cache,download: nil,authorizeAccess: {})
            }
        }
    }

    private func addObject(_ db: any PowerSyncDatabaseProtocol) async throws {
        let hash = String(repeating: "a",count: 64)
        _ = try await db.execute(sql: "INSERT INTO item_image_objects(id,account_id,content_sha256,byte_count,media_type,storage_path) VALUES('object','space-account',?,'4','application/pdf',?)",
            parameters: [hash,"accounts/space-account/attachments/object/\(hash)"])
    }
    private func seed(_ db: any PowerSyncDatabaseProtocol) async throws {
        _ = try await db.execute(sql: "INSERT INTO space_media_sets(id,account_id,space_id,revision,expected_count) VALUES('set','space-account','space','1',1)",parameters: nil)
        _ = try await db.execute(sql: "INSERT INTO space_media_references(id,account_id,space_id,attachment_id,set_revision,position,is_primary,file_name) VALUES('ref','space-account','space','object','1',0,1,'Plan.pdf')",parameters: nil)
        try await addObject(db)
    }
    private func withDatabase(reopen: ((any PowerSyncDatabaseProtocol) async throws -> Void)? = nil,
                              _ body: (any PowerSyncDatabaseProtocol) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("space-media-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("ledger.sqlite").path
        let key = try LedgerPowerSyncEncryptionKey(hexadecimal: String(repeating: "4a",count: 32))
        let db = try LedgerPowerSyncDatabaseFactory.open(absolutePath: path,encryptionKey: key)
        do {
            _ = try await db.execute(sql: "INSERT INTO spike_spaces(id,account_id,scope_kind,display_name,lifecycle,revision) VALUES('space','space-account','business_inventory','Room','active','1')",parameters: nil)
            _ = try await db.execute(sql: "INSERT INTO spike_account_memberships(id,account_id,principal_id,state) VALUES('member','space-account','space-principal','active')",parameters: nil)
            try await body(db); try await db.close()
            if let reopen {
                let reopened = try LedgerPowerSyncDatabaseFactory.open(absolutePath: path,encryptionKey: key)
                do { try await reopen(reopened); try await reopened.close() }
                catch { try? await reopened.close(); throw error }
            }
        } catch { try? await db.close(); throw error }
    }
}

private struct SpaceMediaTestCache: DownloadedImageCaching {
    let read: @Sendable () async throws -> Data?
    func cachedDownloadedImage(_ reference: DownloadedMediaObjectReference) async throws -> Data? { try await read() }
    func cacheDownloadedImage(_ bytes: Data, reference: DownloadedMediaObjectReference) async throws {}
}
