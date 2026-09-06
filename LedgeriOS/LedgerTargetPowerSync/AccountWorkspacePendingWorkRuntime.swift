import Foundation
import LedgerTargetCore
import PowerSync

public enum LedgerPowerSyncLocalBootstrapStage: String, Equatable, Sendable {
    case applicationSupportResolution
    case workspaceLocationResolution
    case databaseKeyLoad
    case mediaKeyLoad
    case keyValidation
    case directoryPreparation
    case structuredDatabaseOpen
    case structuredDatabaseValidation
    case attachmentDatabaseOpen
    case attachmentDatabaseValidation
    case mediaVaultOpen
    case attachmentStoreConstruction
    case pendingWorkQueryConstruction
    case budgetCategoryQueryConstruction
    case spaceAssignmentDestinationQueryConstruction
    case projectNoteQueryConstruction
    case runtimeConstruction
}

public enum LedgerPowerSyncLocalCleanupOutcome: String, Equatable, Sendable {
    case notOpened
    case succeeded
    case failed
}

public struct LedgerPowerSyncLocalBootstrapFailure: Error, Equatable, Sendable {
    public let stage: LedgerPowerSyncLocalBootstrapStage
    public let attachmentDatabaseCleanup: LedgerPowerSyncLocalCleanupOutcome
    public let structuredDatabaseCleanup: LedgerPowerSyncLocalCleanupOutcome

    public var diagnosticCode: String {
        "workspace_bootstrap_\(stage.rawValue)"
    }

    init(
        stage: LedgerPowerSyncLocalBootstrapStage,
        attachmentDatabaseCleanup: LedgerPowerSyncLocalCleanupOutcome = .notOpened,
        structuredDatabaseCleanup: LedgerPowerSyncLocalCleanupOutcome = .notOpened
    ) {
        self.stage = stage
        self.attachmentDatabaseCleanup = attachmentDatabaseCleanup
        self.structuredDatabaseCleanup = structuredDatabaseCleanup
    }
}

protocol AccountWorkspaceAttachmentStoring:
    AttachmentCaptureStoring,
    AttachmentPendingWorkObserving
{}

extension AttachmentCapturePowerSyncStore: AccountWorkspaceAttachmentStoring {}

protocol AccountWorkspacePendingWorkSummarizing: Sendable {
    func summary() async throws -> PendingLocalWorkSummary
}

extension PendingWorkPowerSyncQuery: AccountWorkspacePendingWorkSummarizing {}

protocol AccountWorkspaceBudgetCategoryQuerying: BudgetCategoryReferenceQuerying {
    func cancelAndDrainWatches() async
}

extension BudgetCategoryReferencePowerSyncQuery: AccountWorkspaceBudgetCategoryQuerying {}

protocol AccountWorkspaceSpaceAssignmentDestinationQuerying:
    SpaceAssignmentDestinationQuerying
{
    func cancelAndDrainWatches() async
}

extension SpaceAssignmentDestinationPowerSyncQuery:
    AccountWorkspaceSpaceAssignmentDestinationQuerying
{}

protocol AccountWorkspaceProjectNoteQuerying: ProjectNoteQuerying {
    func cancelAndDrainWatches() async
}

extension ProjectNotePowerSyncQuery: AccountWorkspaceProjectNoteQuerying {}

protocol AccountWorkspaceSpaceCoreDetailsQuerying: SpaceCoreDetailsQuerying {
    func cancelAndDrainWatches() async
}

extension SpaceCoreDetailsPowerSyncQuery: AccountWorkspaceSpaceCoreDetailsQuerying {}

protocol AccountWorkspaceProjectArchiveStoring: ProjectArchiving, Sendable {
    func watchOperation(
        _ operationId: OperationID
    ) -> AsyncThrowingStream<OperationSnapshot, Error>
    func cancelAndDrainWatches() async
}

extension ProjectArchivePowerSyncStore: AccountWorkspaceProjectArchiveStoring {}

enum AccountWorkspaceRuntimeFiniteOperation: Equatable, Sendable {
    case createClient
    case createProject
    case archiveProject
    case archiveClient
    case pendingUploadCount
    case encryptionCipher
    case captureAttachment
    case pendingWorkSummary
}

enum AccountWorkspaceRuntimeStreamOperation: Equatable, Sendable {
    case clientDetails
    case projectDetails
    case clientDirectory
    case projectDirectory
    case projectNotes
    case spaceCoreDetails
    case budgetCategories
    case spaceAssignmentDestinations
    case transferDestinations
    case projectArchiveOperation
    case clientArchiveOperation
}

struct AccountWorkspaceOpenedDatabase: @unchecked Sendable {
    let database: any PowerSyncDatabaseProtocol
    let closePreservingData: @Sendable () async throws -> Void
}

