import Foundation
import LedgerTargetCore
import PowerSync

enum LocalOperationCommandFamily: String, CaseIterable, Sendable {
    case createClient = "create_client"
    case createProject = "create_project"
    case archiveProject = "archive_project"
    case archiveClient = "archive_client"
    case assignItemsToSpace = "assign_items_to_space"
    case clearItemSpaceAssignments = "clear_item_space_assignments"

    var insertOnlyCommandTable: String? {
        switch self {
        case .createClient: LedgerPowerSyncTable.clientCommands
        case .createProject: LedgerPowerSyncTable.projectCommands
        case .archiveProject: LedgerPowerSyncTable.projectArchiveCommands
        case .archiveClient: LedgerPowerSyncTable.clientArchiveCommands
        case .assignItemsToSpace, .clearItemSpaceAssignments: nil
        }
    }
}

enum LocalOperationIdentityGuardFailure: Error, Equatable, Sendable {
    case malformedEvidence
    case payloadMismatch
}

enum LocalOperationIdentityDisposition: Equatable, Sendable {
    case unclaimed
    case matchingOwner
}

enum LocalOperationIdentityGuardCheckpoint: Equatable, Sendable {
    case inventoryConstruction
    case inventoryRead
}

enum LocalOperationIdentityGuard {
    static let commandFamilies = LocalOperationCommandFamily.allCases
    static let operationBearingRelations = [
        LedgerPowerSyncTable.localOperations,
        LedgerPowerSyncTable.operationResults,
        LedgerPowerSyncTable.pendingClients,
        LedgerPowerSyncTable.pendingProjects,
        LedgerPowerSyncTable.pendingProjectCategoryAllocations,
        LedgerPowerSyncTable.projectArchiveOverlays,
        LedgerPowerSyncTable.clientArchiveOverlays,
        LedgerPowerSyncTable.itemSpaceAssignmentCommands,
        LedgerPowerSyncTable.itemSpaceClearingCommands
    ]
    static let insertOnlyCommandTables = [
        LedgerPowerSyncTable.clientCommands,
        LedgerPowerSyncTable.projectCommands,
        LedgerPowerSyncTable.projectArchiveCommands,
        LedgerPowerSyncTable.clientArchiveCommands
    ]
    static let forbiddenMutationTables = [LedgerPowerSyncTable.operationResults]
    static let acceptingProviders = [
        "ClientCreationPowerSyncStore",
        "ProjectSetupPowerSyncStore",
        "ProjectArchivePowerSyncStore",
        "ClientArchivePowerSyncStore",
        "ItemSpaceAssignmentPowerSyncStore",
        "ItemSpaceClearingPowerSyncStore"
    ]

