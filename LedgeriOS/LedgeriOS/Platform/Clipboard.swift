import SwiftUI
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum Clipboard {
    enum ImageFailure: LocalizedError {
        case unavailable, unsupportedType, writeFailed
        var errorDescription: String? {
            switch self {
            case .unavailable: "No supported image was available to paste. Copy an image and try again."
            case .unsupportedType: "This file is not a supported image."
            case .writeFailed: "The image could not be copied. Please try again."
            }
        }
    }

    /// Explicit user actions only. Preserve the original representation; never
    /// substitute an authenticated URL or decode/re-encode the image.
    @MainActor static func copyImage(_ data: Data, mediaType: String) throws {
        guard !data.isEmpty, let type = UTType(mimeType: mediaType), type.conforms(to: .image) else {
            throw ImageFailure.unsupportedType
        }
        #if canImport(UIKit)
        UIPasteboard.general.setData(data, forPasteboardType: type.identifier)
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setData(data, forType: .init(type.identifier)) else {
            throw ImageFailure.writeFailed
        }
        #endif
    }

    /// Do not call this to decide whether a Paste control should be shown.
    @MainActor static func pastedImage() throws -> (data: Data, contentType: UTType) {
        #if canImport(UIKit)
        let identifiers = UIPasteboard.general.types
        #elseif canImport(AppKit)
        let identifiers = NSPasteboard.general.types?.map(\.rawValue) ?? []
        #endif
        for identifier in identifiers {
            guard let type = UTType(identifier), type.conforms(to: .image) else { continue }
            #if canImport(UIKit)
            let data = UIPasteboard.general.data(forPasteboardType: identifier)
            #elseif canImport(AppKit)
            let data = NSPasteboard.general.data(forType: .init(identifier))
            #endif
            if let data, !data.isEmpty { return (data, type) }
        }
        throw ImageFailure.unavailable
    }

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