struct LedgerPowerSyncLocalBootstrapDependencies: @unchecked Sendable {
    var loadDatabaseKey: @Sendable (String, String) throws -> LedgerPowerSyncEncryptionKey
    var loadMediaKeyBytes: @Sendable (String, String) throws -> Data
    var createDirectory: @Sendable (URL) throws -> Void
    var openStructuredDatabase:
        @Sendable (
            String,
            LedgerPowerSyncEncryptionKey
        ) throws -> AccountWorkspaceOpenedDatabase
    var openAttachmentDatabase:
        @Sendable (
            String,
            LedgerPowerSyncEncryptionKey
        ) throws -> AccountWorkspaceOpenedDatabase
    var validateStructuredDatabase:
        @Sendable (
            any PowerSyncDatabaseProtocol
        ) async throws -> Void
    var validateAttachmentDatabase:
        @Sendable (
            any PowerSyncDatabaseProtocol
        ) async throws -> Void
    var makeVault:
        @Sendable (
            URL,
            AttachmentDurabilityNamespaceScope,
            AttachmentMediaEncryptionKey
        ) throws -> AttachmentLocalByteVault
    var makeAttachmentStore:
        @Sendable (
            any PowerSyncDatabaseProtocol,
            AttachmentLocalByteVault,
            AttachmentDurabilityNamespaceScope,
            @Sendable @escaping () -> Date
        ) throws -> any AccountWorkspaceAttachmentStoring
    var makePendingWorkQuery:
        @Sendable (
            any PowerSyncDatabaseProtocol,
            any AttachmentPendingWorkObserving,
            LedgerEnvironmentKind,
            PrincipalID,
            AccountID,
            @Sendable @escaping () -> Date
        ) throws -> any AccountWorkspacePendingWorkSummarizing
    var makeBudgetCategoryQuery:
        @Sendable (
            any PowerSyncDatabaseProtocol,
            PrincipalID,
            AccountID,
            @Sendable @escaping () -> Date
        ) throws -> any AccountWorkspaceBudgetCategoryQuerying
    var makeSpaceAssignmentDestinationQuery:
        @Sendable (
            any PowerSyncDatabaseProtocol,
            PrincipalID,
            AccountID,
            @Sendable @escaping () -> Date
        ) throws -> any AccountWorkspaceSpaceAssignmentDestinationQuerying
    var makeProjectNoteQuery:
        @Sendable (
            any PowerSyncDatabaseProtocol,
            PrincipalID,
            AccountID,
            @Sendable @escaping () -> Date
        ) throws -> any AccountWorkspaceProjectNoteQuerying
    var makeSpaceCoreDetailsQuery:
        @Sendable (
            any PowerSyncDatabaseProtocol,
            PrincipalID,
            AccountID,
            @Sendable @escaping () -> Date
        ) -> any AccountWorkspaceSpaceCoreDetailsQuerying
    var makeProjectArchiveStore:
        @Sendable (
            any PowerSyncDatabaseProtocol,
            AccountID,
            PrincipalID,
            @Sendable @escaping () -> Date
        ) -> any AccountWorkspaceProjectArchiveStoring
    var makeLifecycleOwner:
        @Sendable (
            AccountWorkspaceRuntimeResources
        ) throws -> AccountWorkspacePendingWorkRuntime
    var finiteOperationCheckpoint:
        @Sendable (
            AccountWorkspaceRuntimeFiniteOperation
        ) async throws -> Void
    var streamOperationCheckpoint:
        @Sendable (
            AccountWorkspaceRuntimeStreamOperation
        ) async throws -> Void
    var lifecycleEvent: @Sendable (AccountWorkspaceRuntimeLifecycleEvent) -> Void
    var now: @Sendable () -> Date

    static let live = LedgerPowerSyncLocalBootstrapDependencies(
        loadDatabaseKey: { service, account in
            let keychain = try LedgerPowerSyncKeychain(service: service)
            return try keychain.loadOrCreateKey(principalNamespace: account)
        },
        loadMediaKeyBytes: { service, account in
            let keychain = try LedgerPowerSyncKeychain(service: service)
            return try keychain.loadOrCreateKeyBytes(principalNamespace: account)
        },
        createDirectory: { directory in
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
        },
        openStructuredDatabase: { path, key in
            let database = try LedgerPowerSyncDatabaseFactory.open(
                absolutePath: path,
                encryptionKey: key
            )
            return AccountWorkspaceOpenedDatabase(
                database: database,
                closePreservingData: {
                    try await database.close(deleteDatabase: false)
                }
            )
        },
        openAttachmentDatabase: { path, key in
            let database = try AttachmentCapturePowerSyncDatabaseFactory.open(
                absolutePath: path,
                encryptionKey: key
            )
            return AccountWorkspaceOpenedDatabase(
                database: database,
                closePreservingData: {
                    try await database.close(deleteDatabase: false)
                }
            )
        },
        validateStructuredDatabase: { database in
            _ = try await database.get("SELECT count(*) FROM sqlite_master") { cursor in
                try cursor.getInt64(index: 0)
            }
        },
        validateAttachmentDatabase: { database in
            _ = try await database.get("SELECT count(*) FROM sqlite_master") { cursor in
                try cursor.getInt64(index: 0)
            }
        },
        makeVault: { root, scope, key in
            try AttachmentLocalByteVault(
                trustedRoot: root,
                scope: scope,
                mediaKey: key
            )
        },
        makeAttachmentStore: { database, vault, scope, now in
            AttachmentCapturePowerSyncStore(
                database: database,
                vault: vault,
                scope: scope,
                now: now
            )
        },
        makePendingWorkQuery: {
            database, attachmentObserver, environment, principalId, accountId, now in
            PendingWorkPowerSyncQuery(
                database: database,
                attachmentObserver: attachmentObserver,
                environment: environment,
                principalId: principalId,
                accountId: accountId,
                now: now
            )
        },
        makeBudgetCategoryQuery: { database, principalId, accountId, now in
            BudgetCategoryReferencePowerSyncQuery(
                database: database,
                principalId: principalId,
                accountId: accountId,
                now: now
            )
        },
        makeSpaceAssignmentDestinationQuery: { database, principalId, accountId, now in
            SpaceAssignmentDestinationPowerSyncQuery(
                database: database,
                principalId: principalId,
                accountId: accountId,
                now: now
            )
        },
        makeProjectNoteQuery: { database, principalId, accountId, now in
            ProjectNotePowerSyncQuery(
                database: database,
                principalId: principalId,
                accountId: accountId,
                now: now
            )
        },
        makeSpaceCoreDetailsQuery: { database, principalId, accountId, now in
            SpaceCoreDetailsPowerSyncQuery(
                database: database,
                principalId: principalId,
                accountId: accountId,
                now: now
            )
        },
        makeProjectArchiveStore: { database, accountId, principalId, now in
            ProjectArchivePowerSyncStore(
                database: database,
                accountId: accountId,
                principalId: principalId,
                now: now
            )
        },
        makeLifecycleOwner: { AccountWorkspacePendingWorkRuntime(resources: $0) },
        finiteOperationCheckpoint: { _ in },
        streamOperationCheckpoint: { _ in },
        lifecycleEvent: { _ in },
        now: Date.init
    )
}