    static func inspect(
        transaction: any Transaction,
        operationId: OperationID,
        expectedFamily: LocalOperationCommandFamily,
        expectedFingerprint: String,
        checkpoint: (LocalOperationIdentityGuardCheckpoint) throws -> Void = { _ in }
    ) throws -> LocalOperationIdentityDisposition {
        try checkpoint(.inventoryConstruction)
        let id = operationId.rawValue
        let operations = try transaction.getAll(sql: operationSQL, parameters: [id]) {
            try OperationRow(cursor: $0)
        }
        let results = try transaction.getAll(sql: resultSQL, parameters: [id]) {
            try ResultRow(cursor: $0)
        }
        let crudRows = try transaction.getAll(sql: crudSQL, parameters: [id]) {
            try CrudRow(cursor: $0)
        }
        let malformedCrudPayloads = try transaction.getAll(
            sql: malformedCrudSQL,
            parameters: nil
        ) { try $0.getString(name: "data") }
        let pendingClients = try transaction.getAll(sql: pendingClientSQL, parameters: [id]) {
            try PendingClientRow(cursor: $0)
        }
        let pendingProjects = try transaction.getAll(sql: pendingProjectSQL, parameters: [id]) {
            try PendingProjectRow(cursor: $0)
        }
        let pendingAllocations = try transaction.getAll(
            sql: pendingAllocationSQL, parameters: [id]
        ) { try PendingAllocationRow(cursor: $0) }
        let projectOverlays = try transaction.getAll(sql: projectOverlaySQL, parameters: [id]) {
            try ArchiveOverlayRow(cursor: $0, subjectColumn: "project_id")
        }
        let clientOverlays = try transaction.getAll(sql: clientOverlaySQL, parameters: [id]) {
            try ArchiveOverlayRow(cursor: $0, subjectColumn: "client_id")
        }
        let assignments = try transaction.getAll(sql: assignmentSQL, parameters: [id]) {
            try AssignmentRow(cursor: $0)
        }
        let clearings = try transaction.getAll(sql: clearingSQL, parameters: [id]) {
            try ClearingRow(cursor: $0)
        }
        try checkpoint(.inventoryRead)

        let malformedCrudClaimsID = malformedCrudPayloads.contains(where: {
            malformedCRUDPayload($0, claims: id)
        })
        let hasEvidence = !operations.isEmpty || !results.isEmpty || !crudRows.isEmpty
            || !pendingClients.isEmpty || !pendingProjects.isEmpty
            || !pendingAllocations.isEmpty || !projectOverlays.isEmpty
            || !clientOverlays.isEmpty || !assignments.isEmpty
            || !clearings.isEmpty || malformedCrudClaimsID
        guard hasEvidence else { return .unclaimed }
        guard !malformedCrudClaimsID else {
            throw LocalOperationIdentityGuardFailure.malformedEvidence
        }
        guard operations.count == 1, let operation = operations.first,
              operation.isStructurallyValid else {
            throw LocalOperationIdentityGuardFailure.malformedEvidence
        }
        if crudRows.contains(where: { $0.table == LedgerPowerSyncTable.operationResults }) {
            throw LocalOperationIdentityGuardFailure.malformedEvidence
        }
        guard crudRows.allSatisfy({ insertOnlyCommandTables.contains($0.table) }) else {
            throw LocalOperationIdentityGuardFailure.malformedEvidence
        }
        let commandCrud = crudRows.filter { insertOnlyCommandTables.contains($0.table) }
        guard commandCrud.count <= 1, results.count <= 1,
              pendingClients.count <= 1, pendingProjects.count <= 1,
              projectOverlays.count <= 1, clientOverlays.count <= 1,
              assignments.count <= 1, clearings.count <= 1 else {
            throw LocalOperationIdentityGuardFailure.malformedEvidence
        }

        var families = Set<LocalOperationCommandFamily>()
        if let raw = operation.commandType {
            guard let family = LocalOperationCommandFamily(rawValue: raw) else {
                throw LocalOperationIdentityGuardFailure.malformedEvidence
            }
            families.insert(family)
        }
        for row in commandCrud {
            guard row.operation == "PUT", let family = family(commandTable: row.table),
                  row.matches(operation: operation) else {
                throw LocalOperationIdentityGuardFailure.malformedEvidence
            }
            families.insert(family)
        }
        for result in results {
            guard let family = LocalOperationCommandFamily(rawValue: result.commandType),
                  result.matches(operation: operation) else {
                throw LocalOperationIdentityGuardFailure.malformedEvidence
            }
            families.insert(family)
        }
        for row in pendingClients {
            guard row.operationId == id, row.accountId == operation.accountId,
                  row.principalId == operation.principalId else {
                throw LocalOperationIdentityGuardFailure.malformedEvidence
            }
        }
        for row in pendingProjects {
            guard row.operationId == id, row.accountId == operation.accountId,
                  row.principalId == operation.principalId,
                  row.projectId == operation.subjectId else {
                throw LocalOperationIdentityGuardFailure.malformedEvidence
            }
            families.insert(.createProject)
        }
        for row in pendingAllocations {
            guard row.operationId == id, row.accountId == operation.accountId,
                  row.principalId == operation.principalId,
                  row.projectId == operation.subjectId else {
                throw LocalOperationIdentityGuardFailure.malformedEvidence
            }
            families.insert(.createProject)
        }
        for row in projectOverlays {
            guard row.matches(operation: operation) else {
                throw LocalOperationIdentityGuardFailure.malformedEvidence
            }
            families.insert(.archiveProject)
        }
        for row in clientOverlays {
            guard row.matches(operation: operation) else {
                throw LocalOperationIdentityGuardFailure.malformedEvidence
            }
            families.insert(.archiveClient)
        }
        for row in assignments {
            guard row.matches(operation: operation) else {
                throw LocalOperationIdentityGuardFailure.malformedEvidence
            }
            families.insert(.assignItemsToSpace)
        }
        for row in clearings {
            guard row.matches(operation: operation) else {
                throw LocalOperationIdentityGuardFailure.malformedEvidence
            }
            families.insert(.clearItemSpaceAssignments)
        }

        guard families.count == 1, let ownerFamily = families.first,
              isComplete(
                family: ownerFamily, operation: operation, commandCrud: commandCrud,
                results: results, pendingClients: pendingClients,
                pendingProjects: pendingProjects, pendingAllocations: pendingAllocations,
                projectOverlays: projectOverlays,
                clientOverlays: clientOverlays, assignments: assignments,
                clearings: clearings
              ) else {
            throw LocalOperationIdentityGuardFailure.malformedEvidence
        }
        guard ownerFamily == expectedFamily,
              operation.fingerprint == expectedFingerprint else {
            throw LocalOperationIdentityGuardFailure.payloadMismatch
        }
        return .matchingOwner
    }

