import Foundation
import LedgerTargetCore
import Testing
@testable import LedgerTargetPowerSync

@Suite("Private Account logo download", .serialized)
struct SupabaseAccountLogoDownloadTests {
    @Test("Verified private GET uses only user credentials and exact immutable path")
    func download() async throws {
        let reference = try reference()
        LogoHTTPProtocol.handler = { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/storage/v1/object/authenticated/ledger-attachments/\(reference.storagePath)")
            #expect(request.value(forHTTPHeaderField: "apikey") == "sb_publishable_test")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.token)")
            return (200, [:], Data([1, 2, 3]))
        }
        let client = try client()
        #expect(try await client.download(reference) == Data([1, 2, 3]))
    }

    @Test("Reject HTTP denial, redirect, length mismatch, extra bytes and wrong hash", arguments: [0, 1, 2, 3, 4])
    func rejects(mode: Int) async throws {
        LogoHTTPProtocol.handler = { _ in
            switch mode {
            case 0: (403, [:], Data())
            case 1: (302, ["Location": "https://foreign.invalid/logo"], Data())
            case 2: (200, ["Content-Length": "99"], Data([1, 2, 3]))
            case 3: (200, [:], Data([1, 2, 3, 4]))
            default: (200, [:], Data([1, 2, 4]))
            }
        }
        let client = try client()
        await #expect(throws: AccountLogoDownloadFailure.self) { try await client.download(reference()) }
    }

    @Test("Unsafe endpoint, secret key, service token and oversized evidence fail before HTTP")
    func credentials() async throws {
        LogoHTTPProtocol.handler = { _ in
            Issue.record("Invalid configuration or credential reached HTTP")
            return (500, [:], Data())
        }
        #expect(throws: AccountLogoDownloadFailure.self) {
            try SupabaseAccountLogoDownload(baseURL: URL(string: "http://foreign.invalid")!,
                publishableKey: "sb_publishable_test", accessToken: { Self.token })
        }
        #expect(throws: AccountLogoDownloadFailure.self) {
            try SupabaseAccountLogoDownload(baseURL: URL(string: "https://profile.invalid")!,
                publishableKey: "sb_secret_test", accessToken: { Self.token })
        }
        let privileged = try client(token: "header.\(Data("{\"role\":\"service_role\"}".utf8).base64EncodedString()).signature")
        await #expect(throws: AccountLogoDownloadFailure.self) { try await privileged.download(reference()) }
        let bounded = try client(limit: 2)
        await #expect(throws: AccountLogoDownloadFailure.self) { try await bounded.download(reference()) }
    }

    private static let token = "header.\(Data("{\"role\":\"authenticated\"}".utf8).base64EncodedString()).signature"
    private func client(token: String = Self.token, limit: Int64 = 1024) throws -> SupabaseAccountLogoDownload {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LogoHTTPProtocol.self]
        return try SupabaseAccountLogoDownload(baseURL: URL(string: "https://profile.invalid")!,
            publishableKey: "sb_publishable_test", maximumBytes: limit,
            accessToken: { token }, session: URLSession(configuration: configuration))
    }
    private func reference() throws -> AccountBusinessLogoReference {
        let hash = try AttachmentContentSHA256.make(bytes: Data([1, 2, 3])).rawValue
        return try AccountBusinessLogoReference(accountId: AccountID(validating: "account"),
            attachmentId: "logo", sha256: hash, byteCount: "3", mediaType: "image/png",
            storagePath: "accounts/account/attachments/logo/\(hash)")
    }
}

private final class LogoHTTPProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, [String: String], Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler else { preconditionFailure("Missing synthetic response") }
        let (status, headers, data) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
