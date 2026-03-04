import SwiftUI

/// Shape and dimension constants matching the React Native design system.
enum Dimensions {

    // MARK: - Corner Radius

    /// Card corner radius — 12pt
    static let cardRadius: CGFloat = 12
    /// Button corner radius — 8pt
    static let buttonRadius: CGFloat = 8
    /// Input field corner radius — 8pt
    static let inputRadius: CGFloat = 8

    // MARK: - Border Width

    /// Standard border/divider — 1pt
    static let borderWidth: CGFloat = 1
    /// Selection highlight border — 2pt
    static let selectionBorderWidth: CGFloat = 2

    // MARK: - Thumbnail

    /// Thumbnail corner radius — 21pt
    static let thumbnailRadius: CGFloat = 21

    // MARK: - Adaptive Layout

    /// Maximum width for content in list/detail views (prevents stretching on wide screens)
    static let contentMaxWidth: CGFloat = 720

    /// Maximum width for form sheets on macOS
    static let formMaxWidth: CGFloat = 560

    /// Minimum card width for responsive grid calculation
    static let cardMinWidth: CGFloat = 320
}
