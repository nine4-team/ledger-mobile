import Foundation
import LedgerTargetCore
import Testing
@testable import LedgerTargetAppModel

@Suite("Project Setup Staging Application Flow")
@MainActor
struct ProjectSetupStagingExerciseTests {
    @Test("Compiled SwiftUI source inventory wires recorded controls to AppModel actions")
    func swiftUISourceContract() throws {
        let ledgerDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let setupView = try String(contentsOf: ledgerDirectory.appending(
            path: "LedgerTargetApp/ProjectSetupStagingExerciseView.swift"
        ))
        let browserView = try String(contentsOf: ledgerDirectory.appending(
            path: "LedgerTargetApp/ProjectBrowsingStagingExerciseView.swift"
        ))

        for required in [
            "target-project-setup-step",
            "target-project-name",
            "target-project-existing-client",
            "target-project-client-readiness",
            "target-project-description",
            "target-project-category-readiness",
            "target-project-category-requirement",
            "target-project-allocation-",
            "target-project-allocation-error-",
            "target-project-overall-budget",
            "target-project-secondary-action",
            "target-project-next",
            "target-create-project",
            "target-project-receipt",
            "target-project-diagnostic",
            "target-project-submitted-name",
            "target-project-submitted-client",
            ".disabled(model.isDraftLocked)",
            ".interactiveDismissDisabled(model.isSubmitting)",
            "Button(\"Next\") { _ = model.next() }",
            "Task { await model.submit() }",
            "Button(\"Done\") { onDone() }",
            "model.setCategory(categoryId, selected: selected)",
            "model.setAllocationText(rawValue, for: categoryId)",
            "Synchronization status unavailable",
            "Do not create a duplicate",
        ] {
            #expect(setupView.contains(required), "Missing SwiftUI contract token: \(required)")
        }
        for required in [
            "target-project-add",
            "projectSetup.beginDraft()",
            ".sheet(isPresented: $isProjectSetupPresented)",
            "ProjectSetupStagingExerciseView(",
        ] {
            #expect(browserView.contains(required), "Missing directory route token: \(required)")
        }
    }

    @Test("Independent streams preserve readiness and apply category defaults once")
    func independentStreamsAndHonestReadiness() async throws {
        let clients = ControlledStream<ClientListSnapshot>()
        let categories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let setup = SetupProbe()
        let model = try Self.model()
        await model.start(runtime: Self.runtime(clients, categories, setup))

        categories.yield(try Self.categorySnapshot(quality: .partial, complete: false))
        await Self.waitUntil { model.categoryStatus == "partial • incomplete" }
        #expect(model.clients.isEmpty)
        #expect(model.selectedClientId == nil)
        #expect(model.selectedCategoryIds == Set(model.categories.map(\.id)))
        #expect(!model.canSubmit)

        clients.yield(try Self.clientSnapshot(quality: .stale, complete: false))
        await Self.waitUntil { model.clients.count == 2 }
        #expect(model.clientStatus == "stale • incomplete")
        #expect(model.categories.map(\.id.rawValue) == ["category-alpha", "category-beta"])
        #expect(model.selectedClientId == nil)
        #expect(model.selectedCategoryIds == Set(model.categories.map(\.id)))

        clients.yield(try Self.clientSnapshot(rows: [], quality: .partial, complete: false))
        categories.yield(try Self.categorySnapshot(rows: [], quality: .partial, complete: false))
        await Self.waitUntil { model.clients.isEmpty && model.categories.isEmpty }
        #expect(model.clientStatus == "partial • incomplete")
        #expect(model.categoryStatus == "partial • incomplete")
        #expect(model.selectedCategoryIds.count == 2)

        clients.yield(try Self.clientSnapshot(rows: [], quality: .ready, complete: true))
        categories.yield(try Self.categorySnapshot(rows: [], quality: .ready, complete: true))
        await Self.waitUntil {
            model.clientStatus == "ready • authoritative empty" &&
                model.categoryStatus == "ready • authoritative empty"
        }
        #expect(!model.canSubmit)
        await model.stop()

        let reverseClients = ControlledStream<ClientListSnapshot>()
        let reverseCategories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let reverse = try Self.model()
        await reverse.start(runtime: Self.runtime(reverseClients, reverseCategories, setup))
        reverseClients.yield(try Self.clientSnapshot(quality: .partial, complete: false))
        await Self.waitUntil { reverse.clients.count == 2 }
        #expect(!reverse.canSubmit)
        reverseCategories.yield(try Self.categorySnapshot(quality: .stale, complete: false))
        await Self.waitUntil { reverse.categories.count == 2 }
        reverse.projectName = "Reverse Arrival"
        reverse.selectedClientId = reverse.clients[0].id
        #expect(reverse.canAdvance)
        #expect(!reverse.canSubmit)
        #expect(reverse.clientStatus == "partial • incomplete")
        #expect(reverse.categoryStatus == "stale • incomplete")
        await reverse.stop()
    }

