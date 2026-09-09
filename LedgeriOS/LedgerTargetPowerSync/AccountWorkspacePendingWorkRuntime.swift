import Foundation
import LedgerTargetCore
import PowerSync

public enum LedgerPowerSyncLocalBootstrapStage: String, Equatable, Sendable {
    case applicationSupportResolution
    case workspaceLocationResolution
    case workspaceAccessCheck
    case workspaceAccessRemoved
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
    case spaceBrowserQueryConstruction
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
    AttachmentPendingWorkObserving,
    AttachmentLocalByteResolving
{}

extension AttachmentCapturePowerSyncStore: AccountWorkspaceAttachmentStoring {}

protocol AccountBusinessLogoCaching: Sendable {
    func cachedAccountLogo(_ reference: AccountBusinessLogoReference) async throws -> Data?
    func cacheAccountLogo(_ bytes: Data, reference: AccountBusinessLogoReference) async throws
}
extension AttachmentCapturePowerSyncStore: AccountBusinessLogoCaching {}

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

protocol AccountWorkspaceSpaceListQuerying: SpaceListQuerying {
    func cancelAndDrainWatches() async
}

extension SpaceBrowserPowerSyncProvider: AccountWorkspaceSpaceListQuerying {}

protocol AccountWorkspaceProjectSetupStoring: ProjectSetupOperating, Sendable {
    func watchOperation(
        _ operationId: OperationID
    ) -> AsyncThrowingStream<OperationSnapshot, Error>
    func cancelAndDrainWatches() async
}

extension ProjectSetupPowerSyncStore: AccountWorkspaceProjectSetupStoring {}

protocol AccountWorkspaceProjectArchiveStoring: ProjectArchiving, Sendable {
    func watchOperation(
        _ operationId: OperationID
    ) -> AsyncThrowingStream<OperationSnapshot, Error>
    func cancelAndDrainWatches() async
}

extension ProjectArchivePowerSyncStore: AccountWorkspaceProjectArchiveStoring {}

protocol AccountWorkspaceSpaceChecklistRevisionStoring:
    SpaceChecklistRevising, RejectedOperationRecoveryQuerying, Sendable
{
    func watchOperation(
        _ operationId: OperationID
    ) -> AsyncThrowingStream<OperationSnapshot, Error>
    func cancelAndDrainWatches() async
}

extension SpaceChecklistRevisionPowerSyncStore:
    AccountWorkspaceSpaceChecklistRevisionStoring
{}

protocol AccountWorkspaceItemSpaceAssignmentStoring: ItemSpaceAssigning, Sendable {
    func watchOperation(
        _ operationId: OperationID
    ) -> AsyncThrowingStream<OperationSnapshot, Error>
    func cancelAndDrainWatches() async
}

extension ItemSpaceAssignmentPowerSyncStore:
    AccountWorkspaceItemSpaceAssignmentStoring
{}

protocol AccountWorkspaceItemSpaceClearingStoring:
    ItemSpaceAssignmentClearing, Sendable
{
    func watchOperation(
        _ operationId: OperationID
    ) -> AsyncThrowingStream<OperationSnapshot, Error>
    func cancelAndDrainWatches() async
}

extension ItemSpaceClearingPowerSyncStore:
    AccountWorkspaceItemSpaceClearingStoring
{}

enum AccountWorkspaceRuntimeFiniteOperation: Equatable, Sendable {
    case createClient
    case createProject
    case archiveProject
    case reviseSpaceChecklists
    case rejectedOperationRecoverySnapshot
    case archiveClient
    case assignItemsToSpace
    case clearItemSpaceAssignments
    case pendingUploadCount
    case encryptionCipher
    case captureAttachment
    case resolveAttachmentBytes
    case pendingWorkSummary
    case readDownloadedItemPlacements
    case readDownloadedPropertyManagementReport
    case readDownloadedClientSummaryPhysicalReport
    case readAccountBusinessProfile
}

enum AccountWorkspaceRuntimeStreamOperation: Equatable, Sendable {
    case accountBusinessProfile
    case propertyManagementReport
    case clientSummaryPhysicalReport
    case downloadedItemPlacements
    case clientDetails
    case projectDetails
    case clientDirectory
    case projectDirectory
    case projectNotes
    case spaceCoreDetails
    case spaceDirectory
    case budgetCategories
    case spaceAssignmentDestinations
    case transferDestinations
    case projectCreationOperation
    case projectArchiveOperation
    case spaceChecklistRevisionOperation
    case rejectedOperationRecovery
    case clientArchiveOperation
    case itemSpaceAssignmentOperation
    case itemSpaceClearingOperation
}

struct AccountWorkspaceOpenedDatabase: @unchecked Sendable {
    let database: any PowerSyncDatabaseProtocol
    let closePreservingData: @Sendable () async throws -> Void
}

struct LedgerPowerSyncLocalBootstrapDependencies: @unchecked Sendable {
    var subscribePhysicalItems: (@Sendable (AccountID) async throws -> any SyncStreamSubscription)? = nil
    var accessCoordinator: LedgerWorkspaceAccessCoordinator
    var requireWorkspaceNotRemoved: @Sendable (LedgerEnvironmentKind, PrincipalID, AccountID) throws -> Void
    var recordWorkspaceRemoval: @Sendable (LedgerEnvironmentKind, PrincipalID, AccountID) throws -> Void
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
    var makeSpaceBrowserQuery:
        @Sendable (
            any PowerSyncDatabaseProtocol,
            PrincipalID,
            AccountID,
            @Sendable @escaping () -> Date
        ) throws -> any AccountWorkspaceSpaceListQuerying
    var makeProjectSetupStore:
        @Sendable (
            any PowerSyncDatabaseProtocol,
            AccountID,
            PrincipalID,
            @Sendable @escaping () -> Date
        ) -> any AccountWorkspaceProjectSetupStoring
    var makeProjectArchiveStore:
        @Sendable (
            any PowerSyncDatabaseProtocol,
            AccountID,
            PrincipalID,
            @Sendable @escaping () -> Date
        ) -> any AccountWorkspaceProjectArchiveStoring
    var makeItemSpaceAssignmentStore:
        @Sendable (
            any PowerSyncDatabaseProtocol,
            AccountID,
            PrincipalID,
            @Sendable @escaping () -> Date
        ) -> any AccountWorkspaceItemSpaceAssignmentStoring
    var makeItemSpaceClearingStore:
        @Sendable (
            any PowerSyncDatabaseProtocol,
            AccountID,
            PrincipalID,
            @Sendable @escaping () -> Date
        ) -> any AccountWorkspaceItemSpaceClearingStoring
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
    var downloadAccountLogo: (@Sendable (AccountBusinessLogoReference) async throws -> Data)? = nil

