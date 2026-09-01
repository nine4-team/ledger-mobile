import SwiftUI
import FirebaseFirestore

struct ItemQuickDraftDetailView: View {
    let protoItem: ProtoItem

    @Environment(AccountContext.self) private var accountContext
    @Environment(ProjectContext.self) private var projectContext
    @Environment(AuthManager.self) private var authManager
    @Environment(MediaService.self) private var mediaService
    @Environment(\.dismiss) private var dismiss

    @State private var liveProtoItem: ProtoItem
    @State private var listener: ListenerRegistration?
    @State private var nameDraft: String
    @State private var notesDraft: String
    @State private var showConvertToItem = false
    @State private var showMergeWithExistingItem = false
    @State private var showSpacePicker = false
    @State private var showDeleteConfirmation = false
    @State private var errorMessage: String?
    @State private var skuDraft: String
    @State private var quantityDraft: Int

    private let protoItemsService = ProtoItemsService()

    init(protoItem: ProtoItem) {
        self.protoItem = protoItem
        self._liveProtoItem = State(initialValue: protoItem)
        self._nameDraft = State(initialValue: protoItem.name ?? "")
        self._notesDraft = State(initialValue: protoItem.notes ?? "")
        self._skuDraft = State(initialValue: protoItem.sku ?? "")
        self._quantityDraft = State(initialValue: max(protoItem.quantity ?? 1, 1))
    }

    private var photos: [AttachmentRef] {
        liveProtoItem.photos ?? []
    }

    private var nameHasChanges: Bool {
        nameDraft.trimmingCharacters(in: .whitespacesAndNewlines) != (liveProtoItem.name ?? "")
    }

    private var skuHasChanges: Bool {
        skuDraft.trimmingCharacters(in: .whitespacesAndNewlines) != (liveProtoItem.sku ?? "")
    }

    private var notesHasChanges: Bool {
        notesDraft.trimmingCharacters(in: .whitespacesAndNewlines) != (liveProtoItem.notes ?? "")
    }

    private var quantityHasChanges: Bool {
        quantityDraft != max(liveProtoItem.quantity ?? 1, 1)
    }

    private var quantityBinding: Binding<Int> {
        Binding(
            get: { quantityDraft },
            set: { quantityDraft = min(max($0, 1), 9999) }
        )
    }

