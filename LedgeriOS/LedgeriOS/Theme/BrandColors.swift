import SwiftUI

// MARK: - Brand Colors

enum BrandColors {
    /// Brand primary — #987e55 (taupe/brown). Same in both light and dark modes.
    static let primary = Color(red: 152/255, green: 126/255, blue: 85/255)

    // MARK: - Adaptive Backgrounds (grouped hierarchy — card-based layout)

    /// Screen background — light: #F2F2F7 (subtle gray), dark: #000000
    static let background = platformColor(.systemGroupedBackground)
    /// Elevated surface (cards, sheets) — light: white, dark: #1C1C1E
    static let surface = platformColor(.secondarySystemGroupedBackground)
    /// Tertiary surface — light: #F2F2F7, dark: #2C2C2E
    static let surfaceTertiary = platformColor(.tertiarySystemGroupedBackground)

    // MARK: - Adaptive Text

    /// Primary text
    static let textPrimary = platformColor(.label)
    /// Secondary text
    static let textSecondary = platformColor(.secondaryLabel)
    /// Tertiary text
    static let textTertiary = platformColor(.tertiaryLabel)
    /// Disabled text
    static let textDisabled = platformColor(.quaternaryLabel)

    // MARK: - Adaptive Borders

    /// Primary border
    static let border = platformColor(.separator)
    /// Secondary border (subtle dividers)
    static let borderSecondary = platformColor(.separator)

    // MARK: - Adaptive Buttons

    /// Secondary button background
    static let buttonSecondaryBackground = platformColor(.secondarySystemFill)
    /// Icon button background
    static let iconButtonBackground = platformColor(.tertiarySystemFill)
    /// Disabled button background
    static let buttonDisabledBackground = platformColor(.quaternarySystemFill)

    // MARK: - Adaptive Input

    /// Input field background — subtle recessed fill inside cards
    static let inputBackground = platformColor(.tertiarySystemFill)

    // MARK: - Destructive

    /// Destructive text
    static let destructive = platformColor(.systemRed)
    /// Destructive background — red tint at low opacity
    static let destructiveBackground = platformColor(.systemRed).opacity(0.12)

    // MARK: - Progress

    /// Progress track background
    static let progressTrack = platformColor(.secondarySystemFill)
}

// MARK: - Platform Color Bridge

#if canImport(UIKit)
import UIKit
private func platformColor(_ color: UIColor) -> Color { Color(uiColor: color) }
#elseif canImport(AppKit)
import AppKit

private func platformColor(_ color: NSColor) -> Color { Color(nsColor: color) }

extension NSColor {
    // Map iOS semantic names to macOS equivalents
    static var label: NSColor { .labelColor }
    static var secondaryLabel: NSColor { .secondaryLabelColor }
    static var tertiaryLabel: NSColor { .tertiaryLabelColor }
    static var quaternaryLabel: NSColor { .quaternaryLabelColor }
    static var separator: NSColor { .separatorColor }
    static var systemGroupedBackground: NSColor { .windowBackgroundColor }
    static var secondarySystemGroupedBackground: NSColor { .controlBackgroundColor }
    static var tertiarySystemGroupedBackground: NSColor { .underPageBackgroundColor }
    static var secondarySystemFill: NSColor { .controlColor }
    static var tertiarySystemFill: NSColor { .unemphasizedSelectedContentBackgroundColor }
    static var quaternarySystemFill: NSColor { .quaternaryLabelColor }
    static var systemRed: NSColor { .systemRed }
}
#endif
