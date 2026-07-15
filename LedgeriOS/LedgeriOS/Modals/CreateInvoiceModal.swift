import SwiftUI

/// Multi-step modal for creating an invoice from a project's billable pool:
/// fee installments, items, and non-itemized transactions not on any other
/// non-canceled invoice.
/// Step 1: pick billables. Step 2: confirm + optional invoice number / notes.
/// Created and sent invoices stay live until collection; source amounts are
/// re-derived when the invoice is sent/paid.
struct CreateInvoiceModal: View {
    let accountId: String
    let projectId: String
    let editingInvoice: Invoice?

    @Environment(ProjectContext.self) private var projectContext
    @Environment(AccountContext.self) private var accountContext
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var step = 1
    @State private var selectedItemIds: Set<String>
    @State private var selectedTxIds: Set<String>
    @State private var selectedFeeInstallmentIds: Set<String>
    @State private var manualChargeLines: [InvoiceLine]
    @State private var invoiceName: String
    @State private var notes: String
    @State private var searchText = ""
    @State private var showingManualChargeForm = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(accountId: String, projectId: String, editingInvoice: Invoice? = nil) {
        self.accountId = accountId
        self.projectId = projectId
        self.editingInvoice = editingInvoice
        _selectedItemIds = State(initialValue: Set(editingInvoice?.itemIds ?? []))
        _selectedTxIds = State(initialValue: Set(editingInvoice?.transactionIds ?? []))
        _selectedFeeInstallmentIds = State(initialValue: Set(editingInvoice?.lines?.compactMap { line in
            line.sourceType == .feeInstallment ? line.sourceId : nil
        } ?? []))
        _manualChargeLines = State(initialValue: editingInvoice?.lines?.filter {
            $0.sourceType == .manual && $0.sign == .charge
        } ?? [])
        _invoiceName = State(initialValue: editingInvoice?.invoiceNumber ?? "")
        _notes = State(initialValue: editingInvoice?.notes ?? "")
    }

    private var isEditing: Bool { editingInvoice != nil }

    // MARK: - Source data

    /// Items and transactions eligible for this invoice: anything in the
    /// project's `toInvoice` pool (not on any other non-canceled invoice) plus,
    /// in edit mode, the items/transactions already on this invoice.
    private var membership: InvoiceLineCalculations.BillableMembership {
        InvoiceLineCalculations.billableMembership(
            projectId: projectId,
            items: projectContext.items,
            transactions: projectContext.transactions,
            invoices: accountContext.allInvoices,
            budgetCategories: categoryLookup,
            excludingInvoiceId: editingInvoice?.id
        )
    }

    private var categoryLookup: [String: BudgetCategory] {
        Dictionary(
            uniqueKeysWithValues: projectContext.budgetCategories.compactMap { category in
                guard let id = category.id else { return nil }
                return (id, category)
            }
        )
    }

    private var billableItems: [Item] {
        let pool = membership.toInvoiceItemIds
        return projectContext.items.filter { item in
            guard let id = item.id else { return false }
            guard item.status != .returned else { return false }
            return pool.contains(id)
        }
    }

    private var billableTransactions: [Transaction] {
        let pool = membership.toInvoiceTransactionIds
        return projectContext.transactions.filter { tx in
            guard let id = tx.id else { return false }
            return pool.contains(id)
        }
    }

    private var visibleFeeCategoryIds: Set<String> {
        Set(projectContext.budgetCategories.compactMap { category in
            guard category.isFeeCategory, let id = category.id else { return nil }
            return id
        })
    }

    private var activeFeeInstallmentIds: Set<String> {
        var ids: Set<String> = []
        for invoice in accountContext.allInvoices {
            guard invoice.projectId == projectId else { continue }
            guard invoice.status != .canceled else { continue }
            if invoice.id == editingInvoice?.id { continue }
            for line in invoice.lines ?? [] where line.sourceType == .feeInstallment {
                if let sourceId = line.sourceId { ids.insert(sourceId) }
            }
        }
        return ids
    }

    private var billableFeeInstallments: [FeeInstallment] {
        projectContext.feeInstallments
            .filter { installment in
                guard let id = installment.id else { return false }
                guard visibleFeeCategoryIds.contains(installment.budgetCategoryId) else { return false }
                return !activeFeeInstallmentIds.contains(id)
            }
            .sorted { lhs, rhs in
                if (lhs.sortOrder ?? 0) != (rhs.sortOrder ?? 0) {
                    return (lhs.sortOrder ?? 0) < (rhs.sortOrder ?? 0)
                }
                return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
            }
    }

