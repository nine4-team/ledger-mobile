import Foundation
import LedgerTargetCore
import Observation

public struct ActiveWorkspaceToSpaceChecklistStagingRuntime: Sendable {
    public let projectBrowsing: ProjectBrowsingStagingRuntime
    public let spaceBrowsing: SpaceBrowserStagingRuntime
    public let checklistToggle: SpaceChecklistItemToggleStagingRuntime
    public let itemReader: (any DownloadedItemPlacementReading)?
    public let reportWatcher: (any PropertyManagementReportWatching)?
    public let reportReader: (any PropertyManagementReportReading)?
    public let categoryWatch: (@Sendable () -> AsyncThrowingStream<BudgetCategoryReferenceSnapshot, Error>)?

    public init(
        projectBrowsing: ProjectBrowsingStagingRuntime,
        spaceBrowsing: SpaceBrowserStagingRuntime,
        checklistToggle: SpaceChecklistItemToggleStagingRuntime,
        itemReader: (any DownloadedItemPlacementReading)? = nil,
        reportWatcher: (any PropertyManagementReportWatching)? = nil,
        reportReader: (any PropertyManagementReportReading)? = nil,
        categoryWatch: (@Sendable () -> AsyncThrowingStream<BudgetCategoryReferenceSnapshot, Error>)? = nil
    ) {
        self.projectBrowsing = projectBrowsing
        self.spaceBrowsing = spaceBrowsing
        self.checklistToggle = checklistToggle
        self.itemReader = itemReader
        self.reportWatcher = reportWatcher
        self.reportReader = reportReader
        self.categoryWatch = categoryWatch
    }
}

public enum ActiveWorkspaceToSpaceChecklistRoute: Equatable, Sendable {
    case projectDirectory
    case businessInventory
    case inventorySpaceDetail(SpaceID)
    case projectWorkspace(ProjectID)
    case projectNotes(ProjectID)
    case projectSpaces(ProjectID)
    case spaceDetail(projectId: ProjectID, spaceId: SpaceID)
    case stopped
}

public enum InventoryWorkspaceSection: String, CaseIterable, Sendable {
    case items, transactions, spaces

    public init(savedValue: String?) {
        self = savedValue.flatMap(Self.init(rawValue:)) ?? .items
    }

    public static func preferenceKey(accountId: AccountID) -> String {
        "ledger.target.inventory.section.\(accountId.rawValue)"
    }

    public static func remembered(accountId: AccountID, defaults: UserDefaults = .standard) -> Self {
        Self(savedValue: defaults.string(forKey: preferenceKey(accountId: accountId)))
    }

