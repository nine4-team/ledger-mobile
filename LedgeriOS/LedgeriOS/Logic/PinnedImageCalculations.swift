import Foundation
import CoreGraphics

enum PinnedImageCalculations {

    /// The image frame produced by aspect-fit inside a container.
    static func aspectFitRect(imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else { return .zero }

        let scale = Swift.min(
            containerSize.width / imageSize.width,
            containerSize.height / imageSize.height
        )
        let fittedSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )

        return CGRect(
            x: (containerSize.width - fittedSize.width) / 2,
            y: (containerSize.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    /// Converts a tap in container coordinates into normalized image coordinates.
    static func normalizedImagePoint(for tapPoint: CGPoint, in imageRect: CGRect) -> CGPoint? {
        guard imageRect.width > 0, imageRect.height > 0 else { return nil }

        return CGPoint(
            x: Swift.min(Swift.max((tapPoint.x - imageRect.minX) / imageRect.width, 0), 1),
            y: Swift.min(Swift.max((tapPoint.y - imageRect.minY) / imageRect.height, 0), 1)
        )
    }

    /// Converts normalized image coordinates back into container coordinates for rendering.
    static func renderedPoint(for normalizedPoint: CGPoint, in imageRect: CGRect) -> CGPoint {
        CGPoint(
            x: imageRect.minX + normalizedPoint.x * imageRect.width,
            y: imageRect.minY + normalizedPoint.y * imageRect.height
        )
    }

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
