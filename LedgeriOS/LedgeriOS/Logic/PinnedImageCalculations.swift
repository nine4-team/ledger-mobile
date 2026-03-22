import Foundation

enum PinnedImageCalculations {

    /// Clamp a panel height fraction to valid range.
    static func clampedFraction(_ fraction: CGFloat, min minVal: CGFloat = 0.20, max maxVal: CGFloat = 0.50) -> CGFloat {
        Swift.min(maxVal, Swift.max(minVal, fraction))
    }

    /// Compute new fraction after a drag gesture.
    static func fractionAfterDrag(
        startFraction: CGFloat,
        translationHeight: CGFloat,
        totalHeight: CGFloat,
        min minVal: CGFloat = 0.20,
        max maxVal: CGFloat = 0.50
    ) -> CGFloat {
        guard totalHeight > 0 else { return startFraction }
        let raw = startFraction + translationHeight / totalHeight
        return clampedFraction(raw, min: minVal, max: maxVal)
    }

    /// Whether an attachment can be pinned (image or PDF, and not mid-upload).
    static func canPin(_ attachment: AttachmentRef) -> Bool {
        (attachment.kind == .image || attachment.kind == .pdf) && !(attachment.isUploading ?? false)
    }
}
