import Foundation

public enum DownloadedItemImageFailure: Error, Equatable, Sendable {
    case malformed, scopeMismatch, unavailable
}

/// An explicitly linked small derivative; never an inferred Storage filename.
public struct DownloadedItemCardThumbnail: Equatable, Sendable {
    public let original: DownloadedImageObjectReference
    public let object: DownloadedImageObjectReference
    public let width: Int
    public let height: Int

    public init(original: DownloadedImageObjectReference, object: DownloadedImageObjectReference,
                recipe: String, width: Int, height: Int) throws {
        guard recipe == "item-card-300-jpeg-v1", object.mediaType == "image/jpeg",
              (1...300).contains(width), (1...300).contains(height),
              original.accountId.rawValue.utf8.elementsEqual(object.accountId.rawValue.utf8),
              !original.attachmentId.rawValue.utf8.elementsEqual(object.attachmentId.rawValue.utf8) else {
            throw DownloadedItemImageFailure.malformed
        }
        self.original = original; self.object = object; self.width = width; self.height = height
    }
}

/// A live Item reference owns ordering and primary choice. The protected object
/// is shared independently; reference identity is never a signed URL.
public struct DownloadedItemImage: Equatable, Sendable, Identifiable {
    public let referenceId: EntityID
    public var id: EntityID { referenceId }
    public let itemId: ItemID
    public let object: DownloadedImageObjectReference
    public let position: Int
    public let isPrimary: Bool
    public let setRevision: Int64
    public let thumbnail: DownloadedItemCardThumbnail?
    public let localReceipt: AttachmentLocalDurabilityReceipt?

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.referenceId.rawValue.utf8.elementsEqual(rhs.referenceId.rawValue.utf8)
            && lhs.itemId.rawValue.utf8.elementsEqual(rhs.itemId.rawValue.utf8)
            && lhs.object == rhs.object && lhs.position == rhs.position
            && lhs.isPrimary == rhs.isPrimary && lhs.setRevision == rhs.setRevision
            && lhs.thumbnail == rhs.thumbnail && lhs.localReceipt == rhs.localReceipt
    }

    public init(referenceId: EntityID, itemId: ItemID, object: DownloadedImageObjectReference,
                position: Int, isPrimary: Bool, setRevision: Int64,
                thumbnail: DownloadedItemCardThumbnail? = nil,
                localReceipt: AttachmentLocalDurabilityReceipt? = nil) throws {
        guard position >= 0, setRevision > 0 else { throw DownloadedItemImageFailure.malformed }
        if let receipt = localReceipt {
            guard receipt.scope.parent.kind == .item,
                  receipt.scope.parent.id.rawValue.utf8.elementsEqual(itemId.rawValue.utf8),
                  receipt.scope.accountId == object.accountId,
                  receipt.attachmentId == object.attachmentId,
                  receipt.contentSHA256 == object.contentSHA256,
                  receipt.byteCount == UInt64(object.byteCount),
                  receipt.metadata?.mediaType == object.mediaType,
                  receipt.metadata?.transactionSection == nil,
                  receipt.metadata?.placement != nil else {
                throw DownloadedItemImageFailure.scopeMismatch
            }
        }
        if let thumbnail {
            guard thumbnail.original == object,
                  thumbnail.object.accountId.rawValue.utf8.elementsEqual(object.accountId.rawValue.utf8),
                  !thumbnail.object.attachmentId.rawValue.utf8.elementsEqual(object.attachmentId.rawValue.utf8) else {
                throw DownloadedItemImageFailure.scopeMismatch
            }
        }
        self.referenceId = referenceId; self.itemId = itemId; self.object = object
        self.position = position; self.isPrimary = isPrimary; self.setRevision = setRevision
        self.thumbnail = thumbnail
        self.localReceipt = localReceipt
    }
}

/// Complete empty metadata means No Image. Missing/incomplete metadata does not.
public struct DownloadedItemImageCatalog: Equatable, Sendable {
    public let accountId: AccountID
    public let itemId: ItemID
    public let isComplete: Bool
    public let revision: Int64?
    public let images: [DownloadedItemImage]
    public let localUploadRejections: [AttachmentID: String]