    private static func isComplete(
        family: LocalOperationCommandFamily,
        operation: OperationRow,
        commandCrud: [CrudRow],
        results: [ResultRow],
        pendingClients: [PendingClientRow],
        pendingProjects: [PendingProjectRow],
        pendingAllocations: [PendingAllocationRow],
        projectOverlays: [ArchiveOverlayRow],
        clientOverlays: [ArchiveOverlayRow],
        assignments: [AssignmentRow],
        clearings: [ClearingRow]
    ) -> Bool {
        let commandCount = commandCrud.filter { $0.table == family.insertOnlyCommandTable }.count
        switch operation.state {
        case "queued", "applying":
            guard operation.updatedAt >= operation.acceptedAt,
                  operation.hasNoTerminalEvidence, results.isEmpty else { return false }
            switch family {
            case .createClient:
                return commandCount == 1 && pendingClients.count == 1
                    && pendingClients[0].clientId == operation.subjectId
                    && pendingProjects.isEmpty && pendingAllocations.isEmpty
                    && projectOverlays.isEmpty
                    && clientOverlays.isEmpty && assignments.isEmpty
                    && clearings.isEmpty
            case .createProject:
                return commandCount == 1 && pendingProjects.count == 1
                    && projectOverlays.isEmpty && clientOverlays.isEmpty
                    && assignments.isEmpty && clearings.isEmpty
            case .archiveProject:
                return commandCount == 1 && projectOverlays.count == 1
                    && pendingClients.isEmpty && pendingProjects.isEmpty
                    && pendingAllocations.isEmpty && clientOverlays.isEmpty
                    && assignments.isEmpty && clearings.isEmpty
            case .archiveClient:
                return commandCount == 1 && clientOverlays.count == 1
                    && pendingClients.isEmpty && pendingProjects.isEmpty
                    && pendingAllocations.isEmpty && projectOverlays.isEmpty
                    && assignments.isEmpty && clearings.isEmpty
            case .assignItemsToSpace:
                return commandCrud.isEmpty && assignments.count == 1
                    && pendingClients.isEmpty && pendingProjects.isEmpty
                    && pendingAllocations.isEmpty && projectOverlays.isEmpty
                    && clientOverlays.isEmpty && clearings.isEmpty
            case .clearItemSpaceAssignments:
                return commandCrud.isEmpty && clearings.count == 1
                    && pendingClients.isEmpty && pendingProjects.isEmpty
                    && pendingAllocations.isEmpty && projectOverlays.isEmpty
                    && clientOverlays.isEmpty && assignments.isEmpty
            }
        case "applied", "rejected", "superseded", "resolved":
            switch family {
            case .createClient, .createProject:
                guard operation.state == "applied" || operation.state == "rejected",
                      operation.commandType == family.rawValue,
                      operation.hasNoTerminalEvidence else { return false }
                return commandCount <= 1 && projectOverlays.isEmpty
                    && clientOverlays.isEmpty && assignments.isEmpty
                    && clearings.isEmpty
            case .archiveProject:
                return operation.hasCompleteTerminalEvidence && commandCount <= 1
                    && pendingClients.isEmpty && pendingProjects.isEmpty
                    && pendingAllocations.isEmpty && clientOverlays.isEmpty
                    && assignments.isEmpty && clearings.isEmpty
            case .archiveClient:
                return operation.hasCompleteTerminalEvidence && commandCount <= 1
                    && pendingClients.isEmpty && pendingProjects.isEmpty
                    && pendingAllocations.isEmpty && projectOverlays.isEmpty
                    && assignments.isEmpty && clearings.isEmpty
            case .assignItemsToSpace, .clearItemSpaceAssignments:
                return false
            }
        default:
            return false
        }
    }

