import Foundation

/// Read-only Space relationships. Byte identity and storage remain shared with
/// Item and Transaction media; a catalog is not permission to read cached bytes.
public struct DownloadedSpaceMedia: Equatable, Sendable {
    public enum Failure: Error, Equatable { case unavailable, invalidEvidence }

    public struct Attachment: Equatable, Sendable, Identifiable {
        public let id: EntityID
        public let object: DownloadedMediaObjectReference
        public let position: Int
        public let isPrimary: Bool
        public let fileName: String?

        public init(id: EntityID, object: DownloadedMediaObjectReference, position: Int,
                    isPrimary: Bool, fileName: String? = nil) throws {
            guard position >= 0 else { throw Failure.invalidEvidence }
            self.id = id; self.object = object; self.position = position
            self.isPrimary = isPrimary; self.fileName = fileName
        }

        public var isImage: Bool { object.mediaType != "application/pdf" }
    }

    public let accountId: AccountID
    public let spaceId: SpaceID
    public let scope: SpaceCreationScope
    public let revision: Int64?
    public let isComplete: Bool
    public let attachments: [Attachment]

    /// Missing metadata stays unknown, never "No media". Partial reference sets
    /// may have gaps, but a complete set must have contiguous ordering.
    public init(accountId: AccountID, spaceId: SpaceID, scope: SpaceCreationScope,
                revision: Int64?, isComplete: Bool, attachments: [Attachment]) throws {
        guard revision.map({ $0 > 0 }) ?? (!isComplete && attachments.isEmpty),
              attachments.allSatisfy({ $0.object.accountId == accountId }),
              Set(attachments.map { Array($0.id.rawValue.utf8) }).count == attachments.count,
              Set(attachments.map { Array($0.object.attachmentId.rawValue.utf8) }).count == attachments.count,
              Set(attachments.map(\.position)).count == attachments.count,
              attachments.filter(\.isPrimary).count <= 1 else { throw Failure.invalidEvidence }
        let ordered = attachments.sorted { $0.position < $1.position }
        guard !isComplete || ordered.enumerated().allSatisfy({ $0.offset == $0.element.position }) else {
            throw Failure.invalidEvidence
        }
        self.accountId = accountId; self.spaceId = spaceId; self.scope = scope
        self.revision = revision; self.isComplete = isComplete; self.attachments = ordered
    }

    /// Only published references enter this read-only catalog. The printer must
    /// still resolve every image's bytes and revalidate access before handoff.
    public var printableImages: [Attachment] { attachments.filter(\.isImage) }

    public func retains(_ attachment: Attachment, from previous: Self) -> Bool {
        revision != nil && revision == previous.revision
            && accountId == previous.accountId && spaceId == previous.spaceId && scope == previous.scope
            && previous.attachments.contains(attachment) && attachments.contains(attachment)
    }
}

public protocol DownloadedSpaceMediaReading: Sendable {
    /// Nil withdraws media on access loss. Unknown metadata is a non-complete
    /// catalog, not nil. The runtime owns watcher cancellation.
    func watchDownloadedSpaceMedia(accountId: AccountID, spaceId: SpaceID, scope: SpaceCreationScope)
        -> AsyncThrowingStream<DownloadedSpaceMedia?, Error>
    func readDownloadedSpaceMedia(accountId: AccountID, spaceId: SpaceID, scope: SpaceCreationScope)
        async throws -> DownloadedSpaceMedia
    /// Revalidate exact scope, revision and reference around every await. Nil
    /// means missing bytes, not a blank image or successful print.
    func loadDownloadedSpaceMedia(catalog: DownloadedSpaceMedia,
        attachment: DownloadedSpaceMedia.Attachment, allowDownload: Bool) async throws -> Data?
}
