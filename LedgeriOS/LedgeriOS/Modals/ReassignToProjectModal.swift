import SwiftUI

/// Wraps ProjectPickerList to reassign items to a different project.
/// No financial records created — this corrects misallocations.
struct ReassignToProjectModal: View {
    let items: [Item]
    let onComplete: () -> Void

    @Environment(AccountContext.self) private var accountContext
    @Environment(\.dismiss) private var dismiss

    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Reassign to Project")
                    .font(Typography.h2)
                    .foregroundStyle(BrandColors.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(BrandColors.textTertiary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.top, Spacing.screenPadding)
            .padding(.bottom, Spacing.md)

            if let error = errorMessage {
                Text(error)
                    .font(Typography.small)
                    .foregroundStyle(StatusColors.missedText)
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.bottom, Spacing.sm)
            }

            ProjectPickerList { project in
                reassign(to: project)
            }
        }
        .disabled(isSaving)
    }

    private func reassign(to project: Project) {
        guard let accountId = accountContext.currentAccountId,
              let projectId = project.id else { return }
        isSaving = true
        let service = InventoryOperationsService()
        let itemsToReassign = items
        Task {
            do {
                try await service.reassignToProject(
                    items: itemsToReassign,
                    destinationProjectId: projectId,
                    accountId: accountId
                )
                await MainActor.run {
                    onComplete()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to reassign. Please try again."
                    isSaving = false
                }
            }
        }
    }
}
