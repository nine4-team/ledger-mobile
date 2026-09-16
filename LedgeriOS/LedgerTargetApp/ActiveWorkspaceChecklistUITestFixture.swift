#if DEBUG
import LedgerTargetAppModel
import LedgerTargetCore
import Observation
import SwiftUI
import UniformTypeIdentifiers
import CryptoKit
import LedgerTargetPowerSync
import Security
#if os(iOS)
import UIKit
#endif

/// Tests the actual entry view with a synthetic protected admission and no Auth
/// session. Its .invalid endpoint and unique Keychain namespace cannot reach or
/// modify Ledger's hosted project. The destination is evidence, not a mock app.
@MainActor
struct OfflineAccountEntryUITestFixture: View {
    let environment: ValidatedLedgerEnvironment
    @State private var prepared = false
    @State private var failure: String?
    @State private var cleanup = false
    private let url = URL(string: "https://offline-entry.invalid")!
    private var fixtureId: String {
        let argument = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--ledger-ui-test-entry-id=") }
        let value = argument.map { String($0.dropFirst("--ledger-ui-test-entry-id=".count)) } ?? ""
        return UUID(uuidString: value)?.uuidString ?? "invalid"
    }
    private var namespace: String { "apps.nine4.ledger.target.ui-entry.\(fixtureId)" }
    private var query: [String: Any] {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(namespace).offline.\(hash)", kSecAttrAccount as String: "admissions"]
    }

    var body: some View {
        ScrollView {
            VStack {
                Text("OFFLINE ENTRY UI TEST • SYNTHETIC ADMISSION")
                if let failure { Text(failure).accessibilityIdentifier("offline-entry-fixture-error") }
                if prepared {
                    TargetOnlineAccountEntryView(environment: environment, makeEntry: {
                        try SupabaseOnlineSignIn(supabaseURL: url, publishableKey: "sb_publishable_fixture",
                            localDataNamespace: namespace, redirectTo: TargetSupabaseConfiguration.callback)
                    }) { selection, entry in
                        AnyView(Text(selection.offlineAdmission != nil && !entry.hasStoredSession
                            && selection.account.id.rawValue == fixtureId ? "Offline selection verified" : "Unexpected selection")
                            .accessibilityIdentifier("offline-entry-selected"))
                    }
                }
                Button("Clear fixture admission") {
                    let status = SecItemDelete(query as CFDictionary)
                    cleanup = status == errSecSuccess || status == errSecItemNotFound
                }.accessibilityIdentifier("offline-entry-cleanup")
                if cleanup { Text("Fixture cleared").accessibilityIdentifier("offline-entry-cleaned") }
            }.padding()
        }
        .task {
            guard !prepared, fixtureId != "invalid" else { return }
            do {
                let user = UUID().uuidString
                let bytes = try JSONSerialization.data(withJSONObject: ["version": 1, "activeUserId": user,
                    "workspaces": [["authorization": ["environment": environment.manifest.environment.rawValue,
                        "authUserId": user, "principalId": "offline-test-\(fixtureId)", "accountId": fixtureId,
                        "role": "employee", "financialAccess": "full"],
                        "account": ["id": fixtureId, "displayName": "Offline Test Account"]]]])
                let status = SecItemAdd(query.merging([kSecValueData as String: bytes,
                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]) { _, new in new } as CFDictionary, nil)
                guard status == errSecSuccess || status == errSecDuplicateItem else {
                    failure = "Fixture Keychain write failed: \(status)"; return
                }
                // Duplicate means the prior app process's admission is reused.
                prepared = true
            } catch { failure = "Fixture preparation failed" }
        }
    }
}

/// A deterministic, in-memory route used only by the staging app's explicit
/// UI-test launch argument. It exercises the real SwiftUI composition and
/// command boundary without opening a database or claiming provider durability.
@MainActor
struct ActiveWorkspaceChecklistUITestFixtureView: View {
    @State private var fixture = ActiveWorkspaceChecklistUITestFixture()

    var body: some View {
        VStack(spacing: 0) {
            Text("UI TEST FIXTURE • IN-MEMORY ACCEPTANCE ONLY")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.orange)
                .accessibilityIdentifier("target-ui-fixture-banner")

            // Keep command evidence outside List cell recycling during native QA.
            Text("Accepted invocations: \(fixture.acceptedInvocationCount)")
                .accessibilityIdentifier("target-ui-fixture-acceptance-count")
                .accessibilityValue(String(fixture.acceptedInvocationCount))

            #if os(iOS)
            if ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-report-copy-receiver") ||
                ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-item-detail-copy") ||
                ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-item-groups") {
                UITestReportCopyReceiver(showsExactText:
                    ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-item-detail-copy") ||
                    ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-item-groups"))
            }
            #endif

            if ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-inline-category") {
                ProjectSetupStagingExerciseView(model: fixture.projectSetup, onCancel: {}, onDone: {})
            } else {
            NavigationStack {
            ScrollView {
              VStack(alignment: .leading, spacing: 16) {
                Section("Fixture evidence") {
                    Button("Simulate Account removal") { fixture.simulateRemoval() }
                        .accessibilityIdentifier("target-ui-fixture-remove-account")
                    if ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-remove-after-pdf-edit") {
                        Text("Closed review cleared: \(fixture.vendorReviewWasCleared ? "yes" : "no")")
                            .accessibilityIdentifier("target-ui-fixture-pdf-cleared")
                            .accessibilityValue(fixture.vendorReviewWasCleared ? "true" : "false")
                    }
                }

                WorkspaceAccessGate(access: fixture.access) {
                    ActiveWorkspaceToSpaceChecklistStagingView(model: fixture.model,
                        accountCurrency: try! CurrencyCode(validating: "USD"))
                }
              }.frame(maxWidth: .infinity, alignment: .leading).padding()
            }
            .itemThumbnailViewport()
            .accessibilityIdentifier("target-workspace-scroll")
            }
            }
        }
        .task { await fixture.start() }
        .onChange(of: fixture.access.isLocked) { _, locked in
            if locked { fixture.model.closeVendorDocumentReview() }
        }
        .onChange(of: fixture.model.vendorDocumentReview != nil) { _, isOpen in
            // Synthetic bytes supplied by the UI test exercise the real parser
            // and review UI, not the system file picker (tested separately).
            guard isOpen,
                  ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-vendor-pdf-bytes"),
                  let encoded = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--ledger-ui-test-pdf-base64=") }),
                  let bytes = Data(base64Encoded: String(encoded.dropFirst("--ledger-ui-test-pdf-base64=".count))),
                  let review = fixture.model.vendorDocumentReview else { return }
            if ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-remove-after-pdf-edit") {
                fixture.reviewForLifetimeAssertion = review
            }
            Task { await review.load(bytes, parser: LocalVendorPDFParser()) }
        }
        .onChange(of: fixture.model.vendorDocumentReview?.includedCount) { _, includedCount in
            // A deterministic test-only removal event after a real interaction
            // in the already-loaded sheet; no timer or provider access.
            guard includedCount == 1,
                  fixture.model.vendorDocumentReview?.state == .review,
                  ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-remove-after-pdf-edit") else { return }
            fixture.simulateRemoval()
        }
        .onDisappear {
            Task { await fixture.stop() }
        }
    }
}

@MainActor
@Observable
private final class ActiveWorkspaceChecklistUITestFixture {
    let access = WorkspaceAccessPresentation()
    private let removals = AsyncStream<Void>.makeStream()
    // Retain the exact opened model only in the explicit removal test so hiding
    // the sheet alone cannot falsely prove source/draft cleanup.
    var reviewForLifetimeAssertion: LocalVendorDocumentReview?
    var vendorReviewWasCleared: Bool {
        guard let review = reviewForLifetimeAssertion else { return false }
        return review.isClosed && review.sourceBytes == nil && review.document == nil
            && review.documentHash == nil && review.rows.isEmpty && review.categories.isEmpty
    }

    func simulateRemoval() {
        removals.continuation.yield(())
        removals.continuation.finish()
    }
    private static let observedAt = Date(timeIntervalSince1970: 1_789_500_000)

    private let accountId = try! AccountID(validating: "account-ui-test")
    private let principalId = try! PrincipalID(validating: "principal-ui-test")
    private let projectId = try! ProjectID(validating: "project-ui-test")
    private let spaceId = try! SpaceID(validating: "space-ui-test")
    private let checklistId = try! SpaceChecklistID(validating: "checklist-ui-test")
    private let itemId = try! SpaceChecklistItemID(validating: "item-ui-test")
    private let operationId = try! OperationID(validating: "operation-ui-test")
    private let contractVersion = try! OperationContractVersion(
        validating: "space-checklist-revision-v1"
    )

