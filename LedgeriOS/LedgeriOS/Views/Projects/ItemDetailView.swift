import SwiftUI

struct ItemDetailView: View {
    let item: Item

    @Environment(ProjectContext.self) private var projectContext
    @Environment(AccountContext.self) private var accountContext
    @Environment(\.dismiss) private var dismiss

    // Collapsible section state
    @State private var isMediaExpanded = true
    @State private var isNotesExpanded = false
    @State private var isDetailsExpanded = false

    // Modal presentation
    @State private var showActionMenu = false
    @State private var showEditDetails = false
    @State private var showEditNotes = false
    @State private var showSetSpace = false
    @State private var showReassign = false
    @State private var showSellToBusiness = false
    @State private var showSellToProject = false
    @State private var showTransactionPicker = false
    @State private var showReturnTransactionPicker = false
    @State private var showMakeCopies = false
    @State private var showStatusPicker = false
    @State private var showDeleteConfirmation = false

    // Sheet-on-sheet sequencing
    @State private var menuPendingAction: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                heroCard
                sectionsArea
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.vertical, Spacing.sm)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(item.name.isEmpty ? "Item" : item.name)
                    .font(Typography.h3)
                    .foregroundStyle(BrandColors.textPrimary)
                    .lineLimit(1)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: Spacing.sm) {
                    bookmarkButton
                    menuButton
                }
            }
        }
        // Action menu sheet
        .sheet(isPresented: $showActionMenu, onDismiss: {
            menuPendingAction?()
            menuPendingAction = nil
        }) {
            ActionMenuSheet(
                title: item.name.isEmpty ? "Item" : item.name,
                items: actionMenuItems,
                onSelectAction: { action in menuPendingAction = action }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        // Edit Details
        .sheet(isPresented: $showEditDetails) {
            EditItemDetailsModal(item: item) { fields in
                updateItem(fields: fields)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        // Edit Notes
        .sheet(isPresented: $showEditNotes) {
            EditNotesModal(notes: item.notes ?? "") { newNotes in
                updateItem(fields: ["notes": newNotes])
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        // Set Space
        .sheet(isPresented: $showSetSpace) {
            SetSpaceModal(
                spaces: projectContext.spaces,
                currentSpaceId: item.spaceId,
                onSelect: { space in
                    let fields: [String: Any] = space != nil ? ["spaceId": space!.id ?? ""] : ["spaceId": NSNull()]
                    updateItem(fields: fields)
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        // Reassign
        .sheet(isPresented: $showReassign) {
            ReassignToProjectModal(items: [item]) { }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        // Sell to Business
        .sheet(isPresented: $showSellToBusiness) {
            if let accountId = accountContext.currentAccountId {
                SellToBusinessModal(items: [item], accountId: accountId) {
                    dismiss()
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        // Sell to Project
        .sheet(isPresented: $showSellToProject) {
            if let accountId = accountContext.currentAccountId {
                SellToProjectModal(items: [item], accountId: accountId) {
                    dismiss()
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        // Transaction Picker
        .sheet(isPresented: $showTransactionPicker) {
            TransactionPickerModal(
                transactions: projectContext.transactions,
                selectedId: item.transactionId
            ) { transaction in
                updateItem(fields: ["transactionId": transaction.id ?? ""])
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        // Return Transaction Picker
        .sheet(isPresented: $showReturnTransactionPicker) {
            ReturnTransactionPickerModal(
                transactions: projectContext.transactions,
                selectedId: item.transactionId
            ) { transaction in
                updateItem(fields: ["transactionId": transaction.id ?? ""])
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        // Make Copies
        .sheet(isPresented: $showMakeCopies) {
            if let accountId = accountContext.currentAccountId {
                MakeCopiesModal(item: item, accountId: accountId)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
        // Status Picker
        .sheet(isPresented: $showStatusPicker) {
            StatusPickerModal(currentStatus: item.status) { status in
                updateItem(fields: ["status": status])
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        // Delete confirmation
        .confirmationDialog("Delete Item?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteItem()
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(item.name.isEmpty ? "Unnamed Item" : item.name)
                .font(Typography.h2)
                .foregroundStyle(BrandColors.textPrimary)

            if let quantity = item.quantity, quantity > 0 {
                Text("Qty: \(quantity)")
                    .font(Typography.small)
                    .foregroundStyle(BrandColors.textSecondary)
            }

            HStack(spacing: Spacing.lg) {
                priceCell(label: "Purchase", cents: item.purchasePriceCents)
                priceCell(label: "Project", cents: item.projectPriceCents)
                priceCell(label: "Market", cents: item.marketValueCents)
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private func priceCell(label: String, cents: Int?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(BrandColors.textTertiary)
            Text(cents.map { CurrencyFormatting.formatCentsWithDecimals($0) } ?? "—")
                .font(Typography.body)
                .fontWeight(.medium)
                .foregroundStyle(BrandColors.textPrimary)
        }
    }

    // MARK: - Collapsible Sections

    private var sectionsArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            CollapsibleSection(title: "MEDIA", isExpanded: $isMediaExpanded) {
                mediaContent
            }

            Divider()
                .padding(.vertical, Spacing.xs)

            CollapsibleSection(
                title: "NOTES",
                isExpanded: $isNotesExpanded,
                onEdit: { showEditNotes = true }
            ) {
                notesContent
            }

            Divider()
                .padding(.vertical, Spacing.xs)

            CollapsibleSection(title: "DETAILS", isExpanded: $isDetailsExpanded) {
                detailsContent
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private var mediaContent: some View {
        MediaGallerySection(
            title: "",
            attachments: item.images ?? [],
            emptyStateMessage: "No images yet"
        )
        .padding(.top, Spacing.xs)
    }

    @ViewBuilder
    private var notesContent: some View {
        if let notes = item.notes, !notes.isEmpty {
            Text(notes)
                .font(Typography.body)
                .foregroundStyle(BrandColors.textPrimary)
                .padding(.top, Spacing.xs)
        } else {
            Text("No notes")
                .font(Typography.small)
                .foregroundStyle(BrandColors.textSecondary)
                .padding(.top, Spacing.xs)
        }
    }

    @ViewBuilder
    private var detailsContent: some View {
        VStack(spacing: 0) {
            DetailRow(label: "Status", value: item.status?.capitalized ?? "—")
            DetailRow(label: "Space", value: spaceName)
            DetailRow(label: "Source", value: item.source ?? "—")
            DetailRow(label: "SKU", value: item.sku ?? "—")
            DetailRow(label: "Purchase Price", value: item.purchasePriceCents.map { CurrencyFormatting.formatCentsWithDecimals($0) } ?? "—")
            DetailRow(label: "Project Price", value: item.projectPriceCents.map { CurrencyFormatting.formatCentsWithDecimals($0) } ?? "—")
            DetailRow(label: "Market Value", value: item.marketValueCents.map { CurrencyFormatting.formatCentsWithDecimals($0) } ?? "—")
            if let date = item.createdAt {
                DetailRow(label: "Created", value: DateFormatter.shortDate.string(from: date), showDivider: false)
            }
        }
        .padding(.top, Spacing.xs)
    }

    // MARK: - Toolbar Buttons

    private var bookmarkButton: some View {
        Button {
            toggleBookmark()
        } label: {
            Image(systemName: item.bookmark == true ? "star.fill" : "star")
                .foregroundStyle(item.bookmark == true ? BrandColors.primary : BrandColors.textSecondary)
        }
    }

    private var menuButton: some View {
        Button {
            showActionMenu = true
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(BrandColors.textSecondary)
        }
    }

    // MARK: - Action Menu

    private var actionMenuItems: [ActionMenuItem] {
        var items: [ActionMenuItem] = [
            ActionMenuItem(id: "edit", label: "Edit Details", icon: "pencil", onPress: {
                showEditDetails = true
            }),
            ActionMenuItem(id: "notes", label: "Edit Notes", icon: "note.text", onPress: {
                showEditNotes = true
            }),
            ActionMenuItem(id: "space", label: "Set Space", icon: "mappin.and.ellipse", onPress: {
                showSetSpace = true
            }),
            ActionMenuItem(id: "status", label: "Change Status", icon: "flag", onPress: {
                showStatusPicker = true
            }),
            ActionMenuItem(id: "transaction", label: "Link Transaction", icon: "arrow.left.arrow.right", onPress: {
                showTransactionPicker = true
            }),
            ActionMenuItem(id: "copies", label: "Make Copies", icon: "doc.on.doc", onPress: {
                showMakeCopies = true
            }),
            ActionMenuItem(id: "reassign", label: "Reassign", icon: "arrow.triangle.2.circlepath", onPress: {
                showReassign = true
            }),
            ActionMenuItem(id: "sell-business", label: "Sell to Business", icon: "building.2", onPress: {
                showSellToBusiness = true
            }),
            ActionMenuItem(id: "sell-project", label: "Sell to Project", icon: "arrow.right.square", onPress: {
                showSellToProject = true
            }),
        ]

        if item.status == "to return" || item.status == "returned" {
            items.append(ActionMenuItem(id: "return-tx", label: "Link Return Transaction", icon: "arrow.uturn.left", onPress: {
                showReturnTransactionPicker = true
            }))
        }

        items.append(ActionMenuItem(id: "delete", label: "Delete Item", icon: "trash", isDestructive: true, onPress: {
            showDeleteConfirmation = true
        }))

        return items
    }

    // MARK: - Helpers

    private var spaceName: String {
        guard let spaceId = item.spaceId else { return "—" }
        return projectContext.spaces.first(where: { $0.id == spaceId })?.name ?? "—"
    }

    // MARK: - Actions

    private func updateItem(fields: [String: Any]) {
        guard let accountId = accountContext.currentAccountId,
              let itemId = item.id else { return }
        let service = ItemsService(syncTracker: NoOpSyncTracker())
        Task {
            try? await service.updateItem(accountId: accountId, itemId: itemId, fields: fields)
        }
    }

    private func toggleBookmark() {
        updateItem(fields: ["bookmark": !(item.bookmark ?? false)])
    }

    private func deleteItem() {
        guard let accountId = accountContext.currentAccountId,
              let itemId = item.id else { return }
        let service = ItemsService(syncTracker: NoOpSyncTracker())
        Task {
            try? await service.deleteItem(accountId: accountId, itemId: itemId)
            await MainActor.run { dismiss() }
        }
    }
}

// MARK: - DateFormatter helper

private extension DateFormatter {
    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}
