import Foundation
import LedgerTargetCore
import Observation

public struct ActiveWorkspaceToSpaceChecklistStagingRuntime: Sendable {
    public let projectBrowsing: ProjectBrowsingStagingRuntime
    public let spaceBrowsing: SpaceBrowserStagingRuntime
    public let checklistToggle: SpaceChecklistItemToggleStagingRuntime

    public init(
        projectBrowsing: ProjectBrowsingStagingRuntime,
        spaceBrowsing: SpaceBrowserStagingRuntime,
        checklistToggle: SpaceChecklistItemToggleStagingRuntime
    ) {
        self.projectBrowsing = projectBrowsing
        self.spaceBrowsing = spaceBrowsing
        self.checklistToggle = checklistToggle
    }
}

public enum ActiveWorkspaceToSpaceChecklistRoute: Equatable, Sendable {
    case projectDirectory
    case projectWorkspace(ProjectID)
    case projectNotes(ProjectID)
    case projectSpaces(ProjectID)
    case spaceDetail(projectId: ProjectID, spaceId: SpaceID)
    case stopped
}

/// Coordinates Project -> Spaces -> checklist and read-only Project Notes paths.
/// Data validation and operation ownership remain in the existing browser and
/// checklist models; this type adds route identity and cross-model drainage.
@MainActor
@Observable
public final class ActiveWorkspaceToSpaceChecklistStagingExercise {
    public let projectBrowser: ProjectBrowsingStagingExercise
    public let spaceBrowser: SpaceBrowserStagingExercise
    public let checklistToggle: SpaceChecklistItemToggleStagingExercise

    public private(set) var route: ActiveWorkspaceToSpaceChecklistRoute = .stopped
    public private(set) var isChecklistsExpanded = true

    public var representedProjectId: ProjectID? {
        switch route {
        case .projectWorkspace(let projectId), .projectSpaces(let projectId), .projectNotes(let projectId):
            projectId
        case .spaceDetail(let projectId, _):
            projectId
        case .projectDirectory, .stopped:
            nil
        }
    }

    public var representedSpaceId: SpaceID? {
        guard case .spaceDetail(_, let spaceId) = route else { return nil }
        return spaceId
    }

    public var representedProjectIsActive: Bool {
        representedProjectId.map(isRepresentedActiveProject) == true
    }

    private let accountId: AccountID
    private var runtime: ActiveWorkspaceToSpaceChecklistStagingRuntime?
    private var generation: UInt64 = 0
    private var projectEvidenceTask: Task<Void, Never>?
    private var projectObservationGeneration = UUID()

    public init(
        accountId: AccountID,
        projectBrowser: ProjectBrowsingStagingExercise,
        spaceBrowser: SpaceBrowserStagingExercise,
        checklistToggle: SpaceChecklistItemToggleStagingExercise
    ) {
        self.accountId = accountId
        self.projectBrowser = projectBrowser
        self.spaceBrowser = spaceBrowser
        self.checklistToggle = checklistToggle
    }

    public func start(runtime: ActiveWorkspaceToSpaceChecklistStagingRuntime) async {
        generation &+= 1
        projectObservationGeneration = UUID()
        let activeGeneration = generation
        let observationGeneration = projectObservationGeneration
        let oldProjectEvidenceTask = projectEvidenceTask
        projectEvidenceTask = nil
        self.runtime = nil
        route = .projectDirectory
        isChecklistsExpanded = true

        oldProjectEvidenceTask?.cancel()
        await oldProjectEvidenceTask?.value
        await spaceBrowser.stop()
        guard generation == activeGeneration else { return }
        await checklistToggle.start(runtime: runtime.checklistToggle)
        guard generation == activeGeneration else { return }
        await projectBrowser.start(runtime: runtime.projectBrowsing)
        guard generation == activeGeneration else { return }
        self.runtime = runtime
        let evidenceChanges = projectBrowser.evidenceChanges()
        projectEvidenceTask = Task { [weak self] in
            await self?.observeProjectEvidence(
                evidenceChanges,
                observationGeneration: observationGeneration
            )
        }
    }

