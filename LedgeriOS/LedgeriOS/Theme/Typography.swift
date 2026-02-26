import SwiftUI

/// Typography scale matching the React Native design system.
///
/// The RN app uses system fonts at specific sizes/weights. SwiftUI's built-in
/// text styles (`.title`, `.body`, `.caption`) map closely, so we define
/// helpers for the cases where we need exact parity or custom combinations.
enum Typography {

    // MARK: - Headers

    /// Large header — 20px bold (RN: h1, screen titles)
    /// SwiftUI equivalent: `.title3` + `.bold()`
    static let h1: Font = .title3.bold()

    /// Medium header — 18px bold (RN: h2, section titles)
    /// SwiftUI equivalent: `.headline`
    static let h2: Font = .headline

    /// Small header — 16px semibold (RN: h3, card titles)
    /// SwiftUI equivalent: `.subheadline` + `.weight(.semibold)`
    static let h3: Font = .subheadline.weight(.semibold)

    // MARK: - Body

    /// Body text — 16px regular (RN: body, default paragraph text)
    static let body: Font = .body

    /// Small text — 14px regular (RN: secondary text, descriptions)
    static let small: Font = .subheadline

    /// Tiny text — 12px regular (RN: captions, timestamps)
    static let caption: Font = .caption

    // MARK: - Interactive

    /// Button label — 16px semibold
    static let button: Font = .body.weight(.semibold)

    /// Small button / pill label — 14px semibold
    static let buttonSmall: Font = .subheadline.weight(.semibold)

    /// Input text — 16px regular
    static let input: Font = .body

    /// Form label — 14px semibold
    static let label: Font = .subheadline.weight(.semibold)

    // MARK: - Section Label

    /// Uppercase section label — 13px semibold, uppercased, with letter spacing.
    /// Apply with `.sectionLabelStyle()` modifier for full effect.
    static let sectionLabel: Font = .caption.weight(.semibold)
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
