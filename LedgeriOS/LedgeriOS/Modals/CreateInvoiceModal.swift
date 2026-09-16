import LedgerTargetCore
import SwiftUI

@Observable final class InvoiceCreationFormState {
    var editingInvoice: LiveInvoiceContents?
    init(editingInvoice: LiveInvoiceContents? = nil) {
        self.editingInvoice = editingInvoice
        if let editingInvoice {
            selected = Set(editingInvoice.lines.map { $0.selection.source })
            invoiceName = editingInvoice.name; notes = editingInvoice.notes
        }
    }
    func prepareEdit(_ invoice: LiveInvoiceContents) {
        editingInvoice = invoice
        selected = Set(invoice.lines.map { $0.selection.source })
        invoiceName = invoice.name; notes = invoice.notes
        step = 1; review = nil; searchText = ""; isSaving = false; errorMessage = nil; attempt = nil
    }
    func prepareCreation() {
        editingInvoice = nil; selected = []; invoiceName = ""; notes = ""
        step = 1; review = nil; searchText = ""; isSaving = false; errorMessage = nil; attempt = nil
    }
    var step = 1
    var selected: Set<LiveInvoiceSource> = []
    var review: InvoiceCreationReview?
    var invoiceName = ""
    var notes = ""
    var searchText = ""
    var isSaving = false
    var errorMessage: String?
    var attempt: Attempt?
    struct Attempt {
        let payload: CreateInvoiceCommand.Payload
        let operationUUID: UUID
        let capturedAt: Date
    }
}

/// Original selection/review form adapted to canonical sources and local acceptance.
/// Creation and created-Invoice editing share this form; adjustments and credits remain separate.
struct CreateInvoiceModal: View {
    let accountId: AccountID
    let projectId: ProjectID
    let service: any ProjectInvoiceCreating
    @Bindable var state: InvoiceCreationFormState
    let onSaved: (OperationReceipt) -> Void
    @Environment(\.dismiss) private var dismiss
    private var step: Int { get { state.step } nonmutating set { state.step = newValue } }
    private var selected: Set<LiveInvoiceSource> { get { state.selected } nonmutating set { state.selected = newValue } }
    private var review: InvoiceCreationReview? { get { state.review } nonmutating set { state.review = newValue } }
    private var invoiceName: String { state.invoiceName }
    private var notes: String { state.notes }
    private var searchText: String { state.searchText }
    private var isSaving: Bool { get { state.isSaving } nonmutating set { state.isSaving = newValue } }
    private var errorMessage: String? { get { state.errorMessage } nonmutating set { state.errorMessage = newValue } }
    private var attempt: InvoiceCreationFormState.Attempt? { get { state.attempt } nonmutating set { state.attempt = newValue } }
    private var selectedLines: [LiveInvoiceSelection.Line] {
        review?.candidates.filter { selected.contains($0.selection.source) }.map(\.selection) ?? []
    }
    private var selection: LiveInvoiceSelection? {
        guard let review else { return nil }
        return try? .init(scope: review.scope, lines: selectedLines)
    }
    private var totalText: String {
        guard let total = selection?.reviewedTotal else { return selected.isEmpty ? "—" : "Total unavailable" }
        return amount(total)
    }
    private var search: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var filtered: [LiveInvoiceContents.Line] {
        review?.candidates.filter { search.isEmpty || $0.description.localizedStandardContains(search)
            || (review?.categoryNames[$0.categoryId]?.localizedStandardContains(search) ?? false) } ?? []
    }

