import Foundation

public enum DownloadedItemImageFailure: Error, Equatable, Sendable {
    case malformed, scopeMismatch, unavailable
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

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.referenceId.rawValue.utf8.elementsEqual(rhs.referenceId.rawValue.utf8)
            && lhs.itemId.rawValue.utf8.elementsEqual(rhs.itemId.rawValue.utf8)
            && lhs.object == rhs.object && lhs.position == rhs.position
            && lhs.isPrimary == rhs.isPrimary && lhs.setRevision == rhs.setRevision
    }

    public init(referenceId: EntityID, itemId: ItemID, object: DownloadedImageObjectReference,
                position: Int, isPrimary: Bool, setRevision: Int64) throws {
        guard position >= 0, setRevision > 0 else { throw DownloadedItemImageFailure.malformed }
        self.referenceId = referenceId; self.itemId = itemId; self.object = object
        self.position = position; self.isPrimary = isPrimary; self.setRevision = setRevision
    }
}

/// Complete empty metadata means No Image. Missing/incomplete metadata does not.
public struct DownloadedItemImageCatalog: Equatable, Sendable {
    public let accountId: AccountID
    public let itemId: ItemID
    public let isComplete: Bool
    public let images: [DownloadedItemImage]

    public init(accountId: AccountID, itemId: ItemID, isComplete: Bool,
                images: [DownloadedItemImage]) throws {
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
        self.images = images.sorted {
            $0.position == $1.position ? $0.referenceId.rawValue < $1.referenceId.rawValue : $0.position < $1.position
        }
    }

    public var primaryImage: DownloadedItemImage? {
        images.first(where: \.isPrimary) ?? images.first
    }
}

public protocol DownloadedItemImageReading: Sendable {
    func watchDownloadedItemImages(accountId: AccountID, itemId: ItemID)
        -> AsyncThrowingStream<DownloadedItemImageCatalog, Error>
    /// Revalidate the exact live reference before and after any awaited byte
    /// access. Nil means no cached bytes and no configured/allowed download.
    func loadDownloadedItemImage(accountId: AccountID, itemId: ItemID,
        image: DownloadedItemImage, allowDownload: Bool) async throws -> Data?
}
