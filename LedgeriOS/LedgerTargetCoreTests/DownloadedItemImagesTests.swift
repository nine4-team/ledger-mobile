import LedgerTargetCore
import Testing

@Suite("Downloaded Item image catalog")
struct DownloadedItemImagesTests {
    private let account = try! AccountID(validating: "account")
    private let item = try! ItemID(validating: "item")

    @Test("Catalog separates absent metadata from explicit no images and preserves primary/order")
    func completenessAndOrder() throws {
        let unknown = try DownloadedItemImageCatalog(accountId: account, itemId: item, isComplete: false, images: [])
        let empty = try DownloadedItemImageCatalog(accountId: account, itemId: item, isComplete: true, images: [])
        #expect(unknown != empty)
        #expect(empty.primaryImage == nil)
        let first = try image("first", position: 0)
        let primary = try image("primary", position: 1, primary: true)
        let catalog = try DownloadedItemImageCatalog(accountId: account, itemId: item,
            isComplete: true, images: [primary, first])
        #expect(catalog.images == [first, primary])
        #expect(catalog.primaryImage == primary)
    }

    @Test("Wrong parents, duplicate positions/primary and mixed revisions never form a gallery")
    func malformedEvidence() throws {
        let first = try image("first", position: 0, primary: true)
        for bad in [try image("second", position: 0), try image("second", position: 1, primary: true),
                    try image("second", position: 1, revision: 2)] {
            #expect(throws: DownloadedItemImageFailure.malformed) {
                try DownloadedItemImageCatalog(accountId: account, itemId: item, isComplete: false, images: [first, bad])
            }
        }
        #expect(throws: DownloadedItemImageFailure.scopeMismatch) {
            try DownloadedItemImageCatalog(accountId: .init(validating: "other"), itemId: item,
                isComplete: true, images: [first])
        }
        #expect(throws: DownloadedItemImageFailure.scopeMismatch) {
            try DownloadedItemImageCatalog(accountId: account, itemId: .init(validating: "other"),
                isComplete: true, images: [first])
        }
        #expect(throws: DownloadedItemImageFailure.malformed) { try image("bad", position: -1) }
        #expect(throws: DownloadedItemImageFailure.malformed) { try image("bad", position: 0, revision: 0) }
    }

    @Test("Canonically equivalent Unicode never aliases persisted image parents or references")
    func byteExactIdentity() throws {
        // Both characters are letters accepted by LedgerIdentifier, but Swift
        // String equality treats the Kelvin sign and ASCII K as equivalent.
        let ascii = "K", unicode = "\u{212A}"
        #expect(ascii == unicode)
        let accountA = try AccountID(validating: ascii)
        let accountB = try AccountID(validating: unicode)
        let itemA = try ItemID(validating: ascii)
        let itemB = try ItemID(validating: unicode)
        let hash = String(repeating: "a", count: 64)
        func object(_ account: AccountID) throws -> DownloadedImageObjectReference {
            try .init(accountId: account, attachmentId: "image", sha256: hash,
                byteCount: "1", mediaType: "image/png",
                storagePath: "accounts/\(account.rawValue)/attachments/image/\(hash)")
        }
        let objectA = try object(accountA)
        #expect(objectA != (try object(accountB)))
        let first = try DownloadedItemImage(referenceId: .init(validating: ascii), itemId: itemA,
            object: objectA, position: 0, isPrimary: false, setRevision: 1)
        let otherReference = try DownloadedItemImage(referenceId: .init(validating: unicode), itemId: itemA,
            object: objectA, position: 0, isPrimary: false, setRevision: 1)
        #expect(first != otherReference)
        for (account, item) in [(accountB, itemA), (accountA, itemB)] {
            #expect(throws: DownloadedItemImageFailure.scopeMismatch) {
                try DownloadedItemImageCatalog(accountId: account, itemId: item, isComplete: true, images: [first])
            }
        }
    }

    @Test("Thumbnail identity cannot be borrowed from another original, even in the same Account")
    func thumbnailIdentity() throws {
        let first = try image("first",position: 0), other = try image("other",position: 0)
        let hash = String(repeating: "b",count: 64)
        let small = try DownloadedImageObjectReference(accountId: account,attachmentId: "small",sha256: hash,
            byteCount: "3",mediaType: "image/jpeg",storagePath: "accounts/account/attachments/small/\(hash)")
        let thumbnail = try DownloadedItemCardThumbnail(original: first.object,object: small,
            recipe: "item-card-300-jpeg-v1",width: 300,height: 200)
        #expect(throws: DownloadedItemImageFailure.scopeMismatch) {
            try DownloadedItemImage(referenceId: other.referenceId,itemId: item,object: other.object,
                position: 0,isPrimary: false,setRevision: 1,thumbnail: thumbnail)
        }
        for (recipe,width,height) in [("unknown",300,200),("item-card-300-jpeg-v1",301,200),("item-card-300-jpeg-v1",300,0)] {
            #expect(throws: DownloadedItemImageFailure.malformed) {
                try DownloadedItemCardThumbnail(original: first.object,object: small,recipe: recipe,width: width,height: height)
            }
        }
        #expect(throws: DownloadedItemImageFailure.malformed) {
            try DownloadedItemCardThumbnail(original: small,object: small,recipe: "item-card-300-jpeg-v1",width: 300,height: 200)
        }
    }

    private func image(_ id: String, position: Int, primary: Bool = false, revision: Int64 = 1) throws -> DownloadedItemImage {
        let hash = String(repeating: "a", count: 64)
        let object = try DownloadedImageObjectReference(accountId: account, attachmentId: id, sha256: hash,
            byteCount: "1", mediaType: "image/png", storagePath: "accounts/account/attachments/\(id)/\(hash)")
        return try .init(referenceId: .init(validating: "reference-\(id)"), itemId: item, object: object,
            position: position, isPrimary: primary, setRevision: revision)
    }
}
