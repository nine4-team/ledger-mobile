import LedgerTargetCore
import SwiftUI

@Observable final class FeeInstallmentEntryState {
    var label = ""
    var amount = ""
    var isSaving = false
    var error: String?
    let installmentId = UUID().uuidString.lowercased()
    var attempt: (draft: FeeInstallmentDraft, uuid: UUID, date: Date)?
}

/// Only target save glue; presentation is the extracted original Fee form.
struct FeeInstallmentEntry: View {
    let service: any ProjectFeeInstallmentCreating
    let accountId: AccountID
    let projectId: ProjectID
    let category: FeeCreationCategory
    let currency: CurrencyCode
    @Bindable var state: FeeInstallmentEntryState
    let onSaved: (OperationReceipt) -> Void
    @Environment(\.dismiss) private var dismiss

    private var parsedAmount: Int64? {
        InvoiceMoneyParsing.parseCentsFromDollarString(state.amount).map(Int64.init)
    }
    var body: some View {
        FeeInstallmentFormPresentation(categoryName: category.name,
            totalText: category.configuredTotal.map { (Decimal($0.minorUnits) / 100).formatted(.currency(code: $0.currency.rawValue)) },
            label: $state.label, amount: $state.amount, isSaving: state.isSaving,
            canSave: !state.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && (parsedAmount ?? 0) > 0 && !state.isSaving,
            errorMessage: state.error, onSave: save)
    }
    private func save() {
        guard !state.isSaving, let amount = parsedAmount else { return }
        state.isSaving = true; state.error = nil
        Task { @MainActor in
            defer { state.isSaving = false }
            do {
                let draft = try FeeInstallmentDraft(accountId: accountId, projectId: projectId,
                    installmentId: .init(validating: state.installmentId), categoryId: category.id,
                    label: state.label.trimmingCharacters(in: .whitespacesAndNewlines),
                    amount: .init(minorUnits: amount, currency: category.configuredTotal?.currency ?? currency))
                if state.attempt?.draft != draft { state.attempt = (draft, UUID(), Date()) }
                guard let attempt = state.attempt else { return }
                let receipt = try await service.createFeeInstallment(draft, operationUUID: attempt.uuid, capturedAt: attempt.date)
                onSaved(receipt); dismiss()
            } catch {
                state.error = "Installment exceeds the fee total or could not be saved."
            }
        }
    }
}
