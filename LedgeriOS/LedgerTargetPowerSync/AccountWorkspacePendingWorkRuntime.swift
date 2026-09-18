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
{
    func enqueue(_ capture: LocalAttachmentCapture,
        authorize: @Sendable @escaping () async throws -> Void) async throws -> AttachmentLocalDurabilityReceipt
    func pendingCaptureReceipts(parent: LedgerEntityReference) async throws -> [AttachmentLocalDurabilityReceipt]
    func pendingTransactionUploads() async throws -> [AttachmentLocalDurabilityReceipt]
    func pendingItemUploads() async throws -> [AttachmentLocalDurabilityReceipt]
    func publishItemAttachment(_ receipt: AttachmentLocalDurabilityReceipt,
        publish: TransactionAttachmentPublisher) async throws -> TransactionAttachmentPublication
    func reconcileItemAttachment(_ receipt: AttachmentLocalDurabilityReceipt,
        catalog: DownloadedItemImageCatalog) async throws -> Bool
    func verifiedExpenseReceipts(for command: CreateExpenseCommand) async throws -> Set<AttachmentID>
    func verifiedExpenseReceipts(for command: EditExpenseCommand) async throws -> Set<AttachmentID>
    func publishExpenseAttachment(_ receipt: AttachmentLocalDurabilityReceipt, projectId: EntityID,
        publish: ExpenseAttachmentPublisher) async throws -> ExpenseAttachmentPublication
    func pendingExpenseReconciliations() async throws -> [(AttachmentLocalDurabilityReceipt, EntityID)]
    func reconcileExpenseAttachment(_ receipt: AttachmentLocalDurabilityReceipt, projectId: EntityID,
        object: DownloadedMediaObjectReference) async throws -> Bool
    func pendingCaptureRejections(parent: LedgerEntityReference) async throws -> [AttachmentID: String]
    func publishTransactionAttachment(_ receipt: AttachmentLocalDurabilityReceipt,
        publish: TransactionAttachmentPublisher) async throws -> TransactionAttachmentPublication
    func reconcileTransactionAttachment(_ receipt: AttachmentLocalDurabilityReceipt,
        catalog: DownloadedTransactionAttachments) async throws -> Bool
}

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
    case readProjectBudget
    case readInvoicingCharges
    case readExpenses
    case readCollectedInvoices
    case readLiveInvoices
    case createInvoice
    case reviseCreatedInvoice
    case createFeeInstallment
    case readPendingFeeCreations
    case createClient
    case createProject
    case archiveProject
    case manageCategories
    case sellInventoryItems
    case editItemPrice
    case editItemDetails
    case editTransactionDetails
    case returnUninvoicedItems
    case returnPaidItems
    case createExpense
    case editExpense
    case reviseSpaceChecklists
    case rejectedOperationRecoverySnapshot
    case archiveClient
    case assignItemsToSpace
    case clearItemSpaceAssignments
    case pendingUploadCount
    case verifyWorkspaceMembership
    case encryptionCipher
    case captureAttachment
    case resolveAttachmentBytes
    case pendingWorkSummary
    case readDownloadedItemPlacements
    case readDownloadedPropertyManagementReport
    case protectedReportDelivery
    case readTransactionExport
    case readTransactionAttachments
    case loadTransactionAttachment
    case readSpaceMedia
    case loadSpaceMedia
    case readDownloadedTransactionReceipt
    case readDownloadedClientSummaryPhysicalReport
    case readAccountBusinessProfile
    case loadDownloadedItemImage
}

