import Foundation
import Testing
@testable import LedgeriOS

@Suite("Transaction Display Calculation Tests")
struct TransactionDisplayCalculationTests {

    // MARK: - Helpers

    private func makeTransaction(
        id: String? = "abc123def456",
        source: String? = nil,
        isCanonicalInventorySale: Bool? = nil,
        inventorySaleDirection: InventorySaleDirection? = nil,
        transactionType: String? = nil,
        reimbursementType: String? = nil,
        hasEmailReceipt: Bool? = nil,
        receiptImages: [AttachmentRef]? = nil,
        isComplete: Bool? = true,
        budgetCategoryId: String? = nil,
        amountCents: Int? = nil,
        transactionDate: String? = nil
    ) -> Transaction {
        var txn = Transaction()
        txn.id = id
        txn.source = source
        txn.isCanonicalInventorySale = isCanonicalInventorySale
        txn.inventorySaleDirection = inventorySaleDirection
        txn.transactionType = transactionType
        txn.reimbursementType = reimbursementType
        txn.hasEmailReceipt = hasEmailReceipt
        txn.receiptImages = receiptImages
        txn.isComplete = isComplete
        txn.budgetCategoryId = budgetCategoryId
        txn.amountCents = amountCents
        txn.transactionDate = transactionDate
        return txn
    }

    private func makeCategory(id: String, name: String, type: BudgetCategoryType? = nil) -> BudgetCategory {
        var cat = BudgetCategory()
        cat.id = id
        cat.name = name
        if let type {
            cat.metadata = BudgetCategoryMetadata(categoryType: type)
        }
        return cat
    }

    // MARK: - displayName

    @Test("Display name uses source when present")
    func displayNameSource() {
        let txn = makeTransaction(source: "HomeGoods")
        #expect(TransactionDisplayCalculations.displayName(for: txn) == "HomeGoods")
    }

    @Test("Display name skips empty source")
    func displayNameEmptySource() {
        let txn = makeTransaction(source: "  ")
        #expect(TransactionDisplayCalculations.displayName(for: txn) == "abc123")
    }

    @Test("Display name uses canonical inventory sale label - businessToProject")
    func displayNameInventoryToProject() {
        let txn = makeTransaction(
            isCanonicalInventorySale: true,
            inventorySaleDirection: .businessToProject
        )
        #expect(TransactionDisplayCalculations.displayName(for: txn) == "Purchase from Inventory")
    }

    @Test("Display name uses canonical inventory sale label - projectToBusiness")
    func displayNameInventoryFromProject() {
        let txn = makeTransaction(
            isCanonicalInventorySale: true,
            inventorySaleDirection: .projectToBusiness
        )
        #expect(TransactionDisplayCalculations.displayName(for: txn) == "Sale to Inventory")
    }

    @Test("Display name falls back to ID prefix")
    func displayNameIdPrefix() {
        let txn = makeTransaction(id: "abcdef123456")
        #expect(TransactionDisplayCalculations.displayName(for: txn) == "abcdef")
    }

    @Test("Display name falls back to Untitled Transaction")
    func displayNameUntitled() {
        let txn = makeTransaction(id: nil)
        #expect(TransactionDisplayCalculations.displayName(for: txn) == "Untitled Transaction")
    }

    // MARK: - badgeConfigs

    @Test("Purchase type produces brand-primary badge")
    func badgePurchase() {
        let txn = makeTransaction(transactionType: "purchase")
        let badges = TransactionDisplayCalculations.badgeConfigs(for: txn, category: nil)
        #expect(badges.count == 1)
        #expect(badges[0].text == "Purchase")
        #expect(badges[0].color == BrandColors.primary)
    }

    @Test("Sale type produces brand-primary badge")
    func badgeSale() {
        let txn = makeTransaction(transactionType: "sale")
        let badges = TransactionDisplayCalculations.badgeConfigs(for: txn, category: nil)
        #expect(badges.count == 1)
        #expect(badges[0].text == "Sale")
        #expect(badges[0].color == BrandColors.primary)
    }

    @Test("Return type produces brand-primary badge")
    func badgeReturn() {
        let txn = makeTransaction(transactionType: "return")
        let badges = TransactionDisplayCalculations.badgeConfigs(for: txn, category: nil)
        #expect(badges.count == 1)
        #expect(badges[0].text == "Return")
        #expect(badges[0].color == BrandColors.primary)
    }

    @Test("To-inventory type produces no badge")
    func badgeToInventory() {
        let txn = makeTransaction(transactionType: "to-inventory")
        let badges = TransactionDisplayCalculations.badgeConfigs(for: txn, category: nil)
        #expect(badges.isEmpty)
    }