    var body: some View {
        ScrollView {
            AdaptiveContentWidth {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    nameSection
                    assignmentSection
                    mediaSection
                    actionsSection
                    if let errorMessage {
                        Text(errorMessage)
                            .font(Typography.small)
                            .foregroundStyle(StatusColors.missedText)
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.vertical, Spacing.lg)
            }
        }
        .background(BrandColors.background.ignoresSafeArea())
        .navigationTitle("Needs Assignment")
        .navBarTitleDisplayMode(.inline)
        .onAppear(perform: subscribe)
        .onDisappear {
            listener?.remove()
            listener = nil
        }
        .confirmationDialog("Remove Item?", isPresented: $showDeleteConfirmation) {
            Button("Remove Item", role: .destructive) {
                Task { await deleteDraft() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the captured item and its media. This cannot be undone.")
        }
        .adaptivePresentation(isPresented: $showConvertToItem, style: .form) {
            NewItemView(
                context: conversionContext,
                initialTransactionId: liveProtoItem.transactionId,
                initialName: liveProtoItem.name,
                initialNotes: liveProtoItem.notes,
                initialSku: liveProtoItem.sku,
                initialSkuCandidates: liveProtoItem.extracted?.skuCandidates ?? [],
                initialQuantity: liveProtoItem.quantity,
                initialImageRefs: photos,
                initialSpaceId: liveProtoItem.spaceId,
                convertingProtoItemId: liveProtoItem.id,
                initialAssignmentHint: liveProtoItem.effectiveAssignmentHint,
                onCreated: { itemIds in
                    if let itemId = itemIds.first {
                        Task { await markConverted(itemId: itemId) }
                    }
                }
            )
        }
        .adaptivePresentation(isPresented: $showMergeWithExistingItem, style: .fullSheet) {
            ItemQuickDraftMergePicker(
                protoItem: liveProtoItem,
                items: mergeCandidateItems,
                filterCatalog: ItemFilterCatalog(
                    spaces: accountContext.allSpaces,
                    budgetCategories: accountContext.allBudgetCategories
                ),
                onMerge: { item in
                    Task { await mergeWithExistingItem(item) }
                }
            )
        }
        .adaptivePresentation(isPresented: $showSpacePicker, style: .picker) {
            SetSpaceModal(
                spaces: availableSpaces,
                currentSpaceId: liveProtoItem.spaceId,
                onSelect: { space in
                    Task { await saveSpace(space?.id) }
                }
            )
        }
    }

    private var conversionContext: ItemCreationContext? {
        if let projectId = liveProtoItem.projectId {
            return .project(projectId, spaceId: nil)
        }
        return .inventory
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            FormField(label: "Name", text: $nameDraft, placeholder: "Optional")
            if nameHasChanges {
                Button("Save Name") {
                    Task { await saveName() }
                }
                .font(Typography.label)
                .foregroundStyle(BrandColors.primary)
            }
            FormField(label: "Notes", text: $notesDraft, placeholder: "Optional notes", axis: .vertical)
            if notesHasChanges {
                Button("Save Notes") {
                    Task { await saveNotes() }
                }
                .font(Typography.label)
                .foregroundStyle(BrandColors.primary)
            }
            FormField(label: "SKU", text: $skuDraft, placeholder: "Barcode or SKU number")
            if !skuCandidates.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.xs) {
                        ForEach(skuCandidates, id: \.self) { candidate in
                            Button {
                                skuDraft = candidate
                                Task { await saveSku() }
                            } label: {
                                Text(candidate)
                                    .font(Typography.caption)
                                    .foregroundStyle(candidate == liveProtoItem.sku ? BrandColors.primary : BrandColors.textSecondary)
                                    .padding(.horizontal, Spacing.sm)
                                    .padding(.vertical, Spacing.xs)
                                    .background(
                                        RoundedRectangle(cornerRadius: Dimensions.buttonRadius)
                                            .fill(candidate == liveProtoItem.sku ? BrandColors.primary.opacity(0.12) : BrandColors.surfaceTertiary)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Dimensions.buttonRadius)
                                            .stroke(candidate == liveProtoItem.sku ? BrandColors.primary.opacity(0.35) : BrandColors.borderSecondary, lineWidth: Dimensions.borderWidth)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if skuHasChanges {
                Button("Save SKU") {
                    Task { await saveSku() }
                }
                .font(Typography.label)
                .foregroundStyle(BrandColors.primary)
            }
            quantitySection
        }
    }

    private var quantitySection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Quantity")
                .font(Typography.label)
                .foregroundStyle(BrandColors.textSecondary)

            HStack(spacing: 0) {
                TextField("1", value: quantityBinding, format: .number)
                    .font(Typography.input)
                    .foregroundStyle(BrandColors.textPrimary)
                    .platformKeyboardType(.numberPad)
                    .multilineTextAlignment(.leading)
                    .padding(.leading, Spacing.sm)
                    .frame(width: 96, alignment: .leading)

                Spacer()

                VStack(spacing: 0) {
                    Button {
                        if quantityDraft < 9999 { quantityDraft += 1 }
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(BrandColors.textPrimary)
                            .frame(width: 36, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        if quantityDraft > 1 { quantityDraft -= 1 }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(quantityDraft > 1 ? BrandColors.textPrimary : BrandColors.textDisabled)
                            .frame(width: 36, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(quantityDraft <= 1)
                }
            }
            .frame(height: 44)
            .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                    .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
            )

            if quantityHasChanges {
                Button("Save Quantity") {
                    Task { await saveQuantity() }
                }
                .font(Typography.label)
                .foregroundStyle(BrandColors.primary)
            }
        }
    }

    private var skuCandidates: [String] {
        var seen = Set<String>()
        return (liveProtoItem.extracted?.skuCandidates ?? []).filter { candidate in
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && seen.insert(trimmed).inserted
        }
    }

    private var mediaSection: some View {
        MediaGallerySection(
            title: "Photos",
            attachments: photos,
            allowedKinds: [.image],
            onUploadAttachment: { data in
                try await uploadPhoto(data)
            },
            onRemoveAttachment: { attachment in
                removePhoto(attachment)
            },
            onSetPrimary: { attachment in
                setPrimaryPhoto(attachment)
            }
        )
    }

    private var assignmentHintBinding: Binding<ProtoItemAssignmentHint> {
        Binding(
            get: { liveProtoItem.effectiveAssignmentHint },
            set: { hint in
                liveProtoItem.assignmentHint = hint
                liveProtoItem.isFromInventory = hint == .fromInventory
                Task { await saveAssignmentHint(hint) }
            }
        )
    }

    private var availableSpaces: [Space] {
        if let projectId = liveProtoItem.projectId {
            return projectContext.spaces.filter { $0.projectId == projectId }
        }
        return accountContext.allSpaces.filter { $0.projectId == nil }
    }

    private var selectedSpaceName: String {
        guard let spaceId = liveProtoItem.spaceId else { return "Select Space" }
        return availableSpaces.first(where: { $0.id == spaceId })?.name ?? "Unknown Space"
    }

    private var assignmentSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Assignment")
                .font(Typography.h3)
                .foregroundStyle(BrandColors.textPrimary)

            Text("This is a routing hint only. The choice you confirm while assigning the item is authoritative.")
                .font(Typography.caption)
                .foregroundStyle(BrandColors.textSecondary)

            InlineOptionPicker(selection: assignmentHintBinding, options: [
                InlineOption(id: .undecided, label: ProtoItemAssignmentHint.undecided.displayLabel),
                InlineOption(id: .clientPaid, label: ProtoItemAssignmentHint.clientPaid.displayLabel),
                InlineOption(id: .businessPaid, label: ProtoItemAssignmentHint.businessPaid.displayLabel),
                InlineOption(id: .fromInventory, label: ProtoItemAssignmentHint.fromInventory.displayLabel),
            ])

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Space")
                    .font(Typography.label)
                    .foregroundStyle(BrandColors.textSecondary)
                Button { showSpacePicker = true } label: {
                    HStack {
                        Text(selectedSpaceName)
                            .foregroundStyle(BrandColors.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(BrandColors.textSecondary)
                    }
                    .font(Typography.input)
                    .padding(.horizontal, Spacing.md)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                    .overlay(
                        RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                            .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var actionsSection: some View {
        VStack(spacing: Spacing.sm) {
            AppButton(
                title: "Assign Item",
                action: { showConvertToItem = true }
            )
            AppButton(
                title: "Match Existing Item",
                variant: .secondary,
                action: { showMergeWithExistingItem = true }
            )
            AppButton(
                title: "Remove Item",
                variant: .secondary,
                action: { showDeleteConfirmation = true }
            )
        }
    }

    private var mergeCandidateItems: [Item] {
        dedupeItems(projectContext.items + accountContext.allItems)
    }

    private func subscribe() {
        guard let accountId = accountContext.currentAccountId,
              let protoItemId = protoItem.id else { return }
        listener?.remove()
        listener = protoItemsService.subscribeToProtoItem(accountId: accountId, protoItemId: protoItemId) { item in
            guard let item else {
                dismiss()
                return
            }
            liveProtoItem = item
            if !nameHasChanges {
                nameDraft = item.name ?? ""
            }
            if !notesHasChanges {
                notesDraft = item.notes ?? ""
            }
            if !skuHasChanges {
                skuDraft = item.sku ?? ""
            }
            if !quantityHasChanges {
                quantityDraft = max(item.quantity ?? 1, 1)
            }
        }
    }

    private func saveName() async {
        guard let accountId = accountContext.currentAccountId,
              let protoItemId = liveProtoItem.id else { return }
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await protoItemsService.updateProtoItem(
                accountId: accountId,
                protoItemId: protoItemId,
                fields: ["name": trimmed.isEmpty ? FieldValue.delete() : trimmed]
            )
        } catch {
            errorMessage = "Failed to update name."
        }
    }

    private func saveSku() async {
        guard let accountId = accountContext.currentAccountId,
              let protoItemId = liveProtoItem.id else { return }
        let trimmed = skuDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await protoItemsService.updateProtoItem(
                accountId: accountId,
                protoItemId: protoItemId,
                fields: ["sku": trimmed.isEmpty ? FieldValue.delete() : trimmed]
            )
        } catch {
            errorMessage = "Failed to update SKU."
        }
    }

    private func saveNotes() async {
        guard let accountId = accountContext.currentAccountId,
              let protoItemId = liveProtoItem.id else { return }
        let trimmed = notesDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await protoItemsService.updateProtoItem(
                accountId: accountId,
                protoItemId: protoItemId,
                fields: ["notes": trimmed.isEmpty ? FieldValue.delete() : trimmed]
            )
        } catch {
            errorMessage = "Failed to update notes."
        }
    }

    private func saveQuantity() async {
        guard let accountId = accountContext.currentAccountId,
              let protoItemId = liveProtoItem.id else { return }
        do {
            try await protoItemsService.updateProtoItem(
                accountId: accountId,
                protoItemId: protoItemId,
                fields: ["quantity": max(quantityDraft, 1)]
            )
        } catch {
            errorMessage = "Failed to update quantity."
        }
    }

    private func saveAssignmentHint(_ hint: ProtoItemAssignmentHint) async {
        guard let accountId = accountContext.currentAccountId,
              let protoItemId = liveProtoItem.id else { return }
        do {
            try await protoItemsService.updateProtoItem(
                accountId: accountId,
                protoItemId: protoItemId,
                fields: [
                    "assignmentHint": hint.rawValue,
                    "isFromInventory": hint == .fromInventory,
                ]
            )
        } catch {
            errorMessage = "Failed to update the assignment route."
        }
    }

    private func saveSpace(_ spaceId: String?) async {
        guard let accountId = accountContext.currentAccountId,
              let protoItemId = liveProtoItem.id else { return }
        do {
            try await protoItemsService.updateProtoItem(
                accountId: accountId,
                protoItemId: protoItemId,
                fields: ["spaceId": spaceId as Any? ?? NSNull()]
            )
        } catch {
            errorMessage = "Failed to update the space."
        }
    }

    private func uploadPhoto(_ data: Data) async throws {
        guard let accountId = accountContext.currentAccountId,
              let protoItemId = liveProtoItem.id else { return }
        let filename = "\(UUID().uuidString).jpg"
        let path = mediaService.uploadPath(
            accountId: accountId,
            entityType: ProtoItemsService.entityType,
            entityId: protoItemId,
            filename: filename
        )
        let url = try await mediaService.uploadImage(data, path: path)
        var updatedPhotos = photos
        updatedPhotos.append(AttachmentRef(url: url, kind: .image, fileName: filename, isPrimary: updatedPhotos.isEmpty))
        try await protoItemsService.updateProtoItem(
            accountId: accountId,
            protoItemId: protoItemId,
            fields: ["photos": updatedPhotos.map(attachmentDict)]
        )
    }

    private func removePhoto(_ attachment: AttachmentRef) {
        guard let accountId = accountContext.currentAccountId,
              let protoItemId = liveProtoItem.id else { return }
        var updatedPhotos = photos.filter { $0.url != attachment.url }
        if !updatedPhotos.isEmpty, !updatedPhotos.contains(where: { $0.isPrimary == true }) {
            updatedPhotos[0].isPrimary = true
        }
        Task {
            do {
                try await protoItemsService.updateProtoItem(
                    accountId: accountId,
                    protoItemId: protoItemId,
                    fields: ["photos": updatedPhotos.map(attachmentDict)]
                )
                try? await mediaService.deleteImage(url: attachment.url)
            } catch {
                errorMessage = "Failed to remove photo."
            }
        }
    }

    private func setPrimaryPhoto(_ attachment: AttachmentRef) {
        guard let accountId = accountContext.currentAccountId,
              let protoItemId = liveProtoItem.id else { return }
        let updatedPhotos = photos.map { photo in
            var copy = photo
            copy.isPrimary = photo.url == attachment.url
            return copy
        }
        Task {
            do {
                try await protoItemsService.updateProtoItem(
                    accountId: accountId,
                    protoItemId: protoItemId,
                    fields: ["photos": updatedPhotos.map(attachmentDict)]
                )
            } catch {
                errorMessage = "Failed to update primary photo."
            }
        }
    }

    private func deleteDraft() async {
        guard let accountId = accountContext.currentAccountId,
              let protoItemId = liveProtoItem.id else { return }
        do {
            try await protoItemsService.deleteProtoItem(accountId: accountId, protoItemId: protoItemId)
            for photo in photos where !photo.url.isEmpty {
                try? await mediaService.deleteImage(url: photo.url)
            }
            dismiss()
        } catch {
            errorMessage = "Failed to remove the item."
        }
    }

    private func mergeWithExistingItem(_ item: Item) async {
        guard let accountId = accountContext.currentAccountId,
              let protoItemId = liveProtoItem.id,
              let itemId = item.id else { return }
        do {
            let mergedImages = mergeAttachments(existing: item.images ?? [], incoming: photos)
            var fields: [String: Any] = ["images": mergedImages.map(attachmentDict)]
            if item.projectId == liveProtoItem.projectId,
               item.spaceId == nil,
               let spaceId = liveProtoItem.spaceId {
                fields["spaceId"] = spaceId
            }
            if (item.sku ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let draftSku = liveProtoItem.sku?.trimmingCharacters(in: .whitespacesAndNewlines),
               !draftSku.isEmpty {
                fields["sku"] = draftSku
            }
            if let draftNotes = liveProtoItem.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
               !draftNotes.isEmpty {
                let existingNotes = item.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                fields["notes"] = existingNotes.isEmpty ? draftNotes : "\(existingNotes)\n\n\(draftNotes)"
            }
            try await ItemsService().updateItem(
                accountId: accountId,
                itemId: itemId,
                fields: fields
            )
            try await protoItemsService.convertProtoItem(
                accountId: accountId,
                protoItemId: protoItemId,
                convertedItemId: itemId,
                userId: authManager.currentUser?.uid
            )
            dismiss()
        } catch {
            errorMessage = "Failed to match the captured item."
        }
    }

    private func markConverted(itemId: String) async {
        guard let accountId = accountContext.currentAccountId,
              let protoItemId = liveProtoItem.id else { return }
        do {
            try await protoItemsService.convertProtoItem(
                accountId: accountId,
                protoItemId: protoItemId,
                convertedItemId: itemId,
                userId: authManager.currentUser?.uid
            )
            dismiss()
        } catch {
            errorMessage = "The item was created, but assignment did not finish."
        }
    }

    private func attachmentDict(_ ref: AttachmentRef) -> [String: Any] {
        var dict: [String: Any] = [
            "url": ref.url,
            "kind": ref.kind.rawValue,
        ]
        if let thumbnailUrlSm = ref.thumbnailUrlSm { dict["thumbnailUrlSm"] = thumbnailUrlSm }
        if let thumbnailUrlMd = ref.thumbnailUrlMd { dict["thumbnailUrlMd"] = thumbnailUrlMd }
        if let fileName = ref.fileName { dict["fileName"] = fileName }
        if let contentType = ref.contentType { dict["contentType"] = contentType }
        if let isPrimary = ref.isPrimary { dict["isPrimary"] = isPrimary }
        if let isUploading = ref.isUploading { dict["isUploading"] = isUploading }
        return dict
    }

}

struct ItemQuickDraftMergePicker: View {
    let protoItem: ProtoItem
    let items: [Item]
    let filterCatalog: ItemFilterCatalog
    var onMerge: (Item) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Merge with Existing Item")
                    .font(Typography.h2)
                    .foregroundStyle(BrandColors.textPrimary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(BrandColors.textTertiary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.top, Spacing.screenPadding)
            .padding(.bottom, Spacing.md)

            SharedItemsList(
                mode: .picker(
                    scope: nil,
                    eligibilityCheck: nil,
                    onAddSingle: { item in
                        onMerge(item)
                        dismiss()
                    },
                    addedIds: [],
                    onAddSelected: nil,
                    otherSpaceNameForItem: nil
                ),
                emptyMessage: "No items available",
                emptyIcon: "cube.box",
                filterCatalog: filterCatalog,
                pickerItems: items
            )
        }
    }
}

func dedupeItems(_ items: [Item]) -> [Item] {
    var seen = Set<String>()
    return items.filter { item in
        guard let id = item.id else { return false }
        return seen.insert(id).inserted
    }
}

func mergeAttachments(existing: [AttachmentRef], incoming: [AttachmentRef]) -> [AttachmentRef] {
    var seen = Set(existing.map(\.url))
    var merged = existing
    for attachment in incoming where !attachment.url.isEmpty && seen.insert(attachment.url).inserted {
        var copy = attachment
        if !merged.isEmpty {
            copy.isPrimary = false
        }
        merged.append(copy)
    }
    if !merged.isEmpty, !merged.contains(where: { $0.isPrimary == true }) {
        merged[0].isPrimary = true
    }
    return merged
}
