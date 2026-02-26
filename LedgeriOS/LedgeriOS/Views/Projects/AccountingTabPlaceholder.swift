import SwiftUI

struct AccountingTabPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "Accounting",
            systemImage: "doc.text",
            description: Text("Coming soon")
        )
    }
}
