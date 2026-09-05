import Foundation
import LedgerTargetCore
import Observation

public struct ProjectSetupStagingRuntime: ProjectSetupOperating, Sendable {
    public typealias ClientWatch = @Sendable () -> AsyncThrowingStream<ClientListSnapshot, Error>
    public typealias CategoryWatch = @Sendable () -> AsyncThrowingStream<BudgetCategoryReferenceSnapshot, Error>
    public typealias Create = @Sendable (CreateProjectCommand) async throws -> OperationReceipt

    private let clientWatch: ClientWatch
    private let categoryWatch: CategoryWatch
    private let createOperation: Create

    public init(
        watchClients: @escaping ClientWatch,
        watchBudgetCategories: @escaping CategoryWatch,
        create: @escaping Create
    ) {
        clientWatch = watchClients
        categoryWatch = watchBudgetCategories
        createOperation = create
    }

    public func watchClients() -> AsyncThrowingStream<ClientListSnapshot, Error> {
        clientWatch()
    }

    public func watchBudgetCategories()
        -> AsyncThrowingStream<BudgetCategoryReferenceSnapshot, Error>
    {
        categoryWatch()
    }

    public func create(_ command: CreateProjectCommand) async throws -> OperationReceipt {
        try await createOperation(command)
    }
}

public struct ProjectSetupSubmissionIdentity: Equatable, Sendable {
    public let projectId: ProjectID
    public let operationId: OperationID

    public init(projectId: ProjectID, operationId: OperationID) {
        self.projectId = projectId
        self.operationId = operationId
    }
}

@MainActor
@Observable
public final class ProjectSetupStagingExercise {
    public var projectName = "" { didSet { inputDidChange() } }
    public var projectDescription = "" { didSet { inputDidChange() } }
    public var selectedClientId: ClientID? { didSet { inputDidChange() } }

    public private(set) var selectedCategoryIds: Set<BudgetCategoryID> = []
    public private(set) var clients: [ClientSummary] = []
    public private(set) var categories: [BudgetCategoryDefinitionSnapshot] = []
    public private(set) var clientStatus = "loading • completeness unknown"
    public private(set) var categoryStatus = "loading • completeness unknown"
    public private(set) var diagnostic: String?
    public private(set) var receipt: OperationReceipt?
    public private(set) var isSubmitting = false

    private let accountId: AccountID
    private let actorPrincipalId: PrincipalID
    private let operationContractVersion: OperationContractVersion
    private let makeIdentity: @MainActor () throws -> ProjectSetupSubmissionIdentity
    private let now: @MainActor () -> Date
    private var runtime: ProjectSetupStagingRuntime?
    private var clientSnapshot: ProjectExistingClientSelectionSnapshot?
    private var categorySnapshot: BudgetCategoryReferenceSnapshot?
    private var preparation: ProjectSetupFormPreparation?
    private var pendingIdentity: ProjectSetupSubmissionIdentity?
    private var pendingCapturedAt: Date?
    private var pendingInputFingerprint: InputFingerprint?
    private var clientTask: Task<Void, Never>?
    private var categoryTask: Task<Void, Never>?
    private var generation: UInt64 = 0

    public init(
        accountId: AccountID,
        actorPrincipalId: PrincipalID,
        operationContractVersion: OperationContractVersion,
        makeIdentity: @escaping @MainActor () throws -> ProjectSetupSubmissionIdentity,
        now: @escaping @MainActor () -> Date
    ) {
        self.accountId = accountId
        self.actorPrincipalId = actorPrincipalId
        self.operationContractVersion = operationContractVersion
        self.makeIdentity = makeIdentity
        self.now = now
    }

    public var canSubmit: Bool {
        guard runtime != nil, !isSubmitting, preparation != nil,
              let selectedClientId,
              clients.contains(where: { $0.id == selectedClientId }) else {
            return false
        }
        return (try? ProjectDisplayName(validating: projectName)) != nil
    }

    public var receiptOperationId: String? { receipt?.operationId.rawValue }
    public var receiptState: String? { receipt?.localState.rawValue }

