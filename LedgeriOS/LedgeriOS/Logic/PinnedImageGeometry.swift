import Foundation
import CoreGraphics

// Original annotation coordinate math, independent of attachment/write models.
enum PinnedImageCalculations {
    /// Clamp a panel height fraction to valid range.
    static func clampedFraction(_ fraction: CGFloat, min minVal: CGFloat = 0.20, max maxVal: CGFloat = 0.50) -> CGFloat {
        Swift.min(maxVal, Swift.max(minVal, fraction))
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
}
