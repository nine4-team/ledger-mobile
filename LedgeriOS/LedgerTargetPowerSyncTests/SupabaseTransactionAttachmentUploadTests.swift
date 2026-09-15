import Foundation
import Testing
@testable import LedgerTargetCore
@testable import LedgerTargetPowerSync

@Suite("Supabase Transaction attachment resumable upload", .serialized)
struct SupabaseTransactionAttachmentUploadTests {
    @Test("Actual Expense receipt uses scoped RPC, existing TUS and byte verifier",
          .enabled(if: ProcessInfo.processInfo.environment["LEDGER_EXPENSE_LOCAL_TOKEN"] != nil,
                   "Run expense HTTP runner with --native-expense-media"))
    func actualLocalExpense() async throws {
        let env = ProcessInfo.processInfo.environment
        let fixture = try UploadFixture(bytes: Data("Native Expense receipt".utf8),
            account: #require(env["LEDGER_SALE_LOCAL_ACCOUNT"]), principal: #require(env["LEDGER_SALE_LOCAL_PRINCIPAL"]),
            transaction: #require(env["LEDGER_SALE_LOCAL_ITEM"]), attachment: #require(env["LEDGER_EXPENSE_LOCAL_ATTACHMENT"]),
            parentKind: .expense)
        let token = try #require(env["LEDGER_EXPENSE_LOCAL_TOKEN"])
        let transport = try SupabaseTransactionAttachmentUpload(
            supabaseURL: #require(URL(string: env["LEDGER_EXPENSE_SERVICE_URL"] ?? "http://127.0.0.1:54321")),
            publishableKey: #require(env["LEDGER_SALE_LOCAL_KEY"]), accessToken: { token })
        let client = SupabaseExpenseAttachmentUpload(transport: transport)
        let project = try EntityID(validating: #require(env["LEDGER_SALE_LOCAL_PROJECT"]))
        #expect(try await client.publish(fixture.candidate, projectId: project) == .verified)
        #expect(try await client.publish(fixture.candidate, projectId: project) == .verified)
    }

    @Test("Expense adapter preserves scoped admission and verified retry without retransferring")
    func expenseAdapter() async throws {
        let fixture = try UploadFixture(bytes: Data("expense receipt".utf8), parentKind: .expense)
        let project = try EntityID(validating: "expense-project")
        let result: [String: String] = [
            "attachmentId": fixture.receipt.attachmentId.rawValue, "accountId": fixture.receipt.scope.accountId.rawValue,
            "principalId": fixture.receipt.scope.principalId.rawValue, "expenseId": fixture.receipt.scope.parent.id.rawValue,
            "projectId": project.rawValue, "contentSHA256": fixture.receipt.contentSHA256.rawValue,
            "byteCount": String(fixture.bytes.count), "mediaType": "image/png",
        ]
        let reservation = try JSONSerialization.data(withJSONObject: result.merging([
            "phase": "awaiting_upload", "bucket": "ledger-attachments", "storagePath": fixture.storagePath,
        ]) { _, new in new })
        let verified = try JSONSerialization.data(withJSONObject: result.merging(["phase": "verified"]) { _, new in new })
        let http = UploadHTTPSequence { request, index in
            if index == 0 {
                #expect(request.url?.path == "/rest/v1/rpc/spike_begin_expense_attachment_upload")
                let body = try JSONSerialization.jsonObject(with: Self.requestBody(request)) as? [String: String]
                #expect(body?["p_project_id"] == project.rawValue)
                #expect(body?["p_expense_id"] == fixture.receipt.scope.parent.id.rawValue)
                #expect(body?["p_transaction_id"] == nil)
                return Self.response(status: 200, data: reservation)
            }
            #expect(request.url?.path == "/functions/v1/verify-expense-attachment")
            return Self.response(status: 200, data: verified)
        }
        let client = SupabaseExpenseAttachmentUpload(transport: try fixture.client(http: http))
        #expect(try await client.publish(fixture.candidate, projectId: project) == .verified)
        #expect(http.requestCount == 2)

        for field in ["accountId", "principalId", "projectId", "expenseId", "contentSHA256", "byteCount"] {
            var substituted = result
            substituted[field] = "substituted"
            substituted["phase"] = "awaiting_upload"
            substituted["bucket"] = "ledger-attachments"
            substituted["storagePath"] = fixture.storagePath
            let data = try JSONSerialization.data(withJSONObject: substituted)
            let wrong = UploadHTTPSequence { _, _ in Self.response(status: 200, data: data) }
            let denied = SupabaseExpenseAttachmentUpload(transport: try fixture.client(http: wrong))
            await #expect(throws: SupabaseTransactionAttachmentUploadFailure.reservationMismatch) {
                try await denied.reserve(fixture.receipt, projectId: project)
            }
        }
        let noRequests = UploadHTTPSequence { _, _ in Self.response(status: 500) }
        let cancelled = SupabaseExpenseAttachmentUpload(transport: try fixture.client(http: noRequests))
        await #expect(throws: CancellationError.self) {
            try await cancelled.publish(fixture.candidate, projectId: project, authorize: { throw CancellationError() })
        }
        #expect(noRequests.requestCount == 0)
    }

