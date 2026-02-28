import Foundation
import Testing
@testable import LedgeriOS

@Suite("Report Aggregation Calculation Tests")
struct ReportAggregationCalculationTests {

    // MARK: - Test Helpers

    private func makeTransaction(
        id: String? = "tx1",
        amountCents: Int? = 10000,
        reimbursementType: String? = nil,
        isCanceled: Bool? = nil,
        budgetCategoryId: String? = nil,
        itemIds: [String]? = nil,
        source: String? = "HomeGoods",
        transactionDate: String? = "2024-01-15",
        notes: String? = nil,
        isCanonicalInventorySale: Bool? = nil,
        receiptImages: [AttachmentRef]? = nil
    ) -> Transaction {
        var tx = Transaction()
        tx.id = id
        tx.amountCents = amountCents
        tx.reimbursementType = reimbursementType
        tx.isCanceled = isCanceled
        tx.budgetCategoryId = budgetCategoryId
        tx.itemIds = itemIds
        tx.source = source
        tx.transactionDate = transactionDate
        tx.notes = notes
        tx.isCanonicalInventorySale = isCanonicalInventorySale
        tx.receiptImages = receiptImages
        return tx
    }

    private func makeItem(
        id: String? = "item1",
        name: String = "Test Item",
        projectPriceCents: Int? = 5000,
        marketValueCents: Int? = 8000,
        spaceId: String? = nil,
        transactionId: String? = nil,
        budgetCategoryId: String? = nil,
        source: String? = nil,
        sku: String? = nil
    ) -> Item {
        var item = Item()
        item.id = id
        item.name = name
        item.projectPriceCents = projectPriceCents
        item.marketValueCents = marketValueCents
        item.spaceId = spaceId
        item.transactionId = transactionId
        item.budgetCategoryId = budgetCategoryId
        item.source = source
        item.sku = sku
        return item
    }

    private func makeSpace(id: String? = "space1", name: String = "Living Room") -> Space {
        var space = Space()
        space.id = id
        space.name = name
        return space
    }

    private func makeCategory(id: String = "cat1", name: String = "Furniture") -> BudgetCategory {
        var cat = BudgetCategory()
        cat.id = id
        cat.name = name
        return cat
    }

    // MARK: - Invoice Report Tests

    @Test("Canceled transactions are excluded from invoice report")
    func canceledTransactionExcluded() {
        let transactions = [
            makeTransaction(id: "tx1", reimbursementType: "owed-to-company", isCanceled: true),
            makeTransaction(id: "tx2", reimbursementType: "owed-to-company"),
        ]

        let result = ReportAggregationCalculations.computeInvoiceReport(
            transactions: transactions, items: [], categories: []
        )

        #expect(result.chargeLines.count == 1)
        #expect(result.chargeLines[0].transaction.id == "tx2")
    }

    @Test("Charges vs credits split correctly by reimbursement type")
    func chargesVsCredits() {
        let transactions = [
            makeTransaction(id: "tx1", amountCents: 5000, reimbursementType: "owed-to-company"),
            makeTransaction(id: "tx2", amountCents: 3000, reimbursementType: "owed-to-client"),
            makeTransaction(id: "tx3", amountCents: 2000, reimbursementType: nil),
        ]

        let result = ReportAggregationCalculations.computeInvoiceReport(
            transactions: transactions, items: [], categories: []
        )

        #expect(result.chargeLines.count == 1)
        #expect(result.creditLines.count == 1)
        #expect(result.chargeLines[0].amountCents == 5000)
        #expect(result.creditLines[0].amountCents == 3000)
    }

    @Test("Net due = charges - credits")
    func netDueCalculation() {
        let transactions = [
            makeTransaction(id: "tx1", amountCents: 10000, reimbursementType: "owed-to-company"),
            makeTransaction(id: "tx2", amountCents: 3000, reimbursementType: "owed-to-client"),
        ]

        let result = ReportAggregationCalculations.computeInvoiceReport(
            transactions: transactions, items: [], categories: []
        )

        #expect(result.chargesSubtotalCents == 10000)
        #expect(result.creditsSubtotalCents == 3000)
        #expect(result.netDueCents == 7000)
    }

