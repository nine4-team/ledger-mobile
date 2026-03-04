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

    /// Whether the options button should appear on thumbnails.
    static func shouldShowOptionsButton(hasSetPrimary: Bool, hasRemove: Bool) -> Bool {
        hasSetPrimary || hasRemove
    }

    // MARK: - Lightbox Calculations

    /// Formatted image counter label, e.g. "1 of 5".
    static func imageCounterLabel(currentIndex: Int, total: Int) -> String {
        "\(currentIndex + 1) of \(total)"
    }

    /// Whether the user can zoom in further.
    static func canZoomIn(currentZoom: CGFloat, maxZoom: CGFloat) -> Bool {
        currentZoom < maxZoom
    }

    /// Whether the user can zoom out further.
    static func canZoomOut(currentZoom: CGFloat, minZoom: CGFloat) -> Bool {
        currentZoom > minZoom
    }

    /// Next zoom level after zooming in.
    static func nextZoom(current: CGFloat, step: CGFloat, max: CGFloat) -> CGFloat {
        min(current + step, max)
    }

    /// Next zoom level after zooming out.
    static func previousZoom(current: CGFloat, step: CGFloat, min minZoom: CGFloat) -> CGFloat {
        max(current - step, minZoom)
    }

    /// Whether the reset zoom button should be visible.
    static func shouldShowResetZoom(currentZoom: CGFloat) -> Bool {
        currentZoom > 1.01
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
