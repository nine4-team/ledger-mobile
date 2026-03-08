import SwiftUI

// MARK: - Brand Colors

enum BrandColors {
    /// Brand primary — #987e55 (taupe/brown). Same in both light and dark modes.
    static let primary = Color(red: 152/255, green: 126/255, blue: 85/255)

    // MARK: - Adaptive Backgrounds (grouped hierarchy — card-based layout)

    /// Screen background — light: #F2F2F7 (subtle gray), dark: #000000
    static let background = Color(.systemGroupedBackground)
    /// Elevated surface (cards, sheets) — light: white, dark: #1C1C1E
    static let surface = Color(.secondarySystemGroupedBackground)
    /// Tertiary surface — light: #F2F2F7, dark: #2C2C2E
    static let surfaceTertiary = Color(.tertiarySystemGroupedBackground)

    // MARK: - Adaptive Text

    /// Primary text
    static let textPrimary = Color(.label)
    /// Secondary text
    static let textSecondary = Color(.secondaryLabel)
    /// Tertiary text
    static let textTertiary = Color(.tertiaryLabel)
    /// Disabled text
    static let textDisabled = Color(.quaternaryLabel)

    // MARK: - Adaptive Borders

    /// Primary border
    static let border = Color(.separator)
    /// Secondary border (subtle dividers)
    static let borderSecondary = Color(.separator)

    // MARK: - Adaptive Buttons

    /// Secondary button background
    static let buttonSecondaryBackground = Color(.secondarySystemFill)
    /// Icon button background
    static let iconButtonBackground = Color(.tertiarySystemFill)
    /// Disabled button background
    static let buttonDisabledBackground = Color(.quaternarySystemFill)

    // MARK: - Adaptive Input

    /// Input field background — subtle recessed fill inside cards
    static let inputBackground = Color(.tertiarySystemFill)

    // MARK: - Destructive

    /// Destructive text
    static let destructive = Color(.systemRed)
    /// Destructive background — red tint at low opacity
    static let destructiveBackground = Color(.systemRed).opacity(0.12)

    // MARK: - Progress

    /// Progress track background
    static let progressTrack = Color(.tertiarySystemFill)
}
