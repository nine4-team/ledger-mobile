import SwiftUI

struct SpaceDetailView: View {
    let space: Space

    @Environment(ProjectContext.self) private var projectContext
    @Environment(AccountContext.self) private var accountContext
    @Environment(MediaService.self) private var mediaService
    @Environment(\.dismiss) private var dismiss

    // Collapsible section state (Media expanded by default, others collapsed)
    @State private var isMediaExpanded = true
    @State private var isNotesExpanded = false
    @State private var isItemsExpanded = false
    @State private var isChecklistsExpanded = false

    // Modal presentation
    @State private var showActionMenu = false
    @State private var showEditDetails = false
    @State private var showEditNotes = false
    @State private var showEditChecklists = false
    @State private var showDeleteConfirmation = false
    @State private var menuPendingAction: (() -> Void)?
    @State private var errorMessage: String?

    // Items section state
    @State private var searchText = ""
    @State private var isSearchVisible = false
    @State private var activeFilter: ItemFilterOption = .all
    @State private var activeSort: ItemSortOption = .createdDesc
    @State private var showFilterMenu = false
    @State private var showSortMenu = false

    // MARK: - Computed

    private var liveSpace: Space {
        projectContext.spaces.first(where: { $0.id == space.id }) ?? space
    }

    private var spaceItems: [Item] {
        projectContext.items.filter { $0.spaceId == space.id }
    }

    private var filteredItems: [Item] {
        ListFilterSortCalculations.applyAllFilters(
            spaceItems,
            filter: activeFilter,
            sort: activeSort,
            search: searchText
        )
    }

