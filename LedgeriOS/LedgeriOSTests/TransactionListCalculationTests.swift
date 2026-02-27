import Foundation
import Testing
@testable import LedgeriOS

@Suite("Transaction List Calculation Tests")
struct TransactionListCalculationTests {

    // MARK: - Helpers

    private func makeTransaction(
        id: String? = nil,
        source: String? = nil,
        transactionType: String? = nil,
        status: String? = nil,
        reimbursementType: String? = nil,
        hasEmailReceipt: Bool? = nil,
        receiptImages: [AttachmentRef]? = nil,
        budgetCategoryId: String? = nil,
        purchasedBy: String? = nil,
        amountCents: Int? = nil,
        transactionDate: String? = nil,
        notes: String? = nil
    ) -> Transaction {
        var txn = Transaction()
        txn.id = id
        txn.source = source
        txn.transactionType = transactionType
        txn.status = status
        txn.reimbursementType = reimbursementType
        txn.hasEmailReceipt = hasEmailReceipt
        txn.receiptImages = receiptImages
        txn.budgetCategoryId = budgetCategoryId
        txn.purchasedBy = purchasedBy
        txn.amountCents = amountCents
        txn.transactionDate = transactionDate
        txn.notes = notes
        return txn
    }

    // MARK: - Status Filter

