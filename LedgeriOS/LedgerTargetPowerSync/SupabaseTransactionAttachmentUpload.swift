import Foundation
import LedgerTargetCore

public struct TransactionAttachmentUploadReservation: Equatable, Sendable {
    public let attachmentId: AttachmentID
    public let accountId: AccountID
    public let principalId: PrincipalID
    public let transactionId: EntityID
    public let section: TransactionAttachmentSection
    public let bucket: String
    public let storagePath: String
    public let contentSHA256: AttachmentContentSHA256
    public let byteCount: UInt64
    public let mediaType: String

    init(response: ReservationResponse) throws {
        guard response.phase == "awaiting_upload",
              response.bucket == "ledger-attachments",
              let byteCount = UInt64(response.byteCount),
              byteCount > 0,
              byteCount <= 64 * 1024 * 1024 else {
            throw SupabaseTransactionAttachmentUploadFailure.invalidReservation
        }
        attachmentId = try AttachmentID(validating: response.attachmentId)
        accountId = try AccountID(validating: response.accountId)
        principalId = try PrincipalID(validating: response.principalId)
        transactionId = try EntityID(validating: response.transactionId)
        guard let section = TransactionAttachmentSection(rawValue: response.section),
              response.storagePath == "accounts/\(response.accountId)/attachments/\(response.attachmentId)/\(response.contentSHA256)" else {
            throw SupabaseTransactionAttachmentUploadFailure.invalidReservation
        }
        self.section = section
        bucket = response.bucket
        storagePath = response.storagePath
        contentSHA256 = try AttachmentContentSHA256(validating: response.contentSHA256)
        self.byteCount = byteCount
        mediaType = response.mediaType
    }
}

public struct TransactionAttachmentUploadCheckpoint: Codable, Equatable, Sendable {
    public let uploadURL: URL
    public let offset: UInt64

    public init(uploadURL: URL, offset: UInt64) {
        self.uploadURL = uploadURL
        self.offset = offset
    }
}

public enum TransactionAttachmentPublication: Codable, Equatable, Sendable {
    case incomplete
    case applied(revision: Int64, position: Int)
    case rejected(code: String)
}

public enum SupabaseTransactionAttachmentUploadFailure: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidCredential
    case unsupportedReceipt
    case candidateMismatch
    case invalidResponse
    case requestRejected(statusCode: Int)
    case invalidReservation
    case reservationMismatch
    case invalidCheckpoint
    case expiredCheckpoint
    case invalidServerOffset
}

/// Authenticated admission plus TUS transfer. Publication and server-side byte
/// verification are intentionally separate; successful transfer must not drain
/// the durable local capture queue.
public final class SupabaseTransactionAttachmentUpload: @unchecked Sendable {
    public typealias AccessTokenProvider = @Sendable () async throws -> String
    public typealias CheckpointHandler = @Sendable (TransactionAttachmentUploadCheckpoint) async throws -> Void

    static let chunkSize = 6 * 1024 * 1024

    private let reservationURL: URL
    let supabaseURL: URL
    private let verificationURL: URL
    private let resumableURL: URL
    private let storageOrigin: URL
    private let publishableKey: String
    private let accessToken: AccessTokenProvider
    private let session: URLSession