    private var canSaveAsTemplate: Bool {
        guard let member = accountContext.member else { return false }
        return member.role == .owner || member.role == .admin
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                sectionsArea
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.vertical, Spacing.sm)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(liveSpace.name.isEmpty ? "Space" : liveSpace.name)
                    .font(Typography.h3)
                    .foregroundStyle(BrandColors.textPrimary)
                    .lineLimit(1)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showActionMenu = true
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }
        }
        .sheet(isPresented: $showActionMenu, onDismiss: {
            menuPendingAction?()
            menuPendingAction = nil
        }) {
            ActionMenuSheet(
                title: liveSpace.name.isEmpty ? "Space" : liveSpace.name,
                items: actionMenuItems,
                onSelectAction: { action in menuPendingAction = action }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showEditDetails) {
            EditSpaceDetailsModal(space: liveSpace) { name, notes in
                updateSpace(fields: ["name": name, "notes": notes ?? NSNull()])
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showEditNotes) {
            EditNotesModal(notes: liveSpace.notes ?? "") { newNotes in
                updateSpace(fields: ["notes": newNotes])
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showEditChecklists) {
            EditChecklistModal(space: liveSpace) { updatedChecklists in
                saveChecklists(updatedChecklists)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog("Delete Space?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteSpace()
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .background(FilterMenu(
            isPresented: $showFilterMenu,
            filters: FilterMenu.filterMenuItems(
                activeFilter: activeFilter,
                onSelect: { activeFilter = $0 }
            ),
            closeOnItemPress: true
        ))
        .background(SortMenu(
            isPresented: $showSortMenu,
            sortOptions: SortMenu.sortMenuItems(
                activeSort: activeSort,
                onSelect: { activeSort = $0 }
            )
        ))
        .navigationDestination(for: Item.self) { item in
            ItemDetailView(item: item)
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

            CollapsibleSection(
                title: "ITEMS",
                isExpanded: $isItemsExpanded,
                badge: "\(spaceItems.count)"
            ) {
                itemsContent
            }

            Divider()
                .padding(.vertical, Spacing.xs)

            CollapsibleSection(
                title: "CHECKLISTS",
                isExpanded: $isChecklistsExpanded,
                badge: "\(liveSpace.checklists?.count ?? 0)",
                onEdit: { showEditChecklists = true }
            ) {
                checklistsContent
            }
        }
        .cardStyle()
    }

    // MARK: - Media

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
            emptyStateMessage: "No images yet"
        )
        .padding(.top, Spacing.xs)
    }

    // MARK: - Notes

    @ViewBuilder
    private var notesContent: some View {
        if let notes = liveSpace.notes, !notes.isEmpty {
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

    // MARK: - Items

    @ViewBuilder
    private var itemsContent: some View {
        VStack(spacing: 0) {
            ItemsListControlBar(
                searchText: $searchText,
                isSearchVisible: $isSearchVisible,
                onSort: { showSortMenu = true },
                onFilter: { showFilterMenu = true },
                activeFilterCount: activeFilter != .all ? 1 : 0,
                activeSortLabel: activeSort != .createdDesc ? sortLabel(for: activeSort) : nil
            )

            if filteredItems.isEmpty {
                Text(spaceItems.isEmpty ? "No items in this space" : "No items match your filters")
                    .font(Typography.small)
                    .foregroundStyle(BrandColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Spacing.xl)
            } else {
                LazyVStack(spacing: Spacing.cardListGap) {
                    ForEach(filteredItems) { item in
                        NavigationLink(value: item) {
                            ItemCard(
                                name: item.name,
                                sku: item.sku,
                                sourceLabel: item.source,
                                priceLabel: displayPrice(for: item),
                                thumbnailUri: item.images?.first?.url,
                                bookmarked: item.bookmark == true
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, Spacing.sm)
            }
        }
        .padding(.top, Spacing.xs)
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
            Text(checklist.name)
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

                        Text(item.text)
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

    // MARK: - Actions

    private func updateSpace(fields: [String: Any]) {
        guard let accountId = accountContext.currentAccountId,
              let spaceId = space.id else { return }
        let service = SpacesService(syncTracker: NoOpSyncTracker())
        Task {
            try? await service.updateSpace(accountId: accountId, spaceId: spaceId, fields: fields)
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
        let url = try await mediaService.uploadImage(data, path: path)
        var images = liveSpace.images ?? []
        let isPrimary = images.isEmpty
        images.append(AttachmentRef(url: url, isPrimary: isPrimary))
        updateSpace(fields: ["images": images.map(attachmentDict)])
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

    private func attachmentDict(_ ref: AttachmentRef) -> [String: Any] {
        var dict: [String: Any] = [
            "url": ref.url,
            "kind": ref.kind.rawValue,
        ]
        if let fileName = ref.fileName { dict["fileName"] = fileName }
        if let contentType = ref.contentType { dict["contentType"] = contentType }
        if let isPrimary = ref.isPrimary { dict["isPrimary"] = isPrimary }
        return dict
    }

    private func saveAsTemplate() {
        // SpaceTemplatesService not yet built (WP13) — show placeholder alert
        errorMessage = "Template saved! (Template service coming soon)"
    }

    private func deleteSpace() {
        guard let accountId = accountContext.currentAccountId,
              let spaceId = space.id else { return }
        let service = SpacesService(syncTracker: NoOpSyncTracker())
        Task {
            do {
                try await service.deleteSpace(accountId: accountId, spaceId: spaceId)
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run { errorMessage = "Failed to delete space." }
            }
        }
    }

    // MARK: - Helpers

    private func displayPrice(for item: Item) -> String? {
        if let price = item.projectPriceCents, price != item.purchasePriceCents {
            return CurrencyFormatting.formatCentsWithDecimals(price)
        } else if let price = item.purchasePriceCents {
            return CurrencyFormatting.formatCentsWithDecimals(price)
        } else if let price = item.projectPriceCents {
            return CurrencyFormatting.formatCentsWithDecimals(price)
        }
        return nil
    }

    private func sortLabel(for option: ItemSortOption) -> String {
        switch option {
        case .createdDesc: return "Newest"
        case .createdAsc: return "Oldest"
        case .alphabeticalAsc: return "A-Z"
        case .alphabeticalDesc: return "Z-A"
        }
    }
}
