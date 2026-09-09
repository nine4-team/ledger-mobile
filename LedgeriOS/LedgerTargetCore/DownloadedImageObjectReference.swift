import Foundation

public enum DownloadedImageObjectReferenceFailure: Error { case malformed }

/// Immutable byte identity within an Account. This is not authority to read an
/// Item or profile; callers must authorize their current reference separately.
public struct DownloadedImageObjectReference: Equatable, Sendable {
    public let accountId: AccountID
    public let attachmentId: AttachmentID
    public let contentSHA256: AttachmentContentSHA256
    public let byteCount: Int64
    public let mediaType: String
    public let storagePath: String

    public static func == (lhs: Self, rhs: Self) -> Bool {
        // Swift String equality folds canonical Unicode equivalents; storage
        // paths and persisted identifiers are exact byte identities instead.
        lhs.storagePath.utf8.elementsEqual(rhs.storagePath.utf8)
            && lhs.byteCount == rhs.byteCount && lhs.mediaType == rhs.mediaType
    }

    public init(accountId: AccountID, attachmentId: String, sha256: String,
                byteCount: String, mediaType: String, storagePath: String) throws {
        self.accountId = accountId
        self.attachmentId = try AttachmentID(validating: attachmentId)
        contentSHA256 = try AttachmentContentSHA256(validating: sha256)
        guard let count = Int64(byteCount), count > 0, String(count) == byteCount,
              storagePath.utf8.elementsEqual(
                "accounts/\(accountId.rawValue)/attachments/\(attachmentId)/\(sha256)".utf8),
              Self.isImageMediaType(mediaType) else { throw DownloadedImageObjectReferenceFailure.malformed }
        self.byteCount = count
        self.mediaType = mediaType
        self.storagePath = storagePath
    }

    private static func isImageMediaType(_ value: String) -> Bool {
        guard value.hasPrefix("image/") else { return false }
        let subtype = Array(value.utf8.dropFirst(6))
        func alphanumeric(_ byte: UInt8) -> Bool {
            (97...122).contains(byte) || (48...57).contains(byte)
        }
        guard (1...127).contains(subtype.count), let first = subtype.first,
              alphanumeric(first) else { return false }
        return subtype.allSatisfy { alphanumeric($0) || [43, 45, 46].contains($0) }
    }
}
