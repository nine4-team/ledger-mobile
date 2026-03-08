import SwiftUI

struct FinancesTabView: View {
    @State private var selectedSubtab = "budget"

    var body: some View {
        VStack(spacing: 0) {
            Picker("Finances", selection: $selectedSubtab) {
                Text("Budget").tag("budget")
                Text("Reports").tag("reports")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.vertical, Spacing.sm)

            switch selectedSubtab {
            case "reports":
                AccountingTabView()
            default:
                BudgetTabView()
            }
        }
    }
}
