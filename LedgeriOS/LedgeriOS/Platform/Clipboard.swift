import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum Clipboard {

    @MainActor
    static func copy(_ string: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = string
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }

    /// Copies a collection of strings joined by newlines. IDs are sorted for
    /// deterministic output so the same selection always yields the same paste.
    @MainActor
    static func copyLines<S: Sequence>(_ strings: S) where S.Element == String {
        copy(strings.sorted().joined(separator: "\n"))
    }
}
