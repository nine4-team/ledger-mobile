import SwiftUI

struct InventoryPinnedCard: View {
    @Environment(InventoryContext.self) private var inventoryContext

    var body: some View {
        Card {
            HStack(spacing: Spacing.md) {
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(BrandColors.primary)
                    .frame(width: 44, height: 44)
                    .background(BrandColors.primary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: Dimensions.buttonRadius))

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Business Inventory")
                        .font(Typography.h3)
                        .foregroundStyle(BrandColors.textPrimary)

                    Text(summaryText)
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(Typography.small)
                    .foregroundStyle(BrandColors.textTertiary)
            }
        }
    }

    private var summaryText: String {
        let itemCount = inventoryContext.items.count
        let txCount = inventoryContext.transactions.count
        let parts = [
            "\(itemCount) \(itemCount == 1 ? "item" : "items")",
            "\(txCount) \(txCount == 1 ? "transaction" : "transactions")",
        ]
        return parts.joined(separator: " · ")
    }
}

#Preview {
    InventoryPinnedCard()
        .padding(Spacing.screenPadding)
        .environment(InventoryContext(
            itemsService: ItemsService(),
            transactionsService: TransactionsService(),
            spacesService: SpacesService()
        ))
        .preferredColorScheme(.dark)
}