    private static func family(commandTable: String) -> LocalOperationCommandFamily? {
        commandFamilies.first { $0.insertOnlyCommandTable == commandTable }
    }

    private static func isJSONObject(_ value: String?) -> Bool {
        guard let value, let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              object is [String: Any] else { return false }
        return true
    }

    /// PowerSync keeps the application OperationID inside `ps_crud.data`. If a
    /// queued payload is damaged badly enough that SQLite JSON functions cannot
    /// parse it, conservatively recognize the generated top-level ID token so
    /// the damaged queue entry still reserves that ID. Ledger identifiers cannot
    /// contain quotes or escapes, and stripping JSON whitespace is therefore
    /// sufficient for this deliberately narrow fail-closed check.
    private static func malformedCRUDPayload(_ payload: String, claims id: String) -> Bool {
        let compact = payload
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\t", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
        return compact.contains("\"id\":\"\(id)\"")
    }

    private struct OperationRow {
        let accountId: String; let principalId: String; let contractVersion: String
        let fingerprint: String; let subjectId: String; let state: String
        let acceptedAt: Int64; let updatedAt: Int64; let commandType: String?
        let envelopeJSON: String?; let terminalPhase: String?
        let terminalResultCode: String?; let terminalErrorCode: String?
        let terminalEnvelopeSHA256: String?; let terminalRequestSHA256: String?
        let terminalServerReceivedAt: Int64?; let terminalCompletedAt: Int64?
        init(cursor: any SqlCursor) throws {
            accountId = try cursor.getString(name: "account_id")
            principalId = try cursor.getString(name: "actor_principal_id")
            contractVersion = try cursor.getString(name: "contract_version")
            fingerprint = try cursor.getString(name: "fingerprint")
            subjectId = try cursor.getString(name: "subject_id")
            state = try cursor.getString(name: "local_state")
            acceptedAt = try cursor.getInt64(name: "accepted_at_ms")
            updatedAt = try cursor.getInt64(name: "updated_at_ms")
            commandType = try cursor.getStringOptional(name: "command_type")
            envelopeJSON = try cursor.getStringOptional(name: "command_envelope_json")
            terminalPhase = try cursor.getStringOptional(name: "terminal_phase")
            terminalResultCode = try cursor.getStringOptional(name: "terminal_result_code")
            terminalErrorCode = try cursor.getStringOptional(name: "terminal_error_code")
            terminalEnvelopeSHA256 = try cursor.getStringOptional(name: "terminal_envelope_sha256")
            terminalRequestSHA256 = try cursor.getStringOptional(name: "terminal_request_sha256")
            terminalServerReceivedAt = try cursor.getInt64Optional(name: "terminal_server_received_at_ms")
            terminalCompletedAt = try cursor.getInt64Optional(name: "terminal_completed_at_ms")
        }
        var isStructurallyValid: Bool {
            let ownershipShape = commandType == nil
                ? envelopeJSON == nil
                : LocalOperationIdentityGuard.isJSONObject(envelopeJSON)
            return acceptedAt >= 0 && updatedAt >= 0 && !accountId.isEmpty
                && !principalId.isEmpty && !contractVersion.isEmpty
                && !fingerprint.isEmpty && !subjectId.isEmpty && ownershipShape
        }
        var hasNoTerminalEvidence: Bool {
            terminalPhase == nil && terminalResultCode == nil && terminalErrorCode == nil
                && terminalEnvelopeSHA256 == nil && terminalRequestSHA256 == nil
                && terminalServerReceivedAt == nil && terminalCompletedAt == nil
        }
        var hasCompleteTerminalEvidence: Bool {
            guard let terminalPhase,
                  terminalPhase == "applied" || terminalPhase == "rejected",
                  terminalEnvelopeSHA256 == fingerprint,
                  terminalRequestSHA256?.count == 64,
                  let server = terminalServerReceivedAt,
                  let completed = terminalCompletedAt,
                  server >= 0, completed >= server else { return false }
            if terminalPhase == "applied" {
                return terminalResultCode?.isEmpty == false && terminalErrorCode == nil
            }
            return terminalResultCode == nil && terminalErrorCode?.isEmpty == false
        }
        var clientCreatedAtMilliseconds: Int64? {
            struct TimestampEnvelope: Decodable { let clientCreatedAt: Double }
            guard let envelopeJSON, let bytes = envelopeJSON.data(using: .utf8),
                  let envelope = try? JSONDecoder().decode(
                    TimestampEnvelope.self, from: bytes
                  ),
                  envelope.clientCreatedAt.isFinite else { return nil }
            return Int64(exactly: envelope.clientCreatedAt.rounded(.towardZero))
        }
    }