    static let live = LedgerPowerSyncLocalBootstrapDependencies(
        accessCoordinator: .shared,
        requireWorkspaceNotRemoved: { try LedgerWorkspaceRemovalRegistry.requireNotRemoved(
            environment: $0, principalId: $1, accountId: $2
        ) },
        recordWorkspaceRemoval: { try LedgerWorkspaceRemovalRegistry.recordRemoval(
            environment: $0, principalId: $1, accountId: $2
        ) },
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
        makeSpaceBrowserQuery: { database, principalId, accountId, now in
            SpaceBrowserPowerSyncProvider(
                database: database,
                principalId: principalId,
                accountId: accountId,
                now: now
            )
        },
        makeProjectSetupStore: { database, accountId, principalId, now in
            ProjectSetupPowerSyncStore(
                database: database,
                accountId: accountId,
                principalId: principalId,
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
        makeItemSpaceAssignmentStore: { database, accountId, principalId, now in
            ItemSpaceAssignmentPowerSyncStore(
                database: database,
                accountId: accountId,
                principalId: principalId,
                now: now
            )
        },
        makeItemSpaceClearingStore: { database, accountId, principalId, now in
            ItemSpaceClearingPowerSyncStore(
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
    case spaceBrowserQueryConstructed
    case lifecycleOwnerConstructed
    case accessLocked
    case derivedResourcesReleased
    case vaultReleased
    case attachmentDatabaseCloseAttempted
    case structuredDatabaseCloseAttempted
}

final class AccountWorkspaceRuntimeResources: @unchecked Sendable {
    let subscribePhysicalItems: (@Sendable (AccountID) async throws -> any SyncStreamSubscription)?
    let accessFence: LedgerWorkspaceAccessFence
    let now: @Sendable () -> Date
    let structuredDatabase: any PowerSyncDatabaseProtocol
    let attachmentDatabase: any PowerSyncDatabaseProtocol
    let creationStore: ClientCreationPowerSyncStore
    let detailsQuery: ClientCoreDetailsPowerSyncQuery
    let projectSetupStore: any AccountWorkspaceProjectSetupStoring
    let projectArchiveStore: any AccountWorkspaceProjectArchiveStoring
    let spaceChecklistRevisionStore:
        any AccountWorkspaceSpaceChecklistRevisionStoring
    let itemSpaceAssignmentStore: any AccountWorkspaceItemSpaceAssignmentStoring
    let itemSpaceClearingStore: any AccountWorkspaceItemSpaceClearingStoring
    let clientArchiveStore: ClientArchivePowerSyncStore
    let projectDetailsQuery: ProjectCoreDetailsPowerSyncQuery
    let directoryQuery: ClientProjectDirectoryPowerSyncQuery
    let transferDestinationQuery:
        any AccountWorkspaceTransferDestinationSelectionQuerying
    let attachmentStore: any AccountWorkspaceAttachmentStoring
    let downloadAccountLogo: (@Sendable (AccountBusinessLogoReference) async throws -> Data)?
    let pendingWorkQuery: any AccountWorkspacePendingWorkSummarizing
    let budgetCategoryQuery: any AccountWorkspaceBudgetCategoryQuerying
    let spaceAssignmentDestinationQuery:
        any AccountWorkspaceSpaceAssignmentDestinationQuerying
    let projectNoteQuery: any AccountWorkspaceProjectNoteQuerying
    let spaceCoreDetailsQuery: any AccountWorkspaceSpaceCoreDetailsQuerying
    let spaceBrowserQuery: any AccountWorkspaceSpaceListQuerying
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
        spaceBrowserQuery: any AccountWorkspaceSpaceListQuerying,
        projectSetupStore: any AccountWorkspaceProjectSetupStoring,
        projectArchiveStore: any AccountWorkspaceProjectArchiveStoring,
        itemSpaceAssignmentStore: any AccountWorkspaceItemSpaceAssignmentStoring,
        itemSpaceClearingStore: any AccountWorkspaceItemSpaceClearingStoring,
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
        now: @Sendable @escaping () -> Date,
        accessFence: LedgerWorkspaceAccessFence,
        subscribePhysicalItems: (@Sendable (AccountID) async throws -> any SyncStreamSubscription)? = nil,
        downloadAccountLogo: (@Sendable (AccountBusinessLogoReference) async throws -> Data)? = nil
    ) {
        self.downloadAccountLogo = downloadAccountLogo
        self.subscribePhysicalItems = subscribePhysicalItems
        self.accessFence = accessFence
        self.now = now
        self.structuredDatabase = structuredDatabase
        self.attachmentDatabase = attachmentDatabase
        creationStore = ClientCreationPowerSyncStore(database: structuredDatabase, now: now)
        detailsQuery = ClientCoreDetailsPowerSyncQuery(
            database: structuredDatabase,
            principalId: principalId,
            accountId: accountId,
            now: now
        )
        self.projectSetupStore = projectSetupStore
        self.projectArchiveStore = projectArchiveStore
        spaceChecklistRevisionStore = SpaceChecklistRevisionPowerSyncStore(
            database: structuredDatabase,
            accountId: accountId,
            principalId: principalId,
            now: now
        )
        self.itemSpaceAssignmentStore = itemSpaceAssignmentStore
        self.itemSpaceClearingStore = itemSpaceClearingStore
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
        self.spaceBrowserQuery = spaceBrowserQuery
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
    private var accessLocked = false
    private let accessFence: LedgerWorkspaceAccessFence
    private var normalAccessLocked: Bool { accessLocked || accessFence.isRemoved }
    private var resources: AccountWorkspaceRuntimeResources?
    private var finiteLeaseCount = 0
    private var streamTasks: [UUID: Task<Void, Never>] = [:]
    private var commandUploadTask: Task<Void, Error>?
    private var cancelledBeforeStart: Set<UUID> = []
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []

    init(resources: AccountWorkspaceRuntimeResources) {
        self.resources = resources
        accessFence = resources.accessFence
    }

    nonisolated func watchAccessRemoval() -> AsyncStream<Void> {
        accessFence.watchRemoval()
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

    func reviseSpaceChecklists(
        _ command: ReviseSpaceChecklistsCommand
    ) async throws -> OperationReceipt {
        try await withFiniteLease(.reviseSpaceChecklists) { resources in
            guard command.envelope.accountId == resources.accountId else {
                throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch
            }
            guard command.envelope.actorPrincipalId == resources.principalId else {
                throw LedgerOfflineClientRuntimeFailure.principalScopeMismatch
            }
            return try await resources.spaceChecklistRevisionStore
                .reviseChecklists(command)
        }
    }

    func rejectedOperations(
        _ request: RejectedOperationRecoveryRequest
    ) async throws -> RejectedOperationRecoverySnapshot {
        try await withFiniteLease(.rejectedOperationRecoverySnapshot) { resources in
            try await resources.spaceChecklistRevisionStore
                .rejectedOperations(request)
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

    func assignItemsToSpace(
        _ command: AssignItemsToSpaceCommand
    ) async throws -> OperationReceipt {
        try await withFiniteLease(.assignItemsToSpace) { resources in
            guard command.envelope.accountId == resources.accountId else {
                throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch
            }
            guard command.envelope.actorPrincipalId == resources.principalId else {
                throw LedgerOfflineClientRuntimeFailure.principalScopeMismatch
            }
            return try await resources.itemSpaceAssignmentStore.assignItemsToSpace(command)
        }
    }

    func clearItemSpaceAssignments(
        _ command: ClearItemSpaceAssignmentsCommand
    ) async throws -> OperationReceipt {
        try await withFiniteLease(.clearItemSpaceAssignments) { resources in
            guard command.envelope.accountId == resources.accountId else {
                throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch
            }
            guard command.envelope.actorPrincipalId == resources.principalId else {
                throw LedgerOfflineClientRuntimeFailure.principalScopeMismatch
            }
            return try await resources.itemSpaceClearingStore
                .clearItemSpaceAssignments(command)
        }
    }

    func pendingUploadCount() async throws -> Int64 {
        try await withFiniteLease(.pendingUploadCount) { resources in
            try await resources.structuredDatabase.get("SELECT count(*) FROM ps_crud") { cursor in
                try cursor.getInt64(index: 0)
            }
        }
    }

    func readDownloadedItemPlacements(accountId: AccountID, scope: ItemPlacementScope) async throws -> DownloadedItemPlacements {
        try await withFiniteLease(.readDownloadedItemPlacements) { resources in
            guard accountId == resources.accountId else {
                throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch
            }
            let rows = try await CurrentItemPlacementLocalReader(database: resources.structuredDatabase)
                .read(accountId: resources.accountId, principalId: resources.principalId, scope: scope)
            return try DownloadedItemPlacements(accountId: resources.accountId, scope: scope, rows: rows)
        }
    }

    func readDownloadedItemPlacementHistory(accountId: AccountID, itemId: ItemID) async throws -> DownloadedItemPlacementHistory {
        try await withFiniteLease(.readDownloadedItemPlacements) { resources in
            guard accountId.rawValue.utf8.elementsEqual(resources.accountId.rawValue.utf8) else { throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch }
            return try await CurrentItemPlacementLocalReader(database: resources.structuredDatabase)
                .readHistory(accountId: accountId, principalId: resources.principalId, itemId: itemId)
        }
    }

    func startDownloadedItemPlacementHistoryWatch(id: UUID, accountId: AccountID, itemId: ItemID,
        continuation: AsyncThrowingStream<DownloadedItemPlacementHistory, Error>.Continuation) {
        guard !normalAccessLocked, case .open = state, let resources else {
            continuation.finish(throwing: LedgerOfflineClientRuntimeFailure.runtimeClosed); return
        }
        guard !Task.isCancelled, cancelledBeforeStart.remove(id) == nil else {
            continuation.finish(throwing: CancellationError()); return
        }
        guard accountId.rawValue.utf8.elementsEqual(resources.accountId.rawValue.utf8) else {
            continuation.finish(throwing: LedgerOfflineClientRuntimeFailure.accountScopeMismatch); return
        }
        let task = Task.detached { [resources] in
            do {
                try await resources.streamOperationCheckpoint(.downloadedItemPlacements)
                try Task.checkCancellation()
                let reader = CurrentItemPlacementLocalReader(database: resources.structuredDatabase)
                // Observe already downloaded evidence; no historical subscription
                // or broader access is created by opening this detail screen.
                for try await rows in try reader.watchHistory(accountId: accountId, principalId: resources.principalId, itemId: itemId) {
                    try Task.checkCancellation()
                    let value = try CurrentItemPlacementLocalReader.history(accountId: accountId, itemId: itemId, rows: rows)
                    guard await self.forwardStreamValue(value, to: continuation) else { break }
                }
                continuation.finish()
            } catch is CancellationError {
                continuation.finish(throwing: CancellationError())
            } catch {
                await self.finishStream(continuation, error: error)
            }
            await self.streamFinished(id: id)
        }
        streamTasks[id] = task
    }

    func readAccountBusinessProfile(accountId: AccountID) async throws -> AccountBusinessProfile {
        try await withFiniteLease(.readAccountBusinessProfile) { resources in
            guard accountId.rawValue.utf8.elementsEqual(resources.accountId.rawValue.utf8) else {
                throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch
            }
            let reader = AccountBusinessProfileLocalReader(database: resources.structuredDatabase)
            let row = try await reader.read(accountId: accountId, principalId: resources.principalId)
            var logo: AccountBusinessProfile.Logo = .absent
            if let reference = row.logo {
                logo = .notDownloaded
                do {
                    if let cache = resources.attachmentStore as? any AccountBusinessLogoCaching,
                       let bytes = try await cache.cachedAccountLogo(reference) { logo = .downloaded(bytes) }
                } catch is CancellationError { throw CancellationError() }
                catch { logo = .unavailable }
            }
            let current = try await reader.read(accountId: accountId, principalId: resources.principalId)
            guard current.logo == row.logo else { throw AccountBusinessProfileReadFailure.unavailable }
            return AccountBusinessProfile(accountId: accountId, name: current.name, logo: logo, isStale: true)
        }
    }

    func startAccountBusinessProfileWatch(id: UUID, accountId: AccountID,
        continuation: AsyncThrowingStream<AccountBusinessProfile, Error>.Continuation) {
        guard !normalAccessLocked, case .open = state, let resources else {
            continuation.finish(throwing: LedgerOfflineClientRuntimeFailure.runtimeClosed); return
        }
        guard !Task.isCancelled, cancelledBeforeStart.remove(id) == nil else {
            continuation.finish(throwing: CancellationError()); return
        }
        guard accountId.rawValue.utf8.elementsEqual(resources.accountId.rawValue.utf8) else {
            continuation.finish(throwing: LedgerOfflineClientRuntimeFailure.accountScopeMismatch); return
        }
        let task = Task.detached { [resources] in
            do {
                try await resources.streamOperationCheckpoint(.accountBusinessProfile)
                let reader = AccountBusinessProfileLocalReader(database: resources.structuredDatabase)
                let cache = resources.attachmentStore as? any AccountBusinessLogoCaching
                try await withOwnedSyncStreamWatch(subscribe: {
                    try await resources.structuredDatabase.syncStream(name: "account_business_profile",
                        params: ["account_id": .string(accountId.rawValue)]).subscribe()
                }, observe: {
                var receivedProfile = false
                for try await rows in try reader.watch(accountId: accountId, principalId: resources.principalId) {
                    try Task.checkCancellation()
                    if rows.isEmpty {
                        guard !receivedProfile else { throw AccountBusinessProfileReadFailure.unavailable }
                        let memberships = try await resources.structuredDatabase.getAll(sql: """
                            SELECT id FROM spike_account_memberships
                            WHERE account_id = ? AND principal_id = ? AND state = 'active'
                            """, parameters: [accountId.rawValue, resources.principalId.rawValue],
                            mapper: { try $0.getString(name: "id") })
                        guard !memberships.isEmpty else { throw AccountBusinessProfileReadFailure.unavailable }
                        // Keep the selected subscription alive for its first download.
                        // Missing profile evidence is not an explicit absent logo.
                        continue
                    }
                    guard rows.count == 1 else { throw AccountBusinessProfileReadFailure.unavailable }
                    receivedProfile = true
                    let row = rows[0]
                    var logo: AccountBusinessProfile.Logo = .absent
                    if let reference = row.logo {
                        logo = .notDownloaded
                        do {
                            if let bytes = try await cache?.cachedAccountLogo(reference) { logo = .downloaded(bytes) }
                        } catch is CancellationError { throw CancellationError() }
                        catch { logo = .unavailable }
                        if case .downloaded = logo {} else if let download = resources.downloadAccountLogo, let cache {
                            let current = try await reader.read(accountId: accountId, principalId: resources.principalId)
                            guard current.logo == reference else { continue }
                            // Render honest saved metadata while retrieval is in progress.
                            guard await self.forwardStreamValue(AccountBusinessProfile(accountId: accountId,
                                name: current.name, logo: logo, isStale: true), to: continuation) else { break }
                            do {
                                let bytes = try await download(reference)
                                try Task.checkCancellation()
                                let current = try await reader.read(accountId: accountId, principalId: resources.principalId)
                                guard current.logo == reference else { continue }
                                guard !resources.accessFence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
                                try await cache.cacheAccountLogo(bytes, reference: reference)
                                logo = .downloaded(bytes)
                            } catch is CancellationError { throw CancellationError() }
                            catch { logo = .unavailable }
                        }
                    }
                    try Task.checkCancellation()
                    // Revalidate after every awaited byte operation. A changed or
                    // removed reference must not display an earlier logo/name.
                    let current = try await reader.read(accountId: accountId, principalId: resources.principalId)
                    guard current.logo == row.logo else { continue }
                    let profile = AccountBusinessProfile(accountId: accountId, name: current.name,
                        logo: logo, isStale: true)
                    guard await self.forwardStreamValue(profile, to: continuation) else { break }
                }
                })
                continuation.finish()
            } catch is CancellationError { continuation.finish(throwing: CancellationError()) }
            catch { await self.finishStream(continuation, error: error) }
            await self.streamFinished(id: id)
        }
        streamTasks[id] = task
    }

    func readDownloadedPropertyManagementReport(accountId: AccountID, projectId: ProjectID,
        currency: CurrencyCode, asOf: ProtectedArtifactEpochMilliseconds) async throws -> PropertyManagementReportSnapshot {
        try await withFiniteLease(.readDownloadedPropertyManagementReport) { resources in
            guard accountId == resources.accountId else {
                throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch
            }
            return try await PropertyManagementReportPowerSyncQuery(database: resources.structuredDatabase)
                .readDownloaded(accountId: resources.accountId, principalId: resources.principalId,
                    projectId: projectId, currency: currency, asOf: asOf)
        }
    }

    func readDownloadedClientSummaryPhysicalReport(accountId: AccountID, projectId: ProjectID,
        asOf: ProtectedArtifactEpochMilliseconds) async throws -> ClientSummaryPhysicalReportSnapshot {
        try await withFiniteLease(.readDownloadedClientSummaryPhysicalReport) { resources in
            guard accountId == resources.accountId else {
                throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch
            }
            return try await PropertyManagementReportPowerSyncQuery(database: resources.structuredDatabase)
                .readDownloadedClientSummary(accountId: resources.accountId, principalId: resources.principalId,
                    projectId: projectId, asOf: asOf)
        }
    }

    func startDownloadedItemPlacementsWatch(id: UUID, accountId: AccountID, scope: ItemPlacementScope,
        continuation: AsyncThrowingStream<DownloadedItemPlacements, Error>.Continuation) {
        guard !normalAccessLocked, case .open = state, let resources else {
            continuation.finish(throwing: LedgerOfflineClientRuntimeFailure.runtimeClosed)
            return
        }
        guard !Task.isCancelled, cancelledBeforeStart.remove(id) == nil else {
            continuation.finish(throwing: CancellationError())
            return
        }
        guard accountId == resources.accountId else {
            continuation.finish(throwing: LedgerOfflineClientRuntimeFailure.accountScopeMismatch)
            return
        }
        // Unlike an untracked producer behind an AsyncThrowingStream, this
        // exact task remains in streamTasks until BOTH child tasks and owned
        // subscription cleanup finish. performClose therefore drains it first.
        let task = Task.detached { [resources] in
            do {
                try await resources.streamOperationCheckpoint(.downloadedItemPlacements)
                try Task.checkCancellation()
                try await DownloadedItemPlacementWatch(database: resources.structuredDatabase,
                    subscribe: resources.subscribePhysicalItems).run(
                    accountId: resources.accountId, principalId: resources.principalId, scope: scope
                ) { value in
                    await self.forwardStreamValue(value, to: continuation)
                }
                continuation.finish()
            } catch is CancellationError {
                continuation.finish(throwing: CancellationError())
            } catch {
                await self.finishStream(continuation, error: error)
            }
            await self.streamFinished(id: id)
        }
        streamTasks[id] = task
    }

    func startPropertyManagementReportWatch(id: UUID, accountId: AccountID, projectId: ProjectID,
        currency: CurrencyCode, continuation: AsyncThrowingStream<PropertyManagementReportUpdate, Error>.Continuation) {
        guard !normalAccessLocked, case .open = state, let resources else {
            continuation.finish(throwing: LedgerOfflineClientRuntimeFailure.runtimeClosed)
            return
        }
        guard !Task.isCancelled, cancelledBeforeStart.remove(id) == nil else {
            continuation.finish(throwing: CancellationError())
            return
        }
        guard accountId == resources.accountId else {
            continuation.finish(throwing: LedgerOfflineClientRuntimeFailure.accountScopeMismatch)
            return
        }
        let task = Task.detached { [resources] in
            do {
                try await resources.streamOperationCheckpoint(.propertyManagementReport)
                try Task.checkCancellation()
                try await PropertyManagementReportWatch(database: resources.structuredDatabase).run(
                    accountId: resources.accountId, principalId: resources.principalId,
                    projectId: projectId, currency: currency) { value in
                        await self.forwardStreamValue(value, to: continuation)
                    }
                continuation.finish()
            } catch is CancellationError {
                continuation.finish(throwing: CancellationError())
            } catch {
                await self.finishStream(continuation, error: error)
            }
            await self.streamFinished(id: id)
        }
        streamTasks[id] = task
    }

    func startClientSummaryPhysicalReportWatch(id: UUID, accountId: AccountID, projectId: ProjectID,
        continuation: AsyncThrowingStream<ClientSummaryPhysicalReportUpdate, Error>.Continuation) {
        guard !normalAccessLocked, case .open = state, let resources else {
            continuation.finish(throwing: LedgerOfflineClientRuntimeFailure.runtimeClosed)
            return
        }
        guard !Task.isCancelled, cancelledBeforeStart.remove(id) == nil else {
            continuation.finish(throwing: CancellationError())
            return
        }
        guard accountId == resources.accountId else {
            continuation.finish(throwing: LedgerOfflineClientRuntimeFailure.accountScopeMismatch)
            return
        }
        let task = Task.detached { [resources] in
            do {
                try await resources.streamOperationCheckpoint(.clientSummaryPhysicalReport)
                try Task.checkCancellation()
                try await ClientSummaryPhysicalReportWatch(database: resources.structuredDatabase).run(
                    accountId: resources.accountId, principalId: resources.principalId, projectId: projectId) { value in
                        await self.forwardStreamValue(value, to: continuation)
                    }
                continuation.finish()
            } catch is CancellationError { continuation.finish(throwing: CancellationError()) }
            catch { await self.finishStream(continuation, error: error) }
            await self.streamFinished(id: id)
        }
        streamTasks[id] = task
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

    func resolveLocalAttachmentBytes(
        for receipt: AttachmentLocalDurabilityReceipt
    ) async throws -> Data {
        try await withFiniteLease(.resolveAttachmentBytes) { resources in
            guard receipt.scope.environment == resources.environment,
                  receipt.scope.principalId == resources.principalId else {
                throw AttachmentLocalByteResolutionFailure.scopeMismatch
            }
            guard receipt.scope.accountId == resources.accountId else {
                throw AttachmentLocalByteResolutionFailure.scopeMismatch
            }
            try Task.checkCancellation()
            let bytes = try await resources.attachmentStore
                .resolveLocalAttachmentBytes(for: receipt)
            try Task.checkCancellation()
            return bytes
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

    func startSpaceCoreDetailsWatch(
        id: UUID,
        request: SpaceCoreDetailsRequest,
        continuation: AsyncThrowingStream<SpaceCoreDetailsUpdate, Error>.Continuation
    ) {
        startStream(
            id: id,
            operation: .spaceCoreDetails,
            continuation: continuation,
            validate: { resources in
                guard request.accountId == resources.accountId else {
                    throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch
                }
            },
            makeStream: { resources in
                resources.spaceCoreDetailsQuery.watchSpaceCoreDetails(request)
            }
        )
    }

    func startSpaceDirectoryWatch(
        id: UUID,
        request: SpaceListRequest,
        continuation: AsyncThrowingStream<SpaceListUpdate, Error>.Continuation
    ) {
        startStream(
            id: id,
            operation: .spaceDirectory,
            continuation: continuation,
            validate: { resources in
                guard request.accountId == resources.accountId else {
                    throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch
                }
            },
            makeStream: { resources in
                resources.spaceBrowserQuery.watchSpaces(request)
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

    func startProjectCreationOperationWatch(
        id: UUID,
        operationId: OperationID,
        continuation: AsyncThrowingStream<OperationSnapshot, Error>.Continuation
    ) {
        startStream(
            id: id,
            operation: .projectCreationOperation,
            continuation: continuation,
            validate: { _ in },
            makeStream: { resources in
                resources.projectSetupStore.watchOperation(operationId)
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

    func startSpaceChecklistRevisionOperationWatch(
        id: UUID,
        operationId: OperationID,
        continuation: AsyncThrowingStream<OperationSnapshot, Error>.Continuation
    ) {
        startStream(
            id: id,
            operation: .spaceChecklistRevisionOperation,
            continuation: continuation,
            validate: { _ in },
            makeStream: { resources in
                resources.spaceChecklistRevisionStore.watchOperation(operationId)
            }
        )
    }

    func startRejectedOperationRecoveryWatch(
        id: UUID,
        request: RejectedOperationRecoveryRequest,
        continuation:
            AsyncThrowingStream<RejectedOperationRecoverySnapshot, Error>.Continuation
    ) {
        startStream(
            id: id,
            operation: .rejectedOperationRecovery,
            continuation: continuation,
            validate: { _ in },
            makeStream: { resources in
                resources.spaceChecklistRevisionStore
                    .watchRejectedOperations(request)
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

    func startItemSpaceAssignmentOperationWatch(
        id: UUID,
        operationId: OperationID,
        continuation: AsyncThrowingStream<OperationSnapshot, Error>.Continuation
    ) {
        startStream(
            id: id,
            operation: .itemSpaceAssignmentOperation,
            continuation: continuation,
            validate: { _ in },
            makeStream: { resources in
                resources.itemSpaceAssignmentStore.watchOperation(operationId)
            }
        )
    }

    func startItemSpaceClearingOperationWatch(
        id: UUID,
        operationId: OperationID,
        continuation: AsyncThrowingStream<OperationSnapshot, Error>.Continuation
    ) {
        startStream(
            id: id,
            operation: .itemSpaceClearingOperation,
            continuation: continuation,
            validate: { _ in },
            makeStream: { resources in
                resources.itemSpaceClearingStore.watchOperation(operationId)
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

    func lockAccessPreservingPendingWork() async throws {
        if !accessLocked {
            accessLocked = true
            resources?.lifecycleEvent(.accessLocked)
        }
        try await close()
    }

    /// One upload transaction, bound to this workspace's database and fence.
    /// The authenticated session owner will schedule these; no network session
    /// is created here and no caller receives an unowned database/connector.
    func uploadPendingCommands(using appliers: LedgerPowerSyncCommandAppliers) async throws {
        guard !normalAccessLocked, case .open = state, let resources else {
            throw LedgerOfflineClientRuntimeFailure.runtimeClosed
        }
        try resources.accessFence.beginCommandUpload()
        let connector = LedgerPowerSyncUploadConnector(
            accessFence: resources.accessFence,
            credentialProvider: { nil },
            clientCreationApplier: appliers.clientCreation,
            projectCreationApplier: appliers.projectCreation,
            projectArchiveApplier: appliers.projectArchive,
            clientArchiveApplier: appliers.clientArchive,
            spaceChecklistRevisionApplier: appliers.spaceChecklistRevision,
            now: resources.now
        )
        let task = Task {
            try await connector.uploadData(database: resources.structuredDatabase)
        }
        commandUploadTask = task
        defer {
            commandUploadTask = nil
            resources.accessFence.endCommandUpload()
            resumeDrainWaitersIfDrained()
        }
        do {
            try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            guard !normalAccessLocked else {
                throw LedgerOfflineClientRuntimeFailure.runtimeClosed
            }
        } catch {
            if normalAccessLocked { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            throw error
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
        guard !normalAccessLocked, case .open = state, let resources else {
            throw LedgerOfflineClientRuntimeFailure.runtimeClosed
        }
        finiteLeaseCount += 1
        do {
            try await resources.finiteOperationCheckpoint(operation)
            guard !normalAccessLocked else {
                throw LedgerOfflineClientRuntimeFailure.runtimeClosed
            }
            let value = try await body(resources)
            guard !normalAccessLocked else {
                throw LedgerOfflineClientRuntimeFailure.runtimeClosed
            }
            releaseFiniteLease()
            return value
        } catch {
            releaseFiniteLease()
            if normalAccessLocked { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
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
        guard !normalAccessLocked, case .open = state, let resources else {
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
                    guard await self.forwardStreamValue(value, to: continuation) else { break }
                }
                continuation.finish()
            } catch is CancellationError {
                continuation.finish(throwing: CancellationError())
            } catch {
                await self.finishStream(continuation, error: error)
            }
            await self.streamFinished(id: id)
        }
        streamTasks[id] = task
    }

    private func forwardStreamValue<Value: Sendable>(
        _ value: Value,
        to continuation: AsyncThrowingStream<Value, Error>.Continuation
    ) -> Bool {
        guard !normalAccessLocked, case .open = state else {
            continuation.finish(throwing: LedgerOfflineClientRuntimeFailure.runtimeClosed)
            return false
        }
        if case .terminated = continuation.yield(value) { return false }
        return true
    }

    private func finishStream<Value: Sendable>(
        _ continuation: AsyncThrowingStream<Value, Error>.Continuation,
        error: Error
    ) {
        continuation.finish(throwing: normalAccessLocked
            ? LedgerOfflineClientRuntimeFailure.runtimeClosed : error)
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
        commandUploadTask?.cancel()
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
        await resources.spaceBrowserQuery.cancelAndDrainWatches()
        await resources.transferDestinationQuery.cancelAndDrainWatches()
        await resources.detailsQuery.cancelAndDrainWatches()
        await resources.projectDetailsQuery.cancelAndDrainWatches()
        await resources.directoryQuery.cancelAndDrainWatches()
        await resources.itemSpaceAssignmentStore.cancelAndDrainWatches()
        await resources.itemSpaceClearingStore.cancelAndDrainWatches()
        await resources.projectSetupStore.cancelAndDrainWatches()
        await resources.projectArchiveStore.cancelAndDrainWatches()
        await resources.spaceChecklistRevisionStore.cancelAndDrainWatches()
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
        guard finiteLeaseCount != 0 || !streamTasks.isEmpty || commandUploadTask != nil else { return }
        await withCheckedContinuation { continuation in
            drainWaiters.append(continuation)
        }
    }

    private func resumeDrainWaitersIfDrained() {
        guard finiteLeaseCount == 0, streamTasks.isEmpty, commandUploadTask == nil else { return }
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
        let identity = try LedgerWorkspaceRemovalRegistry.identity(
            environment: validatedEnvironment.manifest.environment,
            principalId: principalId, accountId: accountId
        )
        return try await dependencies.accessCoordinator.open(identity: identity) { fence in
            try await openResources(
                validatedEnvironment: validatedEnvironment, principalId: principalId,
                accountId: accountId, applicationSupportDirectory: applicationSupportDirectory,
                dependencies: dependencies, identity: identity, accessFence: fence
            )
        }
    }

    private static func openResources(
        validatedEnvironment: ValidatedLedgerEnvironment,
        principalId: PrincipalID,
        accountId: AccountID,
        applicationSupportDirectory: URL,
        dependencies: LedgerPowerSyncLocalBootstrapDependencies,
        identity: String,
        accessFence: LedgerWorkspaceAccessFence
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
        var spaceBrowserQuery: (any AccountWorkspaceSpaceListQuerying)?
        var runtimeResources: AccountWorkspaceRuntimeResources?

        do {
            stage = .workspaceAccessCheck
            try dependencies.requireWorkspaceNotRemoved(
                validatedEnvironment.manifest.environment, principalId, accountId
            )
            stage = .workspaceLocationResolution
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

            stage = .spaceBrowserQueryConstruction
            let madeSpaceBrowserQuery = try dependencies.makeSpaceBrowserQuery(
                openedStructured.database,
                principalId,
                accountId,
                dependencies.now
            )
            spaceBrowserQuery = madeSpaceBrowserQuery
            dependencies.lifecycleEvent(.spaceBrowserQueryConstructed)

            let madeProjectSetupStore = dependencies.makeProjectSetupStore(
                openedStructured.database,
                accountId,
                principalId,
                dependencies.now
            )
            let madeProjectArchiveStore = dependencies.makeProjectArchiveStore(
                openedStructured.database,
                accountId,
                principalId,
                dependencies.now
            )
            let madeItemSpaceAssignmentStore = dependencies.makeItemSpaceAssignmentStore(
                openedStructured.database,
                accountId,
                principalId,
                dependencies.now
            )
            let madeItemSpaceClearingStore = dependencies.makeItemSpaceClearingStore(
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
                spaceBrowserQuery: madeSpaceBrowserQuery,
                projectSetupStore: madeProjectSetupStore,
                projectArchiveStore: madeProjectArchiveStore,
                itemSpaceAssignmentStore: madeItemSpaceAssignmentStore,
                itemSpaceClearingStore: madeItemSpaceClearingStore,
                vault: openedVault,
                closeAttachmentDatabase: openedAttachment.closePreservingData,
                closeStructuredDatabase: openedStructured.closePreservingData,
                finiteOperationCheckpoint: dependencies.finiteOperationCheckpoint,
                streamOperationCheckpoint: dependencies.streamOperationCheckpoint,
                lifecycleEvent: dependencies.lifecycleEvent,
                environment: validatedEnvironment.manifest.environment,
                principalId: principalId,
                accountId: accountId,
                now: dependencies.now,
                accessFence: accessFence,
                subscribePhysicalItems: dependencies.subscribePhysicalItems,
                downloadAccountLogo: dependencies.downloadAccountLogo
            )
            runtimeResources = madeRuntimeResources

            stage = .workspaceAccessCheck
            try dependencies.requireWorkspaceNotRemoved(
                validatedEnvironment.manifest.environment, principalId, accountId
            )
            stage = .runtimeConstruction
            let owner = try dependencies.makeLifecycleOwner(madeRuntimeResources)
            dependencies.lifecycleEvent(.lifecycleOwnerConstructed)
            return LedgerOfflineClientRuntime(lifecycleOwner: owner) {
                [coordinator = dependencies.accessCoordinator,
                 record = dependencies.recordWorkspaceRemoval,
                 environment = validatedEnvironment.manifest.environment] in
                try await coordinator.remove(identity: identity) {
                    try record(environment, principalId, accountId)
                }
            }
        } catch {
            let hadDerivedResources =
                runtimeResources != nil
                || spaceAssignmentDestinationQuery != nil
                || projectNoteQuery != nil
                || spaceCoreDetailsQuery != nil
                || spaceBrowserQuery != nil
                || budgetCategoryQuery != nil
                || pendingWorkQuery != nil
                || attachmentStore != nil
            runtimeResources = nil
            spaceAssignmentDestinationQuery = nil
            projectNoteQuery = nil
            spaceCoreDetailsQuery = nil
            spaceBrowserQuery = nil
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
                stage: (error as? LedgerWorkspaceRemovalFailure) == .removed
                    ? .workspaceAccessRemoved : stage,
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
