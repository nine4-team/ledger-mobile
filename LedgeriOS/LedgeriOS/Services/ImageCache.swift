#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

extension PlatformImage {
    /// Base64-encoded PNG representation for embedding in HTML.
    var pngBase64: String? {
        #if canImport(UIKit)
        pngData()?.base64EncodedString()
        #elseif canImport(AppKit)
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return png.base64EncodedString()
        #endif
    }

    var estimatedDecodedByteCount: Int {
        #if canImport(UIKit)
        guard let cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
        #elseif canImport(AppKit)
        return representations
            .map { max(0, $0.pixelsWide) * max(0, $0.pixelsHigh) * 4 }
            .max() ?? 0
        #endif
    }
}

struct PreparedPlatformImage: @unchecked Sendable {
    let image: PlatformImage
}

enum PlatformImageDecoder {
    /// Image construction and display preparation can allocate and populate large
    /// pixel buffers. Keep that work away from SwiftUI's main actor.
    static func decode(_ data: Data) async -> PreparedPlatformImage? {
        let decodeTask = Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled, let sourceImage = PlatformImage(data: data) else {
                return nil as PreparedPlatformImage?
            }

            #if canImport(UIKit)
            let preparedImage = sourceImage.preparingForDisplay() ?? sourceImage
            #elseif canImport(AppKit)
            var proposedRect = CGRect(origin: .zero, size: sourceImage.size)
            let preparedImage: PlatformImage
            if let cgImage = sourceImage.cgImage(
                forProposedRect: &proposedRect,
                context: nil,
                hints: nil
            ) {
                preparedImage = PlatformImage(cgImage: cgImage, size: sourceImage.size)
            } else {
                preparedImage = sourceImage
            }
            #endif

            guard !Task.isCancelled else { return nil }
            return PreparedPlatformImage(image: preparedImage)
        }

        return await withTaskCancellationHandler {
            await decodeTask.value
        } onCancel: {
            decodeTask.cancel()
        }
    }
}

/// Shared in-memory image cache backed by NSCache.
/// Prevents thumbnail flashes when SwiftUI destroys and recreates `FirebaseImage` views
/// (e.g. during GroupedItemCard expand/collapse).
@MainActor
enum ImageCache {
    private static let cache: NSCache<NSString, PlatformImage> = {
        let cache = NSCache<NSString, PlatformImage>()
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB
        return cache
    }()

    /// Synchronous cache lookup. Returns nil on miss.
    static func image(for key: String) -> PlatformImage? {
        cache.object(forKey: key as NSString)
    }

    /// Store an image using its in-memory footprint as the cache cost.
    /// Compressed thumbnails can be a tiny fraction of their decoded pixel buffers,
    /// so charging only downloaded bytes defeats the cache's memory limit.
    static func store(_ image: PlatformImage, for key: String, cost: Int) {
        let decodedCost = image.estimatedDecodedByteCount
        cache.setObject(
            image,
            forKey: key as NSString,
            cost: cacheCost(decodedByteCount: decodedCost, compressedByteCount: cost)
        )
        PerformanceDiagnostics.shared.event(
            "ImageCached",
            kind: "decoded-megabytes",
            count: 1,
            value: decodedCost / 1_048_576
        )
    }

    nonisolated static func cacheCost(decodedByteCount: Int, compressedByteCount: Int) -> Int {
        max(decodedByteCount, compressedByteCount)
    }
}
