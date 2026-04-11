import FirebaseFirestore
import SwiftUI

/// Creates duplicate copies of an item.
struct MakeCopiesModal: View {
    let item: Item
    let accountId: String

    @Environment(\.dismiss) private var dismiss

    @State private var copyCount = 1
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let minCount = 1
    private let maxCount = 20

    var body: some View {
        FormSheet(
            title: "Make Copies",
            primaryAction: FormSheetAction(
                title: "Create \(copyCount) Cop\(copyCount == 1 ? "y" : "ies")",
                isLoading: isSaving,
                action: { createCopies() }
            ),
            secondaryAction: FormSheetAction(title: "Cancel") {
                dismiss()
            },
            error: errorMessage
        ) {
            VStack(spacing: Spacing.lg) {
                Text("How many copies of \"\(item.displayName)\" would you like to create?")
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textSecondary)

                HStack(spacing: Spacing.xl) {
                    Button {
                        if copyCount > minCount { copyCount -= 1 }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(copyCount > minCount ? BrandColors.primary : BrandColors.textDisabled)
                    }
                    .buttonStyle(.plain)
                    .disabled(copyCount <= minCount)

                    Text("\(copyCount)")
                        .font(.custom("AvenirNext-Bold", size: 48))
                        .foregroundStyle(BrandColors.textPrimary)
                        .frame(minWidth: 60, alignment: .center)

                    Button {
                        if copyCount < maxCount { copyCount += 1 }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(copyCount < maxCount ? BrandColors.primary : BrandColors.textDisabled)
                    }
                    .buttonStyle(.plain)
                    .disabled(copyCount >= maxCount)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func createCopies() {
        isSaving = true
        errorMessage = nil
        let service = ItemsService()
        // Build copy with nil id so Firestore auto-assigns a new document ID
        var copyItem = item
        copyItem.id = nil

        Task {
            do {
                var newItemIds: [String] = []
                for _ in 0..<copyCount {
                    let newId = try service.createItem(accountId: accountId, item: copyItem)
                    newItemIds.append(newId)
                }

                // If the source item belongs to a transaction, add copies to it
                if let transactionId = item.transactionId {
                    let txRepo = FirestoreRepository<Transaction>(
                        path: "accounts/\(accountId)/transactions"
                    )
                    try await txRepo.update(id: transactionId, fields: [
                        "itemIds": FieldValue.arrayUnion(newItemIds),
                        "updatedAt": FieldValue.serverTimestamp()
                    ])
                }

                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to create copies. Please try again."
                    isSaving = false
                }
            }
        }
    }
}
