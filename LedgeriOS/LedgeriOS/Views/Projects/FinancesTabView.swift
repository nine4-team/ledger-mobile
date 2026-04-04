import SwiftUI

struct FinancesTabView: View {
    @State private var selectedSubtab = "budget"

    var body: some View {
        VStack(spacing: 0) {
            SegmentedControl(selection: $selectedSubtab, options: [
                SegmentOption(id: "budget", label: "Budget"),
                SegmentOption(id: "reports", label: "Reports"),
            ])
            .frame(maxWidth: Dimensions.contentMaxWidth)
            .frame(maxWidth: .infinity)
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
