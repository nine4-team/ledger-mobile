import Foundation
import LedgerTargetCore

public enum LedgerOfflineClientRuntimeFailure: Error, Equatable, Sendable {
    case accountScopeMismatch
    case principalScopeMismatch
    case runtimeClosed
    case databaseCloseFailed(
        attachmentDatabase: Bool,
        structuredDatabase: Bool
    )

    public var diagnosticCode: String {
        switch self {
        case .accountScopeMismatch: "workspace_runtime_account_scope_mismatch"
        case .principalScopeMismatch: "workspace_runtime_principal_scope_mismatch"
        case .runtimeClosed: "workspace_runtime_closed"
        case .databaseCloseFailed(let attachment, let structured):
            "workspace_runtime_close_failed_\(attachment ? 1 : 0)_\(structured ? 1 : 0)"
        }
    }
}

public final class LedgerOfflineClientRuntime: Sendable {
    private let lifecycleOwner: AccountWorkspacePendingWorkRuntime

    init(lifecycleOwner: AccountWorkspacePendingWorkRuntime) {
        self.lifecycleOwner = lifecycleOwner
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

    public func archive(_ command: ArchiveClientCommand) async throws -> OperationReceipt {
        try await lifecycleOwner.archiveClient(command)
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