    let model: ActiveWorkspaceToSpaceChecklistStagingExercise
    let projectSetup: ProjectSetupStagingExercise
    private let categories: UITestCategoryManagementSource
    private(set) var acceptedInvocationCount = 0

    private let projectDirectorySnapshot: ProjectListSnapshot
    private let clientDirectorySnapshot: ClientListSnapshot
    private let projectDetail = UITestFixtureStream<ProjectCoreDetailsUpdate>()
    private let spaceDirectory: UITestFixtureStream<SpaceListUpdate>
    private let spaceScope: SpaceCreationScope
    private let spaceDetail: UITestFixtureStream<SpaceCoreDetailsUpdate>
    private let operationUpdates = UITestFixtureStream<OperationSnapshot>()
    private let rejectedUpdates: UITestFixtureStream<RejectedOperationRecoverySnapshot>
    private let emptyRejectedSnapshot: RejectedOperationRecoverySnapshot
    private var isStarted = false

    init() {
        let accountId = try! AccountID(validating: "account-ui-test")
        let principalId = try! PrincipalID(validating: "principal-ui-test")
        categories = UITestCategoryManagementSource(accountId: accountId)
        let projectId = try! ProjectID(validating: "project-ui-test")
        let spaceId = try! SpaceID(validating: "space-ui-test")
        let checklistId = try! SpaceChecklistID(validating: "checklist-ui-test")
        let itemId = try! SpaceChecklistItemID(validating: "item-ui-test")
        let contractVersion = try! OperationContractVersion(
            validating: "space-checklist-revision-v1"
        )
        projectSetup = ProjectSetupStagingExercise(accountId: accountId,
            accountCurrency: try! CurrencyCode(validating: "USD"), actorPrincipalId: principalId,
            operationContractVersion: try! OperationContractVersion(validating: "project-create-v1"),
            makeIdentity: { ProjectSetupSubmissionIdentity(
                projectId: try ProjectID(validating: UUID().uuidString),
                operationId: try OperationID(validating: UUID().uuidString)) },
            now: { Self.observedAt })

        let client = try! ClientSummary(
            id: ClientID(validating: "client-ui-test"),
            accountId: accountId,
            displayName: ClientDisplayName(validating: "UI Test Client"),
            lifecycle: .active,
            createdAt: Self.observedAt,
            updatedAt: Self.observedAt
        )
        clientDirectorySnapshot = try! ClientListSnapshot(accountId: accountId,
            local: ListLocalSnapshot(
                queryFingerprint: ListQueryFingerprint(validating: String(repeating: "1", count: 64)),
                rows: [client], visibleRowCountBeforeFiltering: 1, isCompleteForQuery: true,
                quality: .ready, localDataVersion: LocalDataVersion(validating: "ui-clients-1"),
                asOf: Self.observedAt))
        let project = try! ProjectSummary(
            id: projectId,
            accountId: accountId,
            clientId: client.id,
            client: client,
            displayName: ProjectDisplayName(validating: "UI Test Project"),
            description: nil,
            lifecycle: .active
        )
        let archivedProject = try! ProjectSummary(
            id: ProjectID(validating: "project-archived-ui-test"), accountId: accountId,
            clientId: client.id, client: client,
            displayName: ProjectDisplayName(validating: "Archived UI Test Project"),
            description: nil, lifecycle: .archived
        )
        let projectSnapshot = try! ProjectListSnapshot(
            accountId: accountId,
            local: ListLocalSnapshot(
                queryFingerprint: ListQueryFingerprint(
                    validating: String(repeating: "a", count: 64)
                ),
                rows: [project, archivedProject],
                visibleRowCountBeforeFiltering: 2,
                isCompleteForQuery: true,
                quality: .ready,
                localDataVersion: LocalDataVersion(validating: "ui-test-projects"),
                asOf: Self.observedAt
            )
        )

        let checklists = try! SpaceChecklistCollection(checklists: [
            SpaceChecklistState(
                id: checklistId,
                name: SpaceChecklistName(validating: "UI Test Checklist"),
                presentationOrder: 0,
                items: [
                    SpaceChecklistItemState(
                        id: itemId,
                        text: SpaceChecklistItemText(validating: "UI Test Item"),
                        isChecked: false,
                        presentationOrder: 0
                    ),
                ]
            ),
        ])
        let spaceScope: SpaceCreationScope = ProcessInfo.processInfo.arguments
            .contains("--ledger-ui-test-inventory-space") ? .businessInventory : .project(projectId)
        self.spaceScope = spaceScope
        let linkedSpaceArchived = ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-linked-space-archived")
        let spaceRow = SpaceListSourceRow(
            id: spaceId,
            accountId: accountId,
            scope: spaceScope,
            displayName: try! SpaceDisplayName(validating: "UI Test Space"),
            lifecycle: .active,
            revision: 3,
            checklists: checklists
        )
        let spaceListRequest = try! SpaceListRequest(
            accountId: accountId,
            scope: spaceScope
        )
        let spaceListUpdate = try! SpaceListUpdate(
            request: spaceListRequest,
            state: .snapshot(SpaceListLocalSnapshot(
                request: spaceListRequest,
                rows: linkedSpaceArchived ? [] : [spaceRow],
                visibleRowCountBeforeFiltering: linkedSpaceArchived ? 0 : 1,
                isCompleteForQuery: true,
                quality: .ready,
                localDataVersion: LocalDataVersion(validating: "ui-test-spaces"),
                asOf: Self.observedAt
            ))
        )

        let detailRequest = try! SpaceCoreDetailsRequest(
            accountId: accountId,
            spaceId: spaceId
        )
        let detailRow = try! SpaceCoreDetailsSnapshot(
            id: spaceId,
            accountId: accountId,
            scope: spaceScope,
            displayName: SpaceDisplayName(validating: "UI Test Space"),
            notes: SpaceCreationNotes(nil),
            lifecycle: linkedSpaceArchived ? .archived : .active,
            revision: 3,
            createdAt: Self.observedAt,
            updatedAt: Self.observedAt,
            checklists: checklists
        )
        let detailUpdate = try! SpaceCoreDetailsUpdate(
            request: detailRequest,
            state: .snapshot(SpaceCoreDetailsLocalSnapshot(
                request: detailRequest,
                rows: [detailRow],
                visibleRowCountBeforeFiltering: 1,
                isCompleteForQuery: true,
                quality: .ready,
                localDataVersion: LocalDataVersion(validating: "ui-test-space-detail"),
                asOf: Self.observedAt
            ))
        )
        let recoveryRequest = try! RejectedOperationRecoveryRequest(
            accountId: accountId,
            actorPrincipalId: principalId,
            family: .reviseSpaceChecklists,
            expectedContractVersion: contractVersion,
            subject: LedgerEntityReference(
                kind: .space,
                id: EntityID(validating: spaceId.rawValue)
            )
        )
        let recoverySnapshot = try! RejectedOperationRecoverySnapshot(
            request: recoveryRequest,
            candidates: []
        )

        projectDirectorySnapshot = projectSnapshot
        spaceDirectory = UITestFixtureStream(initial: spaceListUpdate)
        spaceDetail = UITestFixtureStream(initial: detailUpdate)
        emptyRejectedSnapshot = recoverySnapshot
        rejectedUpdates = UITestFixtureStream(initial: recoverySnapshot)

        let projectBrowser = ProjectBrowsingStagingExercise(accountId: accountId)
        let spaceBrowser = SpaceBrowserStagingExercise(accountId: accountId)
        let toggle = SpaceChecklistItemToggleStagingExercise(
            accountId: accountId,
            actorPrincipalId: principalId,
            operationContractVersion: contractVersion,
            makeIdentity: {
                SpaceChecklistItemToggleSubmissionIdentity(
                    operationId: try! OperationID(validating: "operation-ui-test")
                )
            },
            now: { Self.observedAt }
        )
        model = ActiveWorkspaceToSpaceChecklistStagingExercise(
            accountId: accountId,
            projectBrowser: projectBrowser,
            spaceBrowser: spaceBrowser,
            checklistToggle: toggle
        )
    }

