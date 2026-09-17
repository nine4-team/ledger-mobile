import LedgerTargetAppModel
import LedgerTargetCore
import SwiftUI

struct TransactionReceiptLinesEditForm: View {
    @State var session: TransactionReceiptLinesEditSession
    @State private var saveRequest: UUID?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ItemDetailsFormPresentation(title: "Edit Receipt Lines", isSaving: session.saving || session.loading,
            isSaveDisabled: session.receipt != nil, error: session.error, hint: session.hint,
            closeTitle: session.receipt == nil ? "Cancel" : "Close", onSave: { saveRequest = UUID() }) {
                Group {
                    ReceiptLineEntryFields(lines: $session.draft.entries, accessibilityPrefix: "target-transaction")
                    Text("These lines describe the receipt. They do not change the Transaction amount or create Items. You can save incomplete details; the audit will show any mismatch.")
                        .font(.caption)
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
