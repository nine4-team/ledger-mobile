import SwiftUI

/// Status colors for budget tracking and transaction badges.
/// Each status has a background, text, and bar/progress color
/// with light and dark mode variants via asset catalog.
enum StatusColors {

    // MARK: - Met / Success

    /// Met status background — light: #F5F3EF, dark: #3D3224
    static let metBackground = Color("statusMetBg")
    /// Met status text — brand primary
    static let metText = BrandColors.primary
    /// Met bar complete — #30A654 (vivid success green, same both modes)
    static let metBarComplete = Color(red: 48/255, green: 166/255, blue: 84/255)

    // MARK: - In Progress

    /// In-progress background — light: #FFF8E1, dark: #3E2E1A
    static let inProgressBackground = Color("statusInProgressBg")
    /// In-progress text — light: #E08B05, dark: #FFC107
    static let inProgressText = Color("statusInProgressText")
    /// In-progress bar — #E3A713 vivid amber/gold (same both modes)
    static let inProgressBar = Color(red: 0.890, green: 0.655, blue: 0.075)

    // MARK: - Missed / Error

    /// Missed background — light: #FCE8E6, dark: #3E1E1E
    static let missedBackground = Color("statusMissedBg")
    /// Missed text — light: #C5221F, dark: #EF5350
    static let missedText = Color("statusMissedText")

    // MARK: - At Risk / Overflow

    /// At-risk bar — #b94520 rust (matches Needs Review badge) for >= 75% fill.
    /// Replaces the former #dc2626 red-600 which read as pink at low opacity.
    static let atRiskBar = Color(red: 185/255, green: 69/255, blue: 32/255)
    /// Overflow bar — #7a2e12 deep rust for the over-budget segment.
    /// Darker than atRiskBar so the overflow stack is still visible when
    /// rendered on top of the at-risk fill.
    static let overflowBar = Color(red: 122/255, green: 46/255, blue: 18/255)

    // MARK: - Transaction Badge Semantic Colors

    /// Success badge — #059669 / #10b981
    static let badgeSuccess = Color(red: 5/255, green: 150/255, blue: 105/255)
    /// Info badge — #2563eb
    static let badgeInfo = Color(red: 37/255, green: 99/255, blue: 235/255)
    /// Warning badge — #d97706
    static let badgeWarning = Color(red: 217/255, green: 119/255, blue: 6/255)
    /// Error badge — #ef4444
    static let badgeError = Color(red: 239/255, green: 68/255, blue: 68/255)
    /// Needs Review — #b94520
    static let badgeNeedsReview = Color(red: 185/255, green: 69/255, blue: 32/255)
}
