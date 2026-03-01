import SwiftUI

/// Creation context for spaces — project-scoped or inventory.
enum SpaceCreationContext {
    case project(String)
    case inventory
}

/// Bottom-sheet form for creating a new space.
struct NewSpaceView: View {
    let context: SpaceCreationContext

    @Environment(AccountContext.self) private var accountContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var notes = ""

    private let spacesService = SpacesService(syncTracker: NoOpSyncTracker())

    private var isValid: Bool {
        SpaceFormValidation.isValidSpace(name: name)
    }

    private var projectId: String? {
        switch context {
        case .project(let id): return id
        case .inventory: return nil
        }
    }

    var body: some View {
        FormSheet(
            title: "New Space",
            primaryAction: FormSheetAction(title: "Create Space", isDisabled: !isValid) {
                createSpace()
            },
            secondaryAction: FormSheetAction(title: "Cancel") {
                dismiss()
            }
        ) {
            VStack(spacing: Spacing.md) {
                FormField(label: "Name *", text: $name, placeholder: "Space name")
                FormField(label: "Notes", text: $notes, placeholder: "Optional notes", axis: .vertical)

                // Template selection — stub (WP13 builds SpaceTemplatesService)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Template")
                        .font(Typography.label)
                        .foregroundStyle(BrandColors.textSecondary)

                    HStack {
                        Text("No templates available")
                            .foregroundStyle(BrandColors.textSecondary)
                        Spacer()
                    }
                    .font(Typography.input)
                    .padding(.horizontal, Spacing.md)
                    .frame(height: 44)
                    .background(BrandColors.inputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                            .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
                    )
                }
            }
        }
    }

    // MARK: - Actions

    private func createSpace() {
        guard let accountId = accountContext.currentAccountId else { return }

        var space = Space()
        space.projectId = projectId
        space.accountId = accountId
        space.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        space.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            _ = try spacesService.createSpace(accountId: accountId, space: space)
            dismiss()
        } catch {
            // Offline-first: should not fail
        }
    }
}
