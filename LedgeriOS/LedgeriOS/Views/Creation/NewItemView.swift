import SwiftUI
import PhotosUI
import FirebaseFirestore

/// Creation context determines Firestore paths and available pickers.
enum ItemCreationContext: Equatable {
    case project(String, spaceId: String?)
    case inventory
}

private enum ProjectItemTransactionMode {
    case existing
    case createViaInventory
}

/// Single scrolling bottom-sheet form for creating a new item.
struct NewItemView: View {
    @State private var resolvedContext: ItemCreationContext?
    @State private var selectedProject: Project?
    private let initialImageRefs: [AttachmentRef]
    private let initialSkuCandidates: [String]
    private let convertingProtoItemId: String?
    private let initialIsFromInventory: Bool
    private let onCreated: (([String]) -> Void)?

    init(
        context: ItemCreationContext? = nil,
        initialTransactionId: String? = nil,
        initialName: String? = nil,
        initialNotes: String? = nil,
        initialSku: String? = nil,
        initialSkuCandidates: [String] = [],
        initialQuantity: Int? = nil,
        initialImageRefs: [AttachmentRef] = [],
        initialSpaceId: String? = nil,
        convertingProtoItemId: String? = nil,
        initialIsFromInventory: Bool = false,
        onCreated: (([String]) -> Void)? = nil
    ) {
        self._resolvedContext = State(initialValue: context)
        self._selectedTransactionId = State(initialValue: initialTransactionId)
        self._name = State(initialValue: initialName ?? "")
        self._notes = State(initialValue: initialNotes ?? "")
        self._sku = State(initialValue: initialSku ?? "")
        self._quantity = State(initialValue: min(max(initialQuantity ?? 1, 1), 9999))
        self._selectedSpaceId = State(initialValue: initialSpaceId)
        self.initialSkuCandidates = initialSkuCandidates
        self.initialImageRefs = initialImageRefs
        self.convertingProtoItemId = convertingProtoItemId
        self.initialIsFromInventory = initialIsFromInventory
        self.onCreated = onCreated
    }

    @Environment(ProjectContext.self) private var projectContext: ProjectContext?
    @Environment(AccountContext.self) private var accountContext
    @Environment(AuthManager.self) private var authManager
    @Environment(MediaService.self) private var mediaService
    @Environment(MediaUploadQueue.self) private var mediaUploadQueue
    @Environment(\.dismiss) private var dismiss

    // Item details
    @State private var name = ""
    @State private var sku = ""
    @State private var source = ""
    @State private var notes = ""
    @State private var imageItems: [PhotosPickerItem] = []
    @State private var imageDatas: [Data] = []

    @State private var selectedTransactionId: String?
    @State private var projectTransactionMode: ProjectItemTransactionMode = .existing
    @State private var selectedInventorySaleCategoryId: String?
    @State private var selectedSpaceId: String?
    @State private var purchasePrice = ""
    @State private var projectPrice = ""
    @State private var marketValue = ""
    @State private var quantity = 1
    @State private var status: ItemStatus = .purchased

    // Scoped transaction subscription
    @State private var scopedTransactions: [Transaction] = []
    @State private var loadedSelectedTransaction: Transaction?
    @State private var transactionListener: ListenerRegistration?
    @State private var enabledProjectCategoryIds: Set<String> = []
    @State private var projectCategoryListener: ListenerRegistration?

    // Pickers
    @State private var showDestinationPicker = false
    @State private var showTransactionPicker = false
    @State private var showSpacePicker = false
    @State private var showStatusPicker = false
    @State private var showVendorPicker = false
    @State private var showInventorySaleCategoryPicker = false
    @State private var isCreating = false
    @State private var submissionError: String?

    // Image source
    @State private var showImageSourceMenu = false
    @State private var imageSourcePendingAction: (() -> Void)?
    @State private var showCamera = false
    @State private var showPhotoPicker = false