    private struct ResultRow {
        let accountId: String; let principalId: String; let commandType: String
        let contractVersion: String; let fingerprint: String; let subjectId: String
        let envelopeSHA256: String; let requestSHA256: String?; let phase: String
        let resultCode: String?; let errorCode: String?
        let clientCreatedAt: Int64
        let serverReceivedAt: Int64; let completedAt: Int64
        init(cursor: any SqlCursor) throws {
            accountId = try cursor.getString(name: "account_id")
            principalId = try cursor.getString(name: "actor_principal_id")
            commandType = try cursor.getString(name: "command_type")
            contractVersion = try cursor.getString(name: "contract_version")
            fingerprint = try cursor.getString(name: "command_fingerprint")
            subjectId = try cursor.getString(name: "subject_id")
            envelopeSHA256 = try cursor.getString(name: "envelope_sha256")
            requestSHA256 = try cursor.getStringOptional(name: "request_sha256")
            phase = try cursor.getString(name: "phase")
            resultCode = try cursor.getStringOptional(name: "result_code")
            errorCode = try cursor.getStringOptional(name: "error_code")
            clientCreatedAt = try cursor.getInt64(name: "client_created_at_ms")
            serverReceivedAt = try cursor.getInt64(name: "server_received_at_ms")
            completedAt = try cursor.getInt64(name: "completed_at_ms")
        }
        func matches(operation: OperationRow) -> Bool {
            let expectedPhase = operation.hasNoTerminalEvidence
                ? operation.state
                : operation.terminalPhase
            guard accountId == operation.accountId && principalId == operation.principalId
                && contractVersion == operation.contractVersion
                && fingerprint == operation.fingerprint && subjectId == operation.subjectId,
                  phase == expectedPhase, phase == "applied" || phase == "rejected",
                  envelopeSHA256 == operation.fingerprint,
                  serverReceivedAt >= 0, completedAt >= serverReceivedAt else {
                return false
            }
            if phase == "applied" {
                guard resultCode?.isEmpty == false, errorCode == nil else { return false }
            } else {
                guard resultCode == nil, errorCode?.isEmpty == false else { return false }
            }
            if operation.hasNoTerminalEvidence {
                guard requestSHA256 == nil,
                      clientCreatedAt == operation.clientCreatedAtMilliseconds else {
                    return false
                }
                switch commandType {
                case LocalOperationCommandFamily.createClient.rawValue:
                    return phase == "applied"
                        ? resultCode == "client_created"
                        : Self.clientCreationRejectionCodes.contains(errorCode ?? "")
                case LocalOperationCommandFamily.createProject.rawValue:
                    return phase == "applied"
                        ? resultCode == "project_created"
                        : Self.projectCreationRejectionCodes.contains(errorCode ?? "")
                default:
                    return false
                }
            }
            return phase == operation.terminalPhase
                && resultCode == operation.terminalResultCode
                && errorCode == operation.terminalErrorCode
                && envelopeSHA256 == operation.terminalEnvelopeSHA256
                && requestSHA256 == operation.terminalRequestSHA256
                && serverReceivedAt == operation.terminalServerReceivedAt
                && completedAt == operation.terminalCompletedAt
        }

