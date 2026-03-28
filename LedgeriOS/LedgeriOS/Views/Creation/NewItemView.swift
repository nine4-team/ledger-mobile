import SwiftUI
import PhotosUI
import FirebaseFirestore

/// Creation context determines Firestore paths and available pickers.
enum ItemCreationContext: Equatable {
    case project(String, spaceId: String?)
    case inventory
}

/// Two-step bottom-sheet form for creating a new item.
struct NewItemView: View {
    @State private var resolvedContext: ItemCreationContext?
    @State private var selectedProject: Project?

    init(context: ItemCreationContext? = nil, initialTransactionId: String? = nil) {
        self._resolvedContext = State(initialValue: context)
        self._selectedTransactionId = State(initialValue: initialTransactionId)
    }

    @Environment(ProjectContext.self) private var projectContext: ProjectContext?
    @Environment(AccountContext.self) private var accountContext
    @Environment(MediaService.self) private var mediaService
    @Environment(MediaUploadQueue.self) private var mediaUploadQueue
    @Environment(\.dismiss) private var dismiss

    // Step
    @State private var currentStep = 1

    // Step 1 fields
    @State private var name = ""
    @State private var sku = ""
    @State private var source = ""
    @State private var notes = ""
    @State private var imageItems: [PhotosPickerItem] = []
    @State private var imageDatas: [Data] = []

    // Step 2 fields
    @State private var selectedTransactionId: String?
    @State private var selectedSpaceId: String?
    @State private var purchasePrice = ""
    @State private var projectPrice = ""
    @State private var marketValue = ""
    @State private var quantity = 1
    @State private var status: ItemStatus = .purchased

    // Scoped transaction subscription
    @State private var scopedTransactions: [Transaction] = []
    @State private var transactionListener: ListenerRegistration?

    // Pickers
    @State private var showDestinationPicker = false
    @State private var showTransactionPicker = false
    @State private var showSpacePicker = false
    @State private var showStatusPicker = false
    @State private var showVendorPicker = false

    // Image source
    @State private var showImageSourceMenu = false
    @State private var imageSourcePendingAction: (() -> Void)?
    @State private var showCamera = false
    @State private var showPhotoPicker = false

    private let itemsService = ItemsService()
    private let transactionsService = TransactionsService()

    private var isValid: Bool {
        resolvedContext != nil &&
        ItemFormValidation.isValidItem(name: name, imageCount: imageDatas.count)
    }

    private var projectId: String? {
        switch resolvedContext {
        case .project(let id, _): return id
        case .inventory, nil: return nil
        }
    }

    private var selectedSpace: Space? {
        projectContext?.spaces.first { $0.id == selectedSpaceId }
    }

    private var selectedTransaction: Transaction? {
        scopedTransactions.first { $0.id == selectedTransactionId }
    }

    private var destinationLabel: String {
        switch resolvedContext {
        case .project:
            let name = selectedProject?.name ?? projectContext?.project?.name ?? ""
            return name.isEmpty ? "Project" : name
        case .inventory:
            return "Business Inventory"
        case nil:
            return "Choose Destination"
        }
    }

    var body: some View {
        Group {
            switch currentStep {
            case 1: step1Essentials
            default: step2Details
            }
        }
        .adaptivePresentation(isPresented: $showDestinationPicker, style: .picker) {
            DestinationPickerSheet { context, project in
                if resolvedContext != context {
                    selectedTransactionId = nil
                    selectedSpaceId = nil
                    scopedTransactions = []
                }
                resolvedContext = context
                selectedProject = project
            }
        }
        .adaptivePresentation(isPresented: $showStatusPicker, style: .quickMenu) {
            StatusPickerModal(currentStatus: status, onSelect: { newStatus in status = newStatus })
        }
        .adaptivePresentation(isPresented: $showSpacePicker, style: .picker) {
            SetSpaceModal(
                spaces: projectContext?.spaces ?? [],
                currentSpaceId: selectedSpaceId,
                onSelect: { space in selectedSpaceId = space?.id }
            )
        }
        .adaptivePresentation(isPresented: $showTransactionPicker, style: .picker) {
            TransactionPickerModal(
                transactions: scopedTransactions,
                selectedId: selectedTransactionId,
                onSelect: { tx in selectedTransactionId = tx.id }
            )
        }
        .adaptivePresentation(isPresented: $showVendorPicker, style: .picker) {
            VendorPickerModal(selectedValue: source, onSelect: { source = $0 })
        }
        .task {
            startTransactionSubscription()
        }
        .onChange(of: resolvedContext) { _, _ in
            startTransactionSubscription()
        }
        .onDisappear {
            transactionListener?.remove()
            transactionListener = nil
        }
        .onAppear {
            if case .project(_, let spaceId) = resolvedContext {
                selectedSpaceId = spaceId
            }
        }
    }

    // MARK: - Step 1: Essentials

