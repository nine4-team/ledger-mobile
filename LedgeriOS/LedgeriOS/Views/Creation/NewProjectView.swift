import SwiftUI
import PhotosUI

/// Multi-step bottom sheet form for creating a new project.
/// Step 1: Basic info → Step 2: Category selection → Step 3: Budget amounts.
struct NewProjectView: View {
    @Environment(AccountContext.self) private var accountContext
    @Environment(AuthManager.self) private var authManager
    @Environment(MediaService.self) private var mediaService
    @Environment(MediaUploadQueue.self) private var mediaUploadQueue
    @Environment(\.dismiss) private var dismiss

    // Step management
    @State private var currentStep = 1

    // Step 1 — basic info
    @State private var name = ""
    @State private var clientName = ""
    @State private var descriptionText = ""
    @State private var notesText = ""
    @State private var heroImageItem: PhotosPickerItem?
    @State private var heroImageData: Data?

    // Step 2 — category selection
    @State private var selectedCategoryIds: Set<String> = []
    @State private var showCategoryForm = false
    @State private var didPreSelect = false

    // Step 3 — budget amounts
    @State private var budgetAllocations: [String: String] = [:]

    private let projectService = ProjectService()
    private let budgetCategoriesService = BudgetCategoriesService()
    private let projectBudgetCategoriesService = ProjectBudgetCategoriesService()

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
        .adaptivePresentation(isPresented: $showCategoryForm, style: .form) {
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
        }
        .onChange(of: activeBudgetCategories.count) {
            preSelectAllIfNeeded()
        }
        .onAppear {
            preSelectAllIfNeeded()
        }
    }

    // MARK: - Step 1: Basic Info

    private var step1BasicInfo: some View {
        MultiStepFormSheet(
            title: "New Project",
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

                FormField(text: $notesText, placeholder: "Notes", axis: .vertical)

                heroImageSection
            }
        }
    }

    // MARK: - Step 2: Category Selection

    private var step2CategorySelection: some View {
        MultiStepFormSheet(
            title: "New Project",
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
            title: "New Project",
            description: "Set budget amounts",
            currentStep: 3,
            totalSteps: 3,
            primaryAction: FormSheetAction(title: "Create Project") {
                createProject()
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
                                    .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                                            .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
                                    )
                            }
                        }
                    }

                    Divider()

                    HStack {
                        Text("Overall Budget")
                            .font(Typography.body.weight(.semibold))
                            .foregroundStyle(BrandColors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(BudgetDisplayCalculations.formatCentsAsDollars(overallBudgetCents))
                            .font(Typography.body.weight(.semibold))
                            .foregroundStyle(BrandColors.textPrimary)
                    }
                }
            }
        }
    }

    private var overallBudgetCents: Int {
        selectedCategories.reduce(0) { total, category in
            guard category.metadata?.excludeFromOverallBudget != true,
                  let catId = category.id else { return total }
            return total + parseDollarsToCents(budgetAllocations[catId] ?? "")
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
                } else {
                    HStack {
                        Image(systemName: "photo")
                        Text("Select Image")
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
            }
            .buttonStyle(.plain)
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

    // MARK: - Pre-selection

    private func preSelectAllIfNeeded() {
        guard !didPreSelect else { return }
        let ids = activeBudgetCategories.compactMap(\.id)
        guard !ids.isEmpty else { return }
        selectedCategoryIds = Set(ids)
        didPreSelect = true
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

    // MARK: - Project Creation

    private func createProject() {
        guard let accountId = accountContext.currentAccountId else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedClient = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDesc = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let trimmedNotes = notesText.trimmingCharacters(in: .whitespacesAndNewlines)
            let projectId = try projectService.createProject(
                accountId: accountId,
                name: trimmedName,
                clientName: trimmedClient,
                description: trimmedDesc.isEmpty ? nil : trimmedDesc,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes
            )

            dismiss()

            // Background: create project budget categories for all selected categories
            Task {
                let userId = authManager.currentUser?.uid
                for catId in selectedCategoryIds {
                    let amountStr = budgetAllocations[catId] ?? ""
                    let cents = parseDollarsToCents(amountStr)
                    try? await projectBudgetCategoriesService.setProjectBudgetCategory(
                        accountId: accountId,
                        projectId: projectId,
                        categoryId: catId,
                        budgetCents: cents,
                        userId: userId
                    )
                }
            }

            // Enqueue hero image for persistent upload — survives app restart
            if let heroImageData {
                let path = mediaService.uploadPath(
                    accountId: accountId, entityType: "projects",
                    entityId: projectId, filename: "hero.jpg"
                )
                let thumbPaths = ImageThumbnailGenerator.thumbnailPaths(for: path)
                var metadata = UploadMetadata(
                    accountId: accountId, entityType: "projects", entityId: projectId,
                    storagePath: path, updateType: .setField("mainImageUrl"),
                    fileName: "hero.jpg"
                )
                metadata.thumbnailStoragePathSm = thumbPaths.sm
                metadata.thumbnailStoragePathMd = thumbPaths.md
                mediaUploadQueue.enqueue(imageData: heroImageData, metadata: metadata)
                mediaUploadQueue.processQueue()
            }
        } catch {
            // Offline-first: creation should not fail in practice
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