    @Test("Missing project prices flagged on invoice line items")
    func missingProjectPricesFlagged() {
        let transactions = [
            makeTransaction(
                id: "tx1", reimbursementType: "owed-to-company", itemIds: ["item1", "item2"]
            ),
        ]
        let items = [
            makeItem(id: "item1", projectPriceCents: 5000),
            makeItem(id: "item2", projectPriceCents: nil),
        ]

        let result = ReportAggregationCalculations.computeInvoiceReport(
            transactions: transactions, items: items, categories: []
        )

        #expect(result.chargeLines[0].isMissingProjectPrices == true)
        #expect(result.chargeLines[0].linkedItems[0].isMissingPrice == false)
        #expect(result.chargeLines[0].linkedItems[1].isMissingPrice == true)
    }

    @Test("Invoice line uses transaction amount when no items linked")
    func invoiceLineUsesTransactionAmount() {
        let transactions = [
            makeTransaction(id: "tx1", amountCents: 7500, reimbursementType: "owed-to-company"),
        ]

        let result = ReportAggregationCalculations.computeInvoiceReport(
            transactions: transactions, items: [], categories: []
        )

        #expect(result.chargeLines[0].amountCents == 7500)
        #expect(result.chargeLines[0].linkedItems.isEmpty)
    }

    @Test("Invoice line sums item project prices when items linked")
    func invoiceLineSumsItemPrices() {
        let transactions = [
            makeTransaction(
                id: "tx1", amountCents: 99999,
                reimbursementType: "owed-to-company",
                itemIds: ["item1", "item2"]
            ),
        ]
        let items = [
            makeItem(id: "item1", projectPriceCents: 3000),
            makeItem(id: "item2", projectPriceCents: 2000),
        ]

        let result = ReportAggregationCalculations.computeInvoiceReport(
            transactions: transactions, items: items, categories: []
        )

        #expect(result.chargeLines[0].amountCents == 5000)
    }

    // MARK: - Client Summary Tests

    @Test("Total spent sums project prices")
    func totalSpentSumsProjectPrices() {
        let items = [
            makeItem(id: "item1", projectPriceCents: 5000),
            makeItem(id: "item2", projectPriceCents: 3000),
            makeItem(id: "item3", projectPriceCents: nil),
        ]

        let result = ReportAggregationCalculations.computeClientSummary(
            items: items, transactions: [], spaces: [], categories: []
        )

        #expect(result.totalSpentCents == 8000)
    }

    @Test("Total saved only counts items where market value > 0")
    func totalSavedOnlyWhereMarketValuePositive() {
        let items = [
            makeItem(id: "item1", projectPriceCents: 5000, marketValueCents: 8000),
            makeItem(id: "item2", projectPriceCents: 3000, marketValueCents: 0),
            makeItem(id: "item3", projectPriceCents: 2000, marketValueCents: nil),
        ]

        let result = ReportAggregationCalculations.computeClientSummary(
            items: items, transactions: [], spaces: [], categories: []
        )

        // Only item1 has marketValue > 0: saved = 8000 - 5000 = 3000
        #expect(result.totalSavedCents == 3000)
    }

    @Test("Category resolved from transaction when item has no category")
    func categoryFromTransaction() {
        let items = [
            makeItem(
                id: "item1", projectPriceCents: 5000,
                transactionId: "tx1", budgetCategoryId: nil
            ),
        ]
        let transactions = [
            makeTransaction(id: "tx1", budgetCategoryId: "cat1"),
        ]
        let categories = [makeCategory(id: "cat1", name: "Furniture")]

        let result = ReportAggregationCalculations.computeClientSummary(
            items: items, transactions: transactions, spaces: [], categories: categories
        )

        #expect(result.categoryBreakdowns.count == 1)
        #expect(result.categoryBreakdowns[0].categoryName == "Furniture")
        #expect(result.categoryBreakdowns[0].spentCents == 5000)
    }

    @Test("Item category takes priority over transaction category")
    func itemCategoryPriority() {
        let items = [
            makeItem(
                id: "item1", projectPriceCents: 5000,
                transactionId: "tx1", budgetCategoryId: "cat2"
            ),
        ]
        let transactions = [
            makeTransaction(id: "tx1", budgetCategoryId: "cat1"),
        ]
        let categories = [
            makeCategory(id: "cat1", name: "Furniture"),
            makeCategory(id: "cat2", name: "Decor"),
        ]

        let result = ReportAggregationCalculations.computeClientSummary(
            items: items, transactions: transactions, spaces: [], categories: categories
        )

        #expect(result.categoryBreakdowns.count == 1)
        #expect(result.categoryBreakdowns[0].categoryName == "Decor")
    }

