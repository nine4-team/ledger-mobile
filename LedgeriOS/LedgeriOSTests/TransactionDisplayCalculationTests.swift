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
        needsReview: Bool? = nil,
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
        txn.needsReview = needsReview
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
        #expect(TransactionDisplayCalculations.displayName(for: txn) == "To Inventory")
    }

    @Test("Display name uses canonical inventory sale label - projectToBusiness")
    func displayNameInventoryFromProject() {
        let txn = makeTransaction(
            isCanonicalInventorySale: true,
            inventorySaleDirection: .projectToBusiness
        )
        #expect(TransactionDisplayCalculations.displayName(for: txn) == "From Inventory")
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

    @Test("Purchase type produces green badge")
    func badgePurchase() {
        let txn = makeTransaction(transactionType: "purchase")
        let badges = TransactionDisplayCalculations.badgeConfigs(for: txn, category: nil)
        #expect(badges.count == 1)
        #expect(badges[0].text == "Purchase")
        #expect(badges[0].color == StatusColors.badgeSuccess)
    }

    @Test("Sale type produces blue badge")
    func badgeSale() {
        let txn = makeTransaction(transactionType: "sale")
        let badges = TransactionDisplayCalculations.badgeConfigs(for: txn, category: nil)
        #expect(badges[0].text == "Sale")
        #expect(badges[0].color == StatusColors.badgeInfo)
    }

    @Test("Return type produces red badge")
    func badgeReturn() {
        let txn = makeTransaction(transactionType: "return")
        let badges = TransactionDisplayCalculations.badgeConfigs(for: txn, category: nil)
        #expect(badges[0].text == "Return")
        #expect(badges[0].color == StatusColors.badgeError)
    }

    @Test("To-inventory type produces primary badge")
    func badgeToInventory() {
        let txn = makeTransaction(transactionType: "to-inventory")
        let badges = TransactionDisplayCalculations.badgeConfigs(for: txn, category: nil)
        #expect(badges[0].text == "To Inventory")
        #expect(badges[0].color == BrandColors.primary)
    }

    @Test("Reimbursement badge when owed-to-client")
    func badgeReimbursementClient() {
        let txn = makeTransaction(transactionType: "purchase", reimbursementType: "owed-to-client")
        let badges = TransactionDisplayCalculations.badgeConfigs(for: txn, category: nil)
        #expect(badges.count == 2)
        #expect(badges[1].text == "Owed to Client")
        #expect(badges[1].color == StatusColors.badgeWarning)
    }

    @Test("No reimbursement badge when type is none")
    func badgeReimbursementNone() {
        let txn = makeTransaction(transactionType: "purchase", reimbursementType: "none")
        let badges = TransactionDisplayCalculations.badgeConfigs(for: txn, category: nil)
        #expect(badges.count == 1) // Only the type badge
    }

    @Test("Receipt badge when has receipt images")
    func badgeReceiptImages() {
        let ref = AttachmentRef(url: "https://example.com/receipt.jpg")
        let txn = makeTransaction(transactionType: "purchase", receiptImages: [ref])
        let badges = TransactionDisplayCalculations.badgeConfigs(for: txn, category: nil)
        #expect(badges.count == 2)
        #expect(badges[1].text == "Receipt")
    }

    @Test("Receipt badge when has email receipt")
    func badgeEmailReceipt() {
        let txn = makeTransaction(transactionType: "purchase", hasEmailReceipt: true)
        let badges = TransactionDisplayCalculations.badgeConfigs(for: txn, category: nil)
        #expect(badges.count == 2)
        #expect(badges[1].text == "Receipt")
    }

    @Test("Needs review badge")
    func badgeNeedsReview() {
        let txn = makeTransaction(transactionType: "purchase", needsReview: true)
        let badges = TransactionDisplayCalculations.badgeConfigs(for: txn, category: nil)
        #expect(badges.count == 2)
        #expect(badges[1].text == "Needs Review")
        #expect(badges[1].color == StatusColors.badgeNeedsReview)
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

    @Test("All badge types present in correct order")
    func badgeAllTypes() {
        let ref = AttachmentRef(url: "https://example.com/receipt.jpg")
        let txn = makeTransaction(
            transactionType: "purchase",
            reimbursementType: "owed-to-client",
            receiptImages: [ref],
            needsReview: true
        )
        let cat = makeCategory(id: "cat1", name: "Decor")
        let badges = TransactionDisplayCalculations.badgeConfigs(for: txn, category: cat)
        #expect(badges.count == 5)
        #expect(badges[0].text == "Purchase")
        #expect(badges[1].text == "Owed to Client")
        #expect(badges[2].text == "Receipt")
        #expect(badges[3].text == "Needs Review")
        #expect(badges[4].text == "Decor")
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
