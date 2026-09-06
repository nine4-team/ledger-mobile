import Foundation
import LedgerTargetCore
import PowerSync
import Testing
@testable import LedgerTargetPowerSync

@Suite("Ledger PowerSync Project setup vertical slice", .serialized)
struct ProjectPowerSyncVerticalSliceTests {
    @Test("Swift and MCP share exact Project command bytes and fingerprint")
    func crossRuntimeCanonicalProjectCommand() throws {
        let command = try CreateProjectCommand(
            operationId: OperationID(validating: "operation-mcp-project"),
            draft: ProjectSetupDraft(
                accountId: AccountID(validating: "account-primary"),
                actorPrincipalId: PrincipalID(validating: "principal-owner"),
                operationContractVersion: OperationContractVersion(
                    validating: "project-create-v1"
                ),
                projectId: ProjectID(validating: "project-mcp"),
                clientSelection: ProjectClientSelectionInput(
                    newClientId: ClientID(validating: "client-mcp-project"),
                    displayName: ClientDisplayName(validating: "MCP Project Client")
                ),
                displayName: ProjectDisplayName(validating: "  MCP Project  "),
                description: "Canonical description",
                categoryAllocations: [
                    try NullableCategoryAllocation(
                        categoryId: BudgetCategoryID(validating: "category-furnishings"),
                        allocation: nil
                    ),
                    try NullableCategoryAllocation(
                        categoryId: BudgetCategoryID(validating: "category-design-fee"),
                        allocation: Money(
                            minorUnits: 2_500,
                            currency: CurrencyCode(validating: "EUR")
                        )
                    ),
                    try NullableCategoryAllocation(
                        categoryId: BudgetCategoryID(validating: "category-zero"),
                        allocation: Money(
                            minorUnits: 0,
                            currency: CurrencyCode(validating: "USD")
                        )
                    )
                ],
                capturedAt: Self.capturedAt
            )
        )
        #expect(String(
            decoding: try OperationContractCodec.encode(command.envelope),
            as: UTF8.self
        ) == """
        {"accountId":"account-primary","actorPrincipalId":"principal-owner","clientCreatedAt":1788523200000,"contractVersion":"project-create-v1","operationId":"operation-mcp-project","payload":{"categoryAllocations":[{"allocation":{"currency":"EUR","minorUnits":2500},"categoryId":"category-design-fee"},{"categoryId":"category-furnishings"},{"allocation":{"currency":"USD","minorUnits":0},"categoryId":"category-zero"}],"clientSelection":{"clientId":"client-mcp-project","displayName":"MCP Project Client","kind":"new"},"description":"Canonical description","displayName":"  MCP Project  ","projectId":"project-mcp"},"preconditions":[]}
        """)
        #expect(
            command.fingerprint.sha256
                == "507d600f6eca70b87ad5afdae47f1846c6d9a99e18bbeec9fc391a8f5bf59558"
        )
    }

    @Test("Offline Project plus new Client and complete allocations survive restart atomically")
    func newClientProjectRestartDurability() async throws {
        let fixture = try ProjectDatabaseFixture()
        let database = try fixture.open()
        let command = try Self.newClientCommand()
        let receipt = try await ProjectSetupPowerSyncStore(
            database: database,
            now: { Self.acceptedAt }
        ).create(command)

        #expect(receipt.localState == .queued)
        #expect(try await Self.count("spike_pending_clients", database: database) == 1)
        #expect(try await Self.count("spike_pending_projects", database: database) == 1)
        #expect(try await Self.count("spike_local_operations", database: database) == 1)
        let acceptedCommand = try #require(try await database.getNextCrudTransaction())
        #expect(acceptedCommand.crud.count == 1)
        #expect(acceptedCommand.crud.first?.table == LedgerPowerSyncTable.projectCommands)
        #expect(
            try await Self.count(
                "spike_pending_project_category_allocations",
                database: database
            ) == 3
        )
        #expect(try await Self.count("spike_clients", database: database) == 0)
        #expect(try await Self.count("spike_projects", database: database) == 0)
        #expect(
            try await Self.text(
                "category_configuration_revision",
                from: LedgerPowerSyncTable.pendingProjects,
                id: command.draft.projectId.rawValue,
                database: database
            ) == "1"
        )
        #expect(
            try await Self.text(
                "typeof(category_configuration_revision)",
                from: LedgerPowerSyncTable.pendingProjects,
                id: command.draft.projectId.rawValue,
                database: database
            ) == "text"
        )

        try await database.close()
        #expect(!String(
            decoding: try Data(contentsOf: fixture.databaseURL),
            as: UTF8.self
        ).contains("New Client"))

        let reopened = try fixture.open()
        #expect(try await Self.count("spike_pending_projects", database: reopened) == 1)
        #expect(
            try await Self.text(
                "category_configuration_revision",
                from: LedgerPowerSyncTable.pendingProjects,
                id: command.draft.projectId.rawValue,
                database: reopened
            ) == "1"
        )
        #expect(
            try await Self.count(
                "spike_pending_project_category_allocations",
                database: reopened
            ) == 3
        )
        let queued = try #require(try await reopened.getNextCrudTransaction())
        #expect(queued.crud.count == 1)
        #expect(queued.crud.first?.table == LedgerPowerSyncTable.projectCommands)

        let query = ProjectCoreDetailsPowerSyncQuery(
            database: reopened,
            principalId: command.envelope.actorPrincipalId,
            accountId: command.envelope.accountId,
            now: { Self.observedAt }
        )
        let request = try ProjectCoreDetailsRequest(
            accountId: command.draft.accountId,
            projectId: command.draft.projectId
        )
        var iterator = query.watchProjectCoreDetails(request).makeAsyncIterator()
        _ = try await iterator.next()
        let update = try await iterator.next()
        guard case .snapshot(let snapshot)? = update?.state else {
            Issue.record("Expected an optimistic Project snapshot")
            try await reopened.close(deleteDatabase: true)
            fixture.removeDirectory()
            return
        }
        #expect(snapshot.local.quality == .partial)
        #expect(snapshot.local.isCompleteForQuery == false)
        #expect(snapshot.row?.project.client.displayName.rawValue == "New Client")
        #expect(snapshot.row?.project.displayName.rawValue == "  Lake House  ")
        #expect(snapshot.row?.project.description == "Canonical description")

        let applier = RecordingProjectCreationApplier()
        let connector = LedgerPowerSyncUploadConnector(
            credentialProvider: { nil },
            clientCreationApplier: UnusedClientCreationApplier(),
            projectCreationApplier: applier,
            now: { Self.observedAt }
        )
        try await connector.uploadData(database: reopened)
        #expect(await applier.requests.count == 1)
        #expect(
            await applier.requests.first?.categoryAllocationsJSON
                == (try Self.uploadRequest(command)).categoryAllocationsJSON
        )
        #expect(try await reopened.getNextCrudTransaction() == nil)
        #expect(try await Self.count("spike_pending_projects", database: reopened) == 1)
        #expect(try await Self.localState(command, database: reopened) == "applied")
        let replay = try await ProjectSetupPowerSyncStore(database: reopened).create(command)
        #expect(replay.localState == .applied)

        try await reopened.close(deleteDatabase: true)
        fixture.removeDirectory()
    }

    @Test("Simulated authoritative projection preserves full UInt64 text across restart")
    func categoryConfigurationRevisionTextDurability() async throws {
        let fixture = try ProjectDatabaseFixture()
        let database = try fixture.open()
        _ = try await database.execute(
            sql: """
            INSERT INTO \(LedgerPowerSyncTable.projects) (
              id, account_id, client_id, display_name, lifecycle, revision,
              category_configuration_revision, created_at_ms, updated_at_ms,
              created_by_principal_id
            ) VALUES (
              'project-config-max', 'account-primary', 'client-existing',
              'Maximum Configuration Revision', 'active', 1,
              '18446744073709551615', 1788696000000, 1788696000000,
              'principal-owner'
            )
            """,
            parameters: nil
        )

        #expect(
            try await Self.text(
                "category_configuration_revision",
                from: LedgerPowerSyncTable.projects,
                id: "project-config-max",
                database: database
            ) == "18446744073709551615"
        )
        #expect(
            try await Self.text(
                "typeof(category_configuration_revision)",
                from: LedgerPowerSyncTable.projects,
                id: "project-config-max",
                database: database
            ) == "text"
        )

        try await database.close()
        let reopened = try fixture.open()
        #expect(
            try await Self.text(
                "category_configuration_revision",
                from: LedgerPowerSyncTable.projects,
                id: "project-config-max",
                database: reopened
            ) == "18446744073709551615"
        )

        try await reopened.close(deleteDatabase: true)
        fixture.removeDirectory()
    }

    @Test("A mid-acceptance failure rolls back the complete pending Project aggregate")
    func failedAcceptanceRollsBackCompleteAggregate() async throws {
        let fixture = try ProjectDatabaseFixture()
        let database = try fixture.open()
        let command = try Self.newClientCommand()
        _ = try await database.execute(
            sql: """
            CREATE TRIGGER fail_project_allocation_insert
            INSTEAD OF INSERT ON spike_pending_project_category_allocations
            BEGIN
              SELECT RAISE(ABORT, 'injected pending allocation failure');
            END
            """,
            parameters: nil
        )

        await #expect(throws: (any Error).self) {
            _ = try await ProjectSetupPowerSyncStore(database: database).create(command)
        }

        #expect(try await Self.count("spike_local_operations", database: database) == 0)
        #expect(try await Self.count("spike_pending_clients", database: database) == 0)
        #expect(try await Self.count("spike_pending_projects", database: database) == 0)
        #expect(
            try await Self.count(
                "spike_pending_project_category_allocations",
                database: database
            ) == 0
        )
        #expect(try await Self.count("spike_project_commands", database: database) == 0)

        try await database.close(deleteDatabase: true)
        fixture.removeDirectory()
    }

    @Test("A rebound operation cannot split the pending Project aggregate")
    func reboundOperationLeavesOriginalAggregate() async throws {
        let fixture = try ProjectDatabaseFixture()
        let database = try fixture.open()
        let command = try Self.newClientCommand()
        let store = ProjectSetupPowerSyncStore(database: database)
        _ = try await store.create(command)
        let rebound = try CreateProjectCommand(
            operationId: command.envelope.operationId,
            draft: ProjectSetupDraft(
                accountId: command.envelope.accountId,
                actorPrincipalId: command.envelope.actorPrincipalId,
                operationContractVersion: command.envelope.contractVersion,
                projectId: ProjectID(validating: "project-rebound"),
                clientSelection: command.draft.clientSelection,
                displayName: ProjectDisplayName(validating: "Rebound Project"),
                description: nil,
                categoryAllocations: [],
                capturedAt: Self.capturedAt
            )
        )

        await #expect(
            throws: OperationContractFailure.payloadMismatch(
                command.envelope.operationId
            )
        ) {
            _ = try await store.create(rebound)
        }
        #expect(try await Self.count("spike_pending_projects", database: database) == 1)
        #expect(try await Self.count("spike_pending_clients", database: database) == 1)
        #expect(try await Self.count("spike_local_operations", database: database) == 1)
        let preservedCommand = try #require(try await database.getNextCrudTransaction())
        #expect(preservedCommand.crud.count == 1)
        #expect(preservedCommand.crud.first?.table == LedgerPowerSyncTable.projectCommands)
        #expect(
            try await Self.count(
                "spike_pending_project_category_allocations",
                database: database
            ) == 3
        )
        #expect(
            try await Self.text(
                "category_configuration_revision",
                from: LedgerPowerSyncTable.pendingProjects,
                id: command.draft.projectId.rawValue,
                database: database
            ) == "1"
        )

        try await database.close(deleteDatabase: true)
        fixture.removeDirectory()
    }

    @Test("Authoritative core readback retains allocation optimism until aggregate proof")
    func authoritativeReadbackReconcilesOnlyProjectCore() async throws {
        let fixture = try ProjectDatabaseFixture()
        let database = try fixture.open()
        let command = try Self.newClientCommand()
        _ = try await ProjectSetupPowerSyncStore(database: database).create(command)
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
        let timestamp = Int64(Self.capturedAt.timeIntervalSince1970 * 1_000)
        _ = try await database.execute(
            sql: """
            INSERT INTO spike_clients (
              id, account_id, display_name, lifecycle, revision,
              created_at_ms, updated_at_ms, created_by_principal_id
            ) VALUES (?, ?, ?, 'active', 1, ?, ?, ?)
            """,
            parameters: [
                command.draft.clientSelection.clientId.rawValue,
                command.envelope.accountId.rawValue,
                command.draft.clientSelection.newClientDisplayName?.rawValue,
                timestamp,
                timestamp,
                command.envelope.actorPrincipalId.rawValue
            ]
        )
        _ = try await database.execute(
            sql: """
            INSERT INTO spike_projects (
              id, account_id, client_id, display_name, description,
              lifecycle, revision, category_configuration_revision,
              created_at_ms, updated_at_ms,
              created_by_principal_id
            ) VALUES (?, ?, ?, ?, ?, 'active', 1, '1', ?, ?, ?)
            """,
            parameters: [
                command.draft.projectId.rawValue,
                command.envelope.accountId.rawValue,
                command.draft.clientSelection.clientId.rawValue,
                command.draft.displayName.rawValue,
                command.draft.description,
                timestamp,
                timestamp,
                command.envelope.actorPrincipalId.rawValue
            ]
        )

        let request = try ProjectCoreDetailsRequest(
            accountId: command.envelope.accountId,
            projectId: command.draft.projectId
        )
        var iterator = ProjectCoreDetailsPowerSyncQuery(
            database: database,
            principalId: command.envelope.actorPrincipalId,
            accountId: command.envelope.accountId,
            now: { Self.observedAt }
        ).watchProjectCoreDetails(request).makeAsyncIterator()
        _ = try await iterator.next()
        let update = try await iterator.next()
        guard case .snapshot(let snapshot)? = update?.state else {
            Issue.record("Expected authoritative Project snapshot")
            try await database.close(deleteDatabase: true)
            fixture.removeDirectory()
            return
        }
        #expect(snapshot.row?.project.id == command.draft.projectId)
        #expect(
            try await Self.text(
                "category_configuration_revision",
                from: LedgerPowerSyncTable.projects,
                id: command.draft.projectId.rawValue,
                database: database
            ) == "1"
        )
        #expect(try await Self.count("spike_pending_clients", database: database) == 0)
        #expect(try await Self.count("spike_pending_projects", database: database) == 0)
        #expect(
            try await Self.count(
                "spike_pending_project_category_allocations",
                database: database
            ) == 3
        )

        try await database.close(deleteDatabase: true)
        fixture.removeDirectory()
    }

    @Test("Existing Client branch adds no Client overlay and preserves zero categories")
    func existingClientWithNoCategories() async throws {
        let fixture = try ProjectDatabaseFixture()
        let database = try fixture.open()
        let command = try Self.existingClientCommand()
        _ = try await ProjectSetupPowerSyncStore(database: database).create(command)

        #expect(try await Self.count("spike_pending_clients", database: database) == 0)
        #expect(try await Self.count("spike_pending_projects", database: database) == 1)
        #expect(
            try await Self.count(
                "spike_pending_project_category_allocations",
                database: database
            ) == 0
        )
        let queued = try #require(try await database.getNextCrudTransaction())
        let request = try LedgerPowerSyncUploadConnector.projectCreationRequest(
            from: queued.crud
        )
        #expect(request.clientSelectionKind == "existing")
        #expect(request.newClientDisplayName == nil)
        #expect(request.categoryAllocationsJSON == "[]")
        #expect(request.description == nil)

        try await database.close(deleteDatabase: true)
        fixture.removeDirectory()
    }

    @Test("A Project rejection removes the entire optimistic aggregate")
    func rejectionRemovesAggregate() async throws {
        let fixture = try ProjectDatabaseFixture()
        let database = try fixture.open()
        let command = try Self.newClientCommand()
        _ = try await ProjectSetupPowerSyncStore(database: database).create(command)
        let connector = LedgerPowerSyncUploadConnector(
            credentialProvider: { nil },
            clientCreationApplier: UnusedClientCreationApplier(),
            projectCreationApplier: RejectingProjectCreationApplier(),
            now: { Self.observedAt }
        )

        try await connector.uploadData(database: database)

        #expect(try await database.getNextCrudTransaction() == nil)
        #expect(try await Self.count("spike_pending_clients", database: database) == 0)
        #expect(try await Self.count("spike_pending_projects", database: database) == 0)
        #expect(
            try await Self.count(
                "spike_pending_project_category_allocations",
                database: database
            ) == 0
        )
        #expect(try await Self.localState(command, database: database) == "rejected")
        let replay = try await ProjectSetupPowerSyncStore(database: database).create(command)
        #expect(replay.localState == .rejected)

        try await database.close(deleteDatabase: true)
        fixture.removeDirectory()
    }

    @Test("Client and Project command transactions dispatch in FIFO order")
    func mixedCommandDispatch() async throws {
        let fixture = try ProjectDatabaseFixture()
        let database = try fixture.open()
        let clientCommand = try Self.clientCommand()
        let projectCommand = try Self.existingClientCommand()
        _ = try await ClientCreationPowerSyncStore(database: database).create(clientCommand)
        _ = try await ProjectSetupPowerSyncStore(database: database).create(projectCommand)
        let clientApplier = RecordingClientApplier()
        let projectApplier = RecordingProjectCreationApplier()
        let connector = LedgerPowerSyncUploadConnector(
            credentialProvider: { nil },
            clientCreationApplier: clientApplier,
            projectCreationApplier: projectApplier
        )

        try await connector.uploadData(database: database)
        #expect(await clientApplier.requests.count == 1)
        #expect(await projectApplier.requests.isEmpty)
        try await connector.uploadData(database: database)
        #expect(await projectApplier.requests.count == 1)
        #expect(try await database.getNextCrudTransaction() == nil)

        try await database.close(deleteDatabase: true)
        fixture.removeDirectory()
    }

    @Test("Supabase Project RPC preserves JSON integer precision and nullable fields")
    func projectRPCBoundary() async throws {
        let command = try Self.newClientCommand(
            allocations: [
                try NullableCategoryAllocation(
                    categoryId: BudgetCategoryID(validating: "category-max"),
                    allocation: Money(
                        minorUnits: Int64.max,
                        currency: try CurrencyCode(validating: "USD")
                    )
                )
            ]
        )
        let request = try Self.uploadRequest(command)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProjectRecordingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
            ProjectRecordingURLProtocol.handler = nil
        }
        ProjectRecordingURLProtocol.handler = { urlRequest in
            let body = try projectRequestBody(urlRequest)
            let text = String(decoding: body, as: UTF8.self)
            #expect(text.contains("9223372036854775807"))
            let json = try #require(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            #expect(json["p_new_client_display_name"] as? String == "New Client")
            #expect(json["p_description"] as? String == "Canonical description")
            let response = try #require(HTTPURLResponse(
                url: urlRequest.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            let responseBody = try JSONSerialization.data(withJSONObject: [
                "operation_id": request.operationId,
                "account_id": request.accountId,
                "command_fingerprint": request.fingerprint,
                "subject_id": request.projectId,
                "phase": "applied",
                "result_code": "project_created",
                "error_code": NSNull()
            ])
            return (response, responseBody)
        }
        let rpc = try SupabaseProjectCreationRPC(
            supabaseURL: URL(string: "https://target.invalid")!,
            publishableKey: "publishable-key",
            accessTokenProvider: { "user-token" },
            session: session
        )

        let result = try await rpc.apply(request)
        #expect(result.phase == "applied")
    }

    private static let capturedAt = Date(timeIntervalSince1970: 1_788_523_200)
    private static let acceptedAt = Date(timeIntervalSince1970: 1_788_523_201)
    private static let observedAt = Date(timeIntervalSince1970: 1_788_523_202)

    private static func newClientCommand(
        allocations: [NullableCategoryAllocation]? = nil
    ) throws -> CreateProjectCommand {
        let resolvedAllocations = try allocations ?? [
            NullableCategoryAllocation(
                categoryId: BudgetCategoryID(validating: "category-furnishings"),
                allocation: nil
            ),
            NullableCategoryAllocation(
                categoryId: BudgetCategoryID(validating: "category-zero"),
                allocation: Money(
                    minorUnits: 0,
                    currency: CurrencyCode(validating: "USD")
                )
            ),
            NullableCategoryAllocation(
                categoryId: BudgetCategoryID(validating: "category-design-fee"),
                allocation: Money(
                    minorUnits: 2_500,
                    currency: CurrencyCode(validating: "EUR")
                )
            )
        ]
        return try CreateProjectCommand(
            operationId: OperationID(validating: "operation-create-project-lake"),
            draft: ProjectSetupDraft(
                accountId: AccountID(validating: "account-primary"),
                actorPrincipalId: PrincipalID(validating: "principal-owner"),
                operationContractVersion: OperationContractVersion(
                    validating: "project-create-v1"
                ),
                projectId: ProjectID(validating: "project-lake"),
                clientSelection: ProjectClientSelectionInput(
                    newClientId: ClientID(validating: "client-new"),
                    displayName: ClientDisplayName(validating: "New Client")
                ),
                displayName: ProjectDisplayName(validating: "  Lake House  "),
                description: "Canonical description",
                categoryAllocations: resolvedAllocations,
                capturedAt: capturedAt
            )
        )
    }

    private static func existingClientCommand() throws -> CreateProjectCommand {
        try CreateProjectCommand(
            operationId: OperationID(validating: "operation-create-project-existing"),
            draft: ProjectSetupDraft(
                accountId: AccountID(validating: "account-primary"),
                actorPrincipalId: PrincipalID(validating: "principal-owner"),
                operationContractVersion: OperationContractVersion(
                    validating: "project-create-v1"
                ),
                projectId: ProjectID(validating: "project-existing"),
                clientSelection: ProjectClientSelectionInput(
                    existing: ClientID(validating: "client-existing")
                ),
                displayName: ProjectDisplayName(validating: "Existing Client Project"),
                description: nil,
                categoryAllocations: [],
                capturedAt: capturedAt
            )
        )
    }

    private static func clientCommand() throws -> CreateClientCommand {
        try CreateClientCommand(
            operationId: OperationID(validating: "operation-create-client-first"),
            draft: ClientCreationDraft(
                accountId: AccountID(validating: "account-primary"),
                actorPrincipalId: PrincipalID(validating: "principal-owner"),
                operationContractVersion: OperationContractVersion(
                    validating: "client-create-v1"
                ),
                clientId: ClientID(validating: "client-first"),
                displayName: ClientDisplayName(validating: "First Client"),
                capturedAt: capturedAt
            )
        )
    }

    private static func uploadRequest(
        _ command: CreateProjectCommand
    ) throws -> ProjectCreationUploadRequest {
        let envelope = String(
            decoding: try OperationContractCodec.encode(command.envelope),
            as: UTF8.self
        )
        let allocations = String(
            decoding: try OperationContractCodec.encode(command.draft.categoryAllocations),
            as: UTF8.self
        )
        return ProjectCreationUploadRequest(
            operationId: command.envelope.operationId.rawValue,
            accountId: command.envelope.accountId.rawValue,
            actorPrincipalId: command.envelope.actorPrincipalId.rawValue,
            contractVersion: command.envelope.contractVersion.rawValue,
            projectCreatedAtMilliseconds: Int64(capturedAt.timeIntervalSince1970 * 1_000),
            projectId: command.draft.projectId.rawValue,
            clientSelectionKind: "new",
            clientId: command.draft.clientSelection.clientId.rawValue,
            newClientDisplayName: command.draft.clientSelection.newClientDisplayName?.rawValue,
            projectDisplayName: command.draft.displayName.rawValue,
            description: command.draft.description,
            categoryAllocationsJSON: allocations,
            fingerprint: command.fingerprint.sha256,
            envelopeJSON: envelope
        )
    }

    private static func count(
        _ table: String,
        database: any PowerSyncDatabaseProtocol
    ) async throws -> Int64 {
        try await database.get("SELECT count(*) FROM \(table)") { cursor in
            try cursor.getInt64(index: 0)
        }
    }

    private static func text(
        _ expression: String,
        from table: String,
        id: String,
        database: any PowerSyncDatabaseProtocol
    ) async throws -> String {
        try await database.get(
            sql: "SELECT \(expression) FROM \(table) WHERE id = ?",
            parameters: [id]
        ) { cursor in
            try cursor.getString(index: 0)
        }
    }

    private static func localState(
        _ command: CreateProjectCommand,
        database: any PowerSyncDatabaseProtocol
    ) async throws -> String {
        try await database.get(
            sql: "SELECT local_state FROM spike_local_operations WHERE id = ?",
            parameters: [command.envelope.operationId.rawValue]
        ) { cursor in
            try cursor.getString(name: "local_state")
        }
    }
}

