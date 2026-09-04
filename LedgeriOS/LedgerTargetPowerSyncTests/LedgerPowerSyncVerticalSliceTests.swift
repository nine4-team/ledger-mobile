import Foundation
import LedgerTargetCore
import PowerSync
import Testing
@testable import LedgerTargetPowerSync

@Suite("Ledger PowerSync Client vertical slice", .serialized)
struct LedgerPowerSyncVerticalSliceTests {
    @Test("Schema is valid and the database rejects unsafe path or key input")
    func schemaAndDatabaseInputValidation() throws {
        try LedgerPowerSyncSchema.schema.validate()

        #expect(throws: LedgerPowerSyncDatabaseFailure.invalidEncryptionKey) {
            try LedgerPowerSyncEncryptionKey(hexadecimal: "not-a-key")
        }
        let key = try Self.key()
        #expect(throws: LedgerPowerSyncDatabaseFailure.invalidDatabasePath) {
            try LedgerPowerSyncDatabaseFactory.open(
                absolutePath: "relative.sqlite",
                encryptionKey: key
            )
        }
        #expect(throws: LedgerPowerSyncDatabaseFailure.invalidDatabasePath) {
            try LedgerPowerSyncDatabaseFactory.open(
                absolutePath: "/tmp/not-a-database.txt",
                encryptionKey: key
            )
        }
    }

    @Test("Offline acceptance is encrypted, atomic, restart durable, and uploaded once")
    func encryptedRestartDurabilityAndUpload() async throws {
        let fixture = try DatabaseFixture()
        let firstDatabase = try fixture.open()
        let cipher = try await firstDatabase.get("PRAGMA cipher") { cursor in
            try cursor.getString(index: 0)
        }
        #expect(!cipher.isEmpty)

        let command = try Self.command()
        let store = ClientCreationPowerSyncStore(
            database: firstDatabase,
            now: { Self.acceptedAt }
        )
        let receipt = try await store.create(command)
        #expect(receipt.operationId == command.envelope.operationId)
        #expect(receipt.localState == .queued)

        let authoritativeClientCount = try await firstDatabase.get(
            sql: "SELECT count(*) AS count FROM spike_clients WHERE id = ?",
            parameters: [command.draft.clientId.rawValue]
        ) { cursor in
            try cursor.getInt64(name: "count")
        }
        let pendingClientCount = try await firstDatabase.get(
            sql: "SELECT count(*) AS count FROM spike_pending_clients WHERE id = ?",
            parameters: [command.draft.clientId.rawValue]
        ) { cursor in
            try cursor.getInt64(name: "count")
        }
        let operationCount = try await firstDatabase.get(
            sql: "SELECT count(*) AS count FROM spike_local_operations WHERE id = ?",
            parameters: [command.envelope.operationId.rawValue]
        ) { cursor in
            try cursor.getInt64(name: "count")
        }
        #expect(authoritativeClientCount == 0)
        #expect(pendingClientCount == 1)
        #expect(operationCount == 1)

        try await firstDatabase.close()
        let rawBytes = try Data(contentsOf: fixture.databaseURL)
        #expect(!String(decoding: rawBytes, as: UTF8.self).contains("North House"))

        let reopened = try fixture.open()
        let restoredPendingClientCount = try await reopened.get(
            sql: "SELECT count(*) AS count FROM spike_pending_clients WHERE id = ?",
            parameters: [command.draft.clientId.rawValue]
        ) { cursor in
            try cursor.getInt64(name: "count")
        }
        #expect(restoredPendingClientCount == 1)

        let queued = try await reopened.getNextCrudTransaction()
        #expect(queued?.crud.count == 1)
        #expect(queued?.crud.first?.table == LedgerPowerSyncTable.clientCommands)

        let applier = RecordingClientCreationApplier()
        let connector = LedgerPowerSyncUploadConnector(
            credentialProvider: { nil },
            clientCreationApplier: applier,
            now: { Self.observedAt }
        )
        try await connector.uploadData(database: reopened)
        #expect(await applier.requests == [Self.uploadRequest(for: command)])
        #expect(try await reopened.getNextCrudTransaction() == nil)
        let localState = try await reopened.get(
            sql: "SELECT local_state FROM spike_local_operations WHERE id = ?",
            parameters: [command.envelope.operationId.rawValue]
        ) { cursor in
            try cursor.getString(name: "local_state")
        }
        #expect(localState == "applied")
        let replay = try await ClientCreationPowerSyncStore(database: reopened).create(command)
        #expect(replay.localState == .applied)

        try await reopened.close(deleteDatabase: true)
        #expect(!FileManager.default.fileExists(atPath: fixture.databaseURL.path))
        fixture.removeDirectory()
    }

    @Test("A pending optimistic row cannot become authoritative after an earlier sync")
    func pendingRowRemainsPartialAfterEarlierSync() {
        #expect(ClientCoreDetailsPowerSyncQuery.snapshotQuality(
            hasPendingOperation: true,
            hasSynced: true,
            hasLastSyncedAt: true
        ) == .partial)
        #expect(ClientCoreDetailsPowerSyncQuery.snapshotQuality(
            hasPendingOperation: false,
            hasSynced: true,
            hasLastSyncedAt: true
        ) == .ready)
    }

    @Test("Swift and MCP share the exact Client command bytes and fingerprint")
    func crossRuntimeCanonicalCommand() throws {
        let command = try CreateClientCommand(
            operationId: OperationID(validating: "operation-mcp-client"),
            draft: ClientCreationDraft(
                accountId: AccountID(validating: "account-primary"),
                actorPrincipalId: PrincipalID(validating: "principal-owner"),
                operationContractVersion: OperationContractVersion(
                    validating: "client-create-v1"
                ),
                clientId: ClientID(validating: "client-mcp"),
                displayName: ClientDisplayName(validating: "MCP Client"),
                capturedAt: Self.capturedAt
            )
        )
        #expect(String(
            decoding: try OperationContractCodec.encode(command.envelope),
            as: UTF8.self
        ) == """
        {"accountId":"account-primary","actorPrincipalId":"principal-owner","clientCreatedAt":1788523200000,"contractVersion":"client-create-v1","operationId":"operation-mcp-client","payload":{"clientId":"client-mcp","displayName":"MCP Client"},"preconditions":[]}
        """)
        #expect(
            command.fingerprint.sha256
                == "afbf890c23952707ad3d7612747baba36be779853da9a6f107fde7285cc1cbf8"
        )
    }

    @Test("The local Client watcher renders optimistic data as partial, never authoritative")
    func optimisticReadinessIsHonest() async throws {
        let fixture = try DatabaseFixture()
        let database = try fixture.open()
        let command = try Self.command()
        let store = ClientCreationPowerSyncStore(
            database: database,
            now: { Self.acceptedAt }
        )
        _ = try await store.create(command)

        let request = try ClientCoreDetailsRequest(
            accountId: command.envelope.accountId,
            clientId: command.draft.clientId
        )
        let query = ClientCoreDetailsPowerSyncQuery(
            database: database,
            principalId: command.envelope.actorPrincipalId,
            accountId: command.envelope.accountId,
            now: { Self.observedAt }
        )
        var iterator = query.watchClientCoreDetails(request).makeAsyncIterator()
        let first = try await iterator.next()
        let second = try await iterator.next()

        guard case .waiting(.loading)? = first?.state else {
            Issue.record("Expected an explicit loading state before the first local query")
            try await database.close(deleteDatabase: true)
            fixture.removeDirectory()
            return
        }
        guard case .snapshot(let snapshot)? = second?.state else {
            Issue.record("Expected an optimistic local Client snapshot")
            try await database.close(deleteDatabase: true)
            fixture.removeDirectory()
            return
        }
        #expect(snapshot.local.quality == .partial)
        #expect(snapshot.local.isCompleteForQuery == false)
        #expect(snapshot.isAuthoritativeAbsence == false)
        #expect(snapshot.row?.client.id == command.draft.clientId)
        #expect(snapshot.row?.client.displayName == command.draft.displayName)
        #expect(snapshot.row?.locallyObservedRevision == ExpectedClientRevision(1))

        try await database.close(deleteDatabase: true)
        fixture.removeDirectory()
    }

    @Test("Authoritative Client readback removes its local optimistic overlay")
    func authoritativeReadbackReconcilesPendingClient() async throws {
        let fixture = try DatabaseFixture()
        let database = try fixture.open()
        let command = try Self.command()
        _ = try await ClientCreationPowerSyncStore(database: database).create(command)
        _ = try await database.execute(
            sql: """
            INSERT INTO spike_account_memberships (
              id, account_id, principal_id, role, state,
              can_manage_clients, can_manage_projects,
              can_manage_project_budgets, financial_access
            ) VALUES ('membership-owner', ?, ?, 'owner', 'active', 1, 1, 1, 'full')
            """,
            parameters: [
                command.envelope.accountId.rawValue,
                command.envelope.actorPrincipalId.rawValue
            ]
        )
        let createdAtMilliseconds = Int64(Self.capturedAt.timeIntervalSince1970 * 1_000)
        _ = try await database.execute(
            sql: """
            INSERT INTO spike_clients (
              id, account_id, display_name, lifecycle, revision,
              created_at_ms, updated_at_ms, created_by_principal_id
            ) VALUES (?, ?, ?, 'active', 1, ?, ?, ?)
            """,
            parameters: [
                command.draft.clientId.rawValue,
                command.envelope.accountId.rawValue,
                command.draft.displayName.rawValue,
                createdAtMilliseconds,
                createdAtMilliseconds,
                command.envelope.actorPrincipalId.rawValue
            ]
        )

        let request = try ClientCoreDetailsRequest(
            accountId: command.envelope.accountId,
            clientId: command.draft.clientId
        )
        var iterator = ClientCoreDetailsPowerSyncQuery(
            database: database,
            principalId: command.envelope.actorPrincipalId,
            accountId: command.envelope.accountId,
            now: { Self.observedAt }
        ).watchClientCoreDetails(request).makeAsyncIterator()
        _ = try await iterator.next()
        let update = try await iterator.next()

        guard case .snapshot(let snapshot)? = update?.state else {
            Issue.record("Expected authoritative Client snapshot")
            try await database.close(deleteDatabase: true)
            fixture.removeDirectory()
            return
        }
        #expect(snapshot.row?.client.id == command.draft.clientId)
        let pendingCount = try await database.get(
            sql: "SELECT count(*) FROM spike_pending_clients WHERE id = ?",
            parameters: [command.draft.clientId.rawValue]
        ) { cursor in
            try cursor.getInt64(index: 0)
        }
        #expect(pendingCount == 0)

        try await database.close(deleteDatabase: true)
        fixture.removeDirectory()
    }

    @Test("A repeated OperationID cannot be rebound locally")
    func replayCannotChangePayload() async throws {
        let fixture = try DatabaseFixture()
        let database = try fixture.open()
        let store = ClientCreationPowerSyncStore(database: database)
        let original = try Self.command()
        _ = try await store.create(original)

        let changed = try Self.command(
            operationId: original.envelope.operationId.rawValue,
            clientId: "client-changed"
        )
        await #expect(throws: OperationContractFailure.payloadMismatch(original.envelope.operationId)) {
            try await store.create(changed)
        }

        let pendingClientCount = try await database.get(
            "SELECT count(*) FROM spike_pending_clients"
        ) { cursor in
            try cursor.getInt64(index: 0)
        }
        #expect(pendingClientCount == 1)
        try await database.close(deleteDatabase: true)
        fixture.removeDirectory()
    }

    @Test("A durable server rejection drains the upload queue without reporting application")
    func durableRejectionDoesNotPoisonQueue() async throws {
        let fixture = try DatabaseFixture()
        let database = try fixture.open()
        let command = try Self.command()
        _ = try await ClientCreationPowerSyncStore(database: database).create(command)
        let connector = LedgerPowerSyncUploadConnector(
            credentialProvider: { nil },
            clientCreationApplier: RejectingClientCreationApplier(),
            now: { Self.observedAt }
        )

        try await connector.uploadData(database: database)

        #expect(try await database.getNextCrudTransaction() == nil)
        let localState = try await database.get(
            sql: "SELECT local_state FROM spike_local_operations WHERE id = ?",
            parameters: [command.envelope.operationId.rawValue]
        ) { cursor in
            try cursor.getString(name: "local_state")
        }
        #expect(localState == "rejected")
        let pendingClientCount = try await database.get(
            sql: "SELECT count(*) FROM spike_pending_clients WHERE id = ?",
            parameters: [command.draft.clientId.rawValue]
        ) { cursor in
            try cursor.getInt64(index: 0)
        }
        #expect(pendingClientCount == 0)
        let replay = try await ClientCreationPowerSyncStore(database: database).create(command)
        #expect(replay.localState == .rejected)
        try await database.close(deleteDatabase: true)
        fixture.removeDirectory()
    }

    @Test("Swift Supabase RPC sends the scoped user token and decodes the typed result")
    func swiftSupabaseRPCBoundary() async throws {
        let command = try Self.command()
        let baseRequest = Self.uploadRequest(for: command)
        let uploadRequest = ClientCreationUploadRequest(
            operationId: baseRequest.operationId,
            accountId: baseRequest.accountId,
            actorPrincipalId: baseRequest.actorPrincipalId,
            contractVersion: baseRequest.contractVersion,
            clientCreatedAtMilliseconds: baseRequest.clientCreatedAtMilliseconds + 123,
            clientId: baseRequest.clientId,
            displayName: baseRequest.displayName,
            fingerprint: baseRequest.fingerprint,
            envelopeJSON: baseRequest.envelopeJSON
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [RecordingURLProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        defer {
            session.invalidateAndCancel()
            RecordingURLProtocol.handler = nil
        }
        RecordingURLProtocol.handler = { request in
            #expect(request.url?.path == "/rest/v1/rpc/spike_create_client")
            #expect(request.value(forHTTPHeaderField: "apikey") == "publishable-key")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer user-token")
            let body = try requestBody(request)
            let json = try #require(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            #expect(json["p_operation_id"] as? String == uploadRequest.operationId)
            #expect(json["p_account_id"] as? String == uploadRequest.accountId)
            #expect(json["p_actor_principal_id"] as? String == uploadRequest.actorPrincipalId)
            #expect((json["p_client_created_at"] as? String)?.hasSuffix(".123Z") == true)
            #expect(json["p_envelope_json"] as? String == uploadRequest.envelopeJSON)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            let responseBody = try JSONSerialization.data(withJSONObject: [
                "operation_id": uploadRequest.operationId,
                "account_id": uploadRequest.accountId,
                "command_fingerprint": uploadRequest.fingerprint,
                "subject_id": uploadRequest.clientId,
                "phase": "applied",
                "result_code": "client_created",
                "error_code": NSNull()
            ])
            return (response, responseBody)
        }

        let rpc = try SupabaseClientCreationRPC(
            supabaseURL: URL(string: "https://target.invalid")!,
            publishableKey: "publishable-key",
            accessTokenProvider: { "user-token" },
            session: session
        )
        let result = try await rpc.apply(uploadRequest)
        #expect(result.phase == "applied")
        #expect(result.subjectId == command.draft.clientId.rawValue)

        #expect(throws: SupabaseClientCreationRPCFailure.invalidPublishableKey) {
            _ = try SupabaseClientCreationRPC(
                supabaseURL: URL(string: "https://target.invalid")!,
                publishableKey: "",
                accessTokenProvider: { "user-token" },
                session: session
            )
        }
        let emptyTokenRPC = try SupabaseClientCreationRPC(
            supabaseURL: URL(string: "https://target.invalid")!,
            publishableKey: "publishable-key",
            accessTokenProvider: { "" },
            session: session
        )
        await #expect(throws: SupabaseClientCreationRPCFailure.emptyAccessToken) {
            _ = try await emptyTokenRPC.apply(uploadRequest)
        }
    }

    private static let capturedAt = Date(timeIntervalSince1970: 1_788_523_200)
    private static let acceptedAt = Date(timeIntervalSince1970: 1_788_523_201)
    private static let observedAt = Date(timeIntervalSince1970: 1_788_523_202)

    private static func key() throws -> LedgerPowerSyncEncryptionKey {
        try LedgerPowerSyncEncryptionKey(hexadecimal: String(repeating: "1a", count: 32))
    }

    private static func command(
        operationId: String = "operation-create-client-north",
        clientId: String = "client-north"
    ) throws -> CreateClientCommand {
        try CreateClientCommand(
            operationId: OperationID(validating: operationId),
            draft: ClientCreationDraft(
                accountId: AccountID(validating: "account-primary"),
                actorPrincipalId: PrincipalID(validating: "principal-owner"),
                operationContractVersion: OperationContractVersion(
                    validating: "client-create-v1"
                ),
                clientId: ClientID(validating: clientId),
                displayName: ClientDisplayName(validating: "North House"),
                capturedAt: capturedAt
            )
        )
    }

    private static func uploadRequest(
        for command: CreateClientCommand
    ) -> ClientCreationUploadRequest {
        ClientCreationUploadRequest(
            operationId: command.envelope.operationId.rawValue,
            accountId: command.envelope.accountId.rawValue,
            actorPrincipalId: command.envelope.actorPrincipalId.rawValue,
            contractVersion: command.envelope.contractVersion.rawValue,
            clientCreatedAtMilliseconds: Int64(capturedAt.timeIntervalSince1970 * 1_000),
            clientId: command.draft.clientId.rawValue,
            displayName: command.draft.displayName.rawValue,
            fingerprint: command.fingerprint.sha256,
            envelopeJSON: String(
                decoding: try! OperationContractCodec.encode(command.envelope),
                as: UTF8.self
            )
        )
    }
}

