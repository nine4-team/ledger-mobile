import SwiftUI

// MARK: - Brand Colors

enum BrandColors {
    /// Brand primary — #987e55 (taupe/brown). Same in both light and dark modes.
    static let primary = Color(red: 152/255, green: 126/255, blue: 85/255)

    // MARK: - Adaptive Backgrounds (auto-switch light/dark)

    /// Screen background — light: #f7f8fa, dark: #1E1E1E
    static let background = Color("background")
    /// Elevated surface (cards, sheets) — light: #FFFFFF, dark: #2E2E2E
    static let surface = Color("surface")
    /// Tertiary surface — light: #fafafa, dark: #323232
    static let surfaceTertiary = Color("surfaceTertiary")

    // MARK: - Adaptive Text

    /// Primary text — light: #111827, dark: #E0E0E0
    static let textPrimary = Color("textPrimary")
    /// Secondary text — light: #6B7280, dark: #B0B0B0
    static let textSecondary = Color("textSecondary")
    /// Tertiary text — light: #9CA3AF, dark: #888888
    static let textTertiary = Color("textTertiary")
    /// Disabled text — light: #CCCCCC, dark: #666666
    static let textDisabled = Color("textDisabled")

    // MARK: - Adaptive Borders

    /// Primary border — light: #C7CBD4, dark: #4A4A4C
    static let border = Color("borderPrimary")
    /// Secondary border (subtle dividers) — light: #E5E7EB, dark: #4A4A4C
    static let borderSecondary = Color("borderSecondary")

    // MARK: - Adaptive Buttons

    /// Secondary button background — light: #FFFFFF, dark: #333333
    static let buttonSecondaryBackground = Color("buttonSecondaryBg")
    /// Icon button background — light: #F3F4F6, dark: #3D3224
    static let iconButtonBackground = Color("iconButtonBg")
    /// Disabled button background — light: #CCCCCC, dark: #666666
    static let buttonDisabledBackground = Color("buttonDisabledBg")

    // MARK: - Adaptive Input

    /// Input background — light: #FFFFFF, dark: #2E2E2E
    static let inputBackground = Color("inputBackground")

    // MARK: - Destructive

    /// Destructive text — light: #d32f2f, dark: #EF5350
    static let destructive = Color("destructive")
    /// Destructive background — light: #ffebee, dark: #3E1E1E
    static let destructiveBackground = Color("destructiveBg")

    // MARK: - Progress

    /// Progress track background — light: system, dark: #3A3A3C
    static let progressTrack = Color("progressTrack")

    // MARK: - Legacy Direct Colors (use adaptive versions above in new code)

    static let darkBackground = Color(red: 30/255, green: 30/255, blue: 30/255)
    static let darkSurface = Color(red: 46/255, green: 46/255, blue: 46/255)
    static let darkText = Color(red: 224/255, green: 224/255, blue: 224/255)
    static let darkTextSecondary = Color(red: 176/255, green: 176/255, blue: 176/255)
    static let darkBorder = Color(red: 74/255, green: 74/255, blue: 76/255)
    static let darkProgressTrack = Color(red: 58/255, green: 58/255, blue: 60/255)
}
