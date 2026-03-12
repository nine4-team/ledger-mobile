#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

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

    /// Store an image with its data byte count as cost.
    static func store(_ image: PlatformImage, for key: String, cost: Int) {
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }
}