    @Test("Expense receipts reuse byte transport without Transaction admission")
    func expenseByteTransport() async throws {
        let fixture = try UploadFixture(bytes: Data("expense receipt".utf8), parentKind: .expense)
        #expect(fixture.receipt.scope.parent.kind == .expense)
        #expect(fixture.receipt.metadata?.transactionSection == nil)
        let http = UploadHTTPSequence { request, index in
            #expect(request.url?.path.hasPrefix("/storage/v1/upload/resumable") == true)
            if index == 0 {
                let metadata = try Self.decodedMetadata(request)
                #expect(metadata["objectName"] == fixture.storagePath)
                return Self.response(status: 201, headers: ["Location": "http://127.0.0.1:54321/storage/v1/upload/resumable/expense-token"])
            }
            let body = try Self.requestBody(request)
            #expect(body == fixture.bytes)
            return Self.response(status: 204, headers: ["Upload-Offset": String(fixture.bytes.count)])
        }
        let client = try fixture.client(http: http)
        await #expect(throws: SupabaseTransactionAttachmentUploadFailure.candidateMismatch) {
            try await client.uploadReservedBytes(fixture.candidate, bucket: "ledger-attachments",
                storagePath: "accounts/other/attachments/substituted", mediaType: "image/png", byteCount: UInt64(fixture.bytes.count))
        }
        #expect(http.requestCount == 0)
        let result = try await client.uploadReservedBytes(fixture.candidate, bucket: "ledger-attachments",
            storagePath: fixture.storagePath, mediaType: "image/png", byteCount: UInt64(fixture.bytes.count))
        #expect(result.offset == UInt64(fixture.bytes.count))
        #expect(http.requestCount == 2)
    }

    @Test("Learned local denial stops publication before its next request")
    func publicationAuthorization() async throws {
        let fixture = try UploadFixture(bytes: Data("receipt".utf8))
        let http = UploadHTTPSequence { _, _ in
            Self.response(status: 200, data: fixture.reservationJSON())
        }
        let client = try fixture.client(http: http)
        await #expect(throws: CancellationError.self) {
            try await client.publish(fixture.candidate, authorize: { throw CancellationError() })
        }
        #expect(http.requestCount == 0)
        await #expect(throws: CancellationError.self) {
            try await client.publish(fixture.candidate, authorize: {
                if http.requestCount > 0 { throw CancellationError() }
            })
        }
        #expect(http.requestCount == 1)
    }

    @Test("Publication distinguishes retryable missing bytes, confirmed results and substituted identity")
    func publication() async throws {
        let fixture = try UploadFixture(bytes: Data("receipt".utf8))
        let http = UploadHTTPSequence { request, _ in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/functions/v1/verify-transaction-attachment")
            return Self.response(status: 409, data: Data(#"{"error":"attachment_upload_incomplete"}"#.utf8))
        }
        let client = try fixture.client(http: http)
        #expect(try await client.verifyAndPublish(fixture.reservation) == .incomplete)
        let reservation = fixture.reservation
        let result: [String: Any] = [
            "upload_id": reservation.attachmentId.rawValue,
            "account_id": reservation.accountId.rawValue,
            "principal_id": reservation.principalId.rawValue,
            "transaction_id": reservation.transactionId.rawValue,
            "section": reservation.section.rawValue,
            "phase": "applied", "result_code": "attachment_published",
            "error_code": NSNull(), "reference_revision": 7, "reference_position": 0
        ]
        let applied = try JSONSerialization.data(withJSONObject: result)
        http.replace { _, _ in Self.response(status: 200, data: applied) }
        #expect(try await client.verifyAndPublish(reservation) == .applied(revision: 7, position: 0))
        http.replace { request, index in
            if index == 0 {
                return Self.response(status: 200, data: fixture.reservationJSON())
            }
            #expect(index == 1)
            #expect(request.url?.path == "/functions/v1/verify-transaction-attachment")
            return Self.response(status: 200, data: applied)
        }
        #expect(try await client.publish(fixture.candidate) == .applied(revision: 7, position: 0))
        #expect(http.requestCount == 2)

        let uploadURL = "http://127.0.0.1:54321/storage/v1/upload/resumable/recovery"
        http.replace { request, index in
            switch index {
            case 0: return Self.response(status: 200, data: fixture.reservationJSON())
            case 1: return Self.response(status: 409, data: Data(#"{"error":"attachment_upload_incomplete"}"#.utf8))
            case 2:
                #expect(request.httpMethod == "POST")
                return Self.response(status: 201, headers: ["Location": uploadURL])
            case 3:
                #expect(request.httpMethod == "PATCH")
                return Self.response(status: 204, headers: ["Upload-Offset": String(fixture.bytes.count)])
            default:
                #expect(index == 4)
                #expect(request.url?.path == "/functions/v1/verify-transaction-attachment")
                return Self.response(status: 200, data: applied)
            }
        }
        #expect(try await client.publish(fixture.candidate) == .applied(revision: 7, position: 0))
        #expect(http.requestCount == 5)
        var wrong = result
        wrong["account_id"] = "foreign-account"
        let substituted = try JSONSerialization.data(withJSONObject: wrong)
        http.replace { _, _ in Self.response(status: 200, data: substituted) }
        await #expect(throws: SupabaseTransactionAttachmentUploadFailure.reservationMismatch) {
            try await client.verifyAndPublish(reservation)
        }
        var rejected = result
        rejected["phase"] = "rejected"
        rejected["error_code"] = "attachment_section_full"
        for field in ["result_code", "reference_revision", "reference_position"] { rejected[field] = NSNull() }
        let rejection = try JSONSerialization.data(withJSONObject: rejected)
        http.replace { _, _ in Self.response(status: 200, data: rejection) }
        #expect(try await client.verifyAndPublish(reservation) == .rejected(code: "attachment_section_full"))
    }

    @Test("Reservation binds the complete durable receipt and rejects substituted server claims")
    func reservation() async throws {
        let fixture = try UploadFixture(bytes: Data("receipt".utf8))
        let http = UploadHTTPSequence { request, index in
            #expect(index == 0)
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/rest/v1/rpc/spike_begin_transaction_attachment_upload")
            #expect(request.value(forHTTPHeaderField: "apikey") == "sb_publishable_test")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.token)")
            let json = try #require(try JSONSerialization.jsonObject(with: try Self.requestBody(request)) as? [String: Any])
            #expect(json["p_id"] as? String == fixture.receipt.attachmentId.rawValue)
            #expect(json["p_transaction_id"] as? String == "transaction-upload")
            #expect(json["p_section"] as? String == "receipts")
            #expect(json["p_byte_count"] as? String == String(fixture.bytes.count))
            #expect(json["p_local_position"] as? String == "7")
            #expect(json["p_make_primary_if_empty"] as? Bool == true)
            return Self.response(status: 200, data: fixture.reservationJSON())
        }
        let client = try fixture.client(http: http)
        let reservation = try await client.reserve(fixture.receipt)
        #expect(reservation.storagePath == fixture.storagePath)
        #expect(reservation.contentSHA256 == fixture.receipt.contentSHA256)
        #expect(http.requestCount == 1)

        http.replace { _, _ in
            Self.response(status: 200, data: fixture.reservationJSON(account: "substituted"))
        }
        await #expect(throws: SupabaseTransactionAttachmentUploadFailure.reservationMismatch) {
            try await client.reserve(fixture.receipt)
        }
    }

    @Test("Fresh upload uses immutable TUS path and exact six-MiB chunks")
    func freshUpload() async throws {
        let bytes = Data(repeating: 0x2a, count: SupabaseTransactionAttachmentUpload.chunkSize + 11)
        let fixture = try UploadFixture(bytes: bytes)
        let uploadURL = URL(string: "http://127.0.0.1:54321/storage/v1/upload/resumable/upload-token")!
        let http = UploadHTTPSequence { request, index in
            switch index {
            case 0:
                #expect(request.httpMethod == "POST")
                #expect(request.url?.path == "/storage/v1/upload/resumable")
                #expect(request.value(forHTTPHeaderField: "Tus-Resumable") == "1.0.0")
                #expect(request.value(forHTTPHeaderField: "Upload-Length") == String(bytes.count))
                #expect(request.value(forHTTPHeaderField: "x-upsert") == nil)
                let metadata = try Self.decodedMetadata(request)
                #expect(metadata["bucketName"] == "ledger-attachments")
                #expect(metadata["objectName"] == fixture.storagePath)
                #expect(metadata["contentType"] == "image/png")
                return Self.response(status: 201, headers: ["Location": uploadURL.absoluteString])
            case 1:
                #expect(request.httpMethod == "PATCH")
                #expect(request.value(forHTTPHeaderField: "Upload-Offset") == "0")
                #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/offset+octet-stream")
                let body = try Self.requestBody(request)
                #expect(body.count == SupabaseTransactionAttachmentUpload.chunkSize)
                return Self.response(status: 204, headers: ["Upload-Offset": String(SupabaseTransactionAttachmentUpload.chunkSize)])
            default:
                #expect(request.httpMethod == "PATCH")
                #expect(request.value(forHTTPHeaderField: "Upload-Offset") == String(SupabaseTransactionAttachmentUpload.chunkSize))
                let body = try Self.requestBody(request)
                #expect(body == Data(repeating: 0x2a, count: 11))
                return Self.response(status: 204, headers: ["Upload-Offset": String(bytes.count)])
            }
        }
        let checkpoints = UploadCheckpointRecorder()
        let client = try fixture.client(http: http)
        let complete = try await client.upload(fixture.candidate, reservation: fixture.reservation,
            onCheckpoint: { await checkpoints.append($0) })
        #expect(complete == TransactionAttachmentUploadCheckpoint(uploadURL: uploadURL, offset: UInt64(bytes.count)))
        #expect(await checkpoints.snapshot().map(\.offset) == [0, UInt64(SupabaseTransactionAttachmentUpload.chunkSize), UInt64(bytes.count)])
        #expect(http.requestCount == 3)
    }

    @Test("Restart trusts the server HEAD offset, not the stale local offset")
    func resumedUpload() async throws {
        let bytes = Data(repeating: 0x5a, count: SupabaseTransactionAttachmentUpload.chunkSize + 5)
        let fixture = try UploadFixture(bytes: bytes)
        let uploadURL = URL(string: "http://127.0.0.1:54321/storage/v1/upload/resumable/resume-token")!
        let stale = TransactionAttachmentUploadCheckpoint(uploadURL: uploadURL, offset: 1)
        let http = UploadHTTPSequence { request, index in
            if index == 0 {
                #expect(request.httpMethod == "HEAD")
                #expect(request.httpBody == nil && request.httpBodyStream == nil)
                return Self.response(status: 200, headers: [
                    "Upload-Offset": String(SupabaseTransactionAttachmentUpload.chunkSize),
                    "Upload-Length": String(bytes.count)
                ])
            }
            #expect(request.httpMethod == "PATCH")
            #expect(request.value(forHTTPHeaderField: "Upload-Offset") == String(SupabaseTransactionAttachmentUpload.chunkSize))
            let body = try Self.requestBody(request)
            #expect(body == Data(repeating: 0x5a, count: 5))
            return Self.response(status: 204, headers: ["Upload-Offset": String(bytes.count)])
        }
        let checkpoints = UploadCheckpointRecorder()
        let complete = try await fixture.client(http: http).upload(
            fixture.candidate, reservation: fixture.reservation, resumeFrom: stale,
            onCheckpoint: { await checkpoints.append($0) }
        )
        #expect(complete.offset == UInt64(bytes.count))
        #expect(await checkpoints.snapshot().map(\.offset) == [UInt64(SupabaseTransactionAttachmentUpload.chunkSize), UInt64(bytes.count)])
        #expect(http.requestCount == 2)
    }

    @Test("Unsafe credentials, locations, expired checkpoints and dishonest offsets fail closed")
    func failures() async throws {
        let fixture = try UploadFixture(bytes: Data("receipt".utf8))
        let foreign = UploadHTTPSequence { _, _ in
            Self.response(status: 201, headers: ["Location": "https://foreign.invalid/storage/v1/upload/resumable/token"])
        }
        await #expect(throws: SupabaseTransactionAttachmentUploadFailure.invalidResponse) {
            try await fixture.client(http: foreign).upload(fixture.candidate, reservation: fixture.reservation)
        }
        let expiredURL = URL(string: "http://127.0.0.1:54321/storage/v1/upload/resumable/expired")!
        let expired = UploadHTTPSequence { _, _ in Self.response(status: 410) }
        await #expect(throws: SupabaseTransactionAttachmentUploadFailure.expiredCheckpoint) {
            try await fixture.client(http: expired).upload(fixture.candidate, reservation: fixture.reservation,
                resumeFrom: .init(uploadURL: expiredURL, offset: 0))
        }
        let dishonest = UploadHTTPSequence { _, _ in
            Self.response(status: 200, headers: ["Upload-Offset": "999", "Upload-Length": String(fixture.bytes.count)])
        }
        await #expect(throws: SupabaseTransactionAttachmentUploadFailure.invalidServerOffset) {
            try await fixture.client(http: dishonest).upload(fixture.candidate, reservation: fixture.reservation,
                resumeFrom: .init(uploadURL: expiredURL, offset: 0))
        }
        #expect(throws: SupabaseTransactionAttachmentUploadFailure.invalidConfiguration) {
            try fixture.client(http: foreign, key: "sb_secret_test")
        }
        let badToken = try fixture.client(http: foreign, token: "not-a-jwt")
        await #expect(throws: SupabaseTransactionAttachmentUploadFailure.invalidCredential) {
            try await badToken.reserve(fixture.receipt)
        }
    }

    @Test("Legacy, non-Transaction and metadata-incomplete receipts never reach the network")
    func unsupportedReceipt() async throws {
        let fixture = try UploadFixture(bytes: Data("receipt".utf8))
        let http = UploadHTTPSequence { _, _ in
            Issue.record("Unsupported receipt reached HTTP")
            return Self.response(status: 500)
        }
        let legacy = try fixture.receipt(metadata: nil)
        await #expect(throws: SupabaseTransactionAttachmentUploadFailure.unsupportedReceipt) {
            try await fixture.client(http: http).reserve(legacy)
        }
        let incomplete = try fixture.receipt(metadata: AttachmentCaptureMetadata(
            mediaType: "image/png", fileName: "receipt.png", transactionSection: .receipts
        ))
        await #expect(throws: SupabaseTransactionAttachmentUploadFailure.unsupportedReceipt) {
            try await fixture.client(http: http).reserve(incomplete)
        }
        #expect(http.requestCount == 0)
    }

    @Test("Actual local Storage resumes after an interrupted six-MiB chunk",
          .enabled(if: ProcessInfo.processInfo.environment["LEDGER_ATTACHMENT_LOCAL_URL"] != nil,
                   "Run scripts/test-local-transaction-attachment-upload.mjs"),
          .timeLimit(.minutes(1)))
    func actualLocalService() async throws {
        let environment = ProcessInfo.processInfo.environment
        let baseURLText = try #require(environment["LEDGER_ATTACHMENT_LOCAL_URL"])
        let baseURL = try #require(URL(string: baseURLText))
        let key = try #require(environment["LEDGER_ATTACHMENT_LOCAL_KEY"])
        let token = try #require(environment["LEDGER_ATTACHMENT_LOCAL_TOKEN"])
        let account = try #require(environment["LEDGER_ATTACHMENT_LOCAL_ACCOUNT"])
        let principal = try #require(environment["LEDGER_ATTACHMENT_LOCAL_PRINCIPAL"])
        let transaction = try #require(environment["LEDGER_ATTACHMENT_LOCAL_TRANSACTION"])
        let attachment = try #require(environment["LEDGER_ATTACHMENT_LOCAL_ATTACHMENT"])
        let bytes = Data(repeating: 0x7e, count: SupabaseTransactionAttachmentUpload.chunkSize + 17)
        let fixture = try UploadFixture(bytes: bytes, account: account, principal: principal,
            transaction: transaction, attachment: attachment)
        let client = try SupabaseTransactionAttachmentUpload(supabaseURL: baseURL,
            storageURL: baseURL, publishableKey: key, accessToken: { token })
        let reservation = try await client.reserve(fixture.receipt)
        #expect(try await client.reserve(fixture.receipt) == reservation)
        if environment["LEDGER_ATTACHMENT_VERIFY_EDGE"] == "1" {
            #expect(try await client.verifyAndPublish(reservation) == .incomplete)
        }
        let recorder = UploadCheckpointRecorder()
        await #expect(throws: LocalUploadInterruption.self) {
            try await client.upload(fixture.candidate, reservation: reservation, onCheckpoint: { checkpoint in
                await recorder.append(checkpoint)
                if checkpoint.offset == UInt64(SupabaseTransactionAttachmentUpload.chunkSize) {
                    throw LocalUploadInterruption()
                }
            })
        }
        let interrupted = try #require(await recorder.snapshot().last)
        #expect(interrupted.offset == UInt64(SupabaseTransactionAttachmentUpload.chunkSize))
        let complete = try await client.upload(fixture.candidate, reservation: reservation,
            resumeFrom: interrupted, onCheckpoint: { await recorder.append($0) })
        #expect(complete.offset == UInt64(bytes.count))

        let reference = try DownloadedMediaObjectReference(accountId: reservation.accountId,
            attachmentId: reservation.attachmentId.rawValue, sha256: reservation.contentSHA256.rawValue,
            byteCount: String(reservation.byteCount), mediaType: reservation.mediaType,
            storagePath: reservation.storagePath, kind: .image)
        let downloader = try SupabaseAccountLogoDownload(baseURL: baseURL, publishableKey: key,
            accessToken: { token })
        #expect(try await downloader.download(reference) == bytes)
    }

    fileprivate static let token = "header.\(Data("{\"role\":\"authenticated\"}".utf8).base64EncodedString()).signature"

    private static func response(status: Int, headers: [String: String] = [:], data: Data = Data()) -> UploadHTTPResponse {
        UploadHTTPResponse(status: status, headers: headers, data: data)
    }

    private static func decodedMetadata(_ request: URLRequest) throws -> [String: String] {
        try Dictionary(uniqueKeysWithValues: (request.value(forHTTPHeaderField: "Upload-Metadata") ?? "")
            .split(separator: ",").map { pair in
                let pieces = pair.split(separator: " ", maxSplits: 1)
                let key = String(try #require(pieces.first))
                let encoded = try #require(pieces.last)
                let bytes = try #require(Data(base64Encoded: String(encoded)))
                return (key, String(decoding: bytes, as: UTF8.self))
            })
    }

    private static func requestBody(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try #require(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
            if count == 0 { break }
            result.append(buffer, count: count)
        }
        return result
    }
}

