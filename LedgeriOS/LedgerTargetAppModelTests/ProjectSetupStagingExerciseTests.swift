import Foundation
import LedgerTargetCore
import Testing
@testable import LedgerTargetAppModel

@Suite("Project Setup Staging Application Flow")
@MainActor
struct ProjectSetupStagingExerciseTests {
    @Test("Independent streams preserve readiness, empty meaning, and no default choices")
    func independentStreamsAndHonestReadiness() async throws {
        let clients = ControlledStream<ClientListSnapshot>()
        let categories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let setup = SetupProbe()
        let model = try Self.model()
        model.start(runtime: Self.runtime(clients, categories, setup))

        categories.yield(try Self.categorySnapshot(quality: .partial, complete: false))
        await Self.waitUntil { model.categoryStatus == "partial • incomplete" }
        #expect(model.clients.isEmpty)
        #expect(model.selectedClientId == nil)
        #expect(model.selectedCategoryIds.isEmpty)
        #expect(!model.canSubmit)

        clients.yield(try Self.clientSnapshot(quality: .stale, complete: false))
        await Self.waitUntil { model.clients.count == 2 }
        #expect(model.clientStatus == "stale • incomplete")
        #expect(model.categories.map(\.id.rawValue) == ["category-alpha", "category-beta"])
        #expect(model.selectedClientId == nil)
        #expect(model.selectedCategoryIds.isEmpty)

        clients.yield(try Self.clientSnapshot(rows: [], quality: .partial, complete: false))
        categories.yield(try Self.categorySnapshot(rows: [], quality: .partial, complete: false))
        await Self.waitUntil { model.clients.isEmpty && model.categories.isEmpty }
        #expect(model.clientStatus == "partial • incomplete")
        #expect(model.categoryStatus == "partial • incomplete")

        clients.yield(try Self.clientSnapshot(rows: [], quality: .ready, complete: true))
        categories.yield(try Self.categorySnapshot(rows: [], quality: .ready, complete: true))
        await Self.waitUntil {
            model.clientStatus == "ready • authoritative empty" &&
                model.categoryStatus == "ready • authoritative empty"
        }
        #expect(!model.canSubmit)
        model.stop()

        let reverseClients = ControlledStream<ClientListSnapshot>()
        let reverseCategories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let reverse = try Self.model()
        reverse.start(runtime: Self.runtime(reverseClients, reverseCategories, setup))
        reverseClients.yield(try Self.clientSnapshot(quality: .partial, complete: false))
        await Self.waitUntil { reverse.clients.count == 2 }
        #expect(!reverse.canSubmit)
        reverseCategories.yield(try Self.categorySnapshot(quality: .stale, complete: false))
        await Self.waitUntil { reverse.categories.count == 2 }
        reverse.projectName = "Reverse Arrival"
        reverse.selectedClientId = reverse.clients[0].id
        #expect(reverse.canSubmit)
        #expect(reverse.clientStatus == "partial • incomplete")
        #expect(reverse.categoryStatus == "stale • incomplete")
        reverse.stop()
    }

