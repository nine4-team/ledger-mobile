import Foundation

// Original pure gallery math, shared without attachment/storage models.
enum MediaGalleryCalculations {
    /// Returns actual column count: min 1, max `preferredColumns`, capped by item count.
    static func gridColumns(for count: Int, preferredColumns: Int = 3) -> Int {
        guard count > 0 else { return 1 }
        return min(count, max(1, preferredColumns))
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

    /// Converts app zoom state to the scroll view's platform zoom scale.
    /// App zoom is relative to the fitted image size, so 1.0 means "fit to container".
    static func platformZoomScale(logicalZoom: CGFloat, fitScale: CGFloat) -> CGFloat {
        max(fitScale, fitScale * logicalZoom)
    }

    /// Converts the scroll view's platform zoom scale back to app zoom state.
    static func logicalZoomScale(platformZoom: CGFloat, fitScale: CGFloat) -> CGFloat {
        guard fitScale > 0 else { return 1.0 }
        return max(1.0, platformZoom / fitScale)
    }

    // MARK: - Navigation

    /// Returns the previous image index, wrapping to the end.
    static func previousIndex(current: Int, total: Int) -> Int {
        guard total > 0 else { return 0 }
        return current > 0 ? current - 1 : total - 1
    }

    /// Returns the next image index, wrapping to the beginning.
    static func nextIndex(current: Int, total: Int) -> Int {
        guard total > 0 else { return 0 }
        return current < total - 1 ? current + 1 : 0
    }

    // MARK: - Swipe-to-Dismiss

    /// Maps vertical drag translation to a 0…1 dismiss progress.
    static func dismissProgress(translation: CGFloat, threshold: CGFloat) -> CGFloat {
        guard threshold > 0 else { return 0 }
        return min(1, abs(translation) / threshold)
    }

    /// Maps dismiss progress to image scale (1.0 at rest, 0.7 at full threshold).
    static func dismissScale(progress: CGFloat) -> CGFloat {
        1.0 - (progress * 0.3)
    }

    /// Maps dismiss progress to background opacity (1.0 at rest, 0.0 at full threshold).
    static func dismissOpacity(progress: CGFloat) -> CGFloat {
        1.0 - progress
    }

}
