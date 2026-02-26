import SwiftUI

struct TransactionsTabPlaceholder: View {
    @Environment(ProjectContext.self) private var projectContext

    var body: some View {
        ContentUnavailableView(
            "\(projectContext.transactions.count) Transactions",
            systemImage: "creditcard",
            description: Text("Coming soon")
        )
    }
}
