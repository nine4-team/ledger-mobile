import SwiftUI

// MARK: - Cross-Platform Toolbar Placements

extension ToolbarItemPlacement {
    /// Trailing position in the navigation bar (iOS) or toolbar (macOS).
    static var trailingNavBar: ToolbarItemPlacement {
        #if canImport(UIKit)
        .navigationBarTrailing
        #else
        .automatic
        #endif
    }

    /// Leading position in the navigation bar (iOS) or toolbar (macOS).
    static var leadingNavBar: ToolbarItemPlacement {
        #if canImport(UIKit)
        .navigationBarLeading
        #else
        .automatic
        #endif
    }
}

// MARK: - iOS-Only View Modifiers (no-op on macOS)

extension View {
    /// Sets the navigation bar title display mode on iOS; no-op on macOS.
    @ViewBuilder
    func navBarTitleDisplayMode(_ mode: PlatformTitleDisplayMode) -> some View {
        #if canImport(UIKit)
        switch mode {
        case .inline:
            self.navigationBarTitleDisplayMode(.inline)
        case .large:
            self.navigationBarTitleDisplayMode(.large)
        }
        #else
        self
        #endif
    }

    /// Sets the keyboard type on iOS; no-op on macOS.
    @ViewBuilder
    func platformKeyboardType(_ type: PlatformKeyboardType) -> some View {
        #if canImport(UIKit)
        switch type {
        case .emailAddress:
            self.keyboardType(.emailAddress)
        case .decimalPad:
            self.keyboardType(.decimalPad)
        case .numberPad:
            self.keyboardType(.numberPad)
        }
        #else
        self
        #endif
    }

    /// Sets text input autocapitalization on iOS; no-op on macOS.
    @ViewBuilder
    func platformTextInputAutocapitalization(_ mode: PlatformAutocapitalization) -> some View {
        #if canImport(UIKit)
        switch mode {
        case .never:
            self.textInputAutocapitalization(.never)
        }
        #else
        self
        #endif
    }
}

// MARK: - Platform-Agnostic Enums

/// Cross-platform enum mirroring NavigationBarItem.TitleDisplayMode.
enum PlatformTitleDisplayMode {
    case inline
    case large
}

/// Cross-platform enum mirroring UIKeyboardType cases used in this project.
enum PlatformKeyboardType {
    case emailAddress
    case decimalPad
    case numberPad
}

/// Cross-platform enum mirroring TextInputAutocapitalization cases used in this project.
enum PlatformAutocapitalization {
    case never
}

// MARK: - Cross-Platform Image from Data

/// Creates a SwiftUI `Image` from raw image data, using `UIImage` on iOS and `NSImage` on macOS.
@ViewBuilder
func platformImage(from data: Data) -> some View {
    #if canImport(UIKit)
    if let uiImage = UIImage(data: data) {
        Image(uiImage: uiImage)
            .resizable()
    }
    #elseif canImport(AppKit)
    if let nsImage = NSImage(data: data) {
        Image(nsImage: nsImage)
            .resizable()
    }
    #endif
}

// MARK: - Cross-Platform System Colors

extension Color {
    /// Secondary system background: `UIColor.secondarySystemBackground` on iOS,
    /// `NSColor.controlBackgroundColor` on macOS.
    static var secondarySystemBackground: Color {
        #if canImport(UIKit)
        Color(.secondarySystemBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    /// Separator color: `UIColor.separator` on iOS, `NSColor.separatorColor` on macOS.
    static var platformSeparator: Color {
        #if canImport(UIKit)
        Color(.separator)
        #else
        Color(nsColor: .separatorColor)
        #endif
    }
}
