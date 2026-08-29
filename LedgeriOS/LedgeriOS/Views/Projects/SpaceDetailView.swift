import FirebaseFirestore
import SwiftUI

struct SpaceDetailView: View {
    let space: Space
    let projectId: String?

    @State private var isContentReady = false

    init(space: Space, projectId: String? = nil) {
        self.space = space
        self.projectId = projectId ?? space.projectId
    }

    var body: some View {
        Group {
            if isContentReady {
                SpaceDetailContainerContent(space: space, projectId: projectId)
            } else {
                BrandColors.background
                    .ignoresSafeArea()
            }
        }
        .task {
            // Keep the large detail and scoped-context graph out of the navigation push transaction.
            await Task.yield()
            guard !Task.isCancelled else { return }
            isContentReady = true
        }
    }
}

private struct SpaceDetailContainerContent: View {
    let space: Space
    let projectId: String?

    @Environment(AccountContext.self) private var accountContext
    @Environment(AuthManager.self) private var authManager
    @Environment(ProjectContext.self) private var ambientProjectContext
    @State private var scopedProjectContext: ProjectContext

    init(space: Space, projectId: String?) {
        self.space = space
        self.projectId = projectId
        _scopedProjectContext = State(initialValue: ProjectContext(
            projectService: ProjectService(),
            transactionsService: TransactionsService(),
            itemsService: ItemsService(),
            protoItemsService: ProtoItemsService(),
            spacesService: SpacesService(),
            projectBudgetCategoriesService: ProjectBudgetCategoriesService()
        ))
    }

    var body: some View {
        if let projectId, ambientProjectContext.currentProjectId != projectId {
            detail
                .environment(scopedProjectContext)
                .task(id: activationKey(projectId: projectId)) {
                    guard let accountId = accountContext.currentAccountId else { return }
                    scopedProjectContext.activate(
                        accountId: accountId,
                        projectId: projectId,
                        userId: authManager.currentUser?.uid,
                        member: accountContext.member,
                        rawBudgetCategories: accountContext.rawAllBudgetCategories
                    )
                }
                .onChange(of: accountContext.member) { _, member in
                    scopedProjectContext.updateFinancialContext(
                        member: member,
                        rawBudgetCategories: accountContext.rawAllBudgetCategories
                    )
                }
                .onChange(of: accountContext.rawAllBudgetCategories) { _, categories in
                    scopedProjectContext.updateFinancialContext(
                        member: accountContext.member,
                        rawBudgetCategories: categories
                    )
                }
        } else {
            detail
        }
    }

    private var detail: some View {
        SpaceDetailContentView(space: space, projectId: projectId)
    }

    private func activationKey(projectId: String) -> String {
        [
            accountContext.currentAccountId ?? "",
            projectId,
            authManager.currentUser?.uid ?? "",
        ].joined(separator: "|")
    }
}

private struct SpaceDetailContentView: View {
    let space: Space
    /// Navigation scope is immutable route context. Do not infer it from a
    /// listener-updated document; a transient/legacy missing `projectId`
    /// would incorrectly switch a project space to inventory data.
    let projectId: String?

    init(space: Space, projectId: String? = nil) {
        self.space = space
        self.projectId = projectId ?? space.projectId
    }

    @Environment(ProjectContext.self) private var projectContext
    @Environment(InventoryContext.self) private var inventoryContext
    @Environment(AccountContext.self) private var accountContext
    @Environment(MediaService.self) private var mediaService
    @Environment(FindStateManager.self) private var findState
    @Environment(\.dismiss) private var dismiss

    // Collapsible section state (all expanded by default)
    @State private var isMediaExpanded = true
    @State private var isNotesExpanded = true
    @State private var isItemsExpanded = true
    @State private var isChecklistsExpanded = true

    // Modal presentation
    @State private var showActionMenu = false
    @State private var showEditDetails = false
    @State private var showEditNotes = false
    @State private var showEditChecklists = false
    @State private var showDeleteConfirmation = false
    @State private var showAddItemMenu = false
    @State private var showCreateNewItem = false
    @State private var isPrintingPhotos = false
    @State private var menuPendingAction: (() -> Void)?
    @State private var errorMessage: String?