private struct UploadFixture {
    let bytes: Data
    let receipt: AttachmentLocalDurabilityReceipt

    init(bytes: Data, account: String = "account-upload", principal: String = "principal-upload",
         transaction: String = "transaction-upload", attachment: String = "attachment-upload",
         parentKind: LedgerEntityKind = .transaction) throws {
        self.bytes = bytes
        receipt = try Self.makeReceipt(bytes: bytes, account: account, principal: principal,
            transaction: transaction, attachment: attachment, parentKind: parentKind, metadata: AttachmentCaptureMetadata(
            mediaType: "image/png", fileName: "Receipt original.png", transactionSection: parentKind == .transaction ? .receipts : nil,
            placement: AttachmentCapturePlacement(localPosition: 7, makePrimaryIfEmpty: true)
        ))
    }

    var storagePath: String {
        "accounts/\(receipt.scope.accountId.rawValue)/attachments/\(receipt.attachmentId.rawValue)/\(receipt.contentSHA256.rawValue)"
    }

    var candidate: AttachmentVerifiedUploadCandidate {
        AttachmentVerifiedUploadCandidate(receipt: receipt, bytes: bytes)
    }

    var reservation: TransactionAttachmentUploadReservation {
        try! TransactionAttachmentUploadReservation(response: try! JSONDecoder().decode(
            ReservationResponse.self, from: reservationJSON()
        ))
    }