    @Test("Reimbursement type does not produce a badge")
    func badgeReimbursementClient() {
        let txn = makeTransaction(transactionType: "purchase", reimbursementType: "owed-to-client")
        let badges = TransactionDisplayCalculations.badgeConfigs(for: txn, category: nil)
        #expect(badges.count == 1)
        #expect(badges[0].text == "Purchase")
    }

    @Test("No reimbursement badge when type is none")
    func badgeReimbursementNone() {
        let txn = makeTransaction(transactionType: "purchase", reimbursementType: "none")
        let badges = TransactionDisplayCalculations.badgeConfigs(for: txn, category: nil)
        #expect(badges.count == 1) // Only the type badge
    }

    @Test("Receipt images do not produce a badge")
    func badgeReceiptImages() {
        let ref = AttachmentRef(url: "https://example.com/receipt.jpg")
        let txn = makeTransaction(transactionType: "purchase", receiptImages: [ref])
        let badges = TransactionDisplayCalculations.badgeConfigs(for: txn, category: nil)
        #expect(badges.count == 1)
        #expect(badges[0].text == "Purchase")
    }

    @Test("Email receipt does not produce a badge")
    func badgeEmailReceipt() {
        let txn = makeTransaction(transactionType: "purchase", hasEmailReceipt: true)
        let badges = TransactionDisplayCalculations.badgeConfigs(for: txn, category: nil)
        #expect(badges.count == 1)
        #expect(badges[0].text == "Purchase")
    }

    @Test("Needs review badge appears first when isComplete is false")
    func badgeNeedsReview() {
        let txn = makeTransaction(transactionType: "purchase", isComplete: false)
        let badges = TransactionDisplayCalculations.badgeConfigs(for: txn, category: nil)
        #expect(badges.count == 2)
        #expect(badges[0].text == "Needs Review")
        #expect(badges[0].color == StatusColors.badgeNeedsReview)
        #expect(badges[1].text == "Purchase")
    }

    @Test("Category badge when category present")
    func badgeCategory() {
        let txn = makeTransaction(transactionType: "purchase")
        let cat = makeCategory(id: "cat1", name: "Furniture")
        let badges = TransactionDisplayCalculations.badgeConfigs(for: txn, category: cat)
        #expect(badges.count == 2)
        #expect(badges[1].text == "Furniture")
        #expect(badges[1].color == BrandColors.primary)
    }

    @Test("All badge types present in correct order: needs review, type, category")
    func badgeAllTypes() {
        let txn = makeTransaction(
            transactionType: "purchase",
            isComplete: false
        )
        let cat = makeCategory(id: "cat1", name: "Decor")
        let badges = TransactionDisplayCalculations.badgeConfigs(for: txn, category: cat)
        #expect(badges.count == 3)
        #expect(badges[0].text == "Needs Review")
        #expect(badges[1].text == "Purchase")
        #expect(badges[2].text == "Decor")
    }

    // MARK: - formattedAmount

    @Test("Formatted amount for positive cents")
    func formattedAmountPositive() {
        let txn = makeTransaction(amountCents: 4999)
        #expect(TransactionDisplayCalculations.formattedAmount(for: txn) == "$49.99")
    }

    @Test("Formatted amount for zero cents")
    func formattedAmountZero() {
        let txn = makeTransaction(amountCents: 0)
        #expect(TransactionDisplayCalculations.formattedAmount(for: txn) == "$0.00")
    }

    @Test("Formatted amount for nil returns dash")
    func formattedAmountNil() {
        let txn = makeTransaction()
        #expect(TransactionDisplayCalculations.formattedAmount(for: txn) == "—")
    }

    // MARK: - canonicalTypeLabel

    @Test("Canonical labels for known types")
    func canonicalLabels() {
        #expect(TransactionDisplayCalculations.canonicalTypeLabel(for: "purchase") == "Purchase")
        #expect(TransactionDisplayCalculations.canonicalTypeLabel(for: "sale") == "Sale")
        #expect(TransactionDisplayCalculations.canonicalTypeLabel(for: "return") == "Return")
        #expect(TransactionDisplayCalculations.canonicalTypeLabel(for: "to-inventory") == "To Inventory")
    }

    @Test("Canonical label nil for unknown type")
    func canonicalLabelUnknown() {
        #expect(TransactionDisplayCalculations.canonicalTypeLabel(for: "custom") == nil)
        #expect(TransactionDisplayCalculations.canonicalTypeLabel(for: nil) == nil)
    }
}
