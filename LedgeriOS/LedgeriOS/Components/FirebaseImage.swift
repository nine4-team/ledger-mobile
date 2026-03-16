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
        .task(id: effectiveUrl) {
            await resolveAndLoad()
        }
    }

    private var failureView: some View {
        Image(systemName: "exclamationmark.triangle")
            .foregroundStyle(BrandColors.textTertiary)
    }

    /// The URL to actually load — prefers thumbnail when available.
    private var effectiveUrl: String? {
        if let thumbnailUrl, !thumbnailUrl.isEmpty { return thumbnailUrl }
        return urlString
    }

    private func resolveAndLoad() async {
        // Reset state for new URL
        loadedImage = nil
        loadFailed = false

        guard let effectiveUrl, !effectiveUrl.isEmpty else {
            loadFailed = true
            return
        }

        // Synchronous cache check — before any await, so no placeholder frame is rendered
        if let cached = ImageCache.image(for: effectiveUrl) {
            loadedImage = cached
            return
        }

        // Resolve URL (gs:// needs async resolution, https:// is immediate)
        let url: URL?
        if effectiveUrl.hasPrefix("http://") || effectiveUrl.hasPrefix("https://") {
            url = URL(string: effectiveUrl)
        } else {
            url = await StorageURLResolver.resolve(effectiveUrl)
        }

        guard let url else {
            loadFailed = true
            return
        }

        // Download image bytes
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled else { return }

            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                loadFailed = true
                return
            }

            guard let image = PlatformImage(data: data) else {
                loadFailed = true
                return
            }
            ImageCache.store(image, for: effectiveUrl, cost: data.count)
            loadedImage = image
        } catch {
            if !Task.isCancelled {
                loadFailed = true
            }
        }
    }
}
