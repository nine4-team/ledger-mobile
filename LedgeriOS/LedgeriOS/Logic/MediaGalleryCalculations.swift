import Foundation

extension MediaGalleryCalculations {

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

    /// Count of image-type attachments.
    static func thumbnailCount(_ attachments: [AttachmentRef]) -> Int {
        attachments.filter { $0.kind == .image }.count
    }

    /// Whether the options button should appear on thumbnails.
    static func shouldShowOptionsButton(hasSetPrimary: Bool, hasRemove: Bool) -> Bool {
        hasSetPrimary || hasRemove
    }

    /// Offers the primary-selection action when the attachment is not primary or
    /// when malformed data marks more than one attachment as primary. In the
    /// duplicate case, selecting either attachment repairs the collection by
    /// allowing the caller to make that attachment the sole primary.
    static func shouldOfferSetPrimary(
        for attachment: AttachmentRef,
        in attachments: [AttachmentRef]
    ) -> Bool {
        attachment.isPrimary != true || attachments.filter { $0.isPrimary == true }.count != 1
    }

    // MARK: - Add Tile

    /// Whether the add tile should appear in the thumbnail grid.
    static func shouldShowAddTile(currentCount: Int, maxAttachments: Int, hasAddHandler: Bool) -> Bool {
        currentCount < maxAttachments && hasAddHandler
    }

    // MARK: - Upload Status

    /// Whether an upload overlay should be shown on a thumbnail.
    static func shouldShowUploadOverlay(status: UploadStatus?) -> Bool {
        status != nil
    }

    /// The icon to display for a given upload status (nil means use ProgressView instead).
    static func uploadOverlayIcon(status: UploadStatus?) -> String? {
        switch status {
        case .failed: return "icloud.slash"
        case .uploading, nil: return nil
        }
    }
}

enum UploadStatus: String {
    case uploading
    case failed
}
