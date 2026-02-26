import Foundation

enum MediaGalleryCalculations {

    static func canAddAttachment(current: [AttachmentRef], maxAttachments: Int) -> Bool {
        current.count < maxAttachments
    }

    static func isAllowedKind(_ kind: AttachmentKind, allowedKinds: [AttachmentKind]) -> Bool {
        allowedKinds.contains(kind)
    }

    /// Returns the primary image: first with `isPrimary == true`, falling back to the first image-kind attachment.
    static func primaryImage(_ attachments: [AttachmentRef]) -> AttachmentRef? {
        attachments.first(where: { $0.isPrimary == true && $0.kind == .image })
            ?? attachments.first(where: { $0.kind == .image })
    }

    /// Returns actual column count: min 1, max `preferredColumns`, capped by item count.
    static func gridColumns(for count: Int, preferredColumns: Int = 3) -> Int {
        guard count > 0 else { return 1 }
        return min(count, max(1, preferredColumns))
    }

    /// Count of image-type attachments.
    static func thumbnailCount(_ attachments: [AttachmentRef]) -> Int {
        attachments.filter { $0.kind == .image }.count
    }
}
