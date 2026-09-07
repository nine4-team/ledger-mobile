import LedgerTargetAppModel
import LedgerTargetCore
import LedgerTargetPowerSync
import SwiftUI

enum ActiveWorkspaceToSpaceChecklistStagingRuntimeAdapter {
    static func adapt(
        _ runtime: LedgerOfflineClientRuntime
    ) -> ActiveWorkspaceToSpaceChecklistStagingRuntime {
        ActiveWorkspaceToSpaceChecklistStagingRuntime(
            projectBrowsing: ProjectBrowsingStagingRuntimeAdapter.adapt(runtime),
            spaceBrowsing: SpaceBrowserStagingRuntimeAdapter.adapt(runtime),
            checklistToggle: SpaceChecklistItemToggleStagingRuntimeAdapter.adapt(runtime)
        )
    }
}

struct ActiveWorkspaceToSpaceChecklistStagingView: View {
    @Bindable var model: ActiveWorkspaceToSpaceChecklistStagingExercise

    var body: some View {
        switch model.route {
        case .projectDirectory:
            projectDirectory
        case .projectWorkspace(let projectId):
            projectWorkspace(projectId)
        case .projectSpaces(let projectId):
            projectSpaces(projectId)
        case .spaceDetail(let projectId, let spaceId):
            spaceDetail(projectId: projectId, spaceId: spaceId)
        case .stopped:
            Section("Active Project Workspace") {
                Text("Project workspace data is stopped.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("target-active-workspace-stopped")
            }
        }
    }

    private var projectDirectory: some View {
        Section("Active Projects") {
            LabeledContent("Project data", value: model.projectBrowser.directoryStatus)
                .accessibilityIdentifier("target-active-project-directory-status")

            if model.projectBrowser.activeProjects.isEmpty {
                if model.projectBrowser.directoryPresentation?.active.isAuthoritativeEmpty == true {
                    Text("No active Projects.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("target-active-project-directory-empty")
                } else {
                    Text("Active Project data is loading or unavailable.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("target-active-project-directory-unavailable")
                }
            } else {
                ForEach(model.projectBrowser.activeProjects, id: \.projectId) { project in
                    Button {
                        Task { await model.selectProject(projectId: project.projectId) }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(project.projectDisplayName.rawValue)
                            Text(project.clientDisplayName.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityIdentifier(
                        "target-active-project-card-\(project.projectId.rawValue)"
                    )
                    .accessibilityLabel(project.projectDisplayName.rawValue)
                    .accessibilityValue(project.clientDisplayName.rawValue)
                    .accessibilityHint("Opens this Project workspace")
                }
            }

            if let diagnostic = model.projectBrowser.directoryDiagnostic {
                Text(diagnostic)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("target-active-project-directory-diagnostic")
            }
        }
    }

    private func projectWorkspace(_ projectId: ProjectID) -> some View {
        Section("Project Workspace") {
            backButton
            if model.representedProjectIsActive,
               model.projectBrowser.selectedProjectId == projectId {
                Text(model.projectBrowser.selectedProjectName ?? "Project name unavailable")
                    .font(.headline)
                    .accessibilityIdentifier("target-active-project-workspace-name")
                if let clientName = model.projectBrowser.selectedClientName {
                    Text(clientName)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("target-active-project-workspace-client")
                }
                LabeledContent("Project data", value: model.projectBrowser.detailStateLabel)
                    .accessibilityIdentifier("target-active-project-workspace-status")
                Button("Spaces") {
                    Task { await model.openSpacesTab() }
                }
                .accessibilityIdentifier("target-active-project-spaces-tab")
                .accessibilityHint("Opens Spaces for this Project")
            } else {
                Text("The represented Project is unavailable.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("target-active-project-workspace-unavailable")
            }
        }
    }

    private func projectSpaces(_ projectId: ProjectID) -> some View {
        Section("Project Spaces") {
            backButton
            Text("Spaces")
                .font(.headline)
                .accessibilityIdentifier("target-active-project-spaces-selected-tab")
            LabeledContent("Space data", value: spaceDirectoryStatus)
                .accessibilityIdentifier("target-active-project-spaces-status")

            if !model.representedProjectIsActive {
                Text("The represented Project is unavailable.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("target-active-project-spaces-project-unavailable")
            } else if model.spaceBrowser.scope != .project(projectId) {
                Text("Exact Project Space data is unavailable.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("target-active-project-spaces-scope-unavailable")
            } else if model.spaceBrowser.spaces.isEmpty {
                spaceDirectoryEmptyState
            } else {
                ForEach(model.spaceBrowser.spaces, id: \.id) { space in
                    Button {
                        Task { await model.selectSpace(spaceId: space.id) }
                    } label: {
                        Text(space.displayName.rawValue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityIdentifier("target-active-space-card-\(space.id.rawValue)")
                    .accessibilityLabel(space.displayName.rawValue)
                    .accessibilityHint("Opens this Space")
                }
            }

            if let diagnostic = model.spaceBrowser.directoryDiagnostic {
                Text(diagnostic)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("target-active-project-spaces-diagnostic")
            }
        }
    }

    @ViewBuilder
    private func spaceDetail(projectId: ProjectID, spaceId: SpaceID) -> some View {
        Section("Space") {
            backButton
            LabeledContent("Space data", value: model.spaceBrowser.detailModel.status)
                .accessibilityIdentifier("target-active-space-detail-status")

            if model.representedProjectIsActive,
               model.spaceBrowser.scope == .project(projectId),
               model.spaceBrowser.selectedSpaceId == spaceId,
               let row = model.spaceBrowser.detailModel.row,
               row.id == spaceId,
               row.scope == .project(projectId),
               row.lifecycle == .active {
                Text(row.displayName.rawValue)
                    .font(.headline)
                    .accessibilityIdentifier("target-active-space-detail-name")
                checklists
            } else if model.representedProjectIsActive,
                      model.spaceBrowser.scope == .project(projectId),
                      model.spaceBrowser.selectedSpaceId == spaceId,
                      model.spaceBrowser.detailModel.isAuthoritativelyEmpty {
                Text("No Space exists for this exact selection.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("target-active-space-detail-empty")
            } else {
                Text("Exact Space details are loading or unavailable.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("target-active-space-detail-unavailable")
            }

            if model.representedProjectIsActive,
               model.spaceBrowser.scope == .project(projectId),
               model.spaceBrowser.selectedSpaceId == spaceId {
                checklistLifecycle
            }

            if let diagnostic = model.spaceBrowser.detailModel.diagnostic {
                Text(diagnostic)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("target-active-space-detail-diagnostic")
            }
        }
        .task(id: model.spaceBrowser.detailModel.evidenceSequence) {
            await model.synchronizeChecklistEvidence()
        }
    }

    @ViewBuilder
    private var checklists: some View {
        DisclosureGroup(isExpanded: Binding(
            get: { model.isChecklistsExpanded },
            set: { expanded in
                if expanded != model.isChecklistsExpanded {
                    model.toggleChecklistsExpanded()
                }
            }
        )) {
            if let collection = model.checklistToggle.displayedCollection {
                if collection.checklists.isEmpty {
                    Text("No checklists.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("target-active-space-checklists-empty")
                } else {
                    ForEach(collection.checklists, id: \.id.rawValue) { checklist in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(checklist.name.rawValue)
                                .font(.headline)
                            ForEach(checklist.items, id: \.id.rawValue) { item in
                                Button {
                                    Task {
                                        await model.toggleChecklistItem(
                                            checklistId: checklist.id,
                                            itemId: item.id
                                        )
                                    }
                                } label: {
                                    Label(
                                        item.text.rawValue,
                                        systemImage: item.isChecked
                                            ? "checkmark.circle.fill"
                                            : "circle"
                                    )
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .disabled(!model.checklistToggle.canToggle(
                                    checklistId: checklist.id,
                                    itemId: item.id
                                ))
                                .accessibilityIdentifier(
                                    "target-active-space-checklist-item-\(checklist.id.rawValue)-\(item.id.rawValue)"
                                )
                                .accessibilityLabel(item.text.rawValue)
                                .accessibilityValue(item.isChecked ? "Checked" : "Not checked")
                                .accessibilityHint(
                                    item.isChecked
                                        ? "Marks this checklist item incomplete"
                                        : "Marks this checklist item complete"
                                )
                            }
                        }
                    }
                }
            } else {
                Text(model.checklistToggle.admission.explanation)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("target-active-space-checklists-unavailable")
            }
        } label: {
            Text("CHECKLISTS")
        }
        .accessibilityIdentifier("target-active-space-checklists-section")
        .accessibilityValue(model.isChecklistsExpanded ? "Expanded" : "Collapsed")
    }

    @ViewBuilder
    private var checklistLifecycle: some View {
        LabeledContent(
            "Checklist synchronization",
            value: model.checklistToggle.operationStatus
        )
        .accessibilityIdentifier("target-active-space-checklist-operation-status")

        if !model.checklistToggle.admission.permitsToggle {
            Text(model.checklistToggle.admission.explanation)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("target-active-space-checklist-admission")
        }
        if model.checklistToggle.rejectedRecovery != nil {
            Text("Rejected checklist changes are preserved for review.")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("target-active-space-checklist-rejected")
        }
        if let diagnostic = model.checklistToggle.diagnostic {
            Text(diagnostic)
                .foregroundStyle(.red)
                .accessibilityIdentifier("target-active-space-checklist-diagnostic")
        }
    }

    private var backButton: some View {
        Button("Back") {
            Task { await model.back() }
        }
        .accessibilityIdentifier("target-active-workspace-back")
    }

    @ViewBuilder
    private var spaceDirectoryEmptyState: some View {
        switch model.spaceBrowser.directoryPresentation {
        case .authoritativeEmpty:
            Text("No Spaces in this Project.")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("target-active-project-spaces-empty")
        case .waiting:
            Text("Exact Project Space data is loading.")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("target-active-project-spaces-loading")
        case .partial:
            Text("Project Space data is incomplete.")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("target-active-project-spaces-partial")
        case .stale:
            Text("Cached Project Space data is available.")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("target-active-project-spaces-stale")
        case .failure, .ready:
            Text("Project Space data is unavailable.")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("target-active-project-spaces-unavailable")
        case .stopped:
            Text("Project Space data is stopped.")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("target-active-project-spaces-stopped")
        }
    }

    private var spaceDirectoryStatus: String {
        switch model.spaceBrowser.directoryPresentation {
        case .waiting(let readiness): readiness.rawValue
        case .partial: "Incomplete local data"
        case .stale: "Cached local data"
        case .ready: "Ready"
        case .authoritativeEmpty: "Ready — empty"
        case .failure: "Unavailable"
        case .stopped: "Stopped"
        }
    }
}