    public init(accountId: AccountID, itemId: ItemID, isComplete: Bool,
                images: [DownloadedItemImage], revision: Int64? = nil,
                localUploadRejections: [AttachmentID: String] = [:]) throws {
        let resolvedRevision = revision ?? images.first?.setRevision
        guard resolvedRevision.map({ $0 > 0 }) ?? true,
              images.allSatisfy({ $0.setRevision == resolvedRevision }) else {
            throw DownloadedItemImageFailure.malformed
        }
        guard images.allSatisfy({ $0.itemId.rawValue.utf8.elementsEqual(itemId.rawValue.utf8)
            && $0.object.accountId.rawValue.utf8.elementsEqual(accountId.rawValue.utf8) }) else {
            throw DownloadedItemImageFailure.scopeMismatch
        }
        guard Set(images.map { Array($0.referenceId.rawValue.utf8) }).count == images.count,
              Set(images.map(\.position)).count == images.count,
              images.filter(\.isPrimary).count <= 1,
              Set(images.map(\.setRevision)).count <= 1 else {
            throw DownloadedItemImageFailure.malformed
        }
        self.accountId = accountId; self.itemId = itemId; self.isComplete = isComplete
        self.revision = resolvedRevision
        self.localUploadRejections = localUploadRejections.filter { id, _ in
            images.contains { $0.object.attachmentId == id && $0.localReceipt != nil }
        }
        self.images = images.sorted {
            $0.position == $1.position ? $0.referenceId.rawValue < $1.referenceId.rawValue : $0.position < $1.position
        }
    }

    public var primaryImage: DownloadedItemImage? {
        images.first(where: \.isPrimary) ?? images.first
    }

    /// Overlay only this workspace's durable captures. A matching synchronized
    /// original replaces its pending presentation without changing identity.
    public func includingPending(_ receipts: [AttachmentLocalDurabilityReceipt],
                                 scope: AttachmentCaptureScope,
                                 rejections: [AttachmentID: String] = [:]) throws -> Self {
        guard scope.accountId == accountId, scope.parent.kind == .item,
              scope.parent.id.rawValue.utf8.elementsEqual(itemId.rawValue.utf8) else {
            throw DownloadedItemImageFailure.scopeMismatch
        }
        guard let revision else { return self }
        var combined = images
        let pending = receipts.filter { $0.scope == scope }.sorted {
            let left = $0.metadata?.placement?.localPosition ?? UInt32.max
            let right = $1.metadata?.placement?.localPosition ?? UInt32.max
            return left == right ? $0.attachmentId.rawValue < $1.attachmentId.rawValue : left < right
        }
        for receipt in pending {
            guard let metadata = receipt.metadata, let placement = metadata.placement else {
                throw DownloadedItemImageFailure.malformed
            }
            if let existing = combined.first(where: { $0.object.attachmentId == receipt.attachmentId }) {
                guard existing.object.contentSHA256 == receipt.contentSHA256,
                      UInt64(existing.object.byteCount) == receipt.byteCount,
                      existing.object.mediaType == metadata.mediaType else {
                    throw DownloadedItemImageFailure.malformed
                }
                continue
            }
            let object = try DownloadedImageObjectReference(accountId: accountId,
                attachmentId: receipt.attachmentId.rawValue, sha256: receipt.contentSHA256.rawValue,
                byteCount: String(receipt.byteCount), mediaType: metadata.mediaType,
                storagePath: "accounts/\(accountId.rawValue)/attachments/\(receipt.attachmentId.rawValue)/\(receipt.contentSHA256.rawValue)")
            let index = min(Int(placement.localPosition), combined.count)
            combined.insert(try .init(referenceId: .init(validating: receipt.attachmentId.rawValue),
                itemId: itemId, object: object, position: index,
                isPrimary: !combined.contains(where: \.isPrimary) && placement.makePrimaryIfEmpty, setRevision: revision,
                localReceipt: receipt), at: index)
        }
        // Presentation positions include pending originals. Stored authoritative
        // positions remain untouched; byte authorization rebuilds this same view.
        combined = try combined.enumerated().map { index, image in
            try .init(referenceId: image.referenceId, itemId: image.itemId, object: image.object,
                position: index, isPrimary: image.isPrimary, setRevision: image.setRevision,
                thumbnail: image.thumbnail, localReceipt: image.localReceipt)
        }
        return try .init(accountId: accountId, itemId: itemId, isComplete: isComplete,
                         images: combined, revision: revision, localUploadRejections: rejections)
    }
}

public protocol DownloadedItemImageReading: Sendable {
    func watchDownloadedItemImages(accountId: AccountID, itemId: ItemID)
        -> AsyncThrowingStream<DownloadedItemImageCatalog, Error>
    /// Revalidate the exact live reference before and after any awaited byte
    /// access. Nil means no cached bytes and no configured/allowed download.
    func loadDownloadedItemImage(accountId: AccountID, itemId: ItemID,
        image: DownloadedItemImage, allowDownload: Bool) async throws -> Data?
    func loadDownloadedItemThumbnail(accountId: AccountID, itemId: ItemID,
        image: DownloadedItemImage, allowDownload: Bool) async throws -> Data?
}

public extension DownloadedItemImageReading {
    /// Implementations without derivative storage do not download an original
    /// as a hidden fallback for small cards.
    func loadDownloadedItemThumbnail(accountId: AccountID, itemId: ItemID,
        image: DownloadedItemImage, allowDownload: Bool) async throws -> Data? { nil }
}
