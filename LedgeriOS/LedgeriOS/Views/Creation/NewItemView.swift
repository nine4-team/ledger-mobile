import SwiftUI
import PhotosUI

/// Creation context determines Firestore paths and available pickers.
enum ItemCreationContext {
    case project(String, spaceId: String?)
    case inventory
}

/// Two-step bottom-sheet form for creating a new item.
struct NewItemView: View {
    let context: ItemCreationContext

    @Environment(ProjectContext.self) private var projectContext: ProjectContext?
    @Environment(AccountContext.self) private var accountContext
    @Environment(MediaService.self) private var mediaService
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
    @State private var status = "purchased"

    // Pickers
    @State private var showTransactionPicker = false
    @State private var showSpacePicker = false
    @State private var showStatusPicker = false

    // Image source
    @State private var showImageSourceMenu = false
    @State private var imageSourcePendingAction: (() -> Void)?
    @State private var showCamera = false
    @State private var showPhotoPicker = false

    private let itemsService = ItemsService(syncTracker: NoOpSyncTracker())

    private var isValid: Bool {
        ItemFormValidation.isValidItem(name: name, imageCount: imageDatas.count)
    }

    private var projectId: String? {
        switch context {
        case .project(let id, _): return id
        case .inventory: return nil
        }
    }

    private var selectedSpace: Space? {
        projectContext?.spaces.first { $0.id == selectedSpaceId }
    }

    private var selectedTransaction: Transaction? {
        projectContext?.transactions.first { $0.id == selectedTransactionId }
    }

    var body: some View {
        Group {
            switch currentStep {
            case 1: step1Essentials
            default: step2Details
            }
        }
        .sheet(isPresented: $showStatusPicker) {
            StatusPickerModal(currentStatus: status, onSelect: { newStatus in status = newStatus })
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSpacePicker) {
            SetSpaceModal(
                spaces: projectContext?.spaces ?? [],
                currentSpaceId: selectedSpaceId,
                onSelect: { space in selectedSpaceId = space?.id }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showTransactionPicker) {
            TransactionPickerModal(
                transactions: projectContext?.transactions ?? [],
                selectedId: selectedTransactionId,
                onSelect: { tx in selectedTransactionId = tx.id }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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
                imagesSection
                FormField(label: "Name", text: $name, placeholder: "Item name")
                FormField(label: "SKU", text: $sku, placeholder: "Barcode or SKU number")
                VendorPickerField(value: $source)
                FormField(label: "Notes", text: $notes, placeholder: "Additional notes", axis: .vertical)
            }
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

                // Transaction picker (project context only) — before Space
                if projectId != nil {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Transaction")
                            .font(Typography.label)
                            .foregroundStyle(BrandColors.textSecondary)

                        Button { showTransactionPicker = true } label: {
                            pickerButton(label: selectedTransaction.map { transactionLabel($0) } ?? "Link Transaction")
                        }
                    }

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Space")
                            .font(Typography.label)
                            .foregroundStyle(BrandColors.textSecondary)

                        Button { showSpacePicker = true } label: {
                            pickerButton(label: selectedSpace?.name ?? "Select Space")
                        }
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

                    Stepper("\(quantity)", value: $quantity, in: 1...9999)
                        .font(Typography.input)
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
                }
            }
        }
        .onAppear {
            if case .project(_, let spaceId) = context {
                selectedSpaceId = spaceId
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
                .background(BrandColors.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                        .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
                )
            }

            if !imageDatas.isEmpty {
                Text("\(imageDatas.count) \(imageDatas.count == 1 ? "image" : "images")")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)
            }
        }
        .sheet(isPresented: $showImageSourceMenu, onDismiss: {
            imageSourcePendingAction?()
            imageSourcePendingAction = nil
        }) {
            imageSourceMenu
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCapture { imageData in
                imageDatas.append(imageData)
            } onDismiss: {
                showCamera = false
            }
        }
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
        .background(BrandColors.inputBackground)
        .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
        )
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
        item.quantity = quantity > 1 ? quantity : nil
        item.transactionId = selectedTransactionId
        item.accountId = accountId

        do {
            let itemId = try itemsService.createItem(accountId: accountId, item: item)
            dismiss()

            // Background: upload images if selected
            if !imageDatas.isEmpty {
                let datasToUpload = imageDatas
                Task {
                    var imageEntries: [[String: Any]] = []
                    for (index, data) in datasToUpload.enumerated() {
                        let filename = "image_\(index).jpg"
                        let path = mediaService.uploadPath(
                            accountId: accountId, entityType: "items",
                            entityId: itemId, filename: filename
                        )
                        if let url = try? await mediaService.uploadImage(data, path: path) {
                            var entry: [String: Any] = ["url": url, "kind": "image"]
                            if index == 0 { entry["isPrimary"] = true }
                            imageEntries.append(entry)
                        }
                    }
                    if !imageEntries.isEmpty {
                        try? await itemsService.updateItem(
                            accountId: accountId, itemId: itemId,
                            fields: ["images": imageEntries]
                        )
                    }
                }
            }
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

    private func statusDisplayLabel(_ status: String) -> String {
        switch status {
        case "to-purchase": return "To Purchase"
        case "purchased": return "Purchased"
        case "to-return": return "To Return"
        case "returned": return "Returned"
        default: return status.capitalized
        }
    }

    private func transactionLabel(_ tx: Transaction) -> String {
        let type = tx.transactionType?.capitalized ?? "Transaction"
        if let cents = tx.amountCents {
            return "\(type) - \(CurrencyFormatting.formatCentsWithDecimals(cents))"
        }
        return type
    }
}