    @Test("Represented stale choices submit zero or exact nil-allocation categories")
    func exactSelectionAndSubmission() async throws {
        let clients = ControlledStream<ClientListSnapshot>()
        let categories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let setup = SetupProbe(responses: [.receipt(.queued), .receipt(.applied)])
        let identities = IdentitySequence()
        let model = try Self.model(identities: identities)
        model.start(runtime: Self.runtime(clients, categories, setup))
        categories.yield(try Self.categorySnapshot(quality: .stale, complete: false))
        clients.yield(try Self.clientSnapshot(quality: .partial, complete: false))
        await Self.waitUntil { model.clients.count == 2 && model.categories.count == 2 }

        model.projectName = "Project One"
        model.projectDescription = "  Useful description  "
        model.selectedClientId = model.clients[1].id
        #expect(model.canSubmit)
        await model.submit()

        var calls = await setup.commands()
        #expect(calls.count == 1)
        #expect(calls[0].draft.clientSelection == .existing(model.clients[1].id))
        #expect(calls[0].draft.accountId == Self.accountId)
        #expect(calls[0].draft.actorPrincipalId == Self.principalId)
        #expect(calls[0].draft.operationContractVersion.rawValue == "project-create-v1")
        #expect(calls[0].draft.description == "Useful description")
        #expect(calls[0].draft.categoryAllocations.isEmpty)
        #expect(model.receiptState == "queued")
        #expect(model.receiptExplanation == "queued — accepted locally; not yet synchronized")

        model.setCategory(model.categories[1].id, selected: true)
        model.setCategory(model.categories[0].id, selected: true)
        await model.submit()
        calls = await setup.commands()
        #expect(calls.count == 2)
        #expect(calls[1].draft.categoryAllocations.map(\.categoryId.rawValue) == [
            "category-alpha", "category-beta"
        ])
        #expect(calls[1].draft.categoryAllocations.allSatisfy { $0.allocation == nil })
        model.stop()
    }

    @Test("Removed choices are pruned and invalid input never dispatches")
    func pruningAndInvalidSubmission() async throws {
        let clients = ControlledStream<ClientListSnapshot>()
        let categories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let setup = SetupProbe()
        let model = try Self.model()
        model.start(runtime: Self.runtime(clients, categories, setup))
        clients.yield(try Self.clientSnapshot())
        categories.yield(try Self.categorySnapshot())
        await Self.waitUntil { model.clients.count == 2 && model.categories.count == 2 }
        model.selectedClientId = model.clients[0].id
        model.setCategory(model.categories[0].id, selected: true)
        model.projectName = "Project"

        clients.yield(try Self.clientSnapshot(rows: [try Self.client("client-two", "Client Two")]))
        categories.yield(try Self.categorySnapshot(rows: [
            try Self.category("category-beta", "Beta", order: 2)
        ]))
        await Self.waitUntil {
            model.selectedClientId == nil && model.selectedCategoryIds.isEmpty
        }
        #expect(!model.canSubmit)
        await model.submit()
        #expect(await setup.commands().isEmpty)

        model.stop()
    }

    @Test("Invalid newer Client or category evidence invalidates the prior preparation")
    func invalidNewerEvidenceFailsClosed() async throws {
        let clients = ControlledStream<ClientListSnapshot>()
        let categories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let setup = SetupProbe()
        let model = try Self.model()
        model.start(runtime: Self.runtime(clients, categories, setup))
        clients.yield(try Self.clientSnapshot())
        categories.yield(try Self.categorySnapshot())
        await Self.waitUntil { model.clients.count == 2 && model.categories.count == 2 }
        model.projectName = "Retained typed input"
        model.selectedClientId = model.clients[0].id
        #expect(model.canSubmit)

        clients.yield(try Self.crossAccountClientSnapshot())
        await Self.waitUntil { model.clientStatus == "blocked • completeness unknown" }
        #expect(model.clients.isEmpty)
        #expect(model.selectedClientId == nil)
        #expect(model.projectName == "Retained typed input")
        #expect(!model.canSubmit)
        await model.submit()
        #expect(await setup.commands().isEmpty)

        clients.yield(try Self.clientSnapshot())
        await Self.waitUntil { model.clients.count == 2 }
        model.selectedClientId = model.clients[0].id
        #expect(model.canSubmit)
        categories.yield(try Self.crossAccountCategorySnapshot())
        await Self.waitUntil { model.categoryStatus == "blocked • completeness unknown" }
        #expect(model.categories.isEmpty)
        #expect(!model.canSubmit)
        await model.submit()
        #expect(await setup.commands().isEmpty)

        categories.yield(try Self.categorySnapshot())
        await Self.waitUntil { model.categories.count == 2 }
        model.selectedClientId = model.clients[0].id
        #expect(model.canSubmit)
        categories.finish(throwing: StreamProbeFailure.upstream)
        await Self.waitUntil { model.categoryStatus == "blocked • completeness unknown" }
        #expect(!model.canSubmit)
        #expect(model.projectName == "Retained typed input")
        #expect(await setup.commands().isEmpty)
        model.stop()
    }

    @Test("Simultaneous submission dispatches once and ambiguous retry preserves identities")
    func singleDispatchAndStableRetryIdentity() async throws {
        let clients = ControlledStream<ClientListSnapshot>()
        let categories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let setup = SetupProbe(responses: [.suspendedFailure, .receipt(.queued)])
        let identities = IdentitySequence()
        let clock = AdvancingClock()
        let model = try Self.model(identities: identities, clock: clock)
        model.start(runtime: Self.runtime(clients, categories, setup))
        clients.yield(try Self.clientSnapshot())
        categories.yield(try Self.categorySnapshot())
        await Self.waitUntil { model.clients.count == 2 && model.categories.count == 2 }
        model.projectName = "Retry Project"
        model.selectedClientId = model.clients[0].id

        let first = Task { await model.submit() }
        let didSuspend = await Self.waitUntilAsync { await setup.isSuspended() }
        #expect(didSuspend)
        guard didSuspend else {
            first.cancel()
            return
        }
        await model.submit()
        #expect(await setup.commands().count == 1)
        await setup.resumeSuspendedFailure()
        await first.value
        #expect(model.diagnostic == "project_setup_local_acceptance_failed")
        #expect(model.projectName == "Retry Project")

        await model.submit()
        let calls = await setup.commands()
        #expect(calls.count == 2)
        #expect(calls[0].draft.projectId == calls[1].draft.projectId)
        #expect(calls[0].envelope.operationId == calls[1].envelope.operationId)
        #expect(calls[0] == calls[1])
        #expect(calls[0].fingerprint == calls[1].fingerprint)
        #expect(calls[0].envelope.clientCreatedAt == calls[1].envelope.clientCreatedAt)
        #expect(identities.allocationCount == 1)
        #expect(clock.readCount == 1)
        model.stop()
    }

    @Test(arguments: LocalOperationState.allCases)
    func everyReceiptStateIsExact(_ state: LocalOperationState) async throws {
        let clients = ControlledStream<ClientListSnapshot>()
        let categories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let setup = SetupProbe(responses: [.receipt(state)])
        let model = try Self.model()
        model.start(runtime: Self.runtime(clients, categories, setup))
        clients.yield(try Self.clientSnapshot())
        categories.yield(try Self.categorySnapshot(rows: []))
        await Self.waitUntil { model.clients.count == 2 && model.categoryStatus == "ready • authoritative empty" }
        model.projectName = "Receipt Project"
        model.selectedClientId = model.clients[0].id
        await model.submit()
        #expect(model.receiptState == state.rawValue)
        #expect(model.receiptOperationId == "operation-1")
        #expect(model.projectName == "Receipt Project")
        model.stop()
    }

    @Test("Cancellation is bounded, retains input, and never reports success")
    func cancellationRetainsInput() async throws {
        let clients = ControlledStream<ClientListSnapshot>()
        let categories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let setup = SetupProbe(responses: [.cancellation, .receipt(.queued)])
        let clock = AdvancingClock()
        let model = try Self.model(clock: clock)
        model.start(runtime: Self.runtime(clients, categories, setup))
        clients.yield(try Self.clientSnapshot())
        categories.yield(try Self.categorySnapshot())
        await Self.waitUntil { model.clients.count == 2 && model.categories.count == 2 }
        model.projectName = "Retain after cancellation"
        model.projectDescription = "Still here"
        model.selectedClientId = model.clients[0].id
        await model.submit()
        #expect(model.diagnostic == "project_setup_cancelled")
        #expect(model.receipt == nil)
        #expect(model.projectName == "Retain after cancellation")
        #expect(model.projectDescription == "Still here")
        #expect(!model.isSubmitting)
        await model.submit()
        let calls = await setup.commands()
        #expect(calls.count == 2)
        #expect(calls[0] == calls[1])
        #expect(clock.readCount == 1)
        #expect(model.receiptState == "queued")
        model.stop()
    }

    @Test("Typed form and operation failures remain bounded and dispatch honestly")
    func typedFailuresAreBounded() async throws {
        let formClients = ControlledStream<ClientListSnapshot>()
        let formCategories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let formSetup = SetupProbe()
        let formModel = ProjectSetupStagingExercise(
            accountId: Self.accountId,
            actorPrincipalId: Self.principalId,
            operationContractVersion: try OperationContractVersion(
                validating: "project-create-v1"
            ),
            makeIdentity: { throw ProjectSetupFormFailure.invalidSelectionFingerprint },
            now: { Self.timestamp }
        )
        formModel.start(runtime: Self.runtime(formClients, formCategories, formSetup))
        formClients.yield(try Self.clientSnapshot())
        formCategories.yield(try Self.categorySnapshot())
        await Self.waitUntil { formModel.clients.count == 2 && formModel.categories.count == 2 }
        formModel.projectName = "Form Failure"
        formModel.selectedClientId = formModel.clients[0].id
        await formModel.submit()
        #expect(formModel.diagnostic == "project_setup_form_selection_fingerprint_invalid")
        #expect(await formSetup.commands().isEmpty)
        formModel.stop()

        let operationClients = ControlledStream<ClientListSnapshot>()
        let operationCategories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let operationSetup = SetupProbe(responses: [.receiptMismatch])
        let operationModel = try Self.model()
        operationModel.start(runtime: Self.runtime(
            operationClients,
            operationCategories,
            operationSetup
        ))
        operationClients.yield(try Self.clientSnapshot())
        operationCategories.yield(try Self.categorySnapshot())
        await Self.waitUntil {
            operationModel.clients.count == 2 && operationModel.categories.count == 2
        }
        operationModel.projectName = "Receipt Failure"
        operationModel.selectedClientId = operationModel.clients[0].id
        await operationModel.submit()
        #expect(operationModel.diagnostic == "project_setup_receipt_mismatch")
        #expect(operationModel.receipt == nil)
        #expect(await operationSetup.commands().count == 1)
        operationModel.stop()
    }

    @Test("Stop drains both streams and prevents late mutation")
    func stopDrainsStreamsAndPreventsMutation() async throws {
        let clients = ControlledStream<ClientListSnapshot>()
        let categories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let setup = SetupProbe()
        let model = try Self.model()
        model.start(runtime: Self.runtime(clients, categories, setup))
        clients.yield(try Self.clientSnapshot())
        categories.yield(try Self.categorySnapshot())
        await Self.waitUntil { model.clients.count == 2 && model.categories.count == 2 }
        model.projectName = "Retained"
        model.stop()
        #expect(await Self.waitUntilAsync { await clients.isCancelled() })
        #expect(await Self.waitUntilAsync { await categories.isCancelled() })
        clients.yield(try Self.clientSnapshot(rows: []))
        categories.yield(try Self.categorySnapshot(rows: []))
        await Task.yield()
        #expect(model.clients.count == 2)
        #expect(model.categories.count == 2)
        #expect(model.projectName == "Retained")
        #expect(!model.canSubmit)
    }

    private static let accountId = try! AccountID(validating: "account-project-setup")
    private static let principalId = try! PrincipalID(validating: "principal-owner")
    private static let timestamp = Date(timeIntervalSince1970: 1_803_000_000)

    private static func model(
        identities: IdentitySequence = IdentitySequence(),
        clock: AdvancingClock = AdvancingClock()
    ) throws -> ProjectSetupStagingExercise {
        ProjectSetupStagingExercise(
            accountId: accountId,
            actorPrincipalId: principalId,
            operationContractVersion: try OperationContractVersion(
                validating: "project-create-v1"
            ),
            makeIdentity: { try identities.next() },
            now: { clock.now() }
        )
    }

    private static func runtime(
        _ clients: ControlledStream<ClientListSnapshot>,
        _ categories: ControlledStream<BudgetCategoryReferenceSnapshot>,
        _ setup: SetupProbe
    ) -> ProjectSetupStagingRuntime {
        ProjectSetupStagingRuntime(
            watchClients: { clients.stream },
            watchBudgetCategories: { categories.stream },
            create: { command in try await setup.create(command) }
        )
    }

    private static func client(_ id: String, _ name: String) throws -> ClientSummary {
        try ClientSummary(
            id: ClientID(validating: id),
            accountId: accountId,
            displayName: ClientDisplayName(validating: name),
            lifecycle: .active,
            createdAt: timestamp,
            updatedAt: timestamp
        )
    }

    private static func clientSnapshot(
        rows: [ClientSummary]? = nil,
        quality: ListSnapshotQuality = .ready,
        complete: Bool = true
    ) throws -> ClientListSnapshot {
        let values = try rows ?? [
            client("client-one", "Client One"),
            client("client-two", "Client Two")
        ]
        return try ClientListSnapshot(
            accountId: accountId,
            local: ListLocalSnapshot(
                queryFingerprint: ListQueryFingerprint(
                    validating: String(repeating: "1", count: 64)
                ),
                rows: values,
                visibleRowCountBeforeFiltering: values.count,
                isCompleteForQuery: complete,
                quality: quality,
                localDataVersion: LocalDataVersion(validating: "clients-\(quality.rawValue)"),
                asOf: timestamp
            )
        )
    }

    private static func category(
        _ id: String,
        _ name: String,
        order: UInt32,
        lifecycle: DirectoryLifecycleState = .active,
        isSystem: Bool = false
    ) throws -> BudgetCategoryDefinitionSnapshot {
        BudgetCategoryDefinitionSnapshot(
            id: try BudgetCategoryID(validating: id),
            accountId: accountId,
            name: try BudgetCategoryName(validating: name),
            kind: .general,
            lifecycle: lifecycle,
            isSystem: isSystem,
            excludesFromOverallBudget: false,
            presentationOrder: order,
            revision: 1
        )
    }

    private static func categorySnapshot(
        rows: [BudgetCategoryDefinitionSnapshot]? = nil,
        quality: ListSnapshotQuality = .ready,
        complete: Bool = true
    ) throws -> BudgetCategoryReferenceSnapshot {
        let values = try rows ?? [
            category("category-alpha", "Alpha", order: 1),
            category("category-beta", "Beta", order: 2),
            category("category-system", "System", order: 3, isSystem: true),
            category("category-archived", "Archived", order: 4, lifecycle: .archived)
        ]
        return try BudgetCategoryReferenceSnapshot(
            accountId: accountId,
            local: ListLocalSnapshot(
                queryFingerprint: ListQueryFingerprint(
                    validating: String(repeating: "2", count: 64)
                ),
                rows: values,
                visibleRowCountBeforeFiltering: values.count,
                isCompleteForQuery: complete,
                quality: quality,
                localDataVersion: LocalDataVersion(validating: "categories-\(quality.rawValue)"),
                asOf: timestamp
            )
        )
    }

    private static func crossAccountClientSnapshot() throws -> ClientListSnapshot {
        let otherAccount = try AccountID(validating: "account-other")
        let row = try ClientSummary(
            id: ClientID(validating: "client-other"),
            accountId: otherAccount,
            displayName: ClientDisplayName(validating: "Other Client"),
            lifecycle: .active,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        return try ClientListSnapshot(
            accountId: otherAccount,
            local: ListLocalSnapshot(
                queryFingerprint: ListQueryFingerprint(
                    validating: String(repeating: "3", count: 64)
                ),
                rows: [row],
                visibleRowCountBeforeFiltering: 1,
                isCompleteForQuery: true,
                quality: .ready,
                localDataVersion: LocalDataVersion(validating: "clients-other"),
                asOf: timestamp
            )
        )
    }

    private static func crossAccountCategorySnapshot()
        throws -> BudgetCategoryReferenceSnapshot
    {
        let otherAccount = try AccountID(validating: "account-other")
        let row = BudgetCategoryDefinitionSnapshot(
            id: try BudgetCategoryID(validating: "category-other"),
            accountId: otherAccount,
            name: try BudgetCategoryName(validating: "Other Category"),
            kind: .general,
            lifecycle: .active,
            isSystem: false,
            excludesFromOverallBudget: false,
            presentationOrder: 1,
            revision: 1
        )
        return try BudgetCategoryReferenceSnapshot(
            accountId: otherAccount,
            local: ListLocalSnapshot(
                queryFingerprint: ListQueryFingerprint(
                    validating: String(repeating: "4", count: 64)
                ),
                rows: [row],
                visibleRowCountBeforeFiltering: 1,
                isCompleteForQuery: true,
                quality: .ready,
                localDataVersion: LocalDataVersion(validating: "categories-other"),
                asOf: timestamp
            )
        )
    }

    private static func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<1_000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("Timed out waiting for model state")
    }

    private static func waitUntilAsync(
        _ condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        for _ in 0..<1_000 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return false
    }
}

