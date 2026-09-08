import Foundation
import LedgerTargetCore
import Testing
@testable import LedgerTargetAppModel

@Suite("Active Project workspace to Space checklist coordination")
@MainActor
struct ActiveWorkspaceToSpaceChecklistStagingExerciseTests {
    @Test("SwiftUI exposes only the catalogued route controls and honest state labels")
    func swiftUISourceContract() throws {
        let ledgerDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let view = try String(contentsOf: ledgerDirectory.appending(
            path: "LedgerTargetApp/ActiveWorkspaceToSpaceChecklistStagingComposition.swift"
        ))

        for required in [
            "target-active-project-card-",
            "target-active-project-spaces-tab",
            "target-active-space-card-",
            "Text(\"CHECKLISTS\")",
            "target-active-space-checklist-item-",
            "model.checklistToggle.operationStatus",
            "model.checklistToggle.canToggle(",
            "await model.toggleChecklistItem(",
            "Cached Project Space data is available.",
            "No Spaces in this Project.",
            "Exact Space details are loading or unavailable.",
            "Rejected checklist changes are preserved for review.",
            "target-vendor-pdf-open",
            "LocalVendorDocumentReviewView(",
            "runtime.watchBudgetCategories()",
            "vendorReview?.close()",
        ] {
            #expect(view.contains(required), "Missing route UI contract token: \(required)")
        }

        for excluded in [
            "Business Inventory",
            "Add Project",
            "Archive Project",
            "Button(\"Edit\")",
            "Retry local acceptance",
            "Item count",
            "Text(\"Budget",
            "Button(\"Budget",
            "Section(\"Budget",
            "Media",
            "Delete Space",
        ] {
            #expect(!view.contains(excluded), "Out-of-scope control escaped: \(excluded)")
        }
    }

