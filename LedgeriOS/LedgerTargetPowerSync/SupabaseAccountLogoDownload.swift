import Foundation
import LedgerTargetCore

enum AccountLogoDownloadFailure: Error { case invalidConfiguration, invalidCredential, rejected, invalidBytes }

/// Private authenticated GET, with no signed URL, persistent HTTP cache, redirect
/// following or unbounded response allocation. Workspace authorization must be
/// rechecked by the caller after download before cache/display admission.
final class SupabaseAccountLogoDownload: @unchecked Sendable {
    private let baseURL: URL
    private let publishableKey: String
    private let accessToken: @Sendable () async throws -> String
    private let session: URLSession
    private let maximumBytes: Int64
    private let redirects = RefuseLogoRedirects()

    init(baseURL: URL, publishableKey: String, maximumBytes: Int64 = 64 * 1024 * 1024,
         accessToken: @escaping @Sendable () async throws -> String, session: URLSession? = nil) throws {
        let loopback = ["localhost", "127.0.0.1", "::1", "[::1]"].contains(baseURL.host?.lowercased() ?? "")
        guard baseURL.host != nil, baseURL.user == nil, baseURL.password == nil,
              baseURL.query == nil, baseURL.fragment == nil,
              baseURL.path.isEmpty || baseURL.path == "/",
              baseURL.scheme == "https" || (baseURL.scheme == "http" && loopback),
              maximumBytes > 0 else { throw AccountLogoDownloadFailure.invalidConfiguration }
        guard Self.headerSafe(publishableKey),
              publishableKey.hasPrefix("sb_publishable_") || Self.role(publishableKey) == "anon" else {
            throw AccountLogoDownloadFailure.invalidCredential
        }
        self.baseURL = baseURL
        self.publishableKey = publishableKey
        self.maximumBytes = maximumBytes
        self.accessToken = accessToken
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        self.session = session ?? URLSession(configuration: configuration)
    }

    func download(_ reference: AccountBusinessLogoReference) async throws -> Data {
        try await download(reference.downloadedImageReference)
    }

    func download(_ reference: DownloadedImageObjectReference) async throws -> Data {
        guard reference.byteCount <= maximumBytes else { throw AccountLogoDownloadFailure.invalidBytes }
        let token = try await accessToken()
        guard Self.headerSafe(token), Self.role(token) == "authenticated" else {
            throw AccountLogoDownloadFailure.invalidCredential
        }
        let url = baseURL.appendingPathComponent("storage/v1/object/authenticated/ledger-attachments")
            .appendingPathComponent(reference.storagePath)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.httpMethod = "GET"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(reference.mediaType, forHTTPHeaderField: "Accept")
        let (stream, response) = try await session.bytes(for: request, delegate: redirects)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url == url else { throw AccountLogoDownloadFailure.rejected }
        guard response.expectedContentLength < 0 || response.expectedContentLength == reference.byteCount else {
            throw AccountLogoDownloadFailure.invalidBytes
        }
        var data = Data()
        data.reserveCapacity(Int(min(reference.byteCount, 1_048_576)))
        for try await byte in stream {
            try Task.checkCancellation()
            guard data.count < reference.byteCount else { throw AccountLogoDownloadFailure.invalidBytes }
            data.append(byte)
        }
        guard data.count == reference.byteCount,
              try AttachmentContentSHA256.make(bytes: data) == reference.contentSHA256 else {
            throw AccountLogoDownloadFailure.invalidBytes
        }
        return data
    }

    private static func headerSafe(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { $0 > 32 && $0 < 127 }
    }

    // The server verifies the signature. This local check only refuses privileged
    // or inappropriate credential classes before any HTTP request is made.
    private static func role(_ token: String) -> String? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return claims["role"] as? String
    }
}

private final class RefuseLogoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
