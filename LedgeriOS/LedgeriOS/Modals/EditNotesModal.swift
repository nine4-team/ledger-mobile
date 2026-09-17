import SwiftUI

/// Shared bottom sheet for editing free-text notes.
/// Reusable for transactions, items, spaces — takes a closure for saving.
struct EditNotesModal: View {
    let notes: String
    let onSave: (String) async throws -> Void
    let allowsEmpty: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var currentText: String
    @State private var submission = NoteSubmissionState()
    @State private var errorMessage: String?

    init(notes: String, onSave: @escaping (String) -> Void) {
        self.notes = notes
        self.onSave = { onSave($0) }
        self.allowsEmpty = true
        self._currentText = State(initialValue: notes)
    }

    init(notes: String, allowsEmpty: Bool, save: @escaping (String) async throws -> Void) {
        self.notes = notes
        self.onSave = save
        self.allowsEmpty = allowsEmpty
        self._currentText = State(initialValue: notes)
    }

    var body: some View {
        FormSheet(
            title: "Edit Notes",
            showDismissButton: !submission.isSaving,
            primaryAction: FormSheetAction(
                title: "Save",
                isLoading: submission.isSaving,
                isDisabled: submission.isSaving || submission.didSave
                    || (!allowsEmpty && currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ) {
                Task { await save() }
            },
            secondaryAction: FormSheetAction(title: "Cancel", isDisabled: submission.isSaving) {
                dismiss()
            },
            error: errorMessage
        ) {
            TextEditor(text: $currentText)
                .disabled(submission.isSaving)
                .font(Typography.body)
                .foregroundStyle(BrandColors.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(Spacing.md)
                .frame(minHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                        .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
                )
        }
        .interactiveDismissDisabled(submission.isSaving)
    }

    private func save() async {
        let text = currentText
        do {
            if try await submission.save({ try await onSave(text) }) {
                dismiss()
            }
        } catch {
            errorMessage = "Failed to update note. Please try again."
        }
    }
}

/// One submission per editor presentation. The guard lives inside the save path,
/// since disabling a button does not cancel actions that are already queued.
@MainActor
@Observable
final class NoteSubmissionState {
    private(set) var isSaving = false
    private(set) var didSave = false

    func save(_ operation: () async throws -> Void) async throws -> Bool {
        guard !isSaving, !didSave else { return false }
        isSaving = true
        defer { isSaving = false }
        try await operation()
        didSave = true
        return true
    }
}

#Preview {
    EditNotesModal(
        notes: "Sample notes for this transaction",
        onSave: { _ in }
    )
}