    func start() async {
        access.observe(removals.stream)
        guard !isStarted else { return }
        isStarted = true
        if ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-reset-inventory-section") {
            InventoryWorkspaceSection.items.remember(accountId: accountId)
        }
        await model.start(runtime: ActiveWorkspaceToSpaceChecklistStagingRuntime(
            projectBrowsing: ProjectBrowsingStagingRuntime(
                // Each subscription gets the current snapshot, including after Back.
                // A cancelled AsyncStream cannot be reused as a new database watch.
                watchProjects: { [projectDirectorySnapshot] in
                    AsyncThrowingStream { $0.yield(projectDirectorySnapshot) }
                },
                watchProject: { [projectDetail, projectDirectorySnapshot, observedAt = Self.observedAt] request in
                    let arguments = ProcessInfo.processInfo.arguments
                    guard let mode = arguments.first(where: { $0.hasPrefix("--ledger-ui-test-legacy-notes=") }) else {
                        return projectDetail.stream
                    }
                    return AsyncThrowingStream { continuation in
                        do {
                            let rows = try projectDirectorySnapshot.local.rows
                                .filter { $0.id == request.projectId && $0.accountId == request.accountId }
                                .map { try ProjectCoreDetailsSnapshot(project: $0,
                                    locallyObservedRevision: ExpectedProjectRevision(3),
                                    legacyNotes: mode.hasSuffix("=both") || mode.hasSuffix("=legacy-only")
                                        ? "Original planning notes\nKeep the blue sofa." : nil) }
                            continuation.yield(try ProjectCoreDetailsUpdate(request: request, state: .snapshot(
                                ProjectCoreDetailsLocalSnapshot(request: request, rows: rows,
                                    visibleRowCountBeforeFiltering: rows.count, isCompleteForQuery: true,
                                    quality: .ready, localDataVersion: LocalDataVersion(validating: "ui-legacy-notes"),
                                    asOf: observedAt))))
                        } catch { continuation.finish(throwing: error) }
                    }
                },
                watchNotes: { request in
                    AsyncThrowingStream { continuation in
                        do {
                            let note = try ProjectNoteSnapshot(
                                id: ProjectNoteID(validating: "note-ui-test"),
                                accountId: request.accountId, projectId: request.projectId,
                                content: .visible(ProjectNoteText(validating: "Measure the entry before delivery.")),
                                source: ProjectNoteSource(validating: "text"),
                                createdByPrincipalId: PrincipalID(validating: "principal-ui-test"),
                                creatorDisplayName: ProjectNoteCreatorDisplayName(validating: "Test Designer"),
                                createdAt: Date(timeIntervalSince1970: 1_789_500_000), revision: 1
                            )
                            let mode = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--ledger-ui-test-legacy-notes=") })
                            let rows = mode?.hasSuffix("=legacy-only") == true || mode?.hasSuffix("=neither") == true ? [] : [note]
                            continuation.yield(try ProjectNotePage(
                                request: request,
                                local: ListLocalSnapshot(
                                    queryFingerprint: request.queryFingerprint, rows: rows,
                                    visibleRowCountBeforeFiltering: rows.count, isCompleteForQuery: true,
                                    quality: .ready, localDataVersion: LocalDataVersion(validating: "ui-notes-1"),
                                    asOf: Date(timeIntervalSince1970: 1_789_500_000)
                                ),
                                isCompleteForProjectHistory: true, nextCursor: nil
                            ))
                            continuation.finish()
                        } catch { continuation.finish(throwing: error) }
                    }
                }
            ),
            spaceBrowsing: SpaceBrowserStagingRuntime(
                listQuery: UITestFixtureSpaceListQuery(source: spaceDirectory,
                    inventoryHasSpace: spaceScope == .businessInventory),
                detailQuery: UITestFixtureSpaceDetailQuery(source: spaceDetail)
            ),
            checklistToggle: SpaceChecklistItemToggleStagingRuntime(
                reviseChecklists: { [weak self] command in
                    guard let self else { throw CancellationError() }
                    return try await self.accept(command)
                },
                watchOperation: { [operationUpdates] _ in operationUpdates.stream },
                rejectedOperations: { [emptyRejectedSnapshot] request in
                    guard request == emptyRejectedSnapshot.request else {
                        throw CancellationError()
                    }
                    return emptyRejectedSnapshot
                },
                watchRejectedOperations: { [rejectedUpdates] _ in rejectedUpdates.stream }
            ),
            itemReader: UITestFixtureItemReader(saleProjects: projectDirectorySnapshot,
                saleAccepted: { [weak self] in await self?.recordSaleAcceptance() }),
            reportWatcher: UITestFixtureReportWatcher(),
            reportReader: UITestFixtureReportWatcher(),
            categoryWatch: { [categories] in categories.watch() },
            categoryManagement: CategoryManagementRuntime(
                watch: { [categories] in categories.watch() },
                submit: { [categories] payload, uuid, _ in
                    try await categories.submit(payload, uuid: uuid)
                }),
            transactionBrowser: ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-workspace-transactions")
                ? TransactionBrowserFixtureReader() : nil
        ))
        if ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-inline-category") {
            await projectSetup.start(runtime: ProjectSetupStagingRuntime(
                watchClients: { [clientDirectorySnapshot] in AsyncThrowingStream { $0.yield(clientDirectorySnapshot) } },
                watchBudgetCategories: { [categories] in categories.watch() },
                create: { [weak self] _ in
                    await self?.recordUnexpectedProjectCreation()
                    throw CancellationError()
                },
                watchOperation: { _ in AsyncThrowingStream { $0.finish() } },
                categoryManagement: CategoryManagementRuntime(
                    watch: { [categories] in categories.watch() },
                    submit: { [categories] payload, uuid, _ in try await categories.submit(payload, uuid: uuid) })))
        }
    }

    private func recordUnexpectedProjectCreation() { acceptedInvocationCount += 1 }
    private func recordSaleAcceptance() { acceptedInvocationCount += 1 }

    func stop() async {
        access.stop()
        guard isStarted else { return }
        isStarted = false
        await model.stop()
        await projectSetup.stop()
    }

    private func accept(_ command: ReviseSpaceChecklistsCommand) throws -> OperationReceipt {
        guard acceptedInvocationCount == 0,
              command.draft.accountId == accountId,
              command.draft.actorPrincipalId == principalId,
              command.draft.operationContractVersion == contractVersion,
              command.draft.spaceId == spaceId,
              command.draft.expectedRevision.rawValue == 3,
              command.draft.collection.checklists.count == 1,
              command.draft.collection.checklists[0].id == checklistId,
              command.draft.collection.checklists[0].items.count == 1,
              command.draft.collection.checklists[0].items[0].id == itemId,
              command.draft.collection.checklists[0].items[0].isChecked,
              command.envelope.operationId == operationId,
              command.envelope.accountId == accountId,
              command.envelope.actorPrincipalId == principalId,
              command.envelope.contractVersion == contractVersion else {
            throw CancellationError()
        }
        acceptedInvocationCount += 1
        return OperationReceipt(
            operationId: command.envelope.operationId,
            localState: .queued
        )
    }
}

/// Synthetic category state behind the real shared Settings form/list. This is
/// interaction evidence only; durable storage and authorization have separate tests.
private actor UITestCategoryManagementSource {
    let accountId: AccountID
    private let withdrawOnSave: Bool
    private var rows: [BudgetCategoryDefinitionSnapshot]
    private var observers: [UUID: AsyncThrowingStream<BudgetCategoryReferenceSnapshot, Error>.Continuation] = [:]
    private var version = 1

    init(accountId: AccountID) {
        self.accountId = accountId
        withdrawOnSave = ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-category-withdraw-on-save")
        rows = [BudgetCategoryDefinitionSnapshot(
            id: try! BudgetCategoryID(validating: "category-ui-test"), accountId: accountId,
            name: try! BudgetCategoryName(validating: withdrawOnSave ? "Design Fee" : "Furnishings"),
            kind: withdrawOnSave ? .fee : .general,
            lifecycle: .active, isSystem: false, excludesFromOverallBudget: false,
            presentationOrder: 0, revision: 1)]
    }

    nonisolated func watch() -> AsyncThrowingStream<BudgetCategoryReferenceSnapshot, Error> {
        AsyncThrowingStream { continuation in
            let id = UUID()
            let registration = Task {
                await register(id, continuation)
                if Task.isCancelled { await remove(id) }
            }
            continuation.onTermination = { _ in
                registration.cancel()
                Task { await self.remove(id) }
            }
        }
    }

    private func register(_ id: UUID, _ continuation: AsyncThrowingStream<BudgetCategoryReferenceSnapshot, Error>.Continuation) {
        do {
            continuation.yield(try snapshot())
            observers[id] = continuation
        } catch { continuation.finish(throwing: error) }
    }

    private func remove(_ id: UUID) { observers.removeValue(forKey: id) }

    func submit(_ payload: CategoryManagementPayload, uuid: UUID) throws -> OperationReceipt {
        if withdrawOnSave {
            // Deterministic permission-change event while the real editor awaits
            // Save. Provider tests separately prove withdrawal and queue retention.
            rows = []
            version += 1
            let updated = try snapshot()
            for observer in observers.values { observer.yield(updated) }
            throw CategoryManagementFailure.categoryUnavailable
        }
        rows = try CategoryManagement.applying(payload, to: snapshot())
        version += 1
        let updated = try snapshot()
        for observer in observers.values { observer.yield(updated) }
        return OperationReceipt(operationId: try OperationID(validating: uuid.uuidString),
            localState: .queued)
    }

    private func snapshot() throws -> BudgetCategoryReferenceSnapshot {
        try BudgetCategoryReferenceSnapshot(accountId: accountId, local: ListLocalSnapshot(
            queryFingerprint: ListQueryFingerprint(validating: String(repeating: "2", count: 64)),
            rows: rows, visibleRowCountBeforeFiltering: rows.count, isCompleteForQuery: true,
            quality: .ready, localDataVersion: LocalDataVersion(validating: "ui-categories-\(version)"),
            asOf: Date(timeIntervalSince1970: 1_789_500_000)))
    }
}

