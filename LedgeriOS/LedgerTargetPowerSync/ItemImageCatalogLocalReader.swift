import Foundation
import LedgerTargetCore
import PowerSync

enum ItemImageCatalogReadFailure: Error, Equatable { case unavailable }

struct ItemImageCatalogLocalReader: Sendable {
    let database: any PowerSyncDatabaseProtocol

    func read(accountId: AccountID, principalId: PrincipalID, itemId: ItemID) async throws -> DownloadedItemImageCatalog {
        try await database.readTransaction { transaction in
            let allowed = try transaction.get(sql: """
                SELECT EXISTS(SELECT 1 FROM spike_items item
                  JOIN spike_account_memberships member ON member.account_id=item.account_id
                  WHERE item.account_id=? AND item.id=? AND member.principal_id=? AND member.state='active') AS allowed
                """, parameters: [accountId.rawValue,itemId.rawValue,principalId.rawValue]) { try $0.getInt(name: "allowed") == 1 }
            guard allowed else { throw ItemImageCatalogReadFailure.unavailable }
            let markers = try transaction.getAll(sql: """
                SELECT revision,expected_count,typeof(expected_count) AS count_type FROM item_image_sets
                WHERE account_id=? AND item_id=? AND id=item_id
                """, parameters: [accountId.rawValue,itemId.rawValue]) { cursor in
                    (try cursor.getString(name: "revision"),try cursor.getInt(name: "expected_count"),try cursor.getString(name: "count_type"))
                }
            guard markers.count == 1, let marker = markers.first,
                  let revision = Int64(marker.0), revision>0, String(revision)==marker.0,
                  marker.1>=0,marker.2=="integer" else {
                return try .init(accountId: accountId,itemId: itemId,isComplete: false,images: [])
            }
            let projected = try transaction.getAll(sql: """
                SELECT reference.id,reference.set_revision,reference.position,reference.is_primary,
                  typeof(reference.position) AS position_type,typeof(reference.is_primary) AS primary_type,
                  object.id AS object_id,object.content_sha256,object.byte_count,object.media_type,object.storage_path
                FROM item_image_references reference LEFT JOIN item_image_objects object
                  ON object.account_id=reference.account_id AND object.id=reference.attachment_id
                WHERE reference.account_id=? AND reference.item_id=?
                ORDER BY reference.position,reference.id
                """, parameters: [accountId.rawValue,itemId.rawValue]) { cursor -> DownloadedItemImage? in
                    // Old cached revisions never become this gallery's evidence.
                    guard try cursor.getString(name: "set_revision") == marker.0 else { return nil }
                    do {
                        guard try cursor.getString(name: "position_type")=="integer",
                              try cursor.getString(name: "primary_type")=="integer" else { return nil }
                        let position = try cursor.getInt(name: "position"), primary = try cursor.getInt(name: "is_primary")
                        guard position>=0,primary==0 || primary==1 else { return nil }
                        let object = try DownloadedImageObjectReference(accountId: accountId,
                            attachmentId: cursor.getString(name: "object_id"),sha256: cursor.getString(name: "content_sha256"),
                            byteCount: cursor.getString(name: "byte_count"),mediaType: cursor.getString(name: "media_type"),
                            storagePath: cursor.getString(name: "storage_path"))
                        return try DownloadedItemImage(referenceId: EntityID(validating: cursor.getString(name: "id")),
                            itemId: itemId,object: object,position: position,isPrimary: primary==1,setRevision: revision)
                    } catch { return nil }
                }
            let images = projected.compactMap { $0 }
            guard Set(images.map(\.position)).count==images.count,
                  Set(images.map(\.object.attachmentId)).count==images.count,
                  images.filter(\.isPrimary).count<=1 else {
                return try .init(accountId: accountId,itemId: itemId,isComplete: false,images: [])
            }
            let complete = projected.count==images.count && images.count==marker.1 && images.enumerated().allSatisfy { $0.offset==$0.element.position }
            return try .init(accountId: accountId,itemId: itemId,isComplete: complete,images: images)
        }
    }

    func watch(accountId: AccountID, principalId: PrincipalID, itemId: ItemID)
        -> AsyncThrowingStream<DownloadedItemImageCatalog,Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(accountId: accountId,principalId: principalId,itemId: itemId) { value in
                        continuation.yield(value)
                        return true
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func run(accountId: AccountID, principalId: PrincipalID, itemId: ItemID,
             receive: @Sendable @escaping (DownloadedItemImageCatalog) async -> Bool) async throws {
        let changes = try database.watch(sql: """
                        SELECT EXISTS(SELECT 1 FROM spike_account_memberships WHERE account_id=?)
                        UNION ALL SELECT EXISTS(SELECT 1 FROM spike_items WHERE account_id=?)
                        UNION ALL SELECT EXISTS(SELECT 1 FROM item_image_sets WHERE account_id=?)
                        UNION ALL SELECT EXISTS(SELECT 1 FROM item_image_references WHERE account_id=?)
                        UNION ALL SELECT EXISTS(SELECT 1 FROM item_image_objects WHERE account_id=?)
                        """, parameters: Array(repeating: accountId.rawValue,count: 5)) { try $0.getInt(index: 0) }
        for try await _ in changes {
            try Task.checkCancellation()
            let value = try await read(accountId: accountId,principalId: principalId,itemId: itemId)
            guard await receive(value) else { return }
        }
    }
}