    var body: some View {
        MultiStepFormSheet(title: step == 1 ? (state.editingInvoice == nil ? "Create Invoice" : "Edit Invoice") : "Review Invoice",
            description: step == 1 ? "Select items and project costs to bill the client for."
                : "Add an optional invoice name and notes, then save.",
            showDismissButton: !isSaving, currentStep: step, totalSteps: 2, primaryAction: primaryAction,
            secondaryAction: secondaryAction, error: errorMessage) {
            if step == 1 { step1Content } else { step2Content }
        }
        .interactiveDismissDisabled(isSaving)
        .task(id: projectId) {
            do {
                for try await ready in service.watchLiveInvoices(accountId: accountId, projectId: projectId) {
                    guard ready != nil else {
                        // Nil can mean either incomplete downloads or lost access.
                        // A scoped local read distinguishes them without waiting for network sync.
                        _ = try await service.readPendingInvoiceCreations(accountId: accountId, projectId: projectId)
                        review = nil
                        if !isSaving { step = 1 }
                        continue
                    }
                    var next = try await service.readInvoiceCreationReview(accountId: accountId, projectId: projectId)
                    if let editing = state.editingInvoice {
                        guard let current = ready?.first(where: { $0.invoiceId == editing.invoiceId }),
                              current.status == .created, current.revision == editing.revision else {
                            review = nil
                            errorMessage = "This Invoice changed. Close this form and reopen it to review the latest version."
                            continue
                        }
                        let retained = Set(current.lines.map { $0.selection.source })
                        next = .init(scope: next.scope, candidates: current.lines + next.candidates.filter { !retained.contains($0.selection.source) },
                            categoryNames: next.categoryNames)
                    }
                    guard !Task.isCancelled else { return }
                    if let review, review != next, !selected.isEmpty, !isSaving {
                        step = 1
                        errorMessage = "Billable records changed. Review your selection before saving."
                    }
                    review = next
                    if !isSaving { selected.formIntersection(Set(next.candidates.map { $0.selection.source })) }
                }
            } catch {
                if !Task.isCancelled {
                    review = nil; selected = []; state.invoiceName = ""; state.notes = ""
                    errorMessage = "Invoice editing is unavailable. Previously saved work remains on this device."
                    dismiss()
                }
            }
        }
    }
    private var primaryAction: FormSheetAction {
        if step == 1 { return .init(title: "Next", isDisabled: selection == nil, action: { step = 2 }) }
        return .init(title: state.editingInvoice == nil ? "Create Invoice" : "Save Changes", isLoading: isSaving,
            isDisabled: selection == nil || isSaving, action: performSave)
    }
    private var secondaryAction: FormSheetAction? {
        .init(title: step == 1 ? "Cancel" : "Back", isDisabled: isSaving, action: {
            if step == 1 { dismiss() } else { step = 1 }
        })
    }
    private var step1Content: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SearchField(text: $state.searchText, placeholder: "Search items, project costs, and charges...")
            HStack {
                Text("Selected total").font(Typography.small).foregroundStyle(BrandColors.textSecondary)
                Spacer()
                Text(totalText).font(Typography.body.weight(.semibold)).foregroundStyle(BrandColors.textPrimary).monospacedDigit()
            }
            if let review {
                if review.candidates.isEmpty {
                    Text("Nothing to bill — every downloaded fee installment, item, and project cost has already been invoiced or paid.")
                        .font(Typography.small).foregroundStyle(BrandColors.textSecondary).padding(.vertical, Spacing.md)
                } else if filtered.isEmpty {
                    Text("No matches for “\(search)”.").font(Typography.small).foregroundStyle(BrandColors.textSecondary)
                }
                ForEach(["Fees", "Items", "Expenses"], id: \.self) { group in
                    let rows = filtered.filter { kind($0.selection.source) == group }
                    if !rows.isEmpty {
                        Text(group).sectionLabelStyle()
                        ForEach(rows, id: \.selection.source) { row in selectionRow(row) }
                    }
                }
                Text("Manual adjustments and credit selection are not available in this build.")
                    .font(Typography.small).foregroundStyle(BrandColors.textSecondary)
            } else { ProgressView("Downloading billable records") }
        }
    }
    private func selectionRow(_ row: LiveInvoiceContents.Line) -> some View {
        let source = row.selection.source
        return Button {
            if !selected.insert(source).inserted { selected.remove(source) }
        } label: {
            HStack(alignment: .center, spacing: Spacing.md) {
                SelectorCircle(isSelected: selected.contains(source), indicator: .check)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.description.isEmpty ? "Untitled charge" : row.description)
                        .font(Typography.body).foregroundStyle(BrandColors.textPrimary).lineLimit(2)
                    if let category = review?.categoryNames[row.categoryId] {
                        Text(category).font(Typography.caption).foregroundStyle(BrandColors.textSecondary)
                    }
                }
                Spacer()
                Text(amount(row.selection.reviewedAmount)).font(Typography.body)
                    .foregroundStyle(BrandColors.textPrimary).monospacedDigit()
            }
            .padding(.vertical, Spacing.sm).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("invoice-source-\(sourceKey(source))")
    }
    private var step2Content: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Total").font(Typography.body.weight(.semibold)).foregroundStyle(BrandColors.textPrimary)
                Spacer()
                Text(totalText).font(Typography.h3).foregroundStyle(BrandColors.textPrimary).monospacedDigit()
            }
            FormField(label: "Invoice Name (optional)", text: $state.invoiceName, placeholder: "Phase 1 — Furnishings")
            FormField(label: "Notes (optional)", text: $state.notes, placeholder: "")
            Text("\(selectedLines.filter { kind($0.source) == "Fees" }.count) fees · \(selectedLines.filter { kind($0.source) == "Items" }.count) items · \(selectedLines.filter { kind($0.source) == "Expenses" }.count) project costs")
                .font(Typography.small).foregroundStyle(BrandColors.textSecondary)
        }
    }
    private func performSave() {
        guard let selection, !isSaving else { return }
        do {
            let id = try state.editingInvoice?.invoiceId ?? attempt?.payload.invoiceId ?? InvoiceID(validating: UUID().uuidString)
            let payload = CreateInvoiceCommand.Payload(invoiceId: id, selection: selection,
                name: invoiceName.trimmingCharacters(in: .whitespacesAndNewlines), notes: notes.trimmingCharacters(in: .whitespacesAndNewlines))
            if attempt?.payload != payload { attempt = .init(payload: payload, operationUUID: UUID(), capturedAt: Date()) }
            guard let attempt else { return }
            isSaving = true; errorMessage = nil
            Task {
                do {
                    let receipt: OperationReceipt
                    if let editing = state.editingInvoice {
                        guard let reviser = service as? any ProjectInvoiceRevising else {
                            isSaving = false; errorMessage = "Invoice editing is unavailable."; return
                        }
                        receipt = try await reviser.reviseCreatedInvoice(.init(invoice: attempt.payload, expectedRevision: editing.revision),
                            operationUUID: attempt.operationUUID, capturedAt: attempt.capturedAt)
                    } else {
                        receipt = try await service.createInvoice(attempt.payload, operationUUID: attempt.operationUUID, capturedAt: attempt.capturedAt)
                    }
                    onSaved(receipt); dismiss()
                } catch {
                    isSaving = false
                    errorMessage = "Invoice was not accepted on this device. Check the current billable records and try again."
                }
            }
        } catch { errorMessage = "Invoice could not be prepared." }
    }
    private func amount(_ value: Money) -> String {
        (Decimal(value.minorUnits) / 100).formatted(.currency(code: value.currency.rawValue))
    }
    private func kind(_ source: LiveInvoiceSource) -> String {
        switch source { case .itemOccurrence: "Items"; case .expense: "Expenses"; case .feeInstallment: "Fees" }
    }
    private func sourceKey(_ source: LiveInvoiceSource) -> String {
        switch source {
        case .itemOccurrence(let id): "item-" + id.rawValue
        case .expense(let id): "expense-" + id.rawValue
        case .feeInstallment(let id): "fee-" + id.rawValue
        }
    }
}