private final class UITestFixtureStream<Value: Sendable>: @unchecked Sendable {
    let stream: AsyncThrowingStream<Value, Error>
    private let continuation: AsyncThrowingStream<Value, Error>.Continuation

    init(initial: Value? = nil) {
        var captured: AsyncThrowingStream<Value, Error>.Continuation!
        stream = AsyncThrowingStream { continuation in
            captured = continuation
        }
        continuation = captured
        if let initial {
            continuation.yield(initial)
        }
    }

    deinit {
        continuation.finish()
    }
}

private struct UITestFixtureSpaceListQuery: SpaceListQuerying {
    let source: UITestFixtureStream<SpaceListUpdate>
    let inventoryHasSpace: Bool

    func watchSpaces(
        _ request: SpaceListRequest
    ) -> AsyncThrowingStream<SpaceListUpdate, Error> {
        if request.scope == .businessInventory && !inventoryHasSpace {
            return AsyncThrowingStream { continuation in
                do {
                    continuation.yield(try SpaceListUpdate(request: request, state: .snapshot(
                        SpaceListLocalSnapshot(request: request, rows: [],
                            visibleRowCountBeforeFiltering: 0, isCompleteForQuery: true,
                            quality: .ready, localDataVersion: LocalDataVersion(validating: "ui-inventory-empty"),
                            asOf: Date(timeIntervalSince1970: 1_789_500_000))
                    )))
                } catch { continuation.finish(throwing: error) }
            }
        }
        return source.stream
    }
}

private struct UITestFixtureSpaceDetailQuery: SpaceCoreDetailsQuerying {
    let source: UITestFixtureStream<SpaceCoreDetailsUpdate>

