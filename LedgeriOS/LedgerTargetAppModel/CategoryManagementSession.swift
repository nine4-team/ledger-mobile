import Foundation
import LedgerTargetCore
import Observation

public struct CategoryManagementRuntime: Sendable {
    public typealias Watch = @Sendable () -> AsyncThrowingStream<BudgetCategoryReferenceSnapshot, Error>
    public typealias Submit = @Sendable (CategoryManagementPayload, UUID, Date) async throws -> OperationReceipt
    public typealias OperationWatch = @Sendable () -> AsyncThrowingStream<[OperationSnapshot], Error>
    public let watch: Watch
    public let submit: Submit
    public let watchOperations: OperationWatch?

    public init(watch: @escaping Watch, submit: @escaping Submit, watchOperations: OperationWatch? = nil) {
        self.watch = watch
        self.submit = submit
        self.watchOperations = watchOperations
    }
}

/// Shared form actions for Settings and inline Project setup. The workspace
/// owns accepted operations; dismissing a form does not undo Account changes.
@MainActor @Observable
public final class CategoryManagementSession {
    public private(set) var snapshot: BudgetCategoryReferenceSnapshot?
    public private(set) var isSaving = false
    public private(set) var message: String?
    public private(set) var operations: [OperationSnapshot] = []
    public private(set) var operationStatusUnavailable = false
    public var categories: [BudgetCategoryDefinitionSnapshot] { snapshot?.local.rows ?? [] }
    public var canSave: Bool { snapshot?.local.isCompleteForQuery == true && !isSaving }
    public var syncMessage: String? {
        if operationStatusUnavailable { return "Category sync status is unavailable. Saved work is retained on this device." }
        let rejected = operations.filter { $0.state.phase == .rejected }.count
        if rejected > 0 { return "\(rejected) category change(s) could not sync. Check the current values before trying again." }
        let pending = operations.filter { $0.state.phase == .queued || $0.state.phase == .applying }.count
        if pending > 0 { return "\(pending) category change(s) saved on this device; waiting to sync." }
        return operations.isEmpty ? nil : "All category changes synced."
    }

    private let accountId: AccountID
    private let runtime: CategoryManagementRuntime
    private var pending: (payloadBytes: Data, uuid: UUID, date: Date)?
    private var generation = UUID()

    public init(accountId: AccountID, runtime: CategoryManagementRuntime) {
        self.accountId = accountId
        self.runtime = runtime
    }

    public func receive(_ update: BudgetCategoryReferenceSnapshot) throws {
        guard update.accountId == accountId else { throw CategoryManagementFailure.wrongAccount }
        snapshot = update
    }

    public func invalidate() {
        generation = UUID()
        snapshot = nil
        message = nil
        operations = []
        operationStatusUnavailable = false
    }

    public func observe() async {
        let active = UUID()
        generation = active
        defer { if generation == active { snapshot = nil } }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.observeCategories(generation: active) }
            group.addTask { await self.observeOperations() }
            await group.waitForAll()
        }
    }

    private func observeCategories(generation active: UUID) async {
        do {
            for try await update in runtime.watch() {
                try Task.checkCancellation()
                guard generation == active else { return }
                try receive(update)
            }
        } catch is CancellationError { }
        catch { if generation == active { message = "Categories could not be loaded." } }
    }

    public func observeOperations() async {
        guard let watch = runtime.watchOperations else { return }
        let active = generation
        do {
            for try await updates in watch() {
                try Task.checkCancellation()
                guard generation == active else { return }
                try receiveOperations(updates)
            }
        } catch is CancellationError { }
        catch {
            if generation == active { operations = []; operationStatusUnavailable = true }
        }
    }

    public func receiveOperations(_ updates: [OperationSnapshot]) throws {
        guard updates.allSatisfy({ $0.accountId == accountId && $0.contractVersion.rawValue == "category-management-v1" }),
              Set(updates.map(\.operationId)).count == updates.count else {
            operations = []
            operationStatusUnavailable = true
            throw CategoryManagementFailure.receiptMismatch
        }
        operations = updates
        operationStatusUnavailable = false
    }

    @discardableResult
    public func save(_ payload: CategoryManagementPayload) async throws -> OperationReceipt {
        guard !isSaving, snapshot != nil else { throw CategoryManagementFailure.incompleteDirectory }
        // Retry identity belongs to exact command bytes, not Swift's canonically
        // equivalent String comparison. A changed display spelling is a new edit.
        let payloadBytes = try OperationContractCodec.encode(payload)
        if pending?.payloadBytes != payloadBytes {
            guard canSave, let snapshot else { throw CategoryManagementFailure.incompleteDirectory }
            _ = try CategoryManagement.applying(payload, to: snapshot)
            pending = (payloadBytes, UUID(), Date())
        }
        guard let operation = pending else { throw CategoryManagementFailure.invalidCommand }
        let active = generation
        isSaving = true
        defer { isSaving = false }
        do {
            let receipt = try await runtime.submit(payload, operation.uuid, operation.date)
            guard generation == active, !Task.isCancelled else { throw CancellationError() }
            guard receipt.localState != .rejected else {
                pending = nil
                throw CategoryManagementFailure.revisionConflict
            }
            pending = nil
            message = receipt.localState == .applied ? "Saved." : "Saved on this device; waiting to sync."
            return receipt
        } catch {
            if generation == active, !(error is CancellationError) {
                message = "The category change could not be saved. Your form is still available."
            }
            throw error
        }
    }
}