    // Image pinning
    @State private var pinnedAttachment: AttachmentRef?
    @State private var pinnedImageSource: [AttachmentRef] = []
    @State private var isMatchingItemsToPhoto = false
    @State private var pendingPhotoMatchItemId: String?

    // Items picker
    @State private var showAddExistingItems = false
    @State private var itemActions = ItemActionsController()
    @State private var selectedItemIds: Set<String> = []
    @State private var selectedItemId: String?
    @State private var showItemDetail = false

    // Bulk action modals
    @State private var showBulkActionMenu = false
    @State private var showBulkStatusPicker = false
    @State private var showBulkSetSpace = false
    @State private var showBulkReturnToInventory = false
    @State private var showBulkSellToProject = false
    @State private var showBulkReassign = false
    @State private var showBulkTransactionPicker = false
    @State private var showBulkDeleteConfirmation = false

    // Live document subscription
    @State private var liveSpaceData: Space?
    @State private var spaceListener: ListenerRegistration?

    // MARK: - Computed

    private var liveSpace: Space {
        liveSpaceData ?? space
    }

    private var isInventorySpace: Bool {
        projectId == nil
    }

    private var activeItems: [Item] {
        isInventorySpace ? inventoryContext.items : projectContext.items
    }

    private var activeSpaces: [Space] {
        isInventorySpace ? inventoryContext.spaces : projectContext.spaces
    }

    private var activeTransactions: [Transaction] {
        isInventorySpace ? inventoryContext.transactions : projectContext.transactions
    }

    private var itemScope: ItemScope {
        isInventorySpace ? .inventory : .project
    }

    private var spaceItems: [Item] {
        guard let spaceId = liveSpace.id else { return [] }
        return activeItems.filter { $0.spaceId == spaceId }
    }

    private var markedPhotoItemIds: Set<String> {
        PinnedImageCalculations.markedItemIds(in: liveSpace.images ?? [])
    }

    private var pendingPhotoMatchItemName: String? {
        guard let pendingPhotoMatchItemId else { return nil }
        return spaceItems.first(where: { $0.id == pendingPhotoMatchItemId })?.displayName
    }

    private var selectedItems: [Item] {
        activeItems.filter { item in
            guard let id = item.id else { return false }
            return selectedItemIds.contains(id)
        }
    }

    private var selectedItemsCanReturnToInventory: Bool {
        !selectedItems.isEmpty && selectedItems.allSatisfy {
            InventoryOperationsService.cameFromInventory($0)
        }
    }

    private var selectedTotalCents: Int? {
        let pairs = selectedItems.compactMap { item -> (id: String, cents: Int)? in
            guard let id = item.id, let cents = item.normalizedProjectPriceCents else { return nil }
            return (id: id, cents: cents)
        }
        let total = SelectionCalculations.totalCentsForSelected(selectedIds: selectedItemIds, items: pairs)
        return total > 0 ? total : nil
    }

    private var canSaveAsTemplate: Bool {
        guard let member = accountContext.member else { return false }
        return SpaceDetailCalculations.canSaveAsTemplate(userRole: member.role?.rawValue ?? "")
    }

    // MARK: - Body

