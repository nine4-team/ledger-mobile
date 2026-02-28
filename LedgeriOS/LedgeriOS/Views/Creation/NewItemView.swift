import SwiftUI
import PhotosUI

/// Creation context determines Firestore paths and available pickers.
enum ItemCreationContext {
    case project(String, spaceId: String?)
    case inventory
}

/// Bottom-sheet form for creating a new item.
struct NewItemView: View {
    let context: ItemCreationContext

    @Environment(ProjectContext.self) private var projectContext
    @Environment(AccountContext.self) private var accountContext
    @Environment(MediaService.self) private var mediaService
    @Environment(\.dismiss) private var dismiss

    // Fields
    @State private var name = ""
    @State private var source = ""
    @State private var sku = ""
    @State private var status = "to-purchase"
    @State private var purchasePrice = ""
    @State private var projectPrice = ""
    @State private var marketValue = ""
    @State private var quantity = 1
    @State private var selectedSpaceId: String?
    @State private var selectedTransactionId: String?
    @State private var imageItem: PhotosPickerItem?
    @State private var imageData: Data?

    // Pickers
    @State private var showSpacePicker = false
    @State private var showTransactionPicker = false
    @State private var showStatusPicker = false

    private let itemsService = ItemsService(syncTracker: NoOpSyncTracker())

    private var isValid: Bool {
        ItemFormValidation.isValidItem(name: name)
    }

    private var projectId: String? {
        switch context {
        case .project(let id, _): return id
        case .inventory: return nil
        }
    }

    private var selectedSpace: Space? {
        projectContext.spaces.first { $0.id == selectedSpaceId }
    }

    private var selectedTransaction: Transaction? {
        projectContext.transactions.first { $0.id == selectedTransactionId }
    }

    var body: some View {
        FormSheet(
            title: "New Item",
            primaryAction: FormSheetAction(title: "Create Item", isDisabled: !isValid) {
                createItem()
            },
            secondaryAction: FormSheetAction(title: "Cancel") {
                dismiss()
            }
        ) {
            VStack(spacing: Spacing.md) {
                FormField(label: "Name *", text: $name, placeholder: "Item name")
                FormField(label: "Source", text: $source, placeholder: "e.g. HomeGoods, Ross")
                FormField(label: "SKU", text: $sku, placeholder: "Barcode or SKU number")

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

                // Prices
                FormField(label: "Purchase Price", text: $purchasePrice, placeholder: "$0.00")
                    .keyboardType(.decimalPad)
                FormField(label: "Project Price", text: $projectPrice, placeholder: "$0.00")
                    .keyboardType(.decimalPad)
                FormField(label: "Market Value", text: $marketValue, placeholder: "$0.00")
                    .keyboardType(.decimalPad)

                // Quantity
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Quantity")
                        .font(Typography.label)
                        .foregroundStyle(BrandColors.textSecondary)

                    Stepper("\(quantity)", value: $quantity, in: 1...9999)
                        .font(Typography.input)
                }

                // Space picker (project context only)
                if projectId != nil {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Space")
                            .font(Typography.label)
                            .foregroundStyle(BrandColors.textSecondary)

                        Button { showSpacePicker = true } label: {
                            pickerButton(label: selectedSpace?.name ?? "Select Space")
                        }
                    }

                    // Transaction picker
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Transaction")
                            .font(Typography.label)
                            .foregroundStyle(BrandColors.textSecondary)

                        Button { showTransactionPicker = true } label: {
                            pickerButton(label: selectedTransaction.map { transactionLabel($0) } ?? "Link Transaction")
                        }
                    }
                }

                // Image
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Image")
                        .font(Typography.label)
                        .foregroundStyle(BrandColors.textSecondary)

                    PhotosPicker(selection: $imageItem, matching: .images) {
                        if let imageData, let uiImage = UIImage(data: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
                        } else {
                            HStack {
                                Image(systemName: "photo")
                                Text("Select Image")
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
                    }
                }
                .onChange(of: imageItem) { _, newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self) {
                            imageData = data
                        }
                    }
                }
            }
        }
        .onAppear {
            // Pre-select space if provided
            if case .project(_, let spaceId) = context {
                selectedSpaceId = spaceId
            }
        }
        .sheet(isPresented: $showStatusPicker) {
            StatusPickerModal(currentStatus: status, onSelect: { newStatus in status = newStatus })
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSpacePicker) {
            SetSpaceModal(
                spaces: projectContext.spaces,
                currentSpaceId: selectedSpaceId,
                onSelect: { space in selectedSpaceId = space?.id }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showTransactionPicker) {
            TransactionPickerModal(
                transactions: projectContext.transactions,
                selectedId: selectedTransactionId,
                onSelect: { tx in selectedTransactionId = tx.id }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
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

            // Background: upload image if selected
            if let imageData {
                Task {
                    let path = mediaService.uploadPath(
                        accountId: accountId, entityType: "items",
                        entityId: itemId, filename: "image.jpg"
                    )
                    if let url = try? await mediaService.uploadImage(imageData, path: path) {
                        let imageEntry: [String: Any] = ["url": url, "kind": "image"]
                        try? await itemsService.updateItem(
                            accountId: accountId, itemId: itemId,
                            fields: ["images": [imageEntry]]
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
