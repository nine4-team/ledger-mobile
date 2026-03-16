import ImageIO
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - ThumbnailSize

enum ThumbnailSize: CaseIterable {
    case sm  // 300px — card squares, grid cells
    case md  // 800px — hero cards, larger previews

    var maxDimension: Int {
        switch self {
        case .sm: 300
        case .md: 800
        }
    }

    var quality: CGFloat { 1.0 }

    var suffix: String {
        switch self {
        case .sm: "_sm"
        case .md: "_md"
        }
    }
}

// MARK: - ImageThumbnailGenerator

/// Generates resized JPEG thumbnail data from source image data using ImageIO.
/// Pure utility — no Firebase or UI dependencies.
enum ImageThumbnailGenerator {

    /// Produces a resized JPEG `Data` from source image data.
    /// Returns `nil` if the source data is not a valid image or if the source is already
    /// smaller than `maxDimension` (to avoid upscaling small images and degrading quality).
    static func generateThumbnailData(
        from sourceData: Data,
        maxDimension: Int,
        quality: CGFloat
    ) -> Data? {
        guard let source = CGImageSourceCreateWithData(sourceData as CFData, nil) else { return nil }

        // Check source dimensions — skip if already smaller than target to avoid upscaling
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Int,
           let height = properties[kCGImagePropertyPixelHeight] as? Int,
           max(width, height) <= maxDimension {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        let mutableData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            mutableData as CFMutableData,
            "public.jpeg" as CFString,
            1,
            nil
        ) else { return nil }

        CGImageDestinationAddImage(dest, cgImage, [
            kCGImageDestinationLossyCompressionQuality: quality,
        ] as CFDictionary)

        guard CGImageDestinationFinalize(dest) else { return nil }
        return mutableData as Data
    }

    /// Convenience: generates thumbnail data for a predefined `ThumbnailSize`.
    static func generateThumbnailData(from sourceData: Data, size: ThumbnailSize) -> Data? {
        generateThumbnailData(from: sourceData, maxDimension: size.maxDimension, quality: size.quality)
    }

    /// Derives the thumbnail storage path from an original path.
    /// Example: `"accounts/x/items/y/image_0.jpg"` → `"accounts/x/items/y/image_0_sm.jpg"`
    static func thumbnailPath(for originalPath: String, size: ThumbnailSize) -> String {
        let nsPath = originalPath as NSString
        let ext = nsPath.pathExtension
        let withoutExt = nsPath.deletingPathExtension
        return "\(withoutExt)\(size.suffix).jpg"
    }

    /// Derives both sm and md thumbnail paths from an original path.
    static func thumbnailPaths(for originalPath: String) -> (sm: String, md: String) {
        (
            sm: thumbnailPath(for: originalPath, size: .sm),
            md: thumbnailPath(for: originalPath, size: .md)
        )
    }
}
