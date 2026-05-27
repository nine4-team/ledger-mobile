import SwiftUI

/// Multi-step modal for creating an invoice from a project's billable pool
/// (items + non-itemized transactions not on any other non-voided invoice).
/// Step 1: pick billables. Step 2: confirm + optional invoice number / notes.
/// On Create, `InvoiceService.createInvoice` writes signed lines onto the
/// invoice document; items and transactions are not mutated.
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
    @State private var manualLines: [InvoiceLine]
    @State private var invoiceName: String
    @State private var notes: String
    @State private var newChargeName = ""
    @State private var newChargeAmount = ""
    @State private var searchText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(accountId: String, projectId: String, editingInvoice: Invoice? = nil) {
        self.accountId = accountId
        self.projectId = projectId
        self.editingInvoice = editingInvoice
        _selectedItemIds = State(initialValue: Set(editingInvoice?.itemIds ?? []))
        _selectedTxIds = State(initialValue: Set(editingInvoice?.transactionIds ?? []))
        _manualLines = State(initialValue: editingInvoice?.lines?.filter { $0.sourceType == .manual } ?? [])
        _invoiceName = State(initialValue: editingInvoice?.invoiceNumber ?? "")
        _notes = State(initialValue: editingInvoice?.notes ?? "")
    }

    private var isEditing: Bool { editingInvoice != nil }

    // MARK: - Source data

    /// Items and transactions eligible for this invoice: anything in the
    /// project's `toInvoice` pool (not on any other non-voided invoice) plus,
    /// in edit mode, the items/transactions already on this invoice.
    private var membership: InvoiceLineCalculations.BillableMembership {
        InvoiceLineCalculations.billableMembership(
            projectId: projectId,
            items: projectContext.items,
            transactions: projectContext.transactions,
            invoices: accountContext.allInvoices,
            excludingInvoiceId: editingInvoice?.id
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

    /// Signed net total. Selected items are always charges; selected transactions
    /// contribute with the sign returned by InvoiceLineCalculations.sign(for:).
    private var totalCents: Int {
        var lines: [InvoiceLine] = []
        for item in billableItems where selectedItemIds.contains(item.id ?? "") {
            if let line = InvoiceLineCalculations.makeLine(item: item) {
                lines.append(line)
            }
        }
        for tx in billableTransactions where selectedTxIds.contains(tx.id ?? "") {
            if let line = InvoiceLineCalculations.makeLine(transaction: tx) {
                lines.append(line)
            }
        }
        lines.append(contentsOf: manualLines)
        return InvoiceLineCalculations.netTotalCents(lines: lines)
    }

    private var hasSelection: Bool {
        !selectedItemIds.isEmpty || !selectedTxIds.isEmpty || !manualLines.isEmpty
    }

    // MARK: - Body

    var body: some View {
        MultiStepFormSheet(
            title: step == 1 ? (isEditing ? "Edit Invoice" : "Create Invoice") : "Review Invoice",
            description: step == 1
                ? (isEditing
                    ? "Update the items and expenses billed on this invoice."
                    : "Select items and expenses to bill the client for.")
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
            SearchField(text: $searchText, placeholder: "Search items, expenses, and charges...")

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

            newChargeEditor

            if billableItems.isEmpty && billableTransactions.isEmpty && manualLines.isEmpty {
                Text("Nothing to bill — every item and expense in this project has already been invoiced or paid.")
                    .font(Typography.small)
                    .foregroundStyle(BrandColors.textSecondary)
                    .padding(.vertical, Spacing.md)
            } else if filteredItems.isEmpty && filteredTransactions.isEmpty && !trimmedSearch.isEmpty {
                Text("No matches for “\(trimmedSearch)”.")
                    .font(Typography.small)
                    .foregroundStyle(BrandColors.textSecondary)
                    .padding(.vertical, Spacing.md)
            }

            if !filteredItems.isEmpty {
                Text("Items")
                    .sectionLabelStyle()
                ForEach(filteredItems, id: \.id) { item in
                    selectionRow(
                        isSelected: selectedItemIds.contains(item.id ?? ""),
                        title: item.displayName.isEmpty ? "Untitled item" : item.displayName,
                        subtitle: categoryName(forCategoryId: item.budgetCategoryId),
                        cents: item.purchasePriceCents ?? 0,
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

            if !manualLines.isEmpty {
                Text("New Charges")
                    .sectionLabelStyle()
                ForEach(manualLines, id: \.id) { line in
                    manualLineRow(line)
                }
            }
        }
    }

    @ViewBuilder
    private var newChargeEditor: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("New Charge")
                .sectionLabelStyle()
            FormField(label: "Name", text: $newChargeName, placeholder: "Design Fee 1 of 3")
            FormField(label: "Amount", text: $newChargeAmount, placeholder: "$2,500")
            Button {
                addManualLine()
            } label: {
                Label("Add New Charge", systemImage: "plus.circle.fill")
                    .font(Typography.body.weight(.semibold))
                    .foregroundStyle(BrandColors.primary)
            }
            .buttonStyle(.plain)
            .disabled(!canAddManualLine)
        }
    }

    private func manualLineRow(_ line: InvoiceLine) -> some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            SelectorCircle(isSelected: true, indicator: .check)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.snapshotName ?? "New Charge")
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textPrimary)
                    .lineLimit(2)
                Text("Manual charge")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)
            }
            Spacer()
            Text(CurrencyFormatting.formatCents(line.signedAmountCents))
                .font(Typography.body)
                .foregroundStyle(BrandColors.textPrimary)
                .monospacedDigit()
            Button {
                removeManualLine(id: line.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(BrandColors.destructive)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove charge")
        }
        .padding(.vertical, Spacing.sm)
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

            Text("\(selectedItemIds.count) item\(selectedItemIds.count == 1 ? "" : "s") · \(selectedTxIds.count) expense\(selectedTxIds.count == 1 ? "" : "s") · \(manualLines.count) charge\(manualLines.count == 1 ? "" : "s")")
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

    private func categoryName(forCategoryId id: String?) -> String? {
        guard let id else { return nil }
        return projectContext.budgetCategories.first { $0.id == id }?.name
    }

    private var canAddManualLine: Bool {
        !newChargeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && parseCents(newChargeAmount) != nil
    }

    private func addManualLine() {
        let name = newChargeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let cents = parseCents(newChargeAmount) else { return }
        manualLines.append(InvoiceLine(
            sourceType: .manual,
            amountCents: cents,
            sign: .charge,
            snapshotName: name
        ))
        newChargeName = ""
        newChargeAmount = ""
    }

    private func removeManualLine(id: String) {
        manualLines.removeAll { $0.id == id }
    }

    private func existingLineId(sourceType: InvoiceLineSourceType, sourceId: String) -> String? {
        editingInvoice?.lines?.first {
            $0.sourceType == sourceType && $0.sourceId == sourceId
        }?.id
    }

    private func draftLines(itemIds: [String], txIds: [String]) -> [InvoiceLine] {
        var lines: [InvoiceLine] = []
        let itemIdSet = Set(itemIds)
        let txIdSet = Set(txIds)
        for item in projectContext.items where item.id.map({ itemIdSet.contains($0) }) ?? false {
            guard var line = InvoiceLineCalculations.makeLine(item: item),
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
        lines.append(contentsOf: manualLines)
        return lines
    }

    private func performSave() {
        guard hasSelection else { return }
        isSaving = true
        errorMessage = nil
        let service = InvoiceService()

        // Drafts store line identity and manual New Charge lines. Item/tx
        // amounts remain live previews and are materialized at markSent.
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
        let lines = draftLines(itemIds: itemIds, txIds: txIds)

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

    private func parseCents(_ text: String) -> Int? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard !cleaned.isEmpty, let value = Double(cleaned), value >= 0 else { return nil }
        return Int(round(value * 100))
    }
}
