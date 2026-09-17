import LedgerTargetCore
import SwiftUI

/// Target save binding; presentation and fields are the existing Item editor components.
struct ItemDetailsEditForm: View {
    enum Fields { case nameAndSKU, notes, workflowStatus }
    let service: any ItemDetailsEditing
    let fields: Fields
    private let bulkRows: [PhysicalItemPlacement]?
    @State private var draft: ItemDetailsEditDraft
    @Environment(\.dismiss) private var dismiss
    @State private var attempt: Attempt?
    @State private var saving = false
    @State private var error: String?
    @State private var saveRequest: UUID?
    @State private var operationId: OperationID?
    @State private var status: OperationSnapshot?
    private struct Attempt {
        let payload: EditItemDetailsCommand.Payload
        let id: UUID
        let capturedAt: Date
    }

    init(itemId: ItemID, details: DownloadedItemDescriptiveDetails, service: any ItemDetailsEditing,
         fields: Fields = .nameAndSKU) {
        self.service = service
        self.fields = fields
        self.bulkRows = nil
        _draft = State(initialValue: .init(itemId: itemId, original: details))
    }

    init(bulkRows: [PhysicalItemPlacement], service: any ItemDetailsEditing) {
        precondition(!bulkRows.isEmpty)
        self.service = service
        self.fields = .workflowStatus
        self.bulkRows = bulkRows
        let first = bulkRows[0]
        _draft = State(initialValue: .init(itemId: first.itemId, original: .init(
            description: first.description, workflowStatusRaw: first.workflowStatusRaw,
            itemRevision: first.itemRevision)))
    }

    var body: some View {
        ItemDetailsFormPresentation(title: title, isSaving: saving,
            isSaveDisabled: operationId != nil || draft.original.itemRevision == nil,
            error: error, hint: hint, closeTitle: operationId == nil ? "Cancel" : "Close", onSave: save) {
                if fields == .notes {
                    NotesEditorField(text: $draft.notes)
                        .disabled(attempt != nil).accessibilityIdentifier("target-item-notes-entry")
                } else if fields == .workflowStatus {
                    ItemStatusPickerRows(options: [
                        .init(id: "to purchase", label: "To Purchase", icon: "cart"),
                        .init(id: "purchased", label: "Purchased", icon: "checkmark.circle"),
                        .init(id: "to return", label: "To Return", icon: "arrow.uturn.left"),
                        .init(id: "returned", label: "Returned", icon: "arrow.uturn.left.circle.fill"),
                        .init(id: "clear", label: "Clear Status", icon: "xmark.circle")
                    ], currentID: selectedStatusID) { raw in
                        draft.selectedStatus = .init(rawValue: raw)
                    }
                    .disabled(attempt != nil)
                } else {
                    FormField(label: "Name", text: $draft.name, placeholder: "Item name")
                    .disabled(attempt != nil).accessibilityIdentifier("target-item-name-entry")
                FormField(label: "SKU", text: $draft.sku, placeholder: "Barcode or SKU number")
                    .disabled(attempt != nil).accessibilityIdentifier("target-item-sku-entry")
                }
            }
        .task(id: saveRequest) {
            guard saveRequest != nil, let attempt else { return }
            do {
                let receipt = try await service.editItemDetails(attempt.payload, operationUUID: attempt.id,
                    capturedAt: attempt.capturedAt)
                operationId = receipt.operationId; error = nil
            } catch is CancellationError {} catch {
                self.error = "The edit could not be confirmed. Save Changes retries the same edit."
            }
            saving = false
        }
        .task(id: operationId) {
            guard let operationId else { return }
            do {
                for try await value in service.watchItemDetailsEdit(operationId) { status = value }
            } catch is CancellationError {} catch {
                self.error = "Edit status is unavailable. The saved edit is retained."
            }
        }
    }

    private var title: String {
        if let bulkRows { return "Change Status for \(bulkRows.count) Items" }
        switch fields {
        case .nameAndSKU: return "Edit Name and SKU"
        case .notes: return "Edit Notes"
        case .workflowStatus: return "Change Status"
        }
    }

    private var selectedStatusID: String? {
        if let selected = draft.selectedStatus { return selected.rawValue }
        if let bulkRows, !bulkRows.allSatisfy({ $0.workflowStatus == draft.original.workflowStatus }) { return nil }
        switch draft.original.workflowStatus {
        case .notSet: return "clear"
        case .unrecognized: return nil
        default: return draft.original.workflowStatus.facetValue
        }
    }

    private var hint: String? {
        guard operationId != nil else { return nil }
        switch status?.state.phase {
        case .applied: return "Item updated. Other devices will receive it when they sync."
        case .rejected: return "The edit was not applied. Your saved operation is retained for review."
        default: return "Saved on this device. Waiting to sync; you can close this form."
        }
    }

    private func save() {
        guard !saving, operationId == nil else { return }
        if attempt == nil {
            do {
                let payload: EditItemDetailsCommand.Payload?
                if let bulkRows {
                    payload = try ItemDetailsEditDraft.bulkStatusPayload(rows: bulkRows, selected: draft.selectedStatus)
                } else { payload = try draft.payload() }
                guard let payload else { dismiss(); return }
                attempt = Attempt(payload: payload, id: UUID(), capturedAt: Date())
            } catch {
                self.error = "This Item cannot be edited with the downloaded information. Refresh its details and try again."
                return
            }
        }
        error = nil; saving = true; saveRequest = UUID()
    }
}
