import SwiftUI
import UniformTypeIdentifiers

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

    @MainActor
    static var containsImage: Bool {
        #if canImport(UIKit)
        UIPasteboard.general.hasImages
        #elseif canImport(AppKit)
        NSPasteboard.general.canReadObject(forClasses: [NSImage.self])
        #else
        false
        #endif
    }

    @MainActor
    static func copyImage(data: Data) throws {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { throw ClipboardImageError.invalidImageData }
        UIPasteboard.general.image = image
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data) else { throw ClipboardImageError.invalidImageData }
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.writeObjects([image]) else {
            throw ClipboardImageError.copyFailed
        }
        #else
        throw ClipboardImageError.unsupportedPlatform
        #endif
    }

    @MainActor
    static func pastedImageData() throws -> Data {
        #if canImport(UIKit)
        guard let image = UIPasteboard.general.image,
              let data = image.pngData() else { throw ClipboardImageError.noImage }
        return data
        #elseif canImport(AppKit)
        guard let objects = NSPasteboard.general.readObjects(forClasses: [NSImage.self]),
              let image = objects.first as? NSImage,
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            throw ClipboardImageError.noImage
        }
        return data
        #else
        throw ClipboardImageError.unsupportedPlatform
        #endif
    }
}

enum ClipboardImageError: LocalizedError {
    case invalidImageData
    case copyFailed
    case noImage
    case unsupportedPlatform

    var errorDescription: String? {
        switch self {
        case .invalidImageData: "This file could not be copied as an image."
        case .copyFailed: "The image could not be copied."
        case .noImage: "There is no image on the clipboard."
        case .unsupportedPlatform: "Image copy and paste is not supported on this device."
        }
    }
}
