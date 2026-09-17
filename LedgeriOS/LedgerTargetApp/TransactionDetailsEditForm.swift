import LedgerTargetAppModel
import LedgerTargetCore
import SwiftUI

/// Provider binding only: uses the existing form shell, fields and notes editor.
struct TransactionDetailsEditForm: View {
    @State var session: TransactionDetailsEditSession
    var notesOnly = false
    @State private var saveRequest: UUID?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ItemDetailsFormPresentation(title: notesOnly ? "Edit Notes" : "Edit Details", isSaving: session.saving || session.loading,
            isSaveDisabled: session.receipt != nil,
            error: session.error, hint: session.hint,
            closeTitle: session.receipt == nil ? "Cancel" : "Close", onSave: { saveRequest = UUID() }) {
              Group {
                if notesOnly {
                    NotesEditorField(text: $session.draft.notes)
                        .accessibilityIdentifier("target-transaction-notes-entry")
                } else {
                    FormField(label: "Vendor / Source", text: $session.draft.source, placeholder: "e.g. Amazon, Wayfair")
                        .accessibilityIdentifier("target-transaction-source-entry")
                    FormField(label: "Payment Method", text: $session.draft.paymentMethod, placeholder: "Unknown")
                        .accessibilityIdentifier("target-transaction-payment-method-entry")
                    FormSelect(label: "Email Receipt", selection: Binding(
                        get: { session.draft.hasEmailReceipt.map { $0 ? "yes" : "no" } ?? "unknown" },
                        set: { session.draft.hasEmailReceipt = $0 == "unknown" ? nil : $0 == "yes" }),
                        options: (session.draft.original.hasEmailReceipt == nil ? [("unknown", "Unknown")] : [])
                            + [("yes", "Yes"), ("no", "No")])
                    Text("Accounting fields are managed by their accounting workflows.")
                        .font(Typography.caption).foregroundStyle(BrandColors.textSecondary)
                }
              }.disabled(session.fieldsLocked)
            }
            .disabled(session.saving)
            .task { await session.loadPending() }
            .task(id: saveRequest) {
                guard saveRequest != nil else { return }
                if await session.save() { dismiss() }
            }
            .task(id: session.receipt?.operationId) { await session.observeStatus() }
    }
}
