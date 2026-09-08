#if DEBUG
import LedgerTargetAppModel
import LedgerTargetCore
import Observation
import SwiftUI
import UniformTypeIdentifiers

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
            if ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-report-copy-receiver") {
                UITestReportCopyReceiver()
            }
            #endif

            List {
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
    private(set) var acceptedInvocationCount = 0

    private let projectDirectorySnapshot: ProjectListSnapshot
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
        let projectId = try! ProjectID(validating: "project-ui-test")
        let spaceId = try! SpaceID(validating: "space-ui-test")
        let checklistId = try! SpaceChecklistID(validating: "checklist-ui-test")
        let itemId = try! SpaceChecklistItemID(validating: "item-ui-test")
        let contractVersion = try! OperationContractVersion(
            validating: "space-checklist-revision-v1"
        )

        let client = try! ClientSummary(
            id: ClientID(validating: "client-ui-test"),
            accountId: accountId,
            displayName: ClientDisplayName(validating: "UI Test Client"),
            lifecycle: .active,
            createdAt: Self.observedAt,
            updatedAt: Self.observedAt
        )
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
                rows: [spaceRow],
                visibleRowCountBeforeFiltering: 1,
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
            lifecycle: .active,
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
            itemReader: UITestFixtureItemReader(),
            reportWatcher: UITestFixtureReportWatcher(),
            reportReader: UITestFixtureReportWatcher(),
            categoryWatch: { [accountId] in
                AsyncThrowingStream { continuation in
                    do {
                        let category = BudgetCategoryDefinitionSnapshot(
                            id: try BudgetCategoryID(validating: "category-ui-test"), accountId: accountId,
                            name: try BudgetCategoryName(validating: "Furnishings"), kind: .general,
                            lifecycle: .active, isSystem: false, excludesFromOverallBudget: false,
                            presentationOrder: 0, revision: 1)
                        continuation.yield(try BudgetCategoryReferenceSnapshot(accountId: accountId,
                            local: ListLocalSnapshot(
                                queryFingerprint: ListQueryFingerprint(validating: String(repeating: "2", count: 64)),
                                rows: [category], visibleRowCountBeforeFiltering: 1, isCompleteForQuery: true,
                                quality: .ready, localDataVersion: LocalDataVersion(validating: "ui-categories-1"),
                                asOf: Date(timeIntervalSince1970: 1_789_500_000))))
                    } catch { continuation.finish(throwing: error) }
                }
            }
        ))
    }

    func stop() async {
        access.stop()
        guard isStarted else { return }
        isStarted = false
        await model.stop()
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
private struct UITestFixtureItemReader: DownloadedItemPlacementReading, DownloadedItemPlacementHistoryReading {
    func readDownloadedItemPlacementHistory(accountId: AccountID, itemId: ItemID) async throws -> DownloadedItemPlacementHistory {
        try DownloadedItemPlacementHistory(accountId: accountId, itemId: itemId,
            description: "Downloaded test chair", intervals: [
                .init(placementId: EntityID(validating: "history-current"),
                    scope: .project(ProjectID(validating: "project-ui-test")), spaceId: nil,
                    projectDisplayName: "Current test Project", startedAt: "2026-09-02T12:00:00Z", endedAt: nil),
                .init(placementId: EntityID(validating: "history-earlier"),
                    scope: .businessInventory, spaceId: SpaceID(validating: "old-space"),
                    startedAt: "2026-09-01T12:00:00Z", endedAt: "2026-09-02T12:00:00Z")
            ])
    }
    func watchDownloadedItemPlacementHistory(accountId: AccountID, itemId: ItemID) -> AsyncThrowingStream<DownloadedItemPlacementHistory, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(try await readDownloadedItemPlacementHistory(accountId: accountId, itemId: itemId))
                    continuation.finish()
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
        let row = try PhysicalItemPlacement(itemId: ItemID(validating: "physical-ui-chair"),
            description: "Downloaded test chair", itemRevision: 1,
            placementId: EntityID(validating: "physical-ui-placement"), scope: scope, spaceId: nil)
        return try DownloadedItemPlacements(accountId: accountId, scope: scope, rows: [row])
    }
}

#if os(iOS)
/// Explicit user-initiated paste, not a synchronous cross-app clipboard read
/// from the XCTest runner. Only the isolated Copy test enables this receiver.
/// https://developer.apple.com/documentation/swiftui/pastebutton
private struct UITestReportCopyReceiver: View {
    @State private var result = "No copied report received"

    var body: some View {
        VStack {
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
            Text(result).accessibilityIdentifier("target-ui-fixture-paste-result")
        }
    }

    private nonisolated func finish(_ data: Data?) {
        let message: String
        if let data, data.starts(with: Data("%PDF-".utf8)) { message = "PDF content received" }
        else if let data, String(decoding: data, as: UTF8.self).contains("Report test chair") { message = "CSV content received" }
        else { message = "Copied report content unavailable" }
        Task { @MainActor in result = message }
    }
}
#endif

private struct UITestFixtureReportWatcher: PropertyManagementReportWatching, PropertyManagementReportReading {
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
                let item = try PropertyManagementReportItem(accountId: accountId, projectId: projectId,
                    itemId: ItemID(validating: "report-ui-chair"), placementId: EntityID(validating: "report-ui-placement"),
                    spaceId: nil, name: "Report test chair", sku: "CHAIR-001", marketValue: nil, itemRevision: 1)
                var items = [item]
                var spaces: [PropertyManagementReportSpace] = []
                if ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-report-grouped") {
                    let room = try SpaceID(validating: "report-ui-living-room")
                    spaces = [.init(accountId: accountId, projectId: projectId, spaceId: room,
                        name: "Report Living Room", revision: 1)]
                    items += try [
                        .init(accountId: accountId, projectId: projectId,
                            itemId: ItemID(validating: "report-ui-table"), placementId: EntityID(validating: "report-ui-table-placement"),
                            spaceId: room, name: "Report test table", sku: "TABLE-002",
                            marketValue: .init(minorUnits: 12345, currency: currency), itemRevision: 1),
                        .init(accountId: accountId, projectId: projectId,
                            itemId: ItemID(validating: "report-ui-lamp"), placementId: EntityID(validating: "report-ui-lamp-placement"),
                            spaceId: room, name: "Report test lamp", sku: nil,
                            marketValue: .zero(currency: currency), itemRevision: 1)
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
