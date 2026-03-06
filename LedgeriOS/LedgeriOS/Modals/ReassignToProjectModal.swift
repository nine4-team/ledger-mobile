import SwiftUI

/// Moves items to a different project.
/// Per spec (reassign-vs-sell.md), moving between projects is always a cross-scope SELL
/// (project → inventory → project). This modal delegates to `sellToProject` accordingly.
/// Items use their own `budgetCategoryId` — no category selection step is shown here.
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
        isSaving = true
        let service = InventoryOperationsService()
        let itemsToSell = items
        Task {
            do {
                // Moving to a different project is a sell (cross-scope), not a reassign.
                // See reassign-vs-sell.md: reassign = same scope, sell = different scope.
                try await service.sellToProject(
                    items: itemsToSell,
                    destinationProjectId: projectId,
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
