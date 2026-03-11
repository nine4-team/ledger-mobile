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
    /// Met bar complete — #4A7C59 (success green, same both modes)
    static let metBarComplete = Color(red: 74/255, green: 124/255, blue: 89/255)

    // MARK: - In Progress

    /// In-progress background — light: #FFF8E1, dark: #3E2E1A
    static let inProgressBackground = Color("statusInProgressBg")
    /// In-progress text — light: #B06E00, dark: #FFC107
    static let inProgressText = Color("statusInProgressText")
    /// In-progress bar — #C4911E darker amber/gold (same both modes)
    static let inProgressBar = Color(red: 0.769, green: 0.569, blue: 0.118)

    // MARK: - Missed / Error

    /// Missed background — light: #FCE8E6, dark: #3E1E1E
    static let missedBackground = Color("statusMissedBg")
    /// Missed text — light: #C5221F, dark: #EF5350
    static let missedText = Color("statusMissedText")

    // MARK: - At Risk / Overflow

    /// At-risk bar — #9E3B2F darker red for >= 75% fill (same both modes)
    static let atRiskBar = Color(red: 0.620, green: 0.231, blue: 0.184)
    /// Overflow bar — #D4574A brighter red for the over-budget segment (same both modes)
    static let overflowBar = Color(red: 0.831, green: 0.341, blue: 0.290)

    // MARK: - Transaction Badge Semantic Colors

    /// Success badge — #059669 / #10b981
    static let badgeSuccess = Color(red: 5/255, green: 150/255, blue: 105/255)
    /// Info badge — #2563eb
    static let badgeInfo = Color(red: 37/255, green: 99/255, blue: 235/255)
    /// Warning badge — #d97706
    static let badgeWarning = Color(red: 217/255, green: 119/255, blue: 6/255)
    /// Error badge — #dc2626
    static let badgeError = Color(red: 220/255, green: 38/255, blue: 38/255)
    /// Needs Review — #b94520
    static let badgeNeedsReview = Color(red: 185/255, green: 69/255, blue: 32/255)
}
