import Foundation
import LedgerTargetCore
#if canImport(ImageIO)
import ImageIO
#endif

public enum ItemCardThumbnailGenerationFailure: Error, Equatable, Sendable {
    case sourceTooLarge, sourceMismatch, invalidImage, encodingFailed, unsupportedPlatform
}

/// Verified derivative bytes, not permission to publish or read their original.
/// Publication must bind this exact original and recipe to a distinct object ID.
public struct GeneratedItemCardThumbnail: Equatable, Sendable {
    public let original: DownloadedImageObjectReference
    public let recipe: String
    public let bytes: Data
    public let contentSHA256: AttachmentContentSHA256
    public let byteCount: Int64
    public let width: Int
    public let height: Int
    public let mediaType: String
}

public enum ItemCardThumbnailGenerator {
    public static let recipe = "item-card-300-jpeg-v1"
    /// Matches the current authenticated image transport's original-byte limit.
    public static let maximumSourceBytes: Int64 = 64 * 1024 * 1024
    public static let maximumDimension = 300

    /// CPU work: callers should run this away from the UI actor. Uses the source
    /// utility's ImageIO orientation transform and quality-1 JPEG recipe, without
    /// its inferred filenames or an eager full-resolution decoded image.
    public static func generate(originalBytes: Data,
                                expectedOriginal: DownloadedImageObjectReference) throws -> GeneratedItemCardThumbnail {
        guard expectedOriginal.byteCount <= maximumSourceBytes,
              originalBytes.count <= maximumSourceBytes else { throw ItemCardThumbnailGenerationFailure.sourceTooLarge }
        guard originalBytes.count == expectedOriginal.byteCount,
              try AttachmentContentSHA256.make(bytes: originalBytes) == expectedOriginal.contentSHA256 else {
            throw ItemCardThumbnailGenerationFailure.sourceMismatch
        }
        #if canImport(ImageIO)
        guard let source = CGImageSourceCreateWithData(originalBytes as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let sourceWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let sourceHeight = properties[kCGImagePropertyPixelHeight] as? Int,
              sourceWidth > 0, sourceHeight > 0 else { throw ItemCardThumbnailGenerationFailure.invalidImage }
        // ImageIO can report complete and synthesize pixels for a truncated
        // JPEG. This recipe requires its explicit end marker, rather than
        // publishing that partial decode as a verified derivative.
        if CGImageSourceGetType(source) as String? == "public.jpeg",
           !originalBytes.suffix(2).elementsEqual([UInt8(0xff),UInt8(0xd9)]) {
            throw ItemCardThumbnailGenerationFailure.invalidImage
        }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        guard (1...8).contains(orientation) else { throw ItemCardThumbnailGenerationFailure.invalidImage }
        let limit = min(maximumDimension,max(sourceWidth,sourceHeight))
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: limit
        ] as CFDictionary) else { throw ItemCardThumbnailGenerationFailure.invalidImage }
        let rotated = (5...8).contains(orientation)
        guard CGImageSourceGetStatusAtIndex(source,0) == .statusComplete,
              image.width > 0, image.height > 0,
              image.width <= limit, image.height <= limit,
              image.width <= (rotated ? sourceHeight : sourceWidth),
              image.height <= (rotated ? sourceWidth : sourceHeight) else {
            throw ItemCardThumbnailGenerationFailure.invalidImage
        }
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(encoded as CFMutableData,
                "public.jpeg" as CFString, 1, nil) else { throw ItemCardThumbnailGenerationFailure.encodingFailed }
        CGImageDestinationAddImage(destination,image,[
            kCGImageDestinationLossyCompressionQuality: 1.0,
            kCGImagePropertyOrientation: 1
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination), encoded.length > 0 else {
            throw ItemCardThumbnailGenerationFailure.encodingFailed
        }
        let bytes = encoded as Data
        return try GeneratedItemCardThumbnail(original: expectedOriginal,recipe: recipe,bytes: bytes,
            contentSHA256: AttachmentContentSHA256.make(bytes: bytes),byteCount: Int64(bytes.count),
            width: image.width,height: image.height,mediaType: "image/jpeg")
        #else
        throw ItemCardThumbnailGenerationFailure.unsupportedPlatform
        #endif
    }
}