    public var receiptExplanation: String? {
        guard let receipt else { return nil }
        if receipt.localState == .queued {
            return "queued — accepted locally; not yet synchronized"
        }
        return "\(receipt.localState.rawValue) — local operation state"
    }

    public func start(runtime: ProjectSetupStagingRuntime) {
        stop()
        self.runtime = runtime
        generation &+= 1
        let activeGeneration = generation
        clientSnapshot = nil
        categorySnapshot = nil
        preparation = nil
        clients = []
        categories = []
        selectedClientId = nil
        selectedCategoryIds = []
        clientStatus = "loading • completeness unknown"
        categoryStatus = "loading • completeness unknown"
        diagnostic = nil

        clientTask = Task { [weak self] in
            do {
                for try await directory in runtime.watchClients() {
                    guard !Task.isCancelled else { return }
                    self?.receiveClients(directory, generation: activeGeneration)
                }
            } catch is CancellationError {
                return
            } catch {
                self?.receiveFailure(
                    "project_setup_clients_local_failed",
                    source: .clients,
                    generation: activeGeneration
                )
            }
        }
        categoryTask = Task { [weak self] in
            do {
                for try await snapshot in runtime.watchBudgetCategories() {
                    guard !Task.isCancelled else { return }
                    self?.receiveCategories(snapshot, generation: activeGeneration)
                }
            } catch is CancellationError {
                return
            } catch {
                self?.receiveFailure(
                    "project_setup_categories_local_failed",
                    source: .categories,
                    generation: activeGeneration
                )
            }
        }
    }

    public func stop() {
        generation &+= 1
        clientTask?.cancel()
        categoryTask?.cancel()
        clientTask = nil
        categoryTask = nil
        runtime = nil
        isSubmitting = false
    }

    public func setCategory(_ categoryId: BudgetCategoryID, selected: Bool) {
        guard categories.contains(where: { $0.id == categoryId }) else { return }
        if selected {
            selectedCategoryIds.insert(categoryId)
        } else {
            selectedCategoryIds.remove(categoryId)
        }
        inputDidChange()
    }

    public func submit() async {
        guard canSubmit, let runtime, let preparation, let selectedClientId else { return }
        let activeGeneration = generation
        isSubmitting = true
        diagnostic = nil
        receipt = nil

        do {
            let fingerprint = currentInputFingerprint()
            let identity: ProjectSetupSubmissionIdentity
            let capturedAt: Date
            if pendingInputFingerprint == fingerprint,
               let pendingIdentity,
               let pendingCapturedAt {
                identity = pendingIdentity
                capturedAt = pendingCapturedAt
            } else {
                identity = try makeIdentity()
                capturedAt = now()
                pendingIdentity = identity
                pendingCapturedAt = capturedAt
                pendingInputFingerprint = fingerprint
            }

            let client = try preparation.clientSelectionSnapshot.selection(
                clientId: selectedClientId
            )
            let allocations = try selectedCategoryIds.map {
                try NullableCategoryAllocation(categoryId: $0, allocation: nil)
            }
            let selection = try preparation.selection(
                client: client,
                projectDisplayName: ProjectDisplayName(validating: projectName),
                rawDescription: projectDescription,
                categoryAllocations: allocations
            )
            let accepted = try await ProjectSetupUseCase(setup: runtime).execute(
                selection: selection,
                currentPreparation: preparation,
                projectId: identity.projectId,
                operationId: identity.operationId,
                actorPrincipalId: actorPrincipalId,
                operationContractVersion: operationContractVersion,
                capturedAt: capturedAt
            )
            guard generation == activeGeneration else { return }
            receipt = accepted
            pendingIdentity = nil
            pendingCapturedAt = nil
            pendingInputFingerprint = nil
        } catch is CancellationError {
            guard generation == activeGeneration else { return }
            diagnostic = "project_setup_cancelled"
        } catch let failure as ProjectSetupFormFailure {
            guard generation == activeGeneration else { return }
            diagnostic = failure.diagnosticCode
        } catch let failure as ProjectSetupFailure {
            guard generation == activeGeneration else { return }
            diagnostic = failure.diagnosticCode
        } catch {
            guard generation == activeGeneration else { return }
            diagnostic = "project_setup_local_failed"
        }
        guard generation == activeGeneration else { return }
        isSubmitting = false
    }