private final class DatabaseFixture: @unchecked Sendable {
    let directoryURL: URL
    let databaseURL: URL
    private let key: LedgerPowerSyncEncryptionKey

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-powersync-\(UUID().uuidString)", isDirectory: true)
        databaseURL = directoryURL.appendingPathComponent("ledger.sqlite")
        key = try LedgerPowerSyncEncryptionKey(
            hexadecimal: String(repeating: "1a", count: 32)
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    func open() throws -> any PowerSyncDatabaseProtocol {
        try LedgerPowerSyncDatabaseFactory.open(
            absolutePath: databaseURL.path,
            encryptionKey: key
        )
    }

    func removeDirectory() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}

private actor RecordingClientCreationApplier: ClientCreationCommandApplying {
    private(set) var requests: [ClientCreationUploadRequest] = []

    func apply(_ request: ClientCreationUploadRequest) async throws -> ClientCreationServerResult {
        requests.append(request)
        return ClientCreationServerResult(
            operationId: request.operationId,
            accountId: request.accountId,
            commandFingerprint: request.fingerprint,
            subjectId: request.clientId,
            phase: "applied",
            resultCode: "client_created",
            errorCode: nil
        )
    }
}

private struct RejectingClientCreationApplier: ClientCreationCommandApplying {
    func apply(_ request: ClientCreationUploadRequest) async throws -> ClientCreationServerResult {
        ClientCreationServerResult(
            operationId: request.operationId,
            accountId: request.accountId,
            commandFingerprint: request.fingerprint,
            subjectId: request.clientId,
            phase: "rejected",
            resultCode: nil,
            errorCode: "client_creation_identity_conflict"
        )
    }
}

private final class RecordingURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw URLError(.badServerResponse)
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func requestBody(_ request: URLRequest) throws -> Data {
    if let body = request.httpBody { return body }
    let stream = try #require(request.httpBodyStream)
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1_024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
        if count == 0 { break }
        data.append(buffer, count: count)
    }
    return data
}
