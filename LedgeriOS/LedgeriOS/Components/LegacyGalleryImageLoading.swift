import Foundation
import SwiftUI

// Deliberately excluded from LedgerTargetProject.yml. Original URL call sites
// keep their loader; shared native presentation has no backend dependency.
extension ZoomableScrollView {
    init(url: URL?, zoomScale: Binding<CGFloat>,
         onSingleTap: (() -> Void)? = nil,
         annotations: [ZoomableImageAnnotation] = [],
         annotationSelectionEnabled: Bool = true,
         onImageTap: ((CGPoint) -> Void)? = nil,
         onAnnotationTap: ((String) -> Void)? = nil) {
        self.init(source: GalleryImageSource(identity: url?.absoluteString ?? "",
            load: { guard let url else { return nil }; return await LegacyGalleryImageLoading.load(url) }),
            zoomScale: zoomScale, onSingleTap: onSingleTap, annotations: annotations,
            annotationSelectionEnabled: annotationSelectionEnabled,
            onImageTap: onImageTap, onAnnotationTap: onAnnotationTap)
    }
}

@MainActor
private enum LegacyGalleryImageLoading {
    static func load(_ url: URL) async -> GalleryPlatformImage? {
        let cacheKey = url.absoluteString
        if let image = ImageCache.image(for: cacheKey) {
            PerformanceDiagnostics.shared.event("ImageCache", kind: "zoomable-hit")
            return image
        }
        PerformanceDiagnostics.shared.adjustCounter("active-zoomable-image-requests", delta: 1)
        defer { PerformanceDiagnostics.shared.adjustCounter("active-zoomable-image-requests", delta: -1) }
        do {
            let loadableURL: URL
            if url.scheme == "gs" {
                guard let resolved = await StorageURLResolver.resolve(url.absoluteString) else { return nil }
                loadableURL = resolved
            } else { loadableURL = url }
            let (data, _) = try await URLSession.shared.data(from: loadableURL)
            try Task.checkCancellation()
            guard let image = await ZoomableImageLoader.prepare(data) else { return nil }
            try Task.checkCancellation()
            ImageCache.store(image, for: cacheKey, cost: data.count)
            return image
        } catch { return nil }
    }
}

enum ZoomableImageLoader {
    static func prepare(_ data: Data) async -> PlatformImage? {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let preparedImage = await PlatformImageDecoder.decode(data)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
        PerformanceDiagnostics.shared.duration(
            "ZoomableImageDecode",
            kind: preparedImage == nil ? "failed" : "success",
            milliseconds: elapsed,
            count: preparedImage?.image.estimatedDecodedByteCount ?? 0,
            value: data.count
        )
        return preparedImage?.image
    }
}