    public func selectProject(projectId: ProjectID) async {
        guard runtime != nil,
              projectBrowser.activeProjects.filter({ $0.projectId == projectId }).count == 1,
              projectBrowser.activeProjects.first(where: { $0.projectId == projectId })?
                .projectLifecycle == .active else { return }

        generation &+= 1
        let activeGeneration = generation
        await checklistToggle.receiveDetailUpdate(nil, selectedSpaceId: nil)
        guard generation == activeGeneration else { return }
        await spaceBrowser.stop()
        guard generation == activeGeneration else { return }
        await projectBrowser.select(projectId: projectId, segment: .active)
        guard generation == activeGeneration,
              projectBrowser.selectedProjectId == projectId,
              projectBrowser.selectedProject?.projectLifecycle == .active else { return }
        route = .projectWorkspace(projectId)
        isChecklistsExpanded = true
    }

    public func openSpacesTab() async {
        guard let runtime,
              case .projectWorkspace(let projectId) = route,
              isRepresentedActiveProject(projectId) else { return }

        generation &+= 1
        let activeGeneration = generation
        await checklistToggle.receiveDetailUpdate(nil, selectedSpaceId: nil)
        guard generation == activeGeneration else { return }
        await spaceBrowser.start(
            scope: .project(projectId),
            runtime: runtime.spaceBrowsing
        )
        guard generation == activeGeneration else { return }
        guard isRepresentedActiveProject(projectId),
              spaceBrowser.scope == .project(projectId) else {
            await checklistToggle.receiveDetailUpdate(nil, selectedSpaceId: nil)
            guard generation == activeGeneration else { return }
            await spaceBrowser.stop()
            return
        }
        route = .projectSpaces(projectId)
        isChecklistsExpanded = true
    }

    public func openNotesTab() {
        guard runtime != nil,
              case .projectWorkspace(let projectId) = route,
              isRepresentedActiveProject(projectId) else { return }
        generation &+= 1
        route = .projectNotes(projectId)
    }

    public func selectSpace(spaceId: SpaceID) async {
        guard case .projectSpaces(let projectId) = route,
              isRepresentedActiveProject(projectId),
              spaceBrowser.scope == .project(projectId),
              spaceBrowser.spaces.filter({ $0.id == spaceId }).count == 1,
              spaceBrowser.spaces.first(where: { $0.id == spaceId })?.lifecycle == .active else {
            return
        }

        generation &+= 1
        let activeGeneration = generation
        await checklistToggle.receiveDetailUpdate(nil, selectedSpaceId: nil)
        guard generation == activeGeneration else { return }
        await spaceBrowser.select(spaceId: spaceId)
        guard generation == activeGeneration else { return }
        guard isRepresentedActiveProject(projectId),
              spaceBrowser.scope == .project(projectId),
              spaceBrowser.selectedSpaceId == spaceId else {
            await checklistToggle.receiveDetailUpdate(nil, selectedSpaceId: nil)
            guard generation == activeGeneration else { return }
            await spaceBrowser.clearSelection()
            return
        }
        route = .spaceDetail(projectId: projectId, spaceId: spaceId)
        isChecklistsExpanded = true
        await synchronizeChecklistEvidence()
    }

    public func synchronizeChecklistEvidence() async {
        while true {
            let activeGeneration = generation
            if route == .stopped {
                await checklistToggle.stop()
                guard generation != activeGeneration else { return }
                continue
            }
            let update: SpaceCoreDetailsUpdate?
            let selectedSpaceId: SpaceID?
            if case .spaceDetail(let projectId, let spaceId) = route,
               isRepresentedActiveProject(projectId),
               spaceBrowser.scope == .project(projectId),
               spaceBrowser.selectedSpaceId == spaceId {
                update = spaceBrowser.detailModel.currentUpdate
                selectedSpaceId = spaceId
            } else {
                update = nil
                selectedSpaceId = nil
            }
            await checklistToggle.receiveDetailUpdate(
                update,
                selectedSpaceId: selectedSpaceId
            )
            guard generation != activeGeneration else { return }
        }
    }

    public func toggleChecklistsExpanded() {
        guard case .spaceDetail = route else { return }
        isChecklistsExpanded.toggle()
    }