enum AccountWorkspaceRuntimeLifecycleEvent: Equatable, Sendable {
    case structuredDatabaseOpened
    case attachmentDatabaseOpened
    case vaultConstructed
    case attachmentStoreConstructed
    case pendingWorkQueryConstructed
    case budgetCategoryQueryConstructed
    case spaceAssignmentDestinationQueryConstructed
    case projectNoteQueryConstructed
    case lifecycleOwnerConstructed
    case derivedResourcesReleased
    case vaultReleased
    case attachmentDatabaseCloseAttempted
    case structuredDatabaseCloseAttempted
}

final class AccountWorkspaceRuntimeResources: @unchecked Sendable {
    let structuredDatabase: any PowerSyncDatabaseProtocol
    let attachmentDatabase: any PowerSyncDatabaseProtocol
    let creationStore: ClientCreationPowerSyncStore
    let detailsQuery: ClientCoreDetailsPowerSyncQuery
    let projectSetupStore: ProjectSetupPowerSyncStore
    let projectArchiveStore: any AccountWorkspaceProjectArchiveStoring
    let clientArchiveStore: ClientArchivePowerSyncStore
    let projectDetailsQuery: ProjectCoreDetailsPowerSyncQuery
    let directoryQuery: ClientProjectDirectoryPowerSyncQuery
    let transferDestinationQuery:
        any AccountWorkspaceTransferDestinationSelectionQuerying
    let attachmentStore: any AccountWorkspaceAttachmentStoring
    let pendingWorkQuery: any AccountWorkspacePendingWorkSummarizing
    let budgetCategoryQuery: any AccountWorkspaceBudgetCategoryQuerying
    let spaceAssignmentDestinationQuery:
        any AccountWorkspaceSpaceAssignmentDestinationQuerying
    let projectNoteQuery: any AccountWorkspaceProjectNoteQuerying
    let spaceCoreDetailsQuery: any AccountWorkspaceSpaceCoreDetailsQuerying
    let vault: AttachmentLocalByteVault
    let closeAttachmentDatabase: @Sendable () async throws -> Void
    let closeStructuredDatabase: @Sendable () async throws -> Void
    let finiteOperationCheckpoint:
        @Sendable (
            AccountWorkspaceRuntimeFiniteOperation
        ) async throws -> Void
    let streamOperationCheckpoint:
        @Sendable (
            AccountWorkspaceRuntimeStreamOperation
        ) async throws -> Void
    let lifecycleEvent: @Sendable (AccountWorkspaceRuntimeLifecycleEvent) -> Void
    let environment: LedgerEnvironmentKind
    let principalId: PrincipalID
    let accountId: AccountID