    var body: some View {
        PinnedImageLayout(
            pinnedAttachment: pinnedAttachment,
            allImages: pinnedImageSource,
            onClose: closePinnedImage,
            onChangeImage: changePinnedImage,
            onUpdateCheckmarks: updateImageCheckmarks,
            isMatchingItems: isMatchingItemsToPhoto,
            pendingItemId: pendingPhotoMatchItemId,
            pendingItemName: pendingPhotoMatchItemName,
            onToggleItemMatching: toggleItemMatching,
            onCancelPendingItemMatch: { pendingPhotoMatchItemId = nil },
            onPlaceItemCheckmark: placeItemCheckmark,
            itemNameForId: itemNameForPhotoCheckmark,
            onMoveItemCheckmark: beginPhotoMatch,
            onClearAllCheckmarks: clearAllPhotoCheckmarks
        ) {
            ScrollViewReader { proxy in
                ScrollView {
                    AdaptiveContentWidth {
                        LazyVStack(alignment: .leading, spacing: Spacing.lg, pinnedViews: [.sectionHeaders]) {
                            spaceOverviewSection
                            itemsSection
                            checklistsSection
                        }
                        .padding(.horizontal, Spacing.screenPadding)
                        .padding(.vertical, Spacing.sm)
                    }
                }
                .onReceive(findState.scrollToPublisher) { matchID in
                    withAnimation { proxy.scrollTo(matchID, anchor: .center) }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !selectedItemIds.isEmpty {
                BulkSelectionBar(
                    selectedCount: selectedItemIds.count,
                    totalCents: selectedTotalCents,
                    onBulkActions: { showBulkActionMenu = true },
                    onClear: { selectedItemIds.removeAll() }
                )
            }
        }
        .findEntity(id: space.id)
        .navBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(liveSpace.name.isEmpty ? "Space" : liveSpace.name)
                    .font(Typography.h3)
                    .foregroundStyle(BrandColors.textPrimary)
                    .lineLimit(1)
            }
            ToolbarItem(placement: .trailingNavBar) {
                Button {
                    showActionMenu = true
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }
        }
        .adaptivePresentation(isPresented: $showActionMenu, style: .quickMenu, onDismiss: {
            menuPendingAction?()
            menuPendingAction = nil
        }) {
            ActionMenuSheet(
                title: liveSpace.name.isEmpty ? "Space" : liveSpace.name,
                items: actionMenuItems,
                onSelectAction: { action in menuPendingAction = action }
            )
        }
        .adaptivePresentation(isPresented: $showBulkActionMenu, style: .quickMenu) {
            ActionMenuSheet(
                title: "\(selectedItemIds.count) selected",
                items: bulkActionMenuItems + [
                    ActionMenuItem(id: "clear-selection", label: "Clear Selection", icon: "xmark.circle", onPress: {
                        selectedItemIds.removeAll()
                    })
                ]
            )
        }
        .adaptivePresentation(isPresented: $showEditDetails, style: .form) {
            EditSpaceDetailsModal(space: liveSpace) { name, notes in
                updateSpace(fields: ["name": name, "notes": notes ?? NSNull()])
            }
        }
        .adaptivePresentation(isPresented: $showEditNotes, style: .form) {
            EditNotesModal(notes: liveSpace.notes ?? "") { newNotes in
                updateSpace(fields: ["notes": newNotes])
            }
        }
        .adaptivePresentation(isPresented: $showEditChecklists, style: .form) {
            EditChecklistModal(space: liveSpace) { updatedChecklists in
                saveChecklists(updatedChecklists)
            }
        }
        .adaptivePresentation(isPresented: $showAddExistingItems, style: .fullSheet) {
            AddExistingItemsPicker(
                context: .space(liveSpace),
                projectId: projectId,
                onDismiss: { showAddExistingItems = false }
            )
        }
        .adaptivePresentation(isPresented: $showAddItemMenu, style: .quickMenu, onDismiss: {
            menuPendingAction?()
            menuPendingAction = nil
        }) {
            ActionMenuSheet(
                title: "Add Item",
                items: [
                    ActionMenuItem(
                        id: "create-new",
                        label: "Create New Item",
                        icon: "plus.square.fill",
                        onPress: { showCreateNewItem = true }
                    ),
                    ActionMenuItem(
                        id: "add-existing",
                        label: "Add Existing Items",
                        icon: "plus.square.on.square",
                        onPress: { showAddExistingItems = true }
                    ),
                ],
                onSelectAction: { action in menuPendingAction = action }
            )
        }
        .adaptivePresentation(
            isPresented: $showCreateNewItem,
            style: pinnedAttachment == nil ? .form : .referenceForm
        ) {
            NewItemView(
                context: projectId.map { .project($0, spaceId: liveSpace.id) } ?? .inventory,
                initialSpaceId: liveSpace.id
            )
        }
        .confirmationDialog("Delete Space?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteSpace()
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .itemActionSheets(
            itemActions,
            spaces: activeSpaces,
            transactions: activeTransactions,
            accountId: accountContext.currentAccountId
        )
        .adaptivePresentation(isPresented: $showBulkStatusPicker, style: .quickMenu) {
            StatusPickerModal { status in updateStatusForSelected(status) }
        }
        .adaptivePresentation(isPresented: $showBulkSetSpace, style: .picker) {
            SetSpaceModal(
                spaces: activeSpaces,
                currentSpaceId: liveSpace.id,
                onSelect: { space in setSpaceForSelected(spaceId: space?.id) }
            )
        }
        .adaptivePresentation(isPresented: $showBulkTransactionPicker, style: .picker) {
            TransactionPickerModal(
                transactions: activeTransactions,
                selectedId: nil,
                onSelect: { tx in
                    if let txId = tx.id { setTransactionForSelected(transactionId: txId) }
                }
            )
        }
        .adaptivePresentation(isPresented: $showBulkReturnToInventory, style: .form) {
            if let accountId = accountContext.currentAccountId {
                MoveToInventoryModal(items: selectedItems, accountId: accountId) {
                    selectedItemIds.removeAll()
                }
            }
        }
        .adaptivePresentation(isPresented: $showBulkSellToProject, style: .form) {
            if let accountId = accountContext.currentAccountId {
                SellItemsModal(items: selectedItems, accountId: accountId) {
                    selectedItemIds.removeAll()
                }
            }
        }
        .adaptivePresentation(isPresented: $showBulkReassign, style: .form) {
            ReassignToProjectModal(items: selectedItems) {
                selectedItemIds.removeAll()
            }
        }
        .confirmationDialog("Delete \(selectedItemIds.count) items?", isPresented: $showBulkDeleteConfirmation) {
            Button("Delete", role: .destructive) { deleteSelected() }
        } message: {
            Text("This action cannot be undone.")
        }
        .navigationDestination(isPresented: $showItemDetail) {
            if let selectedItemId,
               let item = activeItems.first(where: { $0.id == selectedItemId }) {
                ItemDetailView(
                    itemId: selectedItemId,
                    projectId: projectId,
                    initialItem: item
                )
            } else {
                ContentUnavailableView("Item Unavailable", systemImage: "cube.box")
            }
        }
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task { startSpaceListener() }
        .onDisappear { spaceListener?.remove() }
        .background(BrandColors.background)
    }

    // MARK: - Collapsible Sections

    private var spaceOverviewSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            completionControl

            Divider()
                .padding(.vertical, Spacing.xs)

            mediaSection
        }
        .cardStyle()
    }