    /// Charges among filtered transactions — owed-to-company direction.
    private var filteredCharges: [Transaction] {
        filteredTransactions.filter { InvoiceLineCalculations.sign(for: $0) == .charge }
    }

    /// Credits among filtered transactions — owed-to-client direction.
    private var filteredCredits: [Transaction] {
        filteredTransactions.filter { InvoiceLineCalculations.sign(for: $0) == .credit }
    }

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    private var filteredItems: [Item] {
        guard !trimmedSearch.isEmpty else { return billableItems }
        return billableItems.filter {
            SearchCalculations.itemMatches(item: $0, query: trimmedSearch)
        }
    }

    private var filteredTransactions: [Transaction] {
        guard !trimmedSearch.isEmpty else { return billableTransactions }
        return billableTransactions.filter {
            SearchCalculations.transactionMatches(transaction: $0, query: trimmedSearch)
        }
    }

    private var filteredFeeInstallments: [FeeInstallment] {
        guard !trimmedSearch.isEmpty else { return billableFeeInstallments }
        return billableFeeInstallments.filter { installment in
            installment.label.localizedCaseInsensitiveContains(trimmedSearch)
                || (categoryName(forCategoryId: installment.budgetCategoryId)?.localizedCaseInsensitiveContains(trimmedSearch) ?? false)
        }
    }

    /// Signed net total. Selected items are always charges; selected transactions
    /// contribute with the sign returned by InvoiceLineCalculations.sign(for:).
    private var totalCents: Int {
        var lines: [InvoiceLine] = []
        for item in billableItems where selectedItemIds.contains(item.id ?? "") {
            if let line = InvoiceLineCalculations.makeLine(
                item: item,
                projectId: projectId,
                transactions: projectContext.transactions
            ) {
                lines.append(line)
            }
        }
        for tx in billableTransactions where selectedTxIds.contains(tx.id ?? "") {
            if let line = InvoiceLineCalculations.makeLine(transaction: tx) {
                lines.append(line)
            }
        }
        for installment in billableFeeInstallments where selectedFeeInstallmentIds.contains(installment.id ?? "") {
            if let line = InvoiceLineCalculations.makeLine(feeInstallment: installment) {
                lines.append(line)
            }
        }
        lines.append(contentsOf: manualChargeLines)
        lines.append(contentsOf: preservedManualCreditLines)
        return InvoiceLineCalculations.netTotalCents(lines: lines)
    }

    private var hasSelection: Bool {
        !selectedItemIds.isEmpty || !selectedTxIds.isEmpty || !selectedFeeInstallmentIds.isEmpty || !manualChargeLines.isEmpty || !preservedManualCreditLines.isEmpty
    }

    /// Return credits are generated by the inventory-return workflow. They remain
    /// on an edited invoice but are intentionally not editable as manual charges.
    private var preservedManualCreditLines: [InvoiceLine] {
        editingInvoice?.lines?.filter { $0.sourceType == .manual && $0.sign == .credit } ?? []
    }

    // MARK: - Body

    var body: some View {
        MultiStepFormSheet(
            title: step == 1 ? (isEditing ? "Edit Invoice" : "Create Invoice") : "Review Invoice",
            description: step == 1
                ? (isEditing
                    ? "Update the items and project costs billed on this invoice."
                    : "Select items and project costs to bill the client for.")
                : "Add an optional invoice name and notes, then save.",
            currentStep: step,
            totalSteps: 2,
            primaryAction: primaryAction,
            secondaryAction: secondaryAction,
            error: errorMessage
        ) {
            if step == 1 {
                step1Content
            } else {
                step2Content
            }
        }
        .adaptivePresentation(isPresented: $showingManualChargeForm, style: .form) {
            ManualInvoiceChargeFormSheet(onAdd: { line in manualChargeLines.append(line) })
        }
    }

    // MARK: - Actions

    private var primaryAction: FormSheetAction {
        if step == 1 {
            return FormSheetAction(
                title: "Next",
                isDisabled: !hasSelection,
                action: { step = 2 }
            )
        }
        return FormSheetAction(
            title: isEditing ? "Save Changes" : "Create Invoice",
            isLoading: isSaving,
            isDisabled: !hasSelection || isSaving,
            action: { performSave() }
        )
    }

