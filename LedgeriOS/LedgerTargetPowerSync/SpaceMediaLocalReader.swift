import Foundation
import LedgerTargetCore
import PowerSync

struct SpaceMediaLocalReader: Sendable {
    let database: any PowerSyncDatabaseProtocol
    let principalId: PrincipalID
    let accountId: AccountID
    let spaceId: SpaceID
    let scope: SpaceCreationScope

    func read() async throws -> DownloadedSpaceMedia {
        let kind: String
        let project: String?
        switch scope {
        case .businessInventory: kind = "business_inventory"; project = nil
        case .project(let id): kind = "project"; project = id.rawValue
        }
        return try await database.readTransaction { transaction in
            let allowed = try transaction.get(sql: """
                SELECT EXISTS(SELECT 1 FROM spike_spaces space
                  JOIN spike_account_memberships member ON member.account_id=space.account_id
                  WHERE space.account_id=? AND space.id=? AND space.scope_kind=? AND space.project_id IS ?
                    AND member.principal_id=? AND member.state='active'
                    AND (space.lifecycle='active' OR (space.lifecycle='archived' AND EXISTS(
                      SELECT 1 FROM spike_item_placements placement WHERE placement.account_id=space.account_id
                        AND placement.space_id=space.id AND placement.scope_kind=space.scope_kind
                        AND placement.project_id IS space.project_id AND placement.ended_at IS NULL)))) AS allowed
                """, parameters: [accountId.rawValue,spaceId.rawValue,kind,project,principalId.rawValue]) {
                    try $0.getInt(name: "allowed") == 1
                }
            guard allowed else { throw DownloadedSpaceMedia.Failure.unavailable }
            func catalog(_ revision: Int64? = nil, complete: Bool = false,
                         attachments: [DownloadedSpaceMedia.Attachment] = []) throws -> DownloadedSpaceMedia {
                try .init(accountId: accountId, spaceId: spaceId, scope: scope,
                          revision: revision, isComplete: complete, attachments: attachments)
            }
            let markers = try transaction.getAll(sql: """
                SELECT revision,expected_count,typeof(expected_count) AS count_type FROM space_media_sets
                WHERE account_id=? AND space_id=?
                """, parameters: [accountId.rawValue,spaceId.rawValue]) {
                    (try $0.getString(name: "revision"),try $0.getInt(name: "expected_count"),try $0.getString(name: "count_type"))
                }
            guard markers.count == 1, let marker = markers.first, let revision = Int64(marker.0),
                  revision > 0, String(revision) == marker.0, marker.1 >= 0, marker.2 == "integer" else {
                return try catalog()
            }
            let rows = try transaction.getAll(sql: """
                SELECT reference.id,reference.position,reference.is_primary,reference.file_name,
                  typeof(reference.position) AS position_type,typeof(reference.is_primary) AS primary_type,
                  object.id AS object_id,object.content_sha256,object.byte_count,object.media_type,object.storage_path
                FROM space_media_references reference LEFT JOIN item_image_objects object
                  ON object.account_id=reference.account_id AND object.id=reference.attachment_id
                WHERE reference.account_id=? AND reference.space_id=? AND reference.set_revision=?
                ORDER BY reference.position,reference.id
                """, parameters: [accountId.rawValue,spaceId.rawValue,marker.0]) { cursor -> DownloadedSpaceMedia.Attachment? in
                    do {
                        guard try cursor.getString(name: "position_type") == "integer",
                              try cursor.getString(name: "primary_type") == "integer" else { return nil }
                        let primary = try cursor.getInt(name: "is_primary")
                        guard primary == 0 || primary == 1 else { return nil }
                        let mediaType = try cursor.getString(name: "media_type")
                        let object = try DownloadedMediaObjectReference(accountId: accountId,
                            attachmentId: cursor.getString(name: "object_id"),sha256: cursor.getString(name: "content_sha256"),
                            byteCount: cursor.getString(name: "byte_count"),mediaType: mediaType,
                            storagePath: cursor.getString(name: "storage_path"),kind: mediaType == "application/pdf" ? .pdf : .image)
                        return try .init(id: EntityID(validating: cursor.getString(name: "id")),object: object,
                            position: cursor.getInt(name: "position"),isPrimary: primary == 1,
                            fileName: cursor.getStringOptional(name: "file_name"))
                    } catch { return nil }
                }
            let attachments = rows.compactMap { $0 }
            let complete = rows.count == attachments.count && attachments.count == marker.1
                && attachments.enumerated().allSatisfy { $0.offset == $0.element.position }
            do { return try catalog(revision,complete: complete,attachments: attachments) }
            catch { return try catalog(revision) }
        }
    }

    func watch(receive: @Sendable @escaping (DownloadedSpaceMedia?) async -> Bool) async throws {
        try await withOwnedSyncStreamWatch(subscribe: {
            try await database.syncStream(name: "space_media", params: [
                "account_id": .string(accountId.rawValue), "space_id": .string(spaceId.rawValue)
            ]).subscribe()
        }, observe: { try await run(receive: receive) })
    }

    func run(receive: @Sendable @escaping (DownloadedSpaceMedia?) async -> Bool) async throws {
        let changes = try database.watch(sql: """
            SELECT EXISTS(SELECT 1 FROM spike_account_memberships WHERE account_id=?)
            UNION ALL SELECT EXISTS(SELECT 1 FROM spike_spaces WHERE account_id=?)
            UNION ALL SELECT EXISTS(SELECT 1 FROM spike_item_placements WHERE account_id=?)
            UNION ALL SELECT EXISTS(SELECT 1 FROM space_media_sets WHERE account_id=?)
            UNION ALL SELECT EXISTS(SELECT 1 FROM space_media_references WHERE account_id=?)
            UNION ALL SELECT EXISTS(SELECT 1 FROM item_image_objects WHERE account_id=?)
            """, parameters: Array(repeating: accountId.rawValue,count: 6)) { try $0.getInt(index: 0) }
        for try await _ in changes {
            try Task.checkCancellation()
            do { guard await receive(try await read()) else { return } }
            catch DownloadedSpaceMedia.Failure.unavailable { _ = await receive(nil); return }
        }
    }

    func load(catalog: DownloadedSpaceMedia, attachment: DownloadedSpaceMedia.Attachment,
              cache: any DownloadedImageCaching,
              download: (@Sendable (DownloadedMediaObjectReference) async throws -> Data)?,
              authorizeAccess: @Sendable () async throws -> Void) async throws -> Data? {
        guard catalog.accountId == accountId, catalog.spaceId == spaceId, catalog.scope == scope,
              catalog.revision != nil, catalog.attachments.contains(attachment) else {
            throw DownloadedSpaceMedia.Failure.invalidEvidence
        }
        return try await loadAuthorizedDownloadedMedia(attachment.object,cache: cache,download: download) {
            try Task.checkCancellation()
            try await authorizeAccess()
            guard try await read().retains(attachment,from: catalog) else {
                throw DownloadedSpaceMedia.Failure.unavailable
            }
            try await authorizeAccess()
        }
    }
}
