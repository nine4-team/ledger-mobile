import SwiftUI
import PhotosUI

struct ItemDraftCaptureSheet: View {
    let projectId: String
    var projectName: String?
    var transactionId: String?
    var transactionName: String?

    @Environment(AccountContext.self) private var accountContext
    @Environment(AuthManager.self) private var authManager
    @Environment(MediaUploadQueue.self) private var mediaUploadQueue
    @Environment(\.dismiss) private var dismiss

    @State private var imageItems: [PhotosPickerItem] = []
    @State private var imageDatas: [Data] = []
    @State private var notes = ""
    @State private var sourceHint: ProtoItemSourceHint = .unknown
    @State private var showImageSourceMenu = false
    @State private var imageSourcePendingAction: (() -> Void)?
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let protoItemsService = ProtoItemsService()

    private var canSave: Bool {
        !imageDatas.isEmpty && !isSaving
    }

    private var contextTitle: String {
        transactionId == nil ? "Project" : "Transaction"
    }

    private var contextLabel: String {
        if transactionId != nil, let transactionName, !transactionName.isEmpty {
            return transactionName
        }
        if let projectName, !projectName.isEmpty {
            return projectName
        }
        return transactionId == nil ? "Current Project" : "Current Transaction"
    }

    var body: some View {
        FormSheet(
            title: "New Item Draft",
            primaryAction: FormSheetAction(
                title: "Save & Next",
                isLoading: isSaving,
                isDisabled: !canSave,
                action: saveAndReset
            ),
            secondaryAction: FormSheetAction(title: "Done") {
                dismiss()
            },
            error: errorMessage
        ) {
            VStack(spacing: Spacing.md) {
                contextSection
                photosSection
                sourceHintSection
                FormField(label: "Notes", text: $notes, placeholder: "Notes", axis: .vertical)
            }
        }
    }

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(contextTitle)
                .font(Typography.label)
                .foregroundStyle(BrandColors.textSecondary)

            HStack {
                Text(contextLabel)
                    .font(Typography.input)
                    .foregroundStyle(BrandColors.textPrimary)
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(BrandColors.primary)
            }
            .padding(.horizontal, Spacing.md)
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
                    Text(imageDatas.isEmpty ? "Add Photos" : "Add More Photos")
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
            title: "Add Photo",
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

    private var sourceHintSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Source")
                .font(Typography.label)
                .foregroundStyle(BrandColors.textSecondary)

            VStack(spacing: Spacing.sm) {
                sourceHintButton(.unknown, label: "Not Sure", icon: "questionmark.circle")
                sourceHintButton(.purchasedByClient, label: "Client Purchase", icon: "person.crop.circle")
                sourceHintButton(.purchasedByBusiness, label: "Business Purchase", icon: "building.2")
                sourceHintButton(.fromInventory, label: "From Inventory", icon: "shippingbox")
            }
        }
    }

    private func sourceHintButton(_ hint: ProtoItemSourceHint, label: String, icon: String) -> some View {
        Button {
            sourceHint = hint
        } label: {
            HStack {
                Image(systemName: sourceHint == hint ? "checkmark.circle.fill" : icon)
                    .foregroundStyle(sourceHint == hint ? BrandColors.primary : BrandColors.textSecondary)
                Text(label)
                    .foregroundStyle(BrandColors.textPrimary)
                Spacer()
            }
            .font(Typography.input)
            .padding(.horizontal, Spacing.md)
            .frame(height: 44)
            .contentShape(Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                    .stroke(sourceHint == hint ? BrandColors.primary : BrandColors.border, lineWidth: Dimensions.borderWidth)
            )
        }
        .buttonStyle(.plain)
    }

    private func saveAndReset() {
        guard let accountId = accountContext.currentAccountId else { return }
        let capturedImageDatas = imageDatas
        guard !capturedImageDatas.isEmpty else { return }

        isSaving = true
        errorMessage = nil

        do {
            let protoItemId = protoItemsService.newProtoItemId(accountId: accountId)
            var protoItem = ProtoItem()
            protoItem.accountId = accountId
            protoItem.projectId = projectId
            protoItem.transactionId = transactionId
            protoItem.captureContext = transactionId == nil ? .project : .transaction
            protoItem.status = .open
            protoItem.sourceHint = sourceHint == .unknown ? nil : sourceHint
            let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            protoItem.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            protoItem.createdBy = authManager.currentUser?.uid
            protoItem.updatedBy = authManager.currentUser?.uid

            try protoItemsService.createProtoItem(accountId: accountId, id: protoItemId, protoItem: protoItem)
            enqueuePhotos(capturedImageDatas, accountId: accountId, protoItemId: protoItemId)

            imageDatas = []
            notes = ""
            sourceHint = .unknown
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