    public init(
        supabaseURL: URL,
        storageURL: URL? = nil,
        publishableKey: String,
        accessToken: @escaping AccessTokenProvider,
        session: URLSession? = nil
    ) throws {
        guard Self.validBaseURL(supabaseURL),
              Self.validPublishableCredential(publishableKey) else {
            throw SupabaseTransactionAttachmentUploadFailure.invalidConfiguration
        }
        let storageURL = storageURL ?? Self.defaultStorageURL(for: supabaseURL)
        guard Self.validBaseURL(storageURL) else {
            throw SupabaseTransactionAttachmentUploadFailure.invalidConfiguration
        }
        reservationURL = supabaseURL.appendingPathComponent(
            "rest/v1/rpc/spike_begin_transaction_attachment_upload"
        )
        self.supabaseURL = supabaseURL
        verificationURL = supabaseURL.appendingPathComponent("functions/v1/verify-transaction-attachment")
        resumableURL = storageURL.appendingPathComponent("storage/v1/upload/resumable")
        storageOrigin = storageURL
        self.publishableKey = publishableKey
        self.accessToken = accessToken
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.httpCookieStorage = nil
            self.session = URLSession(configuration: configuration)
        }
    }

    public func reserve(
        _ receipt: AttachmentLocalDurabilityReceipt
    ) async throws -> TransactionAttachmentUploadReservation {
        let claims = try Claims(receipt: receipt)
        let data = try JSONSerialization.data(withJSONObject: claims.rpcBody)
        let (responseData, response) = try await send(
            method: "POST",
            url: reservationURL,
            headers: [
                "Content-Type": "application/json",
                "Accept": "application/vnd.pgrst.object+json"
            ],
            body: data
        )
        guard response.statusCode == 200 else {
            throw SupabaseTransactionAttachmentUploadFailure.requestRejected(
                statusCode: response.statusCode
            )
        }
        let decoded: ReservationResponse
        do { decoded = try JSONDecoder().decode(ReservationResponse.self, from: responseData) }
        catch { throw SupabaseTransactionAttachmentUploadFailure.invalidResponse }
        let reservation: TransactionAttachmentUploadReservation
        do { reservation = try TransactionAttachmentUploadReservation(response: decoded) }
        catch { throw SupabaseTransactionAttachmentUploadFailure.invalidReservation }
        guard reservation.attachmentId == receipt.attachmentId,
              reservation.accountId == receipt.scope.accountId,
              reservation.principalId == receipt.scope.principalId,
              reservation.transactionId == receipt.scope.parent.id,
              reservation.section == claims.section,
              reservation.contentSHA256 == receipt.contentSHA256,
              reservation.byteCount == receipt.byteCount,
              reservation.mediaType == claims.mediaType else {
            throw SupabaseTransactionAttachmentUploadFailure.reservationMismatch
        }
        return reservation
    }

    /// Server publication is evidence to retain locally, not permission to delete
    /// captured bytes before authoritative reference readback.
    public func verifyAndPublish(
        _ reservation: TransactionAttachmentUploadReservation
    ) async throws -> TransactionAttachmentPublication {
        let (data, response) = try await send(method: "POST", url: verificationURL,
            headers: ["Content-Type": "application/json"],
            body: JSONSerialization.data(withJSONObject: ["attachmentId": reservation.attachmentId.rawValue]))
        guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SupabaseTransactionAttachmentUploadFailure.invalidResponse
        }
        if response.statusCode == 409, value["error"] as? String == "attachment_upload_incomplete" {
            return .incomplete
        }
        guard response.statusCode == 200 else {
            throw SupabaseTransactionAttachmentUploadFailure.requestRejected(statusCode: response.statusCode)
        }
        guard value["upload_id"] as? String == reservation.attachmentId.rawValue,
              value["account_id"] as? String == reservation.accountId.rawValue,
              value["principal_id"] as? String == reservation.principalId.rawValue,
              value["transaction_id"] as? String == reservation.transactionId.rawValue,
              value["section"] as? String == reservation.section.rawValue else {
            throw SupabaseTransactionAttachmentUploadFailure.reservationMismatch
        }
        if value["phase"] as? String == "applied",
           value["result_code"] as? String == "attachment_published",
           let revision = value["reference_revision"] as? NSNumber,
           let position = value["reference_position"] as? NSNumber,
           let exactRevision = Int64(revision.stringValue), exactRevision > 0,
           let exactPosition = Int(position.stringValue), (0..<50).contains(exactPosition),
           value["error_code"] is NSNull {
            return .applied(revision: exactRevision, position: exactPosition)
        }
        if value["phase"] as? String == "rejected",
           let code = value["error_code"] as? String, !code.isEmpty,
           value["result_code"] is NSNull,
           value["reference_revision"] is NSNull,
           value["reference_position"] is NSNull {
            return .rejected(code: code)
        }
        throw SupabaseTransactionAttachmentUploadFailure.invalidResponse
    }

    /// Check for a previous successful publication before transferring again:
    /// the prior attempt may have committed even when its response was lost.
    public func publish(
        _ candidate: AttachmentVerifiedUploadCandidate,
        resumeFrom checkpoint: TransactionAttachmentUploadCheckpoint? = nil,
        onCheckpoint: @escaping CheckpointHandler = { _ in },
        authorize: @escaping @Sendable () async throws -> Void = {}
    ) async throws -> TransactionAttachmentPublication {
        try await authorize()
        let reservation = try await reserve(candidate.receipt)
        try await authorize()
        let previous = try await verifyAndPublish(reservation)
        try await authorize()
        guard previous == .incomplete else { return previous }
        let save: CheckpointHandler = { checkpoint in
            try await onCheckpoint(checkpoint)
            try await authorize()
        }
        do {
            _ = try await upload(candidate, reservation: reservation,
                resumeFrom: checkpoint, onCheckpoint: save)
        } catch SupabaseTransactionAttachmentUploadFailure.expiredCheckpoint {
            // A completed upload may outlive its TUS session. Verify again before
            // opening a replacement session at the same immutable object path.
            try await authorize()
            let recovered = try await verifyAndPublish(reservation)
            try await authorize()
            guard recovered == .incomplete else { return recovered }
            _ = try await upload(candidate, reservation: reservation, onCheckpoint: save)
        }
        try await authorize()
        return try await verifyAndPublish(reservation)
    }

    public func upload(
        _ candidate: AttachmentVerifiedUploadCandidate,
        reservation: TransactionAttachmentUploadReservation,
        resumeFrom checkpoint: TransactionAttachmentUploadCheckpoint? = nil,
        onCheckpoint: @escaping CheckpointHandler = { _ in }
    ) async throws -> TransactionAttachmentUploadCheckpoint {
        let claims = try Claims(receipt: candidate.receipt)
        guard reservation.attachmentId == candidate.receipt.attachmentId,
              reservation.accountId == candidate.receipt.scope.accountId,
              reservation.principalId == candidate.receipt.scope.principalId,
              reservation.transactionId == candidate.receipt.scope.parent.id,
              reservation.section == claims.section,
              reservation.contentSHA256 == candidate.receipt.contentSHA256,
              reservation.byteCount == candidate.receipt.byteCount,
              reservation.mediaType == claims.mediaType else {
            throw SupabaseTransactionAttachmentUploadFailure.candidateMismatch
        }

        return try await uploadReservedBytes(candidate, bucket: reservation.bucket,
            storagePath: reservation.storagePath, mediaType: reservation.mediaType,
            byteCount: reservation.byteCount, resumeFrom: checkpoint, onCheckpoint: onCheckpoint)
    }

    /// Shared byte transport after the owning adapter validates its reservation.
    /// Expense and Transaction publication remain distinct; neither fabricates
    /// the other's parent record to use the same resumable upload implementation.
    func uploadReservedBytes(_ candidate: AttachmentVerifiedUploadCandidate,
        bucket: String, storagePath: String, mediaType: String, byteCount: UInt64,
        resumeFrom checkpoint: TransactionAttachmentUploadCheckpoint? = nil,
        onCheckpoint: @escaping CheckpointHandler = { _ in }) async throws -> TransactionAttachmentUploadCheckpoint {
        let receipt = candidate.receipt
        guard bucket == "ledger-attachments",
              storagePath == "accounts/\(receipt.scope.accountId.rawValue)/attachments/\(receipt.attachmentId.rawValue)/\(receipt.contentSHA256.rawValue)",
              receipt.metadata?.mediaType == mediaType, byteCount == receipt.byteCount,
              byteCount > 0, byteCount <= 64 * 1024 * 1024,
              UInt64(candidate.bytes.count) == byteCount,
              try AttachmentContentSHA256.make(bytes: candidate.bytes) == receipt.contentSHA256 else {
            throw SupabaseTransactionAttachmentUploadFailure.candidateMismatch
        }
        var progress: TransactionAttachmentUploadCheckpoint
        if let checkpoint {
            guard validUploadURL(checkpoint.uploadURL), checkpoint.offset <= byteCount else {
                throw SupabaseTransactionAttachmentUploadFailure.invalidCheckpoint
            }
            let (_, response) = try await send(method: "HEAD", url: checkpoint.uploadURL,
                headers: ["Tus-Resumable": "1.0.0"])
            if response.statusCode == 404 || response.statusCode == 410 {
                throw SupabaseTransactionAttachmentUploadFailure.expiredCheckpoint
            }
            guard response.statusCode == 200,
                  let offset = Self.unsignedHeader("Upload-Offset", response: response),
                  offset <= byteCount,
                  Self.unsignedHeader("Upload-Length", response: response).map({ $0 == byteCount }) ?? true else {
                throw SupabaseTransactionAttachmentUploadFailure.invalidServerOffset
            }
            progress = TransactionAttachmentUploadCheckpoint(uploadURL: checkpoint.uploadURL, offset: offset)
        } else {
            let metadata = Self.uploadMetadata([
                "bucketName": bucket,
                "objectName": storagePath,
                "contentType": mediaType,
                "cacheControl": "3600"
            ])
            let (_, response) = try await send(method: "POST", url: resumableURL, headers: [
                "Tus-Resumable": "1.0.0",
                "Upload-Length": String(byteCount),
                "Upload-Metadata": metadata
            ])
            guard response.statusCode == 201,
                  let rawLocation = response.value(forHTTPHeaderField: "Location"),
                  let uploadURL = URL(string: rawLocation, relativeTo: resumableURL)?.absoluteURL,
                  validUploadURL(uploadURL) else {
                if response.statusCode != 201 {
                    throw SupabaseTransactionAttachmentUploadFailure.requestRejected(
                        statusCode: response.statusCode
                    )
                }
                throw SupabaseTransactionAttachmentUploadFailure.invalidResponse
            }
            progress = TransactionAttachmentUploadCheckpoint(uploadURL: uploadURL, offset: 0)
        }
        try await onCheckpoint(progress)

        while progress.offset < byteCount {
            try Task.checkCancellation()
            let end = min(byteCount, progress.offset + UInt64(Self.chunkSize))
            let chunk = candidate.bytes.subdata(in: Int(progress.offset)..<Int(end))
            let (_, response) = try await send(method: "PATCH", url: progress.uploadURL, headers: [
                "Tus-Resumable": "1.0.0",
                "Upload-Offset": String(progress.offset),
                "Content-Type": "application/offset+octet-stream"
            ], body: chunk)
            guard response.statusCode == 204 else {
                throw SupabaseTransactionAttachmentUploadFailure.requestRejected(
                    statusCode: response.statusCode
                )
            }
            guard Self.unsignedHeader("Upload-Offset", response: response) == end else {
                throw SupabaseTransactionAttachmentUploadFailure.invalidServerOffset
            }
            progress = TransactionAttachmentUploadCheckpoint(uploadURL: progress.uploadURL, offset: end)
            try await onCheckpoint(progress)
        }
        return progress
    }

    func send(
        method: String,
        url: URL,
        headers: [String: String],
        body: Data? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        let token = try await accessToken()
        guard Self.headerSafe(token), Self.jwtRole(token) == "authenticated" else {
            throw SupabaseTransactionAttachmentUploadFailure.invalidCredential
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.url == url else {
            throw SupabaseTransactionAttachmentUploadFailure.invalidResponse
        }
        return (data, http)
    }

    private func validUploadURL(_ url: URL) -> Bool {
        guard url.user == nil, url.password == nil, url.fragment == nil,
              url.scheme?.lowercased() == storageOrigin.scheme?.lowercased(),
              url.host?.lowercased() == storageOrigin.host?.lowercased(),
              Self.effectivePort(url) == Self.effectivePort(storageOrigin) else { return false }
        return url.path.hasPrefix("/storage/v1/upload/resumable/")
    }

    private static func validBaseURL(_ url: URL) -> Bool {
        let loopback = ["localhost", "127.0.0.1", "::1", "[::1]"].contains(url.host?.lowercased() ?? "")
        return url.host != nil && url.user == nil && url.password == nil && url.query == nil &&
            url.fragment == nil && (url.path.isEmpty || url.path == "/") &&
            (url.scheme == "https" || (url.scheme == "http" && loopback))
    }

    private static func defaultStorageURL(for url: URL) -> URL {
        guard url.scheme == "https", let host = url.host,
              host.hasSuffix(".supabase.co"), !host.hasSuffix(".storage.supabase.co"),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.host = String(host.dropLast(".supabase.co".count)) + ".storage.supabase.co"
        return components.url ?? url
    }

    private static func validPublishableCredential(_ value: String) -> Bool {
        guard headerSafe(value) else { return false }
        return value.hasPrefix("sb_publishable_") || jwtRole(value) == "anon"
    }

    private static func headerSafe(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { $0 > 32 && $0 < 127 }
    }

    private static func jwtRole(_ token: String) -> String? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return claims["role"] as? String
    }

    private static func effectivePort(_ url: URL) -> Int? {
        url.port ?? (url.scheme == "https" ? 443 : (url.scheme == "http" ? 80 : nil))
    }

    private static func unsignedHeader(_ name: String, response: HTTPURLResponse) -> UInt64? {
        response.value(forHTTPHeaderField: name).flatMap(UInt64.init)
    }

    private static func uploadMetadata(_ values: [String: String]) -> String {
        values.keys.sorted().map { key in
            "\(key) \(Data(values[key]!.utf8).base64EncodedString())"
        }.joined(separator: ",")
    }
}

