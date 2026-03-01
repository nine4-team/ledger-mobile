import SwiftUI
import PhotosUI

/// Bottom-sheet form for creating a new project.
struct NewProjectView: View {
    @Environment(AccountContext.self) private var accountContext
    @Environment(AuthManager.self) private var authManager
    @Environment(MediaService.self) private var mediaService
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var clientName = ""
    @State private var descriptionText = ""
    @State private var heroImageItem: PhotosPickerItem?
    @State private var heroImageData: Data?
    @State private var budgetAllocations: [String: String] = [:]
    @State private var budgetCategories: [BudgetCategory] = []
    @State private var listener: (any NSObjectProtocol)?

    private let projectService = ProjectService(syncTracker: NoOpSyncTracker())
    private let budgetCategoriesService = BudgetCategoriesService(syncTracker: NoOpSyncTracker())
    private let projectBudgetCategoriesService = ProjectBudgetCategoriesService(syncTracker: NoOpSyncTracker())

    private var isValid: Bool {
        ProjectFormValidation.isValidProject(name: name, clientName: clientName)
    }

    var body: some View {
        FormSheet(
            title: "New Project",
            primaryAction: FormSheetAction(title: "Create Project", isDisabled: !isValid) {
                createProject()
            },
            secondaryAction: FormSheetAction(title: "Cancel") {
                dismiss()
            }
        ) {
            VStack(spacing: Spacing.md) {
                FormField(label: "Name *", text: $name, placeholder: "Project name")
                FormField(label: "Client Name *", text: $clientName, placeholder: "Client name")
                FormField(label: "Description", text: $descriptionText, placeholder: "Optional description", axis: .vertical)

                // Hero Image
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Hero Image")
                        .font(Typography.label)
                        .foregroundStyle(BrandColors.textSecondary)

                    PhotosPicker(selection: $heroImageItem, matching: .images) {
                        if let heroImageData, let uiImage = UIImage(data: heroImageData) {
                            Image(uiImage: uiImage)
                                .resizable()
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

                // Budget Allocations
                if !budgetCategories.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Budget Allocations")
                            .font(Typography.label)
                            .foregroundStyle(BrandColors.textSecondary)

                        ForEach(budgetCategories) { category in
                            if let catId = category.id {
                                HStack {
                                    Text(category.name)
                                        .font(Typography.body)
                                        .foregroundStyle(BrandColors.textPrimary)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    TextField("$0", text: budgetBinding(for: catId))
                                        .keyboardType(.numberPad)
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
        .task {
            loadBudgetCategories()
        }
    }

    // MARK: - Data Loading

    private func loadBudgetCategories() {
        guard let accountId = accountContext.currentAccountId else { return }
        let reg = budgetCategoriesService.subscribeToBudgetCategories(accountId: accountId) { categories in
            Task { @MainActor in
                self.budgetCategories = categories.filter { $0.isArchived != true }
                    .sorted { ($0.order ?? 0) < ($1.order ?? 0) }
            }
        }
        // Store as opaque to avoid type issues; won't remove since view lifetime is short
        _ = reg
    }

    // MARK: - Budget Binding

    private func budgetBinding(for categoryId: String) -> Binding<String> {
        Binding(
            get: { budgetAllocations[categoryId] ?? "" },
            set: { budgetAllocations[categoryId] = $0 }
        )
    }

    // MARK: - Actions

    private func createProject() {
        guard let accountId = accountContext.currentAccountId else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedClient = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDesc = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let projectId = try projectService.createProject(
                accountId: accountId,
                name: trimmedName,
                clientName: trimmedClient,
                description: trimmedDesc.isEmpty ? nil : trimmedDesc
            )

            dismiss()

            // Background: set budget allocations
            Task {
                let userId = authManager.currentUser?.uid
                for (catId, amountStr) in budgetAllocations {
                    let cents = parseDollarsToCents(amountStr)
                    if cents > 0 {
                        try? await projectBudgetCategoriesService.setProjectBudgetCategory(
                            accountId: accountId,
                            projectId: projectId,
                            categoryId: catId,
                            budgetCents: cents,
                            userId: userId
                        )
                    }
                }
            }

            // Background: upload hero image
            if let heroImageData {
                Task {
                    let path = mediaService.uploadPath(
                        accountId: accountId, entityType: "projects",
                        entityId: projectId, filename: "hero.jpg"
                    )
                    if let url = try? await mediaService.uploadImage(heroImageData, path: path) {
                        try? await projectService.updateProject(
                            accountId: accountId, projectId: projectId,
                            fields: ["mainImageUrl": url]
                        )
                    }
                }
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