private final class ControlledStream<Value: Sendable>: @unchecked Sendable {
    let stream: AsyncThrowingStream<Value, Error>
    private let continuation: AsyncThrowingStream<Value, Error>.Continuation
    private let cancellation = CancellationProbe()

    init() {
        var captured: AsyncThrowingStream<Value, Error>.Continuation?
        stream = AsyncThrowingStream { captured = $0 }
        continuation = captured!
        continuation.onTermination = { [cancellation] _ in
            Task { await cancellation.mark() }
        }
    }

    func yield(_ value: Value) { continuation.yield(value) }
    func finish(throwing error: Error) { continuation.finish(throwing: error) }
    func isCancelled() async -> Bool { await cancellation.value }
}

private enum StreamProbeFailure: Error { case upstream }

private actor CancellationProbe {
    private var cancelled = false

    var value: Bool { cancelled }

    func mark() {
        cancelled = true
    }
}

@MainActor
private final class IdentitySequence {
    private var count = 0

    func next() throws -> ProjectSetupSubmissionIdentity {
        count += 1
        return try ProjectSetupSubmissionIdentity(
            projectId: ProjectID(validating: "project-\(count)"),
            operationId: OperationID(validating: "operation-\(count)")
        )
    }

    var allocationCount: Int { count }
}

