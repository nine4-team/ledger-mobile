import SwiftUI

/// Drop-in replacement for `AsyncImage` that also handles Firebase Storage `gs://` URLs.
/// For `https://` URLs, behaves identically to `AsyncImage`. For `gs://` URLs, resolves
/// the download URL via `StorageURLResolver` before loading.
struct FirebaseImage<Placeholder: View>: View {
    let urlString: String?
    let contentMode: ContentMode
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var resolvedURL: URL?
    @State private var isResolving = true
    @State private var resolveFailed = false

    init(
        url urlString: String?,
        contentMode: ContentMode = .fill,
        @ViewBuilder placeholder: @escaping () -> Placeholder = { ProgressView() }
    ) {
        self.urlString = urlString
        self.contentMode = contentMode
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if resolveFailed {
                failureView
            } else if isResolving {
                placeholder()
            } else if let resolvedURL {
                AsyncImage(url: resolvedURL) { phase in
                    switch phase {
                    case .empty:
                        placeholder()
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: contentMode)
                    case .failure:
                        failureView
                    @unknown default:
                        placeholder()
                    }
                }
            } else {
                failureView
            }
        }
        .task(id: urlString) {
            await resolveURL()
        }
    }

    private var failureView: some View {
        Image(systemName: "exclamationmark.triangle")
            .foregroundStyle(BrandColors.textTertiary)
    }

    private func resolveURL() async {
        guard let urlString, !urlString.isEmpty else {
            isResolving = false
            resolveFailed = true
            return
        }

        // Fast path: HTTP(S) URLs don't need resolution
        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
            resolvedURL = URL(string: urlString)
            isResolving = false
            resolveFailed = resolvedURL == nil
            return
        }

        // Resolve gs:// URLs
        if let url = await StorageURLResolver.resolve(urlString) {
            resolvedURL = url
            isResolving = false
        } else {
            isResolving = false
            resolveFailed = true
        }
    }
}
