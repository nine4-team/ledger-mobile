import SwiftUI
import PhotosUI

struct ItemDraftCaptureSheet: View {
    let projectId: String?
    var projectName: String?
    var transactionId: String?
    var transactionName: String?

    @Environment(AccountContext.self) private var accountContext
    @Environment(AuthManager.self) private var authManager
    @Environment(MediaUploadQueue.self) private var mediaUploadQueue
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var notes = ""
    @State private var quantity = 1
    @State private var isFromInventory = false
    @State private var imageItems: [PhotosPickerItem] = []
    @State private var imageDatas: [Data] = []
    @State private var showImageSourceMenu = false
    @State private var imageSourcePendingAction: (() -> Void)?
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let protoItemsService = ProtoItemsService()

    private var quantityBinding: Binding<Int> {
        Binding(
            get: { quantity },
            set: { quantity = min(max($0, 1), 9999) }
        )
    }

    private var canSave: Bool {
        (!imageDatas.isEmpty || !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) && !isSaving
    }

    var body: some View {
        FormSheet(
            title: "New Item Quick Draft",
            primaryAction: FormSheetAction(
                title: "Save & Next",
                isLoading: isSaving,
                isDisabled: !canSave,
                action: { Task { await saveAndReset() } }
            ),
            secondaryAction: FormSheetAction(title: "Done") {
                dismiss()
            },
            error: errorMessage
        ) {
            VStack(spacing: Spacing.md) {
                FormField(label: "Name", text: $name, placeholder: "Optional")
                FormField(label: "Notes", text: $notes, placeholder: "Optional notes", axis: .vertical)
                quantitySection
                if projectId != nil && transactionId == nil {
                    fromInventorySection
                }
                photosSection
            }
        }
    }

    private var fromInventorySection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Source")
                .font(Typography.label)
                .foregroundStyle(BrandColors.textSecondary)
            InlineOptionPicker(selection: $isFromInventory, options: [
                InlineOption(id: false, label: "Project purchase"),
                InlineOption(id: true, label: "From inventory"),
            ])
            Text(isFromInventory
                 ? "This item will need an inventory transaction before it can be converted."
                 : "This item will be linked directly to a transaction in this project.")
                .font(Typography.small)
                .foregroundStyle(BrandColors.textSecondary)
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
    }

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Photos")
                .font(Typography.label)
                .foregroundStyle(BrandColors.textSecondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: Spacing.sm)], spacing: Spacing.sm) {
                ForEach(Array(imageDatas.enumerated()), id: \.offset) { index, data in
                    ZStack(alignment: .topTrailing) {
                        platformImage(from: data)
                            .scaledToFill()
                            .frame(height: 88)
                            .frame(maxWidth: .infinity)
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

                Button {
                    showImageSourceMenu = true
                } label: {
                    RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                        .strokeBorder(style: StrokeStyle(lineWidth: Dimensions.borderWidth, dash: [6]))
                        .foregroundStyle(BrandColors.borderSecondary)
                        .frame(height: 88)
                        .overlay {
                            VStack(spacing: Spacing.xs) {
                                Image(systemName: "plus")
                                    .font(.system(size: 24, weight: .regular))
                                Text(imageDatas.isEmpty ? "Add Photos" : "Add More")
                                    .font(Typography.caption)
                            }
                            .foregroundStyle(BrandColors.textSecondary)
                        }
                }
                .buttonStyle(.plain)
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
            maxSelectionCount: 0,
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
            title: "Add Photos",
            items: [
                ActionMenuItem(
                    id: "camera",
                    label: "Camera",
                    icon: "camera.fill",
                    onPress: { showCamera = true }
                ),
                ActionMenuItem(
                    id: "photo-library",
                    label: "Photo Library",
                    icon: "photo.on.rectangle",
                    onPress: { showPhotoPicker = true }
                ),
            ],
            onSelectAction: { action in
                imageSourcePendingAction = action
            }
        )
    }

    private func saveAndReset() async {
        guard let accountId = accountContext.currentAccountId else { return }
        let capturedImageDatas = imageDatas
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !capturedImageDatas.isEmpty || !trimmedNotes.isEmpty else { return }

        isSaving = true
        errorMessage = nil

        do {
            let extraction = capturedImageDatas.isEmpty
                ? nil
                : await ItemTagExtractionService.extract(from: capturedImageDatas)
            let protoItemId = protoItemsService.newProtoItemId(accountId: accountId)
            var protoItem = ProtoItem()
            protoItem.accountId = accountId
            protoItem.projectId = projectId
            protoItem.transactionId = transactionId
            protoItem.captureContext = transactionId == nil
                ? (projectId == nil ? .inventory : .project)
                : .transaction
            protoItem.status = .open
            protoItem.isFromInventory = isFromInventory
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            protoItem.name = trimmedName.isEmpty ? nil : trimmedName
            protoItem.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            if let extraction,
               case let .populate(sku) = ItemTagSkuMutationPolicy.decide(existingSku: nil, extraction: extraction) {
                protoItem.sku = sku
            }
            protoItem.quantity = quantity
            protoItem.extracted = extraction?.protoExtraction
            protoItem.createdBy = authManager.currentUser?.uid
            protoItem.updatedBy = authManager.currentUser?.uid

            try protoItemsService.createProtoItem(accountId: accountId, id: protoItemId, protoItem: protoItem)
            enqueuePhotos(capturedImageDatas, accountId: accountId, protoItemId: protoItemId)

            name = ""
            notes = ""
            quantity = 1
            isFromInventory = false
            imageDatas = []
            showImageSourceMenu = true
            mediaUploadQueue.processQueue()
            isSaving = false
        } catch {
            isSaving = false
            errorMessage = "Failed to save item draft. Please try again."
        }
    }

    private func enqueuePhotos(_ datas: [Data], accountId: String, protoItemId: String) {
        for (index, data) in datas.enumerated() {
            let filename = "photo_\(index).jpg"
            let metadata = ProtoItemsService.photoUploadMetadata(
                accountId: accountId,
                protoItemId: protoItemId,
                filename: filename,
                isPrimary: index == 0
            )
            mediaUploadQueue.enqueue(imageData: data, metadata: metadata)
        }
    }
}