    private let itemsService = ItemsService()
    private let transactionsService = TransactionsService()
    private let projectBudgetCategoriesService = ProjectBudgetCategoriesService()

    private var isValid: Bool {
        !isCreating && unmetRequirements.isEmpty
    }

    private var isItemIdentityMissing: Bool {
        !ItemFormValidation.isValidItem(
            name: name,
            imageCount: imageDatas.count + initialImageRefs.count
        )
    }

    private var isTransactionChoiceMissing: Bool {
        projectId != nil
            && projectTransactionMode == .existing
            && selectedTransaction == nil
    }

    private var isBudgetCategoryMissing: Bool {
        projectId != nil
            && selectedInventorySaleCategory == nil
            && (projectTransactionMode == .createViaInventory || selectedTransactionIsInventoryAcquisition)
    }

    private var budgetCategoryRequirementMessage: String {
        enabledPurchaseCategories.isEmpty
            ? "Enable an itemized budget category for this project."
            : "Choose a budget category."
    }

    private var isPriceMissing: Bool {
        return (ItemPricePolicy.normalizedProjectPriceCents(
            purchasePriceCents: parseCents(purchasePrice),
            projectPriceCents: parseCents(projectPrice)
        ) ?? 0) <= 0
    }

    private var unmetRequirements: [String] {
        var requirements: [String] = []

        if resolvedContext == nil {
            requirements.append("choose a destination")
        }
        if !ItemFormValidation.isValidItem(
            name: name,
            imageCount: imageDatas.count + initialImageRefs.count
        ) {
            requirements.append("add a name or at least one image")
        }
        if isPriceMissing {
            requirements.append("enter a purchase or project price")
        }

        guard let projectId else { return requirements }

        switch projectTransactionMode {
        case .existing:
            guard let selectedTransaction else {
                requirements.append("link a transaction or choose Create via Inventory")
                return requirements
            }

            if selectedTransaction.projectId != nil,
               selectedTransaction.projectId != projectId {
                requirements.append("choose a transaction for this project")
            } else if initialIsFromInventory,
                      selectedTransaction.projectId != nil {
                requirements.append("select the business inventory purchase that acquired this item")
            } else if selectedTransaction.projectId == nil {
                if convertingProtoItemId == nil {
                    requirements.append("choose a transaction for this project")
                }
                if selectedTransaction.transactionType != .purchase {
                    requirements.append("select an inventory purchase transaction")
                }
                if selectedInventorySaleCategory == nil {
                    requirements.append(
                        enabledPurchaseCategories.isEmpty
                            ? "enable an itemized budget category for this project"
                            : "choose a budget category"
                    )
                }

                if let intendedProjectId = selectedTransaction.intendedProjectId,
                   intendedProjectId != projectId {
                    requirements.append("select an acquisition intended for this project")
                }
            }

        case .createViaInventory:
            if convertingProtoItemId != nil,
               initialIsFromInventory {
                requirements.append("select the business inventory purchase that acquired this item")
            }
            if selectedInventorySaleCategory == nil {
                requirements.append(
                    enabledPurchaseCategories.isEmpty
                        ? "enable an itemized budget category for this project"
                        : "choose a budget category"
                )
            }
        }

        return requirements
    }

    private var unmetRequirementsMessage: String? {
        let requirements = unmetRequirements
        guard !requirements.isEmpty else { return nil }
        return "Still needed: \(requirements.joined(separator: "; "))."
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
            ?? (loadedSelectedTransaction?.id == selectedTransactionId ? loadedSelectedTransaction : nil)
    }

    private var selectedTransactionIsInventoryAcquisition: Bool {
        guard projectId != nil, let selectedTransaction else { return false }
        return selectedTransaction.projectId == nil
    }

    private var transactionPickerTransactions: [Transaction] {
        if initialIsFromInventory {
            return scopedTransactions.filter {
                $0.projectId == nil
                    && $0.transactionType == .purchase
                    && ($0.intendedProjectId == nil || $0.intendedProjectId == projectId)
            }
        }
        return scopedTransactions.filter { $0.projectId == projectId }
    }