    public func toggleChecklistItem(
        checklistId: SpaceChecklistID,
        itemId: SpaceChecklistItemID
    ) async {
        let activeGeneration = generation
        let capturedRoute = route
        await synchronizeChecklistEvidence()
        guard generation == activeGeneration,
              route == capturedRoute,
              representedProjectId.map(isRepresentedActiveProject) == true,
              checklistToggle.canToggle(checklistId: checklistId, itemId: itemId) else {
            return
        }
        await checklistToggle.toggle(checklistId: checklistId, itemId: itemId)
    }

    public func back() async {
        guard let runtime else { return }
        generation &+= 1
        let activeGeneration = generation

        switch route {
        case .projectNotes(let projectId):
            route = .projectWorkspace(projectId)

        case .spaceDetail(let projectId, _):
            route = .projectSpaces(projectId)
            isChecklistsExpanded = true
            await checklistToggle.receiveDetailUpdate(nil, selectedSpaceId: nil)
            guard generation == activeGeneration else { return }
            await spaceBrowser.clearSelection()

        case .projectSpaces(let projectId):
            route = .projectWorkspace(projectId)
            isChecklistsExpanded = true
            await checklistToggle.receiveDetailUpdate(nil, selectedSpaceId: nil)
            guard generation == activeGeneration else { return }
            await spaceBrowser.stop()

        case .projectWorkspace:
            route = .projectDirectory
            isChecklistsExpanded = true
            await checklistToggle.receiveDetailUpdate(nil, selectedSpaceId: nil)
            guard generation == activeGeneration else { return }
            await spaceBrowser.stop()
            guard generation == activeGeneration else { return }
            await projectBrowser.start(runtime: runtime.projectBrowsing)

        case .projectDirectory, .stopped:
            break
        }
    }

    public func stop() async {
        generation &+= 1
        projectObservationGeneration = UUID()
        let activeGeneration = generation
        let oldProjectEvidenceTask = projectEvidenceTask
        projectEvidenceTask = nil
        runtime = nil
        route = .stopped
        isChecklistsExpanded = true

        oldProjectEvidenceTask?.cancel()
        await oldProjectEvidenceTask?.value
        await checklistToggle.stop()
        guard generation == activeGeneration else { return }
        await spaceBrowser.stop()
        guard generation == activeGeneration else { return }
        await projectBrowser.stop()
    }

    private func isRepresentedActiveProject(_ projectId: ProjectID) -> Bool {
        guard projectBrowser.selectedProjectId == projectId,
              projectBrowser.selectedProject?.projectLifecycle == .active,
              projectBrowser.activeProjects.filter({ $0.projectId == projectId }).count == 1 else {
            return false
        }
        guard let detailState = projectBrowser.detailPresentation?.state else {
            return true
        }
        switch detailState {
        case .found(let content), .retryable(cached: .some(let content)),
             .requiredUpdate(cached: .some(let content)):
            return content.projectId == projectId
                && content.projectLifecycle == .active
                && content.clientLifecycle == .active
        case .waiting, .incomplete,
             .retryable(cached: .none), .requiredUpdate(cached: .none):
            return true
        case .authoritativeAbsence, .unavailable:
            return false
        }
    }

    private func observeProjectEvidence(
        _ changes: AsyncStream<UInt64>,
        observationGeneration: UUID
    ) async {
        for await _ in changes {
            guard !Task.isCancelled,
                  projectObservationGeneration == observationGeneration else { return }
            await projectEvidenceDidChange(observationGeneration: observationGeneration)
        }
    }

    private func projectEvidenceDidChange(observationGeneration: UUID) async {
        guard runtime != nil,
              projectObservationGeneration == observationGeneration else { return }
        guard let projectId = representedProjectId,
              !isRepresentedActiveProject(projectId) else { return }

        generation &+= 1
        let revocationGeneration = generation
        route = .projectWorkspace(projectId)
        isChecklistsExpanded = true
        await checklistToggle.receiveDetailUpdate(nil, selectedSpaceId: nil)
        guard generation == revocationGeneration,
              projectObservationGeneration == observationGeneration else { return }
        await spaceBrowser.stop()
        guard generation == revocationGeneration,
              projectObservationGeneration == observationGeneration else { return }
    }
}