    private var secondaryAction: FormSheetAction? {
        if step == 1 {
            return FormSheetAction(title: "Cancel", action: { dismiss() })
        }
        return FormSheetAction(title: "Back", action: { step = 1 })
    }

    // MARK: - Step 1: pick billables

    @ViewBuilder
    private var step1Content: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SearchField(text: $searchText, placeholder: "Search items, project costs, and charges...")

            HStack {
                Text("Selected total")
                    .font(Typography.small)
                    .foregroundStyle(BrandColors.textSecondary)
                Spacer()
                Text(CurrencyFormatting.formatCents(totalCents))
                    .font(Typography.body.weight(.semibold))
                    .foregroundStyle(BrandColors.textPrimary)
                    .monospacedDigit()
            }

            if billableItems.isEmpty && billableTransactions.isEmpty && billableFeeInstallments.isEmpty {
                Text("Nothing to bill — every fee installment, item, and project cost in this project has already been invoiced or paid.")
                    .font(Typography.small)
                    .foregroundStyle(BrandColors.textSecondary)
                    .padding(.vertical, Spacing.md)
            } else if filteredItems.isEmpty && filteredTransactions.isEmpty && filteredFeeInstallments.isEmpty && !trimmedSearch.isEmpty {
                Text("No matches for “\(trimmedSearch)”.")
                    .font(Typography.small)
                    .foregroundStyle(BrandColors.textSecondary)
                    .padding(.vertical, Spacing.md)
            }

            if !filteredFeeInstallments.isEmpty {
                Text("Fees")
                    .sectionLabelStyle()
                ForEach(filteredFeeInstallments, id: \.id) { installment in
                    selectionRow(
                        isSelected: selectedFeeInstallmentIds.contains(installment.id ?? ""),
                        title: installment.label.isEmpty ? "Fee installment" : installment.label,
                        subtitle: categoryName(forCategoryId: installment.budgetCategoryId),
                        cents: installment.amountCents,
                        needsReview: false,
                        onToggle: { toggle(feeInstallmentId: installment.id ?? "") }
                    )
                }
            }

            Text("Manual Charges")
                .sectionLabelStyle()
            ForEach(manualChargeLines, id: \.id) { line in
                manualChargeRow(line)
            }
            Button {
                showingManualChargeForm = true
            } label: {
                Label("Add Manual Charge", systemImage: "plus.circle")
                    .font(Typography.body.weight(.semibold))
                    .foregroundStyle(BrandColors.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Spacing.sm)
            }
            .buttonStyle(.plain)

            if !filteredItems.isEmpty {
                Text("Items")
                    .sectionLabelStyle()
                ForEach(filteredItems, id: \.id) { item in
                    selectionRow(
                        isSelected: selectedItemIds.contains(item.id ?? ""),
                        title: item.displayName.isEmpty ? "Untitled item" : item.displayName,
                        subtitle: categoryName(forCategoryId: item.budgetCategoryId),
                        cents: InvoiceLineCalculations.amountCents(
                            for: item,
                            projectId: projectId,
                            transactions: projectContext.transactions
                        ) ?? 0,
                        needsReview: false,
                        onToggle: { toggle(itemId: item.id ?? "") }
                    )
                }
            }

            if !filteredCharges.isEmpty {
                Text("Charges")
                    .sectionLabelStyle()
                ForEach(filteredCharges, id: \.id) { tx in
                    selectionRow(
                        isSelected: selectedTxIds.contains(tx.id ?? ""),
                        title: TransactionDisplayCalculations.displayName(for: tx),
                        subtitle: categoryName(forCategoryId: tx.budgetCategoryId),
                        cents: tx.amountCents ?? 0,
                        needsReview: tx.isComplete != true,
                        onToggle: { toggle(txId: tx.id ?? "") }
                    )
                }
            }