    func watchSpaceCoreDetails(
        _ request: SpaceCoreDetailsRequest
    ) -> AsyncThrowingStream<SpaceCoreDetailsUpdate, Error> {
        source.stream
    }
}
private struct UITestFixtureItemReader: DownloadedItemPlacementReading, DownloadedProjectItemsReading, DownloadedItemPlacementHistoryReading, AccountBusinessProfileReading, DownloadedItemImageReading, InventorySaleWorkflowServing, ProjectInvoicingReading, ProjectInvoiceCreating, ExpenseCreating, ExpenseEditing {
    private let expenseAccess = NSLockingTransactionFixtureUpdates()
    func editExpense(_ entry: BusinessPaidExpenseDraft, expectedRevision: Int64, operationUUID: UUID, capturedAt: Date, recovery: ExpenseEntryRecovery? = nil) async throws -> OperationReceipt {
        guard expenseAccess.hasAccess, expectedRevision == 1, entry.expenseId.rawValue == "expense-ui-test",
              entry.vendor == "Receipt vendor updated", entry.finalAmount.minorUnits == 12550,
              !ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-paid-expense") else {
            throw ProjectExpenses.Failure.invalidEvidence
        }
        let id = try OperationID(validating: operationUUID.uuidString)
        expenseAccess.saveExpenseEdit(try .init(id: id, entry: entry, expectedRevision: expectedRevision, state: .queued))
        expenseAccess.publishExpenses(try await readExpenses(accountId: entry.accountId, projectId: entry.projectId))
        return .init(operationId: id, localState: .queued)
    }
    func watchBudgetCategories() -> AsyncThrowingStream<BudgetCategoryReferenceSnapshot, Error> {
        AsyncThrowingStream { continuation in
            do {
                let account = try AccountID(validating: "account-ui-test")
                let row = BudgetCategoryDefinitionSnapshot(id: try .init(validating: "category-ui-test"), accountId: account,
                    name: try .init(validating: "Shipping"), kind: .general, lifecycle: .active, isSystem: false,
                    excludesFromOverallBudget: false, presentationOrder: 0, revision: 1)
                continuation.yield(try .init(accountId: account, local: .init(
                    queryFingerprint: .init(validating: String(repeating: "2", count: 64)), rows: [row],
                    visibleRowCountBeforeFiltering: 1, isCompleteForQuery: true, quality: .ready,
                    localDataVersion: .init(validating: "expense-fixture"), asOf: Date())))
            } catch { continuation.finish(throwing: error) }
        }
    }
    func expenseAttachmentCaptureScope(projectId: ProjectID, expenseId: ExpenseID) async throws -> AttachmentCaptureScope {
        try .init(environment: .targetLocal, principalId: .init(validating: "principal-ui-test"),
            accountId: .init(validating: "account-ui-test"), parent: .init(kind: .expense, id: .init(validating: expenseId.rawValue)))
    }
    func captureAttachment(_ capture: LocalAttachmentCapture) async throws -> AttachmentLocalDurabilityReceipt {
        try .init(accepting: capture, persistedEvidence: .init(attachmentId: capture.attachmentId, scope: capture.scope,
            localObjectId: .init(validating: capture.attachmentId.rawValue), byteCount: capture.byteCount,
            contentSHA256: capture.contentSHA256, persistedAt: capture.capturedAt))
    }
    func createExpense(_ draft: BusinessPaidExpenseDraft, operationUUID: UUID, capturedAt: Date, recovery: ExpenseEntryRecovery?) async throws -> OperationReceipt {
        if ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-expense-lines")
            || ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-expense-recovery-save") {
            guard let recovery, recovery.vendor == draft.vendor, recovery.notes == draft.notes,
                  recovery.categoryId == draft.categoryId, recovery.operationUUID == operationUUID,
                  try Money.parsePositiveEntry(recovery.amountText, currency: draft.finalAmount.currency) == draft.finalAmount else {
                throw ProjectExpenses.Failure.invalidEvidence
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-expense-lines") {
            guard draft.receiptLines.count == 1, draft.receiptLines[0].description.rawValue == "Delivery",
                  draft.receiptLines[0].magnitude.minorUnits == 1025, draft.receiptLines[0].effect == .decrease,
                  draft.receiptLines[0].quantity == -2,
                  draft.finalAmount.minorUnits == 12550 else { throw ProjectExpenses.Failure.invalidEvidence }
        }
        return .init(operationId: try .init(validating: operationUUID.uuidString), localState: .queued)
    }
    func saveExpenseEntry(_ entry: ExpenseEntryRecovery, replacing previous: ExpenseEntryRecovery?) async throws {}
    func restoreExpenseEntryCaptures(_ entry: ExpenseEntryRecovery) async throws -> [LocalAttachmentCapture] {
        if ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-unfinished-receipt-failure") {
            throw ProjectExpenses.Failure.invalidEvidence
        }
        return []
    }
    func readInvoicingCharges(accountId: AccountID, projectId: ProjectID) async throws -> ProjectInvoicingItems {
        try ProjectInvoicingItems(accountId: accountId, projectId: projectId, rows: [])
    }
    func watchInvoicingCharges(accountId: AccountID, projectId: ProjectID) -> AsyncThrowingStream<ProjectInvoicingItems?, Error> {
        AsyncThrowingStream { continuation in
            do { continuation.yield(try ProjectInvoicingItems(accountId: accountId, projectId: projectId, rows: [])) }
            catch { continuation.finish(throwing: error) }
        }
    }
    func readExpenses(accountId: AccountID, projectId: ProjectID) async throws -> ProjectExpenses {
        guard expenseAccess.hasAccess else { throw ProjectExpenses.Failure.invalidEvidence }
        var objects: [DownloadedMediaObjectReference] = []
        if ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-expense-receipts") {
            for (index, kind) in ["pdf", "image", "image"].enumerated() {
                let bytes = kind == "pdf" ? await TransactionBrowserFixtureReader.pdfBytes : TransactionBrowserFixtureReader.imageBytes
                let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
                let id = "expense-receipt-\(index)"
                objects.append(try .init(accountId: accountId, attachmentId: id, sha256: hash,
                    byteCount: String(bytes.count), mediaType: kind == "pdf" ? "application/pdf" : "image/png",
                    storagePath: "accounts/\(accountId.rawValue)/attachments/\(id)/\(hash)", kind: kind == "pdf" ? .pdf : .image))
            }
        }
        let pending: [ProjectExpenses.PendingCreation] = try ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-pending-expenses")
            ? [LocalOperationState.queued, .rejected].map { state in
                try .init(id: .init(validating: "pending-\(state.rawValue)"), entry: .init(accountId: accountId,
                    projectId: projectId, expenseId: .init(validating: "pending-\(state.rawValue)"),
                    vendor: "Offline \(state.rawValue) vendor", date: "2026-09-15",
                    finalAmount: .init(minorUnits: 1000, currency: .init(validating: "USD")),
                    categoryId: .init(validating: "category-ui-test"), notes: "Retained draft",
                    receiptAttachmentIds: [.init(validating: "expense-receipt-0"), .init(validating: "expense-receipt-1")]), state: state)
            } : []
        var collected: FrozenInvoiceContents?
        if ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-paid-expense") {
            let scope = TransactionScope.project(accountId: accountId, projectId: projectId,
                clientId: try .init(validating: "client-ui-test"))
            let line = try FrozenInvoiceLine(id: .init(validating: "paid-expense-line"), scope: scope,
                source: .expense(expenseId: .init(validating: "expense-ui-test")), sourceRevision: 1,
                categoryId: .init(validating: "category-ui-test"),
                signedAmount: .init(minorUnits: 12550, currency: .init(validating: "USD")), description: "Receipt vendor")
            var invoiceLines = [line]
            if ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-long-invoice") {
                for index in 0..<80 {
                    invoiceLines.append(try .init(id: .init(validating: "report-line-\(index)"), scope: scope,
                        source: .feeInstallment(installmentId: .init(validating: "report-fee-\(index)")),
                        sourceRevision: 1, categoryId: line.categoryId,
                        signedAmount: .init(minorUnits: index == 0 ? 9_007_199_254_740_993 : 101, currency: line.signedAmount.currency),
                        description: "Invoice row \(String(format: "%03d", index)) <original>"))
                }
            }
            let invoiceTotal = try invoiceLines.reduce(Money.zero(currency: line.signedAmount.currency)) { try $0.adding($1.signedAmount) }
            collected = try .init(invoiceId: .init(validating: "paid-expense-invoice"), invoiceRevision: 1,
                scope: scope, purchaseId: .init(validating: "paid-expense-payment"), lines: invoiceLines, total: invoiceTotal,
                displayMetadata: .init(invoiceNumber: "INV-UI-001", notes: "Invoice notes", paidAtMilliseconds: "0"))
        }
        return try ProjectExpenses(accountId: accountId, projectId: projectId, expenses: [
            .init(entry: BusinessPaidExpenseDraft(accountId: accountId, projectId: projectId,
                expenseId: ExpenseID(validating: "expense-ui-test"), vendor: "Receipt vendor",
                date: "2026-09-15", finalAmount: Money(minorUnits: 12550, currency: CurrencyCode(validating: "USD")),
                categoryId: BudgetCategoryID(validating: "category-ui-test"), notes: "Delivery",
                receiptAttachmentIds: objects.map(\.attachmentId)), revision: 1,
                currentCategoryName: "Shipping", receiptObjects: objects, collectedInvoice: collected)
        ], pendingCreations: pending, pendingEdits: expenseAccess.pendingExpenseEdit.map { [$0] } ?? [], unfinishedEntries: ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-unfinished-expense") ? [
            .init(accountId: accountId, projectId: projectId, expenseId: .init(validating: "unfinished-expense"),
                operationUUID: UUID(), capturedAt: Date(), vendor: "Saved unfinished vendor", date: Date(),
                amountText: "125.50", notes: "Saved unfinished notes", categoryId: .init(validating:
                    ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-expense-missing-category")
                        ? "category-no-longer-available" : "category-ui-test"),
                lines: [], attachmentIds: [])
        ] : [], unfinishedEdits: ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-paid-expense-saved-edit") ? [
            .init(accountId: accountId, projectId: projectId, expenseId: .init(validating: "expense-ui-test"),
                operationUUID: UUID(), capturedAt: Date(), vendor: "Retained edit", date: Date(),
                amountText: "125.50", notes: "Unsubmitted edit", categoryId: .init(validating: "category-ui-test"),
                lines: [], attachmentIds: [], editContext: .init(expectedRevision: 1,
                    retainedAttachmentIds: objects.map(\.attachmentId)))
        ] : [])
    }
    func readCollectedInvoiceReport(accountId: AccountID, projectId: ProjectID, invoiceId: InvoiceID,
        asOf: ProtectedArtifactEpochMilliseconds) async throws -> CollectedInvoiceReportSnapshot {
        if ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-invoice-export-retry"),
           expenseAccess.rejectFirstInvoiceExport() {
            throw ProjectExpenses.Failure.invalidEvidence
        }
        guard let invoice = try await readCollectedInvoices(accountId: accountId, projectId: projectId)
            .first(where: { $0.invoiceId == invoiceId }) else { throw ProjectExpenses.Failure.invalidEvidence }
        // Explicit synthetic UI evidence; production reads obtain the retained
        // checkpoint and content version from the same local DB transaction.
        return try .init(invoice: invoice, provenance: .init(accountId: accountId, projectId: projectId,
            principalId: .init(validating: "principal-ui-test"),
            visibilityScopeID: .make(bytes: Data("invoice-ui-test".utf8)),
            localDataVersion: .init(validating: "invoice-ui-test-v1"),
            authorityVersion: .init(validating: "collected-invoice-v1"), asOf: asOf,
            readiness: .ready, lastSyncedAt: .init(validating: 1000)))
    }

    func readCollectedInvoices(accountId: AccountID, projectId: ProjectID) async throws -> [FrozenInvoiceContents] {
        try await readExpenses(accountId: accountId, projectId: projectId).expenses.compactMap(\.collectedInvoice)
    }
    func readLiveInvoices(accountId: AccountID, projectId: ProjectID) async throws -> [LiveInvoiceContents] {
        let expenses = try await readExpenses(accountId: accountId, projectId: projectId)
        guard ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-live-invoice"),
              let expense = expenses.expenses.first else { return [] }
        return try [.init(invoiceId: .init(validating: "live-invoice-ui-test"), revision: 1, status: .sent,
            name: "Live Invoice", notes: "Sent outside Ledger",
            scope: .project(accountId: accountId, projectId: projectId, clientId: .init(validating: "client-ui-test")),
            lines: [.init(selection: .init(source: .expense(expense.entry.expenseId), expectedRevision: expense.revision,
                reviewedAmount: expense.entry.finalAmount), categoryId: expense.entry.categoryId,
                description: expense.entry.vendor)], reportedTotal: expense.entry.finalAmount)]
    }
    func watchLiveInvoices(accountId: AccountID, projectId: ProjectID) -> AsyncThrowingStream<[LiveInvoiceContents]?, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await value in watchExpenses(accountId: accountId, projectId: projectId) {
                        continuation.yield(value == nil ? nil : try await readLiveInvoices(accountId: accountId, projectId: projectId))
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    func createInvoice(_ payload: CreateInvoiceCommand.Payload, operationUUID: UUID, capturedAt: Date) async throws -> OperationReceipt {
        throw ProjectExpenses.Failure.invalidEvidence // Read-only fixture; never simulate a successful save.
    }
    func readInvoiceCreationReview(accountId: AccountID, projectId: ProjectID) async throws -> InvoiceCreationReview {
        throw ProjectExpenses.Failure.invalidEvidence // This fixture currently exercises pending/list reads only.
    }
    func readPendingInvoiceCreations(accountId: AccountID, projectId: ProjectID) async throws -> [PendingInvoiceCreation] {
        let expenses = try await readExpenses(accountId: accountId, projectId: projectId)
        guard ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-pending-invoice"),
              let expense = expenses.expenses.first else { return [] }
        return try [LocalOperationState.queued, .rejected].map { state in
            try PendingInvoiceCreation(id: .init(validating: "pending-op-" + state.rawValue),
                payload: .init(invoiceId: .init(validating: "pending-" + state.rawValue),
                    selection: .init(scope: .project(accountId: accountId, projectId: projectId, clientId: .init(validating: "client-ui-test")),
                        lines: [.init(source: .expense(expense.entry.expenseId), expectedRevision: expense.revision,
                            reviewedAmount: expense.entry.finalAmount)]), name: "Pending Invoice", notes: ""), state: state)
        }
    }
    func watchCollectedInvoices(accountId: AccountID, projectId: ProjectID, invoiceId: InvoiceID? = nil) -> AsyncThrowingStream<[FrozenInvoiceContents]?, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await value in watchExpenses(accountId: accountId, projectId: projectId) {
                        continuation.yield(value.map { $0.expenses.compactMap(\.collectedInvoice).filter { invoiceId == nil || $0.invoiceId == invoiceId } })
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func loadExpenseReceipt(projectId: ProjectID, expenseId: ExpenseID, attachmentId: AttachmentID,
                            allowDownload: Bool) async throws -> Data? {
        guard expenseAccess.hasAccess else { throw ProjectExpenses.Failure.invalidEvidence }
        if attachmentId.rawValue == "expense-receipt-0" { return await TransactionBrowserFixtureReader.pdfBytes }
        return TransactionBrowserFixtureReader.imageBytes
    }
    func watchExpenses(accountId: AccountID, projectId: ProjectID) -> AsyncThrowingStream<ProjectExpenses?, Error> {
        AsyncThrowingStream { continuation in
            let id = UUID()
            expenseAccess.observeExpenses(continuation, id: id)
            let task = Task {
                do {
                    continuation.yield(try await readExpenses(accountId: accountId, projectId: projectId))
                    #if os(iOS)
                    if ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-expense-withdrawal") {
                        for await _ in NotificationCenter.default.notifications(named: UIApplication.didBecomeActiveNotification).map({ _ in true }) {
                            expenseAccess.withdraw()
                            continuation.yield(nil)
                        }
                    }
                    #endif
                }
                catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel(); expenseAccess.removeExpenseObserver(id) }
        }
    }
    var saleProjects: ProjectListSnapshot? = nil
    var saleAccepted: (@Sendable () async -> Void)? = nil
    func watchProjects() -> AsyncThrowingStream<ProjectListSnapshot, Error> {
        AsyncThrowingStream { if let saleProjects { $0.yield(saleProjects) } }
    }
    func readInventorySaleReview(itemIds: [ItemID]) async throws -> InventorySaleReview {
        try InventorySaleReview(accountId: AccountID(validating: "account-ui-test"),
            principalId: PrincipalID(validating: "principal-ui-test"), items: itemIds.map {
                .init(itemId: $0, placementId: try EntityID(validating: "history-\($0.rawValue)"), priceRevision: 0,
                    projectPrice: .confirmedAbsent,
                    purchaseCost: ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-bulk-sale")
                        ? .known(try Money(minorUnits: 12550, currency: CurrencyCode(validating: "USD"))) : .confirmedAbsent)
            })
    }
    func watchInventorySaleReview(itemIds: [ItemID]) -> AsyncThrowingStream<InventorySaleReview?, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(try await readInventorySaleReview(itemIds: itemIds))
                    #if os(iOS)
                    let arguments = ProcessInfo.processInfo.arguments
                    if arguments.contains("--ledger-ui-test-sale-review-changes") || arguments.contains("--ledger-ui-test-sale-review-withdraws") {
                        // Background/activate is the test's explicit event, not a timing delay.
                        for await _ in NotificationCenter.default.notifications(named: UIApplication.didBecomeActiveNotification).map({ _ in true }) {
                            if arguments.contains("--ledger-ui-test-sale-review-withdraws") { continuation.yield(nil) }
                            else {
                                continuation.yield(try InventorySaleReview(accountId: .init(validating: "account-ui-test"),
                                    principalId: .init(validating: "principal-ui-test"), items: itemIds.map {
                                        .init(itemId: $0, placementId: try .init(validating: "history-\($0.rawValue)"),
                                            priceRevision: 0, projectPrice: .confirmedAbsent,
                                            purchaseCost: .known(try Money(minorUnits: 25000, currency: .init(validating: "USD"))))
                                    }))
                            }
                        }
                    }
                    #endif
                }
                catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    func sellInventoryItems(_ payload: InventorySalePayload, operationUUID: UUID, capturedAt: Date) async throws -> OperationReceipt {
        if ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-sale-already-accepted") {
            throw InventorySaleCommandFailure.saleAlreadyAccepted
        }
        let expectedCount = ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-bulk-sale") ? 3 : 1
        guard payload.projectId.rawValue == "project-ui-test", payload.items.count == expectedCount,
              payload.items.allSatisfy({ $0.reviewedPriceMinorUnits == "12550" }) else { throw InventorySaleReview.Failure.invalidEvidence }
        await saleAccepted?()
        return OperationReceipt(operationId: try OperationID(validating: operationUUID.uuidString), localState: .queued)
    }
    func watchInventorySale(_ operationId: OperationID) -> AsyncThrowingStream<OperationSnapshot?, Error> {
        AsyncThrowingStream { $0.yield(nil) }
    }
    private var imageBytes: Data {
        Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7")!
    }
    func watchDownloadedItemImages(accountId: AccountID, itemId: ItemID) -> AsyncThrowingStream<DownloadedItemImageCatalog, Error> {
        AsyncThrowingStream { continuation in
            do {
                let populated = ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-item-images")
                let count = itemId.rawValue == "physical-ui-other-space" ? 1
                    : (itemId.rawValue == "physical-ui-chair" && populated ? 2 : 0)
                let hash = try AttachmentContentSHA256.make(bytes: imageBytes).rawValue
                let images: [DownloadedItemImage] = try (0..<count).map { index in
                    let id = "fixture-image-\(index)"
                    let object = try DownloadedImageObjectReference(accountId: accountId, attachmentId: id,
                        sha256: hash, byteCount: String(imageBytes.count), mediaType: "image/gif",
                        storagePath: "accounts/\(accountId.rawValue)/attachments/\(id)/\(hash)")
                    let generated = try ItemCardThumbnailGenerator.generate(originalBytes: imageBytes,expectedOriginal: object)
                    let smallId = "small-\(id)"
                    let small = try DownloadedImageObjectReference(accountId: accountId,attachmentId: smallId,
                        sha256: generated.contentSHA256.rawValue,byteCount: String(generated.byteCount),mediaType: generated.mediaType,
                        storagePath: "accounts/\(accountId.rawValue)/attachments/\(smallId)/\(generated.contentSHA256.rawValue)")
                    return try .init(referenceId: .init(validating: "fixture-reference-\(index)"), itemId: itemId,
                        object: object, position: index, isPrimary: index == 0, setRevision: 1,
                        thumbnail: .init(original: object,object: small,recipe: generated.recipe,width: generated.width,height: generated.height))
                }
                continuation.yield(try .init(accountId: accountId, itemId: itemId,
                    isComplete: itemId.rawValue != "physical-ui-unassigned", images: images))
            } catch { continuation.finish(throwing: error) }
        }
    }
    func loadDownloadedItemImage(accountId: AccountID, itemId: ItemID,
        image: DownloadedItemImage, allowDownload: Bool) async throws -> Data? {
        guard image.itemId == itemId, image.object.accountId == accountId else {
            throw DownloadedItemImageFailure.scopeMismatch
        }
        return imageBytes
    }
    func loadDownloadedItemThumbnail(accountId: AccountID,itemId: ItemID,
        image: DownloadedItemImage,allowDownload: Bool) async throws -> Data? {
        guard image.itemId == itemId, image.object.accountId == accountId,let thumbnail = image.thumbnail else {
            throw DownloadedItemImageFailure.scopeMismatch
        }
        let generated = try ItemCardThumbnailGenerator.generate(originalBytes: imageBytes,expectedOriginal: image.object)
        guard generated.contentSHA256 == thumbnail.object.contentSHA256,
              generated.byteCount == thumbnail.object.byteCount else { throw DownloadedItemImageFailure.malformed }
        return generated.bytes
    }
    func watchDownloadedProjectItems(accountId: AccountID, projectId: ProjectID) -> AsyncThrowingStream<DownloadedProjectItems, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let physical = try await readDownloadedItemPlacements(accountId: accountId, scope: .project(projectId))
                    let clientId = try ClientID(validating: "client-ui-test")
                    let evidence = try physical.rows.map { row in
                        try ProjectItemAccountingEvidence(accountId: accountId, projectId: projectId,
                            clientId: clientId, itemId: row.itemId, spaceId: row.spaceId,
                            billableOccurrences: row.itemId.rawValue == "physical-ui-chair" ? [
                                BillableItemAccountingOccurrence(id: .init(validating: "ui-charge"),
                                    accountId: accountId, projectId: projectId, itemId: row.itemId,
                                    polarity: .charge, phase: .availableToInvoice)
                            ] : [])
                    }
                    let accounting = try ProjectItemAccountingSectionsSnapshot(accountId: accountId,
                        projectId: projectId, clientId: clientId, items: evidence,
                        isCompleteForAccounting: ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-complete-item-accounting"), quality: .ready,
                        localDataVersion: .init(validating: "ui-item-accounting"), asOf: Date())
                    continuation.yield(try DownloadedProjectItems(placements: physical, accounting: accounting))
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    private var failedLogoDownload: Bool {
        ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-profile-logo-unavailable")
    }
    func readAccountBusinessProfile(accountId: AccountID) async throws -> AccountBusinessProfile {
        try AccountBusinessProfile(accountId: accountId,
            name: AccountDisplayName(validating: "Design studio"),
            logo: failedLogoDownload ? .notDownloaded : .absent, isStale: true)
    }
    func watchAccountBusinessProfile(accountId: AccountID) -> AsyncThrowingStream<AccountBusinessProfile, Error> {
        AsyncThrowingStream { continuation in
            do {
                continuation.yield(try AccountBusinessProfile(accountId: accountId,
                    name: AccountDisplayName(validating: "Design studio"),
                    logo: failedLogoDownload ? .unavailable : .absent, isStale: true))
                continuation.finish()
            } catch { continuation.finish(throwing: error) }
        }
    }

    private func pendingSale(accountId: AccountID) throws -> InventorySalePendingPlacement? {
        guard ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-pending-sale") else { return nil }
        let itemId = try ItemID(validating: "physical-ui-chair")
        let command = try InventorySaleCommand(operationId: .init(validating: "ui-pending-sale"),
            accountId: accountId, actorPrincipalId: .init(validating: "principal-ui-test"),
            capturedAt: Date(timeIntervalSince1970: 1000),
            payload: .init(projectId: .init(validating: "project-ui-test"), currency: .init(validating: "USD"),
                items: [.init(itemId: itemId, placementId: .init(validating: "physical-ui-placement"),
                    priceRevision: 0, reviewedPriceMinorUnits: 100,
                    newPlacementId: .init(validating: "ui-sale-destination"), occurrenceId: .init(validating: "ui-sale-charge"))]))
        return try .init(command: command, projectName: "UI Test Project", itemId: itemId, state: .queued)
    }

    func readDownloadedItemPlacementHistory(accountId: AccountID, itemId: ItemID) async throws -> DownloadedItemPlacementHistory {
        let pending = try pendingSale(accountId: accountId)
        let inventory = ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-inventory-space")
        return try DownloadedItemPlacementHistory(accountId: accountId, itemId: itemId,
            description: "Downloaded test chair", intervals: [
                .init(placementId: EntityID(validating: pending == nil ? "history-current" : "physical-ui-placement"),
                    scope: inventory ? .businessInventory : .project(ProjectID(validating: "project-ui-test")),
                    spaceId: SpaceID(validating: "space-ui-test"),
                    projectDisplayName: inventory ? nil : "Current test Project", spaceDisplayName: "Current test Space",
                    startedAt: "2026-09-02T12:00:00Z", endedAt: nil),
                .init(placementId: EntityID(validating: "history-earlier"),
                    scope: .businessInventory, spaceId: SpaceID(validating: "old-space"),
                    startedAt: "2026-09-01T12:00:00Z", endedAt: "2026-09-02T12:00:00Z")
            ], details: .init(name: "Downloaded test chair", description: "Oak chair with woven seat",
                sku: "CHAIR-001", source: "Original vendor", currentSource: "Design Inventory",
                notes: "Keep the woven seat dry.\nPlace beside the window.",
                workflowStatusRaw: "to-purchase", isBookmarked: true, createdAt: "2026-09-01T11:00:00Z"),
            currentBudgetCategoryName: inventory || ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-category-unavailable")
                ? nil : "Furniture",
            currentAccountingResolution: inventory || ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-accounting-unavailable")
                ? nil : .accountedFor, pendingSale: pending)
    }
    func watchDownloadedItemPlacementHistory(accountId: AccountID, itemId: ItemID) -> AsyncThrowingStream<DownloadedItemPlacementHistory, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(try await readDownloadedItemPlacementHistory(accountId: accountId, itemId: itemId))
                    // Remain a live subscription until the Item route cancels.
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    func watchDownloadedItemPlacements(accountId: AccountID, scope: ItemPlacementScope) -> AsyncThrowingStream<DownloadedItemPlacements, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(try await readDownloadedItemPlacements(accountId: accountId, scope: scope))
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    func readDownloadedItemPlacements(accountId: AccountID, scope: ItemPlacementScope) async throws -> DownloadedItemPlacements {
        if ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-item-groups") {
            let rows = try [("group-a", "Group chair", "Store", "Design Inventory"),
                            ("group-b", "Renamed copy", "store", "Design Inventory"),
                            ("group-c", "Other vendor chair", "Other vendor", "Other vendor")].map { id, name, source, current in
                try PhysicalItemPlacement(itemId: .init(validating: id), description: name, itemRevision: 1,
                    placementId: .init(validating: "placement-\(id)"), scope: scope, spaceId: nil,
                    sku: "CHAIR-1", source: source, currentSource: current)
            }
            return try .init(accountId: accountId, scope: scope, rows: rows)
        }
        let pending = try pendingSale(accountId: accountId)
        let row = try PhysicalItemPlacement(itemId: ItemID(validating: "physical-ui-chair"),
            description: "Downloaded test chair", itemRevision: 1,
            placementId: EntityID(validating: "physical-ui-placement"), scope: pending == nil ? scope : .businessInventory,
            spaceId: SpaceID(validating: "space-ui-test"), workflowStatusRaw: "to-purchase", isBookmarked: true,
            imageCount: ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-item-images") ? 2 : 0)
        let elsewhere = try PhysicalItemPlacement(itemId: ItemID(validating: "physical-ui-other-space"),
            description: "Item assigned to another Space", itemRevision: 1,
            placementId: EntityID(validating: "physical-ui-other-placement"), scope: scope,
            spaceId: SpaceID(validating: "other-space-ui-test"), createdAt: Date(timeIntervalSince1970: 1),
            workflowStatusRaw: "returned", isBookmarked: false, imageCount: 1)
        let unassigned = try PhysicalItemPlacement(itemId: ItemID(validating: "physical-ui-unassigned"),
            description: "Unassigned test Item", itemRevision: 1,
            placementId: EntityID(validating: "physical-ui-unassigned-placement"), scope: scope, spaceId: nil,
            sku: "SKU-UNASSIGNED", createdAt: Date(timeIntervalSince1970: 2))
        var rows = [row, elsewhere, unassigned]
        if let pending {
            rows.removeFirst()
            if scope == .project(pending.projectId), let destination = try pending.resolve(source: row, current: row) {
                rows.insert(destination, at: 0)
            }
        }
        return try DownloadedItemPlacements(accountId: accountId, scope: scope, rows: rows, spaces: [
            .init(id: .init(validating: "space-ui-test"), accountId: accountId, scope: scope, displayName: "Current test Space"),
            .init(id: .init(validating: "other-space-ui-test"), accountId: accountId, scope: scope, displayName: "Archived test Space", isArchived: true),
            .init(id: .init(validating: "empty-space-ui-test"), accountId: accountId, scope: scope, displayName: "Empty test Space")
        ])
    }
}

