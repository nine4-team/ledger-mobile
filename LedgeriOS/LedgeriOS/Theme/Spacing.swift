import SwiftUI

/// Spacing scale matching the React Native design system.
/// Use these instead of inline numeric literals.
enum Spacing {
    /// 0pt — no spacing
    static let none: CGFloat = 0
    /// 4pt — tightest spacing (icon gaps, inline elements)
    static let xs: CGFloat = 4
    /// 8pt — small gaps (HStack icon+text, compact padding)
    static let sm: CGFloat = 8
    /// 12pt — medium gaps (card list gap, section internal spacing)
    static let md: CGFloat = 12
    /// 16pt — standard padding (screen padding, card padding, form field spacing)
    static let lg: CGFloat = 16
    /// 24pt — section-level spacing (between form groups)
    static let xl: CGFloat = 24
    /// 32pt — large padding (auth screen horizontal padding)
    static let xxl: CGFloat = 32
    /// 48pt — extra large (major section separation)
    static let xxxl: CGFloat = 48

    // MARK: - Semantic Aliases

    /// Horizontal padding for screen content — 16pt
    static let screenPadding: CGFloat = lg
    /// Internal padding inside cards — 16pt
    static let cardPadding: CGFloat = lg
    /// Vertical gap between cards in a list — 12pt
    static let cardListGap: CGFloat = md
}
