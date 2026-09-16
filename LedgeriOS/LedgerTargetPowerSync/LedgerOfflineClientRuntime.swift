import Foundation
import LedgerTargetCore
import PowerSync

extension LedgerOfflineClientRuntime: ProjectInvoiceCreating {}

public enum LedgerOfflineClientRuntimeFailure: Error, Equatable, Sendable {
    case accountScopeMismatch
    case principalScopeMismatch
    case runtimeClosed
    case workspaceMembershipNotReady
    case syncAlreadyStarted
    case syncRequiresExclusiveWorkspace
    case removalPersistenceFailed
    case removalCloseFailed
    case databaseCloseFailed(
        attachmentDatabase: Bool,
        structuredDatabase: Bool
    )

    public var diagnosticCode: String {
        switch self {
        case .accountScopeMismatch: "workspace_runtime_account_scope_mismatch"
        case .principalScopeMismatch: "workspace_runtime_principal_scope_mismatch"
        case .runtimeClosed: "workspace_runtime_closed"
        case .workspaceMembershipNotReady: "workspace_membership_download_or_reconciliation_required"
        case .syncAlreadyStarted: "workspace_sync_already_started"
        case .syncRequiresExclusiveWorkspace: "workspace_sync_requires_exclusive_runtime"
        case .removalPersistenceFailed: "workspace_removal_persistence_failed"
        case .removalCloseFailed: "workspace_removal_close_failed"
        case .databaseCloseFailed(let attachment, let structured):
            "workspace_runtime_close_failed_\(attachment ? 1 : 0)_\(structured ? 1 : 0)"
        }
    }
}