    func client(http: UploadHTTPSequence, key: String = "sb_publishable_test",
                token: String = SupabaseTransactionAttachmentUploadTests.token) throws -> SupabaseTransactionAttachmentUpload {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UploadURLProtocol.self]
        UploadURLProtocol.sequence = http
        return try SupabaseTransactionAttachmentUpload(
            supabaseURL: URL(string: "http://127.0.0.1:54321")!, publishableKey: key,
            accessToken: { token }, session: URLSession(configuration: configuration)
        )
    }

    func reservationJSON(account: String? = nil) -> Data {
        let account = account ?? receipt.scope.accountId.rawValue
        let path = "accounts/\(account)/attachments/\(receipt.attachmentId.rawValue)/\(receipt.contentSHA256.rawValue)"
        return try! JSONSerialization.data(withJSONObject: [
            "attachmentId": receipt.attachmentId.rawValue, "accountId": account,
            "principalId": receipt.scope.principalId.rawValue, "transactionId": receipt.scope.parent.id.rawValue,
            "section": "receipts", "bucket": "ledger-attachments", "storagePath": path,
            "contentSHA256": receipt.contentSHA256.rawValue, "byteCount": String(bytes.count),
            "mediaType": "image/png", "phase": "awaiting_upload"
        ])
    }

    func receipt(metadata: AttachmentCaptureMetadata?) throws -> AttachmentLocalDurabilityReceipt {
        try Self.makeReceipt(bytes: bytes, account: receipt.scope.accountId.rawValue,
            principal: receipt.scope.principalId.rawValue, transaction: receipt.scope.parent.id.rawValue,
            attachment: receipt.attachmentId.rawValue, parentKind: receipt.scope.parent.kind, metadata: metadata)
    }

    private static func makeReceipt(bytes: Data, account: String, principal: String,
                                    transaction: String, attachment: String, parentKind: LedgerEntityKind = .transaction,
                                    metadata: AttachmentCaptureMetadata?) throws -> AttachmentLocalDurabilityReceipt {
        let scope = AttachmentCaptureScope(environment: .targetLocal,
            principalId: try PrincipalID(validating: principal),
            accountId: try AccountID(validating: account),
            parent: LedgerEntityReference(kind: parentKind, id: try EntityID(validating: transaction)))
        let capture = try LocalAttachmentCapture(attachmentId: try AttachmentID(validating: attachment),
            scope: scope, capturedAt: try AttachmentEpochMilliseconds(validating: 1), bytes: bytes, metadata: metadata)
        let evidence = try AttachmentPersistedLocalObjectEvidence(attachmentId: capture.attachmentId, scope: scope,
            localObjectId: try AttachmentLocalObjectID(validating: String(repeating: "d", count: 64)),
            byteCount: capture.byteCount, contentSHA256: capture.contentSHA256,
            persistedAt: try AttachmentEpochMilliseconds(validating: 2))
        return try AttachmentLocalDurabilityReceipt(accepting: capture, persistedEvidence: evidence)
    }
}

