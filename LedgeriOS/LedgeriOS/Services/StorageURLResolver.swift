import Foundation
import FirebaseStorage

/// Resolves Firebase Storage `gs://` URLs to HTTPS download URLs.
/// Caches results in memory so each `gs://` URL is resolved only once per app session.
@MainActor
enum StorageURLResolver {
    private static var cache: [String: URL] = [:]

    /// Returns a loadable URL. If the input is already an HTTPS URL, returns it directly.
    /// If it's a `gs://` URL, resolves it via Firebase Storage SDK and caches the result.
    static func resolve(_ urlString: String) async -> URL? {
        // Already an HTTP(S) URL — pass through
        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
            return URL(string: urlString)
        }

        // Check cache
        if let cached = cache[urlString] {
            return cached
        }

        // Resolve gs:// URL via Firebase Storage SDK
        guard urlString.hasPrefix("gs://") else {
            return URL(string: urlString)
        }

        do {
            let ref = Storage.storage().reference(forURL: urlString)
            let downloadURL = try await ref.downloadURL()
            cache[urlString] = downloadURL
            return downloadURL
        } catch {
            print("⚠️ StorageURLResolver: failed to resolve \(urlString): \(error.localizedDescription)")
            return nil
        }
    }
}