    init(
        structuredDatabase: any PowerSyncDatabaseProtocol,
        attachmentDatabase: any PowerSyncDatabaseProtocol,
        attachmentStore: any AccountWorkspaceAttachmentStoring,
        pendingWorkQuery: any AccountWorkspacePendingWorkSummarizing,
        budgetCategoryQuery: any AccountWorkspaceBudgetCategoryQuerying,
        spaceAssignmentDestinationQuery:
            any AccountWorkspaceSpaceAssignmentDestinationQuerying,
        projectNoteQuery: any AccountWorkspaceProjectNoteQuerying,
        spaceCoreDetailsQuery: any AccountWorkspaceSpaceCoreDetailsQuerying,
        projectArchiveStore: any AccountWorkspaceProjectArchiveStoring,
        vault: AttachmentLocalByteVault,
        closeAttachmentDatabase: @Sendable @escaping () async throws -> Void,
        closeStructuredDatabase: @Sendable @escaping () async throws -> Void,
        finiteOperationCheckpoint:
            @Sendable @escaping (
                AccountWorkspaceRuntimeFiniteOperation
            ) async throws -> Void,
        streamOperationCheckpoint:
            @Sendable @escaping (
                AccountWorkspaceRuntimeStreamOperation
            ) async throws -> Void,
        lifecycleEvent: @Sendable @escaping (AccountWorkspaceRuntimeLifecycleEvent) -> Void,
        environment: LedgerEnvironmentKind,
        principalId: PrincipalID,
        accountId: AccountID,
        now: @Sendable @escaping () -> Date
    ) {
        self.structuredDatabase = structuredDatabase
        self.attachmentDatabase = attachmentDatabase
        creationStore = ClientCreationPowerSyncStore(database: structuredDatabase, now: now)
        detailsQuery = ClientCoreDetailsPowerSyncQuery(
            database: structuredDatabase,
            principalId: principalId,
            accountId: accountId,
            now: now
        )
        projectSetupStore = ProjectSetupPowerSyncStore(database: structuredDatabase, now: now)
        self.projectArchiveStore = projectArchiveStore
        clientArchiveStore = ClientArchivePowerSyncStore(
            database: structuredDatabase,
            accountId: accountId,
            principalId: principalId,
            now: now
        )
        projectDetailsQuery = ProjectCoreDetailsPowerSyncQuery(
            database: structuredDatabase,
            principalId: principalId,
            accountId: accountId,
            now: now
        )
        directoryQuery = ClientProjectDirectoryPowerSyncQuery(
            database: structuredDatabase,
            principalId: principalId,
            accountId: accountId,
            now: now
        )
        transferDestinationQuery = TransferDestinationSelectionPowerSyncQuery(
            directoryQuery: directoryQuery,
            accountId: accountId
        )
        self.attachmentStore = attachmentStore
        self.pendingWorkQuery = pendingWorkQuery
        self.budgetCategoryQuery = budgetCategoryQuery
        self.spaceAssignmentDestinationQuery = spaceAssignmentDestinationQuery
        self.projectNoteQuery = projectNoteQuery
        self.spaceCoreDetailsQuery = spaceCoreDetailsQuery
        self.vault = vault
        self.closeAttachmentDatabase = closeAttachmentDatabase
        self.closeStructuredDatabase = closeStructuredDatabase
        self.finiteOperationCheckpoint = finiteOperationCheckpoint
        self.streamOperationCheckpoint = streamOperationCheckpoint
        self.lifecycleEvent = lifecycleEvent
        self.environment = environment
        self.principalId = principalId
        self.accountId = accountId
    }
}