    @ViewBuilder
    private var itemsSection: some View {
        if isItemsExpanded {
            itemsContent
        } else {
            pinnedItemsHeader
        }
    }

    private var pinnedItemsHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            CollapsibleSection(
                title: "NOTES",
                isExpanded: $isNotesExpanded,
                onEdit: { showEditNotes = true }
            ) {
                notesContent
            }

            Divider()
                .padding(.vertical, Spacing.xs)

            itemsSectionHeader
        }
        .cardStyle()
    }

    private var itemsSectionHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                isItemsExpanded.toggle()
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(BrandColors.textTertiary)
                    .rotationEffect(.degrees(isItemsExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.25), value: isItemsExpanded)

                Text("ITEMS")
                    .sectionLabelStyle()

                Text("\(spaceItems.count)")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.primary)

                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var checklistsSection: some View {
        CollapsibleSection(
            title: "CHECKLISTS",
            isExpanded: $isChecklistsExpanded,
            badge: "\(liveSpace.checklists?.count ?? 0)",
            onEdit: { showEditChecklists = true }
        ) {
            checklistsContent
        }
        .cardStyle()
    }

    private var completionControl: some View {
        Button {
            updateSpace(fields: ["isComplete": liveSpace.isComplete != true])
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: liveSpace.isComplete == true ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(liveSpace.isComplete == true ? .green : BrandColors.textTertiary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(liveSpace.isComplete == true ? "Space complete" : "Mark space complete")
                        .font(Typography.label)
                        .foregroundStyle(BrandColors.textPrimary)
                    Text(liveSpace.isComplete == true
                         ? "The physical space matches Ledger."
                         : "Confirm the physical space and every Ledger item match.")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(liveSpace.isComplete == true ? "Complete" : "Incomplete")
    }

    private var mediaSection: some View {
        CollapsibleSection(
            title: "MEDIA",
            isExpanded: $isMediaExpanded,
            onPrint: printSpacePhotos,
            isPrinting: isPrintingPhotos,
            isPrintDisabled: printableSpacePhotos.isEmpty
        ) {
            mediaContent
        }
    }

    // MARK: - Media

    private var printableSpacePhotos: [AttachmentRef] {
        (liveSpace.images ?? []).filter {
            $0.kind == .image && !$0.url.isEmpty && $0.isUploading != true
        }
    }

    @ViewBuilder
    private var mediaContent: some View {
        MediaGallerySection(
            title: "",
            attachments: liveSpace.images ?? [],
            onUploadAttachment: { data in
                try await uploadImage(data)
            },
            onRemoveAttachment: { attachment in
                removeImage(attachment)
            },
            onSetPrimary: { attachment in
                setPrimaryImage(attachment)
            },
            onPinImage: { attachment in
                pinImage(attachment)
            }
        )
        .padding(.top, Spacing.xs)
    }

    // MARK: - Notes

    @ViewBuilder
    private var notesContent: some View {
        if let notes = liveSpace.notes, !notes.isEmpty {
            SelectableNoteText(text: notes, style: .body)
                .padding(.top, Spacing.xs)
        } else {
            Text("No notes")
                .font(Typography.small)
                .foregroundStyle(BrandColors.textSecondary)
                .padding(.top, Spacing.xs)
        }
    }

    // MARK: - Items

    @ViewBuilder
    private var itemsContent: some View {
        SharedItemsList(
            mode: .embedded(items: spaceItems, onItemPress: { itemId in
                selectedItemId = itemId
                showItemDetail = true
            }),
            getMenuItems: { spaceItemMenuItems(for: $0) },
            emptyMessage: "No items in this space",
            onAdd: { showAddItemMenu = true },
            getBulkMenuItems: { bulkActionMenuItems },
            selectedIds: $selectedItemIds,
            filterScope: .spaceDetail,
            filterCatalog: ItemFilterCatalog(
                spaces: [],
                budgetCategories: projectId == nil ? [] : projectContext.budgetCategories
            ),
            inline: true,
            inlineSectionHeader: AnyView(pinnedItemsHeader),
            isItemMarkedInPhoto: { item in
                guard let itemId = item.id else { return false }
                return markedPhotoItemIds.contains(itemId)
            },
            photoMatchActionTitle: { item in
                guard isMatchingItemsToPhoto,
                      pinnedAttachment?.kind == .image,
                      let itemId = item.id else { return nil }
                return markedPhotoItemIds.contains(itemId) ? "Move checkmark" : "Mark in photo"
            },
            photoMatchTargetItemId: pendingPhotoMatchItemId,
            onPhotoMatchPress: beginPhotoMatch,
            showsGroupExpansionControl: isMatchingItemsToPhoto
        )
    }

    private func spaceItemMenuItems(for item: Item) -> [ActionMenuItem] {
        guard let itemId = item.id else { return [] }
        return itemActions.buildMenu(
            for: item,
            scope: itemScope,
            menuContext: .space,
            accountId: accountContext.currentAccountId,
            onSelect: { selectedItemIds.insert(itemId) },
            projectDestinationPresentation: .resolve(
                for: [item],
                transactions: accountContext.allTransactions,
                projects: accountContext.allProjects
            )
        )
    }

    // MARK: - Checklists

    @ViewBuilder
    private var checklistsContent: some View {
        let checklists = liveSpace.checklists ?? []
        if checklists.isEmpty {
            Text("No checklists")
                .font(Typography.small)
                .foregroundStyle(BrandColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, Spacing.xl)
        } else {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                ForEach(checklists) { checklist in
                    checklistView(checklist)
                }
            }
            .padding(.top, Spacing.xs)
        }
    }

    @ViewBuilder
    private func checklistView(_ checklist: Checklist) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            FindableText(checklist.name)
                .font(Typography.label)
                .foregroundStyle(BrandColors.textPrimary)

            ForEach(checklist.items) { item in
                Button {
                    toggleChecklistItem(checklistId: checklist.id, itemId: item.id)
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(item.isChecked ? BrandColors.primary : BrandColors.textTertiary)

                        FindableText(item.text)
                            .font(Typography.body)
                            .foregroundStyle(item.isChecked ? BrandColors.textSecondary : BrandColors.textPrimary)
                            .strikethrough(item.isChecked)
                    }
                }
                .buttonStyle(.plain)
            }

            if !checklist.items.isEmpty {
                let checked = checklist.items.filter(\.isChecked).count
                let total = checklist.items.count
                ProgressBar(
                    percentage: Double(checked) / Double(total) * 100,
                    fillColor: BrandColors.primary,
                    height: 4
                )
            }
        }
    }

    // MARK: - Action Menu

    private var actionMenuItems: [ActionMenuItem] {
        var items: [ActionMenuItem] = [
            ActionMenuItem(id: "edit", label: "Edit Space", icon: "pencil", onPress: {
                showEditDetails = true
            }),
            ActionMenuItem(id: "notes", label: "Edit Notes", icon: "note.text", onPress: {
                showEditNotes = true
            }),
            ActionMenuItem(id: "checklists", label: "Edit Checklists", icon: "checklist", onPress: {
                showEditChecklists = true
            }),
        ]

        if canSaveAsTemplate {
            items.append(ActionMenuItem(
                id: "template",
                label: "Save as Template",
                icon: "doc.on.doc",
                onPress: { saveAsTemplate() }
            ))
        }

        items.append(ActionMenuItem(
            id: "delete",
            label: "Delete Space",
            icon: "trash",
            isDestructive: true,
            onPress: { showDeleteConfirmation = true }
        ))

        return items
    }

    private var bulkActionMenuItems: [ActionMenuItem] {
        ItemMenuBuilder.buildBulkMenu(
            context: .space,
            scope: itemScope,
            callbacks: BulkItemMenuCallbacks(
                onStatusChange: { _ in showBulkStatusPicker = true },
                onSetTransaction: { showBulkTransactionPicker = true },
                onClearTransaction: { clearTransactionForSelected() },
                onSetSpace: { showBulkSetSpace = true },
                onClearSpace: { clearSpaceForSelected() },
                onReturnToInventory: selectedItemsCanReturnToInventory && !isInventorySpace
                    ? { showBulkReturnToInventory = true }
                    : nil,
                onSellToProject: { showBulkSellToProject = true },
                onReassignToProject: { showBulkReassign = true },
                onCopyIDs: { Clipboard.copyLines(selectedItemIds) },
                onDelete: { showBulkDeleteConfirmation = true }
            ),
            projectDestinationPresentation: .resolve(
                for: selectedItems,
                transactions: accountContext.allTransactions,
                projects: accountContext.allProjects
            )
        )
    }

    // MARK: - Actions

    private func printSpacePhotos() {
        guard !isPrintingPhotos else { return }
        let photos = printableSpacePhotos
        let spaceName = liveSpace.name.isEmpty ? "Space" : liveSpace.name
        isPrintingPhotos = true
        Task {
            defer { isPrintingPhotos = false }
            do {
                try await PhotoPrintHelper.printPhotos(
                    photos,
                    jobName: "\(spaceName) Photos"
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func startSpaceListener() {
        guard spaceListener == nil,
              let accountId = accountContext.currentAccountId,
              let spaceId = space.id else { return }
        spaceListener = SpacesService()
            .subscribeToSpace(accountId: accountId, spaceId: spaceId) { updatedSpace in
                self.liveSpaceData = updatedSpace
            }
    }

    private func updateStatusForSelected(_ status: ItemStatus) {
        updateSelectedItems(fields: ["status": status.rawValue])
    }

    private func setSpaceForSelected(spaceId: String?) {
        updateSelectedItems(fields: ["spaceId": spaceId as Any? ?? NSNull()])
    }

    private func clearSpaceForSelected() {
        updateSelectedItems(fields: ["spaceId": NSNull()])
    }

    private func updateSelectedItems(fields: [String: Any]) {
        guard let accountId = accountContext.currentAccountId else { return }
        let items = selectedItems
        nonisolated(unsafe) let updateFields = fields
        Task {
            do {
                try await ItemsService().updateItems(
                    accountId: accountId,
                    items: items,
                    fields: updateFields
                )
            } catch {
                print("Bulk item update failed: \(error)")
            }
        }
        selectedItemIds.removeAll()
    }

    private func setTransactionForSelected(transactionId: String) {
        guard let accountId = accountContext.currentAccountId else { return }
        let items = Array(selectedItems)
        Task { try? await ItemsService().setTransaction(accountId: accountId, items: items, transactionId: transactionId) }
        selectedItemIds.removeAll()
    }

    private func clearTransactionForSelected() {
        guard let accountId = accountContext.currentAccountId else { return }
        let items = Array(selectedItems)
        Task { try? await ItemsService().clearTransaction(accountId: accountId, items: items) }
        selectedItemIds.removeAll()
    }

    private func updateSpace(fields: [String: Any]) {
        guard let accountId = accountContext.currentAccountId,
              let spaceId = space.id else {
            print("⚠️ updateSpace skipped — missing accountId or spaceId")
            return
        }
        let service = SpacesService()
        nonisolated(unsafe) let f = fields
        Task {
            do {
                try await service.updateSpace(accountId: accountId, spaceId: spaceId, fields: f)
            } catch {
                print("🔴 updateSpace failed: \(error)")
            }
        }
    }

    private func saveChecklists(_ checklists: [Checklist]) {
        let encoded = checklists.map { checklist -> [String: Any] in
            [
                "id": checklist.id,
                "name": checklist.name,
                "items": checklist.items.map { item -> [String: Any] in
                    [
                        "id": item.id,
                        "text": item.text,
                        "isChecked": item.isChecked,
                    ]
                },
            ]
        }
        updateSpace(fields: ["checklists": encoded])
    }

    private func toggleChecklistItem(checklistId: String, itemId: String) {
        guard var checklists = liveSpace.checklists else { return }
        guard let ci = checklists.firstIndex(where: { $0.id == checklistId }),
              let ii = checklists[ci].items.firstIndex(where: { $0.id == itemId }) else { return }
        checklists[ci].items[ii].isChecked.toggle()
        saveChecklists(checklists)
    }

    private func uploadImage(_ data: Data) async throws {
        guard let accountId = accountContext.currentAccountId,
              let spaceId = space.id else { return }
        let filename = "\(UUID().uuidString).jpg"
        let path = mediaService.uploadPath(
            accountId: accountId,
            entityType: "spaces",
            entityId: spaceId,
            filename: filename
        )

        // H7: Write placeholder first so the Firestore record survives upload failures
        var images = liveSpace.images ?? []
        let isPrimary = images.isEmpty
        images.append(AttachmentRef(
            url: "",
            fileName: filename,
            contentType: "image/jpeg",
            isPrimary: isPrimary,
            isUploading: true
        ))
        updateSpace(fields: ["images": images.map(attachmentDict)])

        // Upload bytes (H8: MediaService retries on transient failures)
        let url = try await mediaService.uploadImage(data, path: path)
        let thumbnails = await mediaService.uploadThumbnails(
            for: data,
            originalPath: path,
            contentType: "image/jpeg"
        )

        // Replace placeholder with real URL
        var updatedImages = liveSpace.images ?? []
        if let idx = updatedImages.firstIndex(where: { $0.url.isEmpty && $0.fileName == filename }) {
            updatedImages[idx].url = url
            updatedImages[idx].thumbnailUrlSm = thumbnails.sm
            updatedImages[idx].thumbnailUrlMd = thumbnails.md
            updatedImages[idx].isUploading = nil
        } else {
            // Listener hasn't reflected the placeholder yet — append the resolved ref directly
            updatedImages.append(AttachmentRef(
                url: url,
                thumbnailUrlSm: thumbnails.sm,
                thumbnailUrlMd: thumbnails.md,
                fileName: filename,
                contentType: "image/jpeg",
                isPrimary: isPrimary
            ))
        }
        updateSpace(fields: ["images": updatedImages.map(attachmentDict)])
    }

    private func removeImage(_ attachment: AttachmentRef) {
        var images = liveSpace.images ?? []
        images.removeAll { $0.url == attachment.url }
        updateSpace(fields: ["images": images.map(attachmentDict)])
        Task {
            try? await mediaService.deleteImage(url: attachment.url)
        }
    }

    private func setPrimaryImage(_ attachment: AttachmentRef) {
        guard var images = liveSpace.images else { return }
        images = images.map { img in
            var copy = img
            copy.isPrimary = (img.url == attachment.url)
            return copy
        }
        updateSpace(fields: ["images": images.map(attachmentDict)])
    }

    private func pinImage(_ attachment: AttachmentRef) {
        pinnedImageSource = (liveSpace.images ?? []).filter(PinnedImageCalculations.canPin)
        pinnedAttachment = attachment
        pendingPhotoMatchItemId = nil
    }

    private func closePinnedImage() {
        pinnedAttachment = nil
        isMatchingItemsToPhoto = false
        pendingPhotoMatchItemId = nil
    }

    private func changePinnedImage(_ attachment: AttachmentRef) {
        pinnedAttachment = attachment
        pendingPhotoMatchItemId = nil
        if attachment.kind != .image {
            isMatchingItemsToPhoto = false
        }
    }

    private func toggleItemMatching() {
        isMatchingItemsToPhoto.toggle()
        pendingPhotoMatchItemId = nil
        if isMatchingItemsToPhoto {
            isItemsExpanded = true
        }
    }

    private func beginPhotoMatch(_ item: Item) {
        guard isMatchingItemsToPhoto,
              pinnedAttachment?.kind == .image,
              let itemId = item.id else { return }
        pendingPhotoMatchItemId = itemId
    }

    private func beginPhotoMatch(itemId: String) {
        guard isMatchingItemsToPhoto,
              pinnedAttachment?.kind == .image,
              spaceItems.contains(where: { $0.id == itemId }) else { return }
        pendingPhotoMatchItemId = itemId
    }

    private func itemNameForPhotoCheckmark(itemId: String) -> String? {
        spaceItems.first(where: { $0.id == itemId })?.displayName
    }

    private func attachmentDict(_ ref: AttachmentRef) -> [String: Any] {
        ref.firestoreDictionary
    }

    private func updateImageCheckmarks(_ attachment: AttachmentRef, _ checkmarks: [ImageCheckmark]) {
        guard var images = liveSpace.images,
              let index = images.firstIndex(where: { $0.url == attachment.url }) else { return }
        images[index].checkmarks = checkmarks.isEmpty ? nil : checkmarks
        pinnedImageSource = images.filter(PinnedImageCalculations.canPin)
        pinnedAttachment = images[index]
        updateSpace(fields: ["images": images.map(attachmentDict)])
    }

    private func clearAllPhotoCheckmarks() {
        let images = PinnedImageCalculations.clearingCheckmarks(from: liveSpace.images ?? [])
        pinnedImageSource = images.filter(PinnedImageCalculations.canPin)
        if let pinnedURL = pinnedAttachment?.url {
            pinnedAttachment = images.first(where: { $0.url == pinnedURL })
        }
        pendingPhotoMatchItemId = nil
        updateSpace(fields: ["images": images.map(attachmentDict)])
    }

    private func placeItemCheckmark(
        _ attachment: AttachmentRef,
        _ itemId: String,
        _ normalizedPoint: CGPoint
    ) {
        guard pendingPhotoMatchItemId == itemId else { return }
        let images = PinnedImageCalculations.placingCheckmark(
            for: itemId,
            at: normalizedPoint,
            in: attachment.url,
            attachments: liveSpace.images ?? []
        )
        pinnedImageSource = images.filter(PinnedImageCalculations.canPin)
        pinnedAttachment = images.first(where: { $0.url == attachment.url })
        pendingPhotoMatchItemId = nil
        updateSpace(fields: ["images": images.map(attachmentDict)])
    }

    private func saveAsTemplate() {
        // SpaceTemplatesService not yet built (WP13) — show placeholder alert
        errorMessage = "Template saved! (Template service coming soon)"
    }


    private func deleteSpace() {
        guard let accountId = accountContext.currentAccountId,
              let spaceId = space.id else { return }
        let service = SpacesService()
        Task {
            do {
                try await service.deleteSpace(accountId: accountId, spaceId: spaceId)
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run { errorMessage = "Failed to delete space." }
            }
        }
    }

    private func deleteSelected() {
        guard let accountId = accountContext.currentAccountId else { return }
        let service = ItemsService()
        let items = Array(selectedItems)
        Task { try? await service.deleteItems(accountId: accountId, items: items) }
        selectedItemIds.removeAll()
    }

}