    @Test("Receipt link returns invoice for canonical inventory sale")
    func receiptLinkInvoice() {
        let item = makeItem(id: "item1", transactionId: "tx1")
        let transactions = [
            makeTransaction(id: "tx1", isCanonicalInventorySale: true),
        ]

        let txMap = Dictionary(
            transactions.compactMap { tx -> (String, Transaction)? in
                guard let id = tx.id else { return nil }
                return (id, tx)
            },
            uniquingKeysWith: { first, _ in first }
        )

        let link = ReportAggregationCalculations.getReceiptLink(item, transactionMap: txMap)
        if case .invoice = link {
            // pass
        } else {
            Issue.record("Expected .invoice, got \(link)")
        }
    }

    @Test("Receipt link returns receipt URL for transaction with receipt images")
    func receiptLinkURL() {
        let item = makeItem(id: "item1", transactionId: "tx1")
        let transactions = [
            makeTransaction(
                id: "tx1",
                receiptImages: [AttachmentRef(url: "https://example.com/receipt.jpg")]
            ),
        ]

        let txMap = Dictionary(
            transactions.compactMap { tx -> (String, Transaction)? in
                guard let id = tx.id else { return nil }
                return (id, tx)
            },
            uniquingKeysWith: { first, _ in first }
        )

        let link = ReportAggregationCalculations.getReceiptLink(item, transactionMap: txMap)
        if case .receiptURL(let url) = link {
            #expect(url == "https://example.com/receipt.jpg")
        } else {
            Issue.record("Expected .receiptURL, got \(link)")
        }
    }

    @Test("Receipt link returns none when no transaction linked")
    func receiptLinkNone() {
        let item = makeItem(id: "item1", transactionId: nil)

        let link = ReportAggregationCalculations.getReceiptLink(item, transactionMap: [:])
        if case .none = link {
            // pass
        } else {
            Issue.record("Expected .none, got \(link)")
        }
    }

    // MARK: - Property Management Tests

    @Test("Items grouped by space correctly")
    func groupsBySpace() {
        let items = [
            makeItem(id: "item1", spaceId: "space1"),
            makeItem(id: "item2", spaceId: "space1"),
            makeItem(id: "item3", spaceId: "space2"),
        ]
        let spaces = [
            makeSpace(id: "space1", name: "Living Room"),
            makeSpace(id: "space2", name: "Kitchen"),
        ]

        let result = ReportAggregationCalculations.computePropertyManagement(
            items: items, spaces: spaces
        )

        #expect(result.spaceGroups.count == 2)
        let livingRoom = result.spaceGroups.first { $0.space.name == "Living Room" }
        let kitchen = result.spaceGroups.first { $0.space.name == "Kitchen" }
        #expect(livingRoom?.items.count == 2)
        #expect(kitchen?.items.count == 1)
    }

    @Test("Items with nil spaceId go to noSpaceItems")
    func noSpaceGroup() {
        let items = [
            makeItem(id: "item1", spaceId: "space1"),
            makeItem(id: "item2", spaceId: nil),
            makeItem(id: "item3", spaceId: nil),
        ]
        let spaces = [makeSpace(id: "space1", name: "Living Room")]

        let result = ReportAggregationCalculations.computePropertyManagement(
            items: items, spaces: spaces
        )

        #expect(result.noSpaceItems.count == 2)
        #expect(result.spaceGroups.count == 1)
    }

    @Test("Total market value sums across all items")
    func totalMarketValue() {
        let items = [
            makeItem(id: "item1", marketValueCents: 5000, spaceId: "space1"),
            makeItem(id: "item2", marketValueCents: 3000, spaceId: nil),
            makeItem(id: "item3", marketValueCents: nil, spaceId: nil),
        ]
        let spaces = [makeSpace(id: "space1")]

        let result = ReportAggregationCalculations.computePropertyManagement(
            items: items, spaces: spaces
        )

        #expect(result.totalMarketValueCents == 8000)
        #expect(result.totalItemCount == 3)
    }
}