    private func receiveClients(_ directory: ClientListSnapshot, generation: UInt64) {
        guard self.generation == generation else { return }
        do {
            let snapshot = try ProjectExistingClientSelectionSnapshot(directory: directory)
            guard snapshot.accountId == accountId else {
                throw ProjectSetupFormFailure.accountScopeMismatch
            }
            clientSnapshot = snapshot
            clients = snapshot.activeClients
            clientStatus = Self.status(
                readiness: snapshot.readiness,
                isComplete: snapshot.isCompleteForQuery,
                isEmpty: snapshot.activeClients.isEmpty
            )
            let represented = Set(clients.map(\.id))
            if let selectedClientId, !represented.contains(selectedClientId) {
                self.selectedClientId = nil
            }
            rebuildPreparation()
        } catch {
            clientSnapshot = nil
            clients = []
            selectedClientId = nil
            clientStatus = "blocked • completeness unknown"
            rebuildPreparation()
            diagnostic = "project_setup_clients_invalid"
        }
    }

    private func receiveCategories(
        _ snapshot: BudgetCategoryReferenceSnapshot,
        generation: UInt64
    ) {
        guard self.generation == generation else { return }
        guard snapshot.accountId == accountId else {
            categorySnapshot = nil
            categories = []
            selectedCategoryIds = []
            categoryStatus = "blocked • completeness unknown"
            inputDidChange()
            rebuildPreparation()
            diagnostic = "project_setup_categories_invalid"
            return
        }
        categorySnapshot = snapshot
        categories = snapshot.local.rows.filter(\.isSelectableForProjectConfiguration)
        categoryStatus = Self.status(
            readiness: snapshot.local.quality.readiness,
            isComplete: snapshot.local.isCompleteForQuery,
            isEmpty: categories.isEmpty
        )
        selectedCategoryIds.formIntersection(categories.map(\.id))
        inputDidChange()
        rebuildPreparation()
    }

    private func rebuildPreparation() {
        guard let clientSnapshot, let categorySnapshot else {
            preparation = nil
            return
        }
        do {
            preparation = try ProjectSetupFormPresentation.prepare(
                clientSelectionSnapshot: clientSnapshot,
                categoryReferenceSnapshot: categorySnapshot
            )
        } catch {
            preparation = nil
            diagnostic = "project_setup_preparation_invalid"
        }
    }

    private func receiveFailure(
        _ code: String,
        source: StreamSource,
        generation: UInt64
    ) {
        guard self.generation == generation else { return }
        switch source {
        case .clients:
            clientSnapshot = nil
            clients = []
            selectedClientId = nil
            clientStatus = "blocked • completeness unknown"
        case .categories:
            categorySnapshot = nil
            categories = []
            selectedCategoryIds = []
            categoryStatus = "blocked • completeness unknown"
            inputDidChange()
        }
        rebuildPreparation()
        diagnostic = code
    }

    private func currentInputFingerprint() -> InputFingerprint {
        InputFingerprint(
            projectName: projectName,
            projectDescription: projectDescription,
            clientId: selectedClientId,
            categoryIds: selectedCategoryIds.sorted { $0.rawValue < $1.rawValue }
        )
    }

    private func invalidateRetryIfInputChanged() {
        guard let pendingInputFingerprint,
              currentInputFingerprint() != pendingInputFingerprint else { return }
        pendingIdentity = nil
        pendingCapturedAt = nil
        self.pendingInputFingerprint = nil
    }

    private func inputDidChange() {
        receipt = nil
        invalidateRetryIfInputChanged()
    }

    private static func status(
        readiness: ListReadiness,
        isComplete: Bool,
        isEmpty: Bool
    ) -> String {
        if isComplete, isEmpty { return "\(readiness.rawValue) • authoritative empty" }
        return "\(readiness.rawValue) • \(isComplete ? "complete" : "incomplete")"
    }

    private struct InputFingerprint: Equatable {
        let projectName: String
        let projectDescription: String
        let clientId: ClientID?
        let categoryIds: [BudgetCategoryID]
    }

    private enum StreamSource {
        case clients
        case categories
    }
}