    @Test("Filter by status")
    func filterStatus() {
        let txns = [
            makeTransaction(id: "1", status: "pending"),
            makeTransaction(id: "2", status: "completed"),
            makeTransaction(id: "3", status: "pending"),
        ]
        var filter = TransactionListCalculations.TransactionFilter()
        filter.statusValues = ["pending"]
        let result = TransactionListCalculations.applyFilters(txns, filter: filter)
        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.status == "pending" })
    }

    // MARK: - Reimbursement Filter

    @Test("Filter by reimbursement type")
    func filterReimbursement() {
        let txns = [
            makeTransaction(id: "1", reimbursementType: "owed-to-client"),
            makeTransaction(id: "2", reimbursementType: "owed-to-company"),
            makeTransaction(id: "3"),
        ]
        var filter = TransactionListCalculations.TransactionFilter()
        filter.reimbursementValues = ["owed-to-client"]
        let result = TransactionListCalculations.applyFilters(txns, filter: filter)
        #expect(result.count == 1)
        #expect(result[0].id == "1")
    }

    // MARK: - Has Receipt Filter

    @Test("Filter by has receipt")
    func filterHasReceipt() {
        let ref = AttachmentRef(url: "https://example.com/receipt.jpg")
        let txns = [
            makeTransaction(id: "1", receiptImages: [ref]),
            makeTransaction(id: "2", hasEmailReceipt: true),
            makeTransaction(id: "3"),
        ]
        var filter = TransactionListCalculations.TransactionFilter()
        filter.hasReceipt = true
        let result = TransactionListCalculations.applyFilters(txns, filter: filter)
        #expect(result.count == 2)
    }

    @Test("Filter by no receipt")
    func filterNoReceipt() {
        let ref = AttachmentRef(url: "https://example.com/receipt.jpg")
        let txns = [
            makeTransaction(id: "1", receiptImages: [ref]),
            makeTransaction(id: "2"),
        ]
        var filter = TransactionListCalculations.TransactionFilter()
        filter.hasReceipt = false
        let result = TransactionListCalculations.applyFilters(txns, filter: filter)
        #expect(result.count == 1)
        #expect(result[0].id == "2")
    }

    // MARK: - Type Filter

    @Test("Filter by transaction type")
    func filterType() {
        let txns = [
            makeTransaction(id: "1", transactionType: "purchase"),
            makeTransaction(id: "2", transactionType: "sale"),
            makeTransaction(id: "3", transactionType: "return"),
        ]
        var filter = TransactionListCalculations.TransactionFilter()
        filter.typeValues = ["purchase", "return"]
        let result = TransactionListCalculations.applyFilters(txns, filter: filter)
        #expect(result.count == 2)
    }

    // MARK: - Budget Category Filter

    @Test("Filter by budget category ID")
    func filterCategory() {
        let txns = [
            makeTransaction(id: "1", budgetCategoryId: "cat1"),
            makeTransaction(id: "2", budgetCategoryId: "cat2"),
            makeTransaction(id: "3"),
        ]
        var filter = TransactionListCalculations.TransactionFilter()
        filter.budgetCategoryId = "cat1"
        let result = TransactionListCalculations.applyFilters(txns, filter: filter)
        #expect(result.count == 1)
        #expect(result[0].id == "1")
    }

    // MARK: - Purchased By Filter

    @Test("Filter by purchased by")
    func filterPurchasedBy() {
        let txns = [
            makeTransaction(id: "1", purchasedBy: "client-card"),
            makeTransaction(id: "2", purchasedBy: "design-business"),
            makeTransaction(id: "3"),
        ]
        var filter = TransactionListCalculations.TransactionFilter()
        filter.purchasedByValues = ["missing"]
        let result = TransactionListCalculations.applyFilters(txns, filter: filter)
        #expect(result.count == 1)
        #expect(result[0].id == "3")
    }

    // MARK: - Source Filter

    @Test("Filter by source")
    func filterSource() {
        let txns = [
            makeTransaction(id: "1", source: "HomeGoods"),
            makeTransaction(id: "2", source: "Target"),
            makeTransaction(id: "3", source: "HomeGoods"),
        ]
        var filter = TransactionListCalculations.TransactionFilter()
        filter.sourceValues = ["homegoods"]
        let result = TransactionListCalculations.applyFilters(txns, filter: filter)
        #expect(result.count == 2)
    }

    // MARK: - No Active Filter

    @Test("Empty filter returns all transactions")
    func emptyFilter() {
        let txns = [makeTransaction(id: "1"), makeTransaction(id: "2")]
        let filter = TransactionListCalculations.TransactionFilter()
        let result = TransactionListCalculations.applyFilters(txns, filter: filter)
        #expect(result.count == 2)
    }

    // MARK: - Search

    @Test("Search by source text")
    func searchSource() {
        let txns = [
            makeTransaction(id: "1", source: "HomeGoods"),
            makeTransaction(id: "2", source: "Target"),
        ]
        let result = TransactionListCalculations.applySearch(txns, query: "home")
        #expect(result.count == 1)
        #expect(result[0].id == "1")
    }

    @Test("Search by notes")
    func searchNotes() {
        let txns = [
            makeTransaction(id: "1", notes: "Living room furniture"),
            makeTransaction(id: "2", notes: "Kitchen supplies"),
        ]
        let result = TransactionListCalculations.applySearch(txns, query: "furniture")
        #expect(result.count == 1)
    }

    @Test("Search by transaction type label")
    func searchTypeLabel() {
        let txns = [
            makeTransaction(id: "1", transactionType: "purchase"),
            makeTransaction(id: "2", transactionType: "sale"),
        ]
        let result = TransactionListCalculations.applySearch(txns, query: "Purchase")
        #expect(result.count == 1)
        #expect(result[0].id == "1")
    }

    @Test("Search by formatted amount")
    func searchAmount() {
        let txns = [
            makeTransaction(id: "1", amountCents: 4999),
            makeTransaction(id: "2", amountCents: 12500),
        ]
        let result = TransactionListCalculations.applySearch(txns, query: "$49.99")
        #expect(result.count == 1)
        #expect(result[0].id == "1")
    }

    @Test("Empty search returns all")
    func searchEmpty() {
        let txns = [makeTransaction(id: "1"), makeTransaction(id: "2")]
        let result = TransactionListCalculations.applySearch(txns, query: "  ")
        #expect(result.count == 2)
    }

    // MARK: - Sorting

    @Test("Sort by date descending, nil dates last")
    func sortDateDesc() {
        let txns = [
            makeTransaction(id: "1", transactionDate: "2024-01-01"),
            makeTransaction(id: "2", transactionDate: nil),
            makeTransaction(id: "3", transactionDate: "2024-06-15"),
        ]
        let result = TransactionListCalculations.applySort(txns, sort: .dateDesc)
        #expect(result[0].id == "3")
        #expect(result[1].id == "1")
        #expect(result[2].id == "2") // nil last
    }

    @Test("Sort by date ascending, nil dates last")
    func sortDateAsc() {
        let txns = [
            makeTransaction(id: "1", transactionDate: "2024-06-15"),
            makeTransaction(id: "2", transactionDate: nil),
            makeTransaction(id: "3", transactionDate: "2024-01-01"),
        ]
        let result = TransactionListCalculations.applySort(txns, sort: .dateAsc)
        #expect(result[0].id == "3")
        #expect(result[1].id == "1")
        #expect(result[2].id == "2") // nil last
    }

    @Test("Sort by amount descending")
    func sortAmountDesc() {
        let txns = [
            makeTransaction(id: "1", amountCents: 1000),
            makeTransaction(id: "2", amountCents: 5000),
            makeTransaction(id: "3", amountCents: 2500),
        ]
        let result = TransactionListCalculations.applySort(txns, sort: .amountDesc)
        #expect(result[0].id == "2")
        #expect(result[1].id == "3")
        #expect(result[2].id == "1")
    }

    @Test("Sort by source ascending")
    func sortSourceAsc() {
        let txns = [
            makeTransaction(id: "1", source: "Target"),
            makeTransaction(id: "2", source: "HomeGoods"),
            makeTransaction(id: "3", source: nil),
        ]
        let result = TransactionListCalculations.applySort(txns, sort: .sourceAsc)
        #expect(result[0].id == "2") // HomeGoods
        #expect(result[1].id == "1") // Target
        #expect(result[2].id == "3") // nil last
    }

    // MARK: - Unique Sources

    @Test("Unique sources returns sorted, non-empty sources")
    func uniqueSources() {
        let txns = [
            makeTransaction(source: "HomeGoods"),
            makeTransaction(source: "Target"),
            makeTransaction(source: "HomeGoods"),
            makeTransaction(source: nil),
            makeTransaction(source: "  "),
        ]
        let sources = TransactionListCalculations.uniqueSources(from: txns)
        #expect(sources == ["HomeGoods", "Target"])
    }

    // MARK: - Combined Pipeline

    @Test("filterAndSort applies filter, search, and sort together")
    func combinedPipeline() {
        let txns = [
            makeTransaction(id: "1", source: "HomeGoods", transactionType: "purchase", amountCents: 5000, transactionDate: "2024-01-01"),
            makeTransaction(id: "2", source: "Target", transactionType: "sale", amountCents: 3000, transactionDate: "2024-06-15"),
            makeTransaction(id: "3", source: "HomeGoods", transactionType: "purchase", amountCents: 8000, transactionDate: "2024-03-10"),
        ]
        var filter = TransactionListCalculations.TransactionFilter()
        filter.typeValues = ["purchase"]
        let result = TransactionListCalculations.filterAndSort(
            transactions: txns,
            filter: filter,
            sort: .dateDesc,
            query: "home"
        )
        #expect(result.count == 2)
        #expect(result[0].id == "3") // Mar 10 before Jan 1
        #expect(result[1].id == "1")
    }
}
