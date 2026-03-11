import SwiftUI
import PhotosUI

/// 3-step bottom sheet for editing an existing project.
/// Step 1: Basic info → Step 2: Category selection → Step 3: Budget amounts.
struct EditProjectModal: View {
    let project: Project
    let existingBudgetCategories: [ProjectBudgetCategory]

    @Environment(AccountContext.self) private var accountContext
    @Environment(AuthManager.self) private var authManager
    @Environment(MediaService.self) private var mediaService
    @Environment(MediaUploadQueue.self) private var mediaUploadQueue
    @Environment(\.dismiss) private var dismiss

    // Step management
    @State private var currentStep = 1

    // Step 1 — basic info
    @State private var name: String
    @State private var clientName: String
    @State private var descriptionText: String
    @State private var heroImageItem: PhotosPickerItem?
    @State private var heroImageData: Data?
    @State private var existingImageUrl: String?

    // Step 2 — category selection
    @State private var selectedCategoryIds: Set<String>

    // Step 3 — budget amounts
    @State private var budgetAllocations: [String: String]

    // On-the-fly category creation
    @State private var showCategoryForm = false

    private let projectService = ProjectService()
    private let budgetCategoriesService = BudgetCategoriesService()
    private let projectBudgetCategoriesService = ProjectBudgetCategoriesService()

    // Snapshots for diffing on save
    private let originalCategoryIds: Set<String>
    private let originalBudgetCents: [String: Int]

    init(project: Project, existingBudgetCategories: [ProjectBudgetCategory]) {
        self.project = project
        self.existingBudgetCategories = existingBudgetCategories

        // Step 1 pre-population
        _name = State(initialValue: project.name)
        _clientName = State(initialValue: project.clientName)
        _descriptionText = State(initialValue: project.description ?? "")
        _existingImageUrl = State(initialValue: project.mainImageUrl)

        // Step 2 pre-population
        let existingIds = Set(existingBudgetCategories.compactMap(\.id))
        _selectedCategoryIds = State(initialValue: existingIds)

        // Step 3 pre-population
        var allocations: [String: String] = [:]
        var originalCents: [String: Int] = [:]
        for pbc in existingBudgetCategories {
            guard let catId = pbc.id else { continue }
            let cents = pbc.budgetCents ?? 0
            originalCents[catId] = cents
            if cents > 0 {
                allocations[catId] = String(format: "%.2f", Double(cents) / 100.0)
            }
        }
        _budgetAllocations = State(initialValue: allocations)

        self.originalCategoryIds = existingIds
        self.originalBudgetCents = originalCents
    }

    private var isStep1Valid: Bool {
        ProjectFormValidation.isValidProject(name: name, clientName: clientName)
    }

    private var activeBudgetCategories: [BudgetCategory] {
        accountContext.allBudgetCategories
            .filter { $0.isArchived != true }
            .sorted { ($0.order ?? 0) < ($1.order ?? 0) }
    }

    private var selectedCategories: [BudgetCategory] {
        activeBudgetCategories.filter { cat in
            guard let id = cat.id else { return false }
            return selectedCategoryIds.contains(id)
        }
    }

    var body: some View {
        Group {
            switch currentStep {
            case 1: step1BasicInfo
            case 2: step2CategorySelection
            default: step3BudgetAmounts
            }
        }
        .sheet(isPresented: $showCategoryForm) {
            CategoryFormModal(
                mode: .create,
                existingNames: activeBudgetCategories.map(\.name)
            ) { name, categoryType, excludeFromBudget in
                createCategoryOnTheFly(
                    name: name,
                    categoryType: categoryType,
                    excludeFromBudget: excludeFromBudget
                )
            }
            .sheetStyle(.form)
        }
    }

    // MARK: - Step 1: Basic Info

