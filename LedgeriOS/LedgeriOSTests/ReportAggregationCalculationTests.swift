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
        sku: String? = nil
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

    @Test("Canceled transactions are excluded from invoice report")
    func canceledTransactionExcluded() {
        let transactions = [
            makeTransaction(id: "tx1", reimbursementType: "owed-to-company", status: .canceled),
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

    @Test("Invoice line uses transaction amount even when items are linked")
    func invoiceLineUsesTransactionAmountWithItems() {
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

        // Amount comes from transaction, not item sum
        #expect(result.chargeLines[0].amountCents == 99999)
        // Items are still listed for informational breakdown
        #expect(result.chargeLines[0].linkedItems.count == 2)
    }

    @Test("Canonical sale business_to_project appears as charge")
    func canonicalSaleBusinessToProjectIsCharge() {
        let transactions = [
            makeTransaction(
                id: "SALE_proj1_business_to_project_cat1",
                amountCents: 8000,
                isCanonicalInventorySale: true,
                inventorySaleDirection: .businessToProject
            ),
        ]

        let result = ReportAggregationCalculations.computeInvoiceReport(
            transactions: transactions, items: [], categories: []
        )

        #expect(result.chargeLines.count == 1)
        #expect(result.creditLines.isEmpty)
        #expect(result.chargeLines[0].transaction.id == "SALE_proj1_business_to_project_cat1")
    }

    @Test("Canonical sale project_to_business appears as credit")
    func canonicalSaleProjectToBusinessIsCredit() {
        let transactions = [
            makeTransaction(
                id: "SALE_proj1_project_to_business_cat1",
                amountCents: 5000,
                isCanonicalInventorySale: true,
                inventorySaleDirection: .projectToBusiness
            ),
        ]

        let result = ReportAggregationCalculations.computeInvoiceReport(
            transactions: transactions, items: [], categories: []
        )

        #expect(result.creditLines.count == 1)
        #expect(result.chargeLines.isEmpty)
        #expect(result.creditLines[0].transaction.id == "SALE_proj1_project_to_business_cat1")
    }

    @Test("Canonical sales and reimbursement transactions combine on invoice")
    func canonicalSalesAndReimbursementCombine() {
        let transactions = [
            makeTransaction(id: "tx1", amountCents: 5000, reimbursementType: "owed-to-company"),
            makeTransaction(
                id: "SALE_proj1_business_to_project_cat1",
                amountCents: 3000,
                isCanonicalInventorySale: true,
                inventorySaleDirection: .businessToProject
            ),
            makeTransaction(id: "tx2", amountCents: 2000, reimbursementType: "owed-to-client"),
            makeTransaction(
                id: "SALE_proj1_project_to_business_cat1",
                amountCents: 1000,
                isCanonicalInventorySale: true,
                inventorySaleDirection: .projectToBusiness
            ),
        ]

        let result = ReportAggregationCalculations.computeInvoiceReport(
            transactions: transactions, items: [], categories: []
        )

        #expect(result.chargeLines.count == 2)
        #expect(result.creditLines.count == 2)
        #expect(result.chargesSubtotalCents == 8000)
        #expect(result.creditsSubtotalCents == 3000)
        #expect(result.netDueCents == 5000)
    }

    @Test("Canceled canonical sale excluded from invoice")
    func canceledCanonicalSaleExcluded() {
        let transactions = [
            makeTransaction(
                id: "SALE_proj1_business_to_project_cat1",
                amountCents: 5000,
                status: .canceled,
                isCanonicalInventorySale: true,
                inventorySaleDirection: .businessToProject
            ),
        ]

        let result = ReportAggregationCalculations.computeInvoiceReport(
            transactions: transactions, items: [], categories: []
        )

        #expect(result.chargeLines.isEmpty)
        #expect(result.creditLines.isEmpty)
    }

    @Test("Canonical sale with linked items uses transaction amount")
    func canonicalSaleWithLinkedItemsUsesTransactionAmount() {
        let transactions = [
            makeTransaction(
                id: "SALE_proj1_business_to_project_cat1",
                amountCents: 10000,
                itemIds: ["item1", "item2"],
                isCanonicalInventorySale: true,
                inventorySaleDirection: .businessToProject
            ),
        ]
        let items = [
            makeItem(id: "item1", projectPriceCents: 4000),
            makeItem(id: "item2", projectPriceCents: 6000),
        ]

        let result = ReportAggregationCalculations.computeInvoiceReport(
            transactions: transactions, items: items, categories: []
        )

        #expect(result.chargeLines.count == 1)
        #expect(result.chargeLines[0].amountCents == 10000)
        #expect(result.chargeLines[0].linkedItems.count == 2)
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

    // MARK: - Invoice with Canonical Sales

    @Test("Canonical business-to-project sale appears as charge in invoice")
    func canonicalSaleAppearsAsCharge() {
        let transactions = [
            makeTransaction(
                id: "sale1", amountCents: 15000,
                isCanonicalInventorySale: true,
                inventorySaleDirection: .businessToProject
            ),
        ]

        let result = ReportAggregationCalculations.computeInvoiceReport(
            transactions: transactions, items: [], categories: []
        )

        #expect(result.chargeLines.count == 1)
        #expect(result.creditLines.count == 0)
        #expect(result.chargesSubtotalCents == 15000)
    }

    @Test("Canonical project-to-business sale appears as credit in invoice")
    func canonicalSaleAppearsAsCredit() {
        let transactions = [
            makeTransaction(
                id: "sale1", amountCents: 8000,
                isCanonicalInventorySale: true,
                inventorySaleDirection: .projectToBusiness
            ),
        ]

        let result = ReportAggregationCalculations.computeInvoiceReport(
            transactions: transactions, items: [], categories: []
        )

        #expect(result.chargeLines.count == 0)
        #expect(result.creditLines.count == 1)
        #expect(result.creditsSubtotalCents == 8000)
    }

    @Test("Invoice mixes reimbursement and canonical sale transactions")
    func invoiceMixesReimbursementAndCanonicalSales() {
        let transactions = [
            makeTransaction(id: "tx1", amountCents: 5000, reimbursementType: "owed-to-company"),
            makeTransaction(
                id: "sale1", amountCents: 12000,
                isCanonicalInventorySale: true,
                inventorySaleDirection: .businessToProject
            ),
            makeTransaction(id: "tx2", amountCents: 3000, reimbursementType: "owed-to-client"),
        ]

        let result = ReportAggregationCalculations.computeInvoiceReport(
            transactions: transactions, items: [], categories: []
        )

        #expect(result.chargeLines.count == 2)
        #expect(result.creditLines.count == 1)
        #expect(result.chargesSubtotalCents == 17000)
        #expect(result.creditsSubtotalCents == 3000)
        #expect(result.netDueCents == 14000)
    }

    // MARK: - Invoice Display Name

    @Test("Invoice display name shows vendor for regular transactions")
    func invoiceDisplayNameRegular() {
        let tx = makeTransaction(source: "Wayfair")
        #expect(ReportAggregationCalculations.invoiceDisplayName(for: tx) == "Wayfair")
    }

    @Test("Invoice display name for business-to-project canonical sale")
    func invoiceDisplayNameBusinessToProject() {
        let tx = makeTransaction(
            source: "Wayfair",
            isCanonicalInventorySale: true,
            inventorySaleDirection: .businessToProject
        )
        #expect(ReportAggregationCalculations.invoiceDisplayName(for: tx) == "Design Business Inventory Sale")
    }

    @Test("Invoice display name for project-to-business canonical sale")
    func invoiceDisplayNameProjectToBusiness() {
        let tx = makeTransaction(
            source: "Wayfair",
            isCanonicalInventorySale: true,
            inventorySaleDirection: .projectToBusiness
        )
        #expect(ReportAggregationCalculations.invoiceDisplayName(for: tx) == "Design Business Inventory Purchase")
    }
}