#if os(iOS)
/// Explicit user-initiated paste, not a synchronous cross-app clipboard read
/// from the XCTest runner. Only the isolated Copy test enables this receiver.
/// https://developer.apple.com/documentation/swiftui/pastebutton
private struct UITestReportCopyReceiver: View {
    let showsExactText: Bool
    @State private var result = "No copied report received"

    var body: some View {
        VStack {
            if showsExactText {
                // Materialize text through the native typed paste API. Item ID
                // assertions still inspect the actual clipboard payload.
                PasteButton(payloadType: String.self) { strings in
                    result = strings.first ?? "Missing copied text"
                }
                .accessibilityIdentifier("target-ui-fixture-paste-report")
            } else {
              PasteButton(supportedContentTypes: [.pdf, .commaSeparatedText, .utf8PlainText, .fileURL]) { providers in
                result = "Reading copied report"
                guard let provider = providers.first else { result = "Missing copied report"; return }
                let contentTypes: [UTType] = [.pdf, .commaSeparatedText, .utf8PlainText]
                if let type = contentTypes.first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) }) {
                    provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                        finish(data)
                    }
                } else {
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                        let fileURL = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                        guard let url = fileURL, url.isFileURL else { finish(nil); return }
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        // A dead scratch-file URL must fail, not count as a copy.
                        finish(try? Data(contentsOf: url))
                    }
                }
            }
            .accessibilityIdentifier("target-ui-fixture-paste-report")
            }
            Text(result).accessibilityIdentifier("target-ui-fixture-paste-result")
        }
    }

    private nonisolated func finish(_ data: Data?) {
        let message: String
        if showsExactText, let data, let text = String(data: data, encoding: .utf8) { message = text }
        else if let data, data.starts(with: Data("%PDF-".utf8)) { message = "PDF content received" }
        else if let data, String(decoding: data, as: UTF8.self).contains("Report test chair") { message = "CSV content received" }
        else { message = "Copied report content unavailable" }
        Task { @MainActor in result = message }
    }
}
#endif

