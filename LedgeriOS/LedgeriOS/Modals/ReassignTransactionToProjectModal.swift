import SwiftUI

/// Moves a transaction to a different project by updating its projectId.
/// Unlike item reassignment, transactions don't create sale records when moved between contexts.
struct ReassignTransactionToProjectModal: View {
    let transaction: Transaction
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
                move(to: project)
            }
        }
        .disabled(isSaving)
    }

    private func move(to project: Project) {
        guard let accountId = accountContext.currentAccountId,
              let transactionId = transaction.id,
              let projectId = project.id else { return }
        isSaving = true
        let service = TransactionsService()
        Task {
            do {
                try await service.updateTransaction(
                    accountId: accountId,
                    transactionId: transactionId,
                    fields: ["projectId": projectId]
                )
                await MainActor.run {
                    onComplete()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to reassign transaction. Please try again."
                    isSaving = false
                }
            }
        }
    }
}
