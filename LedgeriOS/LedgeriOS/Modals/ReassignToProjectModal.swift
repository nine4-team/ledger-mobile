import SwiftUI

/// Corrects items into a transaction in another project without creating
/// financial movement transactions. Use SellToProjectModal for actual sales.
struct ReassignToProjectModal: View {
    let items: [Item]
    let onComplete: () -> Void

    @Environment(AccountContext.self) private var accountContext
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var selectedProject: Project?

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

            if let selectedProject {
                transactionStep(project: selectedProject)
            } else {
                ProjectPickerList { project in
                    selectedProject = project
                }
            }
        }
        .disabled(isSaving)
    }

    private func transactionStep(project: Project) -> some View {
        let projectTransactions = accountContext.allTransactions.filter { $0.projectId == project.id }
        return VStack(alignment: .leading, spacing: Spacing.md) {
            if projectTransactions.isEmpty {
                ContentUnavailableView(
                    "No transactions",
                    systemImage: "arrow.left.arrow.right",
                    description: Text("Create a destination transaction in this project before correcting items into it.")
                )
            } else {
                TransactionPickerModal(
                    transactions: projectTransactions,
                    selectedId: nil,
                    onSelect: { transaction in
                        move(to: project, transaction: transaction)
                    }
                )
            }
        }
    }

    private func move(to project: Project, transaction: Transaction) {
        guard let accountId = accountContext.currentAccountId,
              let projectId = project.id,
              let transactionId = transaction.id else { return }

        isSaving = true
        let service = InventoryOperationsService()
        Task {
            do {
                try await service.reassignToProject(
                    items: items,
                    destinationTransactionId: transactionId,
                    destinationProjectId: projectId,
                    destinationBudgetCategoryId: transaction.budgetCategoryId,
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
