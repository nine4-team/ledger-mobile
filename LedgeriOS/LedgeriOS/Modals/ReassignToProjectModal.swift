import SwiftUI

/// Moves items from their current project to a different project.
/// Uses `moveBetweenProjects` (Return + Sale) under the new per-batch model.
/// Carries forward the items' existing budgetCategoryId for the destination.
struct ReassignToProjectModal: View {
    let items: [Item]
    let onComplete: () -> Void

    @Environment(AccountContext.self) private var accountContext
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Move to Project")
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
                move(to: project)
            }
        }
        .disabled(isSaving)
    }

    private func move(to project: Project) {
        guard let accountId = accountContext.currentAccountId,
              let projectId = project.id else { return }

        // Use the first item's budgetCategoryId as default for the destination
        let categoryId = items.compactMap(\.budgetCategoryId).first ?? "uncategorized"

        isSaving = true
        let service = InventoryOperationsService()
        let itemsToMove = items
        Task {
            do {
                try await service.moveBetweenProjects(
                    items: itemsToMove,
                    destinationProjectId: projectId,
                    destinationCategoryId: categoryId,
                    accountId: accountId,
                    userId: authManager.currentUser?.uid
                )
                await MainActor.run {
                    onComplete()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to move items. Please try again."
                    isSaving = false
                }
            }
        }
    }
}