private struct UITestFixtureReportWatcher: PropertyManagementReportWatching, PropertyManagementReportReading,
    ClientSummaryPhysicalReportWatching, ClientSummaryPhysicalReportReading {
    func watchClientSummaryPhysicalReport(accountId: AccountID, projectId: ProjectID)
        -> AsyncThrowingStream<ClientSummaryPhysicalReportUpdate, Error> {
        AsyncThrowingStream { continuation in
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--ledger-ui-test-report-loading") { return }
            if arguments.contains("--ledger-ui-test-report-incomplete") { continuation.yield(.incomplete); return }
            if arguments.contains("--ledger-ui-test-report-failed") {
                continuation.finish(throwing: ClientSummaryPhysicalReportFailure.scopeMismatch)
                return
            }
            do {
                continuation.yield(.ready(try clientSnapshot(accountId: accountId, projectId: projectId,
                    asOf: .init(validating: 1_789_500_000_000))))
            } catch { continuation.finish(throwing: error) }
        }
    }

    func readDownloadedClientSummaryPhysicalReport(accountId: AccountID, projectId: ProjectID,
        asOf: ProtectedArtifactEpochMilliseconds) async throws -> ClientSummaryPhysicalReportSnapshot {
        if ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-report-export-denied") {
            throw ClientSummaryPhysicalReportFailure.scopeMismatch
        }
        return try clientSnapshot(accountId: accountId, projectId: projectId, asOf: asOf)
    }

    private func clientSnapshot(accountId: AccountID, projectId: ProjectID,
        asOf: ProtectedArtifactEpochMilliseconds) throws -> ClientSummaryPhysicalReportSnapshot {
        let physical = try snapshot(accountId: accountId, projectId: projectId,
            currency: CurrencyCode(validating: "USD"), asOf: asOf)
        let items = try physical.groups.flatMap(\.rows).map { item in
            ClientSummaryPhysicalReportItem(accountId: accountId, projectId: projectId,
                itemId: item.itemId, placementId: item.placementId, spaceId: item.spaceId,
                name: item.name, sku: item.sku,
                category: .known(categoryId: try BudgetCategoryID(validating: "furnishings-ui"), name: "Furnishings"),
                itemRevision: item.itemRevision, accounting: item.accounting)
        }
        return try .build(project: physical.project,
            client: .known(clientId: ClientID(validating: "client-ui-test"), name: "Report Client", revision: 1),
            spaces: physical.groups.compactMap { group in
                group.spaceId.map { .init(accountId: accountId, projectId: projectId, spaceId: $0, name: group.name, revision: 1) }
            }, items: items, provenance: .init(accountId: accountId, projectId: projectId,
                principalId: PrincipalID(validating: "principal-ui-test"),
                visibilityScopeID: .make(bytes: Data("client-report-ui".utf8)),
                localDataVersion: .init(validating: "client-report-ui-1"),
                authorityVersion: .init(validating: "client-summary-physical-v1"),
                asOf: asOf, readiness: .ready, lastSyncedAt: .init(validating: 1_789_500_000_000)))
    }

    func watchPropertyManagementReport(accountId: AccountID, projectId: ProjectID,
        currency: CurrencyCode) -> AsyncThrowingStream<PropertyManagementReportUpdate, Error> {
        AsyncThrowingStream { continuation in
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--ledger-ui-test-report-loading") { return }
            if arguments.contains("--ledger-ui-test-report-incomplete") {
                continuation.yield(.incomplete)
                return
            }
            if arguments.contains("--ledger-ui-test-report-failed") {
                continuation.finish(throwing: PropertyManagementReportFailure.scopeMismatch)
                return
            }
            do {
                continuation.yield(.ready(try snapshot(accountId: accountId, projectId: projectId, currency: currency,
                    asOf: .init(validating: 1_789_500_000_000))))
                // Every refresh owns a distinct stream until cancellation.
            } catch { continuation.finish(throwing: error) }
        }
    }

    func readDownloadedPropertyManagementReport(accountId: AccountID, projectId: ProjectID,
        currency: CurrencyCode, asOf: ProtectedArtifactEpochMilliseconds) async throws -> PropertyManagementReportSnapshot {
        if ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-report-export-denied") {
            throw PropertyManagementReportFailure.scopeMismatch
        }
        return try snapshot(accountId: accountId, projectId: projectId, currency: currency, asOf: asOf)
    }

    private func snapshot(accountId: AccountID, projectId: ProjectID, currency: CurrencyCode,
        asOf: ProtectedArtifactEpochMilliseconds) throws -> PropertyManagementReportSnapshot {
                func accounting(_ id: String, spaceId: SpaceID? = nil, accounted: Bool = true) throws -> ProjectItemAccountingRow {
                    let itemId = try ItemID(validating: id)
                    let occurrences: [BillableItemAccountingOccurrence] = accounted ? [
                        .init(id: try BillableItemOccurrenceID(validating: "charge-" + id),
                              accountId: accountId, projectId: projectId, itemId: itemId,
                              polarity: .charge, phase: .availableToInvoice)
                    ] : []
                    return try .init(evidence: .init(accountId: accountId, projectId: projectId,
                        clientId: ClientID(validating: "client-ui-test"), itemId: itemId, spaceId: spaceId,
                        billableOccurrences: occurrences), relationshipAbsenceIsAuthoritative: true)
                }
                let item = try PropertyManagementReportItem(accountId: accountId, projectId: projectId,
                    itemId: ItemID(validating: "report-ui-chair"), placementId: EntityID(validating: "report-ui-placement"),
                    spaceId: nil, name: "Report test chair", sku: "CHAIR-001", marketValue: nil, itemRevision: 1,
                    accounting: accounting("report-ui-chair"))
                // Existing report count/value assertions must exclude this
                // known capture, even though it has a price in another currency.
                let excluded = try PropertyManagementReportItem(accountId: accountId, projectId: projectId,
                    itemId: ItemID(validating: "report-ui-capture"), placementId: EntityID(validating: "report-ui-capture-placement"),
                    spaceId: nil, name: "Report excluded capture", sku: nil,
                    marketValue: Money(minorUnits: 99999, currency: CurrencyCode(validating: "EUR")), itemRevision: 1,
                    accounting: accounting("report-ui-capture", accounted: false))
                var items = [item, excluded]
                var spaces: [PropertyManagementReportSpace] = []
                if ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-report-grouped") {
                    let room = try SpaceID(validating: "report-ui-living-room")
                    spaces = [.init(accountId: accountId, projectId: projectId, spaceId: room,
                        name: "Report Living Room", revision: 1)]
                    items += try [
                        .init(accountId: accountId, projectId: projectId,
                            itemId: ItemID(validating: "report-ui-table"), placementId: EntityID(validating: "report-ui-table-placement"),
                            spaceId: room, name: "Report test table", sku: "TABLE-002",
                            marketValue: .init(minorUnits: 12345, currency: currency), itemRevision: 1,
                            accounting: accounting("report-ui-table", spaceId: room)),
                        .init(accountId: accountId, projectId: projectId,
                            itemId: ItemID(validating: "report-ui-lamp"), placementId: EntityID(validating: "report-ui-lamp-placement"),
                            spaceId: room, name: "Report test lamp", sku: nil,
                            marketValue: .zero(currency: currency), itemRevision: 1,
                            accounting: accounting("report-ui-lamp", spaceId: room))
                    ]
                }
                return try PropertyManagementReportSnapshot.build(
                    project: .init(accountId: accountId, projectId: projectId, name: "Report test property",
                        address: "123 Synthetic Street", revision: 1), spaces: spaces,
                    items: ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-report-empty") ? [] : items, currency: currency,
                    provenance: .init(accountId: accountId, projectId: projectId,
                        principalId: PrincipalID(validating: "principal-ui-test"),
                        visibilityScopeID: .make(bytes: Data("report-ui-fixture".utf8)),
                        localDataVersion: .init(validating: "report-ui-1"),
                        authorityVersion: .init(validating: "property-management-v1"),
                        asOf: asOf, readiness: .ready,
                        lastSyncedAt: .init(validating: 1_789_500_000_000)))
    }
}
#endif
