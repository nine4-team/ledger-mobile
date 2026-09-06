import LedgerTargetAppModel
import LedgerTargetCore
import SwiftUI

struct ProjectSetupStagingExerciseView: View {
    @Bindable var model: ProjectSetupStagingExercise

    var body: some View {
        Section("Offline Project Creation") {
            TextField("Project name", text: $model.projectName)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("target-project-name")

            Picker("Existing Client", selection: $model.selectedClientId) {
                Text("Choose a Client").tag(Optional<ClientID>.none)
                ForEach(model.clients, id: \.id) { client in
                    Text(client.displayName.rawValue).tag(Optional(client.id))
                }
            }
            .accessibilityIdentifier("target-project-existing-client")

            LabeledContent("Client data", value: model.clientStatus)
                .accessibilityIdentifier("target-project-client-readiness")

            TextField("Description (optional)", text: $model.projectDescription)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("target-project-description")

            LabeledContent("Category data", value: model.categoryStatus)
                .accessibilityIdentifier("target-project-category-readiness")

            if model.categories.isEmpty {
                Text("No represented configurable categories. A Project can be created without categories.")
            } else {
                ForEach(model.categories, id: \.id) { category in
                    Toggle(
                        category.name.rawValue,
                        isOn: Binding(
                            get: { model.selectedCategoryIds.contains(category.id) },
                            set: { model.setCategory(category.id, selected: $0) }
                        )
                    )
                    .accessibilityIdentifier(
                        "target-project-category-\(category.id.rawValue)"
                    )
                }
            }

            Button(model.isSubmitting ? "Creating…" : "Create Project while offline") {
                Task { await model.submit() }
            }
            .disabled(!model.canSubmit)
            .accessibilityIdentifier("target-create-project")

            if let operationId = model.receiptOperationId,
               let state = model.receiptState,
               let explanation = model.receiptExplanation {
                LabeledContent("Operation", value: operationId)
                LabeledContent("Local state", value: state)
                Text(explanation)
                    .accessibilityIdentifier("target-project-receipt")
            }
            if let diagnostic = model.diagnostic {
                Text(diagnostic)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("target-project-diagnostic")
            }
        }
    }
}