    private var step1Essentials: some View {
        MultiStepFormSheet(
            title: "New Item",
            description: "Add a name or at least one image to create an item.",
            currentStep: 1,
            totalSteps: 2,
            primaryAction: FormSheetAction(title: "Next") {
                currentStep = 2
            },
            secondaryAction: FormSheetAction(title: "Cancel") {
                dismiss()
            }
        ) {
            VStack(spacing: Spacing.md) {
                destinationSection
                imagesSection
                FormField(label: "Name", text: $name, placeholder: "Item name")
                FormField(label: "SKU", text: $sku, placeholder: "Barcode or SKU number")
                VendorPickerField(value: $source, showPicker: $showVendorPicker)
                FormField(label: "Notes", text: $notes, placeholder: "Additional notes", axis: .vertical)
            }
        }
    }

    // MARK: - Destination Section

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Destination")
                .font(Typography.label)
                .foregroundStyle(BrandColors.textSecondary)

            Button { showDestinationPicker = true } label: {
                HStack {
                    Text(destinationLabel)
                        .foregroundStyle(resolvedContext == nil ? BrandColors.textSecondary : BrandColors.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(BrandColors.textSecondary)
                }
                .font(Typography.input)
                .padding(.horizontal, Spacing.md)
                .frame(height: 44)
                .contentShape(Rectangle())
                .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                        .stroke(
                            resolvedContext == nil ? BrandColors.destructive : BrandColors.border,
                            lineWidth: Dimensions.borderWidth
                        )
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Step 2: Details

    private var step2Details: some View {
        FormSheet(
            title: "New Item",
            primaryAction: FormSheetAction(title: "Create Item", isDisabled: !isValid) {
                createItem()
            },
            secondaryAction: FormSheetAction(title: "Back") {
                currentStep = 1
            }
        ) {
            VStack(spacing: Spacing.md) {
                Text("Step 2 of 2")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)

                // Transaction picker — available once a destination is chosen
                if resolvedContext != nil {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Transaction")
                            .font(Typography.label)
                            .foregroundStyle(BrandColors.textSecondary)

                        Button { showTransactionPicker = true } label: {
                            pickerButton(label: selectedTransaction.map { transactionLabel($0) } ?? "Link Transaction")
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Space picker — project context only
                if case .project = resolvedContext {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Space")
                            .font(Typography.label)
                            .foregroundStyle(BrandColors.textSecondary)

                        Button { showSpacePicker = true } label: {
                            pickerButton(label: selectedSpace?.name ?? "Select Space")
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Prices
                FormField(text: $purchasePrice, placeholder: "Purchase price")
                    .platformKeyboardType(.decimalPad)
                FormField(text: $projectPrice, placeholder: "Project price")
                    .platformKeyboardType(.decimalPad)
                FormField(text: $marketValue, placeholder: "Market value")
                    .platformKeyboardType(.decimalPad)

                // Quantity
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Quantity")
                        .font(Typography.label)
                        .foregroundStyle(BrandColors.textSecondary)

                    HStack(spacing: 0) {
                        Text("\(quantity)")
                            .font(Typography.input)
                            .foregroundStyle(BrandColors.textPrimary)
                            .padding(.leading, Spacing.sm)

                        Spacer()

                        VStack(spacing: 0) {
                            Button {
                                if quantity < 9999 { quantity += 1 }
                            } label: {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(BrandColors.textPrimary)
                                    .frame(width: 36, height: 22)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button {
                                if quantity > 1 { quantity -= 1 }
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(quantity > 1 ? BrandColors.textPrimary : BrandColors.textDisabled)
                                    .frame(width: 36, height: 22)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(quantity <= 1)
                        }
                    }
                    .frame(height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                            .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
                    )
                }

                // Status
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Status")
                        .font(Typography.label)
                        .foregroundStyle(BrandColors.textSecondary)

                    Button {
                        showStatusPicker = true
                    } label: {
                        pickerButton(label: statusDisplayLabel(status))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Images Section

    private var imagesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Images")
                .font(Typography.label)
                .foregroundStyle(BrandColors.textSecondary)

            if !imageDatas.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: Spacing.sm)], spacing: Spacing.sm) {
                    ForEach(Array(imageDatas.enumerated()), id: \.offset) { index, data in
                        ZStack(alignment: .topTrailing) {
                            platformImage(from: data)
                                .scaledToFill()
                                .frame(width: 70, height: 70)
                                .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))

                            Button {
                                imageDatas.remove(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.white)
                                    .shadow(radius: 2)
                            }
                            .offset(x: 4, y: -4)
                        }
                    }
                }
            }

            Button {
                showImageSourceMenu = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle")
                    Text(imageDatas.isEmpty ? "Add Images" : "Add More Images")
                }
                .font(Typography.input)
                .foregroundStyle(BrandColors.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                        .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
                )
            }
            .buttonStyle(.plain)

            if !imageDatas.isEmpty {
                Text("\(imageDatas.count) \(imageDatas.count == 1 ? "image" : "images")")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)
            }
        }
        .adaptivePresentation(isPresented: $showImageSourceMenu, style: .quickMenu, onDismiss: {
            imageSourcePendingAction?()
            imageSourcePendingAction = nil
        }) {
            imageSourceMenu
        }
        #if canImport(UIKit)
        .fullScreenCover(isPresented: $showCamera) {
            CameraCapture { imageData in
                imageDatas.append(imageData)
            } onDismiss: {
                showCamera = false
            }
        }
        #endif
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $imageItems,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: imageItems) { _, newItems in
            Task {
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        imageDatas.append(data)
                    }
                }
                imageItems = []
            }
        }
    }

    private var imageSourceMenu: some View {
        ActionMenuSheet(
            title: "Add Image",
            items: [
                ActionMenuItem(
                    id: "camera",
                    label: "Camera",
                    icon: "camera.fill",
                    onPress: {
                        showCamera = true
                    }
                ),
                ActionMenuItem(
                    id: "photo-library",
                    label: "Photo Library",
                    icon: "photo.on.rectangle",
                    onPress: {
                        showPhotoPicker = true
                    }
                ),
            ],
            onSelectAction: { action in
                imageSourcePendingAction = action
            }
        )
    }

    // MARK: - Shared Picker Button

    private func pickerButton(label: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(BrandColors.textPrimary)
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(BrandColors.textSecondary)
        }
        .font(Typography.input)
        .padding(.horizontal, Spacing.md)
        .frame(height: 44)
        .contentShape(Rectangle())
        .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
        )
    }

    // MARK: - Transaction Subscription

    private func startTransactionSubscription() {
        guard let accountId = accountContext.currentAccountId,
              let context = resolvedContext else {
            transactionListener?.remove()
            transactionListener = nil
            scopedTransactions = []
            return
        }

        transactionListener?.remove()

        let scope: ListScope
        switch context {
        case .project(let id, _): scope = .project(id)
        case .inventory: scope = .inventory
        }

        transactionListener = transactionsService.subscribeToTransactions(
            accountId: accountId,
            scope: scope
        ) { transactions in
            Task { @MainActor in
                self.scopedTransactions = transactions
            }
        }
    }

    // MARK: - Actions

    private func createItem() {
        guard let accountId = accountContext.currentAccountId else { return }

        var item = Item()
        item.projectId = projectId
        item.spaceId = selectedSpaceId
        item.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.source = source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : source.trimmingCharacters(in: .whitespacesAndNewlines)
        item.sku = sku.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : sku.trimmingCharacters(in: .whitespacesAndNewlines)
        item.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines)
        item.status = status
        item.purchasePriceCents = parseCents(purchasePrice)
        item.projectPriceCents = parseCents(projectPrice)
        item.marketValueCents = parseCents(marketValue)
        item.transactionId = selectedTransactionId
        item.accountId = accountId

        do {
            var itemIds: [String] = []
            for _ in 0..<quantity {
                var copy = item
                copy.id = nil
                let itemId = try itemsService.createItem(accountId: accountId, item: copy)
                itemIds.append(itemId)
            }

            if let transactionId = selectedTransactionId {
                let txPath = "accounts/\(accountId)/transactions/\(transactionId)"
                Task {
                    try? await Firestore.firestore().document(txPath).updateData([
                        "itemIds": FieldValue.arrayUnion(itemIds),
                        "updatedAt": FieldValue.serverTimestamp()
                    ])
                }
            }

            dismiss()

            // Enqueue images for persistent upload — survives app restart
            for itemId in itemIds {
                for (index, data) in imageDatas.enumerated() {
                    let filename = "image_\(index).jpg"
                    let path = mediaService.uploadPath(
                        accountId: accountId, entityType: "items",
                        entityId: itemId, filename: filename
                    )
                    let thumbPaths = ImageThumbnailGenerator.thumbnailPaths(for: path)
                    var metadata = UploadMetadata(
                        accountId: accountId, entityType: "items", entityId: itemId,
                        storagePath: path, updateType: .appendToArray(field: "images", kind: "image", isPrimary: index == 0),
                        fileName: filename
                    )
                    metadata.thumbnailStoragePathSm = thumbPaths.sm
                    metadata.thumbnailStoragePathMd = thumbPaths.md
                    mediaUploadQueue.enqueue(imageData: data, metadata: metadata)
                }
            }
            mediaUploadQueue.processQueue()
        } catch {
            // Offline-first: should not fail
        }
    }

    private func parseCents(_ text: String) -> Int? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard !cleaned.isEmpty, let value = Double(cleaned), value >= 0 else { return nil }
        return Int(value * 100)
    }

    private func statusDisplayLabel(_ status: ItemStatus) -> String {
        status.displayLabel
    }

    private func transactionLabel(_ tx: Transaction) -> String {
        let type = tx.transactionType?.displayLabel ?? "Transaction"
        if let cents = tx.amountCents {
            return "\(type) - \(CurrencyFormatting.formatCentsWithDecimals(cents))"
        }
        return type
    }
}
