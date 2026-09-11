import Foundation
import LedgerTargetCore
import PowerSync

enum AccountBusinessProfileReadFailure: Error { case unavailable, malformed }

struct AccountBusinessLogoReference: Equatable, Sendable {
    let accountId: AccountID
    let attachmentId: AttachmentID
    let contentSHA256: AttachmentContentSHA256
    let byteCount: Int64
    let mediaType: String
    let storagePath: String

    init(accountId: AccountID, attachmentId: String, sha256: String,
         byteCount: String, mediaType: String, storagePath: String) throws {
        self.accountId = accountId
        self.attachmentId = try AttachmentID(validating: attachmentId)
        contentSHA256 = try AttachmentContentSHA256(validating: sha256)
        guard let count = Int64(byteCount), count > 0, String(count) == byteCount,
              storagePath.utf8.elementsEqual(
                "accounts/\(accountId.rawValue)/attachments/\(attachmentId)/\(sha256)".utf8),
              !mediaType.isEmpty else { throw AccountBusinessProfileReadFailure.malformed }
        self.byteCount = count
        self.mediaType = mediaType
        self.storagePath = storagePath
    }
}

struct AccountBusinessProfileRow: Sendable {
    let accountId: AccountID
    let name: AccountDisplayName
    let logo: AccountBusinessLogoReference?
}

/// A missing profile row is unknown evidence, never proof that no logo exists.
/// No subscription or remote request is created by this local query.
struct AccountBusinessProfileLocalReader: Sendable {
    let database: any PowerSyncDatabaseProtocol

    func read(accountId: AccountID, principalId: PrincipalID) async throws -> AccountBusinessProfileRow {
        let rows = try await database.getAll(sql: Self.sql,
            parameters: [accountId.rawValue, principalId.rawValue], mapper: Self.row)
        guard rows.count == 1 else { throw AccountBusinessProfileReadFailure.unavailable }
        return rows[0]
    }

    func watch(accountId: AccountID, principalId: PrincipalID)
        throws -> AsyncThrowingStream<[AccountBusinessProfileRow], Error> {
        try database.watch(sql: Self.sql,
            parameters: [accountId.rawValue, principalId.rawValue], mapper: Self.row)
    }

    static func row(_ cursor: any SqlCursor) throws -> AccountBusinessProfileRow {
        let account = try AccountID(validating: cursor.getString(name: "account_id"))
        let attachment = try cursor.getStringOptional(name: "logo_attachment_id")
        let hash = try cursor.getStringOptional(name: "logo_content_sha256")
        let count = try cursor.getStringOptional(name: "logo_byte_count")
        let type = try cursor.getStringOptional(name: "logo_media_type")
        let path = try cursor.getStringOptional(name: "logo_storage_path")
        let fields = [attachment, hash, count, type, path]
        let logo: AccountBusinessLogoReference?
        if fields.allSatisfy({ $0 == nil }) { logo = nil }
        else if let attachment, let hash, let count, let type, let path {
            logo = try AccountBusinessLogoReference(accountId: account, attachmentId: attachment,
                sha256: hash, byteCount: count, mediaType: type, storagePath: path)
        } else { throw AccountBusinessProfileReadFailure.malformed }
        return try AccountBusinessProfileRow(accountId: account,
            name: AccountDisplayName(validating: cursor.getString(name: "display_name")), logo: logo)
    }

    static let sql = """
        SELECT profile.account_id, account.display_name,
               profile.logo_attachment_id, profile.logo_content_sha256,
               profile.logo_byte_count, profile.logo_media_type, profile.logo_storage_path
        FROM spike_account_business_profiles AS profile
        JOIN spike_accounts AS account ON account.id = profile.account_id
        WHERE profile.account_id = ? AND profile.id = profile.account_id
          AND EXISTS (
            SELECT 1 FROM spike_account_memberships AS membership
            WHERE membership.account_id = profile.account_id
              AND membership.principal_id = ? AND membership.state = 'active'
          )
        """
}
