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
                Text("How many copies of \"\(item.name)\" would you like to create?")
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
                        .font(.system(size: 48, weight: .bold, design: .rounded))
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
        let service = ItemsService(syncTracker: NoOpSyncTracker())
        // Build copy with nil id so Firestore auto-assigns a new document ID
        var copyItem = item
        copyItem.id = nil

        Task {
            do {
                for _ in 0..<copyCount {
                    _ = try service.createItem(accountId: accountId, item: copyItem)
                    createdCount += 1
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