actor AccountWorkspacePendingWorkRuntime {
    private enum State {
        case open
        case closing(Task<Result<Void, LedgerOfflineClientRuntimeFailure>, Never>)
        case closed(Result<Void, LedgerOfflineClientRuntimeFailure>)
    }

    private var state: State = .open
    private var resources: AccountWorkspaceRuntimeResources?
    private var finiteLeaseCount = 0
    private var streamTasks: [UUID: Task<Void, Never>] = [:]
    private var cancelledBeforeStart: Set<UUID> = []
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []

    init(resources: AccountWorkspaceRuntimeResources) {
        self.resources = resources
    }

    func createClient(_ command: CreateClientCommand) async throws -> OperationReceipt {
        try await withFiniteLease(.createClient) { resources in
            guard command.envelope.accountId == resources.accountId else {
                throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch
            }
            guard command.envelope.actorPrincipalId == resources.principalId else {
                throw LedgerOfflineClientRuntimeFailure.principalScopeMismatch
            }
            return try await resources.creationStore.create(command)
        }
    }

    func createProject(_ command: CreateProjectCommand) async throws -> OperationReceipt {
        try await withFiniteLease(.createProject) { resources in
            guard command.envelope.accountId == resources.accountId else {
                throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch
            }
            guard command.envelope.actorPrincipalId == resources.principalId else {
                throw LedgerOfflineClientRuntimeFailure.principalScopeMismatch
            }
            return try await resources.projectSetupStore.create(command)
        }
    }

    func archiveProject(_ command: ArchiveProjectCommand) async throws -> OperationReceipt {
        try await withFiniteLease(.archiveProject) { resources in
            guard command.envelope.accountId == resources.accountId else {
                throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch
            }
            guard command.envelope.actorPrincipalId == resources.principalId else {
                throw LedgerOfflineClientRuntimeFailure.principalScopeMismatch
            }
            return try await resources.projectArchiveStore.archive(command)
        }
    }

    func archiveClient(_ command: ArchiveClientCommand) async throws -> OperationReceipt {
        try await withFiniteLease(.archiveClient) { resources in
            guard command.envelope.accountId == resources.accountId else {
                throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch
            }
            guard command.envelope.actorPrincipalId == resources.principalId else {
                throw LedgerOfflineClientRuntimeFailure.principalScopeMismatch
            }
            return try await resources.clientArchiveStore.archive(command)
        }
    }

    func pendingUploadCount() async throws -> Int64 {
        try await withFiniteLease(.pendingUploadCount) { resources in
            try await resources.structuredDatabase.get("SELECT count(*) FROM ps_crud") { cursor in
                try cursor.getInt64(index: 0)
            }
        }
    }

    func encryptionCipher() async throws -> String {
        try await withFiniteLease(.encryptionCipher) { resources in
            try await resources.structuredDatabase.get("PRAGMA cipher") { cursor in
                try cursor.getString(index: 0)
            }
        }
    }

    func captureAttachment(
        _ capture: LocalAttachmentCapture
    ) async throws -> AttachmentLocalDurabilityReceipt {
        try await withFiniteLease(.captureAttachment) { resources in
            try await resources.attachmentStore.enqueue(capture)
        }
    }

    func pendingWorkSummary() async throws -> PendingLocalWorkSummary {
        try await withFiniteLease(.pendingWorkSummary) { resources in
            try await resources.pendingWorkQuery.summary()
        }
    }

    func startClientWatch(
        id: UUID,
        request: ClientCoreDetailsRequest,
        continuation: AsyncThrowingStream<ClientCoreDetailsUpdate, Error>.Continuation
    ) {
        startStream(
            id: id,
            operation: .clientDetails,
            continuation: continuation,
            validate: { resources in
                guard request.accountId == resources.accountId else {
                    throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch
                }
            },
            makeStream: { $0.detailsQuery.watchClientCoreDetails(request) }
        )
    }

    func startProjectWatch(
        id: UUID,
        request: ProjectCoreDetailsRequest,
        continuation: AsyncThrowingStream<ProjectCoreDetailsUpdate, Error>.Continuation
    ) {
        startStream(
            id: id,
            operation: .projectDetails,
            continuation: continuation,
            validate: { resources in
                guard request.accountId == resources.accountId else {
                    throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch
                }
            },
            makeStream: { $0.projectDetailsQuery.watchProjectCoreDetails(request) }
        )
    }

    func startClientDirectoryWatch(
        id: UUID,
        continuation: AsyncThrowingStream<ClientListSnapshot, Error>.Continuation
    ) {
        startStream(
            id: id,
            operation: .clientDirectory,
            continuation: continuation,
            validate: { _ in },
            makeStream: { resources in
                resources.directoryQuery.watchClients(accountId: resources.accountId)
            }
        )
    }

    func startProjectDirectoryWatch(
        id: UUID,
        continuation: AsyncThrowingStream<ProjectListSnapshot, Error>.Continuation
    ) {
        startStream(
            id: id,
            operation: .projectDirectory,
            continuation: continuation,
            validate: { _ in },
            makeStream: { resources in
                resources.directoryQuery.watchProjects(accountId: resources.accountId)
            }
        )
    }

    func startProjectNoteWatch(
        id: UUID,
        request: ProjectNotePageRequest,
        continuation: AsyncThrowingStream<ProjectNotePage, Error>.Continuation
    ) {
        startStream(
            id: id,
            operation: .projectNotes,
            continuation: continuation,
            validate: { resources in
                guard request.accountId == resources.accountId else {
                    throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch
                }
            },
            makeStream: { resources in
                resources.projectNoteQuery.watchNotes(request)
            }
        )
    }

    func startSpaceCoreDetailsWatch(
        id: UUID,
        spaceId: SpaceID,
        continuation: AsyncThrowingStream<SpaceCoreDetailsUpdate, Error>.Continuation
    ) {
        startStream(
            id: id,
            operation: .spaceCoreDetails,
            continuation: continuation,
            validate: { _ in },
            makeStream: { resources in
                do {
                    return resources.spaceCoreDetailsQuery.watchSpaceCoreDetails(
                        try SpaceCoreDetailsRequest(
                            accountId: resources.accountId,
                            spaceId: spaceId
                        )
                    )
                } catch {
                    return AsyncThrowingStream { $0.finish(throwing: error) }
                }
            }
        )
    }

    func startBudgetCategoryWatch(
        id: UUID,
        continuation: AsyncThrowingStream<BudgetCategoryReferenceSnapshot, Error>.Continuation
    ) {
        startStream(
            id: id,
            operation: .budgetCategories,
            continuation: continuation,
            validate: { _ in },
            makeStream: { resources in
                resources.budgetCategoryQuery.watchBudgetCategories(
                    accountId: resources.accountId
                )
            }
        )
    }

    func startSpaceAssignmentDestinationWatch(
        id: UUID,
        scope: ItemPlacementScope,
        continuation:
            AsyncThrowingStream<SpaceAssignmentDestinationDirectorySnapshot, Error>.Continuation
    ) {
        startStream(
            id: id,
            operation: .spaceAssignmentDestinations,
            continuation: continuation,
            validate: { _ in },
            makeStream: { resources in
                do {
                    return resources.spaceAssignmentDestinationQuery.watchEligibleDestinations(
                        try SpaceAssignmentDestinationRequest(
                            accountId: resources.accountId,
                            scope: scope
                        )
                    )
                } catch {
                    return AsyncThrowingStream { $0.finish(throwing: error) }
                }
            }
        )
    }

    func startTransferDestinationWatch(
        id: UUID,
        source: ProjectSummary,
        continuation:
            AsyncThrowingStream<TransferDestinationSelectionSnapshot, Error>.Continuation
    ) {
        startStream(
            id: id,
            operation: .transferDestinations,
            continuation: continuation,
            validate: { resources in
                guard source.accountId == resources.accountId else {
                    throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch
                }
            },
            makeStream: { resources in
                resources.transferDestinationQuery.watchTransferDestinations(
                    source: source
                )
            }
        )
    }

    func startProjectArchiveOperationWatch(
        id: UUID,
        operationId: OperationID,
        continuation: AsyncThrowingStream<OperationSnapshot, Error>.Continuation
    ) {
        startStream(
            id: id,
            operation: .projectArchiveOperation,
            continuation: continuation,
            validate: { _ in },
            makeStream: { resources in
                resources.projectArchiveStore.watchOperation(operationId)
            }
        )
    }

    func startClientArchiveOperationWatch(
        id: UUID,
        operationId: OperationID,
        continuation: AsyncThrowingStream<OperationSnapshot, Error>.Continuation
    ) {
        startStream(
            id: id,
            operation: .clientArchiveOperation,
            continuation: continuation,
            validate: { _ in },
            makeStream: { resources in
                resources.clientArchiveStore.watchOperation(operationId)
            }
        )
    }

    func cancelStream(id: UUID) {
        if let task = streamTasks[id] {
            task.cancel()
        } else if case .open = state {
            cancelledBeforeStart.insert(id)
        }
    }

    func close() async throws {
        let task: Task<Result<Void, LedgerOfflineClientRuntimeFailure>, Never>
        switch state {
        case .open:
            task = Task { await self.performClose() }
            state = .closing(task)
        case .closing(let existing):
            task = existing
        case .closed(let result):
            return try result.get()
        }
        return try await task.value.get()
    }

    private func withFiniteLease<Value: Sendable>(
        _ operation: AccountWorkspaceRuntimeFiniteOperation,
        body: @Sendable (AccountWorkspaceRuntimeResources) async throws -> Value
    ) async throws -> Value {
        guard case .open = state, let resources else {
            throw LedgerOfflineClientRuntimeFailure.runtimeClosed
        }
        finiteLeaseCount += 1
        do {
            try await resources.finiteOperationCheckpoint(operation)
            let value = try await body(resources)
            releaseFiniteLease()
            return value
        } catch {
            releaseFiniteLease()
            throw error
        }
    }

    private func startStream<Value: Sendable>(
        id: UUID,
        operation: AccountWorkspaceRuntimeStreamOperation,
        continuation: AsyncThrowingStream<Value, Error>.Continuation,
        validate: @Sendable (AccountWorkspaceRuntimeResources) throws -> Void,
        makeStream:
            @Sendable @escaping (
                AccountWorkspaceRuntimeResources
            ) -> AsyncThrowingStream<Value, Error>
    ) {
        guard case .open = state, let resources else {
            continuation.finish(throwing: LedgerOfflineClientRuntimeFailure.runtimeClosed)
            return
        }
        guard !Task.isCancelled, cancelledBeforeStart.remove(id) == nil else {
            continuation.finish(throwing: CancellationError())
            return
        }
        do {
            try validate(resources)
        } catch {
            continuation.finish(throwing: error)
            return
        }

        let task = Task.detached { [resources] in
            do {
                try await resources.streamOperationCheckpoint(operation)
                try Task.checkCancellation()
                let stream = makeStream(resources)
                for try await value in stream {
                    try Task.checkCancellation()
                    if case .terminated = continuation.yield(value) { break }
                }
                continuation.finish()
            } catch is CancellationError {
                continuation.finish(throwing: CancellationError())
            } catch {
                continuation.finish(throwing: error)
            }
            await self.streamFinished(id: id)
        }
        streamTasks[id] = task
    }

    private func streamFinished(id: UUID) {
        guard streamTasks.removeValue(forKey: id) != nil else { return }
        resumeDrainWaitersIfDrained()
    }

    private func releaseFiniteLease() {
        precondition(finiteLeaseCount > 0)
        finiteLeaseCount -= 1
        resumeDrainWaitersIfDrained()
    }

    private func performClose() async -> Result<Void, LedgerOfflineClientRuntimeFailure> {
        for task in streamTasks.values { task.cancel() }
        await waitUntilDrained()

        guard let resources else {
            let result: Result<Void, LedgerOfflineClientRuntimeFailure> = .success(())
            state = .closed(result)
            return result
        }

        await resources.budgetCategoryQuery.cancelAndDrainWatches()
        await resources.spaceAssignmentDestinationQuery.cancelAndDrainWatches()
        await resources.projectNoteQuery.cancelAndDrainWatches()
        await resources.spaceCoreDetailsQuery.cancelAndDrainWatches()
        await resources.transferDestinationQuery.cancelAndDrainWatches()
        await resources.projectArchiveStore.cancelAndDrainWatches()
        await resources.clientArchiveStore.cancelAndDrainWatches()

        var attachmentFailed = false
        var structuredFailed = false
        resources.lifecycleEvent(.attachmentDatabaseCloseAttempted)
        do {
            try await resources.closeAttachmentDatabase()
        } catch {
            attachmentFailed = true
        }
        resources.lifecycleEvent(.structuredDatabaseCloseAttempted)
        do {
            try await resources.closeStructuredDatabase()
        } catch {
            structuredFailed = true
        }

        let lifecycleEvent = resources.lifecycleEvent
        self.resources = nil
        cancelledBeforeStart.removeAll(keepingCapacity: false)
        lifecycleEvent(.derivedResourcesReleased)
        lifecycleEvent(.vaultReleased)

        let result: Result<Void, LedgerOfflineClientRuntimeFailure>
        if attachmentFailed || structuredFailed {
            result = .failure(
                .databaseCloseFailed(
                    attachmentDatabase: attachmentFailed,
                    structuredDatabase: structuredFailed
                )
            )
        } else {
            result = .success(())
        }
        state = .closed(result)
        return result
    }

    private func waitUntilDrained() async {
        guard finiteLeaseCount != 0 || !streamTasks.isEmpty else { return }
        await withCheckedContinuation { continuation in
            drainWaiters.append(continuation)
        }
    }

    private func resumeDrainWaitersIfDrained() {
        guard finiteLeaseCount == 0, streamTasks.isEmpty else { return }
        let waiters = drainWaiters
        drainWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters { waiter.resume() }
    }
}