    private var enabledPurchaseCategories: [BudgetCategory] {
        let contextIds = Set(projectContext?.projectBudgetCategories.compactMap(\.id) ?? [])
        let enabledIds = enabledProjectCategoryIds.isEmpty ? contextIds : enabledProjectCategoryIds
        return accountContext.allBudgetCategories
            .filter { category in
                guard let id = category.id else { return false }
                return enabledIds.contains(id)
                    && category.isArchived != true
                    && !category.isSystemCategory
                    && category.isItemsCategory
            }
            .sorted { ($0.order ?? 999) < ($1.order ?? 999) }
    }

    private var selectedInventorySaleCategory: BudgetCategory? {
        enabledPurchaseCategories.first { $0.id == selectedInventorySaleCategoryId }
    }

    private var inventorySaleCategoryLabel: String {
        return selectedInventorySaleCategory?.name ?? "Choose Category"
    }

    private var quantityBinding: Binding<Int> {
        Binding(
            get: { quantity },
            set: { quantity = min(max($0, 1), 9999) }
        )
    }

    private var skuCandidates: [String] {
        var seen = Set<String>()
        return initialSkuCandidates.compactMap { candidate in
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
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
        itemForm
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
                transactions: transactionPickerTransactions,
                selectedId: selectedTransactionId,
                onSelect: { tx in
                    projectTransactionMode = .existing
                    selectedTransactionId = tx.id
                    if tx.projectId == nil, let intendedCategoryId = tx.intendedBudgetCategoryId {
                        selectedInventorySaleCategoryId = intendedCategoryId
                    }
                }
            )
        }
        .adaptivePresentation(isPresented: $showInventorySaleCategoryPicker, style: .picker) {
            CategoryPickerList(
                categories: enabledPurchaseCategories,
                selectedId: selectedInventorySaleCategoryId,
                onSelect: { category in
                    selectedInventorySaleCategoryId = category?.id
                }
            )
        }
        .adaptivePresentation(isPresented: $showVendorPicker, style: .picker) {
            VendorPickerModal(selectedValue: source, onSelect: { source = $0 })
        }
        .task {
            startTransactionSubscription()
            startProjectCategorySubscription()
            await loadSelectedTransactionIfNeeded()
        }
        .task(id: selectedTransactionId) {
            await loadSelectedTransactionIfNeeded()
        }
        .onChange(of: resolvedContext) { _, _ in
            startTransactionSubscription()
            startProjectCategorySubscription()
        }
        .onDisappear {
            transactionListener?.remove()
            transactionListener = nil
            projectCategoryListener?.remove()
            projectCategoryListener = nil
        }
        .onAppear {
            if selectedSpaceId == nil,
               case .project(_, let spaceId) = resolvedContext {
                selectedSpaceId = spaceId
            }
        }
    }

    private var skuSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            FormField(label: "SKU", text: $sku, placeholder: "Barcode or SKU number")
            if !skuCandidates.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.xs) {
                        ForEach(skuCandidates, id: \.self) { candidate in
                            Button {
                                sku = candidate
                            } label: {
                                Text(candidate)
                                    .font(Typography.caption)
                                    .foregroundStyle(candidate == sku ? BrandColors.primary : BrandColors.textSecondary)
                                    .padding(.horizontal, Spacing.sm)
                                    .padding(.vertical, Spacing.xs)
                                    .background(
                                        RoundedRectangle(cornerRadius: Dimensions.buttonRadius)
                                            .fill(candidate == sku ? BrandColors.primary.opacity(0.12) : BrandColors.surfaceTertiary)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Dimensions.buttonRadius)
                                            .stroke(candidate == sku ? BrandColors.primary.opacity(0.35) : BrandColors.borderSecondary, lineWidth: Dimensions.borderWidth)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Destination Section

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            fieldLabel("Destination", isMissing: resolvedContext == nil)

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

            if resolvedContext == nil {
                requirementMessage("Choose a destination.")
            }
        }
    }

    // MARK: - Item Form

    private var itemForm: some View {
        FormSheet(
            title: "New Item",
            description: "Add a name or at least one image, plus a price, to create an item.",
            primaryAction: FormSheetAction(
                title: "Create Item",
                isLoading: isCreating,
                isDisabled: !isValid
            ) {
                createItem()
            },
            actionHint: submissionError == nil && !isCreating ? unmetRequirementsMessage : nil,
            error: submissionError
        ) {
            VStack(spacing: Spacing.md) {
                destinationSection
                imagesSection
                FormField(
                    label: "Name",
                    text: $name,
                    placeholder: "Item name",
                    errorText: isItemIdentityMissing ? "Add a name or at least one image." : nil
                )
                skuSection
                VendorPickerField(value: $source, showPicker: $showVendorPicker)
                FormField(label: "Notes", text: $notes, placeholder: "Additional notes", axis: .vertical)

                // Transaction picker — available once a destination is chosen
                if resolvedContext != nil {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        fieldLabel("Transaction", isMissing: isTransactionChoiceMissing)

                        if projectId != nil {
                            Text(convertingProtoItemId != nil && initialIsFromInventory
                                ? "Select the business inventory purchase that acquired this item. Ledger will create the project Purchase and sale lineage together."
                                : "Choose how this item gets attached to the project: link it to an existing transaction, or create it through inventory so Ledger creates an inventory sale transaction automatically.")
                                .font(Typography.caption)
                                .foregroundStyle(BrandColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if selectedTransactionIsInventoryAcquisition {
                            Text("This inventory acquisition will be converted through a new Purchase in this project.")
                                .font(Typography.caption)
                                .foregroundStyle(BrandColors.textSecondary)
                            Button { showInventorySaleCategoryPicker = true } label: {
                                pickerButton(
                                    label: "Category: \(inventorySaleCategoryLabel)",
                                    showsError: isBudgetCategoryMissing
                                )
                            }
                            .buttonStyle(.plain)

                            if isBudgetCategoryMissing {
                                requirementMessage(budgetCategoryRequirementMessage)
                            }
                        } else if initialIsFromInventory,
                                  selectedTransaction?.projectId != nil {
                            Text("This draft is marked From Inventory. Select its inventory acquisition transaction or remove the marker before converting.")
                                .font(Typography.caption)
                                .foregroundStyle(BrandColors.destructive)
                        }

                        Button { showTransactionPicker = true } label: {
                            pickerButton(
                                label: selectedTransaction.map { transactionLabel($0) } ?? "Link Transaction",
                                isSelected: projectTransactionMode == .existing && selectedTransactionId != nil
                            )
                        }
                        .buttonStyle(.plain)

                        if projectId != nil,
                           !(convertingProtoItemId != nil && initialIsFromInventory) {
                            Button {
                                projectTransactionMode = .createViaInventory
                                selectedTransactionId = nil
                                if selectedInventorySaleCategoryId == nil {
                                    selectedInventorySaleCategoryId = enabledPurchaseCategories.first?.id
                                }
                            } label: {
                                pickerButton(
                                    label: "Create via Inventory",
                                    isSelected: projectTransactionMode == .createViaInventory
                                )
                            }
                            .buttonStyle(.plain)

                            if projectTransactionMode == .createViaInventory {
                                Button { showInventorySaleCategoryPicker = true } label: {
                                    pickerButton(
                                        label: "Budget category: \(inventorySaleCategoryLabel)",
                                        font: Typography.caption,
                                        showsError: isBudgetCategoryMissing
                                    )
                                }
                                .buttonStyle(.plain)

                                if isBudgetCategoryMissing {
                                    requirementMessage(budgetCategoryRequirementMessage)
                                }
                            }
                        }

                        if isTransactionChoiceMissing {
                            requirementMessage("Link a transaction or choose Create via Inventory.")
                        }
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
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    fieldLabel("Price", isMissing: isPriceMissing)

                    FormField(
                        text: $purchasePrice,
                        placeholder: "Purchase price",
                        errorText: isPriceMissing ? "Enter a purchase or project price." : nil
                    )
                    .platformKeyboardType(.decimalPad)

                    FormField(text: $projectPrice, placeholder: "Project price")
                        .platformKeyboardType(.decimalPad)

                    FormField(text: $marketValue, placeholder: "Market value")
                        .platformKeyboardType(.decimalPad)
                }

                // Quantity
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
                    ForEach(Array(initialImageRefs.enumerated()), id: \.offset) { _, attachment in
                        FirebaseImage(url: attachment.url, thumbnailUrl: attachment.thumbnailUrlSm, contentMode: .fill) {
                            ProgressView()
                        }
                        .frame(width: 70, height: 70)
                        .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
                    }
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
            } else if !initialImageRefs.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: Spacing.sm)], spacing: Spacing.sm) {
                    ForEach(Array(initialImageRefs.enumerated()), id: \.offset) { _, attachment in
                        FirebaseImage(url: attachment.url, thumbnailUrl: attachment.thumbnailUrlSm, contentMode: .fill) {
                            ProgressView()
                        }
                        .frame(width: 70, height: 70)
                        .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
                    }
                }
            }

            Button {
                showImageSourceMenu = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle")
                    Text(imageDatas.isEmpty && initialImageRefs.isEmpty ? "Add Images" : "Add More Images")
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

            if !imageDatas.isEmpty || !initialImageRefs.isEmpty {
                let imageCount = imageDatas.count + initialImageRefs.count
                Text("\(imageCount) \(imageCount == 1 ? "image" : "images")")
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

    private func pickerButton(
        label: String,
        detail: String? = nil,
        isSelected: Bool = false,
        font: Font = Typography.input,
        showsError: Bool = false
    ) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .foregroundStyle(BrandColors.textPrimary)
                if let detail {
                    Text(detail)
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }
            Spacer()
            Image(systemName: isSelected ? "checkmark" : "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? BrandColors.primary : BrandColors.textSecondary)
        }
        .font(font)
        .padding(.horizontal, Spacing.md)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                .stroke(
                    isSelected
                        ? BrandColors.primary
                        : (showsError ? StatusColors.missedText : BrandColors.border),
                    lineWidth: Dimensions.borderWidth
                )
        )
    }

    private func fieldLabel(_ title: String, isMissing: Bool) -> some View {
        HStack(spacing: Spacing.sm) {
            Text(title)
            if isMissing {
                Text("Required")
                    .font(Typography.caption)
                    .foregroundStyle(StatusColors.missedText)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 2)
                    .background(StatusColors.missedBackground, in: Capsule())
            }
        }
        .font(Typography.label)
        .foregroundStyle(BrandColors.textSecondary)
    }

    private func requirementMessage(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(Typography.caption)
            .foregroundStyle(StatusColors.missedText)
            .fixedSize(horizontal: false, vertical: true)
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
        case .project(let id, _):
            scope = initialIsFromInventory ? .all : .project(id)
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

    private func startProjectCategorySubscription() {
        projectCategoryListener?.remove()
        projectCategoryListener = nil

        guard let accountId = accountContext.currentAccountId,
              let projectId else {
            enabledProjectCategoryIds = []
            return
        }

        enabledProjectCategoryIds = Set(projectContext?.projectBudgetCategories.compactMap(\.id) ?? [])
        projectCategoryListener = projectBudgetCategoriesService.subscribeToProjectBudgetCategories(
            accountId: accountId,
            projectId: projectId
        ) { categories in
            Task { @MainActor in
                self.enabledProjectCategoryIds = Set(categories.compactMap(\.id))
            }
        }
    }

    @MainActor
    private func loadSelectedTransactionIfNeeded() async {
        guard let accountId = accountContext.currentAccountId,
              let transactionId = selectedTransactionId else {
            loadedSelectedTransaction = nil
            return
        }
        do {
            loadedSelectedTransaction = try await transactionsService.getTransaction(
                accountId: accountId,
                transactionId: transactionId
            )
            if let tx = loadedSelectedTransaction,
               tx.projectId == nil,
               selectedInventorySaleCategoryId == nil {
                selectedInventorySaleCategoryId = tx.intendedBudgetCategoryId
            }
        } catch {
            loadedSelectedTransaction = nil
            submissionError = "Couldn't load the linked transaction."
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
        // On day one the immediate source IS the original vendor.
        item.currentSource = item.source
        item.sku = sku.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : sku.trimmingCharacters(in: .whitespacesAndNewlines)
        item.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines)
        item.status = status
        item.purchasePriceCents = parseCents(purchasePrice)
        item.projectPriceCents = parseCents(projectPrice)
        item.marketValueCents = parseCents(marketValue)
        item.transactionId = selectedTransactionId
        item.images = initialImageRefs.isEmpty ? nil : initialImageRefs
        if projectId != nil, projectTransactionMode == .existing {
            item.budgetCategoryId = selectedTransaction?.budgetCategoryId
        }
        item.accountId = accountId
        item = ItemPricePolicy.normalizedForPersistence(item)

        if case .project(let destinationProjectId, _) = resolvedContext,
           projectTransactionMode == .createViaInventory {
            createProjectItemViaInventory(
                accountId: accountId,
                destinationProjectId: destinationProjectId,
                item: item
            )
            return
        }


        if let acquisition = selectedTransaction,
           acquisition.projectId == nil,
           let destinationProjectId = projectId,
           let protoItemId = convertingProtoItemId {
            createProjectDraftFromInventory(
                accountId: accountId,
                destinationProjectId: destinationProjectId,
                protoItemId: protoItemId,
                acquisition: acquisition,
                item: item
            )
            return
        }

        let copies = (0..<quantity).map { _ -> Item in
            var copy = item
            copy.id = nil
            return copy
        }

        if let transactionId = selectedTransactionId {
            isCreating = true
            submissionError = nil
            Task {
                do {
                    // Inventory items cannot carry a project budget category. Older
                    // acquisitions may still expose one as accounting metadata, so
                    // do not pass it into item persistence for inventory scope.
                    let linkedCategoryId = projectId == nil
                        ? nil
                        : selectedTransaction?.budgetCategoryId
                    let createdItems = try itemsService.createItemsForTransaction(
                        accountId: accountId,
                        transactionId: transactionId,
                        budgetCategoryId: linkedCategoryId,
                        items: copies,
                        onCommitError: { _, error in
                            print("🔴 createItem linked batch failed: \(error)")
                        }
                    )
                    let itemIds = createdItems.compactMap(\.id)
                    await MainActor.run {
                        onCreated?(itemIds)
                        dismiss()
                        enqueueImages(for: itemIds, accountId: accountId)
                    }
                } catch {
                    await MainActor.run {
                        isCreating = false
                        submissionError = error.localizedDescription
                    }
                }
            }
            return
        }

        do {
            isCreating = true
            var itemIds: [String] = []
            for copy in copies {
                let itemId = try itemsService.createItem(accountId: accountId, item: copy)
                itemIds.append(itemId)
            }

            onCreated?(itemIds)
            dismiss()

            enqueueImages(for: itemIds, accountId: accountId)
        } catch {
            // Offline-first: should not fail
            isCreating = false
            submissionError = "Couldn't create the item."
        }
    }

    /// Converts a project quick draft linked to an inventory acquisition in one
    /// Firestore batch. The item never exists in a stranded intermediate state:
    /// acquisition lineage, project Purchase, final item scope, and converted
    /// draft status commit together.
    private func createProjectDraftFromInventory(
        accountId: String,
        destinationProjectId: String,
        protoItemId: String,
        acquisition: Transaction,
        item: Item
    ) {
        let projectPriceCents = InventoryOperationsService.projectPriceForMovement(item)
        guard let acquisitionId = acquisition.id,
              let categoryId = selectedInventorySaleCategoryId,
              projectPriceCents > 0 else {
            submissionError = "Choose a project category and enter a project or purchase price."
            return
        }
        if let intendedProjectId = acquisition.intendedProjectId,
           intendedProjectId != destinationProjectId {
            submissionError = "This acquisition is intended for a different project."
            return
        }

        isCreating = true
        submissionError = nil
        Task {
            do {
                let db = Firestore.firestore()
                let projectCategoryRef = db.document(
                    "accounts/\(accountId)/projects/\(destinationProjectId)/budgetCategories/\(categoryId)"
                )
                guard try await projectCategoryRef.getDocument().exists else {
                    await MainActor.run {
                        isCreating = false
                        submissionError = "That category is no longer enabled for this project."
                    }
                    return
                }

                let batch = db.batch()
                let txRef = db.collection("accounts/\(accountId)/transactions").document()
                let itemRefs = (0..<quantity).map { _ in
                    db.collection("accounts/\(accountId)/items").document()
                }
                let itemIds = itemRefs.map(\.documentID)
                let inventoryLabel = InventoryOperationsService.inventoryLabel(for: accountContext.account?.name)
                let rate = item.taxRatePct ?? acquisition.taxRatePct ?? 0
                let subtotalCents = projectPriceCents * itemIds.count
                let amountCents = rate > 0
                    ? Int((Double(subtotalCents) * (1 + rate / 100)).rounded())
                    : subtotalCents

                batch.setData([
                    "type": TransactionType.purchase.rawValue,
                    "source": inventoryLabel,
                    "projectId": destinationProjectId,
                    "budgetCategoryId": categoryId,
                    "amountCents": amountCents,
                    "subtotalCents": subtotalCents,
                    "itemIds": itemIds,
                    "isComplete": true,
                    "createdAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp(),
                ], forDocument: txRef)

                for itemRef in itemRefs {
                    var copy = item
                    copy.id = itemRef.documentID
                    copy.accountId = accountId
                    copy.projectId = destinationProjectId
                    copy.budgetCategoryId = categoryId
                    copy.transactionId = txRef.documentID
                    copy.currentSource = inventoryLabel
                    copy.source = copy.source ?? acquisition.source
                    copy.taxRatePct = rate
                    copy.projectPriceCents = projectPriceCents

                    var fields = try Firestore.Encoder().encode(copy)
                    fields["accountId"] = accountId
                    fields["projectId"] = destinationProjectId
                    fields["budgetCategoryId"] = categoryId
                    fields["transactionId"] = txRef.documentID
                    fields["currentSource"] = inventoryLabel
                    fields["updatedAt"] = FieldValue.serverTimestamp()
                    batch.setData(fields, forDocument: itemRef)

                    batch.setData([
                        "accountId": accountId,
                        "itemId": itemRef.documentID,
                        "fromTransactionId": acquisitionId,
                        "toTransactionId": txRef.documentID,
                        "fromProjectId": NSNull(),
                        "toProjectId": destinationProjectId,
                        "movementKind": "sold",
                        "source": "app",
                        "createdAt": FieldValue.serverTimestamp(),
                    ], forDocument: db.collection("accounts/\(accountId)/lineageEdges").document())
                }

                batch.updateData([
                    "itemIds": FieldValue.arrayRemove(itemIds),
                    "inventoryIntentResolvedAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp(),
                ], forDocument: db.document("accounts/\(accountId)/transactions/\(acquisitionId)"))

                var draftFields: [String: Any] = [
                    "status": ProtoItemStatus.converted.rawValue,
                    "convertedItemId": itemIds[0],
                    "convertedAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp(),
                ]
                if let userId = authManager.currentUser?.uid {
                    draftFields["convertedBy"] = userId
                    draftFields["updatedBy"] = userId
                }
                batch.updateData(
                    draftFields,
                    forDocument: db.document("accounts/\(accountId)/protoItems/\(protoItemId)")
                )

                try await batch.commit()
                await MainActor.run {
                    onCreated?(itemIds)
                    dismiss()
                    enqueueImages(for: itemIds, accountId: accountId)
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    submissionError = "Couldn't convert the draft from inventory. No records were changed."
                }
            }
        }
    }

    private func createProjectItemViaInventory(accountId: String, destinationProjectId: String, item: Item) {
        guard let categoryId = selectedInventorySaleCategoryId else { return }
        isCreating = true

        Task {
            do {
                let db = Firestore.firestore()
                let batch = db.batch()
                let txRef = db.collection("accounts/\(accountId)/transactions").document()
                let purchaseId = txRef.documentID
                let itemRefs = (0..<quantity).map { _ in
                    db.collection("accounts/\(accountId)/items").document()
                }
                let itemIds = itemRefs.map(\.documentID)
                let inventoryLabel = InventoryOperationsService.inventoryLabel(for: accountContext.account?.name)
                let resolvedProjectPrice = InventoryOperationsService.projectPriceForMovement(item)
                let amountCents = itemIds.reduce(0) { total, _ in total + resolvedProjectPrice }
                let today = todayDateString()

                batch.setData([
                    "type": "Purchase",
                    "source": inventoryLabel,
                    "projectId": destinationProjectId,
                    "budgetCategoryId": categoryId,
                    "amountCents": amountCents,
                    "subtotalCents": amountCents,
                    "itemIds": itemIds,
                    "isComplete": true,
                    "transactionDate": today,
                    "createdAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp(),
                ], forDocument: txRef)

                for itemRef in itemRefs {
                    var copy = item
                    copy.id = itemRef.documentID
                    copy.projectId = destinationProjectId
                    copy.budgetCategoryId = categoryId
                    copy.transactionId = purchaseId
                    copy.currentSource = inventoryLabel
                    copy.accountId = accountId
                    copy.projectPriceCents = resolvedProjectPrice > 0 ? resolvedProjectPrice : nil

                    var itemFields = try Firestore.Encoder().encode(copy)
                    itemFields["accountId"] = accountId
                    itemFields["projectId"] = destinationProjectId
                    itemFields["budgetCategoryId"] = categoryId
                    itemFields["transactionId"] = purchaseId
                    itemFields["currentSource"] = inventoryLabel
                    itemFields["updatedAt"] = FieldValue.serverTimestamp()
                    batch.setData(itemFields, forDocument: itemRef)

                    let edgeRef = db.collection("accounts/\(accountId)/lineageEdges").document()
                    batch.setData([
                        "accountId": accountId,
                        "itemId": itemRef.documentID,
                        "toProjectId": destinationProjectId,
                        "toTransactionId": purchaseId,
                        "movementKind": "sold",
                        "source": "app",
                        "createdAt": FieldValue.serverTimestamp(),
                    ], forDocument: edgeRef)
                }

                let categoryRef = db.document("accounts/\(accountId)/projects/\(destinationProjectId)/budgetCategories/\(categoryId)")
                batch.setData(["updatedAt": FieldValue.serverTimestamp()], forDocument: categoryRef, merge: true)

                try await batch.commit()
                onCreated?(itemIds)
                dismiss()
                enqueueImages(for: itemIds, accountId: accountId)
            } catch {
                isCreating = false
            }
        }
    }

    private func enqueueImages(for itemIds: [String], accountId: String) {
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
    }

    private func parseCents(_ text: String) -> Int? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard !cleaned.isEmpty, let value = Double(cleaned), value >= 0 else { return nil }
        return Int(round(value * 100))
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

    private func todayDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }
}