    private var step1BasicInfo: some View {
        MultiStepFormSheet(
            title: "Edit Project",
            description: "Basic information",
            currentStep: 1,
            totalSteps: 3,
            primaryAction: FormSheetAction(
                title: "Next",
                isDisabled: !isStep1Valid
            ) {
                currentStep = 2
            },
            secondaryAction: FormSheetAction(title: "Cancel") { dismiss() }
        ) {
            VStack(spacing: Spacing.md) {
                FormField(text: $name, placeholder: "Project name *")
                FormField(text: $clientName, placeholder: "Client name *")
                FormField(text: $descriptionText, placeholder: "Description", axis: .vertical)

                heroImageSection
            }
        }
    }

    // MARK: - Step 2: Category Selection

    private var step2CategorySelection: some View {
        MultiStepFormSheet(
            title: "Edit Project",
            description: "Select budget categories",
            currentStep: 2,
            totalSteps: 3,
            primaryAction: FormSheetAction(
                title: "Next",
                isDisabled: selectedCategoryIds.isEmpty
            ) {
                currentStep = 3
            },
            secondaryAction: FormSheetAction(title: "Back") { currentStep = 1 }
        ) {
            VStack(spacing: Spacing.md) {
                Button {
                    showCategoryForm = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Category")
                    }
                    .font(Typography.button)
                    .foregroundStyle(BrandColors.primary)
                }
                .buttonStyle(.plain)

                if activeBudgetCategories.isEmpty {
                    Text("No budget categories yet. Tap above to create one.")
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, Spacing.lg)
                } else {
                    ForEach(activeBudgetCategories) { category in
                        if let catId = category.id {
                            categorySelectionRow(category: category, id: catId)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Step 3: Budget Amounts

    private var step3BudgetAmounts: some View {
        MultiStepFormSheet(
            title: "Edit Project",
            description: "Set budget amounts",
            currentStep: 3,
            totalSteps: 3,
            primaryAction: FormSheetAction(title: "Save Changes") {
                saveProject()
            },
            secondaryAction: FormSheetAction(title: "Back") { currentStep = 2 }
        ) {
            VStack(spacing: Spacing.md) {
                if selectedCategories.isEmpty {
                    Text("No categories selected.")
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textTertiary)
                } else {
                    ForEach(selectedCategories) { category in
                        if let catId = category.id {
                            HStack {
                                Text(category.name)
                                    .font(Typography.body)
                                    .foregroundStyle(BrandColors.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                TextField("$0", text: budgetBinding(for: catId))
                                    .platformKeyboardType(.numberPad)
                                    .font(Typography.input)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 100)
                                    .padding(.horizontal, Spacing.sm)
                                    .frame(height: 36)
                                    .background(BrandColors.inputBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                                            .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
                                    )
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    private var heroImageSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Hero Image")
                .font(Typography.label)
                .foregroundStyle(BrandColors.textSecondary)

            PhotosPicker(selection: $heroImageItem, matching: .images) {
                if let heroImageData {
                    platformImage(from: heroImageData)
                        .scaledToFill()
                        .frame(height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
                } else if let existingUrl = existingImageUrl, !existingUrl.isEmpty {
                    FirebaseImage(url: existingUrl, contentMode: .fill) {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                    .frame(height: 120)
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
        .onChange(of: heroImageItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    heroImageData = data
                }
            }
        }
    }

    private func categorySelectionRow(category: BudgetCategory, id: String) -> some View {
        Button {
            if selectedCategoryIds.contains(id) {
                selectedCategoryIds.remove(id)
                budgetAllocations.removeValue(forKey: id)
            } else {
                selectedCategoryIds.insert(id)
            }
        } label: {
            HStack(spacing: Spacing.md) {
                SelectorCircle(isSelected: selectedCategoryIds.contains(id), indicator: .check)

                Text(category.name)
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textPrimary)

                if let type = category.metadata?.categoryType, type != .general {
                    Badge(
                        text: type == .itemized ? "Itemized" : "Fee",
                        color: type == .itemized ? StatusColors.badgeInfo : StatusColors.badgeWarning
                    )
                }

                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - On-the-fly Category Creation

    private func createCategoryOnTheFly(
        name: String,
        categoryType: BudgetCategoryType,
        excludeFromBudget: Bool
    ) {
        guard let accountId = accountContext.currentAccountId else { return }
        var category = BudgetCategory()
        category.accountId = accountId
        category.name = name
        category.slug = name.lowercased().replacingOccurrences(of: " ", with: "-")
        category.order = (activeBudgetCategories.last?.order ?? 0) + 1
        category.metadata = BudgetCategoryMetadata(
            categoryType: categoryType,
            excludeFromOverallBudget: excludeFromBudget
        )

        do {
            let newCategoryId = try budgetCategoriesService.createBudgetCategory(
                accountId: accountId, category: category
            )
            selectedCategoryIds.insert(newCategoryId)
        } catch {
            // Offline-first: should not fail in practice
        }
    }

    // MARK: - Budget Binding

    private func budgetBinding(for categoryId: String) -> Binding<String> {
        Binding(
            get: { budgetAllocations[categoryId] ?? "" },
            set: { budgetAllocations[categoryId] = $0 }
        )
    }

    // MARK: - Save

    private func saveProject() {
        guard let accountId = accountContext.currentAccountId,
              let projectId = project.id else { return }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedClient = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDesc = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let userId = authManager.currentUser?.uid

        // Build project field updates
        var fields: [String: Any] = [
            "name": trimmedName,
            "clientName": trimmedClient,
        ]
        if trimmedDesc.isEmpty {
            fields["description"] = NSNull()
        } else {
            fields["description"] = trimmedDesc
        }

        // Dismiss immediately (optimistic UI)
        dismiss()

        // Background: update project document
        Task {
            try? await projectService.updateProject(
                accountId: accountId, projectId: projectId, fields: fields
            )
        }

        // Background: diff categories and apply changes
        Task {
            let addedIds = selectedCategoryIds.subtracting(originalCategoryIds)
            let removedIds = originalCategoryIds.subtracting(selectedCategoryIds)
            let keptIds = selectedCategoryIds.intersection(originalCategoryIds)

            // Add new categories
            for catId in addedIds {
                let cents = parseDollarsToCents(budgetAllocations[catId] ?? "")
                try? await projectBudgetCategoriesService.setProjectBudgetCategory(
                    accountId: accountId, projectId: projectId,
                    categoryId: catId, budgetCents: cents, userId: userId
                )
            }

            // Update existing categories where budget changed
            for catId in keptIds {
                let newCents = parseDollarsToCents(budgetAllocations[catId] ?? "")
                let oldCents = originalBudgetCents[catId] ?? 0
                if newCents != oldCents {
                    try? await projectBudgetCategoriesService.setProjectBudgetCategory(
                        accountId: accountId, projectId: projectId,
                        categoryId: catId, budgetCents: newCents, userId: userId
                    )
                }
            }

            // Delete removed categories
            for catId in removedIds {
                try? await projectBudgetCategoriesService.deleteProjectBudgetCategory(
                    accountId: accountId, projectId: projectId, categoryId: catId
                )
            }
        }

        // Enqueue hero image for persistent upload — survives app restart
        if let heroImageData {
            let path = mediaService.uploadPath(
                accountId: accountId, entityType: "projects",
                entityId: projectId, filename: "hero.jpg"
            )
            mediaUploadQueue.enqueue(
                imageData: heroImageData,
                metadata: UploadMetadata(
                    accountId: accountId, entityType: "projects", entityId: projectId,
                    storagePath: path, updateType: .setField("mainImageUrl"),
                    fileName: "hero.jpg"
                )
            )
            mediaUploadQueue.processQueue()
        }
    }

    private func parseDollarsToCents(_ text: String) -> Int {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard let value = Double(cleaned), value >= 0 else { return 0 }
        return Int(value * 100)
    }
}
