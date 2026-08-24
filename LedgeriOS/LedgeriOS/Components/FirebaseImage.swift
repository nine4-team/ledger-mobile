import SwiftUI

/// Drop-in replacement for `AsyncImage` that also handles Firebase Storage `gs://` URLs.
/// Uses a shared `ImageCache` so images survive view destruction/recreation without flashing.
///
/// When `thumbnailUrl` is provided, that URL is loaded instead of the primary URL.
/// This allows cards to load pre-generated smaller images while galleries use the full URL.
struct FirebaseImage<Placeholder: View>: View {
    let urlString: String?
    let thumbnailUrl: String?
    let contentMode: ContentMode
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var loadedImage: PlatformImage?
    @State private var loadFailed = false

    private struct LoadKey: Equatable {
        let urlString: String?
        let thumbnailUrl: String?
    }

    init(
        url urlString: String?,
        thumbnailUrl: String? = nil,
        contentMode: ContentMode = .fill,
        @ViewBuilder placeholder: @escaping () -> Placeholder = { ProgressView() }
    ) {
        self.urlString = urlString
        self.thumbnailUrl = thumbnailUrl
        self.contentMode = contentMode
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let loadedImage {
                #if canImport(UIKit)
                Image(uiImage: loadedImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                #elseif canImport(AppKit)
                Image(nsImage: loadedImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                #endif
            } else if loadFailed {
                failureView
            } else {
                placeholder()
            }
        }
        .task(id: loadKey) {
            PerformanceDiagnostics.shared.adjustCounter("active-image-requests", delta: 1)
            defer { PerformanceDiagnostics.shared.adjustCounter("active-image-requests", delta: -1) }
            await resolveAndLoadWithFallback(for: loadKey)
        }
    }

    private var failureView: some View {
        Image(systemName: "exclamationmark.triangle")
            .foregroundStyle(BrandColors.textTertiary)
    }

    private var loadKey: LoadKey {
        LoadKey(urlString: urlString, thumbnailUrl: thumbnailUrl)
    }

    private func resolveAndLoadWithFallback(for requestedKey: LoadKey) async {
        loadedImage = nil
        loadFailed = false

        let urls = [requestedKey.thumbnailUrl, requestedKey.urlString]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .reduce(into: [String]()) { uniqueUrls, value in
                if !uniqueUrls.contains(value) {
                    uniqueUrls.append(value)
                }
            }

        guard !urls.isEmpty else {
            PerformanceDiagnostics.shared.event("ImageRequestSkipped", kind: "missing-url")
            loadFailed = true
            return
        }

        for (index, url) in urls.enumerated() {
            guard !Task.isCancelled, loadKey == requestedKey else { return }
            if await resolveAndLoadWithTimeout(url, requestedKey: requestedKey) {
                return
            }
            PerformanceDiagnostics.shared.event(
                "ImageAttemptFailed",
                kind: index == 0 && urls.count > 1 ? "thumbnail" : "primary"
            )
        }

        if !Task.isCancelled, loadKey == requestedKey {
            loadFailed = true
        }
    }

    private func resolveAndLoadWithTimeout(_ requestedUrl: String, requestedKey: LoadKey) async -> Bool {
        let loader = Task {
            await resolveAndLoad(requestedUrl: requestedUrl, requestedKey: requestedKey)
        }
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            if loadKey == requestedKey, loadedImage == nil {
                loader.cancel()
            }
        }

        let didLoad = await loader.value
        watchdog.cancel()
        return didLoad
    }

    private func resolveAndLoad(requestedUrl: String, requestedKey: LoadKey) async -> Bool {
        // Synchronous cache check — before any await, so no placeholder frame is rendered
        if let cached = ImageCache.image(for: requestedUrl) {
            PerformanceDiagnostics.shared.event("ImageCache", kind: "hit")
            loadedImage = cached
            return true
        }
        PerformanceDiagnostics.shared.event("ImageCache", kind: "miss")

        // Resolve URL (gs:// needs async resolution, https:// is immediate)
        let resolveInterval = PerformanceDiagnostics.shared.beginInterval(
            "ImageURLResolve",
            kind: requestedUrl.hasPrefix("gs://") ? "storage" : "http"
        )
        let url: URL?
        if requestedUrl.hasPrefix("http://") || requestedUrl.hasPrefix("https://") {
            url = URL(string: requestedUrl)
        } else {
            url = await StorageURLResolver.resolve(requestedUrl)
        }
        PerformanceDiagnostics.shared.endInterval(resolveInterval, value: url == nil ? 0 : 1)

        guard !Task.isCancelled, loadKey == requestedKey else { return false }

        guard let url else {
            return false
        }

        // Download image bytes
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            let downloadInterval = PerformanceDiagnostics.shared.beginInterval("ImageDownload", kind: "network")
            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                PerformanceDiagnostics.shared.endInterval(downloadInterval, value: -1)
                throw error
            }
            PerformanceDiagnostics.shared.endInterval(downloadInterval, value: data.count / 1024)
            guard !Task.isCancelled else { return false }
            guard loadKey == requestedKey else { return false }

            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                return false
            }

            let decodeStartedAt = DispatchTime.now().uptimeNanoseconds
            guard let preparedImage = await PlatformImageDecoder.decode(data) else {
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - decodeStartedAt) / 1_000_000
                PerformanceDiagnostics.shared.duration(
                    "ImageDecode",
                    kind: "failed",
                    milliseconds: elapsed,
                    value: data.count / 1024
                )
                return false
            }
            let image = preparedImage.image
            let decodeElapsed = Double(DispatchTime.now().uptimeNanoseconds - decodeStartedAt) / 1_000_000
            PerformanceDiagnostics.shared.duration(
                "ImageDecode",
                kind: "success",
                milliseconds: decodeElapsed,
                count: image.estimatedDecodedByteCount / 1_048_576,
                value: data.count / 1024
            )
            ImageCache.store(image, for: requestedUrl, cost: data.count)
            loadedImage = image
            return true
        } catch {
            return false
        }
    }
}
