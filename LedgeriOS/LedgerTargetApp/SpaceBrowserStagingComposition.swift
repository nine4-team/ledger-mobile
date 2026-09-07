import LedgerTargetAppModel
import LedgerTargetCore
import LedgerTargetPowerSync
import SwiftUI

/// Both entry paths render the same available Space evidence. Item/media
/// projections are not wired yet; absence must not look like an empty Space.
struct SpaceDirectoryCardLabel: View {
    let space: SpaceDirectoryRowPresentation

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(space.displayName.rawValue)
                Text("Checklist: \(space.completedChecklistItemCount) of \(space.totalChecklistItemCount) complete")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Item count unavailable • Image unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var accessibilitySummary: String {
        "\(space.completedChecklistItemCount) of \(space.totalChecklistItemCount) checklist items complete; item count unavailable; image unavailable"
    }
}

enum SpaceBrowserStagingRuntimeAdapter {
  static func adapt(
    _ runtime: LedgerOfflineClientRuntime
  ) -> SpaceBrowserStagingRuntime {
    SpaceBrowserStagingRuntime(
      listQuery: runtime,
      detailQuery: runtime
    )
  }
}

struct SpaceBrowserStagingExerciseView: View {
    @Bindable var model: SpaceBrowserStagingExercise
    @Bindable var checklistToggle: SpaceChecklistItemToggleStagingExercise
    @Bindable var checklistEditor: SpaceChecklistEditorStagingExercise
    let representedProjectId: ProjectID?
    let openProject: (ProjectID) -> Void
    let openBusinessInventory: () -> Void

  var body: some View {
        Section(scopeTitle) {
            HStack {
                Button("Selected Project Spaces") {
                    if let representedProjectId {
                        openProject(representedProjectId)
                    }
                }
                .disabled(representedProjectId == nil)
                .accessibilityIdentifier("target-space-browser-open-project")

                Button("Business Inventory Spaces") {
                    openBusinessInventory()
                }
                .accessibilityIdentifier("target-space-browser-open-inventory")
            }

            LabeledContent("Space data", value: directoryStatus)
        .accessibilityIdentifier("target-space-browser-status")

      if model.spaces.isEmpty {
        emptyOrIncompleteState
      } else {
        ForEach(model.spaces, id: \.id) { space in
          Button {
            Task { await model.select(spaceId: space.id) }
          } label: {
            HStack {
              SpaceDirectoryCardLabel(space: space)
              Spacer()
              if model.selectedSpaceId == space.id {
                Image(systemName: "checkmark")
                  .accessibilityLabel("Selected")
              }
            }
          }
          .accessibilityIdentifier("target-space-row-\(space.id.rawValue)")
          .accessibilityLabel(space.displayName.rawValue)
          .accessibilityValue(
            SpaceDirectoryCardLabel(space: space).accessibilitySummary
          )
          .accessibilityHint("Opens this Space")
        }
      }

      switch model.detailPresentation {
      case .notSelected:
        Text("Select a Space to open its details.")
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("target-space-browser-not-selected")
      case .selected(let selection, _):
        LabeledContent("Selected Space", value: selection.displayName.rawValue)
          .accessibilityIdentifier("target-space-browser-selection")
      case .unavailable:
        Text("Space Unavailable.")
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("target-space-browser-selection-unavailable")
      case .stopped:
        EmptyView()
      }

      if let diagnostic = model.directoryDiagnostic {
        Text(diagnostic)
          .foregroundStyle(.red)
          .accessibilityIdentifier("target-space-browser-diagnostic")
      }
    }

    SpaceCoreDetailsStagingExerciseView(
      model: model.detailModel,
      checklistToggle: checklistToggle,
      checklistEditor: checklistEditor
    )
  }

  @ViewBuilder
  private var emptyOrIncompleteState: some View {
    switch model.directoryPresentation {
    case .authoritativeEmpty:
      Text(emptyMessage)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("target-space-browser-empty")
    case .waiting:
      Text("Waiting for exact-scope Space data.")
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("target-space-browser-waiting")
    case .partial:
      Text("Space data is incomplete.")
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("target-space-browser-partial")
    case .stale:
      Text("Showing cached Space data.")
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("target-space-browser-stale")
    case .failure:
      Text("Space data is unavailable.")
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("target-space-browser-unavailable")
    case .ready:
      Text("Space data is unavailable.")
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("target-space-browser-invalid-empty")
    case .stopped:
      EmptyView()
    }
  }

  private var scopeTitle: String {
    switch model.scope {
    case .project: "Project Spaces"
    case .businessInventory: "Business Inventory Spaces"
    case nil: "Spaces"
    }
  }

  private var emptyMessage: String {
    switch model.scope {
    case .businessInventory: "No inventory spaces yet."
    case .project, nil: "No spaces yet."
    }
  }

  private var directoryStatus: String {
    switch model.directoryPresentation {
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