    @Test("Represented stable IDs derive the exact Project and Space scopes")
    func exactRepresentedRoute() async throws {
        let projectDirectory = RouteSource<ProjectListSnapshot>()
        let projectDetail = RouteSource<ProjectCoreDetailsUpdate>()
        let spaceDirectory = RouteSource<SpaceListUpdate>()
        let spaceDetail = RouteSource<SpaceCoreDetailsUpdate>()
        let projectRequests = RouteRecorder<ProjectCoreDetailsRequest>()
        let listRequests = RouteRecorder<SpaceListRequest>()
        let detailRequests = RouteRecorder<SpaceCoreDetailsRequest>()
        let model = Self.model()

        await model.start(runtime: Self.runtime(
            projectDirectory: projectDirectory,
            projectDetail: projectDetail,
            spaceDirectory: spaceDirectory,
            spaceDetail: spaceDetail,
            projectRequests: projectRequests,
            listRequests: listRequests,
            detailRequests: detailRequests
        ))
        #expect(model.route == .projectDirectory)

        let selectedProject = try Self.project("project-selected", name: "Same Name")
        let sameNameProject = try Self.project("project-other", name: "Same Name")
        projectDirectory.yield(try Self.projectList([sameNameProject, selectedProject]))
        await Self.wait { model.projectBrowser.activeProjects.count == 2 }

        await model.selectProject(projectId: try ProjectID(validating: "not-represented"))
        #expect(model.route == .projectDirectory)
        #expect(projectRequests.values.isEmpty)

        await model.selectProject(projectId: selectedProject.id)
        await Self.wait { projectRequests.values.count == 1 }
        #expect(projectRequests.values[0].accountId == Self.accountId)
        #expect(projectRequests.values[0].projectId == selectedProject.id)
        #expect(model.route == .projectWorkspace(selectedProject.id))

        model.openNotesTab()
        #expect(model.route == .projectNotes(selectedProject.id))
        #expect(model.representedProjectId == selectedProject.id)
        #expect(model.projectBrowser.noteHistory.selectedProjectId == selectedProject.id)
        await model.back()
        #expect(model.route == .projectWorkspace(selectedProject.id))

        await model.openSpacesTab()
        await Self.wait { listRequests.values.count == 1 }
        #expect(listRequests.values[0].accountId == Self.accountId)
        #expect(listRequests.values[0].scope == .project(selectedProject.id))
        #expect(model.route == .projectSpaces(selectedProject.id))

        let selectedSpace = try Self.space("space-selected", name: "Same Space", project: selectedProject.id)
        let sameNameSpace = try Self.space("space-other", name: "Same Space", project: selectedProject.id)
        spaceDirectory.yield(try Self.spaceList(
            [sameNameSpace, selectedSpace], project: selectedProject.id
        ))
        await Self.wait { model.spaceBrowser.spaces.count == 2 }

        await model.selectSpace(spaceId: try SpaceID(validating: "not-represented"))
        #expect(detailRequests.values.isEmpty)
        #expect(model.route == .projectSpaces(selectedProject.id))

        await model.selectSpace(spaceId: selectedSpace.id)
        await Self.wait { detailRequests.values.count == 1 }
        #expect(detailRequests.values[0] == (try SpaceCoreDetailsRequest(
            accountId: Self.accountId,
            spaceId: selectedSpace.id
        )))
        #expect(model.route == .spaceDetail(
            projectId: selectedProject.id,
            spaceId: selectedSpace.id
        ))

        let collection = try Self.checklists()
        spaceDetail.yield(try Self.spaceDetail(
            selectedSpace.id,
            project: selectedProject.id,
            collection: collection
        ))
        await Self.wait { model.spaceBrowser.detailModel.row?.id == selectedSpace.id }
        await model.synchronizeChecklistEvidence()
        #expect(model.checklistToggle.displayedCollection == collection)
        #expect(model.checklistToggle.admission == .ready)
        #expect(model.checklistToggle.canToggle(
            checklistId: Self.checklistId,
            itemId: Self.itemId
        ))

        projectDirectory.yield(try Self.projectList([]))
        await Self.wait { model.projectBrowser.activeProjects.isEmpty }
        await Self.wait {
            model.route == .projectWorkspace(selectedProject.id)
                && spaceDirectory.terminationCount == 1
                && spaceDetail.terminationCount == 1
        }
        #expect(!model.representedProjectIsActive)
        #expect(model.checklistToggle.selectedSpaceId == nil)
        #expect(!model.checklistToggle.canToggle(
            checklistId: Self.checklistId,
            itemId: Self.itemId
        ))

        await model.stop()
        #expect(model.route == .stopped)
        #expect(projectDirectory.terminationCount == 1)
        #expect(spaceDirectory.terminationCount == 1)
        #expect(spaceDetail.terminationCount == 1)
    }

    @Test("Notes route closes and cannot reopen when its Project disappears")
    func notesRouteClosesWhenProjectDisappears() async throws {
        let directory = RouteSource<ProjectListSnapshot>()
        let model = Self.model()
        await model.start(runtime: Self.runtime(
            projectDirectory: directory, projectDetail: RouteSource(),
            spaceDirectory: RouteSource(), spaceDetail: RouteSource(),
            projectRequests: RouteRecorder(), listRequests: RouteRecorder(),
            detailRequests: RouteRecorder()
        ))
        let project = try Self.project("notes-project")
        directory.yield(try Self.projectList([project]))
        await Self.wait { model.projectBrowser.activeProjects.count == 1 }
        await model.selectProject(projectId: project.id)
        model.openNotesTab()
        #expect(model.route == .projectNotes(project.id))
        directory.yield(try Self.projectList([]))
        await Self.wait {
            model.route == .projectWorkspace(project.id)
                && model.projectBrowser.noteHistory.selectedProjectId == nil
        }
        #expect(!model.representedProjectIsActive)
        model.openNotesTab()
        #expect(model.route == .projectWorkspace(project.id))
        await model.stop()
    }

    @Test("Archived Project selection preserves history but refuses active-only actions")
    func archivedProjectReadRouteKeepsActiveActionsClosed() async throws {
        let directory = RouteSource<ProjectListSnapshot>()
        let model = Self.model()
        await model.start(runtime: Self.runtime(
            projectDirectory: directory, projectDetail: RouteSource(),
            spaceDirectory: RouteSource(), spaceDetail: RouteSource(),
            projectRequests: RouteRecorder(), listRequests: RouteRecorder(),
            detailRequests: RouteRecorder()
        ))
        let active = try Self.project("active-project")
        let archived = try Self.project("archived-project", lifecycle: .archived)
        directory.yield(try Self.projectList([active, archived]))
        await Self.wait { model.projectBrowser.archivedProjects.count == 1 }
        #expect(model.directoryProjects.map(\.projectId) == [active.id])
        model.setDirectorySegment(.archived)
        #expect(model.directoryProjects.map(\.projectId) == [archived.id])
        await model.selectProject(projectId: active.id)
        #expect(model.route == .projectDirectory)
        await model.selectProject(projectId: archived.id)
        #expect(model.representedProjectIsAvailable)
        #expect(!model.representedProjectIsActive)
        await model.openSpacesTab()
        #expect(model.route == .projectWorkspace(archived.id))
        model.openNotesTab()
        #expect(model.route == .projectNotes(archived.id))
        model.setDirectorySegment(.active)
        #expect(model.directorySegment == .archived)
        await model.back()
        await model.back()
        #expect(model.route == .projectDirectory)
        #expect(model.directorySegment == .archived)
        await model.stop()
    }

    @Test("Back drains exact routes and restarts an unselected Project directory")
    func backAndStopDrainage() async throws {
        let projectDirectory = RouteSource<ProjectListSnapshot>()
        let restartedProjectDirectory = RouteSource<ProjectListSnapshot>()
        let spaceDirectory = RouteSource<SpaceListUpdate>()
        let spaceDetail = RouteSource<SpaceCoreDetailsUpdate>()
        let projectWatchCount = RouteCounter()
        let project = try Self.project("project-selected")
        let space = try Self.space("space-selected", project: project.id)
        let model = Self.model()
        let runtime = ActiveWorkspaceToSpaceChecklistStagingRuntime(
            projectBrowsing: ProjectBrowsingStagingRuntime(
                watchProjects: {
                    projectWatchCount.increment()
                    return projectWatchCount.value == 1
                        ? projectDirectory.stream
                        : restartedProjectDirectory.stream
                },
                watchProject: { _ in AsyncThrowingStream { _ in } }
            ),
            spaceBrowsing: SpaceBrowserStagingRuntime(
                listQuery: RouteListQuery { _ in spaceDirectory.stream },
                detailQuery: RouteDetailQuery { _ in spaceDetail.stream }
            ),
            checklistToggle: Self.toggleRuntime()
        )

        await model.start(runtime: runtime)
        projectDirectory.yield(try Self.projectList([project]))
        await Self.wait { model.projectBrowser.activeProjects.count == 1 }
        await model.selectProject(projectId: project.id)
        await model.openSpacesTab()
        spaceDirectory.yield(try Self.spaceList([space], project: project.id))
        await Self.wait { model.spaceBrowser.spaces.count == 1 }
        await model.selectSpace(spaceId: space.id)
        #expect(model.route == .spaceDetail(projectId: project.id, spaceId: space.id))

        model.toggleChecklistsExpanded()
        #expect(!model.isChecklistsExpanded)
        await model.back()
        #expect(model.route == .projectSpaces(project.id))
        #expect(model.isChecklistsExpanded)
        #expect(spaceDetail.terminationCount == 1)
        #expect(model.checklistToggle.selectedSpaceId == nil)

        await model.back()
        #expect(model.route == .projectWorkspace(project.id))
        #expect(spaceDirectory.terminationCount == 1)

        await model.back()
        #expect(model.route == .projectDirectory)
        await Self.wait { projectWatchCount.value == 2 }
        #expect(projectDirectory.terminationCount == 1)
        #expect(model.projectBrowser.selectedProjectId == nil)

        await model.stop()
        #expect(restartedProjectDirectory.terminationCount == 1)
        #expect(model.checklistToggle.admission == .stopped)
        await model.synchronizeChecklistEvidence()
        #expect(model.checklistToggle.admission == .stopped)
    }

    @Test("The composed route submits one existing durable checklist command")
    func composedToggleSubmission() async throws {
        let projectDirectory = RouteSource<ProjectListSnapshot>()
        let spaceDirectory = RouteSource<SpaceListUpdate>()
        let spaceDetail = RouteSource<SpaceCoreDetailsUpdate>()
        let acceptance = RouteChecklistAcceptance()
        let project = try Self.project("project-selected")
        let space = try Self.space("space-selected", project: project.id)
        let model = Self.model()
        let runtime = ActiveWorkspaceToSpaceChecklistStagingRuntime(
            projectBrowsing: ProjectBrowsingStagingRuntime(
                watchProjects: { projectDirectory.stream },
                watchProject: { _ in AsyncThrowingStream { _ in } }
            ),
            spaceBrowsing: SpaceBrowserStagingRuntime(
                listQuery: RouteListQuery { _ in spaceDirectory.stream },
                detailQuery: RouteDetailQuery { _ in spaceDetail.stream }
            ),
            checklistToggle: Self.toggleRuntime(acceptance: acceptance)
        )

        await model.start(runtime: runtime)
        projectDirectory.yield(try Self.projectList([project]))
        await Self.wait { model.projectBrowser.activeProjects.count == 1 }
        await model.selectProject(projectId: project.id)
        await model.openSpacesTab()
        spaceDirectory.yield(try Self.spaceList([space], project: project.id))
        await Self.wait { model.spaceBrowser.spaces.count == 1 }
        await model.selectSpace(spaceId: space.id)
        spaceDetail.yield(try Self.spaceDetail(
            space.id,
            project: project.id,
            collection: Self.checklists()
        ))
        await Self.wait { model.spaceBrowser.detailModel.row?.id == space.id }
        await model.synchronizeChecklistEvidence()
        await Self.wait {
            model.checklistToggle.canToggle(
                checklistId: Self.checklistId,
                itemId: Self.itemId
            )
        }

        await model.toggleChecklistItem(
            checklistId: Self.checklistId,
            itemId: Self.itemId
        )
        await Self.wait { model.checklistToggle.operationState == .queued }
        let commands = await acceptance.commands()
        let command = try #require(commands.first)
        #expect(commands.count == 1)
        #expect(command.draft.spaceId == space.id)
        #expect(command.draft.collection.checklists[0].items[0].isChecked)

        await model.toggleChecklistItem(
            checklistId: Self.checklistId,
            itemId: Self.itemId
        )
        #expect((await acceptance.commands()).count == 1)
        await model.stop()
    }

    private static let accountId = try! AccountID(validating: "account-route")
    private static let principalId = try! PrincipalID(validating: "principal-route")
    private static let checklistId = try! SpaceChecklistID(validating: "checklist-route")
    private static let itemId = try! SpaceChecklistItemID(validating: "item-route")
    private static let observedAt = Date(timeIntervalSince1970: 1_789_500_000)

    private static func model() -> ActiveWorkspaceToSpaceChecklistStagingExercise {
        let projectBrowser = ProjectBrowsingStagingExercise(accountId: accountId)
        let spaceBrowser = SpaceBrowserStagingExercise(accountId: accountId)
        let toggle = SpaceChecklistItemToggleStagingExercise(
            accountId: accountId,
            actorPrincipalId: principalId,
            operationContractVersion: try! OperationContractVersion(
                validating: "space-checklist-revision-v1"
            ),
            makeIdentity: {
                SpaceChecklistItemToggleSubmissionIdentity(
                    operationId: try OperationID(validating: "operation-route")
                )
            },
            now: { observedAt }
        )
        return ActiveWorkspaceToSpaceChecklistStagingExercise(
            accountId: accountId,
            projectBrowser: projectBrowser,
            spaceBrowser: spaceBrowser,
            checklistToggle: toggle
        )
    }

    private static func runtime(
        projectDirectory: RouteSource<ProjectListSnapshot>,
        projectDetail: RouteSource<ProjectCoreDetailsUpdate>,
        spaceDirectory: RouteSource<SpaceListUpdate>,
        spaceDetail: RouteSource<SpaceCoreDetailsUpdate>,
        projectRequests: RouteRecorder<ProjectCoreDetailsRequest>,
        listRequests: RouteRecorder<SpaceListRequest>,
        detailRequests: RouteRecorder<SpaceCoreDetailsRequest>
    ) -> ActiveWorkspaceToSpaceChecklistStagingRuntime {
        ActiveWorkspaceToSpaceChecklistStagingRuntime(
            projectBrowsing: ProjectBrowsingStagingRuntime(
                watchProjects: { projectDirectory.stream },
                watchProject: {
                    projectRequests.record($0)
                    return projectDetail.stream
                }
            ),
            spaceBrowsing: SpaceBrowserStagingRuntime(
                listQuery: RouteListQuery {
                    listRequests.record($0)
                    return spaceDirectory.stream
                },
                detailQuery: RouteDetailQuery {
                    detailRequests.record($0)
                    return spaceDetail.stream
                }
            ),
            checklistToggle: toggleRuntime()
        )
    }

    private static func toggleRuntime(
        acceptance: RouteChecklistAcceptance? = nil
    ) -> SpaceChecklistItemToggleStagingRuntime {
        SpaceChecklistItemToggleStagingRuntime(
            reviseChecklists: { command in
                guard let acceptance else { throw CancellationError() }
                return await acceptance.accept(command)
            },
            watchOperation: { _ in AsyncThrowingStream { _ in } },
            rejectedOperations: { request in
                try RejectedOperationRecoverySnapshot(request: request, candidates: [])
            },
            watchRejectedOperations: { request in
                AsyncThrowingStream { continuation in
                    do {
                        continuation.yield(try RejectedOperationRecoverySnapshot(
                            request: request,
                            candidates: []
                        ))
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        )
    }

    private static func project(_ id: String, name: String = "Project", lifecycle: DirectoryLifecycleState = .active) throws -> ProjectSummary {
        let client = try ClientSummary(
            id: ClientID(validating: "client-route"),
            accountId: accountId,
            displayName: ClientDisplayName(validating: "Client"),
            lifecycle: .active,
            createdAt: observedAt,
            updatedAt: observedAt
        )
        return try ProjectSummary(
            id: ProjectID(validating: id),
            accountId: accountId,
            clientId: client.id,
            client: client,
            displayName: ProjectDisplayName(validating: name),
            description: nil,
            lifecycle: lifecycle
        )
    }

    private static func projectList(_ rows: [ProjectSummary]) throws -> ProjectListSnapshot {
        try ProjectListSnapshot(
            accountId: accountId,
            local: ListLocalSnapshot(
                queryFingerprint: ListQueryFingerprint(
                    validating: String(repeating: "1", count: 64)
                ),
                rows: rows,
                visibleRowCountBeforeFiltering: rows.count,
                isCompleteForQuery: true,
                quality: .ready,
                localDataVersion: LocalDataVersion(validating: "route-projects"),
                asOf: observedAt
            )
        )
    }

    private static func space(
        _ id: String,
        name: String = "Space",
        project: ProjectID
    ) throws -> SpaceListSourceRow {
        SpaceListSourceRow(
            id: try SpaceID(validating: id),
            accountId: accountId,
            scope: .project(project),
            displayName: try SpaceDisplayName(validating: name),
            lifecycle: .active,
            revision: 1,
            checklists: try SpaceChecklistCollection(checklists: [])
        )
    }

    private static func spaceList(
        _ rows: [SpaceListSourceRow],
        project: ProjectID
    ) throws -> SpaceListUpdate {
        let request = try SpaceListRequest(accountId: accountId, scope: .project(project))
        return try SpaceListUpdate(
            request: request,
            state: .snapshot(SpaceListLocalSnapshot(
                request: request,
                rows: rows,
                visibleRowCountBeforeFiltering: rows.count,
                isCompleteForQuery: true,
                quality: .ready,
                localDataVersion: LocalDataVersion(validating: "route-spaces"),
                asOf: observedAt
            ))
        )
    }

    private static func checklists() throws -> SpaceChecklistCollection {
        try SpaceChecklistCollection(checklists: [
            SpaceChecklistState(
                id: checklistId,
                name: SpaceChecklistName(validating: "Installation"),
                presentationOrder: 0,
                items: [
                    SpaceChecklistItemState(
                        id: itemId,
                        text: SpaceChecklistItemText(validating: "Hang art"),
                        isChecked: false,
                        presentationOrder: 0
                    ),
                ]
            ),
        ])
    }

    private static func spaceDetail(
        _ spaceId: SpaceID,
        project: ProjectID,
        collection: SpaceChecklistCollection
    ) throws -> SpaceCoreDetailsUpdate {
        let request = try SpaceCoreDetailsRequest(accountId: accountId, spaceId: spaceId)
        let row = try SpaceCoreDetailsSnapshot(
            id: spaceId,
            accountId: accountId,
            scope: .project(project),
            displayName: SpaceDisplayName(validating: "Selected Space"),
            notes: SpaceCreationNotes(nil),
            lifecycle: .active,
            revision: 3,
            createdAt: observedAt,
            updatedAt: observedAt,
            checklists: collection
        )
        return try SpaceCoreDetailsUpdate(
            request: request,
            state: .snapshot(SpaceCoreDetailsLocalSnapshot(
                request: request,
                rows: [row],
                visibleRowCountBeforeFiltering: 1,
                isCompleteForQuery: true,
                quality: .ready,
                localDataVersion: LocalDataVersion(validating: "route-space-detail"),
                asOf: observedAt
            ))
        )
    }

    private static func wait(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<2_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("Timed out waiting for route state")
    }
}

private struct RouteListQuery: SpaceListQuerying {
    let watch: @Sendable (SpaceListRequest) -> AsyncThrowingStream<SpaceListUpdate, Error>
    func watchSpaces(_ request: SpaceListRequest) -> AsyncThrowingStream<SpaceListUpdate, Error> {
        watch(request)
    }
}

private struct RouteDetailQuery: SpaceCoreDetailsQuerying {
    let watch: @Sendable (SpaceCoreDetailsRequest)
        -> AsyncThrowingStream<SpaceCoreDetailsUpdate, Error>
    func watchSpaceCoreDetails(
        _ request: SpaceCoreDetailsRequest
    ) -> AsyncThrowingStream<SpaceCoreDetailsUpdate, Error> {
        watch(request)
    }
}

private final class RouteSource<Value: Sendable>: @unchecked Sendable {
    let stream: AsyncThrowingStream<Value, Error>
    private let continuation: AsyncThrowingStream<Value, Error>.Continuation
    private let terminations = RouteCounter()

    init() {
        var captured: AsyncThrowingStream<Value, Error>.Continuation!
        let terminations = terminations
        stream = AsyncThrowingStream { continuation in
            captured = continuation
            continuation.onTermination = { _ in terminations.increment() }
        }
        continuation = captured
    }

    var terminationCount: Int { terminations.value }
    func yield(_ value: Value) { continuation.yield(value) }
}

private final class RouteRecorder<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Value] = []
    var values: [Value] { lock.withLock { recorded } }
    func record(_ value: Value) { lock.withLock { recorded.append(value) } }
}

private final class RouteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

private actor RouteChecklistAcceptance {
    private var recorded: [ReviseSpaceChecklistsCommand] = []

    func accept(_ command: ReviseSpaceChecklistsCommand) -> OperationReceipt {
        recorded.append(command)
        return OperationReceipt(
            operationId: command.envelope.operationId,
            localState: .queued
        )
    }

    func commands() -> [ReviseSpaceChecklistsCommand] { recorded }
}