enum AccountWorkspaceRuntimeStreamOperation: Equatable, Sendable {
    case spaceMedia
    case invoicingCharges
    case projectBudget
    case expenses
    case downloadedProjectItems
    case accountBusinessProfile
    case itemImages
    case propertyManagementReport
    case transactionReceipt
    case transactionBrowser
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
    case categoryOperations
    case inventorySaleOperation
    case itemPriceEditOperation
    case itemDetailsEditOperation
    case transactionDetailsEditOperation
    case uninvoicedReturnOperation
    case paidReturnOperation
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
    var downloadImage: (@Sendable (DownloadedImageObjectReference) async throws -> Data)? = nil
    var categoryDirectoryIsComplete: @Sendable (any PowerSyncDatabaseProtocol) -> Bool = {
        BudgetCategorySyncCompleteness.isComplete($0.currentStatus)
    }

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
            var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
            #if os(iOS) || os(tvOS) || os(watchOS)
            attributes[.protectionKey] = FileProtectionType.complete
            #endif
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: attributes
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
    case sessionEndingStarted
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
    let categoryManagementStore: CategoryManagementPowerSyncStore
    let inventorySaleStore: InventorySalePowerSyncStore
    let itemPriceEditStore: ItemPriceEditPowerSyncStore
    let itemDetailsEditStore: ItemDetailsEditPowerSyncStore
    let transactionDetailsEditStore: TransactionDetailsEditPowerSyncStore
    let uninvoicedReturnStore: ReturnUninvoicedItemsPowerSyncStore
    let paidReturnStore: ReturnPaidItemsPowerSyncStore
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
    let downloadImage: (@Sendable (DownloadedImageObjectReference) async throws -> Data)?
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
        categoryDirectoryIsComplete: @Sendable @escaping () -> Bool = { false },
        subscribePhysicalItems: (@Sendable (AccountID) async throws -> any SyncStreamSubscription)? = nil,
        downloadImage: (@Sendable (DownloadedImageObjectReference) async throws -> Data)? = nil
    ) {
        self.downloadImage = downloadImage
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
        categoryManagementStore = CategoryManagementPowerSyncStore(
            database: structuredDatabase, accountId: accountId, principalId: principalId,
            accessFence: accessFence, isDirectoryComplete: categoryDirectoryIsComplete, now: now
        )
        inventorySaleStore = InventorySalePowerSyncStore(database: structuredDatabase,
            accountId: accountId, principalId: principalId, accessFence: accessFence, now: now)
        itemPriceEditStore = ItemPriceEditPowerSyncStore(database: structuredDatabase,
            accountId: accountId, principalId: principalId, accessFence: accessFence, now: now)
        itemDetailsEditStore = ItemDetailsEditPowerSyncStore(database: structuredDatabase,
            accountId: accountId, principalId: principalId, accessFence: accessFence, now: now)
        transactionDetailsEditStore = TransactionDetailsEditPowerSyncStore(database: structuredDatabase,
            accountId: accountId, principalId: principalId, accessFence: accessFence, now: now)
        uninvoicedReturnStore = ReturnUninvoicedItemsPowerSyncStore(database: structuredDatabase,
            accountId: accountId, principalId: principalId, accessFence: accessFence, now: now)
        paidReturnStore = ReturnPaidItemsPowerSyncStore(database: structuredDatabase,
            accountId: accountId, principalId: principalId, accessFence: accessFence, now: now)
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
    private var sessionEndValidation: Result<SessionEndEvaluation, any Error>?
    private var accessLocked = false
    private let accessFence: LedgerWorkspaceAccessFence
    private var normalAccessLocked: Bool { accessLocked || accessFence.isRemoved }
    private var resources: AccountWorkspaceRuntimeResources?
    private var downloadImage: (@Sendable (DownloadedImageObjectReference) async throws -> Data)?
    private var finiteLeaseCount = 0
    private var transactionCaptureSections: Set<[String]> = []
    private var capturingItems: Set<ItemID> = []
    private var streamTasks: [UUID: Task<Void, Never>] = [:]
    private var commandUploadTask: Task<Void, Error>?
    private var syncConnectionTask: Task<Void, Error>?
    private var syncStarted = false
    private var membershipWatchID: UUID?
    private var attachmentUploadTaskID: UUID?
    private var attachmentRetryAfter: [String: Date] = [:]
    private var ownsOpenRegistration = false
    private var cancelledBeforeStart: Set<UUID> = []
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []

    init(resources: AccountWorkspaceRuntimeResources) {
        self.resources = resources
        downloadImage = resources.downloadImage
        accessFence = resources.accessFence
    }

    func adoptOpenRegistration() {
        if case .closed = state {
            accessFence.endRuntimeOpen()
        } else {
            ownsOpenRegistration = true
        }
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

    func inventorySaleStatus(_ operationId: OperationID) async throws -> OperationSnapshot? {
        try await withFiniteLease(.sellInventoryItems) { resources in
            try await resources.inventorySaleStore.status(operationId)
        }
    }

    func startItemDetailsEditWatch(id: UUID, operationId: OperationID,
        continuation: AsyncThrowingStream<OperationSnapshot?, Error>.Continuation) {
        startStream(id: id, operation: .itemDetailsEditOperation, continuation: continuation,
            validate: { _ in }, makeStream: { $0.itemDetailsEditStore.watch(operationId) })
    }

    func startTransactionDetailsEditWatch(id: UUID, operationId: OperationID,
        continuation: AsyncThrowingStream<OperationSnapshot?, Error>.Continuation) {
        startStream(id: id, operation: .transactionDetailsEditOperation, continuation: continuation,
            validate: { _ in }, makeStream: { $0.transactionDetailsEditStore.watch(operationId) })
    }

    func transactionDetailsEditStatus(_ operationId: OperationID) async throws -> OperationSnapshot? {
        try await withFiniteLease(.editTransactionDetails) { try await $0.transactionDetailsEditStore.status(operationId) }
    }

    func pendingTransactionReceiptLinesEdit(scope: TransactionScope, transactionId: TransactionID) async throws -> PendingTransactionReceiptLinesEdit? {
        try await withFiniteLease(.editTransactionDetails) {
            try await $0.transactionDetailsEditStore.pendingReceiptLines(scope: scope, transactionId: transactionId)
        }
    }

    func editTransactionReceiptLines(_ payload: EditTransactionReceiptLinesCommand.Payload, operationUUID: UUID,
        capturedAt: Date) async throws -> OperationReceipt {
        try await withFiniteLease(.editTransactionDetails) { resources in
            let command = try EditTransactionReceiptLinesCommand(
                operationId: TransactionReceiptLinesEditOperationIdentity.make(accountId: resources.accountId, uuid: operationUUID),
                actorPrincipalId: resources.principalId, capturedAt: capturedAt, payload: payload)
            return try await resources.transactionDetailsEditStore.submit(command)
        }
    }

    func pendingTransactionDetailsEdit(scope: TransactionScope, transactionId: TransactionID) async throws -> PendingTransactionDetailsEdit? {
        try await withFiniteLease(.editTransactionDetails) {
            try await $0.transactionDetailsEditStore.pending(scope: scope, transactionId: transactionId)
        }
    }

    func editTransactionDetails(_ payload: EditTransactionDetailsCommand.Payload, operationUUID: UUID,
                                capturedAt: Date) async throws -> OperationReceipt {
        try await withFiniteLease(.editTransactionDetails) { resources in
            let command = try EditTransactionDetailsCommand(
                operationId: TransactionDetailsEditOperationIdentity.make(accountId: resources.accountId, uuid: operationUUID),
                actorPrincipalId: resources.principalId, capturedAt: capturedAt, payload: payload)
            return try await resources.transactionDetailsEditStore.submit(command)
        }
    }

    func itemDetailsEditStatus(_ operationId: OperationID) async throws -> OperationSnapshot? {
        try await withFiniteLease(.editItemDetails) { try await $0.itemDetailsEditStore.status(operationId) }
    }

    func editItemDetails(_ payload: EditItemDetailsCommand.Payload, operationUUID: UUID,
                         capturedAt: Date) async throws -> OperationReceipt {
        try await withFiniteLease(.editItemDetails) { resources in
            let command = try EditItemDetailsCommand(
                operationId: ItemDetailsEditOperationIdentity.make(accountId: resources.accountId, uuid: operationUUID),
                accountId: resources.accountId, actorPrincipalId: resources.principalId,
                capturedAt: capturedAt, payload: payload)
            return try await resources.itemDetailsEditStore.submit(command)
        }
    }

    func itemPriceEditStatus(_ operationId: OperationID) async throws -> OperationSnapshot? {
        try await withFiniteLease(.editItemPrice) { try await $0.itemPriceEditStore.status(operationId) }
    }

    func reviewItemPrice(project: ProjectID, item: ItemID, requested: Money) async throws -> EditUncollectedItemPriceCommand.Payload {
        try await withFiniteLease(.editItemPrice) {
            try await $0.itemPriceEditStore.review(project: project, item: item, requested: requested)
        }
    }

    func editItemPrice(_ payload: EditUncollectedItemPriceCommand.Payload, operationUUID: UUID,
                       capturedAt: Date) async throws -> OperationReceipt {
        try await withFiniteLease(.editItemPrice) { resources in
            let command = try EditUncollectedItemPriceCommand(
                operationId: ItemPriceEditOperationIdentity.make(accountId: resources.accountId, uuid: operationUUID),
                accountId: resources.accountId, actorPrincipalId: resources.principalId,
                capturedAt: capturedAt, payload: payload)
            return try await resources.itemPriceEditStore.submit(command)
        }
    }

    func readInventorySaleReview(itemIds: [ItemID]) async throws -> InventorySaleReview {
        try await withFiniteLease(.sellInventoryItems) { resources in
            try await resources.inventorySaleStore.review(itemIds: itemIds)
        }
    }

    func sellInventoryItems(_ payload: InventorySalePayload, operationUUID: UUID,
                            capturedAt: Date) async throws -> OperationReceipt {
        try await withFiniteLease(.sellInventoryItems) { resources in
            let command = try InventorySaleCommand(
                operationId: InventorySaleOperationIdentity.make(accountId: resources.accountId, uuid: operationUUID),
                accountId: resources.accountId, actorPrincipalId: resources.principalId,
                capturedAt: capturedAt, payload: payload)
            return try await resources.inventorySaleStore.submit(command)
        }
    }

    func readPaidReturnReview(projectId: ProjectID, itemIds: [ItemID]) async throws -> PaidReturnReview {
        try await withFiniteLease(.returnPaidItems) { resources in
            try await resources.paidReturnStore.review(projectId: projectId, itemIds: itemIds)
        }
    }

    func paidReturnStatus(_ operationId: OperationID) async throws -> OperationSnapshot? {
        try await withFiniteLease(.returnPaidItems) { resources in
            try await resources.paidReturnStore.status(operationId)
        }
    }

    func returnPaidItems(_ payload: ReturnPaidItemsPayload, operationUUID: UUID,
                         capturedAt: Date) async throws -> OperationReceipt {
        try await withFiniteLease(.returnPaidItems) { resources in
            let command = try ReturnPaidItemsCommand(
                operationId: ReturnPaidItemsOperationIdentity.make(accountId: resources.accountId, uuid: operationUUID),
                accountId: resources.accountId, actorPrincipalId: resources.principalId,
                capturedAt: capturedAt, payload: payload)
            return try await resources.paidReturnStore.submit(command)
        }
    }

    func readUninvoicedReturnReview(projectId: ProjectID, itemIds: [ItemID]) async throws -> UninvoicedReturnReview {
        try await withFiniteLease(.returnUninvoicedItems) { resources in
            try await resources.uninvoicedReturnStore.review(projectId: projectId, itemIds: itemIds)
        }
    }

    func uninvoicedReturnStatus(_ operationId: OperationID) async throws -> OperationSnapshot? {
        try await withFiniteLease(.returnUninvoicedItems) { resources in
            try await resources.uninvoicedReturnStore.status(operationId)
        }
    }

    func returnUninvoicedItems(_ payload: ReturnUninvoicedItemsPayload, operationUUID: UUID,
                              capturedAt: Date) async throws -> OperationReceipt {
        try await withFiniteLease(.returnUninvoicedItems) { resources in
            let command = try ReturnUninvoicedItemsCommand(
                operationId: ReturnUninvoicedItemsOperationIdentity.make(accountId: resources.accountId, uuid: operationUUID),
                accountId: resources.accountId, actorPrincipalId: resources.principalId,
                capturedAt: capturedAt, payload: payload)
            return try await resources.uninvoicedReturnStore.submit(command)
        }
    }

    func expenseAttachmentCaptureScope(projectId: ProjectID, expenseId: ExpenseID) async throws -> AttachmentCaptureScope {
        try await withFiniteLease(.createExpense) { resources in
            try await resources.structuredDatabase.readTransaction { local in
                try ProjectInvoicingItemLocalReader.requireAccess(transaction: local,
                    accountId: resources.accountId, principalId: resources.principalId, projectId: projectId)
                guard let project = try ClientProjectDirectoryPowerSyncQuery.readProject(projectId,
                    account: resources.accountId, principal: resources.principalId, in: local),
                    project.lifecycle == .active, project.client.lifecycle == .active,
                    !resources.accessFence.isRemoved else { throw ExpenseCreationPowerSyncStore.Failure.unavailable }
                return try AttachmentCaptureScope(environment: resources.environment, principalId: resources.principalId,
                    accountId: resources.accountId, parent: .init(kind: .expense, id: .init(validating: expenseId.rawValue)))
            }
        }
    }

    func createExpense(_ draft: BusinessPaidExpenseDraft, operationUUID: UUID, capturedAt: Date, recovery: ExpenseEntryRecovery? = nil) async throws -> OperationReceipt {
        try await withFiniteLease(.createExpense) { resources in
            guard draft.accountId == resources.accountId else { throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch }
            let command = try CreateExpenseCommand(
                operationId: ExpenseCreationOperationIdentity.make(accountId: resources.accountId, uuid: operationUUID),
                actorPrincipalId: resources.principalId, capturedAt: capturedAt, draft: draft)
            let store = ExpenseCreationPowerSyncStore(database: resources.structuredDatabase,
                accountId: resources.accountId, principalId: resources.principalId,
                accessFence: resources.accessFence, now: resources.now)
            let alreadyAccepted = try await resources.structuredDatabase.getOptional(
                sql: "SELECT id FROM spike_local_operations WHERE id=?",
                parameters: [command.envelope.operationId.rawValue]) { try $0.getString(index: 0) } != nil
            if alreadyAccepted {
                // The store rechecks authorization and the exact saved command.
                // Reconciliation may already have retired its pending captures.
                return try await store.submit(command, expectedRecovery: recovery)
            }
            let parent = try LedgerEntityReference(kind: .expense, id: .init(validating: draft.expenseId.rawValue))
            let receipts = try await resources.attachmentStore.pendingCaptureReceipts(parent: parent)
            for id in draft.receiptAttachmentIds {
                guard let receipt = receipts.first(where: { $0.attachmentId == id }) else {
                    throw AttachmentLocalByteResolutionFailure.receiptNotFound
                }
                // Enforce durability at the public command boundary too, not
                // only in the form. Resolving verifies the retained byte identity.
                _ = try await resources.attachmentStore.resolveLocalAttachmentBytes(for: receipt)
            }
            return try await store.submit(command, expectedRecovery: recovery)
        }
    }

    func editExpense(_ entry: BusinessPaidExpenseDraft, expectedRevision: Int64,
                     operationUUID: UUID, capturedAt: Date, recovery: ExpenseEntryRecovery? = nil) async throws -> OperationReceipt {
        try await withFiniteLease(.editExpense) { resources in
            guard entry.accountId == resources.accountId else { throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch }
            let command = try EditExpenseCommand(operationId: AccountBoundOperationIdentity.make(
                family: .expenseEdit, accountId: resources.accountId, uuid: operationUUID),
                actorPrincipalId: resources.principalId, capturedAt: capturedAt,
                expectedRevision: expectedRevision, entry: entry)
            try await resources.structuredDatabase.readTransaction { local in
                try ProjectInvoicingItemLocalReader.requireAccess(transaction: local,
                    accountId: resources.accountId, principalId: resources.principalId, projectId: entry.projectId)
                _ = try PropertyManagementReportPowerSyncQuery.completedStreamCheckpoint(transaction: local,
                    identity: ProjectExpenseStreamIdentity(accountId: resources.accountId, projectId: entry.projectId))
            }
            let accepted = try await resources.structuredDatabase.getOptional(sql: "SELECT id FROM spike_local_operations WHERE id=?",
                parameters: [command.envelope.operationId.rawValue]) { try $0.getString(index: 0) } != nil
            if !accepted {
                let retained = try await resources.structuredDatabase.getAll(
                    sql: "SELECT attachment_id FROM expense_receipt_attachments WHERE account_id=? AND expense_id=? ORDER BY position",
                    parameters: [resources.accountId.rawValue,entry.expenseId.rawValue]) { try $0.getString(index: 0) }
                guard entry.receiptAttachmentIds.map(\.rawValue).starts(with: retained) else {
                    throw ExpenseCreationPowerSyncStore.Failure.unavailable
                }
                let parent = try LedgerEntityReference(kind: .expense, id: .init(validating: entry.expenseId.rawValue))
                let captures = try await resources.attachmentStore.pendingCaptureReceipts(parent: parent)
                for id in entry.receiptAttachmentIds.dropFirst(retained.count) {
                    guard let capture = captures.first(where: { $0.attachmentId == id }) else {
                        throw AttachmentLocalByteResolutionFailure.receiptNotFound
                    }
                    _ = try await resources.attachmentStore.resolveLocalAttachmentBytes(for: capture)
                }
            }
            return try await ExpenseCreationPowerSyncStore(database: resources.structuredDatabase,
                accountId: resources.accountId, principalId: resources.principalId,
                accessFence: resources.accessFence, now: resources.now).submit(command, expectedRecovery: recovery)
        }
    }

    func saveExpenseEntry(_ entry: ExpenseEntryRecovery, replacing previous: ExpenseEntryRecovery?) async throws {
        try await withFiniteLease(.createExpense) { resources in
            guard entry.accountId == resources.accountId else { throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch }
            let json = String(decoding: try OperationContractCodec.encode(entry), as: UTF8.self)
            let expectedJSON = try previous.map { String(decoding: try OperationContractCodec.encode($0), as: UTF8.self) }
            try await resources.structuredDatabase.writeTransaction { local in
                try ProjectInvoicingItemLocalReader.requireAccess(transaction: local, accountId: resources.accountId,
                    principalId: resources.principalId, projectId: entry.projectId)
                guard !resources.accessFence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
                if let edit = entry.editContext {
                    let operation = try AccountBoundOperationIdentity.make(family: .expenseEdit,
                        accountId: resources.accountId, uuid: entry.operationUUID)
                    let accepted = try local.getOptional(sql: "SELECT id FROM spike_local_operations WHERE id=?",
                        parameters: [operation.rawValue]) { try $0.getString(index: 0) }
                    guard accepted == nil else { throw ExpenseEntryRecoveryFailure.staleEntry }
                    let eligible = try local.get(sql: """
                        SELECT count(*) FROM expenses e WHERE account_id=? AND project_id=? AND id=? AND revision=?
                          AND NOT EXISTS(SELECT 1 FROM collected_invoice_lines l WHERE l.account_id=e.account_id
                            AND l.source_kind='expense' AND l.source_id=e.id)
                        """, parameters: [resources.accountId.rawValue,entry.projectId.rawValue,entry.expenseId.rawValue,
                            String(edit.expectedRevision)]) { try $0.getInt(index: 0) }
                    let retained = try local.getAll(sql: "SELECT attachment_id FROM expense_receipt_attachments WHERE account_id=? AND expense_id=? ORDER BY position",
                        parameters: [resources.accountId.rawValue,entry.expenseId.rawValue]) { try $0.getString(index: 0) }
                    guard eligible == 1, retained == edit.retainedAttachmentIds.map(\.rawValue),
                          Set(entry.attachmentIds).isDisjoint(with: edit.retainedAttachmentIds) else {
                        throw ExpenseEntryRecoveryFailure.staleEntry
                    }
                } else {
                    let accepted = try local.get(sql: "SELECT count(*) FROM spike_local_operations WHERE account_id=? AND command_type='create_expense' AND subject_id=?",
                        parameters: [resources.accountId.rawValue, entry.expenseId.rawValue]) { try $0.getInt(index: 0) }
                    guard accepted == 0 else { throw ExpenseCreationPowerSyncStore.Failure.duplicateExpense }
                }
                let owner = try local.getOptional(sql: "SELECT account_id,actor_principal_id,project_id FROM spike_expense_entry_recovery WHERE id=?",
                    parameters: [entry.expenseId.rawValue]) { c in
                        try [c.getString(index: 0), c.getString(index: 1), c.getString(index: 2)]
                    }
                if let owner {
                    guard owner == [resources.accountId.rawValue, resources.principalId.rawValue, entry.projectId.rawValue] else {
                        throw ProjectExpenses.Failure.invalidEvidence
                    }
                    let current = try local.get(sql: "SELECT entry_json FROM spike_expense_entry_recovery WHERE id=?",
                        parameters: [entry.expenseId.rawValue]) { try $0.getString(index: 0) }
                    var consumedPrevious = false
                    if entry.editContext != nil, previous == nil, current != json {
                        let old = try OperationContractCodec.decode(ExpenseEntryRecovery.self, from: Data(current.utf8))
                        let oldOperation = try AccountBoundOperationIdentity.make(
                            family: old.editContext == nil ? .expenseCreation : .expenseEdit,
                            accountId: resources.accountId, uuid: old.operationUUID)
                        consumedPrevious = try local.getOptional(sql: "SELECT id FROM spike_local_operations WHERE id=?",
                            parameters: [oldOperation.rawValue]) { try $0.getString(index: 0) } != nil
                    }
                    guard current == json || current == expectedJSON || consumedPrevious else { throw ExpenseEntryRecoveryFailure.staleEntry }
                    try local.execute(sql: "UPDATE spike_expense_entry_recovery SET entry_json=? WHERE id=?",
                        parameters: [json, entry.expenseId.rawValue])
                } else {
                    guard previous == nil else { throw ExpenseEntryRecoveryFailure.staleEntry }
                    try local.execute(sql: """
                        INSERT INTO spike_expense_entry_recovery(id,account_id,actor_principal_id,project_id,entry_json)
                        VALUES (?,?,?,?,?)
                        """, parameters: [entry.expenseId.rawValue, resources.accountId.rawValue,
                            resources.principalId.rawValue, entry.projectId.rawValue, json])
                }
                let retained = try local.get(sql: "SELECT entry_json FROM spike_expense_entry_recovery WHERE id=?",
                    parameters: [entry.expenseId.rawValue]) { try $0.getString(index: 0) }
                guard retained == json, !resources.accessFence.isRemoved else { throw ProjectExpenses.Failure.invalidEvidence }
            }
        }
    }

    func restoreExpenseEntryCaptures(_ entry: ExpenseEntryRecovery) async throws -> [LocalAttachmentCapture] {
        try await withFiniteLease(.resolveAttachmentBytes) { resources in
            let query = ProjectExpensePowerSyncQuery(database: resources.structuredDatabase)
            let snapshot = try await query.read(accountId: resources.accountId, principalId: resources.principalId, projectId: entry.projectId)
            guard snapshot.unfinishedEntries.contains(entry) || snapshot.unfinishedEdits.contains(entry) else { throw ProjectExpenses.Failure.invalidEvidence }
            let parent = try LedgerEntityReference(kind: .expense, id: .init(validating: entry.expenseId.rawValue))
            let receipts = try await resources.attachmentStore.pendingCaptureReceipts(parent: parent)
            var captures: [LocalAttachmentCapture] = []
            for id in entry.attachmentIds {
                guard let receipt = receipts.first(where: { $0.attachmentId == id }) else {
                    throw AttachmentLocalByteResolutionFailure.receiptNotFound
                }
                let bytes = try await resources.attachmentStore.resolveLocalAttachmentBytes(for: receipt)
                captures.append(try .init(attachmentId: id, scope: receipt.scope, capturedAt: receipt.capturedAt,
                    bytes: bytes, metadata: receipt.metadata))
            }
            let current = try await query.read(accountId: resources.accountId, principalId: resources.principalId, projectId: entry.projectId)
            guard (current.unfinishedEntries.contains(entry) || current.unfinishedEdits.contains(entry)),
                  !resources.accessFence.isRemoved else { throw ProjectExpenses.Failure.invalidEvidence }
            return captures
        }
    }

    func manageCategories(_ command: CategoryManagementCommand) async throws -> OperationReceipt {
        try await withFiniteLease(.manageCategories) { resources in
            guard command.envelope.accountId == resources.accountId else {
                throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch
            }
            guard command.envelope.actorPrincipalId == resources.principalId else {
                throw LedgerOfflineClientRuntimeFailure.principalScopeMismatch
            }
            return try await resources.categoryManagementStore.submit(command)
        }
    }

    func manageCategories(_ payload: CategoryManagementPayload, operationUUID: UUID,
                          capturedAt: Date) async throws -> OperationReceipt {
        try await withFiniteLease(.manageCategories) { resources in
            let command = try CategoryManagementCommand(
                operationId: CategoryManagementOperationIdentity.make(
                    accountId: resources.accountId, uuid: operationUUID),
                accountId: resources.accountId, actorPrincipalId: resources.principalId,
                capturedAt: capturedAt, payload: payload)
            return try await resources.categoryManagementStore.submit(command)
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

    func requireWorkspaceScope(_ authorization: WorkspaceMembershipAuthorization) throws {
        try requireOpenForSync()
        guard let resources else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
        guard authorization.environment == resources.environment,
              authorization.accountId == resources.accountId,
              authorization.principalId == resources.principalId else {
            throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch
        }
    }

    func bindMediaDownload(_ authorization: WorkspaceMembershipAuthorization,
        download: @escaping @Sendable (DownloadedImageObjectReference) async throws -> Data) throws {
        try requireWorkspaceScope(authorization)
        downloadImage = download
    }

    func startMembershipRevalidation(_ authorization: WorkspaceMembershipAuthorization,
        check: @escaping @Sendable () async throws -> Void) throws {
        try requireWorkspaceScope(authorization)
        guard membershipWatchID == nil, let resources else { return }
        let id = UUID()
        let observations = try resources.structuredDatabase.watch(sql: """
            SELECT state, role, financial_access FROM spike_account_memberships
            WHERE account_id = ? AND principal_id = ?
            """, parameters: [resources.accountId.rawValue, resources.principalId.rawValue],
            mapper: { try $0.getString(name: "state") })
        membershipWatchID = id
        streamTasks[id] = Task { [weak self] in
            do {
                for try await _ in observations {
                    try Task.checkCancellation()
                    // Missing local rows are not proof of revocation. Only the
                    // authenticated server response may trigger removal cleanup.
                    do { try await check() }
                    catch is CancellationError { throw CancellationError() }
                    catch { /* Offline/expired sessions retain downloaded access. */ }
                    if resources.accessFence.isRemoved { break }
                }
            } catch { /* Runtime cancellation closes this observation. */ }
            await self?.membershipRevalidationFinished(id)
        }
    }

    private func membershipRevalidationFinished(_ id: UUID) {
        if membershipWatchID == id { membershipWatchID = nil }
        streamFinished(id: id)
    }

    func requireMatchingDownloadedMembership(_ authorization: WorkspaceMembershipAuthorization) async throws {
        try await withFiniteLease(.verifyWorkspaceMembership) { resources in
            guard authorization.environment == resources.environment,
                  authorization.accountId == resources.accountId,
                  authorization.principalId == resources.principalId else {
                throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch
            }
            let matches = try await resources.structuredDatabase.getOptional(sql: """
                SELECT state = 'active' AND role = ? AND financial_access = ? AS matches
                FROM spike_account_memberships WHERE account_id = ? AND principal_id = ?
                """, parameters: [authorization.role.rawValue, authorization.financialAccess.rawValue,
                    resources.accountId.rawValue, resources.principalId.rawValue]) {
                        try $0.getInt64(name: "matches") == 1
                    }
            guard matches == true else { throw LedgerOfflineClientRuntimeFailure.workspaceMembershipNotReady }
        }
    }

    func readDownloadedItemPlacements(accountId: AccountID, scope: ItemPlacementScope) async throws -> DownloadedItemPlacements {
        try await withFiniteLease(.readDownloadedItemPlacements) { resources in
            guard accountId == resources.accountId else {
                throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch
            }
            return try await CurrentItemPlacementLocalReader(database: resources.structuredDatabase)
                .readSnapshot(accountId: resources.accountId, principalId: resources.principalId, scope: scope)
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
                // Reuse the Item browser's authorized physical working set so
                // Transaction→Item navigation does not require visiting Items first.
                try await DownloadedItemPlacementWatch(database: resources.structuredDatabase)
                    .runHistory(accountId: accountId, principalId: resources.principalId, itemId: itemId) { value in
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

    func startDownloadedItemImagesWatch(id: UUID, accountId: AccountID, itemId: ItemID,
        continuation: AsyncThrowingStream<DownloadedItemImageCatalog, Error>.Continuation) {
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
                try await resources.streamOperationCheckpoint(.itemImages)
                try Task.checkCancellation()
                let reader = ItemImageCatalogLocalReader(database: resources.structuredDatabase)
                try await withOwnedSyncStreamWatch(subscribe: {
                    try await resources.structuredDatabase.syncStream(name: "item_images",
                        params: ["account_id": .string(accountId.rawValue), "item_id": .string(itemId.rawValue)]).subscribe()
                }, observe: {
                    try await reader.run(accountId: accountId, principalId: resources.principalId, itemId: itemId,
                                         attachmentDatabase: resources.attachmentDatabase) { value in
                        do {
                            let scope = try AttachmentCaptureScope(environment: resources.environment,
                                principalId: resources.principalId, accountId: accountId,
                                parent: .init(kind: .item, id: .init(validating: itemId.rawValue)))
                            let receipts = try await resources.attachmentStore.pendingCaptureReceipts(parent: scope.parent)
                            let rejections = try await resources.attachmentStore.pendingCaptureRejections(parent: scope.parent)
                            let combined = try value.includingPending(receipts, scope: scope, rejections: rejections)
                            return await self.forwardStreamValue(combined, to: continuation)
                        } catch {
                            await self.finishStream(continuation, error: error)
                            return false
                        }
                    }
                })
                continuation.finish()
            } catch is CancellationError { continuation.finish(throwing: CancellationError()) }
            catch { await self.finishStream(continuation, error: error) }
            await self.streamFinished(id: id)
        }
        streamTasks[id] = task
    }

    func loadDownloadedItemImage(accountId: AccountID, itemId: ItemID,
        image: DownloadedItemImage, allowDownload: Bool, thumbnail: Bool = false) async throws -> Data? {
        let download = allowDownload ? downloadImage : nil
        return try await withFiniteLease(.loadDownloadedItemImage) { resources in
            guard accountId.rawValue.utf8.elementsEqual(resources.accountId.rawValue.utf8),
                  image.itemId.rawValue.utf8.elementsEqual(itemId.rawValue.utf8),
                  image.object.accountId.rawValue.utf8.elementsEqual(accountId.rawValue.utf8) else {
                throw DownloadedItemImageFailure.scopeMismatch
            }
            let reader = ItemImageCatalogLocalReader(database: resources.structuredDatabase)
            let object = thumbnail ? image.thumbnail?.object : image.object
            @Sendable func authorize() async throws {
                try Task.checkCancellation()
                guard !resources.accessFence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
                let downloaded = try await reader.read(accountId: accountId, principalId: resources.principalId, itemId: itemId)
                let scope = try AttachmentCaptureScope(environment: resources.environment,
                    principalId: resources.principalId, accountId: accountId,
                    parent: .init(kind: .item, id: .init(validating: itemId.rawValue)))
                let pending = try await resources.attachmentStore.pendingCaptureReceipts(parent: scope.parent)
                let current = try downloaded.includingPending(pending, scope: scope)
                guard current.images.contains(image) else { throw DownloadedItemImageFailure.unavailable }
                if thumbnail, !current.isComplete { throw DownloadedItemImageFailure.unavailable }
                guard !resources.accessFence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            }
            guard let object else { try await authorize(); return nil }
            if let receipt = image.localReceipt {
                try await authorize()
                let bytes = try await resources.attachmentStore.resolveLocalAttachmentBytes(for: receipt)
                try await authorize()
                return bytes
            }
            guard let cache = resources.attachmentStore as? any DownloadedImageCaching else {
                throw DownloadedItemImageFailure.unavailable
            }
            return try await loadAuthorizedDownloadedMedia(object, cache: cache,
                download: download, authorize: authorize)
        }
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
        let downloadImage = self.downloadImage
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
                var receivedMembership = false
                for try await rows in try reader.watch(accountId: accountId, principalId: resources.principalId) {
                    try Task.checkCancellation()
                    if rows.isEmpty {
                        guard !receivedProfile else { throw AccountBusinessProfileReadFailure.unavailable }
                        let memberships = try await resources.structuredDatabase.getAll(sql: """
                            SELECT id FROM spike_account_memberships
                            WHERE account_id = ? AND principal_id = ? AND state = 'active'
                            """, parameters: [accountId.rawValue, resources.principalId.rawValue],
                            mapper: { try $0.getString(name: "id") })
                        if memberships.isEmpty {
                            guard !receivedMembership else { throw AccountBusinessProfileReadFailure.unavailable }
                            // A newly authorized workspace can start observing before
                            // bootstrap membership arrives. Do not mistake that for
                            // learned removal; the scoped query yields no profile until
                            // active membership is present. Runtime revocation still
                            // closes this watch through the normal access fence.
                        } else { receivedMembership = true }
                        // Keep the selected subscription alive for its first download.
                        // Missing profile evidence is not an explicit absent logo.
                        continue
                    }
                    guard rows.count == 1 else { throw AccountBusinessProfileReadFailure.unavailable }
                    receivedProfile = true
                    receivedMembership = true
                    let row = rows[0]
                    var logo: AccountBusinessProfile.Logo = .absent
                    if let reference = row.logo {
                        logo = .notDownloaded
                        do {
                            if let bytes = try await cache?.cachedAccountLogo(reference) { logo = .downloaded(bytes) }
                        } catch is CancellationError { throw CancellationError() }
                        catch { logo = .unavailable }
                            if case .downloaded = logo {} else if let download = downloadImage, let cache {
                            let current = try await reader.read(accountId: accountId, principalId: resources.principalId)
                            guard current.logo == reference else { continue }
                            // Render honest saved metadata while retrieval is in progress.
                            guard await self.forwardStreamValue(AccountBusinessProfile(accountId: accountId,
                                name: current.name, logo: logo, isStale: true), to: continuation) else { break }
                            do {
                                let bytes = try await download(reference.downloadedImageReference)
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

    func readDownloadedTransactionReceipt(scope: TransactionScope, transactionId: TransactionID) async throws
        -> TransactionReceiptSnapshot {
        try await withFiniteLease(.readDownloadedTransactionReceipt) { resources in
            guard scope.accountId == resources.accountId else {
                throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch
            }
            return try await TransactionReceiptPowerSyncQuery(database: resources.structuredDatabase,
                principalId: resources.principalId, scope: scope).read(transactionId: transactionId)
        }
    }

    func readDownloadedSpaceMedia(accountId: AccountID, spaceId: SpaceID, scope: SpaceCreationScope) async throws -> DownloadedSpaceMedia {
        try await withFiniteLease(.readSpaceMedia) { resources in
            guard accountId == resources.accountId else { throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch }
            let value = try await SpaceMediaLocalReader(database: resources.structuredDatabase,
                principalId: resources.principalId,accountId: accountId,spaceId: spaceId,scope: scope).read()
            guard !resources.accessFence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            return value
        }
    }

    func loadDownloadedSpaceMedia(catalog: DownloadedSpaceMedia, attachment: DownloadedSpaceMedia.Attachment,
                                 allowDownload: Bool) async throws -> Data? {
        let download = allowDownload ? downloadImage : nil
        return try await withFiniteLease(.loadSpaceMedia) { resources in
            guard catalog.accountId == resources.accountId else { throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch }
            guard let cache = resources.attachmentStore as? any DownloadedImageCaching else {
                throw DownloadedSpaceMedia.Failure.unavailable
            }
            return try await SpaceMediaLocalReader(database: resources.structuredDatabase,
                principalId: resources.principalId,accountId: catalog.accountId,spaceId: catalog.spaceId,scope: catalog.scope)
                .load(catalog: catalog,attachment: attachment,cache: cache,download: download,authorizeAccess: {
                    guard !resources.accessFence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
                })
        }
    }

    func readDownloadedTransactionAttachments(scope: TransactionScope, transactionId: TransactionID,
        section: TransactionAttachmentSection) async throws -> DownloadedTransactionAttachments {
        try await withFiniteLease(.readTransactionAttachments) { resources in
            guard scope.accountId.rawValue.utf8.elementsEqual(resources.accountId.rawValue.utf8) else {
                throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch
            }
            let result = try await TransactionAttachmentLocalReader(database: resources.structuredDatabase,
                principalId: resources.principalId, scope: scope, pendingStore: resources.attachmentStore,
                attachmentDatabase: resources.attachmentDatabase).read(transactionId: transactionId, section: section)
            guard !resources.accessFence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            return result
        }
    }

    func loadDownloadedTransactionAttachment(catalog: DownloadedTransactionAttachments,
        attachment: DownloadedTransactionAttachment, allowDownload: Bool) async throws -> Data? {
        let download = allowDownload ? downloadImage : nil
        return try await withFiniteLease(.loadTransactionAttachment) { resources in
            guard catalog.scope.accountId.rawValue.utf8.elementsEqual(resources.accountId.rawValue.utf8) else {
                throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch
            }
            guard let cache = resources.attachmentStore as? any DownloadedImageCaching else {
                throw DownloadedTransactionAttachments.Failure.unavailable
            }
            return try await TransactionAttachmentLocalReader(database: resources.structuredDatabase,
                principalId: resources.principalId, scope: catalog.scope, pendingStore: resources.attachmentStore,
                attachmentDatabase: resources.attachmentDatabase).load(catalog: catalog,
                    attachment: attachment, cache: cache, download: download,
                    authorizeAccess: {
                        guard !resources.accessFence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
                    })
        }
    }

    func loadExpenseReceipt(projectId: ProjectID, expenseId: ExpenseID, attachmentId: AttachmentID,
                            allowDownload: Bool) async throws -> Data? {
        let download = allowDownload ? downloadImage : nil
        return try await withFiniteLease(.resolveAttachmentBytes) { resources in
            guard let cache = resources.attachmentStore as? any DownloadedImageCaching else {
                throw ProjectExpenses.Failure.invalidEvidence
            }
            let query = ProjectExpensePowerSyncQuery(database: resources.structuredDatabase)
            let expense = try EntityID(validating: expenseId.rawValue)
            let reference = try await query.receiptObject(accountId: resources.accountId,
                principalId: resources.principalId, projectId: projectId, expenseId: expense, attachmentId: attachmentId)
            if reference == nil {
                let snapshot = try await query.read(accountId: resources.accountId,
                    principalId: resources.principalId, projectId: projectId)
                guard let pending = snapshot.pendingCreations.first(where: {
                    $0.entry.expenseId == expenseId && $0.entry.receiptAttachmentIds.contains(attachmentId)
                }) else { throw ProjectExpenses.Failure.invalidEvidence }
                let parent = try LedgerEntityReference(kind: .expense, id: expense)
                let receipts = try await resources.attachmentStore.pendingCaptureReceipts(parent: parent)
                guard let receipt = receipts.first(where: { $0.attachmentId == attachmentId }),
                      receipt.scope.environment == resources.environment,
                      receipt.scope.accountId == resources.accountId,
                      receipt.scope.principalId == resources.principalId,
                      !resources.accessFence.isRemoved else { throw ProjectExpenses.Failure.invalidEvidence }
                let bytes = try await resources.attachmentStore.resolveLocalAttachmentBytes(for: receipt)
                try Task.checkCancellation()
                let current = try await query.read(accountId: resources.accountId,
                    principalId: resources.principalId, projectId: projectId)
                guard current.pendingCreations.contains(pending), !resources.accessFence.isRemoved else {
                    throw ProjectExpenses.Failure.invalidEvidence
                }
                return bytes
            }
            guard let reference else { throw ProjectExpenses.Failure.invalidEvidence }
            return try await loadAuthorizedDownloadedMedia(reference, cache: cache, download: download) {
                try Task.checkCancellation()
                guard !resources.accessFence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
                let current = try await query.receiptObject(accountId: resources.accountId,
                    principalId: resources.principalId, projectId: projectId, expenseId: expense, attachmentId: attachmentId)
                guard current == reference, !resources.accessFence.isRemoved else { throw ProjectExpenses.Failure.invalidEvidence }
            }
        }
    }

    func readTransactionExport(scope: TransactionScope, orderedTransactionIDs: [TransactionID]?,
                               asOf: ProtectedArtifactEpochMilliseconds) async throws -> TransactionExportSnapshot {
        try await withFiniteLease(.readTransactionExport) { resources in
            guard scope.accountId == resources.accountId else {
                throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch
            }
            return try await TransactionDetailPowerSyncQuery(database: resources.structuredDatabase,
                principalId: resources.principalId, scope: scope).readTransactionExport(scope: scope,
                    orderedTransactionIDs: orderedTransactionIDs, asOf: asOf)
        }
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

    func readInvoicingCharges(accountId: AccountID, projectId: ProjectID) async throws -> ProjectInvoicingItems {
        try await withFiniteLease(.readInvoicingCharges) { resources in
            guard accountId == resources.accountId else { throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch }
            return try await ProjectInvoicingChargePowerSyncQuery(database: resources.structuredDatabase)
                .read(accountId: accountId, principalId: resources.principalId, projectId: projectId)
        }
    }

    func readProjectBudget(accountId: AccountID, projectId: ProjectID, currency: CurrencyCode) async throws -> ProjectBudgetRead {
        try await withFiniteLease(.readProjectBudget) { resources in
            guard accountId == resources.accountId else { throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch }
            return try await ProjectBudgetPowerSyncQuery(database: resources.structuredDatabase)
                .readImplementedSources(accountId: accountId, principalId: resources.principalId, projectId: projectId, currency: currency)
        }
    }

    func readExpenses(accountId: AccountID, projectId: ProjectID) async throws -> ProjectExpenses {
        try await withFiniteLease(.readExpenses) { resources in
            guard accountId == resources.accountId else { throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch }
            return try await ProjectExpensePowerSyncQuery(database: resources.structuredDatabase)
                .read(accountId: accountId, principalId: resources.principalId, projectId: projectId)
        }
    }

    func readCollectedInvoiceReport(accountId: AccountID, projectId: ProjectID, invoiceId: InvoiceID,
        asOf: ProtectedArtifactEpochMilliseconds) async throws -> CollectedInvoiceReportSnapshot {
        try await withFiniteLease(.readCollectedInvoices) { resources in
            guard accountId == resources.accountId else { throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch }
            return try await ProjectExpensePowerSyncQuery(database: resources.structuredDatabase)
                .readCollectedInvoiceReport(accountId: accountId, principalId: resources.principalId,
                    projectId: projectId, invoiceId: invoiceId, asOf: asOf)
        }
    }

    func readFeeCreationCategories(accountId: AccountID, projectId: ProjectID) async throws -> [FeeCreationCategory] {
        try await withFiniteLease(.readPendingFeeCreations) { resources in
            guard accountId == resources.accountId else { throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch }
            return try await FeeCreationPowerSyncStore(database: resources.structuredDatabase, accountId: resources.accountId,
                principalId: resources.principalId, accessFence: resources.accessFence).readCreationCategories(projectId: projectId)
        }
    }

    func readFeeBrowsingReview(accountId: AccountID, projectId: ProjectID) async throws -> FeeBrowsingReview {
        try await withFiniteLease(.readLiveInvoices) { resources in
            guard accountId == resources.accountId else { throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch }
            return try await LiveInvoicePowerSyncQuery(database: resources.structuredDatabase)
                .readFeeBrowsingReview(accountId: accountId, principalId: resources.principalId, projectId: projectId)
        }
    }

    func readPendingFeeCreations(accountId: AccountID, projectId: ProjectID) async throws -> [PendingFeeCreation] {
        try await withFiniteLease(.readPendingFeeCreations) { resources in
            guard accountId == resources.accountId else { throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch }
            return try await FeeCreationPowerSyncStore(database: resources.structuredDatabase, accountId: resources.accountId,
                principalId: resources.principalId, accessFence: resources.accessFence).readPending(projectId: projectId)
        }
    }

    func createFeeInstallment(_ draft: FeeInstallmentDraft, operationUUID: UUID, capturedAt: Date) async throws -> OperationReceipt {
        try await withFiniteLease(.createFeeInstallment) { resources in
            guard draft.accountId == resources.accountId else { throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch }
            let command = try CreateFeeInstallmentCommand(operationId: FeeCreationOperationIdentity.make(accountId: resources.accountId, uuid: operationUUID),
                actorPrincipalId: resources.principalId, capturedAt: capturedAt, draft: draft)
            return try await FeeCreationPowerSyncStore(database: resources.structuredDatabase, accountId: resources.accountId,
                principalId: resources.principalId, accessFence: resources.accessFence, now: resources.now).submit(command)
        }
    }

    func createInvoice(_ payload: CreateInvoiceCommand.Payload, operationUUID: UUID, capturedAt: Date) async throws -> OperationReceipt {
        try await withFiniteLease(.createInvoice) { resources in
            guard payload.selection.scope.accountId == resources.accountId else { throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch }
            let command = try CreateInvoiceCommand(operationId: InvoiceCreationOperationIdentity.make(accountId: resources.accountId, uuid: operationUUID),
                actorPrincipalId: resources.principalId, capturedAt: capturedAt, payload: payload)
            return try await InvoiceCreationPowerSyncStore(database: resources.structuredDatabase, accountId: resources.accountId,
                principalId: resources.principalId, accessFence: resources.accessFence, now: resources.now).submit(command)
        }
    }

    func reviseCreatedInvoice(_ payload: ReviseCreatedInvoiceCommand.Payload, operationUUID: UUID, capturedAt: Date) async throws -> OperationReceipt {
        try await withFiniteLease(.reviseCreatedInvoice) { resources in
            guard payload.invoice.selection.scope.accountId == resources.accountId else { throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch }
            let command = try ReviseCreatedInvoiceCommand(operationId: InvoiceRevisionOperationIdentity.make(accountId: resources.accountId, uuid: operationUUID),
                actorPrincipalId: resources.principalId, capturedAt: capturedAt, payload: payload)
            return try await InvoiceCreationPowerSyncStore(database: resources.structuredDatabase, accountId: resources.accountId,
                principalId: resources.principalId, accessFence: resources.accessFence, now: resources.now).submit(command)
        }
    }

    func readPendingInvoiceRevisions(accountId: AccountID, projectId: ProjectID) async throws -> [PendingInvoiceRevision] {
        try await withFiniteLease(.readLiveInvoices) { resources in
            guard accountId == resources.accountId else { throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch }
            return try await LiveInvoicePowerSyncQuery(database: resources.structuredDatabase)
                .readPendingRevisions(accountId: accountId, principalId: resources.principalId, projectId: projectId)
        }
    }

    func readLiveInvoices(accountId: AccountID, projectId: ProjectID) async throws -> [LiveInvoiceContents] {
        try await withFiniteLease(.readLiveInvoices) { resources in
            guard accountId == resources.accountId else { throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch }
            return try await LiveInvoicePowerSyncQuery(database: resources.structuredDatabase)
                .read(accountId: accountId, principalId: resources.principalId, projectId: projectId)
        }
    }

    func readPendingInvoiceCreations(accountId: AccountID, projectId: ProjectID) async throws -> [PendingInvoiceCreation] {
        try await withFiniteLease(.readLiveInvoices) { resources in
            guard accountId == resources.accountId else { throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch }
            return try await LiveInvoicePowerSyncQuery(database: resources.structuredDatabase)
                .readPendingCreations(accountId: accountId, principalId: resources.principalId, projectId: projectId)
        }
    }

    func readInvoiceCreationReview(accountId: AccountID, projectId: ProjectID) async throws -> InvoiceCreationReview {
        try await withFiniteLease(.readLiveInvoices) { resources in
            guard accountId == resources.accountId else { throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch }
            return try await LiveInvoicePowerSyncQuery(database: resources.structuredDatabase)
                .readCreationReview(accountId: accountId, principalId: resources.principalId, projectId: projectId)
        }
    }

    func startLiveInvoiceWatch(id: UUID, accountId: AccountID, projectId: ProjectID,
        continuation: AsyncThrowingStream<[LiveInvoiceContents]?, Error>.Continuation) {
        guard !normalAccessLocked, case .open = state, let resources else {
            continuation.finish(throwing: LedgerOfflineClientRuntimeFailure.runtimeClosed); return
        }
        guard !Task.isCancelled, cancelledBeforeStart.remove(id) == nil else {
            continuation.finish(throwing: CancellationError()); return
        }
        guard accountId == resources.accountId else {
            continuation.finish(throwing: LedgerOfflineClientRuntimeFailure.accountScopeMismatch); return
        }
        let task = Task.detached { [resources] in
            do {
                try await resources.streamOperationCheckpoint(.expenses)
                try Task.checkCancellation()
                try await LiveInvoicePowerSyncQuery(database: resources.structuredDatabase).run(
                    accountId: accountId, principalId: resources.principalId, projectId: projectId) { value in
                        await self.forwardStreamValue(value, to: continuation)
                    }
                continuation.finish()
            } catch is CancellationError { continuation.finish(throwing: CancellationError()) }
            catch { await self.finishStream(continuation, error: error) }
            await self.streamFinished(id: id)
        }
        streamTasks[id] = task
    }

    func readCollectedInvoices(accountId: AccountID, projectId: ProjectID) async throws -> [FrozenInvoiceContents] {
        try await withFiniteLease(.readCollectedInvoices) { resources in
            guard accountId == resources.accountId else { throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch }
            return try await ProjectExpensePowerSyncQuery(database: resources.structuredDatabase)
                .readCollectedInvoices(accountId: accountId, principalId: resources.principalId, projectId: projectId)
        }
    }

    func startCollectedInvoiceWatch(id: UUID, accountId: AccountID, projectId: ProjectID, invoiceId: InvoiceID?,
        continuation: AsyncThrowingStream<[FrozenInvoiceContents]?, Error>.Continuation) {
        guard !normalAccessLocked, case .open = state, let resources else {
            continuation.finish(throwing: LedgerOfflineClientRuntimeFailure.runtimeClosed); return
        }
        guard !Task.isCancelled, cancelledBeforeStart.remove(id) == nil else {
            continuation.finish(throwing: CancellationError()); return
        }
        guard accountId == resources.accountId else {
            continuation.finish(throwing: LedgerOfflineClientRuntimeFailure.accountScopeMismatch); return
        }
        let task = Task.detached { [resources] in
            do {
                try await resources.streamOperationCheckpoint(.expenses)
                try Task.checkCancellation()
                try await ProjectExpensePowerSyncQuery(database: resources.structuredDatabase).runCollectedInvoices(
                    accountId: accountId, principalId: resources.principalId, projectId: projectId, invoiceId: invoiceId) { value in
                        await self.forwardStreamValue(value, to: continuation)
                    }
                continuation.finish()
            } catch is CancellationError { continuation.finish(throwing: CancellationError()) }
            catch { await self.finishStream(continuation, error: error) }
            await self.streamFinished(id: id)
        }
        streamTasks[id] = task
    }

    func startExpenseWatch(id: UUID, accountId: AccountID, projectId: ProjectID,
        continuation: AsyncThrowingStream<ProjectExpenses?, Error>.Continuation) {
        guard !normalAccessLocked, case .open = state, let resources else {
            continuation.finish(throwing: LedgerOfflineClientRuntimeFailure.runtimeClosed); return
        }
        guard !Task.isCancelled, cancelledBeforeStart.remove(id) == nil else {
            continuation.finish(throwing: CancellationError()); return
        }
        guard accountId == resources.accountId else {
            continuation.finish(throwing: LedgerOfflineClientRuntimeFailure.accountScopeMismatch); return
        }
        let task = Task.detached { [resources] in
            do {
                try await resources.streamOperationCheckpoint(.expenses)
                try Task.checkCancellation()
                try await ProjectExpensePowerSyncQuery(database: resources.structuredDatabase).run(
                    accountId: accountId, principalId: resources.principalId, projectId: projectId) { value in
                        await self.forwardStreamValue(value, to: continuation)
                    }
                continuation.finish()
            } catch is CancellationError { continuation.finish(throwing: CancellationError()) }
            catch { await self.finishStream(continuation, error: error) }
            await self.streamFinished(id: id)
        }
        streamTasks[id] = task
    }

    func startProjectBudgetWatch(id: UUID, accountId: AccountID, projectId: ProjectID, currency: CurrencyCode,
        continuation: AsyncThrowingStream<ProjectBudgetRead?, Error>.Continuation) {
        guard !normalAccessLocked, case .open = state, let resources else {
            continuation.finish(throwing: LedgerOfflineClientRuntimeFailure.runtimeClosed); return
        }
        guard !Task.isCancelled, cancelledBeforeStart.remove(id) == nil else {
            continuation.finish(throwing: CancellationError()); return
        }
        guard accountId == resources.accountId else {
            continuation.finish(throwing: LedgerOfflineClientRuntimeFailure.accountScopeMismatch); return
        }
        let task = Task.detached { [resources] in
            do {
                try await resources.streamOperationCheckpoint(.projectBudget)
                try Task.checkCancellation()
                try await ProjectBudgetPowerSyncQuery(database: resources.structuredDatabase).run(
                    accountId: accountId, principalId: resources.principalId, projectId: projectId, currency: currency) { value in
                        await self.forwardStreamValue(value, to: continuation)
                    }
                continuation.finish()
            } catch is CancellationError { continuation.finish(throwing: CancellationError()) }
            catch { await self.finishStream(continuation, error: error) }
            await self.streamFinished(id: id)
        }
        streamTasks[id] = task
    }

    func startInvoicingChargeWatch(id: UUID, accountId: AccountID, projectId: ProjectID,
        continuation: AsyncThrowingStream<ProjectInvoicingItems?, Error>.Continuation) {
        guard !normalAccessLocked, case .open = state, let resources else {
            continuation.finish(throwing: LedgerOfflineClientRuntimeFailure.runtimeClosed); return
        }
        guard !Task.isCancelled, cancelledBeforeStart.remove(id) == nil else {
            continuation.finish(throwing: CancellationError()); return
        }
        guard accountId == resources.accountId else {
            continuation.finish(throwing: LedgerOfflineClientRuntimeFailure.accountScopeMismatch); return
        }
        let task = Task.detached { [resources] in
            do {
                try await resources.streamOperationCheckpoint(.invoicingCharges)
                try Task.checkCancellation()
                try await ProjectInvoicingChargePowerSyncQuery(database: resources.structuredDatabase).run(
                    accountId: accountId, principalId: resources.principalId, projectId: projectId) { value in
                        await self.forwardStreamValue(value, to: continuation)
                    }
                continuation.finish()
            } catch is CancellationError { continuation.finish(throwing: CancellationError()) }
            catch { await self.finishStream(continuation, error: error) }
            await self.streamFinished(id: id)
        }
        streamTasks[id] = task
    }

    func startDownloadedProjectItemsWatch(id: UUID, accountId: AccountID, projectId: ProjectID,
        continuation: AsyncThrowingStream<DownloadedProjectItems, Error>.Continuation) {
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
                try await resources.streamOperationCheckpoint(.downloadedProjectItems)
                try Task.checkCancellation()
                try await DownloadedProjectItemsWatch(database: resources.structuredDatabase).run(
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

    func startSpaceMediaWatch(id: UUID, accountId: AccountID, spaceId: SpaceID, scope: SpaceCreationScope,
        continuation: AsyncThrowingStream<DownloadedSpaceMedia?, Error>.Continuation) {
        guard !normalAccessLocked, case .open = state, let resources else {
            continuation.finish(throwing: LedgerOfflineClientRuntimeFailure.runtimeClosed); return
        }
        guard !Task.isCancelled, cancelledBeforeStart.remove(id) == nil else {
            continuation.finish(throwing: CancellationError()); return
        }
        guard accountId == resources.accountId else {
            continuation.finish(throwing: LedgerOfflineClientRuntimeFailure.accountScopeMismatch); return
        }
        let task = Task.detached { [resources] in
            do {
                try await resources.streamOperationCheckpoint(.spaceMedia)
                try Task.checkCancellation()
                try await SpaceMediaLocalReader(database: resources.structuredDatabase,
                    principalId: resources.principalId,accountId: accountId,spaceId: spaceId,scope: scope).watch { value in
                        await self.forwardStreamValue(value,to: continuation)
                    }
                continuation.finish()
            } catch is CancellationError { continuation.finish(throwing: CancellationError()) }
            catch { await self.finishStream(continuation,error: error) }
            await self.streamFinished(id: id)
        }
        streamTasks[id] = task
    }

    func startTransactionAttachmentWatch(id: UUID, scope: TransactionScope, transactionId: TransactionID,
        section: TransactionAttachmentSection,
        continuation: AsyncThrowingStream<DownloadedTransactionAttachments?, Error>.Continuation) {
        guard !normalAccessLocked, case .open = state, let resources else {
            continuation.finish(throwing: LedgerOfflineClientRuntimeFailure.runtimeClosed); return
        }
        guard !Task.isCancelled, cancelledBeforeStart.remove(id) == nil else {
            continuation.finish(throwing: CancellationError()); return
        }
        guard scope.accountId == resources.accountId else {
            continuation.finish(throwing: LedgerOfflineClientRuntimeFailure.accountScopeMismatch); return
        }
        let task = Task.detached { [resources] in
            do {
                try await resources.streamOperationCheckpoint(.transactionBrowser)
                try Task.checkCancellation()
                try await TransactionAttachmentLocalReader(database: resources.structuredDatabase,
                    principalId: resources.principalId, scope: scope, pendingStore: resources.attachmentStore,
                    attachmentDatabase: resources.attachmentDatabase).watch(transactionId: transactionId, section: section) { value in
                        await self.forwardStreamValue(value, to: continuation)
                    }
                continuation.finish()
            } catch is CancellationError { continuation.finish(throwing: CancellationError()) }
            catch { await self.finishStream(continuation, error: error) }
            await self.streamFinished(id: id)
        }
        streamTasks[id] = task
    }

    func startTransactionBrowserWatch(id: UUID, scope: TransactionScope,
        continuation: AsyncThrowingStream<TransactionBrowserUpdate, Error>.Continuation) {
        guard !normalAccessLocked, case .open = state, let resources else {
            continuation.finish(throwing: LedgerOfflineClientRuntimeFailure.runtimeClosed)
            return
        }
        guard !Task.isCancelled, cancelledBeforeStart.remove(id) == nil else {
            continuation.finish(throwing: CancellationError())
            return
        }
        guard scope.accountId == resources.accountId else {
            continuation.finish(throwing: LedgerOfflineClientRuntimeFailure.accountScopeMismatch)
            return
        }
        let task = Task.detached { [resources] in
            do {
                try await resources.streamOperationCheckpoint(.transactionBrowser)
                try Task.checkCancellation()
                try await TransactionDetailPowerSyncQuery(database: resources.structuredDatabase,
                    principalId: resources.principalId, scope: scope).watch { value in
                        await self.forwardStreamValue(value, to: continuation)
                    }
                continuation.finish()
            } catch is CancellationError { continuation.finish(throwing: CancellationError()) }
            catch { await self.finishStream(continuation, error: error) }
            await self.streamFinished(id: id)
        }
        streamTasks[id] = task
    }

    func startTransactionReceiptWatch(id: UUID, scope: TransactionScope, transactionId: TransactionID,
        continuation: AsyncThrowingStream<TransactionReceiptUpdate, Error>.Continuation) {
        guard !normalAccessLocked, case .open = state, let resources else {
            continuation.finish(throwing: LedgerOfflineClientRuntimeFailure.runtimeClosed)
            return
        }
        guard !Task.isCancelled, cancelledBeforeStart.remove(id) == nil else {
            continuation.finish(throwing: CancellationError())
            return
        }
        guard scope.accountId == resources.accountId else {
            continuation.finish(throwing: LedgerOfflineClientRuntimeFailure.accountScopeMismatch)
            return
        }
        let task = Task.detached { [resources] in
            do {
                try await resources.streamOperationCheckpoint(.transactionReceipt)
                try Task.checkCancellation()
                try await TransactionReceiptPowerSyncQuery(database: resources.structuredDatabase,
                    principalId: resources.principalId, scope: scope).watch(transactionId: transactionId) { value in
                        await self.forwardStreamValue(value, to: continuation)
                    }
                continuation.finish()
            } catch is CancellationError { continuation.finish(throwing: CancellationError()) }
            catch { await self.finishStream(continuation, error: error) }
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

    func transactionAttachmentCaptureScope(scope: TransactionScope, transactionId: TransactionID)
        async throws -> AttachmentCaptureScope {
        try await withFiniteLease(.captureAttachment) { resources in
            guard scope.accountId == resources.accountId else { throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch }
            return try .init(environment: resources.environment, principalId: resources.principalId,
                accountId: resources.accountId, parent: .init(kind: .transaction, id: EntityID(validating: transactionId.rawValue)))
        }
    }

    func captureTransactionAttachment(_ capture: LocalAttachmentCapture, scope: TransactionScope)
        async throws -> AttachmentLocalDurabilityReceipt {
        guard capture.scope.parent.kind == .transaction,
              let section = capture.metadata?.transactionSection else {
            throw TransactionAttachmentCaptureFailure.invalidCapture
        }
        let key = [scope.accountId.rawValue, capture.scope.parent.id.rawValue, section.rawValue]
        guard transactionCaptureSections.insert(key).inserted else {
            throw TransactionAttachmentCaptureFailure.alreadyCapturing
        }
        defer { transactionCaptureSections.remove(key) }
        return try await withFiniteLease(.captureAttachment) { resources in
            guard capture.scope.environment == resources.environment,
                  capture.scope.principalId == resources.principalId,
                  capture.scope.accountId == resources.accountId,
                  scope.accountId == resources.accountId else {
                throw AttachmentCapturePowerSyncStoreFailure.scopeMismatch
            }
            let transactionId = try TransactionID(validating: capture.scope.parent.id.rawValue)
            let reader = TransactionAttachmentLocalReader(database: resources.structuredDatabase,
                principalId: resources.principalId, scope: scope)
            let initial = try await reader.read(transactionId: transactionId, section: section)
            let pendingAtStart = try await resources.attachmentStore.pendingCaptureReceipts(parent: capture.scope.parent)
            let positioned = try TransactionAttachmentCaptureAdmission.assigningPlacement(capture,
                catalog: initial, pending: pendingAtStart)
            return try await resources.attachmentStore.enqueue(positioned, authorize: {
                try Task.checkCancellation()
                guard !resources.accessFence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
                let pending = try await resources.attachmentStore.pendingCaptureReceipts(parent: capture.scope.parent)
                let current = try await reader.read(transactionId: transactionId, section: section)
                guard current.revision == initial.revision else { throw TransactionAttachmentCaptureFailure.unavailable }
                try TransactionAttachmentCaptureAdmission.validate(positioned, catalog: current,
                    pending: pending)
                guard !resources.accessFence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            })
        }
    }

    func itemImageCaptureScope(accountId: AccountID, itemId: ItemID) async throws -> AttachmentCaptureScope {
        try await withFiniteLease(.captureAttachment) { resources in
            guard accountId == resources.accountId else { throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch }
            return try .init(environment: resources.environment, principalId: resources.principalId,
                accountId: accountId, parent: .init(kind: .item, id: EntityID(validating: itemId.rawValue)))
        }
    }

    func captureItemImage(_ capture: LocalAttachmentCapture) async throws -> AttachmentLocalDurabilityReceipt {
        guard capture.scope.parent.kind == .item else { throw ItemImageCaptureFailure.invalidCapture }
        let itemId = try ItemID(validating: capture.scope.parent.id.rawValue)
        guard capturingItems.insert(itemId).inserted else { throw ItemImageCaptureFailure.alreadyCapturing }
        defer { capturingItems.remove(itemId) }
        return try await withFiniteLease(.captureAttachment) { resources in
            guard capture.scope.environment == resources.environment,
                  capture.scope.principalId == resources.principalId,
                  capture.scope.accountId == resources.accountId else {
                throw AttachmentCapturePowerSyncStoreFailure.scopeMismatch
            }
            let reader = ItemImageCatalogLocalReader(database: resources.structuredDatabase)
            let initial = try await reader.read(accountId: resources.accountId,
                principalId: resources.principalId, itemId: itemId)
            let pending = try await resources.attachmentStore.pendingCaptureReceipts(parent: capture.scope.parent)
            let positioned = try ItemImageCaptureAdmission.assigningPlacement(capture, catalog: initial, pending: pending)
            return try await resources.attachmentStore.enqueue(positioned, authorize: {
                try Task.checkCancellation()
                guard !resources.accessFence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
                let current = try await reader.read(accountId: resources.accountId,
                    principalId: resources.principalId, itemId: itemId)
                guard current == initial else { throw ItemImageCaptureFailure.unavailable }
                let pending = try await resources.attachmentStore.pendingCaptureReceipts(parent: capture.scope.parent)
                // Recompute from the original capture: a new placement is server-independent
                // local intent, while a retry must preserve its already persisted placement.
                guard try ItemImageCaptureAdmission.assigningPlacement(capture, catalog: current, pending: pending) == positioned else {
                    throw ItemImageCaptureFailure.unavailable
                }
                guard !resources.accessFence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            })
        }
    }

    func captureAttachment(
        _ capture: LocalAttachmentCapture
    ) async throws -> AttachmentLocalDurabilityReceipt {
        try await withFiniteLease(.captureAttachment) { resources in
            try await resources.attachmentStore.enqueue(capture)
        }
    }

    func publishTransactionAttachment(_ receipt: AttachmentLocalDurabilityReceipt, scope: TransactionScope,
        using client: SupabaseTransactionAttachmentUpload) async throws -> TransactionAttachmentPublication {
        try await withFiniteLease(.captureAttachment) { resources in
            guard receipt.scope.environment == resources.environment,
                  receipt.scope.principalId == resources.principalId,
                  receipt.scope.accountId == resources.accountId, scope.accountId == resources.accountId,
                  receipt.scope.parent.kind == .transaction, let section = receipt.metadata?.transactionSection else {
                throw AttachmentCapturePowerSyncStoreFailure.scopeMismatch
            }
            let transactionId = try TransactionID(validating: receipt.scope.parent.id.rawValue)
            let reader = TransactionAttachmentLocalReader(database: resources.structuredDatabase,
                principalId: resources.principalId, scope: scope)
            let authorize: @Sendable () async throws -> Void = {
                try Task.checkCancellation()
                guard !resources.accessFence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
                _ = try await reader.read(transactionId: transactionId, section: section)
                guard !resources.accessFence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            }
            try await authorize()
            let result = try await resources.attachmentStore.publishTransactionAttachment(receipt) { candidate, checkpoint, save in
                try await client.publish(candidate, resumeFrom: checkpoint, onCheckpoint: save, authorize: authorize)
            }
            try await authorize()
            let synced = try await reader.read(transactionId: transactionId, section: section)
            guard !resources.accessFence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            _ = try await resources.attachmentStore.reconcileTransactionAttachment(receipt, catalog: synced)
            return result
        }
    }

    /// Owned alongside the existing streams, so Account removal/close cancels
    /// and drains the worker before either database or its protected key closes.
    func startTransactionAttachmentUploads(using client: SupabaseTransactionAttachmentUpload) throws {
        try requireOpenForSync()
        guard attachmentUploadTaskID == nil, let resources else { return }
        let id = UUID()
        attachmentUploadTaskID = id
        let task = Task { [resources] in
            let (events, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
            continuation.yield(())
            let observer = Task {
                    await withTaskGroup(of: Void.self) { group in
                        group.addTask {
                            do {
                                for try await _ in try resources.attachmentDatabase.watch(sql:
                                    "SELECT id,receipt_fingerprint FROM \(AttachmentCapturePowerSyncTable.queue) WHERE parent_kind IN ('transaction','expense','item')",
                                    parameters: nil, mapper: { try $0.getString(name: "id") }) {
                                    continuation.yield(())
                                }
                            } catch { continuation.yield(()) }
                        }
                        group.addTask {
                            do {
                                for try await _ in try resources.structuredDatabase.watch(sql:
                                    "SELECT id FROM transaction_attachment_references UNION ALL SELECT id FROM expense_receipt_attachments UNION ALL SELECT id FROM item_image_objects UNION ALL SELECT id FROM item_image_references UNION ALL SELECT id FROM item_image_sets",
                                    parameters: nil, mapper: { try $0.getString(name: "id") }) {
                                    continuation.yield(())
                                }
                            } catch { continuation.yield(()) }
                        }
                        group.addTask {
                            do {
                                for try await _ in try resources.structuredDatabase.watch(sql:
                                    "SELECT id,command_envelope_json FROM spike_local_operations WHERE command_type IN ('create_expense','edit_expense') AND local_state IN ('queued','applying')",
                                    parameters: nil, mapper: { try $0.getString(name: "id") }) {
                                    continuation.yield(())
                                }
                            } catch { continuation.yield(()) }
                        }
                        group.addTask {
                            for await _ in resources.structuredDatabase.currentStatus.asFlow() {
                                if Task.isCancelled { break }
                                continuation.yield(())
                            }
                        }
                        group.addTask {
                            while !Task.isCancelled {
                                do { try await Task.sleep(for: .seconds(30)) } catch { break }
                                continuation.yield(()) // Retry transient failures, including while sync is disconnected.
                            }
                        }
                    }
                    continuation.finish()
            }
            continuation.onTermination = { _ in observer.cancel() }
            for await _ in events {
                if Task.isCancelled { break }
                await self.uploadPendingTransactionAttachments(using: client)
                await self.uploadPendingItemAttachments(using: SupabaseItemAttachmentUpload(transport: client))
                await self.uploadPendingExpenseAttachments(using: SupabaseExpenseAttachmentUpload(transport: client))
                await self.reconcilePendingExpenseAttachments()
            }
            observer.cancel()
            await observer.value
            self.attachmentUploadTaskID = nil
            self.attachmentRetryAfter.removeAll()
            self.streamFinished(id: id)
        }
        streamTasks[id] = task
    }

    #if DEBUG
    func rejectTransactionAttachmentUIFixture() async throws {
        try await withFiniteLease(.captureAttachment) { resources in
            guard resources.environment != .targetProduction,
                  resources.accountId.rawValue.hasPrefix("capture-ui-"),
                  ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-transaction-capture") else {
                throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch
            }
            let parent = try LedgerEntityReference(kind: .transaction, id: EntityID(validating: "capture-ui-parent"))
            guard let receipt = try await resources.attachmentStore.pendingCaptureReceipts(parent: parent).first else {
                throw TransactionAttachmentCaptureFailure.unavailable
            }
            _ = try await resources.attachmentStore.publishTransactionAttachment(receipt) { _, _, _ in
                .rejected(code: "attachment_section_full")
            }
        }
    }
    #endif

    func uploadPendingItemAttachments(using client: SupabaseItemAttachmentUpload) async {
        guard !normalAccessLocked, case .open = state, let resources,
              let pending = try? await resources.attachmentStore.pendingItemUploads() else { return }
        let ids = Set(pending.map { "item:" + $0.attachmentId.rawValue })
        attachmentRetryAfter = attachmentRetryAfter.filter { !$0.key.hasPrefix("item:") || ids.contains($0.key) }
        var waitingParents = Set<String>()
        // Persisted milliseconds can tie. The accepted placement owns picker
        // order, and a retrying original must not be overtaken by later images.
        for receipt in pending.sorted(by: {
            if $0.scope.parent.id != $1.scope.parent.id { return $0.scope.parent.id.rawValue < $1.scope.parent.id.rawValue }
            return ($0.metadata?.placement?.localPosition ?? .max) < ($1.metadata?.placement?.localPosition ?? .max)
        }) {
            if Task.isCancelled || normalAccessLocked { return }
            let parent = receipt.scope.parent.id.rawValue
            if waitingParents.contains(parent) { continue }
            let key = "item:" + receipt.attachmentId.rawValue
            if let retry = attachmentRetryAfter[key], retry > resources.now() {
                waitingParents.insert(parent); continue
            }
            do {
                let result = try await withFiniteLease(.captureAttachment) { owned in
                    guard receipt.scope.environment == owned.environment,
                          receipt.scope.principalId == owned.principalId,
                          receipt.scope.accountId == owned.accountId,
                          receipt.scope.parent.kind == .item else {
                        throw AttachmentCapturePowerSyncStoreFailure.scopeMismatch
                    }
                    let itemId = try ItemID(validating: receipt.scope.parent.id.rawValue)
                    let reader = ItemImageCatalogLocalReader(database: owned.structuredDatabase)
                    let authorize: @Sendable () async throws -> Void = {
                        try Task.checkCancellation()
                        guard !owned.accessFence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
                        let catalog = try await reader.read(accountId: owned.accountId,
                            principalId: owned.principalId, itemId: itemId)
                        guard catalog.isComplete, !owned.accessFence.isRemoved else {
                            throw ItemImageCaptureFailure.unavailable
                        }
                    }
                    try await authorize()
                    let result = try await owned.attachmentStore.publishItemAttachment(receipt) { candidate, checkpoint, save in
                        try await client.publish(candidate, resumeFrom: checkpoint, onCheckpoint: save, authorize: authorize)
                    }
                    try await authorize()
                    let synced = try await reader.read(accountId: owned.accountId, principalId: owned.principalId, itemId: itemId)
                    guard !owned.accessFence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
                    _ = try await owned.attachmentStore.reconcileItemAttachment(receipt, catalog: synced)
                    return result
                }
                attachmentRetryAfter[key] = result == .incomplete ? resources.now().addingTimeInterval(30) : nil
                if result == .incomplete { waitingParents.insert(parent) }
            } catch {
                attachmentRetryAfter[key] = resources.now().addingTimeInterval(30)
                waitingParents.insert(parent)
            }
        }
    }

    func uploadPendingTransactionAttachments(using client: SupabaseTransactionAttachmentUpload) async {
        guard !normalAccessLocked, case .open = state, let resources else { return }
        guard let pending = try? await resources.attachmentStore.pendingTransactionUploads() else { return }
        let ids = Set(pending.map { $0.attachmentId.rawValue })
        attachmentRetryAfter = attachmentRetryAfter.filter { ids.contains($0.key) || $0.key.hasPrefix("expense:") || $0.key.hasPrefix("item:") }
        for receipt in pending {
            if Task.isCancelled || normalAccessLocked { return }
            let id = receipt.attachmentId.rawValue
            if let retry = attachmentRetryAfter[id], retry > resources.now() { continue }
            do {
                let scope = try await resources.structuredDatabase.getOptional(sql: """
                    SELECT scope_kind,project_id,client_id FROM spike_transactions WHERE id=? AND account_id=?
                    """, parameters: [receipt.scope.parent.id.rawValue, resources.accountId.rawValue]) { row -> TransactionScope in
                        let kind = try row.getString(name: "scope_kind")
                        guard ["business_inventory", "project"].contains(kind) else {
                            throw DownloadedTransactionAttachments.Failure.invalidEvidence
                        }
                        return try TransactionScope(ownerKind: kind == "business_inventory" ? .businessInventory : .project,
                            accountId: resources.accountId,
                            projectId: row.getStringOptional(name: "project_id").map { try ProjectID(validating: $0) },
                            clientId: row.getStringOptional(name: "client_id").map { try ClientID(validating: $0) })
                    }
                guard let scope else { continue } // Await the authorized parent download.
                let result = try await publishTransactionAttachment(receipt, scope: scope, using: client)
                attachmentRetryAfter[id] = result == .incomplete ? resources.now().addingTimeInterval(30) : nil
            } catch {
                // Keep durable work intact. One failing file must not starve the
                // rest; status/row events cannot hammer its failed request.
                attachmentRetryAfter[id] = resources.now().addingTimeInterval(30)
            }
        }
    }

    func reconcilePendingExpenseAttachments() async {
        guard !normalAccessLocked, case .open = state, let resources,
              let pending = try? await resources.attachmentStore.pendingExpenseReconciliations() else { return }
        for (receipt, project) in pending {
            if Task.isCancelled || normalAccessLocked { return }
            do {
                try await withFiniteLease(.captureAttachment) { owned in
                    guard !owned.accessFence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
                    if let object = try await ProjectExpensePowerSyncQuery(database: owned.structuredDatabase)
                        .receiptObject(accountId: owned.accountId, principalId: owned.principalId,
                            projectId: ProjectID(validating: project.rawValue), expenseId: receipt.scope.parent.id,
                            attachmentId: receipt.attachmentId) {
                        try Task.checkCancellation()
                        guard !owned.accessFence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
                        _ = try await owned.attachmentStore.reconcileExpenseAttachment(receipt, projectId: project, object: object)
                    }
                }
            } catch { continue } // Missing/incomplete/withdrawn read evidence never discards captured bytes.
        }
    }

    func uploadPendingExpenseAttachments(using client: SupabaseExpenseAttachmentUpload) async {
        guard !normalAccessLocked, case .open = state, let resources else { return }
        let commands: [BusinessPaidExpenseDraft]
        do {
            commands = try await resources.structuredDatabase.getAll(sql: """
                SELECT command_type,command_envelope_json FROM spike_local_operations
                WHERE account_id=? AND actor_principal_id=? AND command_type IN ('create_expense','edit_expense') AND local_state IN ('queued','applying')
                """, parameters: [resources.accountId.rawValue, resources.principalId.rawValue]) {
                    let envelope = try $0.getString(name: "command_envelope_json")
                    let bytes = Data("{\"envelope\":\(envelope)}".utf8)
                    let draft: BusinessPaidExpenseDraft
                    let actor: PrincipalID
                    if try $0.getString(name: "command_type") == "edit_expense" {
                        let command = try OperationContractCodec.decode(EditExpenseCommand.self, from: bytes)
                        draft = command.envelope.payload.entry; actor = command.envelope.actorPrincipalId
                    } else {
                        let command = try OperationContractCodec.decode(CreateExpenseCommand.self, from: bytes)
                        draft = command.envelope.payload; actor = command.envelope.actorPrincipalId
                    }
                    guard draft.accountId == resources.accountId, actor == resources.principalId else {
                        throw AttachmentCapturePowerSyncStoreFailure.scopeMismatch
                    }
                    return draft
                }
        } catch { return }
        var active: Set<String> = []
        for draft in commands {
            do {
                let parent = try LedgerEntityReference(kind: .expense, id: .init(validating: draft.expenseId.rawValue))
                let receipts = try await resources.attachmentStore.pendingCaptureReceipts(parent: parent)
                for receipt in receipts where draft.receiptAttachmentIds.contains(receipt.attachmentId) {
                    let retryID = "expense:" + receipt.attachmentId.rawValue
                    active.insert(retryID)
                    if Task.isCancelled || normalAccessLocked { return }
                    if let retry = attachmentRetryAfter[retryID], retry > resources.now() { continue }
                    do {
                        try await withFiniteLease(.captureAttachment) { owned in
                            let authorize: @Sendable () async throws -> Void = {
                                try Task.checkCancellation()
                                guard !owned.accessFence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
                                let allowed = try await owned.structuredDatabase.get(sql: """
                                    SELECT EXISTS(SELECT 1 FROM spike_account_memberships m
                                    JOIN spike_projects p ON p.account_id=m.account_id
                                    JOIN spike_clients c ON c.account_id=p.account_id AND c.id=p.client_id
                                    WHERE m.account_id=? AND m.principal_id=? AND m.state='active' AND m.financial_access='full'
                                      AND p.id=? AND p.lifecycle='active' AND c.lifecycle='active') AS allowed
                                    """, parameters: [owned.accountId.rawValue, owned.principalId.rawValue, draft.projectId.rawValue]) {
                                        try $0.getInt(name: "allowed") == 1
                                    }
                                guard allowed, !owned.accessFence.isRemoved else { throw ExpenseCreationUpload.Failure.unavailable }
                            }
                            try await authorize()
                            _ = try await owned.attachmentStore.publishExpenseAttachment(receipt,
                                projectId: EntityID(validating: draft.projectId.rawValue)) { candidate, checkpoint, save in
                                    try await client.publish(candidate, projectId: EntityID(validating: draft.projectId.rawValue),
                                        resumeFrom: checkpoint, onCheckpoint: save, authorize: authorize)
                                }
                            try await authorize()
                        }
                        attachmentRetryAfter[retryID] = nil
                    } catch { attachmentRetryAfter[retryID] = resources.now().addingTimeInterval(30) }
                }
            } catch { continue }
        }
        attachmentRetryAfter = attachmentRetryAfter.filter { !$0.key.hasPrefix("expense:") || active.contains($0.key) }
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

    func startCategoryOperationWatch(id: UUID,
        continuation: AsyncThrowingStream<[OperationSnapshot], Error>.Continuation) {
        startStream(id: id, operation: .categoryOperations, continuation: continuation,
            validate: { _ in }, makeStream: { $0.categoryManagementStore.watchOperations() })
    }

    func startPaidReturnReviewWatch(id: UUID, projectId: ProjectID, itemIds: [ItemID],
        continuation: AsyncThrowingStream<PaidReturnReview?, Error>.Continuation) {
        startStream(id: id, operation: .paidReturnOperation, continuation: continuation,
            validate: { _ in }, makeStream: { $0.paidReturnStore.watchReview(projectId: projectId, itemIds: itemIds) })
    }

    func startPaidReturnWatch(id: UUID, operationId: OperationID,
        continuation: AsyncThrowingStream<OperationSnapshot?, Error>.Continuation) {
        startStream(id: id, operation: .paidReturnOperation, continuation: continuation,
            validate: { _ in }, makeStream: { $0.paidReturnStore.watch(operationId) })
    }

    func startUninvoicedReturnReviewWatch(id: UUID, projectId: ProjectID, itemIds: [ItemID],
        continuation: AsyncThrowingStream<UninvoicedReturnReview?, Error>.Continuation) {
        startStream(id: id, operation: .uninvoicedReturnOperation, continuation: continuation,
            validate: { _ in }, makeStream: { $0.uninvoicedReturnStore.watchReview(projectId: projectId, itemIds: itemIds) })
    }

    func startUninvoicedReturnWatch(id: UUID, operationId: OperationID,
        continuation: AsyncThrowingStream<OperationSnapshot?, Error>.Continuation) {
        startStream(id: id, operation: .uninvoicedReturnOperation, continuation: continuation,
            validate: { _ in }, makeStream: { $0.uninvoicedReturnStore.watch(operationId) })
    }

    func startInventorySaleWatch(id: UUID, operationId: OperationID,
        continuation: AsyncThrowingStream<OperationSnapshot?, Error>.Continuation) {
        startStream(id: id, operation: .inventorySaleOperation, continuation: continuation,
            validate: { _ in }, makeStream: { $0.inventorySaleStore.watch(operationId) })
    }

    func startItemPriceEditWatch(id: UUID, operationId: OperationID,
        continuation: AsyncThrowingStream<OperationSnapshot?, Error>.Continuation) {
        startStream(id: id, operation: .itemPriceEditOperation, continuation: continuation,
            validate: { _ in }, makeStream: { $0.itemPriceEditStore.watch(operationId) })
    }

    func startItemPriceReviewWatch(id: UUID, project: ProjectID?, item: ItemID,
        continuation: AsyncThrowingStream<ItemPriceEditReview?, Error>.Continuation) {
        startStream(id: id, operation: .itemPriceEditOperation, continuation: continuation,
            validate: { _ in }, makeStream: { $0.itemPriceEditStore.watchReview(project: project, item: item) })
    }

    func startInventorySaleReviewWatch(id: UUID, itemIds: [ItemID],
        continuation: AsyncThrowingStream<InventorySaleReview?, Error>.Continuation) {
        startStream(id: id, operation: .inventorySaleOperation, continuation: continuation,
            validate: { _ in },makeStream: { $0.inventorySaleStore.watchReview(itemIds: itemIds) })
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
            categoryManagementApplier: appliers.categoryManagement,
            inventorySaleApplier: appliers.inventorySale,
            itemPriceEditApplier: appliers.itemPriceEdit,
            itemDetailsEditApplier: appliers.itemDetailsEdit,
            transactionDetailsEditApplier: appliers.transactionDetailsEdit,
            transactionReceiptLinesEditApplier: appliers.transactionReceiptLinesEdit,
            uninvoicedReturnApplier: appliers.uninvoicedReturn,
            paidReturnApplier: appliers.paidReturn,
            expenseCreationApplier: appliers.expenseCreation,
            invoiceCreationApplier: appliers.invoiceCreation,
            invoiceRevisionApplier: appliers.invoiceRevision,
            feeCreationApplier: appliers.feeCreation,
            expenseEditApplier: appliers.expenseEdit,
            verifiedExpenseReceipts: { try await resources.attachmentStore.verifiedExpenseReceipts(for: $0) },
            verifiedExpenseEditReceipts: { try await resources.attachmentStore.verifiedExpenseReceipts(for: $0) },
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

    private func requireOpenForSync() throws {
        try Task.checkCancellation()
        guard !normalAccessLocked, case .open = state else {
            throw LedgerOfflineClientRuntimeFailure.runtimeClosed
        }
    }

    func startSync(
        credentialProvider: @escaping @Sendable () async throws -> PowerSyncCredentials?,
        appliers: LedgerPowerSyncCommandAppliers
    ) async throws {
        try requireOpenForSync()
        guard !syncStarted else { throw LedgerOfflineClientRuntimeFailure.syncAlreadyStarted }
        guard let resources else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
        try resources.accessFence.beginSyncConnection()
        syncStarted = true
        let connector = LedgerPowerSyncUploadConnector(
            accessFence: resources.accessFence,
            credentialProvider: { [weak self] in
                guard let self else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
                try await self.requireOpenForSync()
                let credentials = try await credentialProvider()
                try await self.requireOpenForSync()
                return credentials
            },
            clientCreationApplier: appliers.clientCreation,
            projectCreationApplier: appliers.projectCreation,
            projectArchiveApplier: appliers.projectArchive,
            clientArchiveApplier: appliers.clientArchive,
            spaceChecklistRevisionApplier: appliers.spaceChecklistRevision,
            categoryManagementApplier: appliers.categoryManagement,
            inventorySaleApplier: appliers.inventorySale,
            itemPriceEditApplier: appliers.itemPriceEdit,
            itemDetailsEditApplier: appliers.itemDetailsEdit,
            transactionDetailsEditApplier: appliers.transactionDetailsEdit,
            transactionReceiptLinesEditApplier: appliers.transactionReceiptLinesEdit,
            uninvoicedReturnApplier: appliers.uninvoicedReturn,
            paidReturnApplier: appliers.paidReturn,
            expenseCreationApplier: appliers.expenseCreation,
            invoiceCreationApplier: appliers.invoiceCreation,
            invoiceRevisionApplier: appliers.invoiceRevision,
            feeCreationApplier: appliers.feeCreation,
            expenseEditApplier: appliers.expenseEdit,
            verifiedExpenseReceipts: { try await resources.attachmentStore.verifiedExpenseReceipts(for: $0) },
            verifiedExpenseEditReceipts: { try await resources.attachmentStore.verifiedExpenseReceipts(for: $0) },
            workspaceUpload: { [weak self] in
                guard let self else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
                try await self.uploadPendingCommands(using: appliers)
            },
            now: resources.now)
        let task = Task { try await resources.structuredDatabase.connect(connector: connector) }
        syncConnectionTask = task
        defer {
            syncConnectionTask = nil
            resumeDrainWaitersIfDrained()
        }
        do {
            try await withTaskCancellationHandler {
                try await task.value
                try Task.checkCancellation()
            } onCancel: { task.cancel() }
            try requireOpenForSync()
        } catch {
            // A cancelled caller can race SDK setup; disconnect before releasing
            // this startup lease so close cannot leave a late connection alive.
            try? await resources.structuredDatabase.disconnect()
            if case .open = state {
                syncStarted = false
                resources.accessFence.endSyncConnection()
            }
            throw error
        }
    }

    /// Internal session-ending boundary, not a sign-out API. The coordinator
    /// must persist recoverable cleanup intent before deleting anything in its
    /// teardown callback. A returned summary alone never authorizes deletion.
    func withSessionEndShutdown(
        _ request: SessionEndRequest,
        teardown: @Sendable () async throws -> Void
    ) async throws {
        let initial = try await pendingWorkSummary()
        guard case .readyForTeardown = try SessionEndPolicy.evaluate(request, against: initial) else {
            throw SessionEndingFailure.synchronizationIncomplete
        }
        guard !normalAccessLocked, case .open = state else {
            throw LedgerOfflineClientRuntimeFailure.runtimeClosed
        }
        try accessFence.beginSessionEnding()
        defer { accessFence.endSessionEnding() }
        let task = Task { await self.performClose(sessionEndRequest: request) }
        state = .closing(task)
        resources?.lifecycleEvent(.sessionEndingStarted)
        try await task.value.get()
        try Task.checkCancellation()
        guard !normalAccessLocked, let sessionEndValidation else {
            throw LedgerOfflineClientRuntimeFailure.runtimeClosed
        }
        guard case .readyForTeardown = try sessionEndValidation.get() else {
            throw SessionEndingFailure.synchronizationIncomplete
        }
        try await teardown()
    }

    func withProtectedReportActivity(_ body: @escaping @MainActor @Sendable () async throws -> Void) async throws {
        try await withFiniteLease(.protectedReportDelivery) { _ in
            try Task.checkCancellation()
            try await body()
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

    private func performClose(sessionEndRequest: SessionEndRequest? = nil) async -> Result<Void, LedgerOfflineClientRuntimeFailure> {
        for task in streamTasks.values { task.cancel() }
        commandUploadTask?.cancel()
        syncConnectionTask?.cancel()
        await waitUntilDrained()

        guard let resources else {
            let result: Result<Void, LedgerOfflineClientRuntimeFailure> = .success(())
            state = .closed(result)
            return result
        }

        var attachmentFailed = false
        var structuredFailed = false
        if syncStarted {
            do { try await resources.structuredDatabase.disconnect() }
            catch { structuredFailed = true }
        }

        await resources.budgetCategoryQuery.cancelAndDrainWatches()
        await resources.categoryManagementStore.cancelAndDrainWatches()
        await resources.inventorySaleStore.cancelAndDrainWatches()
        await resources.itemPriceEditStore.cancelAndDrainWatches()
        await resources.itemDetailsEditStore.cancelAndDrainWatches()
        await resources.transactionDetailsEditStore.cancelAndDrainWatches()
        await resources.uninvoicedReturnStore.cancelAndDrainWatches()
        await resources.paidReturnStore.cancelAndDrainWatches()
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

        if let sessionEndRequest {
            do {
                // All admitted mutations and SDK callbacks have drained, and
                // replication is disconnected. Recheck before closing either DB.
                let summary = try await resources.pendingWorkQuery.summary()
                sessionEndValidation = .success(try SessionEndPolicy.evaluate(sessionEndRequest, against: summary))
            } catch {
                sessionEndValidation = .failure(error)
            }
        }

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
        if syncStarted {
            syncStarted = false
            resources.accessFence.endSyncConnection()
        }

        let lifecycleEvent = resources.lifecycleEvent
        self.resources = nil
        downloadImage = nil
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
        if ownsOpenRegistration {
            ownsOpenRegistration = false
            accessFence.endRuntimeOpen()
        }
        return result
    }

    private func waitUntilDrained() async {
        guard finiteLeaseCount != 0 || !streamTasks.isEmpty || commandUploadTask != nil || syncConnectionTask != nil else { return }
        await withCheckedContinuation { continuation in
            drainWaiters.append(continuation)
        }
    }

    private func resumeDrainWaitersIfDrained() {
        guard finiteLeaseCount == 0, streamTasks.isEmpty, commandUploadTask == nil, syncConnectionTask == nil else { return }
        let waiters = drainWaiters
        drainWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters { waiter.resume() }
    }
}

public enum LedgerPowerSyncLocalBootstrap {
    #if DEBUG
    /// Explicit UI-test-only local seed. Uses live encryption, keys, queue and
    /// runtime, but never starts sync or connects to the configured endpoint.
    public static func openTransactionAttachmentUIFixture(
        validatedEnvironment: ValidatedLedgerEnvironment, fixtureID: UUID
    ) async throws -> LedgerOfflineClientRuntime {
        guard validatedEnvironment.manifest.environment != .targetProduction,
              ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-transaction-capture"),
              let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw LedgerOfflineClientRuntimeFailure.workspaceMembershipNotReady
        }
        let account = try AccountID(validating: "capture-ui-\(fixtureID.uuidString)")
        let principal = try PrincipalID(validating: "capture-ui-member-\(fixtureID.uuidString)")
        var dependencies = LedgerPowerSyncLocalBootstrapDependencies.live
        // This no-network fixture seeds the complete category directory below.
        // Supply its synthetic download evidence without bypassing real row reads.
        dependencies.makeBudgetCategoryQuery = { database, principalId, accountId, now in
            BudgetCategoryReferencePowerSyncQuery(database: database, principalId: principalId,
                accountId: accountId, completenessObservation: { _ in
                    AsyncStream { continuation in continuation.yield(true); continuation.finish() }
                }, now: now)
        }
        let validate = dependencies.validateStructuredDatabase
        dependencies.validateStructuredDatabase = { database in
            try await validate(database)
            _ = try await database.execute(sql: """
                INSERT OR IGNORE INTO spike_account_memberships(id,account_id,principal_id,state,financial_access,role)
                VALUES('capture-ui-member',?,?,'active','full','employee')
                """, parameters: [account.rawValue, principal.rawValue])
            _ = try await database.execute(sql: """
                INSERT OR IGNORE INTO spike_budget_categories(id,account_id,display_name,kind,lifecycle,is_system,
                    excludes_from_overall_budget,presentation_order,revision)
                VALUES('capture-ui-category',?,'Capture','general','active',0,0,0,1)
                """, parameters: [account.rawValue])
            _ = try await database.execute(sql: """
                INSERT OR IGNORE INTO spike_transactions(id,account_id,scope_kind,origin,type,role,
                    amount_minor_units,currency,category_id,non_item_receipt_lines,has_email_receipt)
                VALUES('capture-ui-parent',?,'business_inventory','vendor_payment','purchase','standalone',
                    '100','USD','capture-ui-category','[]',0)
                """, parameters: [account.rawValue])
            _ = try await database.execute(sql: """
                INSERT OR IGNORE INTO transaction_attachment_sets(id,account_id,transaction_id,section,revision,expected_count)
                VALUES('capture-ui-set',?,'capture-ui-parent','receipts','1',0)
                """, parameters: [account.rawValue])
            if ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-item-capture") {
                _ = try await database.execute(sql: "INSERT OR IGNORE INTO spike_items(id,account_id,description) VALUES('capture-ui-item',?,'Capture Item')", parameters: [account.rawValue])
                _ = try await database.execute(sql: "INSERT OR IGNORE INTO item_image_sets(id,account_id,item_id,revision,expected_count) VALUES('capture-ui-item',?,'capture-ui-item','1',0)", parameters: [account.rawValue])
            }
            let identity = TransactionReceiptStreamIdentity(scope: .businessInventory(accountId: account))
            _ = try await database.syncStream(name: identity.name, params: identity.parameters).subscribe()
            // Synthetic service completeness, not live replication evidence.
            _ = try await database.execute(sql: "UPDATE ps_stream_subscriptions SET active=1,last_synced_at=1000000 WHERE stream_name='transaction_receipts'", parameters: nil)
            if ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-expense-capture") {
                _ = try await database.execute(sql: "INSERT OR IGNORE INTO spike_clients(id,account_id,display_name,lifecycle,revision,created_at_ms,updated_at_ms) VALUES('capture-ui-client',?,'Capture Client','active',1,1,1)", parameters: [account.rawValue])
                _ = try await database.execute(sql: "INSERT OR IGNORE INTO spike_projects(id,account_id,client_id,display_name,lifecycle,revision) VALUES('capture-ui-project',?,'capture-ui-client','Capture Project','active',1)", parameters: [account.rawValue])
                if ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-expense-edit-capture") {
                    _ = try await database.execute(sql: """
                        INSERT OR IGNORE INTO expenses(id,account_id,project_id,category_id,vendor,
                            expense_date,final_amount_minor_units,currency,notes,revision)
                        VALUES('capture-ui-expense',?,'capture-ui-project','capture-ui-category',
                            'Original expense','2026-09-15','100','USD','','1')
                        """, parameters: [account.rawValue])
                }
                let expenses = ProjectExpenseStreamIdentity(accountId: account,
                    projectId: try ProjectID(validating: "capture-ui-project"))
                _ = try await database.syncStream(name: expenses.name, params: expenses.parameters).subscribe()
                _ = try await database.execute(sql: "UPDATE ps_stream_subscriptions SET active=1,last_synced_at=1000000 WHERE stream_name='project_expenses'", parameters: nil)
            }
        }
        return try await open(validatedEnvironment: validatedEnvironment, principalId: principal,
            accountId: account, applicationSupportDirectory: root, dependencies: dependencies)
    }
    #endif

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
            try LedgerWorkspaceSessionCleanup.requireNoPendingCleanup(
                environment: validatedEnvironment.manifest.environment,
                principalId: principalId, accountId: accountId
            )
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
                categoryDirectoryIsComplete: {
                    dependencies.categoryDirectoryIsComplete(openedStructured.database)
                },
                subscribePhysicalItems: dependencies.subscribePhysicalItems,
                downloadImage: dependencies.downloadImage
            )
            runtimeResources = madeRuntimeResources

            stage = .workspaceAccessCheck
            try LedgerWorkspaceSessionCleanup.requireNoPendingCleanup(
                environment: validatedEnvironment.manifest.environment,
                principalId: principalId, accountId: accountId
            )
            try dependencies.requireWorkspaceNotRemoved(
                validatedEnvironment.manifest.environment, principalId, accountId
            )
            stage = .runtimeConstruction
            let owner = try dependencies.makeLifecycleOwner(madeRuntimeResources)
            dependencies.lifecycleEvent(.lifecycleOwnerConstructed)
            return LedgerOfflineClientRuntime(lifecycleOwner: owner, location: location) {
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