private struct Claims {
    let section: TransactionAttachmentSection
    let mediaType: String
    let rpcBody: [String: Any]

    init(receipt: AttachmentLocalDurabilityReceipt) throws {
        guard receipt.scope.parent.kind == .transaction,
              let metadata = receipt.metadata,
              let section = metadata.transactionSection,
              let placement = metadata.placement,
              receipt.byteCount > 0,
              receipt.byteCount <= 64 * 1024 * 1024 else {
            throw SupabaseTransactionAttachmentUploadFailure.unsupportedReceipt
        }
        self.section = section
        mediaType = metadata.mediaType
        rpcBody = [
            "p_id": receipt.attachmentId.rawValue,
            "p_account_id": receipt.scope.accountId.rawValue,
            "p_transaction_id": receipt.scope.parent.id.rawValue,
            "p_section": section.rawValue,
            "p_content_sha256": receipt.contentSHA256.rawValue,
            "p_byte_count": String(receipt.byteCount),
            "p_media_type": metadata.mediaType,
            "p_file_name": metadata.fileName ?? NSNull(),
            "p_local_position": String(placement.localPosition),
            "p_make_primary_if_empty": placement.makePrimaryIfEmpty
        ]
    }
}

struct ReservationResponse: Decodable {
    let attachmentId: String
    let accountId: String
    let principalId: String
    let transactionId: String
    let section: String
    let bucket: String
    let storagePath: String
    let contentSHA256: String
    let byteCount: String
    let mediaType: String
    let phase: String
}