    public func remember(accountId: AccountID, defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.preferenceKey(accountId: accountId))
    }
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

    public private(set) var route: ActiveWorkspaceToSpaceChecklistRoute = .stopped {
        didSet { if oldValue != route { closeVendorDocumentReview() } }
    }
    public private(set) var vendorDocumentReview: LocalVendorDocumentReview?

    public func openVendorDocumentReview() {
        guard runtime != nil, case .projectWorkspace = route, representedProjectIsAvailable else { return }
        closeVendorDocumentReview()
        vendorDocumentReview = LocalVendorDocumentReview(accountId: accountId)
    }

    public func closeVendorDocumentReview() {
        vendorDocumentReview?.close()
        vendorDocumentReview = nil
    }
    public private(set) var isChecklistsExpanded = true
    public private(set) var directorySegment: ProjectDirectorySegment = .active
    public private(set) var inventorySection: InventoryWorkspaceSection = .items

    public func openBusinessInventory(savedSection: String? = nil) async {
        guard let runtime, route == .projectDirectory, directorySegment == .active else { return }
        generation &+= 1
        let activeGeneration = generation
        route = .businessInventory
        inventorySection = InventoryWorkspaceSection(savedValue: savedSection)
        await checklistToggle.receiveDetailUpdate(nil, selectedSpaceId: nil)
        guard generation == activeGeneration else { return }
        await spaceBrowser.start(scope: .businessInventory, runtime: runtime.spaceBrowsing)
    }

    public func selectInventorySection(_ section: InventoryWorkspaceSection) {
        guard route == .businessInventory else { return }
        inventorySelectionGeneration &+= 1
        inventorySection = section
    }

    public var representedSpaceScope: SpaceCreationScope? {
        switch route {
        case .businessInventory, .inventorySpaceDetail: .businessInventory
        case .projectSpaces(let id), .spaceDetail(let id, _): .project(id)
        default: nil
        }
    }

    public var representedSpaceScopeIsAvailable: Bool {
        guard runtime != nil, let scope = representedSpaceScope, spaceBrowser.scope == scope else { return false }
        if case .project = scope { return representedProjectIsActive }
        return true
    }

    public var directoryProjects: [ProjectDirectoryCoreRow] {
        let rows = directorySegment == .active ? projectBrowser.activeProjects : projectBrowser.archivedProjects
        return rows.sorted {
            let comparison = $0.projectDisplayName.rawValue.localizedCaseInsensitiveCompare($1.projectDisplayName.rawValue)
            if comparison == .orderedSame { return $0.projectId.rawValue < $1.projectId.rawValue }
            return comparison == .orderedAscending
        }
    }

    public var representedProjectIsAvailable: Bool {
        representedProjectId.map { isRepresentedProject($0, segment: directorySegment) } == true
    }

    public func setDirectorySegment(_ segment: ProjectDirectorySegment) {
        guard case .projectDirectory = route, directorySegment != segment else { return }
        generation &+= 1
        directorySegment = segment
    }

    public var representedProjectId: ProjectID? {
        switch route {
        case .projectWorkspace(let projectId), .projectSpaces(let projectId), .projectNotes(let projectId):
            projectId
        case .spaceDetail(let projectId, _):
            projectId
        case .projectDirectory, .businessInventory, .inventorySpaceDetail, .stopped:
            nil
        }
    }

    public var representedSpaceId: SpaceID? {
        if case .inventorySpaceDetail(let spaceId) = route { return spaceId }
        guard case .spaceDetail(_, let spaceId) = route else { return nil }
        return spaceId
    }

    public var representedProjectIsActive: Bool {
        representedProjectId.map(isRepresentedActiveProject) == true
    }

    public let accountId: AccountID
    public var itemReader: (any DownloadedItemPlacementReading)? { runtime?.itemReader }
    public var reportWatcher: (any PropertyManagementReportWatching)? { runtime?.reportWatcher }
    public var reportReader: (any PropertyManagementReportReading)? { runtime?.reportReader }
    public var categoryWatch: (@Sendable () -> AsyncThrowingStream<BudgetCategoryReferenceSnapshot, Error>)? { runtime?.categoryWatch }
    private var runtime: ActiveWorkspaceToSpaceChecklistStagingRuntime?
    private var generation: UInt64 = 0
    private var inventorySelectionGeneration: UInt64 = 0
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
        directorySegment = .active
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
        let segment = directorySegment
        let lifecycle: DirectoryLifecycleState = segment == .active ? .active : .archived
        guard runtime != nil,
              directoryProjects.filter({ $0.projectId == projectId }).count == 1,
              directoryProjects.first(where: { $0.projectId == projectId })?
                .projectLifecycle == lifecycle else { return }

        generation &+= 1
        let activeGeneration = generation
        await checklistToggle.receiveDetailUpdate(nil, selectedSpaceId: nil)
        guard generation == activeGeneration else { return }
        await spaceBrowser.stop()
        guard generation == activeGeneration else { return }
        await projectBrowser.select(projectId: projectId, segment: segment)
        guard generation == activeGeneration,
              projectBrowser.selectedProjectId == projectId,
              projectBrowser.selectedProject?.projectLifecycle == lifecycle else { return }
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
              isRepresentedProject(projectId, segment: directorySegment) else { return }
        generation &+= 1
        route = .projectNotes(projectId)
    }

    public func selectSpace(spaceId: SpaceID) async {
        let capturedRoute = route
        let capturedSelectionGeneration = inventorySelectionGeneration
        guard let scope = representedSpaceScope,
              representedSpaceScopeIsAvailable,
              (route == .businessInventory && inventorySection == .spaces || representedProjectId.map { route == .projectSpaces($0) } == true),
              spaceBrowser.spaces.filter({ $0.id == spaceId }).count == 1,
              spaceBrowser.spaces.first(where: { $0.id == spaceId })?.lifecycle == .active else {
            return
        }

        generation &+= 1
        let activeGeneration = generation
        await checklistToggle.receiveDetailUpdate(nil, selectedSpaceId: nil)
        guard generation == activeGeneration, route == capturedRoute,
              scope != .businessInventory || inventorySelectionGeneration == capturedSelectionGeneration else { return }
        await spaceBrowser.select(spaceId: spaceId)
        guard generation == activeGeneration, route == capturedRoute,
              scope != .businessInventory || inventorySelectionGeneration == capturedSelectionGeneration else { return }
        guard representedSpaceScopeIsAvailable,
              spaceBrowser.scope == scope,
              spaceBrowser.selectedSpaceId == spaceId else {
            await checklistToggle.receiveDetailUpdate(nil, selectedSpaceId: nil)
            guard generation == activeGeneration else { return }
            await spaceBrowser.clearSelection()
            return
        }
        switch scope {
        case .project(let projectId): route = .spaceDetail(projectId: projectId, spaceId: spaceId)
        case .businessInventory: route = .inventorySpaceDetail(spaceId)
        }
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
            if let spaceId = representedSpaceId,
               representedSpaceScopeIsAvailable,
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
        guard representedSpaceId != nil else { return }
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
              representedSpaceScopeIsAvailable,
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
        case .inventorySpaceDetail:
            route = .businessInventory
            await checklistToggle.receiveDetailUpdate(nil, selectedSpaceId: nil)
            guard generation == activeGeneration else { return }
            await spaceBrowser.clearSelection()

        case .businessInventory:
            route = .projectDirectory
            await checklistToggle.receiveDetailUpdate(nil, selectedSpaceId: nil)
            guard generation == activeGeneration else { return }
            await spaceBrowser.stop()

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
        isRepresentedProject(projectId, segment: .active)
    }

    private func isRepresentedProject(_ projectId: ProjectID, segment: ProjectDirectorySegment) -> Bool {
        let lifecycle: DirectoryLifecycleState = segment == .active ? .active : .archived
        let rows = segment == .active ? projectBrowser.activeProjects : projectBrowser.archivedProjects
        guard projectBrowser.selectedProjectId == projectId,
              projectBrowser.selectedProject?.projectLifecycle == lifecycle,
              rows.filter({ $0.projectId == projectId }).count == 1 else {
            return false
        }
        guard let detailState = projectBrowser.detailPresentation?.state else {
            return true
        }
        switch detailState {
        case .found(let content), .retryable(cached: .some(let content)),
             .requiredUpdate(cached: .some(let content)):
            return content.projectId == projectId
                && content.projectLifecycle == lifecycle
                && (content.clientLifecycle == .active || segment == .archived)
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
              !isRepresentedProject(projectId, segment: directorySegment) else { return }

        generation &+= 1
        let revocationGeneration = generation
        closeVendorDocumentReview()
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
