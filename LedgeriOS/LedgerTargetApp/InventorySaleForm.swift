import LedgerTargetCore
import SwiftUI

/// Target orchestration around the original picker, price fields and form controls.
/// All mutations go through the account-bound durable operation port.
struct InventorySaleForm: View {
    let accountId: AccountID
    let itemNames: [ItemID: String]
    let currency: CurrencyCode
    let service: any InventorySaleWorkflowServing
    @Environment(\.dismiss) private var dismiss
    @State private var review: InventorySaleReview?
    @State private var projects: [Choice] = []
    @State private var selected: ProjectSummary?
    @State private var texts: [String: String] = [:]
    @State private var confirming = false
    @State private var error: String?
    @State private var draft: Draft?
    @State private var submitRequest: UUID?
    @State private var submitting = false
    @State private var saleAlreadyAccepted = false
    @State private var operationId: OperationID?
    @State private var status: OperationSnapshot?
    private struct Choice: Identifiable {
        let project: ProjectSummary
        var id: ProjectID { project.id }
    }
    private struct Draft { let payload: InventorySalePayload; let id: UUID; let createdAt: Date }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SaleStepHeaderPresentation(title: selected != nil && !confirming ? "Project Price" : "Sell to Project",
                canGoBack: selected != nil && draft == nil,
                onBack: {
                    if confirming, let review, !missingPrices(review).isEmpty { confirming = false }
                    else { selected = nil; confirming = false }
                    error = nil
                }, onClose: { dismiss() })
            if let error {
                Text(error).font(Typography.small).foregroundStyle(StatusColors.missedText)
                    .padding(.horizontal, Spacing.screenPadding)
            }
            if let operationId {
                Text(operationMessage).accessibilityIdentifier("target-sale-status")
                    .task(id: operationId) {
                        do {
                            for try await update in service.watchInventorySale(operationId) { status = update }
                        } catch { self.error = "Sale status is unavailable. Your accepted work is retained." }
                    }
            } else if saleAlreadyAccepted {
                Text("One or more selected Items already have a saved sale. No new sale was saved. Close this form and check pending work or let the existing sale finish syncing.")
                    .accessibilityIdentifier("target-sale-already-accepted")
            } else if let review {
                if let selected {
                    if !confirming && !missingPrices(review).isEmpty {
                        SalePriceEntryPresentation(rows: missingPrices(review).map {
                            .init(id: $0.rawValue,title: itemNames[$0] ?? "Item",helperText: nil)
                        },texts: $texts,errorMessage: error) {
                            do { _ = try enteredPrices(review); error = nil; confirming = true }
                            catch { self.error = "Enter a positive price with no more than two decimal places for each Item." }
                        }
                    } else {
                        Text(selected.displayName.rawValue).font(Typography.h2)
                        Text("Furnishings · Added to Invoicing. No client payment is recorded.")
                            .font(Typography.small).foregroundStyle(BrandColors.textSecondary)
                        ForEach(review.items,id: \.itemId) { item in
                            HStack {
                                Text(itemNames[item.itemId] ?? "Item")
                                Spacer()
                                Text(priceLabel(item))
                            }
                        }
                        AppButton(title: draft == nil ? "Confirm Sale" : "Retry Sale",isLoading: submitting) {
                            do {
                                if draft == nil {
                                    draft = .init(payload: try review.makePayload(projectId: selected.id,currency: currency,
                                        enteredPrices: enteredPrices(review)),id: UUID(),createdAt: Date())
                                }
                                submitting = true; error = nil; submitRequest = UUID()
                            } catch { self.error = "Review the Item prices before confirming." }
                        }.disabled(submitting)
                    }
                } else if projects.isEmpty {
                    Text("No eligible Projects are downloaded. Reconnect to refresh the list.")
                } else {
                    ProjectPickerPresentation(projects: projects,name: { $0.project.displayName.rawValue },
                        clientName: { $0.project.client.displayName.rawValue }) { choice in
                            selected = choice.project; confirming = missingPrices(review).isEmpty; error = nil
                        }
                }
            } else if error == nil { ProgressView("Loading sale review…") }
        }
        .task {
            do {
                let ids = itemNames.keys.sorted { $0.rawValue < $1.rawValue }
                for try await value in service.watchInventorySaleReview(itemIds: ids) {
                    guard let value else { clearReview(); continue }
                    try value.validate(accountId: accountId,principalId: value.principalId,itemIds: ids)
                    do {
                        for item in value.items {
                            do { _ = try item.reviewedPrice(currency: currency) }
                            catch InventorySalePrice.Failure.priceRequired { continue }
                        }
                        if draft != nil, operationId == nil, review != value {
                            clearReview()
                            error = "The saved sale's review changed. Check pending work before starting another sale."
                        } else {
                            if draft == nil, let previous = review, previous != value {
                                selected = nil; texts = [:]; confirming = false
                                error = "Item information changed. Choose the Project and review the prices again."
                            } else if draft == nil { error = nil }
                            review = value
                        }
                    } catch { clearReview() }
                }
                clearReview()
            } catch is CancellationError { clearReview() }
            catch { clearReview() }
        }
        .task {
            do {
                for try await snapshot in service.watchProjects() {
                    guard snapshot.accountId == accountId else { throw InventorySaleReview.Failure.scopeMismatch }
                    projects = snapshot.local.rows.filter { $0.lifecycle == .active && $0.client.lifecycle == .active }
                        .sorted { $0.displayName.rawValue.localizedCaseInsensitiveCompare($1.displayName.rawValue) == .orderedAscending }
                        .map(Choice.init)
                    if draft == nil, let selected, !projects.contains(where: { $0.id == selected.id }) { self.selected = nil }
                }
                projects = []; selected = nil
            } catch is CancellationError { projects = []; selected = nil }
            catch { projects = []; selected = nil; self.error = "Project information is unavailable." }
        }
        .task(id: submitRequest) {
            guard submitRequest != nil, let draft else { return }
            do {
                let receipt = try await service.sellInventoryItems(draft.payload,operationUUID: draft.id,capturedAt: draft.createdAt)
                operationId = receipt.operationId
            } catch InventorySaleCommandFailure.saleAlreadyAccepted {
                saleAlreadyAccepted = true
                error = nil
            } catch is CancellationError { }
            catch { self.error = "Could not confirm acceptance. Retry uses the same sale, so it cannot duplicate it." }
            submitting = false
        }
    }

    private func clearReview() {
        review = nil; selected = nil; texts = [:]; confirming = false
        error = "Sale review is unavailable. Item location or purchase-cost access may have changed."
    }

    private func missingPrices(_ review: InventorySaleReview) -> [ItemID] {
        review.items.compactMap {
            do { _ = try $0.reviewedPrice(currency: currency); return nil }
            catch InventorySalePrice.Failure.priceRequired { return $0.itemId }
            catch { return nil } // Loading rejects other failures before assigning review.
        }
    }
    private func enteredPrices(_ review: InventorySaleReview) throws -> [ItemID: Money] {
        try Dictionary(uniqueKeysWithValues: missingPrices(review).map {
            ($0,try InventorySalePrice.parseEntry(texts[$0.rawValue] ?? "",currency: currency))
        })
    }
    private func priceLabel(_ item: InventorySaleReview.Item) -> String {
        let amount = (try? item.reviewedPrice(currency: currency))
            ?? (try? InventorySalePrice.parseEntry(texts[item.itemId.rawValue] ?? "",currency: currency))
        guard let amount else { return "Price required" }
        return "\(currency.rawValue) \(amount.minorUnits / 100)." + String(format: "%02lld",amount.minorUnits % 100)
    }
    private var operationMessage: String {
        switch status?.state.phase {
        case .applied: "Sale applied. The Item charge is in the Project's Invoicing."
        case .rejected: "Sale was not applied. Close this form and review the latest Item and Project information."
        default: "Sale saved on this device. Waiting to sync."
        }
    }
}
