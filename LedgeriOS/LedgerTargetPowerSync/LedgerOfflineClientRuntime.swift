import Foundation
import LedgerTargetCore

public enum LedgerOfflineClientRuntimeFailure: Error, Equatable, Sendable {
    case accountScopeMismatch
    case principalScopeMismatch
    case runtimeClosed
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
        case .removalPersistenceFailed: "workspace_removal_persistence_failed"
        case .removalCloseFailed: "workspace_removal_close_failed"
        case .databaseCloseFailed(let attachment, let structured):
            "workspace_runtime_close_failed_\(attachment ? 1 : 0)_\(structured ? 1 : 0)"
        }
    }
}

public final class LedgerOfflineClientRuntime:
    ItemSpaceAssigning, ItemSpaceAssignmentClearing, SpaceChecklistRevising,
    RejectedOperationRecoveryQuerying, Sendable
{
    let lifecycleOwner: AccountWorkspacePendingWorkRuntime
    private let removalHandler: @Sendable () async throws -> Void

    init(lifecycleOwner: AccountWorkspacePendingWorkRuntime,
         removalHandler: @Sendable @escaping () async throws -> Void) {
        self.lifecycleOwner = lifecycleOwner
        self.removalHandler = removalHandler
    }

    public func createClient(_ command: CreateClientCommand) async throws -> OperationReceipt {
        try await lifecycleOwner.createClient(command)
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

    public func encryptionCipher() async throws -> String {
        try await lifecycleOwner.encryptionCipher()
    }

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
extension LedgerOfflineClientRuntime: SpaceCoreDetailsQuerying {}