    @Test("Represented stale choices submit exact nil, zero, and positive allocations")
    func exactSelectionAndSubmission() async throws {
        let clients = ControlledStream<ClientListSnapshot>()
        let categories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let setup = SetupProbe(responses: [.receipt(.queued), .receipt(.applied)])
        let identities = IdentitySequence()
        let model = try Self.model(identities: identities)
        await model.start(runtime: Self.runtime(clients, categories, setup))
        categories.yield(try Self.categorySnapshot(quality: .stale, complete: false))
        clients.yield(try Self.clientSnapshot(quality: .partial, complete: false))
        await Self.waitUntil { model.clients.count == 2 && model.categories.count == 2 }

        model.projectName = "Project One"
        model.projectDescription = "  Useful description  "
        model.selectedClientId = model.clients[1].id
        #expect(Self.advanceToBudget(model))
        #expect(model.canSubmit)
        await model.submit()

        var calls = await setup.commands()
        #expect(calls.count == 1)
        #expect(calls[0].draft.clientSelection == .existing(model.clients[1].id))
        #expect(calls[0].draft.accountId == Self.accountId)
        #expect(calls[0].draft.actorPrincipalId == Self.principalId)
        #expect(calls[0].draft.operationContractVersion.rawValue == "project-create-v1")
        #expect(calls[0].draft.description == "Useful description")
        #expect(calls[0].draft.categoryAllocations.map(\.categoryId.rawValue) == [
            "category-alpha", "category-beta"
        ])
        #expect(calls[0].draft.categoryAllocations.allSatisfy { $0.allocation == nil })
        #expect(model.receiptState == "queued")
        #expect(model.receiptExplanation == "queued — accepted locally; not yet synchronized")

        #expect(!model.setAllocation(
            Money(minorUnits: 0, currency: model.accountCurrency),
            for: model.categories[0].id
        ))
        #expect(!model.setAllocation(
            Money(minorUnits: 12_345, currency: model.accountCurrency),
            for: model.categories[1].id
        ))
        model.projectName = "Must not replace accepted draft"
        await model.submit()
        calls = await setup.commands()
        #expect(calls.count == 1)
        #expect(model.projectName == "Project One")

        model.beginDraft()
        model.projectName = "Project Two"
        model.selectedClientId = model.clients[1].id
        #expect(model.setAllocation(
            Money(minorUnits: 0, currency: model.accountCurrency),
            for: model.categories[0].id
        ))
        #expect(model.setAllocation(
            Money(minorUnits: 12_345, currency: model.accountCurrency),
            for: model.categories[1].id
        ))
        #expect(Self.advanceToBudget(model))
        await model.submit()
        calls = await setup.commands()
        #expect(calls.count == 2)
        #expect(calls[1].draft.categoryAllocations.map(\.categoryId.rawValue) == [
            "category-alpha", "category-beta"
        ])
        #expect(calls[1].draft.categoryAllocations[0].allocation == Money(
            minorUnits: 0,
            currency: model.accountCurrency
        ))
        #expect(calls[1].draft.categoryAllocations[1].allocation == Money(
            minorUnits: 12_345,
            currency: model.accountCurrency
        ))
        await model.stop()
    }

    @Test("Three steps guard navigation and preserve later category choices")
    func navigationAndOneTimeDefaults() async throws {
        let clients = ControlledStream<ClientListSnapshot>()
        let categories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let model = try Self.model()
        await model.start(runtime: Self.runtime(clients, categories, SetupProbe()))

        clients.yield(try Self.clientSnapshot())
        categories.yield(try Self.categorySnapshot(rows: [], quality: .partial, complete: false))
        await Self.waitUntil { model.clients.count == 2 && model.categoryStatus == "partial • incomplete" }
        #expect(model.currentStep == .basicInfo)
        #expect(model.stepIndex == 1)
        #expect(model.stepTitle == "Basic information")
        #expect(!model.canGoBack)
        #expect(!model.next())

        model.projectName = "Three Step Project"
        model.selectedClientId = model.clients[1].id
        #expect(model.next())
        #expect(model.currentStep == .categorySelection)
        #expect(!model.canAdvance)

        categories.yield(try Self.categorySnapshot(quality: .partial, complete: false))
        await Self.waitUntil { model.categories.count == 2 }
        #expect(model.selectedCategoryIds == Set(model.categories.map(\.id)))
        model.setCategory(model.categories[0].id, selected: false)

        categories.yield(try Self.categorySnapshot(rows: [
            try Self.category("category-alpha", "Alpha", order: 1),
            try Self.category("category-beta", "Beta", order: 2),
            try Self.category("category-gamma", "Gamma", order: 3),
        ]))
        await Self.waitUntil { model.categories.count == 3 }
        #expect(model.selectedCategoryIds.map(\.rawValue).sorted() == ["category-beta"])
        #expect(model.next())
        #expect(model.currentStep == .budgetAmounts)
        #expect(!model.canAdvance)
        #expect(model.canSubmit)
        #expect(model.back())
        #expect(model.back())
        #expect(model.currentStep == .basicInfo)
        #expect(!model.back())
        await model.stop()
    }

    @Test("Allocations preserve nil, zero, positive, currency, and draft reset")
    func exactAccountCurrencyAllocationsAndReset() async throws {
        let clients = ControlledStream<ClientListSnapshot>()
        let categories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let setup = SetupProbe()
        let cad = try CurrencyCode(validating: "CAD")
        let model = try Self.model(currency: cad)
        await model.start(runtime: Self.runtime(clients, categories, setup))
        clients.yield(try Self.clientSnapshot())
        categories.yield(try Self.categorySnapshot())
        await Self.waitUntil { model.clients.count == 2 && model.categories.count == 2 }
        model.projectName = "Exact Budget"
        model.projectDescription = "Retain me"
        model.selectedClientId = model.clients[0].id

        let alpha = model.categories[0].id
        let beta = model.categories[1].id
        #expect(model.allocation(for: alpha) == nil)
        #expect(model.setAllocationText("   ", for: alpha))
        #expect(model.allocation(for: alpha) == nil)
        #expect(model.setAllocationText("0", for: alpha))
        #expect(model.allocation(for: alpha) == .zero(currency: cad))
        #expect(model.setAllocationText("$1,234.56", for: beta))
        #expect(model.allocation(for: beta) == Money(minorUnits: 123_456, currency: cad))
        #expect(!model.setAllocationText(".", for: beta))
        #expect(model.invalidAllocationIds == [beta])
        #expect(model.allocation(for: beta) == nil)
        #expect(model.setAllocation(.zero(currency: cad), for: alpha))
        #expect(model.setAllocation(Money(minorUnits: 999, currency: cad), for: beta))
        #expect(model.allocationText(for: alpha) == "0.00")
        #expect(model.allocationText(for: beta) == "9.99")
        #expect(model.invalidAllocationIds.isEmpty)
        #expect(!model.setAllocation(
            Money(minorUnits: 1, currency: try CurrencyCode(validating: "USD")),
            for: beta
        ))
        #expect(!model.setAllocation(Money(minorUnits: -1, currency: cad), for: beta))
        #expect(Self.advanceToBudget(model))
        await model.submit()

        let command = try #require(await setup.commands().first)
        #expect(command.draft.categoryAllocations[0].allocation == .zero(currency: cad))
        #expect(command.draft.categoryAllocations[1].allocation == Money(
            minorUnits: 999,
            currency: cad
        ))

        model.beginDraft()
        #expect(model.currentStep == .basicInfo)
        #expect(model.projectName.isEmpty)
        #expect(model.projectDescription.isEmpty)
        #expect(model.selectedClientId == nil)
        #expect(model.selectedCategoryIds == Set(model.categories.map(\.id)))
        #expect(model.budgetAllocations.isEmpty)
        #expect(model.budgetAllocationText.isEmpty)
        #expect(model.invalidAllocationIds.isEmpty)
        #expect(model.receipt == nil)
        #expect(model.diagnostic == nil)
        await model.stop()
    }

    @Test("Removed choices are pruned and invalid input never dispatches")
    func pruningAndInvalidSubmission() async throws {
        let clients = ControlledStream<ClientListSnapshot>()
        let categories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let setup = SetupProbe()
        let model = try Self.model()
        await model.start(runtime: Self.runtime(clients, categories, setup))
        clients.yield(try Self.clientSnapshot())
        categories.yield(try Self.categorySnapshot())
        await Self.waitUntil { model.clients.count == 2 && model.categories.count == 2 }
        model.selectedClientId = model.clients[0].id
        model.setCategory(model.categories[0].id, selected: true)
        model.setCategory(model.categories[1].id, selected: false)
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

        await model.stop()
    }

    @Test("Invalid newer Client or category evidence invalidates the prior preparation")
    func invalidNewerEvidenceFailsClosed() async throws {
        let clients = ControlledStream<ClientListSnapshot>()
        let categories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let setup = SetupProbe()
        let model = try Self.model()
        await model.start(runtime: Self.runtime(clients, categories, setup))
        clients.yield(try Self.clientSnapshot())
        categories.yield(try Self.categorySnapshot())
        await Self.waitUntil { model.clients.count == 2 && model.categories.count == 2 }
        model.projectName = "Retained typed input"
        model.selectedClientId = model.clients[0].id
        #expect(model.canAdvance)

        clients.yield(try Self.crossAccountClientSnapshot())
        await Self.waitUntil { model.clientStatus == "blocked • completeness unknown" }
        #expect(model.clients.isEmpty)
        #expect(model.selectedClientId?.rawValue == "client-one")
        #expect(model.projectName == "Retained typed input")
        #expect(!model.canSubmit)
        await model.submit()
        #expect(await setup.commands().isEmpty)

        clients.yield(try Self.clientSnapshot())
        await Self.waitUntil { model.clients.count == 2 }
        model.selectedClientId = model.clients[0].id
        #expect(model.canAdvance)
        categories.yield(try Self.crossAccountCategorySnapshot())
        await Self.waitUntil { model.categoryStatus == "blocked • completeness unknown" }
        #expect(model.categories.isEmpty)
        #expect(model.selectedCategoryIds.count == 2)
        #expect(!model.canSubmit)
        await model.submit()
        #expect(await setup.commands().isEmpty)

        categories.yield(try Self.categorySnapshot())
        await Self.waitUntil { model.categories.count == 2 }
        model.selectedClientId = model.clients[0].id
        #expect(model.canAdvance)
        categories.finish(throwing: StreamProbeFailure.upstream)
        await Self.waitUntil { model.categoryStatus == "blocked • completeness unknown" }
        #expect(!model.canSubmit)
        #expect(model.projectName == "Retained typed input")
        #expect(await setup.commands().isEmpty)
        await model.stop()
    }

    @Test("Simultaneous submission dispatches once and ambiguous retry preserves identities")
    func singleDispatchAndStableRetryIdentity() async throws {
        let clients = ControlledStream<ClientListSnapshot>()
        let categories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let setup = SetupProbe(responses: [.suspendedFailure, .receipt(.queued)])
        let identities = IdentitySequence()
        let clock = AdvancingClock()
        let model = try Self.model(identities: identities, clock: clock)
        await model.start(runtime: Self.runtime(clients, categories, setup))
        clients.yield(try Self.clientSnapshot())
        categories.yield(try Self.categorySnapshot())
        await Self.waitUntil { model.clients.count == 2 && model.categories.count == 2 }
        model.projectName = "Retry Project"
        model.selectedClientId = model.clients[0].id
        #expect(Self.advanceToBudget(model))

        let first = Task { await model.submit() }
        let didSuspend = await Self.waitUntilAsync { await setup.isSuspended() }
        #expect(didSuspend)
        guard didSuspend else {
            first.cancel()
            await setup.resumeSuspension()
            await first.value
            await model.stop()
            return
        }
        await model.submit()
        #expect(await setup.commands().count == 1)
        await setup.resumeSuspension()
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
        await model.stop()
    }

    @Test("An admitted submission freezes its draft and reports the immutable accepted payload")
    func submissionFreezesImmutableDraft() async throws {
        let clients = ControlledStream<ClientListSnapshot>()
        let categories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let operations = ControlledStream<OperationSnapshot>()
        let setup = SetupProbe(responses: [.suspendedReceipt(.queued)])
        let model = try Self.model()
        await model.start(runtime: Self.runtime(
            clients,
            categories,
            setup,
            operations: operations
        ))
        clients.yield(try Self.clientSnapshot())
        categories.yield(try Self.categorySnapshot())
        await Self.waitUntil { model.clients.count == 2 && model.categories.count == 2 }
        model.projectName = "Frozen Project"
        model.projectDescription = "Original description"
        model.selectedClientId = model.clients[0].id
        let selectedCategory = model.categories[0].id
        #expect(model.setAllocationText("123.45", for: selectedCategory))
        #expect(Self.advanceToBudget(model))

        let submission = Task { @MainActor in await model.submit() }
        let didSuspend = await Self.waitUntilAsync { await setup.isSuspended() }
        #expect(didSuspend)
        guard didSuspend else {
            submission.cancel()
            await setup.resumeSuspension()
            await submission.value
            await model.stop()
            return
        }

        #expect(model.isDraftLocked)
        model.projectName = "Wrong Project"
        model.projectDescription = "Wrong description"
        model.selectedClientId = model.clients[1].id
        model.setCategory(selectedCategory, selected: false)
        #expect(!model.setAllocationText("999", for: selectedCategory))
        #expect(model.projectName == "Frozen Project")
        #expect(model.projectDescription == "Original description")
        #expect(model.selectedClientId == model.clients[0].id)
        #expect(model.selectedCategoryIds.contains(selectedCategory))
        #expect(model.allocation(for: selectedCategory)?.minorUnits == 12_345)

        await setup.resumeSuspension()
        await submission.value
        let summary = try #require(model.submittedProject)
        #expect(summary.projectName == "Frozen Project")
        #expect(summary.projectDescription == "Original description")
        #expect(summary.clientId == model.clients[0].id)
        #expect(summary.categories.first(where: { $0.id == selectedCategory })?.allocation?.minorUnits == 12_345)
        #expect(model.isDraftLocked)
        await model.stop()
    }

    @Test("Queued creation follows applying and rejection, then retries with a new identity")
    func queuedOperationTransitionsToRecoverableRejection() async throws {
        let clients = ControlledStream<ClientListSnapshot>()
        let categories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let operations = ControlledStream<OperationSnapshot>()
        let setup = SetupProbe(responses: [.receipt(.queued), .receipt(.queued)])
        let identities = IdentitySequence()
        let model = try Self.model(identities: identities)
        await model.start(runtime: Self.runtime(
            clients,
            categories,
            setup,
            operations: operations
        ))
        clients.yield(try Self.clientSnapshot())
        categories.yield(try Self.categorySnapshot())
        await Self.waitUntil { model.clients.count == 2 && model.categories.count == 2 }
        model.projectName = "Observed Project"
        model.selectedClientId = model.clients[0].id
        #expect(Self.advanceToBudget(model))
        await model.submit()

        let first = try #require((await setup.commands()).first)
        operations.yield(Self.operationSnapshot(
            command: first,
            state: .applying(attempt: 1, startedAt: Self.timestamp.addingTimeInterval(1)),
            updatedAt: Self.timestamp.addingTimeInterval(1)
        ))
        await Self.waitUntil { model.receiptState == "applying" }
        #expect(model.isDraftLocked)

        operations.yield(Self.operationSnapshot(
            command: first,
            state: .rejected(Self.operationRejection()),
            updatedAt: Self.timestamp.addingTimeInterval(2)
        ))
        await Self.waitUntil { model.receiptState == "rejected" }
        #expect(model.diagnostic == "project_setup_operation_rejected")
        #expect(!model.isDraftLocked)
        #expect(model.projectName == "Observed Project")
        #expect(model.canSubmit)

        await model.submit()
        let calls = await setup.commands()
        #expect(calls.count == 2)
        #expect(calls[1].envelope.operationId != calls[0].envelope.operationId)
        #expect(calls[1].draft.projectId != calls[0].draft.projectId)
        #expect(identities.allocationCount == 2)
        await model.stop()
    }

    @Test("Mismatched operation evidence fails closed")
    func mismatchedOperationEvidenceFailsClosed() async throws {
        let clients = ControlledStream<ClientListSnapshot>()
        let categories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let operations = ControlledStream<OperationSnapshot>()
        let setup = SetupProbe()
        let model = try Self.model()
        await model.start(runtime: Self.runtime(
            clients,
            categories,
            setup,
            operations: operations
        ))
        clients.yield(try Self.clientSnapshot())
        categories.yield(try Self.categorySnapshot())
        await Self.waitUntil { model.clients.count == 2 && model.categories.count == 2 }
        model.projectName = "Evidence Project"
        model.selectedClientId = model.clients[0].id
        #expect(Self.advanceToBudget(model))
        await model.submit()
        let command = try #require((await setup.commands()).first)
        operations.yield(OperationSnapshot(
            operationId: try OperationID(validating: "wrong-operation"),
            accountId: command.envelope.accountId,
            contractVersion: command.envelope.contractVersion,
            fingerprint: command.fingerprint,
            acceptedAt: Self.timestamp,
            updatedAt: Self.timestamp,
            state: .queued(attemptCount: 0, lastTransientError: nil)
        ))
        await Self.waitUntil {
            model.diagnostic == "project_setup_operation_evidence_invalid"
        }
        #expect(model.receiptState == "queued")
        #expect(model.isDraftLocked)
        #expect(model.hasPostAcceptanceObservationIssue)
        await model.stop()
    }

    @Test("Reference-stream failures after acceptance never revoke or contradict acceptance")
    func referenceFailuresAfterAcceptanceRemainStatusIssues() async throws {
        let clients = ControlledStream<ClientListSnapshot>()
        let categories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let operations = ControlledStream<OperationSnapshot>()
        let setup = SetupProbe()
        let model = try Self.model()
        await model.start(runtime: Self.runtime(
            clients,
            categories,
            setup,
            operations: operations
        ))
        clients.yield(try Self.clientSnapshot())
        categories.yield(try Self.categorySnapshot())
        await Self.waitUntil { model.clients.count == 2 && model.categories.count == 2 }
        model.projectName = "Accepted Before Reference Failure"
        model.selectedClientId = model.clients[0].id
        #expect(Self.advanceToBudget(model))
        await model.submit()
        #expect(model.receiptState == "queued")

        clients.finish(throwing: StreamProbeFailure.upstream)
        await Self.waitUntil { model.diagnostic == "project_setup_clients_local_failed" }
        #expect(model.isAcceptedProjectReceipt)
        #expect(model.hasPostAcceptanceObservationIssue)

        categories.finish(throwing: StreamProbeFailure.upstream)
        await Self.waitUntil { model.diagnostic == "project_setup_categories_local_failed" }
        #expect(model.isAcceptedProjectReceipt)
        #expect(model.hasPostAcceptanceObservationIssue)
        await model.stop()
    }

    @Test("Queued creation reaches applied through the AppModel observer")
    func queuedOperationReachesApplied() async throws {
        let clients = ControlledStream<ClientListSnapshot>()
        let categories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let operations = ControlledStream<OperationSnapshot>()
        let setup = SetupProbe()
        let model = try Self.model()
        await model.start(runtime: Self.runtime(
            clients,
            categories,
            setup,
            operations: operations
        ))
        clients.yield(try Self.clientSnapshot())
        categories.yield(try Self.categorySnapshot())
        await Self.waitUntil { model.clients.count == 2 && model.categories.count == 2 }
        model.projectName = "Applied Project"
        model.selectedClientId = model.clients[0].id
        #expect(Self.advanceToBudget(model))
        await model.submit()

        let command = try #require((await setup.commands()).first)
        operations.yield(Self.operationSnapshot(
            command: command,
            state: .applied(Self.operationApplied()),
            updatedAt: Self.timestamp.addingTimeInterval(1)
        ))
        await Self.waitUntil { model.receiptState == "applied" }
        #expect(model.diagnostic == nil)
        #expect(model.isAcceptedProjectReceipt)
        #expect(!model.hasPostAcceptanceObservationIssue)

        model.beginDraft()
        operations.yield(Self.operationSnapshot(
            command: command,
            state: .rejected(Self.operationRejection()),
            updatedAt: Self.timestamp.addingTimeInterval(2)
        ))
        await Task.yield()
        #expect(model.receipt == nil)
        #expect(model.diagnostic == nil)
        await model.stop()
    }

    @Test("Restart drains an active operation observer and ignores its stale generation")
    func restartDrainsOperationObserverAndIgnoresStaleGeneration() async throws {
        let oldClients = ControlledStream<ClientListSnapshot>()
        let oldCategories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let oldOperations = ControlledStream<OperationSnapshot>()
        let newClients = ControlledStream<ClientListSnapshot>()
        let newCategories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let newOperations = ControlledStream<OperationSnapshot>()
        let setup = SetupProbe()
        let model = try Self.model()

        await model.start(runtime: Self.runtime(
            oldClients,
            oldCategories,
            setup,
            operations: oldOperations
        ))
        oldClients.yield(try Self.clientSnapshot())
        oldCategories.yield(try Self.categorySnapshot())
        await Self.waitUntil { model.clients.count == 2 && model.categories.count == 2 }
        model.projectName = "Old Project"
        model.selectedClientId = model.clients[0].id
        #expect(Self.advanceToBudget(model))
        await model.submit()
        let command = try #require((await setup.commands()).first)
        oldOperations.yield(Self.operationSnapshot(
            command: command,
            state: .applying(attempt: 1, startedAt: Self.timestamp.addingTimeInterval(1)),
            updatedAt: Self.timestamp.addingTimeInterval(1)
        ))
        await Self.waitUntil { model.receiptState == "applying" }

        await model.start(runtime: Self.runtime(
            newClients,
            newCategories,
            setup,
            operations: newOperations
        ))
        #expect(oldOperations.isCancelled())
        #expect(model.receipt == nil)
        #expect(model.submittedProject == nil)

        oldOperations.yield(Self.operationSnapshot(
            command: command,
            state: .applied(Self.operationApplied()),
            updatedAt: Self.timestamp.addingTimeInterval(2)
        ))
        await Task.yield()
        #expect(model.receipt == nil)
        #expect(model.diagnostic == nil)

        newClients.yield(try Self.clientSnapshot(rows: [try Self.client("client-two", "Client Two")]))
        newCategories.yield(try Self.categorySnapshot(rows: [
            try Self.category("category-beta", "Beta", order: 2)
        ]))
        await Self.waitUntil { model.clients.count == 1 && model.categories.count == 1 }
        #expect(model.clients.map(\.id.rawValue) == ["client-two"])
        #expect(model.categories.map(\.id.rawValue) == ["category-beta"])
        await model.stop()
    }

    @Test(arguments: LocalOperationState.allCases)
    func everyReceiptStateIsExact(_ state: LocalOperationState) async throws {
        let clients = ControlledStream<ClientListSnapshot>()
        let categories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let setup = SetupProbe(responses: [.receipt(state)])
        let model = try Self.model()
        await model.start(runtime: Self.runtime(clients, categories, setup))
        clients.yield(try Self.clientSnapshot())
        categories.yield(try Self.categorySnapshot())
        await Self.waitUntil { model.clients.count == 2 && model.categories.count == 2 }
        model.projectName = "Receipt Project"
        model.selectedClientId = model.clients[0].id
        #expect(Self.advanceToBudget(model))
        await model.submit()
        #expect(model.receiptState == state.rawValue)
        #expect(model.receiptOperationId == "operation-1")
        #expect(model.isAcceptedProjectReceipt == [.queued, .applying, .applied].contains(state))
        #expect(model.projectName == "Receipt Project")
        await model.stop()
    }

    @Test("Cancellation is bounded, retains input, and never reports success")
    func cancellationRetainsInput() async throws {
        let clients = ControlledStream<ClientListSnapshot>()
        let categories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let setup = SetupProbe(responses: [.cancellation, .receipt(.queued)])
        let clock = AdvancingClock()
        let model = try Self.model(clock: clock)
        await model.start(runtime: Self.runtime(clients, categories, setup))
        clients.yield(try Self.clientSnapshot())
        categories.yield(try Self.categorySnapshot())
        await Self.waitUntil { model.clients.count == 2 && model.categories.count == 2 }
        model.projectName = "Retain after cancellation"
        model.projectDescription = "Still here"
        model.selectedClientId = model.clients[0].id
        let retainedCategory = model.categories[0].id
        let retainedAllocation = Money(minorUnits: 4_321, currency: model.accountCurrency)
        #expect(model.setAllocation(retainedAllocation, for: retainedCategory))
        #expect(Self.advanceToBudget(model))
        await model.submit()
        #expect(model.diagnostic == "project_setup_cancelled")
        #expect(model.receipt == nil)
        #expect(model.projectName == "Retain after cancellation")
        #expect(model.projectDescription == "Still here")
        #expect(model.selectedClientId == model.clients[0].id)
        #expect(model.selectedCategoryIds.contains(retainedCategory))
        #expect(model.allocation(for: retainedCategory) == retainedAllocation)
        #expect(!model.isSubmitting)
        await model.submit()
        let calls = await setup.commands()
        #expect(calls.count == 2)
        #expect(calls[0] == calls[1])
        #expect(clock.readCount == 1)
        #expect(model.receiptState == "queued")
        await model.stop()
    }

    @Test("Caller cancellation rejects a late success from a noncooperative dependency")
    func callerCancellationRejectsLateSuccess() async throws {
        let clients = ControlledStream<ClientListSnapshot>()
        let categories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let setup = SetupProbe(responses: [.suspendedReceipt(.queued)])
        let model = try Self.model()
        await model.start(runtime: Self.runtime(clients, categories, setup))
        clients.yield(try Self.clientSnapshot())
        categories.yield(try Self.categorySnapshot())
        await Self.waitUntil { model.clients.count == 2 && model.categories.count == 2 }
        model.projectName = "Cancelled late success"
        model.selectedClientId = model.clients[0].id
        #expect(Self.advanceToBudget(model))

        let completion = CompletionProbe()
        let submission = Task { @MainActor in
            await model.submit()
            await completion.mark()
        }
        let didSuspend = await Self.waitUntilAsync { await setup.isSuspended() }
        #expect(didSuspend)
        guard didSuspend else {
            submission.cancel()
            await setup.resumeSuspension()
            await submission.value
            await model.stop()
            return
        }

        submission.cancel()
        #expect(!(await completion.value))
        await setup.resumeSuspension()
        await submission.value

        #expect(await completion.value)
        #expect(model.receipt == nil)
        #expect(model.diagnostic == "project_setup_cancelled")
        #expect(model.projectName == "Cancelled late success")
        #expect(!model.isSubmitting)
        await model.stop()
    }

    @Test("Typed form and operation failures remain bounded and dispatch honestly")
    func typedFailuresAreBounded() async throws {
        let formClients = ControlledStream<ClientListSnapshot>()
        let formCategories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let formSetup = SetupProbe()
        let formModel = ProjectSetupStagingExercise(
            accountId: Self.accountId,
            accountCurrency: try CurrencyCode(validating: "USD"),
            actorPrincipalId: Self.principalId,
            operationContractVersion: try OperationContractVersion(
                validating: "project-create-v1"
            ),
            makeIdentity: { throw ProjectSetupFormFailure.invalidSelectionFingerprint },
            now: { Self.timestamp }
        )
        await formModel.start(runtime: Self.runtime(formClients, formCategories, formSetup))
        formClients.yield(try Self.clientSnapshot())
        formCategories.yield(try Self.categorySnapshot())
        await Self.waitUntil { formModel.clients.count == 2 && formModel.categories.count == 2 }
        formModel.projectName = "Form Failure"
        formModel.selectedClientId = formModel.clients[0].id
        #expect(Self.advanceToBudget(formModel))
        await formModel.submit()
        #expect(formModel.diagnostic == "project_setup_form_selection_fingerprint_invalid")
        #expect(await formSetup.commands().isEmpty)
        await formModel.stop()

        let operationClients = ControlledStream<ClientListSnapshot>()
        let operationCategories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let operationSetup = SetupProbe(responses: [.receiptMismatch])
        let operationModel = try Self.model()
        await operationModel.start(runtime: Self.runtime(
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
        #expect(Self.advanceToBudget(operationModel))
        await operationModel.submit()
        #expect(operationModel.diagnostic == "project_setup_receipt_mismatch")
        #expect(operationModel.receipt == nil)
        #expect(await operationSetup.commands().count == 1)
        await operationModel.stop()
    }

    @Test("Stop drains both streams and prevents late mutation")
    func stopDrainsStreamsAndPreventsMutation() async throws {
        let clients = ControlledStream<ClientListSnapshot>()
        let categories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let setup = SetupProbe()
        let model = try Self.model()
        await model.start(runtime: Self.runtime(clients, categories, setup))
        clients.yield(try Self.clientSnapshot())
        categories.yield(try Self.categorySnapshot())
        await Self.waitUntil { model.clients.count == 2 && model.categories.count == 2 }
        model.projectName = "Retained"
        await model.stop()
        #expect(clients.isCancelled())
        #expect(categories.isCancelled())
        clients.yield(try Self.clientSnapshot(rows: []))
        categories.yield(try Self.categorySnapshot(rows: []))
        await Task.yield()
        #expect(model.clients.count == 2)
        #expect(model.categories.count == 2)
        #expect(model.projectName == "Retained")
        #expect(!model.canSubmit)
    }

    @Test("Restart drains prior streams before activating replacement evidence")
    func restartDrainsPriorStreamsBeforeReplacement() async throws {
        let oldClients = ControlledStream<ClientListSnapshot>()
        let oldCategories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let newClients = ControlledStream<ClientListSnapshot>()
        let newCategories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let setup = SetupProbe()
        let model = try Self.model()

        await model.start(runtime: Self.runtime(oldClients, oldCategories, setup))
        oldClients.yield(try Self.clientSnapshot())
        oldCategories.yield(try Self.categorySnapshot())
        await Self.waitUntil { model.clients.count == 2 && model.categories.count == 2 }

        await model.start(runtime: Self.runtime(newClients, newCategories, setup))
        #expect(oldClients.isCancelled())
        #expect(oldCategories.isCancelled())
        #expect(model.clients.isEmpty)
        #expect(model.categories.isEmpty)

        oldClients.yield(try Self.clientSnapshot())
        oldCategories.yield(try Self.categorySnapshot())
        newClients.yield(try Self.clientSnapshot(rows: [try Self.client("client-two", "Client Two")]))
        newCategories.yield(try Self.categorySnapshot(rows: [
            try Self.category("category-beta", "Beta", order: 2)
        ]))
        await Self.waitUntil { model.clients.count == 1 && model.categories.count == 1 }
        #expect(model.clients.map(\.id.rawValue) == ["client-two"])
        #expect(model.categories.map(\.id.rawValue) == ["category-beta"])

        await model.stop()
        #expect(newClients.isCancelled())
        #expect(newCategories.isCancelled())
    }

    @Test("Concurrent stop and restart share drainage with an admitted submission")
    func concurrentStopAndRestartDrainSubmission() async throws {
        let oldClients = ControlledStream<ClientListSnapshot>()
        let oldCategories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let newClients = ControlledStream<ClientListSnapshot>()
        let newCategories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let setup = SetupProbe(responses: [.suspendedReceipt(.queued)])
        let model = try Self.model()

        await model.start(runtime: Self.runtime(oldClients, oldCategories, setup))
        oldClients.yield(try Self.clientSnapshot())
        oldCategories.yield(try Self.categorySnapshot())
        await Self.waitUntil { model.clients.count == 2 && model.categories.count == 2 }
        model.projectName = "Drain before restart"
        model.selectedClientId = model.clients[0].id
        #expect(Self.advanceToBudget(model))

        let submission = Task { @MainActor in await model.submit() }
        let didSuspend = await Self.waitUntilAsync { await setup.isSuspended() }
        #expect(didSuspend)
        guard didSuspend else {
            submission.cancel()
            await setup.resumeSuspension()
            await submission.value
            await model.stop()
            return
        }

        let stopLifecycle = LifecycleCallProbe()
        let stop = Task { @MainActor in
            stopLifecycle.markEntered()
            await model.stop()
            stopLifecycle.markCompleted()
        }
        #expect(await Self.waitUntilAsync {
            let entered = await MainActor.run { stopLifecycle.entered }
            return entered && oldClients.isCancelled() && oldCategories.isCancelled()
        })

        let restartLifecycle = LifecycleCallProbe()
        let restart = Task { @MainActor in
            restartLifecycle.markEntered()
            await model.start(runtime: Self.runtime(newClients, newCategories, setup))
            restartLifecycle.markCompleted()
        }
        #expect(await Self.waitUntilAsync {
            await MainActor.run { restartLifecycle.entered }
        })
        #expect(!stopLifecycle.completed)
        #expect(!restartLifecycle.completed)

        await setup.resumeSuspension()
        await submission.value
        await stop.value
        await restart.value
        #expect(stopLifecycle.completed)
        #expect(restartLifecycle.completed)
        #expect(model.diagnostic == nil)
        #expect(model.receipt == nil)

        newClients.yield(try Self.clientSnapshot(rows: [try Self.client("client-two", "Client Two")]))
        newCategories.yield(try Self.categorySnapshot(rows: []))
        await Self.waitUntil {
            model.clients.map(\.id.rawValue) == ["client-two"] &&
                model.categoryStatus == "ready • authoritative empty"
        }
        await model.stop()
    }

    @Test("Concurrent starts share drainage and only the latest runtime activates")
    func concurrentStartsShareDrainage() async throws {
        let oldClients = ControlledStream<ClientListSnapshot>()
        let oldCategories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let firstClients = ControlledStream<ClientListSnapshot>()
        let firstCategories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let latestClients = ControlledStream<ClientListSnapshot>()
        let latestCategories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let firstActivation = RuntimeActivationProbe()
        let latestActivation = RuntimeActivationProbe()
        let setup = SetupProbe(responses: [.suspendedReceipt(.queued)])
        let model = try Self.model()

        await model.start(runtime: Self.runtime(oldClients, oldCategories, setup))
        oldClients.yield(try Self.clientSnapshot())
        oldCategories.yield(try Self.categorySnapshot())
        await Self.waitUntil { model.clients.count == 2 && model.categories.count == 2 }
        model.projectName = "Drain before two starts"
        model.selectedClientId = model.clients[0].id
        #expect(Self.advanceToBudget(model))

        let submission = Task { @MainActor in await model.submit() }
        let didSuspend = await Self.waitUntilAsync { await setup.isSuspended() }
        #expect(didSuspend)
        guard didSuspend else {
            submission.cancel()
            await setup.resumeSuspension()
            await submission.value
            await model.stop()
            return
        }

        let firstLifecycle = LifecycleCallProbe()
        let firstStart = Task { @MainActor in
            firstLifecycle.markEntered()
            await model.start(runtime: Self.runtime(
                firstClients,
                firstCategories,
                setup,
                activation: firstActivation
            ))
            firstLifecycle.markCompleted()
        }
        #expect(await Self.waitUntilAsync {
            let entered = await MainActor.run { firstLifecycle.entered }
            return entered && oldClients.isCancelled() && oldCategories.isCancelled()
        })

        let latestLifecycle = LifecycleCallProbe()
        let latestStart = Task { @MainActor in
            latestLifecycle.markEntered()
            await model.start(runtime: Self.runtime(
                latestClients,
                latestCategories,
                setup,
                activation: latestActivation
            ))
            latestLifecycle.markCompleted()
        }
        #expect(await Self.waitUntilAsync {
            await MainActor.run { latestLifecycle.entered }
        })
        #expect(!firstLifecycle.completed)
        #expect(!latestLifecycle.completed)
        #expect(firstActivation.counts == .zero)
        #expect(latestActivation.counts == .zero)

        await setup.resumeSuspension()
        await submission.value
        await firstStart.value
        await latestStart.value

        #expect(firstLifecycle.completed)
        #expect(latestLifecycle.completed)
        #expect(firstActivation.counts == .zero)
        #expect(latestActivation.counts == .both)
        #expect(model.receipt == nil)
        latestClients.yield(try Self.clientSnapshot(rows: [try Self.client("client-two", "Client Two")]))
        latestCategories.yield(try Self.categorySnapshot(rows: []))
        await Self.waitUntil {
            model.clients.map(\.id.rawValue) == ["client-two"] &&
                model.categoryStatus == "ready • authoritative empty"
        }
        await model.stop()
    }

    @Test("Concurrent stops share drainage and neither returns before admitted work")
    func concurrentStopsShareDrainage() async throws {
        let clients = ControlledStream<ClientListSnapshot>()
        let categories = ControlledStream<BudgetCategoryReferenceSnapshot>()
        let setup = SetupProbe(responses: [.suspendedReceipt(.queued)])
        let model = try Self.model()

        await model.start(runtime: Self.runtime(clients, categories, setup))
        clients.yield(try Self.clientSnapshot())
        categories.yield(try Self.categorySnapshot())
        await Self.waitUntil { model.clients.count == 2 && model.categories.count == 2 }
        model.projectName = "Drain before two stops"
        model.selectedClientId = model.clients[0].id
        #expect(Self.advanceToBudget(model))

        let submission = Task { @MainActor in await model.submit() }
        let didSuspend = await Self.waitUntilAsync { await setup.isSuspended() }
        #expect(didSuspend)
        guard didSuspend else {
            submission.cancel()
            await setup.resumeSuspension()
            await submission.value
            await model.stop()
            return
        }

        let firstLifecycle = LifecycleCallProbe()
        let firstStop = Task { @MainActor in
            firstLifecycle.markEntered()
            await model.stop()
            firstLifecycle.markCompleted()
        }
        #expect(await Self.waitUntilAsync {
            let entered = await MainActor.run { firstLifecycle.entered }
            return entered && clients.isCancelled() && categories.isCancelled()
        })

        let secondLifecycle = LifecycleCallProbe()
        let secondStop = Task { @MainActor in
            secondLifecycle.markEntered()
            await model.stop()
            secondLifecycle.markCompleted()
        }
        #expect(await Self.waitUntilAsync {
            await MainActor.run { secondLifecycle.entered }
        })
        #expect(!firstLifecycle.completed)
        #expect(!secondLifecycle.completed)

        await setup.resumeSuspension()
        await submission.value
        await firstStop.value
        await secondStop.value

        #expect(firstLifecycle.completed)
        #expect(secondLifecycle.completed)
        #expect(model.receipt == nil)
        #expect(model.diagnostic == nil)
        #expect(!model.isSubmitting)
    }

    private static let accountId = try! AccountID(validating: "account-project-setup")
    private static let principalId = try! PrincipalID(validating: "principal-owner")
    private static let timestamp = Date(timeIntervalSince1970: 1_803_000_000)

    private static func advanceToBudget(_ model: ProjectSetupStagingExercise) -> Bool {
        model.next() && model.next() && model.currentStep == .budgetAmounts
    }

    private static func model(
        currency: CurrencyCode = try! CurrencyCode(validating: "USD"),
        identities: IdentitySequence = IdentitySequence(),
        clock: AdvancingClock = AdvancingClock()
    ) throws -> ProjectSetupStagingExercise {
        ProjectSetupStagingExercise(
            accountId: accountId,
            accountCurrency: currency,
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
        _ setup: SetupProbe,
        operations: ControlledStream<OperationSnapshot> = ControlledStream(),
        activation: RuntimeActivationProbe? = nil
    ) -> ProjectSetupStagingRuntime {
        ProjectSetupStagingRuntime(
            watchClients: {
                activation?.markClients()
                return clients.stream
            },
            watchBudgetCategories: {
                activation?.markCategories()
                return categories.stream
            },
            create: { command in try await setup.create(command) },
            watchOperation: { _ in operations.stream }
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

    private static func operationSnapshot(
        command: CreateProjectCommand,
        state: OperationState,
        updatedAt: Date
    ) -> OperationSnapshot {
        OperationSnapshot(
            operationId: command.envelope.operationId,
            accountId: command.envelope.accountId,
            contractVersion: command.envelope.contractVersion,
            fingerprint: command.fingerprint,
            acceptedAt: command.envelope.clientCreatedAt,
            updatedAt: updatedAt,
            state: state
        )
    }

    private static func operationRejection() -> OperationRejection {
        OperationRejection(
            error: ApplicationErrorSummary(
                code: try! ApplicationErrorCode(validating: "project_setup_stale_evidence"),
                category: .conflict,
                retryDisposition: .afterUserCorrection
            ),
            rejectedAt: timestamp.addingTimeInterval(2)
        )
    }

    private static func operationApplied() -> AppliedOperationResult {
        AppliedOperationResult(
            resultCode: try! ApplicationResultCode(validating: "project_created"),
            serverReceivedAt: timestamp.addingTimeInterval(0.5),
            completedAt: timestamp.addingTimeInterval(1),
            affectedRevisions: [
                EntityRevision(
                    entity: LedgerEntityReference(
                        kind: .project,
                        id: try! EntityID(validating: "project-1")
                    ),
                    revision: 1
                )
            ]
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
            cancellation.mark()
        }
    }

    func yield(_ value: Value) { continuation.yield(value) }
    func finish(throwing error: Error) { continuation.finish(throwing: error) }
    func isCancelled() -> Bool { cancellation.value }
}

private enum StreamProbeFailure: Error { case upstream }

private actor CompletionProbe {
    private(set) var value = false

    func mark() {
        value = true
    }
}

@MainActor
private final class LifecycleCallProbe {
    private(set) var entered = false
    private(set) var completed = false

    func markEntered() {
        entered = true
    }

    func markCompleted() {
        completed = true
    }
}

private struct RuntimeActivationCounts: Equatable, Sendable {
    let clients: Int
    let categories: Int

    static let zero = RuntimeActivationCounts(clients: 0, categories: 0)
    static let both = RuntimeActivationCounts(clients: 1, categories: 1)
}

private final class RuntimeActivationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var clientCount = 0
    private var categoryCount = 0

    var counts: RuntimeActivationCounts {
        lock.withLock {
            RuntimeActivationCounts(clients: clientCount, categories: categoryCount)
        }
    }

    func markClients() {
        lock.withLock { clientCount += 1 }
    }

    func markCategories() {
        lock.withLock { categoryCount += 1 }
    }
}

private final class CancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var value: Bool { lock.withLock { cancelled } }

    func mark() {
        lock.withLock { cancelled = true }
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
    case suspendedReceipt(LocalOperationState)
    case cancellation
    case receiptMismatch
}

private enum SetupProbeFailure: Error { case ambiguous }

private actor SetupProbe {
    private var recorded: [CreateProjectCommand] = []
    private var responses: [SetupResponse]
    private var suspended: CheckedContinuation<Void, Never>?
    private var releaseRequested = false

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
            await waitForSuspensionRelease()
            throw SetupProbeFailure.ambiguous
        case .suspendedReceipt(let state):
            await waitForSuspensionRelease()
            return OperationReceipt(operationId: command.envelope.operationId, localState: state)
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

    func resumeSuspension() {
        guard let suspended else {
            releaseRequested = true
            return
        }
        self.suspended = nil
        suspended.resume()
    }

    private func waitForSuspensionRelease() async {
        await withCheckedContinuation { continuation in
            if releaseRequested {
                releaseRequested = false
                continuation.resume()
            } else {
                suspended = continuation
            }
        }
    }
}
