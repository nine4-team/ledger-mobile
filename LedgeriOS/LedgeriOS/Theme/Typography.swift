import SwiftUI

/// Brand typography scale.
///
/// Two fonts, used with restraint:
/// - **Playfair Display** (Google Fonts, bundled variable TTF) for screen
///   titles — editorial, high-contrast serif. Used sparingly.
/// - **Avenir Next** (system font on every Apple platform) for everything
///   else — clean, geometric workhorse.
///
/// Each token uses `.custom(_:size:relativeTo:)` so text still scales with
/// Dynamic Type.
enum Typography {

    // MARK: - Font Family

    private static let avenirRegular  = "AvenirNext-Regular"
    private static let avenirMedium   = "AvenirNext-Medium"
    private static let avenirDemiBold = "AvenirNext-DemiBold"
    private static let avenirBold     = "AvenirNext-Bold"

    private static let playfairDisplay = "PlayfairDisplay-Regular"

    // MARK: - Headers

    /// Screen title — 26pt Playfair Display Regular. Editorial, used only
    /// for the main title on each screen.
    static let h1: Font = .custom(playfairDisplay, size: 26, relativeTo: .title2)

    /// Section header — 18pt semibold.
    static let h2: Font = .custom(avenirDemiBold, size: 18, relativeTo: .headline)

    /// Card title — 16pt semibold.
    static let h3: Font = .custom(avenirDemiBold, size: 16, relativeTo: .subheadline)

    // MARK: - Body

    /// Body text — 16pt regular.
    static let body: Font = .custom(avenirRegular, size: 16, relativeTo: .body)

    /// Secondary text / descriptions — 14pt regular.
    static let small: Font = .custom(avenirRegular, size: 14, relativeTo: .subheadline)

    /// Captions / timestamps — 12pt regular.
    static let caption: Font = .custom(avenirRegular, size: 12, relativeTo: .caption)

    // MARK: - Interactive

    /// Button label — 16pt semibold.
    static let button: Font = .custom(avenirDemiBold, size: 16, relativeTo: .body)

    /// Small button / pill label — 14pt semibold.
    static let buttonSmall: Font = .custom(avenirDemiBold, size: 14, relativeTo: .subheadline)

    /// Input text — 16pt regular.
    static let input: Font = .custom(avenirRegular, size: 16, relativeTo: .body)

    /// Form label — 14pt semibold.
    static let label: Font = .custom(avenirDemiBold, size: 14, relativeTo: .subheadline)

    // MARK: - Section Label

    /// Uppercase section label — 13pt semibold. Apply with `.sectionLabelStyle()`.
    static let sectionLabel: Font = .custom(avenirDemiBold, size: 13, relativeTo: .caption)
}

// MARK: - View Modifiers

extension View {
    /// Applies the section label style: uppercase, semibold, letter-spaced, secondary color.
    func sectionLabelStyle() -> some View {
        self
            .font(Typography.sectionLabel)
            .textCase(.uppercase)
            .tracking(0.5)
            .foregroundStyle(BrandColors.textSecondary)
    }
}
