#if DEBUG
import LedgerTargetAppModel
import LedgerTargetCore
import Observation
import SwiftUI

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

            List {
                Section("Fixture evidence") {
                    Text("Accepted invocations: \(fixture.acceptedInvocationCount)")
                        .accessibilityIdentifier("target-ui-fixture-acceptance-count")
                        .accessibilityValue(String(fixture.acceptedInvocationCount))
                    Button("Simulate Account removal") { fixture.simulateRemoval() }
                        .accessibilityIdentifier("target-ui-fixture-remove-account")
                }

                WorkspaceAccessGate(access: fixture.access) {
                    ActiveWorkspaceToSpaceChecklistStagingView(model: fixture.model)
                }
            }
        }
        .task { await fixture.start() }
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
        let spaceRow = SpaceListSourceRow(
            id: spaceId,
            accountId: accountId,
            scope: .project(projectId),
            displayName: try! SpaceDisplayName(validating: "UI Test Space"),
            lifecycle: .active,
            revision: 3,
            checklists: checklists
        )
        let spaceListRequest = try! SpaceListRequest(
            accountId: accountId,
            scope: .project(projectId)
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
            scope: .project(projectId),
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
        await model.start(runtime: ActiveWorkspaceToSpaceChecklistStagingRuntime(
            projectBrowsing: ProjectBrowsingStagingRuntime(
                // Each subscription gets the current snapshot, including after Back.
                // A cancelled AsyncStream cannot be reused as a new database watch.
                watchProjects: { [projectDirectorySnapshot] in
                    AsyncThrowingStream { $0.yield(projectDirectorySnapshot) }
                },
                watchProject: { [projectDetail] _ in projectDetail.stream },
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
                            continuation.yield(try ProjectNotePage(
                                request: request,
                                local: ListLocalSnapshot(
                                    queryFingerprint: request.queryFingerprint, rows: [note],
                                    visibleRowCountBeforeFiltering: 1, isCompleteForQuery: true,
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
                listQuery: UITestFixtureSpaceListQuery(source: spaceDirectory),
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
            itemReader: UITestFixtureItemReader()
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

    func watchSpaces(
        _ request: SpaceListRequest
    ) -> AsyncThrowingStream<SpaceListUpdate, Error> {
        source.stream
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
private struct UITestFixtureItemReader: DownloadedItemPlacementReading {
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
#endif