private struct LocalUploadInterruption: Error {}

private actor UploadCheckpointRecorder {
    private(set) var values: [TransactionAttachmentUploadCheckpoint] = []
    func append(_ value: TransactionAttachmentUploadCheckpoint) { values.append(value) }
    func snapshot() -> [TransactionAttachmentUploadCheckpoint] { values }
}

private struct UploadHTTPResponse {
    let status: Int
    let headers: [String: String]
    let data: Data
}

private final class UploadHTTPSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: @Sendable (URLRequest, Int) throws -> UploadHTTPResponse
    private var count = 0

    init(handler: @escaping @Sendable (URLRequest, Int) throws -> UploadHTTPResponse) {
        self.handler = handler
    }

    var requestCount: Int { lock.withLock { count } }

    func replace(_ replacement: @escaping @Sendable (URLRequest, Int) throws -> UploadHTTPResponse) {
        lock.withLock { handler = replacement; count = 0 }
    }

    func next(_ request: URLRequest) throws -> UploadHTTPResponse {
        try lock.withLock {
            defer { count += 1 }
            return try handler(request, count)
        }
    }
}

private final class UploadURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var sequence: UploadHTTPSequence?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let response = try Self.sequence?.next(request) else { preconditionFailure("Missing upload response") }
            let http = HTTPURLResponse(url: request.url!, statusCode: response.status,
                httpVersion: "HTTP/1.1", headerFields: response.headers)!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            if request.httpMethod != "HEAD" { client?.urlProtocol(self, didLoad: response.data) }
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