        private static let clientCreationRejectionCodes: Set<String> = [
            "client_creation_command_encoding_invalid", "contract_unsupported",
            "client_creation_payload_invalid", "client_creation_fingerprint_mismatch",
            "client_creation_envelope_mismatch", "client_creation_identity_conflict"
        ]
        private static let projectCreationRejectionCodes: Set<String> = [
            "project_setup_command_encoding_invalid", "contract_unsupported",
            "project_setup_payload_invalid", "project_setup_fingerprint_mismatch",
            "project_setup_envelope_mismatch", "project_setup_category_allocation_invalid",
            "project_setup_category_not_selectable", "project_setup_identity_conflict",
            "project_setup_client_not_selectable",
            "project_setup_new_client_identity_conflict"
        ]
    }

    private struct CrudRow {
        let operation: String?; let table: String; let accountId: String?
        let principalId: String?; let contractVersion: String?
        let fingerprint: String?; let envelopeJSON: String?; let subjectId: String?
        init(cursor: any SqlCursor) throws {
            operation = try cursor.getStringOptional(name: "crud_operation")
            table = try cursor.getString(name: "table_name")
            accountId = try cursor.getStringOptional(name: "account_id")
            principalId = try cursor.getStringOptional(name: "actor_principal_id")
            contractVersion = try cursor.getStringOptional(name: "contract_version")
            fingerprint = try cursor.getStringOptional(name: "fingerprint")
            envelopeJSON = try cursor.getStringOptional(name: "envelope_json")
            subjectId = try cursor.getStringOptional(name: "subject_id")
        }
        func matches(operation: OperationRow) -> Bool {
            let envelopeMatches = operation.commandType == nil
                && operation.envelopeJSON == nil
                || envelopeJSON == operation.envelopeJSON
                    && LocalOperationIdentityGuard.isJSONObject(envelopeJSON)
            return accountId == operation.accountId && principalId == operation.principalId
                && contractVersion == operation.contractVersion
                && fingerprint == operation.fingerprint
                && envelopeMatches && subjectId == operation.subjectId
        }
    }

    private struct PendingClientRow {
        let clientId: String; let accountId: String; let principalId: String
        let operationId: String
        init(cursor: any SqlCursor) throws {
            clientId = try cursor.getString(name: "id")
            accountId = try cursor.getString(name: "account_id")
            principalId = try cursor.getString(name: "created_by_principal_id")
            operationId = try cursor.getString(name: "operation_id")
        }
    }
    private struct PendingProjectRow {
        let projectId: String; let accountId: String; let principalId: String
        let operationId: String
        init(cursor: any SqlCursor) throws {
            projectId = try cursor.getString(name: "id")
            accountId = try cursor.getString(name: "account_id")
            principalId = try cursor.getString(name: "created_by_principal_id")
            operationId = try cursor.getString(name: "operation_id")
        }
    }
    private struct PendingAllocationRow {
        let accountId: String; let principalId: String; let projectId: String
        let operationId: String
        init(cursor: any SqlCursor) throws {
            accountId = try cursor.getString(name: "account_id")
            principalId = try cursor.getString(name: "created_by_principal_id")
            projectId = try cursor.getString(name: "project_id")
            operationId = try cursor.getString(name: "operation_id")
        }
    }
    private struct ArchiveOverlayRow {
        let accountId: String; let principalId: String; let subjectId: String
        let operationId: String; let fingerprint: String
        init(cursor: any SqlCursor, subjectColumn: String) throws {
            accountId = try cursor.getString(name: "account_id")
            principalId = try cursor.getString(name: "actor_principal_id")
            subjectId = try cursor.getString(name: subjectColumn)
            operationId = try cursor.getString(name: "operation_id")
            fingerprint = try cursor.getString(name: "fingerprint")
        }
        func matches(operation: OperationRow) -> Bool {
            !operationId.isEmpty && accountId == operation.accountId
                && principalId == operation.principalId && subjectId == operation.subjectId
                && fingerprint == operation.fingerprint
        }
    }
    private struct AssignmentRow {
        let accountId: String; let principalId: String; let contractVersion: String
        let destinationSpaceId: String; let fingerprint: String
        init(cursor: any SqlCursor) throws {
            accountId = try cursor.getString(name: "account_id")
            principalId = try cursor.getString(name: "actor_principal_id")
            contractVersion = try cursor.getString(name: "contract_version")
            destinationSpaceId = try cursor.getString(name: "destination_space_id")
            fingerprint = try cursor.getString(name: "fingerprint")
        }
        func matches(operation: OperationRow) -> Bool {
            accountId == operation.accountId && principalId == operation.principalId
                && contractVersion == operation.contractVersion
                && destinationSpaceId == operation.subjectId
                && fingerprint == operation.fingerprint
        }
    }
    private struct ClearingRow {
        let accountId: String; let principalId: String; let contractVersion: String
        let scopeKind: String; let projectId: String?; let fingerprint: String
        init(cursor: any SqlCursor) throws {
            accountId = try cursor.getString(name: "account_id")
            principalId = try cursor.getString(name: "actor_principal_id")
            contractVersion = try cursor.getString(name: "contract_version")
            scopeKind = try cursor.getString(name: "scope_kind")
            projectId = try cursor.getStringOptional(name: "project_id")
            fingerprint = try cursor.getString(name: "fingerprint")
        }
        func matches(operation: OperationRow) -> Bool {
            guard accountId == operation.accountId,
                  principalId == operation.principalId,
                  contractVersion == operation.contractVersion,
                  fingerprint == operation.fingerprint else { return false }
            switch scopeKind {
            case "project": return projectId == operation.subjectId
            case "business_inventory":
                return projectId == nil && operation.subjectId == operation.accountId
            default: return false
            }
        }
    }

