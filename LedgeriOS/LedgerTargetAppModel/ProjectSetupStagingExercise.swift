import Foundation
import LedgerTargetCore
import Observation

public struct ProjectSetupStagingRuntime: ProjectSetupOperating, Sendable {
    public typealias ClientWatch = @Sendable () -> AsyncThrowingStream<ClientListSnapshot, Error>
    public typealias CategoryWatch = @Sendable () -> AsyncThrowingStream<BudgetCategoryReferenceSnapshot, Error>
    public typealias Create = @Sendable (CreateProjectCommand) async throws -> OperationReceipt
    public typealias OperationWatch = @Sendable (OperationID)
        -> AsyncThrowingStream<OperationSnapshot, Error>

    private let clientWatch: ClientWatch
    private let categoryWatch: CategoryWatch
    private let createOperation: Create
    private let operationWatch: OperationWatch

    public init(
        watchClients: @escaping ClientWatch,
        watchBudgetCategories: @escaping CategoryWatch,
        create: @escaping Create,
        watchOperation: @escaping OperationWatch
    ) {
        clientWatch = watchClients
        categoryWatch = watchBudgetCategories
        createOperation = create
        operationWatch = watchOperation
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

    public func watchOperation(
        _ operationId: OperationID
    ) -> AsyncThrowingStream<OperationSnapshot, Error> {
        operationWatch(operationId)
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

public enum ProjectSetupStagingStep: Int, CaseIterable, Equatable, Sendable {
    case basicInfo = 1
    case categorySelection = 2
    case budgetAmounts = 3

    public var title: String {
        switch self {
        case .basicInfo: "Basic information"
        case .categorySelection: "Select budget categories"
        case .budgetAmounts: "Set budget amounts"
        }
    }
}

public struct SubmittedProjectCategorySummary: Equatable, Sendable {
    public let id: BudgetCategoryID
    public let name: String
    public let allocation: Money?

    public init(id: BudgetCategoryID, name: String, allocation: Money?) {
        self.id = id
        self.name = name
        self.allocation = allocation
    }
}

public struct SubmittedProjectSummary: Equatable, Sendable {
    public let projectId: ProjectID
    public let projectName: String
    public let projectDescription: String?
    public let clientId: ClientID
    public let clientName: String
    public let categories: [SubmittedProjectCategorySummary]

    public init(
        projectId: ProjectID,
        projectName: String,
        projectDescription: String?,
        clientId: ClientID,
        clientName: String,
        categories: [SubmittedProjectCategorySummary]
    ) {
        self.projectId = projectId
        self.projectName = projectName
        self.projectDescription = projectDescription
        self.clientId = clientId
        self.clientName = clientName
        self.categories = categories
    }
}

@MainActor
@Observable
public final class ProjectSetupStagingExercise {
    private var projectNameStorage = ""
    private var projectDescriptionStorage = ""
    private var selectedClientIdStorage: ClientID?

    public var projectName: String {
        get { projectNameStorage }
        set {
            guard !isDraftLocked else { return }
            projectNameStorage = newValue
            inputDidChange()
        }
    }

    public var projectDescription: String {
        get { projectDescriptionStorage }
        set {
            guard !isDraftLocked else { return }
            projectDescriptionStorage = newValue
            inputDidChange()
        }
    }

    public var selectedClientId: ClientID? {
        get { selectedClientIdStorage }
        set {
            guard !isDraftLocked else { return }
            selectedClientIdStorage = newValue
            inputDidChange()
        }
    }

    public private(set) var currentStep: ProjectSetupStagingStep = .basicInfo
    public private(set) var selectedCategoryIds: Set<BudgetCategoryID> = []
    public private(set) var budgetAllocations: [BudgetCategoryID: Money] = [:]
    public private(set) var budgetAllocationText: [BudgetCategoryID: String] = [:]
    public private(set) var invalidAllocationIds: Set<BudgetCategoryID> = []
    public private(set) var clients: [ClientSummary] = []
    public private(set) var categories: [BudgetCategoryDefinitionSnapshot] = []
    public private(set) var clientStatus = "loading • completeness unknown"
    public private(set) var categoryStatus = "loading • completeness unknown"
    public private(set) var diagnostic: String?
    public private(set) var receipt: OperationReceipt?
    public private(set) var submittedProject: SubmittedProjectSummary?
    public private(set) var isSubmitting = false

    public let accountCurrency: CurrencyCode

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
    private var didInitializeCategorySelection = false
    private var operationObservationTask: Task<Void, Never>?
    private var draftGeneration = UUID()
    private var admittedTasks: [UUID: Task<Void, Never>] = [:]
    private var generation = UUID()

    public init(
        accountId: AccountID,
        accountCurrency: CurrencyCode,
        actorPrincipalId: PrincipalID,
        operationContractVersion: OperationContractVersion,
        makeIdentity: @escaping @MainActor () throws -> ProjectSetupSubmissionIdentity,
        now: @escaping @MainActor () -> Date
    ) {
        self.accountId = accountId
        self.accountCurrency = accountCurrency
        self.actorPrincipalId = actorPrincipalId
        self.operationContractVersion = operationContractVersion
        self.makeIdentity = makeIdentity
        self.now = now
    }

    public var canSubmit: Bool {
        guard currentStep == .budgetAmounts,
              runtime != nil, !isDraftLocked, preparation != nil,
              let selectedClientId,
              clients.contains(where: { $0.id == selectedClientId }),
              !selectedCategoryIds.isEmpty,
              selectedCategoryIds.isSubset(of: Set(categories.map(\.id))),
              invalidAllocationIds.isDisjoint(with: selectedCategoryIds),
              didInitializeCategorySelection else {
            return false
        }
        return (try? ProjectDisplayName(validating: projectName)) != nil
    }

    public var stepIndex: Int { currentStep.rawValue }
    public var stepTitle: String { currentStep.title }
    public var isDraftLocked: Bool { isSubmitting || isAcceptedProjectReceipt }

    public var canGoBack: Bool {
        !isDraftLocked && currentStep != .basicInfo
    }

    public var canAdvance: Bool {
        guard !isDraftLocked else { return false }
        switch currentStep {
        case .basicInfo:
            return runtime != nil &&
                (try? ProjectDisplayName(validating: projectName)) != nil &&
                selectedClientId.map { selected in
                    clients.contains(where: { $0.id == selected })
                } == true
        case .categorySelection:
            return preparation != nil && didInitializeCategorySelection &&
                !selectedCategoryIds.isEmpty &&
                selectedCategoryIds.isSubset(of: Set(categories.map(\.id)))
        case .budgetAmounts:
            return false
        }
    }

    @discardableResult
    public func next() -> Bool {
        guard canAdvance else { return false }
        switch currentStep {
        case .basicInfo:
            currentStep = .categorySelection
        case .categorySelection:
            currentStep = .budgetAmounts
        case .budgetAmounts:
            return false
        }
        return true
    }

    @discardableResult
    public func back() -> Bool {
        guard canGoBack else { return false }
        switch currentStep {
        case .basicInfo:
            return false
        case .categorySelection:
            currentStep = .basicInfo
        case .budgetAmounts:
            currentStep = .categorySelection
        }
        return true
    }

    public var receiptOperationId: String? { receipt?.operationId.rawValue }
    public var receiptState: String? { receipt?.localState.rawValue }

    public var hasPostAcceptanceObservationIssue: Bool {
        isAcceptedProjectReceipt && diagnostic != nil
    }

    public var isAcceptedProjectReceipt: Bool {
        guard let state = receipt?.localState else { return false }
        return [.queued, .applying, .applied].contains(state)
    }

    public var receiptExplanation: String? {
        guard let receipt else { return nil }
        switch receipt.localState {
        case .queued:
            return "queued — accepted locally; not yet synchronized"
        case .applying:
            return "applying — accepted locally; synchronization is in progress"
        case .applied:
            return "applied — accepted and synchronized"
        case .rejected:
            return "rejected — the draft is retained for a corrected attempt"
        case .superseded:
            return "superseded — this operation was replaced by a correction"
        case .resolved:
            return "resolved — the prior rejection was resolved without this operation pending"
        }
    }

    public func start(runtime: ProjectSetupStagingRuntime) async {
        generation = UUID()
        draftGeneration = UUID()
        let activeGeneration = generation
        operationObservationTask?.cancel()
        operationObservationTask = nil
        self.runtime = nil
        isSubmitting = false
        clientSnapshot = nil
        categorySnapshot = nil
        preparation = nil
        clients = []
        categories = []
        resetDraftState(applyCurrentCategoryDefaults: false)
        clientStatus = "loading • completeness unknown"
        categoryStatus = "loading • completeness unknown"

        await cancelAndDrainAdmittedTasks()

        guard generation == activeGeneration else { return }
        self.runtime = runtime

        let clientTaskID = UUID()
        let clientTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.admittedTasks[clientTaskID] = nil }
            do {
                for try await directory in runtime.watchClients() {
                    guard !Task.isCancelled else { return }
                    self.receiveClients(directory, generation: activeGeneration)
                }
            } catch is CancellationError {
                return
            } catch {
                self.receiveFailure(
                    "project_setup_clients_local_failed",
                    source: .clients,
                    generation: activeGeneration
                )
            }
        }
        admittedTasks[clientTaskID] = clientTask

        let categoryTaskID = UUID()
        let categoryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.admittedTasks[categoryTaskID] = nil }
            do {
                for try await snapshot in runtime.watchBudgetCategories() {
                    guard !Task.isCancelled else { return }
                    self.receiveCategories(snapshot, generation: activeGeneration)
                }
            } catch is CancellationError {
                return
            } catch {
                self.receiveFailure(
                    "project_setup_categories_local_failed",
                    source: .categories,
                    generation: activeGeneration
                )
            }
        }
        admittedTasks[categoryTaskID] = categoryTask
    }

    public func stop() async {
        generation = UUID()
        draftGeneration = UUID()
        runtime = nil
        isSubmitting = false
        // Clear presentation evidence before awaiting potentially suspended work.
        // Accepted operations remain owned by the durable runtime, not this form.
        clientSnapshot = nil
        categorySnapshot = nil
        preparation = nil
        clients = []
        categories = []
        resetDraftState(applyCurrentCategoryDefaults: false)
        clientStatus = "unavailable • workspace closed"
        categoryStatus = "unavailable • workspace closed"
        operationObservationTask?.cancel()
        operationObservationTask = nil
        await cancelAndDrainAdmittedTasks()
    }

    public func setCategory(_ categoryId: BudgetCategoryID, selected: Bool) {
        guard !isDraftLocked,
              categories.contains(where: { $0.id == categoryId }) else { return }
        if selected {
            selectedCategoryIds.insert(categoryId)
        } else {
            selectedCategoryIds.remove(categoryId)
            budgetAllocations[categoryId] = nil
            budgetAllocationText[categoryId] = nil
            invalidAllocationIds.remove(categoryId)
        }
        inputDidChange()
    }

    public func allocation(for categoryId: BudgetCategoryID) -> Money? {
        guard selectedCategoryIds.contains(categoryId) else { return nil }
        return budgetAllocations[categoryId]
    }

    @discardableResult
    public func setAllocation(
        _ allocation: Money?,
        for categoryId: BudgetCategoryID
    ) -> Bool {
        guard !isDraftLocked,
              selectedCategoryIds.contains(categoryId),
              categories.contains(where: { $0.id == categoryId }) else {
            return false
        }
        if let allocation {
            guard allocation.currency == accountCurrency,
                  allocation.minorUnits >= 0 else {
                return false
            }
            budgetAllocations[categoryId] = allocation
            budgetAllocationText[categoryId] = Self.formatAllocation(allocation)
        } else {
            budgetAllocations[categoryId] = nil
            budgetAllocationText[categoryId] = nil
        }
        invalidAllocationIds.remove(categoryId)
        inputDidChange()
        return true
    }

    public func allocationText(for categoryId: BudgetCategoryID) -> String {
        guard selectedCategoryIds.contains(categoryId) else { return "" }
        return budgetAllocationText[categoryId, default: ""]
    }

    @discardableResult
    public func setAllocationText(
        _ rawValue: String,
        for categoryId: BudgetCategoryID
    ) -> Bool {
        guard !isDraftLocked,
              selectedCategoryIds.contains(categoryId),
              categories.contains(where: { $0.id == categoryId }) else {
            return false
        }
        budgetAllocationText[categoryId] = rawValue
        switch Self.parseAllocation(rawValue, currency: accountCurrency) {
        case .some(let allocation):
            budgetAllocations[categoryId] = allocation
            invalidAllocationIds.remove(categoryId)
            inputDidChange()
            return true
        case .none where rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            budgetAllocations[categoryId] = nil
            invalidAllocationIds.remove(categoryId)
            inputDidChange()
            return true
        case .none:
            budgetAllocations[categoryId] = nil
            invalidAllocationIds.insert(categoryId)
            inputDidChange()
            return false
        }
    }

    public func beginDraft() {
        guard !isSubmitting else { return }
        draftGeneration = UUID()
        operationObservationTask?.cancel()
        operationObservationTask = nil
        resetDraftState(applyCurrentCategoryDefaults: true)
    }

    public func submit() async {
        guard canSubmit, let runtime, let preparation, let selectedClientId else { return }
        let activeGeneration = generation
        let activeDraftGeneration = draftGeneration
        let inputFingerprint = currentInputFingerprint()
        let capturedProjectName = projectName
        let capturedProjectDescription = projectDescription
        let capturedCategoryIDs = selectedCategoryIds
        let capturedAllocations = budgetAllocations
        guard let capturedClient = clients.first(where: { $0.id == selectedClientId }) else {
            return
        }
        let capturedCategories = categories
            .filter { capturedCategoryIDs.contains($0.id) }
            .map {
                SubmittedProjectCategorySummary(
                    id: $0.id,
                    name: $0.name.rawValue,
                    allocation: capturedAllocations[$0.id]
                )
            }
        isSubmitting = true
        diagnostic = nil
        receipt = nil
        submittedProject = nil

        let taskID = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.admittedTasks[taskID] = nil }
            await self.performSubmission(
                runtime: runtime,
                preparation: preparation,
                selectedClientId: selectedClientId,
                projectName: capturedProjectName,
                projectDescription: capturedProjectDescription,
                categoryIDs: capturedCategoryIDs,
                allocationByCategoryId: capturedAllocations,
                clientSummary: capturedClient,
                categorySummaries: capturedCategories,
                inputFingerprint: inputFingerprint,
                generation: activeGeneration,
                draftGeneration: activeDraftGeneration
            )
        }
        admittedTasks[taskID] = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func performSubmission(
        runtime: ProjectSetupStagingRuntime,
        preparation: ProjectSetupFormPreparation,
        selectedClientId: ClientID,
        projectName: String,
        projectDescription: String,
        categoryIDs: Set<BudgetCategoryID>,
        allocationByCategoryId: [BudgetCategoryID: Money],
        clientSummary: ClientSummary,
        categorySummaries: [SubmittedProjectCategorySummary],
        inputFingerprint: InputFingerprint,
        generation activeGeneration: UUID,
        draftGeneration activeDraftGeneration: UUID
    ) async {
        defer {
            if generation == activeGeneration {
                isSubmitting = false
            }
        }
        do {
            try Task.checkCancellation()
            let identity: ProjectSetupSubmissionIdentity
            let capturedAt: Date
            if pendingInputFingerprint == inputFingerprint,
               let pendingIdentity,
               let pendingCapturedAt {
                identity = pendingIdentity
                capturedAt = pendingCapturedAt
            } else {
                identity = try makeIdentity()
                capturedAt = now()
                pendingIdentity = identity
                pendingCapturedAt = capturedAt
                pendingInputFingerprint = inputFingerprint
            }

            let client = try preparation.clientSelectionSnapshot.selection(
                clientId: selectedClientId
            )
            let allocations = try categoryIDs.map {
                try NullableCategoryAllocation(
                    categoryId: $0,
                    allocation: allocationByCategoryId[$0]
                )
            }
            let selection = try preparation.selection(
                client: client,
                projectDisplayName: ProjectDisplayName(validating: projectName),
                rawDescription: projectDescription,
                categoryAllocations: allocations
            )
            let execution = try await ProjectSetupUseCase(setup: runtime).execute(
                selection: selection,
                currentPreparation: preparation,
                projectId: identity.projectId,
                operationId: identity.operationId,
                actorPrincipalId: actorPrincipalId,
                operationContractVersion: operationContractVersion,
                capturedAt: capturedAt
            )
            let command = execution.command
            let accepted = execution.receipt
            try Task.checkCancellation()
            guard generation == activeGeneration,
                  draftGeneration == activeDraftGeneration else { return }
            receipt = accepted
            submittedProject = SubmittedProjectSummary(
                projectId: identity.projectId,
                projectName: command.draft.displayName.rawValue,
                projectDescription: command.draft.description,
                clientId: selectedClientId,
                clientName: clientSummary.displayName.rawValue,
                categories: categorySummaries
            )
            pendingIdentity = nil
            pendingCapturedAt = nil
            pendingInputFingerprint = nil
            if accepted.localState == .queued || accepted.localState == .applying {
                await beginOperationObservation(
                    command: command,
                    runtime: runtime,
                    generation: activeGeneration,
                    draftGeneration: activeDraftGeneration
                )
            } else if !isAcceptedProjectReceipt {
                diagnostic = Self.terminalDiagnostic(for: accepted.localState)
            }
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
    }

    private func beginOperationObservation(
        command: CreateProjectCommand,
        runtime: ProjectSetupStagingRuntime,
        generation activeGeneration: UUID,
        draftGeneration activeDraftGeneration: UUID
    ) async {
        let oldTask = operationObservationTask
        operationObservationTask = nil
        oldTask?.cancel()
        await oldTask?.value
        guard generation == activeGeneration,
              draftGeneration == activeDraftGeneration else { return }

        let taskID = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.admittedTasks[taskID] = nil
                if self.generation == activeGeneration,
                   self.draftGeneration == activeDraftGeneration {
                    self.operationObservationTask = nil
                }
            }
            await self.observeOperation(
                command: command,
                runtime: runtime,
                generation: activeGeneration,
                draftGeneration: activeDraftGeneration
            )
        }
        operationObservationTask = task
        admittedTasks[taskID] = task
    }

    private func observeOperation(
        command: CreateProjectCommand,
        runtime: ProjectSetupStagingRuntime,
        generation activeGeneration: UUID,
        draftGeneration activeDraftGeneration: UUID
    ) async {
        var iterator = runtime.watchOperation(command.envelope.operationId).makeAsyncIterator()
        do {
            while let snapshot = try await iterator.next() {
                guard !Task.isCancelled else { return }
                guard generation == activeGeneration,
                      draftGeneration == activeDraftGeneration else { return }
                guard snapshot.operationId == command.envelope.operationId,
                      snapshot.accountId == accountId,
                      snapshot.contractVersion == operationContractVersion,
                      snapshot.fingerprint == command.fingerprint,
                      snapshot.acceptedAt.timeIntervalSinceReferenceDate.isFinite,
                      snapshot.updatedAt.timeIntervalSinceReferenceDate.isFinite,
                      snapshot.updatedAt >= snapshot.acceptedAt,
                      let localState = snapshot.state.localState else {
                    diagnostic = "project_setup_operation_evidence_invalid"
                    return
                }
                receipt = OperationReceipt(
                    operationId: snapshot.operationId,
                    localState: localState
                )
                switch localState {
                case .queued, .applying:
                    diagnostic = nil
                case .applied:
                    diagnostic = nil
                    return
                case .rejected, .superseded, .resolved:
                    diagnostic = Self.terminalDiagnostic(for: localState)
                    pendingIdentity = nil
                    pendingCapturedAt = nil
                    pendingInputFingerprint = nil
                    return
                }
            }
            guard !Task.isCancelled,
                  generation == activeGeneration,
                  draftGeneration == activeDraftGeneration else { return }
            diagnostic = "project_setup_operation_source_completed"
        } catch is CancellationError {
            guard !Task.isCancelled,
                  generation == activeGeneration,
                  draftGeneration == activeDraftGeneration else { return }
            diagnostic = "project_setup_operation_source_cancelled"
        } catch {
            guard generation == activeGeneration,
                  draftGeneration == activeDraftGeneration else { return }
            diagnostic = "project_setup_operation_local_failed"
        }
    }

    private func cancelAndDrainAdmittedTasks() async {
        let tasks = Array(admittedTasks.values)
        tasks.forEach { $0.cancel() }
        for task in tasks {
            await task.value
        }
    }

    private func receiveClients(_ directory: ClientListSnapshot, generation: UUID) {
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
            if directory.local.isCompleteForQuery,
               let selectedClientId, !represented.contains(selectedClientId) {
                self.selectedClientId = nil
            }
            rebuildPreparation()
        } catch {
            clientSnapshot = nil
            clients = []
            clientStatus = "blocked • completeness unknown"
            rebuildPreparation()
            diagnostic = "project_setup_clients_invalid"
        }
    }

    private func receiveCategories(
        _ snapshot: BudgetCategoryReferenceSnapshot,
        generation: UUID
    ) {
        guard self.generation == generation else { return }
        guard snapshot.accountId == accountId else {
            categorySnapshot = nil
            categories = []
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
        let representedCategoryIds = Set(categories.map(\.id))
        if !didInitializeCategorySelection,
           !categories.isEmpty || snapshot.local.isCompleteForQuery {
            selectedCategoryIds = representedCategoryIds
            didInitializeCategorySelection = true
        } else if snapshot.local.isCompleteForQuery {
            selectedCategoryIds.formIntersection(representedCategoryIds)
        }
        budgetAllocations = budgetAllocations.filter {
            selectedCategoryIds.contains($0.key)
        }
        budgetAllocationText = budgetAllocationText.filter {
            selectedCategoryIds.contains($0.key)
        }
        invalidAllocationIds.formIntersection(selectedCategoryIds)
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
        generation: UUID
    ) {
        guard self.generation == generation else { return }
        switch source {
        case .clients:
            clientSnapshot = nil
            clients = []
            clientStatus = "blocked • completeness unknown"
        case .categories:
            categorySnapshot = nil
            categories = []
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
                .map {
                    CategoryAllocationFingerprint(
                        categoryId: $0,
                        allocation: budgetAllocations[$0]
                    )
                }
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
        guard !isDraftLocked else { return }
        receipt = nil
        submittedProject = nil
        invalidateRetryIfInputChanged()
    }

    private func resetDraftState(applyCurrentCategoryDefaults: Bool) {
        receipt = nil
        submittedProject = nil
        projectNameStorage = ""
        projectDescriptionStorage = ""
        selectedClientIdStorage = nil
        currentStep = .basicInfo
        selectedCategoryIds = []
        budgetAllocations = [:]
        budgetAllocationText = [:]
        invalidAllocationIds = []
        didInitializeCategorySelection = false
        diagnostic = nil
        pendingIdentity = nil
        pendingCapturedAt = nil
        pendingInputFingerprint = nil
        if applyCurrentCategoryDefaults,
           let categorySnapshot,
           !categories.isEmpty || categorySnapshot.local.isCompleteForQuery {
            selectedCategoryIds = Set(categories.map(\.id))
            didInitializeCategorySelection = true
        }
    }

    private static func status(
        readiness: ListReadiness,
        isComplete: Bool,
        isEmpty: Bool
    ) -> String {
        if isComplete, isEmpty { return "\(readiness.rawValue) • authoritative empty" }
        return "\(readiness.rawValue) • \(isComplete ? "complete" : "incomplete")"
    }

    private static func terminalDiagnostic(for state: LocalOperationState) -> String? {
        switch state {
        case .rejected: "project_setup_operation_rejected"
        case .superseded: "project_setup_operation_superseded"
        case .resolved: "project_setup_operation_resolved"
        case .queued, .applying, .applied: nil
        }
    }

    private static func parseAllocation(
        _ rawValue: String,
        currency: CurrencyCode
    ) -> Money? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let cleaned = trimmed
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard !cleaned.isEmpty,
              !cleaned.hasPrefix("-"),
              cleaned.filter({ $0 == "." }).count <= 1 else {
            return nil
        }
        let components = cleaned.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count <= 2,
              components.contains(where: { !$0.isEmpty }),
              components.allSatisfy({ $0.allSatisfy(\.isNumber) }),
              !(components.count == 1 && components[0].isEmpty),
              components.count < 2 || components[1].count <= 2 else {
            return nil
        }
        let wholeText = components[0].isEmpty ? "0" : String(components[0])
        let fractionText = components.count == 2 ? String(components[1]) : ""
        guard let whole = Int64(wholeText) else { return nil }
        let wholeCents = whole.multipliedReportingOverflow(by: 100)
        guard !wholeCents.overflow else { return nil }
        let paddedFraction = fractionText.padding(
            toLength: 2,
            withPad: "0",
            startingAt: 0
        )
        guard let fraction = Int64(paddedFraction.isEmpty ? "0" : paddedFraction) else {
            return nil
        }
        let total = wholeCents.partialValue.addingReportingOverflow(fraction)
        guard !total.overflow else { return nil }
        return Money(minorUnits: total.partialValue, currency: currency)
    }

    private static func formatAllocation(_ allocation: Money) -> String {
        let whole = allocation.minorUnits / 100
        let fraction = allocation.minorUnits % 100
        return "\(whole).\(String(format: "%02lld", fraction))"
    }

    private struct InputFingerprint: Equatable {
        let projectName: String
        let projectDescription: String
        let clientId: ClientID?
        let categoryIds: [CategoryAllocationFingerprint]
    }

    private struct CategoryAllocationFingerprint: Equatable {
        let categoryId: BudgetCategoryID
        let allocation: Money?
    }

    private enum StreamSource {
        case clients
        case categories
    }
}
