import Foundation
import LedgerTargetAppModel
import LedgerTargetCore
import SwiftUI

struct ProjectSetupStagingExerciseView: View {
    @Bindable var model: ProjectSetupStagingExercise
    let onCancel: () -> Void
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Step", value: "\(model.stepIndex) of 3")
                        .accessibilityIdentifier("target-project-setup-step")
                    Text(model.stepTitle)
                        .font(.headline)
                        .accessibilityIdentifier("target-project-setup-step-title")
                }

                Group {
                    if model.isAcceptedProjectReceipt,
                       let submittedProject = model.submittedProject {
                        submittedSummary(submittedProject)
                    } else {
                        switch model.currentStep {
                        case .basicInfo:
                            basicInformation
                        case .categorySelection:
                            categorySelection
                        case .budgetAmounts:
                            budgetAmounts
                        }
                    }
                }
                .disabled(model.isDraftLocked)

                operationResult
                actions
            }
            .navigationTitle("New Project")
            .interactiveDismissDisabled(model.isSubmitting)
        }
    }

    private var basicInformation: some View {
        Section("Basic information") {
            TextField("Project name *", text: $model.projectName)
                .accessibilityIdentifier("target-project-name")

            Picker("Existing Client *", selection: $model.selectedClientId) {
                Text("Choose a Client").tag(Optional<ClientID>.none)
                ForEach(model.clients, id: \.id) { client in
                    Text(client.displayName.rawValue).tag(Optional(client.id))
                }
            }
            .accessibilityIdentifier("target-project-existing-client")

            LabeledContent("Client data", value: model.clientStatus)
                .accessibilityIdentifier("target-project-client-readiness")

            TextField(
                "Description (optional)",
                text: $model.projectDescription,
                axis: .vertical
            )
            .lineLimit(3 ... 6)
            .accessibilityIdentifier("target-project-description")

        }
    }

    private var categorySelection: some View {
        Section("Select budget categories") {
            LabeledContent("Category data", value: model.categoryStatus)
                .accessibilityIdentifier("target-project-category-readiness")

            if model.categories.isEmpty {
                Text("No budget categories yet.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("target-project-no-categories")
            } else {
                ForEach(model.categories, id: \.id) { category in
                    Toggle(isOn: categorySelectionBinding(category.id)) {
                        HStack {
                            Text(category.name.rawValue)
                            if category.kind != .general {
                                Text(category.kind.rawValue.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier(
                        "target-project-category-\(category.id.rawValue)"
                    )
                }
            }

            Text("Choose at least one category to continue.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("target-project-category-requirement")
        }
    }

    private var budgetAmounts: some View {
        Section("Set budget amounts") {
            ForEach(selectedCategories, id: \.id) { category in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(category.name.rawValue)
                        Spacer()
                        TextField(
                            "Optional amount",
                            text: allocationBinding(category.id)
                        )
                        .multilineTextAlignment(.trailing)
                        .frame(minWidth: 120, maxWidth: 180)
                        .accessibilityIdentifier(
                            "target-project-allocation-\(category.id.rawValue)"
                        )
                    }
                    if model.invalidAllocationIds.contains(category.id) {
                        Text("Enter a nonnegative amount with no more than two decimal places.")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier(
                                "target-project-allocation-error-\(category.id.rawValue)"
                            )
                    } else if model.allocationText(for: category.id).isEmpty {
                        Text("No budget set")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            LabeledContent("Overall Budget", value: formattedOverallBudget)
                .accessibilityIdentifier("target-project-overall-budget")
            Text("Blank remains unset; entering 0 records an explicit zero budget.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("target-project-allocation-semantics")
        }
    }

    private func submittedSummary(_ project: SubmittedProjectSummary) -> some View {
        Section("Submitted Project") {
            LabeledContent("Project", value: project.projectName)
                .accessibilityIdentifier("target-project-submitted-name")
            LabeledContent("Client", value: project.clientName)
                .accessibilityIdentifier("target-project-submitted-client")
            if let description = project.projectDescription {
                LabeledContent("Description", value: description)
                    .accessibilityIdentifier("target-project-submitted-description")
            }
            ForEach(project.categories, id: \.id) { category in
                LabeledContent(
                    category.name,
                    value: category.allocation.map(Self.format) ?? "No budget set"
                )
                .accessibilityIdentifier(
                    "target-project-submitted-category-\(category.id.rawValue)"
                )
            }
        }
    }

    @ViewBuilder
    private var operationResult: some View {
        if let operationId = model.receiptOperationId,
           let state = model.receiptState,
           let explanation = model.receiptExplanation {
            Section(model.isAcceptedProjectReceipt ? "Project accepted" : "Project not pending") {
                LabeledContent("Operation", value: operationId)
                LabeledContent("State", value: state)
                Text(explanation)
                    .accessibilityIdentifier("target-project-receipt")
            }
        }
        if let diagnostic = model.diagnostic {
            Section(
                model.hasPostAcceptanceObservationIssue
                    ? "Synchronization status unavailable"
                    : "Project not accepted"
            ) {
                Text(diagnostic)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("target-project-diagnostic")
                Text(
                    model.hasPostAcceptanceObservationIssue
                        ? "The project was accepted locally, but its latest synchronization status could not be verified. Do not create a duplicate; reopen Projects or check again when connectivity is available."
                        : "Your draft is still here. Correct any changed evidence or retry local acceptance."
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actions: some View {
        Section {
            HStack {
                if !model.isAcceptedProjectReceipt {
                    Button(secondaryActionTitle) {
                        performSecondaryAction()
                    }
                    .disabled(model.isSubmitting)
                    .accessibilityIdentifier("target-project-secondary-action")
                }

                Spacer()

                if model.isAcceptedProjectReceipt {
                    Button("Done") { onDone() }
                        .accessibilityIdentifier("target-project-done")
                } else if model.currentStep == .budgetAmounts {
                    Button(model.isSubmitting ? "Creating…" : primarySubmissionTitle) {
                        Task { await model.submit() }
                    }
                    .disabled(!model.canSubmit)
                    .accessibilityIdentifier("target-create-project")
                } else {
                    Button("Next") { _ = model.next() }
                        .disabled(!model.canAdvance)
                        .accessibilityIdentifier("target-project-next")
                }
            }
        }
    }

    private var selectedCategories: [BudgetCategoryDefinitionSnapshot] {
        model.categories.filter { model.selectedCategoryIds.contains($0.id) }
    }

    private var primarySubmissionTitle: String {
        model.diagnostic == nil && model.receipt == nil ? "Create Project" : "Retry"
    }

    private var secondaryActionTitle: String {
        model.currentStep == .basicInfo ? "Cancel" : "Back"
    }

    private func performSecondaryAction() {
        if model.currentStep == .basicInfo {
            onCancel()
        } else {
            _ = model.back()
        }
    }

    private func categorySelectionBinding(_ categoryId: BudgetCategoryID) -> Binding<Bool> {
        Binding(
            get: { model.selectedCategoryIds.contains(categoryId) },
            set: { selected in
                model.setCategory(categoryId, selected: selected)
            }
        )
    }

    private func allocationBinding(_ categoryId: BudgetCategoryID) -> Binding<String> {
        Binding(
            get: { model.allocationText(for: categoryId) },
            set: { rawValue in _ = model.setAllocationText(rawValue, for: categoryId) }
        )
    }

    private var formattedOverallBudget: String {
        var total: Int64 = 0
        for category in selectedCategories where !category.excludesFromOverallBudget {
            let amount = model.allocation(for: category.id)?.minorUnits ?? 0
            let addition = total.addingReportingOverflow(amount)
            guard !addition.overflow else { return "Unavailable" }
            total = addition.partialValue
        }
        return Self.format(minorUnits: total, currency: model.accountCurrency)
    }

    private static func format(minorUnits: Int64, currency: CurrencyCode) -> String {
        let whole = minorUnits / 100
        let fraction = minorUnits % 100
        return "\(currency.rawValue) \(whole).\(String(format: "%02lld", fraction))"
    }

    private static func format(_ amount: Money) -> String {
        format(minorUnits: amount.minorUnits, currency: amount.currency)
    }
}