@MainActor
private final class AdvancingClock {
    private(set) var readCount = 0

    func now() -> Date {
        defer { readCount += 1 }
        return Date(timeIntervalSince1970: 1_803_000_000 + Double(readCount))
    }
}

private enum SetupResponse: Sendable {
    case receipt(LocalOperationState)
    case suspendedFailure
    case cancellation
    case receiptMismatch
}

private enum SetupProbeFailure: Error { case ambiguous }

private actor SetupProbe {
    private var recorded: [CreateProjectCommand] = []
    private var responses: [SetupResponse]
    private var suspended: CheckedContinuation<Void, Never>?

    init(responses: [SetupResponse] = [.receipt(.queued)]) {
        self.responses = responses
    }

    func create(_ command: CreateProjectCommand) async throws -> OperationReceipt {
        recorded.append(command)
        let response = responses.isEmpty ? .receipt(.queued) : responses.removeFirst()
        switch response {
        case .receipt(let state):
            return OperationReceipt(operationId: command.envelope.operationId, localState: state)
        case .suspendedFailure:
            await withCheckedContinuation { suspended = $0 }
            throw SetupProbeFailure.ambiguous
        case .cancellation:
            throw CancellationError()
        case .receiptMismatch:
            return OperationReceipt(
                operationId: try OperationID(validating: "operation-wrong"),
                localState: .queued
            )
        }
    }

    func commands() -> [CreateProjectCommand] { recorded }

    func isSuspended() -> Bool { suspended != nil }

    func resumeSuspendedFailure() {
        suspended?.resume()
        suspended = nil
    }
}