public enum LedgerPowerSyncLocalBootstrap {
    public static func open(
        validatedEnvironment: ValidatedLedgerEnvironment,
        principalId: PrincipalID,
        accountId: AccountID
    ) async throws -> LedgerOfflineClientRuntime {
        guard
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        else {
            throw LedgerPowerSyncLocalBootstrapFailure(
                stage: .applicationSupportResolution
            )
        }
        return try await open(
            validatedEnvironment: validatedEnvironment,
            principalId: principalId,
            accountId: accountId,
            applicationSupportDirectory: applicationSupport,
            dependencies: .live
        )
    }

    static func open(
        validatedEnvironment: ValidatedLedgerEnvironment,
        principalId: PrincipalID,
        accountId: AccountID,
        applicationSupportDirectory: URL,
        dependencies: LedgerPowerSyncLocalBootstrapDependencies
    ) async throws -> LedgerOfflineClientRuntime {
        var stage: LedgerPowerSyncLocalBootstrapStage = .workspaceLocationResolution
        var structured: AccountWorkspaceOpenedDatabase?
        var attachment: AccountWorkspaceOpenedDatabase?
        var vault: AttachmentLocalByteVault?
        var attachmentStore: (any AccountWorkspaceAttachmentStoring)?
        var pendingWorkQuery: (any AccountWorkspacePendingWorkSummarizing)?
        var budgetCategoryQuery: (any AccountWorkspaceBudgetCategoryQuerying)?
        var spaceAssignmentDestinationQuery:
            (any AccountWorkspaceSpaceAssignmentDestinationQuerying)?
        var projectNoteQuery: (any AccountWorkspaceProjectNoteQuerying)?
        var spaceCoreDetailsQuery: (any AccountWorkspaceSpaceCoreDetailsQuerying)?
        var runtimeResources: AccountWorkspaceRuntimeResources?

        do {
            let location = try LedgerWorkspaceRuntimeIsolation.resolve(
                validatedEnvironment: validatedEnvironment,
                principalId: principalId,
                accountId: accountId,
                applicationSupportDirectory: applicationSupportDirectory
            )
            let scope = try AttachmentDurabilityNamespaceScope(
                validatedEnvironment: validatedEnvironment,
                principalId: principalId,
                accountId: accountId
            )

            stage = .databaseKeyLoad
            let databaseKey = try dependencies.loadDatabaseKey(
                location.databaseKeychainService,
                location.databaseKeychainAccount
            )
            stage = .mediaKeyLoad
            let mediaKeyBytes = try dependencies.loadMediaKeyBytes(
                location.mediaKeychainService,
                location.mediaKeychainAccount
            )
            stage = .keyValidation
            let mediaKey = try AttachmentMediaEncryptionKey(bytes: mediaKeyBytes)
            let mediaKeyHex = mediaKeyBytes.map { String(format: "%02x", $0) }.joined()
            guard mediaKeyHex != databaseKey.hexadecimal,
                location.databaseKeychainService != location.mediaKeychainService
                    || location.databaseKeychainAccount != location.mediaKeychainAccount
            else {
                throw LedgerPowerSyncDatabaseFailure.invalidEncryptionKey
            }

            stage = .directoryPreparation
            try dependencies.createDirectory(
                location.structuredDatabaseURL.deletingLastPathComponent()
            )
            try dependencies.createDirectory(location.mediaVaultRootURL)

            stage = .structuredDatabaseOpen
            let openedStructured = try dependencies.openStructuredDatabase(
                location.structuredDatabaseURL.path,
                databaseKey
            )
            structured = openedStructured
            dependencies.lifecycleEvent(.structuredDatabaseOpened)
            stage = .structuredDatabaseValidation
            try await dependencies.validateStructuredDatabase(openedStructured.database)

            stage = .attachmentDatabaseOpen
            let openedAttachment = try dependencies.openAttachmentDatabase(
                location.attachmentDatabaseURL.path,
                databaseKey
            )
            attachment = openedAttachment
            dependencies.lifecycleEvent(.attachmentDatabaseOpened)
            stage = .attachmentDatabaseValidation
            try await dependencies.validateAttachmentDatabase(openedAttachment.database)

            stage = .mediaVaultOpen
            let openedVault = try dependencies.makeVault(
                location.mediaVaultRootURL,
                scope,
                mediaKey
            )
            vault = openedVault
            dependencies.lifecycleEvent(.vaultConstructed)

            stage = .attachmentStoreConstruction
            let madeAttachmentStore = try dependencies.makeAttachmentStore(
                openedAttachment.database,
                openedVault,
                scope,
                dependencies.now
            )
            attachmentStore = madeAttachmentStore
            dependencies.lifecycleEvent(.attachmentStoreConstructed)

            stage = .pendingWorkQueryConstruction
            let madePendingWorkQuery = try dependencies.makePendingWorkQuery(
                openedStructured.database,
                madeAttachmentStore,
                validatedEnvironment.manifest.environment,
                principalId,
                accountId,
                dependencies.now
            )
            pendingWorkQuery = madePendingWorkQuery
            dependencies.lifecycleEvent(.pendingWorkQueryConstructed)

            stage = .budgetCategoryQueryConstruction
            let madeBudgetCategoryQuery = try dependencies.makeBudgetCategoryQuery(
                openedStructured.database,
                principalId,
                accountId,
                dependencies.now
            )
            budgetCategoryQuery = madeBudgetCategoryQuery
            dependencies.lifecycleEvent(.budgetCategoryQueryConstructed)

            stage = .spaceAssignmentDestinationQueryConstruction
            let madeSpaceAssignmentDestinationQuery =
                try dependencies.makeSpaceAssignmentDestinationQuery(
                    openedStructured.database,
                    principalId,
                    accountId,
                    dependencies.now
                )
            spaceAssignmentDestinationQuery = madeSpaceAssignmentDestinationQuery
            dependencies.lifecycleEvent(.spaceAssignmentDestinationQueryConstructed)

            stage = .projectNoteQueryConstruction
            let madeProjectNoteQuery = try dependencies.makeProjectNoteQuery(
                openedStructured.database,
                principalId,
                accountId,
                dependencies.now
            )
            projectNoteQuery = madeProjectNoteQuery
            dependencies.lifecycleEvent(.projectNoteQueryConstructed)

            let madeSpaceCoreDetailsQuery = dependencies.makeSpaceCoreDetailsQuery(
                openedStructured.database,
                principalId,
                accountId,
                dependencies.now
            )
            spaceCoreDetailsQuery = madeSpaceCoreDetailsQuery

            let madeProjectArchiveStore = dependencies.makeProjectArchiveStore(
                openedStructured.database,
                accountId,
                principalId,
                dependencies.now
            )

            let madeRuntimeResources = AccountWorkspaceRuntimeResources(
                structuredDatabase: openedStructured.database,
                attachmentDatabase: openedAttachment.database,
                attachmentStore: madeAttachmentStore,
                pendingWorkQuery: madePendingWorkQuery,
                budgetCategoryQuery: madeBudgetCategoryQuery,
                spaceAssignmentDestinationQuery: madeSpaceAssignmentDestinationQuery,
                projectNoteQuery: madeProjectNoteQuery,
                spaceCoreDetailsQuery: madeSpaceCoreDetailsQuery,
                projectArchiveStore: madeProjectArchiveStore,
                vault: openedVault,
                closeAttachmentDatabase: openedAttachment.closePreservingData,
                closeStructuredDatabase: openedStructured.closePreservingData,
                finiteOperationCheckpoint: dependencies.finiteOperationCheckpoint,
                streamOperationCheckpoint: dependencies.streamOperationCheckpoint,
                lifecycleEvent: dependencies.lifecycleEvent,
                environment: validatedEnvironment.manifest.environment,
                principalId: principalId,
                accountId: accountId,
                now: dependencies.now
            )
            runtimeResources = madeRuntimeResources

            stage = .runtimeConstruction
            let owner = try dependencies.makeLifecycleOwner(madeRuntimeResources)
            dependencies.lifecycleEvent(.lifecycleOwnerConstructed)
            return LedgerOfflineClientRuntime(lifecycleOwner: owner)
        } catch {
            let hadDerivedResources =
                runtimeResources != nil
                || spaceAssignmentDestinationQuery != nil
                || projectNoteQuery != nil
                || spaceCoreDetailsQuery != nil
                || budgetCategoryQuery != nil
                || pendingWorkQuery != nil
                || attachmentStore != nil
            runtimeResources = nil
            spaceAssignmentDestinationQuery = nil
            projectNoteQuery = nil
            spaceCoreDetailsQuery = nil
            budgetCategoryQuery = nil
            pendingWorkQuery = nil
            attachmentStore = nil
            if vault != nil {
                vault = nil
                dependencies.lifecycleEvent(.vaultReleased)
            }
            if hadDerivedResources {
                dependencies.lifecycleEvent(.derivedResourcesReleased)
            }

            let attachmentCleanup = await cleanup(
                attachment,
                event: .attachmentDatabaseCloseAttempted,
                dependencies: dependencies
            )
            attachment = nil
            let structuredCleanup = await cleanup(
                structured,
                event: .structuredDatabaseCloseAttempted,
                dependencies: dependencies
            )
            structured = nil
            throw LedgerPowerSyncLocalBootstrapFailure(
                stage: stage,
                attachmentDatabaseCleanup: attachmentCleanup,
                structuredDatabaseCleanup: structuredCleanup
            )
        }
    }

    private static func cleanup(
        _ opened: AccountWorkspaceOpenedDatabase?,
        event: AccountWorkspaceRuntimeLifecycleEvent,
        dependencies: LedgerPowerSyncLocalBootstrapDependencies
    ) async -> LedgerPowerSyncLocalCleanupOutcome {
        guard let opened else { return .notOpened }
        dependencies.lifecycleEvent(event)
        do {
            try await opened.closePreservingData()
            return .succeeded
        } catch {
            return .failed
        }
    }
}