public final class LedgerOfflineClientRuntime:
    ItemSpaceAssigning, ItemSpaceAssignmentClearing, SpaceChecklistRevising, CategoryManaging, ExpenseCreating, ExpenseEditing, TransactionBrowsing, TransactionReceiptWatching, TransactionExportReading, DownloadedTransactionAttachmentReading, TransactionAttachmentCapturing,
    RejectedOperationRecoveryQuerying, DownloadedItemPlacementReading, DownloadedItemPlacementHistoryReading, PropertyManagementReportReading,
    PropertyManagementReportWatching, ClientSummaryPhysicalReportReading, ClientSummaryPhysicalReportWatching, AccountBusinessProfileReading, DownloadedProjectItemsReading, DownloadedItemImageReading, ProjectInvoicingReading, Sendable
{
    let lifecycleOwner: AccountWorkspacePendingWorkRuntime
    public func readInvoicingCharges(accountId: AccountID, projectId: ProjectID) async throws -> ProjectInvoicingItems {
        try await lifecycleOwner.readInvoicingCharges(accountId: accountId, projectId: projectId)
    }
    public func watchInvoicingCharges(accountId: AccountID, projectId: ProjectID) -> AsyncThrowingStream<ProjectInvoicingItems?, Error> {
        trackedStream { id, continuation in
            await self.lifecycleOwner.startInvoicingChargeWatch(id: id, accountId: accountId,
                projectId: projectId, continuation: continuation)
        }
    }
    public func watchDownloadedTransactionAttachments(scope: TransactionScope, transactionId: TransactionID,
        section: TransactionAttachmentSection) -> AsyncThrowingStream<DownloadedTransactionAttachments?, Error> {
        trackedStream { id, continuation in
            await self.lifecycleOwner.startTransactionAttachmentWatch(id: id, scope: scope,
                transactionId: transactionId, section: section, continuation: continuation)
        }
    }
    public func readDownloadedTransactionAttachments(scope: TransactionScope, transactionId: TransactionID,
        section: TransactionAttachmentSection) async throws -> DownloadedTransactionAttachments {
        try await lifecycleOwner.readDownloadedTransactionAttachments(scope: scope, transactionId: transactionId, section: section)
    }
    public func loadDownloadedTransactionAttachment(catalog: DownloadedTransactionAttachments,
        attachment: DownloadedTransactionAttachment, allowDownload: Bool) async throws -> Data? {
        try await lifecycleOwner.loadDownloadedTransactionAttachment(catalog: catalog, attachment: attachment,
            allowDownload: allowDownload)
    }
    public func readTransactionExport(scope: TransactionScope, orderedTransactionIDs: [TransactionID]?,
                                      asOf: ProtectedArtifactEpochMilliseconds) async throws -> TransactionExportSnapshot {
        try await lifecycleOwner.readTransactionExport(scope: scope, orderedTransactionIDs: orderedTransactionIDs, asOf: asOf)
    }
    public func watchDownloadedProjectItems(accountId: AccountID, projectId: ProjectID)
        -> AsyncThrowingStream<DownloadedProjectItems, Error> {
        trackedStream { id, continuation in
            await self.lifecycleOwner.startDownloadedProjectItemsWatch(id: id,
                accountId: accountId, projectId: projectId, continuation: continuation)
        }
    }
    func uploadPendingCommands(using appliers: LedgerPowerSyncCommandAppliers) async throws {
        try await lifecycleOwner.uploadPendingCommands(using: appliers)
    }

    /// Start SDK-managed delivery/downloads for this already-open workspace.
    /// The session owner supplies credentials and command transports bound to
    /// this Principal. Starting sync is not authentication or a grant of access.
    /// Nil download credentials do not disable uploads: command transports
    /// independently obtain and validate their authenticated user credentials.
    /// Reuse this runtime for all views. Sync requires sole runtime ownership;
    /// opening/closing a second handle can disconnect the SDK's shared coordinator.
    public func startSync(
        credentialProvider: @escaping @Sendable () async throws -> PowerSyncCredentials?,
        appliers: LedgerPowerSyncCommandAppliers
    ) async throws {
        try await lifecycleOwner.startSync(credentialProvider: credentialProvider, appliers: appliers)
    }
    private let removalHandler: @Sendable () async throws -> Void

    init(lifecycleOwner: AccountWorkspacePendingWorkRuntime,
         removalHandler: @Sendable @escaping () async throws -> Void) {
        self.lifecycleOwner = lifecycleOwner
        self.removalHandler = removalHandler
    }

    public func createClient(_ command: CreateClientCommand) async throws -> OperationReceipt {
        try await lifecycleOwner.createClient(command)
    }

    public func watchAccountBusinessProfile(accountId: AccountID) -> AsyncThrowingStream<AccountBusinessProfile, Error> {
        trackedStream { id, continuation in
            await self.lifecycleOwner.startAccountBusinessProfileWatch(id: id,
                accountId: accountId, continuation: continuation)
        }
    }

    public func readAccountBusinessProfile(accountId: AccountID) async throws -> AccountBusinessProfile {
        try await lifecycleOwner.readAccountBusinessProfile(accountId: accountId)
    }

    public func watchDownloadedItemImages(accountId: AccountID, itemId: ItemID) -> AsyncThrowingStream<DownloadedItemImageCatalog, Error> {
        trackedStream { id, continuation in
            await self.lifecycleOwner.startDownloadedItemImagesWatch(id: id, accountId: accountId,
                itemId: itemId, continuation: continuation)
        }
    }

    public func loadDownloadedItemImage(accountId: AccountID, itemId: ItemID,
        image: DownloadedItemImage, allowDownload: Bool) async throws -> Data? {
        try await lifecycleOwner.loadDownloadedItemImage(accountId: accountId, itemId: itemId,
            image: image, allowDownload: allowDownload)
    }

    public func loadDownloadedItemThumbnail(accountId: AccountID, itemId: ItemID,
        image: DownloadedItemImage, allowDownload: Bool) async throws -> Data? {
        try await lifecycleOwner.loadDownloadedItemImage(accountId: accountId, itemId: itemId,
            image: image, allowDownload: allowDownload, thumbnail: true)
    }

    public func readDownloadedItemPlacements(accountId: AccountID, scope: ItemPlacementScope) async throws -> DownloadedItemPlacements {
        try await lifecycleOwner.readDownloadedItemPlacements(accountId: accountId, scope: scope)
    }

    public func readDownloadedItemPlacementHistory(accountId: AccountID, itemId: ItemID) async throws -> DownloadedItemPlacementHistory {
        try await lifecycleOwner.readDownloadedItemPlacementHistory(accountId: accountId, itemId: itemId)
    }

    public func watchDownloadedItemPlacementHistory(accountId: AccountID, itemId: ItemID) -> AsyncThrowingStream<DownloadedItemPlacementHistory, Error> {
        trackedStream { id, continuation in
            await self.lifecycleOwner.startDownloadedItemPlacementHistoryWatch(id: id,
                accountId: accountId, itemId: itemId, continuation: continuation)
        }
    }

    public func readDownloadedTransactionReceipt(scope: TransactionScope, transactionId: TransactionID) async throws
        -> TransactionReceiptSnapshot {
        try await lifecycleOwner.readDownloadedTransactionReceipt(scope: scope, transactionId: transactionId)
    }

    public func watchTransactionReceipt(scope: TransactionScope, transactionId: TransactionID)
        -> AsyncThrowingStream<TransactionReceiptUpdate, Error> {
        trackedStream { id, continuation in
            await self.lifecycleOwner.startTransactionReceiptWatch(id: id, scope: scope,
                transactionId: transactionId, continuation: continuation)
        }
    }

    public func watchTransactions(scope: TransactionScope) -> AsyncThrowingStream<TransactionBrowserUpdate, Error> {
        trackedStream { id, continuation in
            await self.lifecycleOwner.startTransactionBrowserWatch(id: id, scope: scope, continuation: continuation)
        }
    }

    public func readDownloadedPropertyManagementReport(accountId: AccountID, projectId: ProjectID,
        currency: CurrencyCode, asOf: ProtectedArtifactEpochMilliseconds) async throws -> PropertyManagementReportSnapshot {
        try await lifecycleOwner.readDownloadedPropertyManagementReport(accountId: accountId,
            projectId: projectId, currency: currency, asOf: asOf)
    }

    public func watchDownloadedItemPlacements(accountId: AccountID, scope: ItemPlacementScope) -> AsyncThrowingStream<DownloadedItemPlacements, Error> {
        trackedStream { id, continuation in
            await self.lifecycleOwner.startDownloadedItemPlacementsWatch(id: id,
                accountId: accountId, scope: scope, continuation: continuation)
        }
    }

    public func readDownloadedClientSummaryPhysicalReport(accountId: AccountID, projectId: ProjectID,
        asOf: ProtectedArtifactEpochMilliseconds) async throws -> ClientSummaryPhysicalReportSnapshot {
        try await lifecycleOwner.readDownloadedClientSummaryPhysicalReport(accountId: accountId,
            projectId: projectId, asOf: asOf)
    }

    public func watchClientSummaryPhysicalReport(accountId: AccountID, projectId: ProjectID)
        -> AsyncThrowingStream<ClientSummaryPhysicalReportUpdate, Error> {
        trackedStream { id, continuation in
            await self.lifecycleOwner.startClientSummaryPhysicalReportWatch(id: id,
                accountId: accountId, projectId: projectId, continuation: continuation)
        }
    }

    public func watchPropertyManagementReport(accountId: AccountID, projectId: ProjectID,
        currency: CurrencyCode) -> AsyncThrowingStream<PropertyManagementReportUpdate, Error> {
        trackedStream { id, continuation in
            await self.lifecycleOwner.startPropertyManagementReportWatch(id: id, accountId: accountId,
                projectId: projectId, currency: currency, continuation: continuation)
        }
    }

    public func watchClient(
        _ request: ClientCoreDetailsRequest
    ) -> AsyncThrowingStream<ClientCoreDetailsUpdate, Error> {
        trackedStream { id, continuation in
            await self.lifecycleOwner.startClientWatch(
                id: id,
                request: request,
                continuation: continuation
            )
        }
    }

    public func createProject(_ command: CreateProjectCommand) async throws -> OperationReceipt {
        try await lifecycleOwner.createProject(command)
    }

    public func submit(_ command: CategoryManagementCommand) async throws -> OperationReceipt {
        try await lifecycleOwner.manageCategories(command)
    }

    public func inventorySaleStatus(_ operationId: OperationID) async throws -> OperationSnapshot? {
        try await lifecycleOwner.inventorySaleStatus(operationId)
    }

    public func readInventorySaleReview(itemIds: [ItemID]) async throws -> InventorySaleReview {
        try await lifecycleOwner.readInventorySaleReview(itemIds: itemIds)
    }

    public func watchInventorySaleReview(itemIds: [ItemID]) -> AsyncThrowingStream<InventorySaleReview?, Error> {
        trackedStream { id,continuation in
            await self.lifecycleOwner.startInventorySaleReviewWatch(id: id,itemIds: itemIds,continuation: continuation)
        }
    }

    public func watchInventorySale(_ operationId: OperationID) -> AsyncThrowingStream<OperationSnapshot?, Error> {
        trackedStream { id, continuation in
            await self.lifecycleOwner.startInventorySaleWatch(id: id, operationId: operationId,
                continuation: continuation)
        }
    }

    /// Retain UUID/time with the user's reviewed selection across retries.
    public func sellInventoryItems(_ payload: InventorySalePayload,
        operationUUID: UUID, capturedAt: Date) async throws -> OperationReceipt {
        try await lifecycleOwner.sellInventoryItems(payload, operationUUID: operationUUID, capturedAt: capturedAt)
    }

    public func watchCategoryOperations() -> AsyncThrowingStream<[OperationSnapshot], Error> {
        trackedStream { id, continuation in
            await self.lifecycleOwner.startCategoryOperationWatch(id: id, continuation: continuation)
        }
    }

    public func createExpense(_ draft: BusinessPaidExpenseDraft, operationUUID: UUID, capturedAt: Date, recovery: ExpenseEntryRecovery? = nil) async throws -> OperationReceipt {
        try await lifecycleOwner.createExpense(draft, operationUUID: operationUUID, capturedAt: capturedAt, recovery: recovery)
    }

    public func editExpense(_ entry: BusinessPaidExpenseDraft, expectedRevision: Int64,
                            operationUUID: UUID, capturedAt: Date, recovery: ExpenseEntryRecovery? = nil) async throws -> OperationReceipt {
        try await lifecycleOwner.editExpense(entry, expectedRevision: expectedRevision,
            operationUUID: operationUUID, capturedAt: capturedAt, recovery: recovery)
    }

    public func expenseAttachmentCaptureScope(projectId: ProjectID, expenseId: ExpenseID) async throws -> AttachmentCaptureScope {
        try await lifecycleOwner.expenseAttachmentCaptureScope(projectId: projectId, expenseId: expenseId)
    }
    public func saveExpenseEntry(_ entry: ExpenseEntryRecovery, replacing previous: ExpenseEntryRecovery? = nil) async throws {
        try await lifecycleOwner.saveExpenseEntry(entry, replacing: previous)
    }
    public func restoreExpenseEntryCaptures(_ entry: ExpenseEntryRecovery) async throws -> [LocalAttachmentCapture] {
        try await lifecycleOwner.restoreExpenseEntryCaptures(entry)
    }

    public func readExpenses(accountId: AccountID, projectId: ProjectID) async throws -> ProjectExpenses {
        try await lifecycleOwner.readExpenses(accountId: accountId, projectId: projectId)
    }

    public func readCollectedInvoiceReport(accountId: AccountID, projectId: ProjectID, invoiceId: InvoiceID,
        asOf: ProtectedArtifactEpochMilliseconds) async throws -> CollectedInvoiceReportSnapshot {
        try await lifecycleOwner.readCollectedInvoiceReport(accountId: accountId, projectId: projectId,
            invoiceId: invoiceId, asOf: asOf)
    }

    public func readLiveInvoices(accountId: AccountID, projectId: ProjectID) async throws -> [LiveInvoiceContents] {
        try await lifecycleOwner.readLiveInvoices(accountId: accountId, projectId: projectId)
    }

    public func createInvoice(_ payload: CreateInvoiceCommand.Payload, operationUUID: UUID, capturedAt: Date) async throws -> OperationReceipt {
        try await lifecycleOwner.createInvoice(payload, operationUUID: operationUUID, capturedAt: capturedAt)
    }

    public func readPendingInvoiceCreations(accountId: AccountID, projectId: ProjectID) async throws -> [PendingInvoiceCreation] {
        try await lifecycleOwner.readPendingInvoiceCreations(accountId: accountId, projectId: projectId)
    }

    public func readInvoiceCreationReview(accountId: AccountID, projectId: ProjectID) async throws -> InvoiceCreationReview {
        try await lifecycleOwner.readInvoiceCreationReview(accountId: accountId, projectId: projectId)
    }

    public func watchLiveInvoices(accountId: AccountID, projectId: ProjectID) -> AsyncThrowingStream<[LiveInvoiceContents]?, Error> {
        trackedStream { id, continuation in
            await self.lifecycleOwner.startLiveInvoiceWatch(id: id, accountId: accountId, projectId: projectId, continuation: continuation)
        }
    }

    public func readCollectedInvoices(accountId: AccountID, projectId: ProjectID) async throws -> [FrozenInvoiceContents] {
        try await lifecycleOwner.readCollectedInvoices(accountId: accountId, projectId: projectId)
    }

    public func watchCollectedInvoices(accountId: AccountID, projectId: ProjectID, invoiceId: InvoiceID? = nil) -> AsyncThrowingStream<[FrozenInvoiceContents]?, Error> {
        trackedStream { id, continuation in
            await self.lifecycleOwner.startCollectedInvoiceWatch(id: id, accountId: accountId, projectId: projectId, invoiceId: invoiceId, continuation: continuation)
        }
    }

    public func loadExpenseReceipt(projectId: ProjectID, expenseId: ExpenseID,
        attachmentId: AttachmentID, allowDownload: Bool = true) async throws -> Data? {
        try await lifecycleOwner.loadExpenseReceipt(projectId: projectId, expenseId: expenseId,
            attachmentId: attachmentId, allowDownload: allowDownload)
    }

    public func watchExpenses(accountId: AccountID, projectId: ProjectID) -> AsyncThrowingStream<ProjectExpenses?, Error> {
        trackedStream { id, continuation in
            await self.lifecycleOwner.startExpenseWatch(id: id, accountId: accountId, projectId: projectId, continuation: continuation)
        }
    }

    /// UI convenience: bind the same domain command to this workspace. The
    /// caller retains UUID/time across retries, never backend credentials.
    public func submitCategoryChange(_ payload: CategoryManagementPayload,
        operationUUID: UUID, capturedAt: Date) async throws -> OperationReceipt {
        try await lifecycleOwner.manageCategories(payload, operationUUID: operationUUID,
                                                   capturedAt: capturedAt)
    }

    public func archive(_ command: ArchiveProjectCommand) async throws -> OperationReceipt {
        try await lifecycleOwner.archiveProject(command)
    }

    public func reviseChecklists(
        _ command: ReviseSpaceChecklistsCommand
    ) async throws -> OperationReceipt {
        try await lifecycleOwner.reviseSpaceChecklists(command)
    }

    public func archive(_ command: ArchiveClientCommand) async throws -> OperationReceipt {
        try await lifecycleOwner.archiveClient(command)
    }

    public func assignItemsToSpace(
        _ command: AssignItemsToSpaceCommand
    ) async throws -> OperationReceipt {
        try await lifecycleOwner.assignItemsToSpace(command)
    }

    public func clearItemSpaceAssignments(
        _ command: ClearItemSpaceAssignmentsCommand
    ) async throws -> OperationReceipt {
        try await lifecycleOwner.clearItemSpaceAssignments(command)
    }

    public func watchOperation(
        _ operationId: OperationID
    ) -> AsyncThrowingStream<OperationSnapshot, Error> {
        trackedStream { id, continuation in
            await self.lifecycleOwner.startProjectArchiveOperationWatch(
                id: id,
                operationId: operationId,
                continuation: continuation
            )
        }
    }

    public func watchProjectCreationOperation(
        _ operationId: OperationID
    ) -> AsyncThrowingStream<OperationSnapshot, Error> {
        trackedStream { id, continuation in
            await self.lifecycleOwner.startProjectCreationOperationWatch(
                id: id,
                operationId: operationId,
                continuation: continuation
            )
        }
    }

    public func watchSpaceChecklistRevisionOperation(
        _ operationId: OperationID
    ) -> AsyncThrowingStream<OperationSnapshot, Error> {
        trackedStream { id, continuation in
            await self.lifecycleOwner.startSpaceChecklistRevisionOperationWatch(
                id: id,
                operationId: operationId,
                continuation: continuation
            )
        }
    }

    public func rejectedOperations(
        _ request: RejectedOperationRecoveryRequest
    ) async throws -> RejectedOperationRecoverySnapshot {
        try await lifecycleOwner.rejectedOperations(request)
    }

    public func watchRejectedOperations(
        _ request: RejectedOperationRecoveryRequest
    ) -> AsyncThrowingStream<RejectedOperationRecoverySnapshot, Error> {
        trackedStream { id, continuation in
            await self.lifecycleOwner.startRejectedOperationRecoveryWatch(
                id: id,
                request: request,
                continuation: continuation
            )
        }
    }

    public func watchClientArchiveOperation(
        _ operationId: OperationID
    ) -> AsyncThrowingStream<OperationSnapshot, Error> {
        trackedStream { id, continuation in
            await self.lifecycleOwner.startClientArchiveOperationWatch(
                id: id,
                operationId: operationId,
                continuation: continuation
            )
        }
    }

    public func watchItemSpaceAssignmentOperation(
        _ operationId: OperationID
    ) -> AsyncThrowingStream<OperationSnapshot, Error> {
        trackedStream { id, continuation in
            await self.lifecycleOwner.startItemSpaceAssignmentOperationWatch(
                id: id,
                operationId: operationId,
                continuation: continuation
            )
        }
    }

    public func watchItemSpaceClearingOperation(
        _ operationId: OperationID
    ) -> AsyncThrowingStream<OperationSnapshot, Error> {
        trackedStream { id, continuation in
            await self.lifecycleOwner.startItemSpaceClearingOperationWatch(
                id: id,
                operationId: operationId,
                continuation: continuation
            )
        }
    }

    public func watchProject(
        _ request: ProjectCoreDetailsRequest
    ) -> AsyncThrowingStream<ProjectCoreDetailsUpdate, Error> {
        trackedStream { id, continuation in
            await self.lifecycleOwner.startProjectWatch(
                id: id,
                request: request,
                continuation: continuation
            )
        }
    }

    public func watchClients() -> AsyncThrowingStream<ClientListSnapshot, Error> {
        trackedStream { id, continuation in
            await self.lifecycleOwner.startClientDirectoryWatch(
                id: id,
                continuation: continuation
            )
        }
    }

    public func watchProjects() -> AsyncThrowingStream<ProjectListSnapshot, Error> {
        trackedStream { id, continuation in
            await self.lifecycleOwner.startProjectDirectoryWatch(
                id: id,
                continuation: continuation
            )
        }
    }

    public func watchProjectNotes(
        _ request: ProjectNotePageRequest
    ) -> AsyncThrowingStream<ProjectNotePage, Error> {
        trackedStream { id, continuation in
            await self.lifecycleOwner.startProjectNoteWatch(
                id: id,
                request: request,
                continuation: continuation
            )
        }
    }

    public func watchSpaceCoreDetails(
        spaceId: SpaceID
    ) -> AsyncThrowingStream<SpaceCoreDetailsUpdate, Error> {
        trackedStream { id, continuation in
            await self.lifecycleOwner.startSpaceCoreDetailsWatch(
                id: id,
                spaceId: spaceId,
                continuation: continuation
            )
        }
    }

    public func watchSpaceCoreDetails(
        _ request: SpaceCoreDetailsRequest
    ) -> AsyncThrowingStream<SpaceCoreDetailsUpdate, Error> {
        trackedStream { id, continuation in
            await self.lifecycleOwner.startSpaceCoreDetailsWatch(
                id: id,
                request: request,
                continuation: continuation
            )
        }
    }

    public func watchSpaces(
        _ request: SpaceListRequest
    ) -> AsyncThrowingStream<SpaceListUpdate, Error> {
        trackedStream { id, continuation in
            await self.lifecycleOwner.startSpaceDirectoryWatch(
                id: id,
                request: request,
                continuation: continuation
            )
        }
    }

    public func watchBudgetCategories()
        -> AsyncThrowingStream<BudgetCategoryReferenceSnapshot, Error>
    {
        trackedStream { id, continuation in
            await self.lifecycleOwner.startBudgetCategoryWatch(
                id: id,
                continuation: continuation
            )
        }
    }

    public func watchSpaceAssignmentDestinations(
        scope: ItemPlacementScope
    ) -> AsyncThrowingStream<SpaceAssignmentDestinationDirectorySnapshot, Error> {
        trackedStream { id, continuation in
            await self.lifecycleOwner.startSpaceAssignmentDestinationWatch(
                id: id,
                scope: scope,
                continuation: continuation
            )
        }
    }

    public func watchTransferDestinations(
        source: ProjectSummary
    ) -> AsyncThrowingStream<TransferDestinationSelectionSnapshot, Error> {
        trackedStream { id, continuation in
            await self.lifecycleOwner.startTransferDestinationWatch(
                id: id,
                source: source,
                continuation: continuation
            )
        }
    }

    public func pendingUploadCount() async throws -> Int64 {
        try await lifecycleOwner.pendingUploadCount()
    }

    /// Before presenting cached data after online activation, require downloaded
    /// permissions to agree. Do not expose stale full-access data after learning
    /// a reduced scope, or rewrite synced membership from an HTTP response.
    public func requireMatchingDownloadedMembership(_ authorization: WorkspaceMembershipAuthorization) async throws {
        try await lifecycleOwner.requireMatchingDownloadedMembership(authorization)
    }

    /// Wait on the existing directory stream, not a timer or a second database
    /// handle. Its owned watch is cancelled/drained by normal workspace close.
    public func waitForCategoryWorkspaceReady(_ authorization: WorkspaceMembershipAuthorization) async throws {
        for try await snapshot in watchBudgetCategories() {
            try Task.checkCancellation()
            guard snapshot.local.isCompleteForQuery, snapshot.local.quality == .ready else { continue }
            try await requireMatchingDownloadedMembership(authorization)
            return
        }
        try Task.checkCancellation()
        throw LedgerOfflineClientRuntimeFailure.runtimeClosed
    }

    public func encryptionCipher() async throws -> String {
        try await lifecycleOwner.encryptionCipher()
    }

    public func transactionAttachmentCaptureScope(scope: TransactionScope, transactionId: TransactionID)
        async throws -> AttachmentCaptureScope {
        try await lifecycleOwner.transactionAttachmentCaptureScope(scope: scope, transactionId: transactionId)
    }

    public func captureTransactionAttachment(_ capture: LocalAttachmentCapture, scope: TransactionScope)
        async throws -> AttachmentLocalDurabilityReceipt {
        try await lifecycleOwner.captureTransactionAttachment(capture, scope: scope)
    }

    public func publishTransactionAttachment(_ receipt: AttachmentLocalDurabilityReceipt, scope: TransactionScope,
        using client: SupabaseTransactionAttachmentUpload) async throws -> TransactionAttachmentPublication {
        try await lifecycleOwner.publishTransactionAttachment(receipt, scope: scope, using: client)
    }

    #if DEBUG
    public func rejectTransactionAttachmentUIFixture() async throws {
        try await lifecycleOwner.rejectTransactionAttachmentUIFixture()
    }
    #endif

    public func captureAttachment(
        _ capture: LocalAttachmentCapture
    ) async throws -> AttachmentLocalDurabilityReceipt {
        try await lifecycleOwner.captureAttachment(capture)
    }

    public func resolveLocalAttachmentBytes(
        for receipt: AttachmentLocalDurabilityReceipt
    ) async throws -> Data {
        try await lifecycleOwner.resolveLocalAttachmentBytes(for: receipt)
    }

    public func pendingWorkSummary() async throws -> PendingLocalWorkSummary {
        try await lifecycleOwner.pendingWorkSummary()
    }

    /// Ordinary close preserves both encrypted databases, protected media, and keys.
    /// Destructive cleanup belongs to a later, separately authorized coordinator.
    public func close() async throws {
        try await lifecycleOwner.close()
    }

    /// One monotonic UI-invalidation event for this exact runtime's workspace.
    /// Late subscribers also receive removal; this never grants access.
    public func watchAccessRemoval() -> AsyncStream<Void> {
        lifecycleOwner.watchAccessRemoval()
    }

    /// Blocks new calls and late finite results, then drains and
    /// closes without deleting pending operations, media, databases, or keys.
    /// The consuming coordinator must immediately clear protected presentation
    /// and fence its observers: values buffered before locking cannot be recalled.
    /// Persists learned removal outside the Account databases before reporting
    /// success. Failure leaves this runtime locked and must not be acknowledged
    /// as durable removal. Activation still requires independent authorization.
    // Internal until the authorization owner can supply validated removal
    // evidence; ordinary feature/UI callers must not permanently mark removal.
    func lockAccessPreservingPendingWork() async throws {
        try await removalHandler()
    }

    func lockLocalAccessPreservingPendingWork() async throws {
        try await lifecycleOwner.lockAccessPreservingPendingWork()
    }

    private func trackedStream<Value: Sendable>(
        start:
            @Sendable @escaping (
                UUID,
                AsyncThrowingStream<Value, Error>.Continuation
            ) async -> Void
    ) -> AsyncThrowingStream<Value, Error> {
        let id = UUID()
        return AsyncThrowingStream { continuation in
            let startTask = Task {
                await start(id, continuation)
            }
            continuation.onTermination = { [lifecycleOwner] termination in
                guard case .cancelled = termination else { return }
                startTask.cancel()
                Task { await lifecycleOwner.cancelStream(id: id) }
            }
        }
    }
}

extension LedgerOfflineClientRuntime: SpaceListQuerying {}
extension LedgerOfflineClientRuntime: InventorySaleReviewReading {}
extension LedgerOfflineClientRuntime: InventorySaleWorkflowServing {}
extension LedgerOfflineClientRuntime: SpaceCoreDetailsQuerying {}
