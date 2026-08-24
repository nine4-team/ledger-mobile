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
        status: TransactionStatus? = nil,
        budgetCategoryId: String? = nil,
        itemIds: [String]? = nil,
        source: String? = "HomeGoods",
        transactionDate: String? = "2024-01-15",
        notes: String? = nil,
        isCanonicalInventorySale: Bool? = nil,
        inventorySaleDirection: InventorySaleDirection? = nil,
        receiptImages: [AttachmentRef]? = nil
    ) -> Transaction {
        var tx = Transaction()
        tx.id = id
        tx.amountCents = amountCents
        tx.reimbursementType = reimbursementType
        tx.status = status
        tx.budgetCategoryId = budgetCategoryId
        tx.itemIds = itemIds
        tx.source = source
        tx.transactionDate = transactionDate
        tx.notes = notes
        tx.isCanonicalInventorySale = isCanonicalInventorySale
        tx.inventorySaleDirection = inventorySaleDirection
        tx.receiptImages = receiptImages
        return tx
    }

    private func makeItem(
        id: String? = "item1",
        name: String = "Test Item",
        purchasePriceCents: Int? = nil,
        projectPriceCents: Int? = 5000,
        marketValueCents: Int? = 8000,
        spaceId: String? = nil,
        transactionId: String? = nil,
        budgetCategoryId: String? = nil,
        source: String? = nil,
        sku: String? = nil,
        status: ItemStatus? = nil
    ) -> Item {
        var item = Item()
        item.id = id
        item.name = name
        item.purchasePriceCents = purchasePriceCents
        item.projectPriceCents = projectPriceCents
        item.marketValueCents = marketValueCents
        item.spaceId = spaceId
        item.transactionId = transactionId
        item.budgetCategoryId = budgetCategoryId
        item.source = source
        item.sku = sku
        item.status = status
        return item
    }

    private func makeSpace(id: String? = "space1", name: String = "Living Room") -> Space {
        var space = Space()
        space.id = id
        space.name = name
        return space
    }

    private func makeCategory(
        id: String = "cat1",
        name: String = "Furniture",
        categoryType: BudgetCategoryType? = nil
    ) -> BudgetCategory {
        var cat = BudgetCategory()
        cat.id = id
        cat.name = name
        if let categoryType {
            cat.metadata = BudgetCategoryMetadata(categoryType: categoryType, excludeFromOverallBudget: nil)
        }
        return cat
    }

    // MARK: - Invoice Report Tests

    @Test("Canceled transactions excluded from invoice")
    func canceledTransactionExcluded() {
        let transactions = [
            makeTransaction(id: "tx1", amountCents: 5000, reimbursementType: "owed-to-company", status: .canceled, itemIds: ["item1"]),
            makeTransaction(id: "tx2", reimbursementType: "owed-to-company", itemIds: ["item2"]),
        ]
        let items = [
            makeItem(id: "item1", name: "Canceled Chair", projectPriceCents: 5000),
            makeItem(id: "item2", name: "Good Chair", projectPriceCents: 3000),
        ]

        let result = ReportAggregationCalculations.computeInvoiceReport(
            transactions: transactions, items: items, categories: []
        )

        #expect(result.chargeLines.count == 1)
        #expect(result.chargeLines[0].name == "Good Chair")
    }

    @Test("Items from charge transactions appear as charges, credits as credits")
    func itemsSplitByDirection() {
        let transactions = [
            makeTransaction(id: "tx1", reimbursementType: "owed-to-company", itemIds: ["item1", "item2"]),
            makeTransaction(id: "tx2", reimbursementType: "owed-to-client", itemIds: ["item3"]),
        ]
        let items = [
            makeItem(id: "item1", name: "Sofa", projectPriceCents: 5000),
            makeItem(id: "item2", name: "Table", projectPriceCents: 3000),
            makeItem(id: "item3", name: "Returned Lamp", projectPriceCents: 2000),
        ]

        let result = ReportAggregationCalculations.computeInvoiceReport(
            transactions: transactions, items: items, categories: []
        )

        #expect(result.chargeLines.count == 2)
        #expect(result.creditLines.count == 1)
        #expect(result.chargesSubtotalCents == 8000)
        #expect(result.creditsSubtotalCents == 2000)
        #expect(result.netDueCents == 6000)
    }

    @Test("Transaction with no items uses transaction amount as a line")
    func transactionWithNoItemsBecomesLine() {
        let transactions = [
            makeTransaction(id: "tx1", amountCents: 7500, reimbursementType: "owed-to-company", source: "Design Fee"),
        ]

        let result = ReportAggregationCalculations.computeInvoiceReport(
            transactions: transactions, items: [], categories: []
        )

        #expect(result.chargeLines.count == 1)
        #expect(result.chargeLines[0].name == "Design Fee")
        #expect(result.chargeLines[0].priceCents == 7500)
        #expect(result.chargeLines[0].isMissingPrice == false)
    }

    @Test("Legacy project prices normalize to the purchase-price floor")
    func missingProjectPriceFallback() {
        let transactions = [
            makeTransaction(id: "tx1", reimbursementType: "owed-to-company", itemIds: ["item1", "item2", "item3"]),
        ]
        let items = [
            makeItem(id: "item1", name: "Has Project Price", purchasePriceCents: 3000, projectPriceCents: 5000),
            makeItem(id: "item2", name: "No Project Price", purchasePriceCents: 2000, projectPriceCents: nil),
            makeItem(id: "item3", name: "Zero Project Price", purchasePriceCents: 1500, projectPriceCents: 0),
        ]

        let result = ReportAggregationCalculations.computeInvoiceReport(
            transactions: transactions, items: items, categories: []
        )

        let hasProject = result.chargeLines.first { $0.name == "Has Project Price" }
        let noProject = result.chargeLines.first { $0.name == "No Project Price" }
        let zeroProject = result.chargeLines.first { $0.name == "Zero Project Price" }
        #expect(hasProject?.priceCents == 5000)
        #expect(hasProject?.isMissingPrice == false)
        #expect(noProject?.priceCents == 2000)
        #expect(noProject?.isMissingPrice == false)
        #expect(zeroProject?.priceCents == 1500)
        #expect(zeroProject?.isMissingPrice == false)
    }

    @Test("Transactions without reimbursement direction excluded from invoice")
    func noDirectionExcluded() {
        let transactions = [
            makeTransaction(id: "tx1", amountCents: 5000, reimbursementType: nil),
        ]

        let result = ReportAggregationCalculations.computeInvoiceReport(
            transactions: transactions, items: [], categories: []
        )

        #expect(result.chargeLines.isEmpty)
        #expect(result.creditLines.isEmpty)
    }

    @Test("Canonical sale items appear as charges or credits based on direction")
    func canonicalSaleItemsByDirection() {
        let transactions = [
            makeTransaction(
                id: "sale1", itemIds: ["item1"],
                isCanonicalInventorySale: true,
                inventorySaleDirection: .businessToProject
            ),
            makeTransaction(
                id: "sale2", itemIds: ["item2"],
                isCanonicalInventorySale: true,
                inventorySaleDirection: .projectToBusiness
            ),
        ]
        let items = [
            makeItem(id: "item1", name: "Sold Chair", projectPriceCents: 4000),
            makeItem(id: "item2", name: "Returned Table", projectPriceCents: 6000),
        ]

        let result = ReportAggregationCalculations.computeInvoiceReport(
            transactions: transactions, items: items, categories: []
        )

        #expect(result.chargeLines.count == 1)
        #expect(result.chargeLines[0].name == "Sold Chair")
        #expect(result.chargeLines[0].priceCents == 4000)
        #expect(result.creditLines.count == 1)
        #expect(result.creditLines[0].name == "Returned Table")
        #expect(result.creditLines[0].priceCents == 6000)
    }

    @Test("Canceled canonical sale excluded from invoice")
    func canceledCanonicalSaleExcluded() {
        let transactions = [
            makeTransaction(
                id: "sale1", status: .canceled, itemIds: ["item1"],
                isCanonicalInventorySale: true,
                inventorySaleDirection: .businessToProject
            ),
        ]
        let items = [
            makeItem(id: "item1", name: "Chair", projectPriceCents: 5000),
        ]

        let result = ReportAggregationCalculations.computeInvoiceReport(
            transactions: transactions, items: items, categories: []
        )

        #expect(result.chargeLines.isEmpty)
        #expect(result.creditLines.isEmpty)
    }

    @Test("Items sorted by name within each section")
    func itemsSortedByName() {
        let transactions = [
            makeTransaction(id: "tx1", reimbursementType: "owed-to-company", itemIds: ["item1", "item2", "item3"]),
        ]
        let items = [
            makeItem(id: "item1", name: "Zebra Rug", projectPriceCents: 1000),
            makeItem(id: "item2", name: "Armchair", projectPriceCents: 2000),
            makeItem(id: "item3", name: "Lamp", projectPriceCents: 3000),
        ]

        let result = ReportAggregationCalculations.computeInvoiceReport(
            transactions: transactions, items: items, categories: []
        )

        #expect(result.chargeLines.map(\.name) == ["Armchair", "Lamp", "Zebra Rug"])
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

    @Test("Client price falls back to purchase price when project price is nil")
    func clientPriceFallsBackToPurchasePrice() {
        let items = [
            makeItem(id: "item1", purchasePriceCents: 2000, projectPriceCents: 5000),
            makeItem(id: "item2", purchasePriceCents: 3000, projectPriceCents: nil),
            makeItem(id: "item3", purchasePriceCents: nil, projectPriceCents: nil),
        ]

        let result = ReportAggregationCalculations.computeClientSummary(
            items: items, transactions: [], spaces: [], categories: []
        )

        // item1: 5000 (project price wins), item2: 3000 (fallback), item3: 0
        #expect(result.totalSpentCents == 8000)
    }

    @Test("clientPriceCents prefers project price over purchase price")
    func clientPriceCentsPreference() {
        let item = makeItem(purchasePriceCents: 2000, projectPriceCents: 5000)
        #expect(ReportAggregationCalculations.clientPriceCents(for: item) == 5000)
    }

    @Test("clientPriceCents falls back to purchase price")
    func clientPriceCentsFallback() {
        let item = makeItem(purchasePriceCents: 3000, projectPriceCents: nil)
        #expect(ReportAggregationCalculations.clientPriceCents(for: item) == 3000)
    }

    @Test("clientPriceCents returns 0 when both nil")
    func clientPriceCentsBothNil() {
        let item = makeItem(purchasePriceCents: nil, projectPriceCents: nil)
        #expect(ReportAggregationCalculations.clientPriceCents(for: item) == 0)
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

    @Test("Returned items excluded from client summary totals")
    func returnedItemsExcludedFromClientSummary() {
        let items = [
            makeItem(id: "item1", projectPriceCents: 5000, marketValueCents: 8000, status: .purchased),
            makeItem(id: "item2", projectPriceCents: 3000, marketValueCents: 6000, status: .returned),
            makeItem(id: "item3", projectPriceCents: 2000, marketValueCents: 4000, status: .toReturn),
        ]

        let result = ReportAggregationCalculations.computeClientSummary(
            items: items, transactions: [], spaces: [], categories: []
        )

        // item2 (returned) excluded; item1 + item3 included
        #expect(result.totalSpentCents == 7000)
        #expect(result.totalMarketValueCents == 12000)
        #expect(result.items.count == 2)
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

    @Test("Items with orphaned spaceId (not in spaces array) fall back to noSpaceItems")
    func orphanedSpaceIdFallsBackToNoSpace() {
        let items = [
            makeItem(id: "item1", spaceId: "space1"),
            makeItem(id: "item2", spaceId: "space-deleted"),
            makeItem(id: "item3", spaceId: nil),
        ]
        let spaces = [makeSpace(id: "space1", name: "Living Room")]

        let result = ReportAggregationCalculations.computePropertyManagement(
            items: items, spaces: spaces
        )

        #expect(result.spaceGroups.count == 1)
        #expect(result.spaceGroups[0].items.count == 1)
        // Both nil-spaceId and orphaned-spaceId items end up in noSpaceItems
        #expect(result.noSpaceItems.count == 2)
        #expect(result.totalItemCount == 3)
    }

    @Test("Total market value sums across all items using fallback chain")
    func totalMarketValue() {
        let items = [
            makeItem(id: "item1", marketValueCents: 5000, spaceId: "space1"),
            makeItem(id: "item2", projectPriceCents: 3000, marketValueCents: nil, spaceId: nil),
            makeItem(id: "item3", purchasePriceCents: 1000, projectPriceCents: nil, marketValueCents: nil, spaceId: nil),
        ]
        let spaces = [makeSpace(id: "space1")]

        let result = ReportAggregationCalculations.computePropertyManagement(
            items: items, spaces: spaces
        )

        // 5000 (market) + 3000 (project fallback) + 1000 (purchase fallback)
        #expect(result.totalMarketValueCents == 9000)
        #expect(result.totalItemCount == 3)
    }

    @Test("Returned items excluded from property management")
    func returnedItemsExcludedFromPropertyManagement() {
        let items = [
            makeItem(id: "item1", marketValueCents: 5000, spaceId: "space1", status: .purchased),
            makeItem(id: "item2", marketValueCents: 3000, spaceId: "space1", status: .returned),
            makeItem(id: "item3", marketValueCents: 2000, spaceId: nil, status: .returned),
        ]
        let spaces = [makeSpace(id: "space1", name: "Living Room")]

        let result = ReportAggregationCalculations.computePropertyManagement(
            items: items, spaces: spaces
        )

        #expect(result.totalItemCount == 1)
        #expect(result.totalMarketValueCents == 5000)
        #expect(result.spaceGroups[0].items.count == 1)
        #expect(result.noSpaceItems.count == 0)
    }

    // MARK: - propertyValueCents Fallback Chain

    @Test("propertyValueCents returns market value when present")
    func propertyValueReturnsMarketValue() {
        let item = makeItem(purchasePriceCents: 1000, projectPriceCents: 2000, marketValueCents: 5000)
        #expect(ReportAggregationCalculations.propertyValueCents(for: item) == 5000)
    }

    @Test("propertyValueCents falls back to project price when no market value")
    func propertyValueFallsBackToProjectPrice() {
        let item = makeItem(purchasePriceCents: 1000, projectPriceCents: 2000, marketValueCents: nil)
        #expect(ReportAggregationCalculations.propertyValueCents(for: item) == 2000)
    }

    @Test("propertyValueCents falls back to purchase price when no market value or project price")
    func propertyValueFallsBackToPurchasePrice() {
        let item = makeItem(purchasePriceCents: 1000, projectPriceCents: nil, marketValueCents: nil)
        #expect(ReportAggregationCalculations.propertyValueCents(for: item) == 1000)
    }

    @Test("propertyValueCents returns 0 when all prices are nil")
    func propertyValueReturnsZeroWhenAllNil() {
        let item = makeItem(purchasePriceCents: nil, projectPriceCents: nil, marketValueCents: nil)
        #expect(ReportAggregationCalculations.propertyValueCents(for: item) == 0)
    }

    @Test("SpaceGroup marketValueCents uses fallback chain")
    func spaceGroupUsesPropertyValueFallback() {
        let items = [
            makeItem(id: "item1", marketValueCents: 5000),
            makeItem(id: "item2", projectPriceCents: 3000, marketValueCents: nil),
            makeItem(id: "item3", purchasePriceCents: 1000, projectPriceCents: nil, marketValueCents: nil),
        ]
        var space = Space()
        space.id = "space1"
        space.name = "Living Room"
        let group = SpaceGroup(space: space, items: items)

        #expect(group.marketValueCents == 9000)
    }

    // MARK: - Reimbursement Direction Tests

    @Test("reimbursementDirection returns owedToCompany for explicit reimbursement type")
    func directionExplicitOwedToCompany() {
        let tx = makeTransaction(reimbursementType: "owed-to-company")
        #expect(ReportAggregationCalculations.reimbursementDirection(for: tx) == .owedToCompany)
    }

    @Test("reimbursementDirection returns owedToClient for explicit reimbursement type")
    func directionExplicitOwedToClient() {
        let tx = makeTransaction(reimbursementType: "owed-to-client")
        #expect(ReportAggregationCalculations.reimbursementDirection(for: tx) == .owedToClient)
    }

    @Test("reimbursementDirection returns owedToCompany for business-to-project canonical sale")
    func directionCanonicalSaleBusinessToProject() {
        let tx = makeTransaction(
            reimbursementType: nil,
            isCanonicalInventorySale: true,
            inventorySaleDirection: .businessToProject
        )
        #expect(ReportAggregationCalculations.reimbursementDirection(for: tx) == .owedToCompany)
    }

    @Test("reimbursementDirection returns owedToClient for project-to-business canonical sale")
    func directionCanonicalSaleProjectToBusiness() {
        let tx = makeTransaction(
            reimbursementType: nil,
            isCanonicalInventorySale: true,
            inventorySaleDirection: .projectToBusiness
        )
        #expect(ReportAggregationCalculations.reimbursementDirection(for: tx) == .owedToClient)
    }

    @Test("reimbursementDirection returns nil for transaction with no reimbursement info")
    func directionNilForPlainTransaction() {
        let tx = makeTransaction(reimbursementType: nil, isCanonicalInventorySale: nil)
        #expect(ReportAggregationCalculations.reimbursementDirection(for: tx) == nil)
    }

    @Test("Explicit reimbursementType takes priority over canonical sale direction")
    func directionExplicitOverridesCanonical() {
        let tx = makeTransaction(
            reimbursementType: "owed-to-client",
            isCanonicalInventorySale: true,
            inventorySaleDirection: .businessToProject
        )
        // Explicit says owed-to-client, even though direction says businessToProject
        #expect(ReportAggregationCalculations.reimbursementDirection(for: tx) == .owedToClient)
    }

}
