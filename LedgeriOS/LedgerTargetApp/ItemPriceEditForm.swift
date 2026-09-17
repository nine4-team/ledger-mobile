import LedgerTargetCore
import SwiftUI

/// Thin target controller around the original Item editor's form and field.
struct ItemPriceEditForm: View {
    let projectId: ProjectID?
    let itemId: ItemID
    let currency: CurrencyCode
    let service: any ItemPriceEditing
    @Environment(\.dismiss) private var dismiss
    @State private var review: ItemPriceEditReview?
    @State private var originalReview: ItemPriceEditReview?
    @State private var text = ""
    @State private var prefilled = false
    @State private var saving = false
    @State private var error: String?
    @State private var attempt: Attempt?
    @State private var saveRequest: UUID?
    @State private var operationId: OperationID?
    @State private var status: OperationSnapshot?
    private struct Attempt {
        let payload: EditUncollectedItemPriceCommand.Payload
        let id: UUID
        let capturedAt: Date
    }

    var body: some View {
        ItemDetailsFormPresentation(title: "Edit Project Price", isSaving: saving,
            isSaveDisabled: operationId != nil || (review == nil && attempt == nil),
            error: error, hint: hint, closeTitle: operationId == nil ? "Cancel" : "Close", onSave: save) {
                ItemProjectPriceField(text: $text)
                    .disabled(attempt != nil || review == nil)
                    .accessibilityIdentifier("target-item-price-entry")
                if review == nil && operationId == nil {
                    Text(projectId == nil
                        ? "Price editing requires downloaded Inventory and purchase-cost records."
                        : "Price editing requires downloaded Item and billing records. Collected charges cannot be edited here.")
                        .font(Typography.caption)
                }
            }
        .task {
            do {
                for try await value in service.watchItemPriceReview(project: projectId, item: itemId) {
                    guard value == nil || (value?.projectId == projectId && value?.itemId == itemId) else {
                        review = nil; error = "The downloaded Item does not match this editor."; return
                    }
                    if let originalReview, let value, value != originalReview {
                        review = nil
                        error = "This Item changed while the editor was open. Close and reopen it to review the updated price."
                        continue
                    }
                    review = value
                    if !prefilled, let value {
                        originalReview = value
                        text = value.currentPrice.map(Self.amount) ?? ""
                        prefilled = true
                    }
                }
            } catch is CancellationError {} catch {
                review = nil; self.error = "Price editing is unavailable. Your saved work is retained."
            }
        }
        .task(id: saveRequest) {
            guard saveRequest != nil, let attempt else { return }
            do {
                let receipt = try await service.editItemPrice(attempt.payload, operationUUID: attempt.id,
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
                for try await value in service.watchItemPriceEdit(operationId) { status = value }
            } catch is CancellationError {} catch {
                self.error = "Edit status is unavailable. The saved edit is retained."
            }
        }
    }

    private var hint: String? {
        if operationId != nil {
            switch status?.state.phase {
            case .applied: return "Project price updated. Other devices will receive it when they sync."
            case .rejected: return "The edit was not applied because the Item or its accounting changed. Your saved operation is retained for review."
            default: return "Saved on this device. Waiting to sync; you can close this form."
            }
        }
        if let review, let payload = try? proposedPayload(review),
           payload.reviewedPrice.minorUnits > payload.requestedPrice.minorUnits {
            return "The project price will be raised to \(Self.amount(payload.reviewedPrice)) to match the purchase cost."
        }
        return nil
    }

    private func save() {
        guard !saving, operationId == nil else { return }
        if attempt == nil {
            guard let review else { return }
            do {
                let payload = try proposedPayload(review)
                let effectivePrice: Money? = payload.clearPrice == true && payload.reviewedPrice.minorUnits == 0
                    ? nil : payload.reviewedPrice
                if effectivePrice == review.currentPrice { dismiss(); return }
                attempt = Attempt(payload: payload, id: UUID(), capturedAt: Date())
            } catch {
                self.error = projectId == nil
                    ? "Enter a nonnegative price with no more than two decimal places, or leave it blank to clear."
                    : "Enter a valid project price with no more than two decimal places. A positive price or purchase cost is required."
                return
            }
        }
        error = nil; saving = true; saveRequest = UUID()
    }

    private func proposedPayload(_ review: ItemPriceEditReview) throws -> EditUncollectedItemPriceCommand.Payload {
        let currency = review.priceCurrency ?? currency
        if projectId == nil && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return try review.clearingInventoryPrice(currency: currency)
        }
        return try review.payload(requested: Money.parseNonnegativeEntry(text, currency: currency))
    }

    private static func amount(_ money: Money) -> String {
        "\(money.minorUnits / 100)." + String(format: "%02lld", money.minorUnits % 100)
    }
}
