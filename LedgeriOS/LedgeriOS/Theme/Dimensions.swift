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

    /// Standard border/divider. macOS uses a 0.5pt hairline so cards and
    /// modals read as filled surfaces rather than outlined boxes — iOS keeps
    /// the 1pt stroke since touch targets benefit from a slightly heavier edge.
    static var borderWidth: CGFloat {
        #if os(macOS)
        0.5
        #else
        1
        #endif
    }
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

    /// Grid columns for card lists — single-column on macOS, adaptive grid on iOS.
    static var listColumns: [GridItem] {
        #if os(macOS)
        [GridItem(.flexible())]
        #else
        [GridItem(.adaptive(minimum: cardMinWidth), spacing: Spacing.cardListGap)]
        #endif
    }

    // MARK: - Pinned Image

    /// Width of the pinned image sidebar on regular-width displays (iPad)
    static let pinnedSidebarWidth: CGFloat = 384
}

// MARK: - Form Input Container

extension View {
    /// Standard bordered input container — matches `FormField` styling.
    /// Applies horizontal padding, 44pt min height, input radius, and border stroke.
    func formInputStyle() -> some View {
        self
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: 44)
            .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                    .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
            )
    }
}