private final class ProjectDatabaseFixture: @unchecked Sendable {
    let directoryURL: URL
    let databaseURL: URL
    private let key: LedgerPowerSyncEncryptionKey

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-project-powersync-\(UUID().uuidString)")
        databaseURL = directoryURL.appendingPathComponent("ledger.sqlite")
        key = try LedgerPowerSyncEncryptionKey(
            hexadecimal: String(repeating: "2b", count: 32)
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

private actor RecordingProjectCreationApplier: ProjectCreationCommandApplying {
    private(set) var requests: [ProjectCreationUploadRequest] = []

    func apply(_ request: ProjectCreationUploadRequest) async throws -> ProjectCreationServerResult {
        requests.append(request)
        return ProjectCreationServerResult(
            operationId: request.operationId,
            accountId: request.accountId,
            commandFingerprint: request.fingerprint,
            subjectId: request.projectId,
            phase: "applied",
            resultCode: "project_created",
            errorCode: nil
        )
    }
}

private struct RejectingProjectCreationApplier: ProjectCreationCommandApplying {
    func apply(_ request: ProjectCreationUploadRequest) async throws -> ProjectCreationServerResult {
        ProjectCreationServerResult(
            operationId: request.operationId,
            accountId: request.accountId,
            commandFingerprint: request.fingerprint,
            subjectId: request.projectId,
            phase: "rejected",
            resultCode: nil,
            errorCode: "project_setup_client_not_selectable"
        )
    }
}

private actor RecordingClientApplier: ClientCreationCommandApplying {
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

private struct UnusedClientCreationApplier: ClientCreationCommandApplying {
    func apply(_ request: ClientCreationUploadRequest) async throws -> ClientCreationServerResult {
        throw LedgerPowerSyncUploadFailure.unsupportedCommandTable("unexpected-client")
    }
}

private final class ProjectRecordingURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
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

private func projectRequestBody(_ request: URLRequest) throws -> Data {
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