    private static let operationSQL = """
        SELECT COALESCE(id, '') AS id, COALESCE(account_id, '') AS account_id,
               COALESCE(actor_principal_id, '') AS actor_principal_id,
               COALESCE(contract_version, '') AS contract_version,
               COALESCE(fingerprint, '') AS fingerprint,
               COALESCE(subject_id, '') AS subject_id,
               COALESCE(local_state, '') AS local_state,
               COALESCE(accepted_at_ms, -1) AS accepted_at_ms,
               COALESCE(updated_at_ms, -1) AS updated_at_ms, command_type,
               command_envelope_json, terminal_phase, terminal_result_code,
               terminal_error_code, terminal_envelope_sha256, terminal_request_sha256,
               terminal_server_received_at_ms, terminal_completed_at_ms
        FROM \(LedgerPowerSyncTable.localOperations) WHERE id = ?
        """
    private static let resultSQL = """
        SELECT COALESCE(account_id, '') AS account_id,
               COALESCE(actor_principal_id, '') AS actor_principal_id,
               COALESCE(command_type, '') AS command_type,
               COALESCE(contract_version, '') AS contract_version,
               COALESCE(command_fingerprint, '') AS command_fingerprint,
               COALESCE(subject_id, '') AS subject_id,
               COALESCE(envelope_sha256, '') AS envelope_sha256,
               request_sha256,
               COALESCE(phase, '') AS phase, result_code, error_code,
               COALESCE(client_created_at_ms, -1) AS client_created_at_ms,
               COALESCE(server_received_at_ms, -1) AS server_received_at_ms,
               COALESCE(completed_at_ms, -1) AS completed_at_ms
        FROM \(LedgerPowerSyncTable.operationResults) WHERE id = ?
        """
    private static let crudSQL = """
        SELECT json_extract(data, '$.op') AS crud_operation,
               COALESCE(json_extract(data, '$.type'), '') AS table_name,
               json_extract(data, '$.data.account_id') AS account_id,
               json_extract(data, '$.data.actor_principal_id') AS actor_principal_id,
               json_extract(data, '$.data.contract_version') AS contract_version,
               json_extract(data, '$.data.fingerprint') AS fingerprint,
               json_extract(data, '$.data.envelope_json') AS envelope_json,
               CASE json_extract(data, '$.type')
                 WHEN '\(LedgerPowerSyncTable.clientCommands)'
                   THEN json_extract(data, '$.data.client_id')
                 WHEN '\(LedgerPowerSyncTable.clientArchiveCommands)'
                   THEN json_extract(data, '$.data.client_id')
                 ELSE json_extract(data, '$.data.project_id')
               END AS subject_id
        FROM ps_crud
        WHERE json_valid(data) = 1 AND json_extract(data, '$.id') = ?
          AND (
            json_extract(data, '$.type') IN (
              '\(LedgerPowerSyncTable.clientCommands)',
              '\(LedgerPowerSyncTable.projectCommands)',
              '\(LedgerPowerSyncTable.projectArchiveCommands)',
              '\(LedgerPowerSyncTable.clientArchiveCommands)',
              '\(LedgerPowerSyncTable.operationResults)'
            )
            OR (
              json_type(data, '$.data.actor_principal_id') = 'text'
              AND json_type(data, '$.data.contract_version') = 'text'
              AND json_type(data, '$.data.fingerprint') = 'text'
              AND json_type(data, '$.data.envelope_json') = 'text'
            )
            OR json_extract(data, '$.type') GLOB 'spike_*_commands'
          )
        """
    private static let malformedCrudSQL = """
        SELECT COALESCE(data, '') AS data
        FROM ps_crud
        WHERE json_valid(data) = 0
        """
    private static let pendingClientSQL = """
        SELECT COALESCE(id, '') AS id, COALESCE(account_id, '') AS account_id,
               COALESCE(created_by_principal_id, '') AS created_by_principal_id,
               COALESCE(operation_id, '') AS operation_id
        FROM \(LedgerPowerSyncTable.pendingClients) WHERE operation_id = ?
        """
    private static let pendingProjectSQL = """
        SELECT COALESCE(id, '') AS id, COALESCE(account_id, '') AS account_id,
               COALESCE(created_by_principal_id, '') AS created_by_principal_id,
               COALESCE(operation_id, '') AS operation_id
        FROM \(LedgerPowerSyncTable.pendingProjects) WHERE operation_id = ?
        """
    private static let pendingAllocationSQL = """
        SELECT COALESCE(account_id, '') AS account_id,
               COALESCE(created_by_principal_id, '') AS created_by_principal_id,
               COALESCE(project_id, '') AS project_id,
               COALESCE(operation_id, '') AS operation_id
        FROM \(LedgerPowerSyncTable.pendingProjectCategoryAllocations) WHERE operation_id = ?
        """
    private static let projectOverlaySQL = """
        SELECT COALESCE(account_id, '') AS account_id,
               COALESCE(actor_principal_id, '') AS actor_principal_id,
               COALESCE(project_id, '') AS project_id,
               COALESCE(operation_id, '') AS operation_id,
               COALESCE(fingerprint, '') AS fingerprint
        FROM \(LedgerPowerSyncTable.projectArchiveOverlays) WHERE operation_id = ?
        """
    private static let clientOverlaySQL = """
        SELECT COALESCE(account_id, '') AS account_id,
               COALESCE(actor_principal_id, '') AS actor_principal_id,
               COALESCE(client_id, '') AS client_id,
               COALESCE(operation_id, '') AS operation_id,
               COALESCE(fingerprint, '') AS fingerprint
        FROM \(LedgerPowerSyncTable.clientArchiveOverlays) WHERE operation_id = ?
        """
    private static let assignmentSQL = """
        SELECT COALESCE(account_id, '') AS account_id,
               COALESCE(actor_principal_id, '') AS actor_principal_id,
               COALESCE(contract_version, '') AS contract_version,
               COALESCE(destination_space_id, '') AS destination_space_id,
               COALESCE(fingerprint, '') AS fingerprint
        FROM \(LedgerPowerSyncTable.itemSpaceAssignmentCommands) WHERE id = ?
        """
    private static let clearingSQL = """
        SELECT COALESCE(account_id, '') AS account_id,
               COALESCE(actor_principal_id, '') AS actor_principal_id,
               COALESCE(contract_version, '') AS contract_version,
               COALESCE(scope_kind, '') AS scope_kind, project_id,
               COALESCE(fingerprint, '') AS fingerprint
        FROM \(LedgerPowerSyncTable.itemSpaceClearingCommands) WHERE id = ?
        """
}