            if !filteredCredits.isEmpty {
                Text("Credits")
                    .sectionLabelStyle()
                ForEach(filteredCredits, id: \.id) { tx in
                    selectionRow(
                        isSelected: selectedTxIds.contains(tx.id ?? ""),
                        title: TransactionDisplayCalculations.displayName(for: tx),
                        subtitle: categoryName(forCategoryId: tx.budgetCategoryId),
                        cents: -(tx.amountCents ?? 0),
                        needsReview: tx.isComplete != true,
                        onToggle: { toggle(txId: tx.id ?? "") }
                    )
                }
            }

        }
    }

    private func selectionRow(
        isSelected: Bool,
        title: String,
        subtitle: String?,
        cents: Int,
        needsReview: Bool,
        onToggle: @escaping () -> Void
    ) -> some View {
        Button(action: onToggle) {
            HStack(alignment: .center, spacing: Spacing.md) {
                SelectorCircle(isSelected: isSelected, indicator: .check)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Spacing.sm) {
                        Text(title)
                            .font(Typography.body)
                            .foregroundStyle(BrandColors.textPrimary)
                            .lineLimit(2)
                        if needsReview {
                            Text("Needs Review")
                                .font(Typography.caption.weight(.semibold))
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, 2)
                                .background(StatusColors.badgeNeedsReview.opacity(0.10), in: Capsule())
                                .overlay(Capsule().stroke(StatusColors.badgeNeedsReview.opacity(0.30), lineWidth: 1))
                                .foregroundStyle(StatusColors.badgeNeedsReview)
                        }
                    }
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)
                    }
                }
                Spacer()
                Text(CurrencyFormatting.formatCents(cents))
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textPrimary)
                    .monospacedDigit()
            }
            .padding(.vertical, Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func manualChargeRow(_ line: InvoiceLine) -> some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.snapshotName?.isEmpty == false ? line.snapshotName! : "Manual charge")
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textPrimary)
                Text("Other Client Charges & Credits")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)
            }
            Spacer()
            Text(CurrencyFormatting.formatCents(line.amountCents))
                .font(Typography.body)
                .foregroundStyle(BrandColors.textPrimary)
                .monospacedDigit()
            Button {
                manualChargeLines.removeAll { $0.id == line.id }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(BrandColors.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove manual charge")
        }
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Step 2: review

    @ViewBuilder
    private var step2Content: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Total")
                    .font(Typography.body.weight(.semibold))
                    .foregroundStyle(BrandColors.textPrimary)
                Spacer()
                Text(CurrencyFormatting.formatCents(totalCents))
                    .font(Typography.h3)
                    .foregroundStyle(BrandColors.textPrimary)
                    .monospacedDigit()
            }

            FormField(label: "Invoice Name (optional)", text: $invoiceName, placeholder: "Phase 1 — Furnishings")
            FormField(label: "Notes (optional)", text: $notes, placeholder: "")

            Text("\(selectedFeeInstallmentIds.count) fee\(selectedFeeInstallmentIds.count == 1 ? "" : "s") · \(selectedItemIds.count) item\(selectedItemIds.count == 1 ? "" : "s") · \(selectedTxIds.count) project cost\(selectedTxIds.count == 1 ? "" : "s") · \(manualChargeLines.count) manual charge\(manualChargeLines.count == 1 ? "" : "s")")
                .font(Typography.small)
                .foregroundStyle(BrandColors.textSecondary)
        }
    }

    // MARK: - Helpers

    private func toggle(itemId: String) {
        if selectedItemIds.contains(itemId) {
            selectedItemIds.remove(itemId)
        } else {
            selectedItemIds.insert(itemId)
        }
    }

    private func toggle(txId: String) {
        if selectedTxIds.contains(txId) {
            selectedTxIds.remove(txId)
        } else {
            selectedTxIds.insert(txId)
        }
    }

    private func toggle(feeInstallmentId: String) {
        if selectedFeeInstallmentIds.contains(feeInstallmentId) {
            selectedFeeInstallmentIds.remove(feeInstallmentId)
        } else {
            selectedFeeInstallmentIds.insert(feeInstallmentId)
        }
    }

    private func categoryName(forCategoryId id: String?) -> String? {
        guard let id else { return nil }
        return projectContext.budgetCategories.first { $0.id == id }?.name
    }

    private func existingLineId(sourceType: InvoiceLineSourceType, sourceId: String) -> String? {
        editingInvoice?.lines?.first {
            $0.sourceType == sourceType && $0.sourceId == sourceId
        }?.id
    }

    private func draftLines(itemIds: [String], txIds: [String], feeInstallmentIds: [String]) -> [InvoiceLine] {
        var lines: [InvoiceLine] = []
        let itemIdSet = Set(itemIds)
        let txIdSet = Set(txIds)
        let feeIdSet = Set(feeInstallmentIds)
        for item in projectContext.items where item.id.map({ itemIdSet.contains($0) }) ?? false {
            guard var line = InvoiceLineCalculations.makeLine(
                item: item,
                projectId: projectId,
                transactions: projectContext.transactions
            ),
                  let sourceId = item.id else { continue }
            if let existing = existingLineId(sourceType: .item, sourceId: sourceId) {
                line.id = existing
            }
            lines.append(line)
        }
        for tx in projectContext.transactions where tx.id.map({ txIdSet.contains($0) }) ?? false {
            guard var line = InvoiceLineCalculations.makeLine(transaction: tx),
                  let sourceId = tx.id else { continue }
            if let existing = existingLineId(sourceType: .transaction, sourceId: sourceId) {
                line.id = existing
            }
            lines.append(line)
        }
        for installment in projectContext.feeInstallments where installment.id.map({ feeIdSet.contains($0) }) ?? false {
            guard var line = InvoiceLineCalculations.makeLine(feeInstallment: installment),
                  let sourceId = installment.id else { continue }
            if let existing = existingLineId(sourceType: .feeInstallment, sourceId: sourceId) {
                line.id = existing
            }
            lines.append(line)
        }
        lines.append(contentsOf: manualChargeLines)
        lines.append(contentsOf: preservedManualCreditLines)
        return lines
    }

    private func performSave() {
        guard hasSelection else { return }
        isSaving = true
        errorMessage = nil
        let service = InvoiceService()

        // Drafts store source identity. Amounts remain live previews and are
        // materialized when the invoice is sent or collected.
        let itemIds = projectContext.items.compactMap { item -> String? in
            guard let id = item.id, selectedItemIds.contains(id) else { return nil }
            return id
        }
        let txIds = projectContext.transactions.compactMap { tx -> String? in
            guard let id = tx.id, selectedTxIds.contains(id) else { return nil }
            return id
        }

        let number = invoiceName.trimmingCharacters(in: .whitespaces)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)
        let userId = authManager.currentUser?.uid
        let acctId = accountId
        let projId = projectId
        let editingId = editingInvoice?.id
        let feeInstallmentIds = projectContext.feeInstallments.compactMap { installment -> String? in
            guard let id = installment.id, selectedFeeInstallmentIds.contains(id) else { return nil }
            return id
        }
        let lines = draftLines(itemIds: itemIds, txIds: txIds, feeInstallmentIds: feeInstallmentIds)
        guard lines.allSatisfy({ $0.budgetCategoryId?.isEmpty == false }) else {
            errorMessage = "Every invoice line needs a budget category."
            isSaving = false
            return
        }

        Task {
            do {
                if let editingId {
                    var snapshot = Invoice()
                    snapshot.id = editingId
                    try await service.updateSelections(
                        invoice: snapshot,
                        accountId: acctId,
                        newItemIds: itemIds,
                        newTransactionIds: txIds,
                        lines: lines,
                        invoiceNumber: number.isEmpty ? nil : number,
                        notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                        userId: userId
                    )
                } else {
                    _ = try await service.createInvoice(
                        accountId: acctId,
                        projectId: projId,
                        itemIds: itemIds,
                        transactionIds: txIds,
                        lines: lines,
                        invoiceNumber: number.isEmpty ? nil : number,
                        notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                        userId: userId
                    )
                }
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    errorMessage = editingId == nil
                        ? "Failed to create invoice. Please try again."
                        : "Failed to save invoice. Please try again."
                    isSaving = false
                }
            }
        }
    }

}

private struct ManualInvoiceChargeFormSheet: View {
    let onAdd: (InvoiceLine) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var label = ""
    @State private var amount = ""
    private var amountCents: Int? {
        InvoiceMoneyParsing.parseCentsFromDollarString(amount)
    }

    private var canAdd: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && amountCents != nil
    }

    var body: some View {
        FormSheet(
            title: "Add Manual Charge",
            description: "",
            primaryAction: FormSheetAction(title: "Add Charge", isDisabled: !canAdd, action: add),
            secondaryAction: FormSheetAction(title: "Cancel", action: { dismiss() })
        ) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                FormField(label: "Description", text: $label, placeholder: "Additional installation work")
                FormField(label: "Amount", text: $amount, placeholder: "$250")
            }
        }
    }

    private func add() {
        guard let amountCents else { return }
        onAdd(InvoiceLine(
            sourceType: .manual,
            amountCents: amountCents,
            sign: .charge,
            budgetCategoryId: SystemBudgetCategory.otherClientChargesAndCreditsId,
            snapshotName: label.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        dismiss()
    }
}
