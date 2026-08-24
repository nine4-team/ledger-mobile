import Foundation
import Testing
@testable import LedgeriOS

@Suite("Performance Diagnostics")
struct PerformanceDiagnosticsTests {
    @Test("Runtime gate accepts launch argument")
    func runtimeGateArgument() {
        #expect(PerformanceDiagnosticsConfiguration.isEnabled(
            arguments: ["Ledger", "-LedgerPerformanceDiagnostics", "YES"],
            environment: [:]
        ))
    }

    @Test("Runtime gate accepts environment variable")
    func runtimeGateEnvironment() {
        #expect(PerformanceDiagnosticsConfiguration.isEnabled(
            arguments: ["Ledger"],
            environment: ["LEDGER_PERFORMANCE_DIAGNOSTICS": "1"]
        ))
    }

    @Test("Runtime gate is disabled by default")
    func runtimeGateDefault() {
        #expect(!PerformanceDiagnosticsConfiguration.isEnabled(
            arguments: ["Ledger"],
            environment: [:]
        ))
    }

    @Test("Stall severity thresholds are deterministic")
    func stallSeverity() {
        #expect(MainThreadStallSeverity.classify(milliseconds: 249) == nil)
        #expect(MainThreadStallSeverity.classify(milliseconds: 250) == .notice)
        #expect(MainThreadStallSeverity.classify(milliseconds: 999) == .notice)
        #expect(MainThreadStallSeverity.classify(milliseconds: 1_000) == .severe)
        #expect(MainThreadStallSeverity.classify(milliseconds: 5_000) == .critical)
    }

    @Test("Ring buffer retains only newest events")
    func ringBufferCapacity() {
        var buffer = PerformanceDiagnosticRingBuffer(capacity: 2)
        for index in 0..<3 {
            buffer.append(PerformanceDiagnosticEvent(
                timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                name: "event-\(index)",
                kind: "test",
                count: index,
                value: 0,
                durationMilliseconds: nil
            ))
        }

        #expect(buffer.events.map(\.name) == ["event-1", "event-2"])
    }

    @Test("Disabled diagnostics retain no events or counters")
    func disabledDiagnostics() {
        let diagnostics = PerformanceDiagnostics(arguments: ["Ledger"], environment: [:])
        diagnostics.event("DisabledTest", kind: "test")
        diagnostics.adjustCounter("test-counter", delta: 1)
        var invocationCount = 0
        let result = diagnostics.measureAggregate("DisabledMeasure", kind: "test") {
            invocationCount += 1
            return 42
        }

        #expect(diagnostics.recentEvents().isEmpty)
        #expect(diagnostics.counterValue("test-counter") == 0)
        #expect(invocationCount == 1)
        #expect(result == 42)
    }

    @Test("Synthetic 668-item browsing cost profile")
    func syntheticBrowsingCostProfile() {
        let items = makeBrowsingItems(count: 668)
        let selectedIds = Set(items.prefix(20).compactMap(\.id))
        let spaces = makeBrowsingSpaces(count: 80)
        let categories = makeBrowsingCategories(count: 40)
        let invoices = makeBrowsingInvoices(items: items, count: 80)

        let pipeline = benchmark(iterations: 100) {
            ListFilterSortCalculations.applyAllMultiFilters(
                items,
                filters: [],
                sort: .createdDesc,
                search: ""
            ).count
        }
        let grouping = benchmark(iterations: 100) {
            ListFilterSortCalculations.groupItems(items).count
        }
        let selection = benchmark(iterations: 1_000) {
            let pairs = items.compactMap { item -> (id: String, cents: Int)? in
                guard let id = item.id, let cents = item.normalizedProjectPriceCents else { return nil }
                return (id, cents)
            }
            return SelectionCalculations.totalCentsForSelected(selectedIds: selectedIds, items: pairs)
        }
        let linearLookups = benchmark(iterations: 25) {
            browsingLinearLookupChecksum(items: items, spaces: spaces, categories: categories, invoices: invoices)
        }

        let spaceById = AccountLookupIndex.spaceNames(spaces)
        let categoryById = AccountLookupIndex.categoryNames(categories)
        let invoiceStatusByItemId = AccountLookupIndex.invoiceStatusesByItemId(invoices)
        let indexedLookups = benchmark(iterations: 25) {
            browsingIndexedLookupChecksum(
                items: items,
                spaceById: spaceById,
                categoryById: categoryById,
                invoiceStatusByItemId: invoiceStatusByItemId
            )
        }

        #expect(pipeline.result == 668)
        #expect(grouping.result > 0)
        #expect(selection.result > 0)
        #expect(linearLookups.result == indexedLookups.result)

        print(
            "BROWSING_BENCHMARK " +
            "items=668 " +
            "pipeline_ms=\(formatMilliseconds(pipeline.millisecondsPerIteration)) " +
            "grouping_ms=\(formatMilliseconds(grouping.millisecondsPerIteration)) " +
            "selection_ms=\(formatMilliseconds(selection.millisecondsPerIteration)) " +
            "linear_card_lookups_ms=\(formatMilliseconds(linearLookups.millisecondsPerIteration)) " +
            "indexed_card_lookups_ms=\(formatMilliseconds(indexedLookups.millisecondsPerIteration)) " +
            "lookup_speedup=\(String(format: "%.1f", linearLookups.millisecondsPerIteration / max(indexedLookups.millisecondsPerIteration, 0.000_001)))x"
        )
    }

    @Test("Account indexes preserve names and invoice status priority")
    func accountLookupIndexes() {
        let spaces = makeBrowsingSpaces(count: 2)
        let categories = makeBrowsingCategories(count: 2)
        var created = Invoice()
        created.status = .created
        created.itemIds = ["item-1", "item-created"]
        var paid = Invoice()
        paid.status = .paid
        paid.itemIds = ["item-1"]
        var sent = Invoice()
        sent.status = .sent
        sent.itemIds = ["item-1", "item-sent"]
        var canceled = Invoice()
        canceled.status = .canceled
        canceled.itemIds = ["item-canceled"]

        #expect(AccountLookupIndex.spaceNames(spaces)["space-1"] == "Space 1")
        #expect(AccountLookupIndex.categoryNames(categories)["category-1"] == "Category 1")

        let statuses = AccountLookupIndex.invoiceStatusesByItemId([created, paid, sent, canceled])
        #expect(statuses["item-1"] == .paid)
        #expect(statuses["item-created"] == .created)
        #expect(statuses["item-sent"] == .sent)
        #expect(statuses["item-canceled"] == nil)
    }

    @Test("Image cache charges decoded memory instead of compressed payload size")
    func imageCacheCostTracksMemoryFootprint() {
        let compressedBytes = 180_000
        let decodedBytes = 4_000 * 3_000 * 4

        #expect(ImageCache.cacheCost(
            decodedByteCount: decodedBytes,
            compressedByteCount: compressedBytes
        ) == decodedBytes)
        #expect(ImageCache.cacheCost(
            decodedByteCount: 0,
            compressedByteCount: compressedBytes
        ) == compressedBytes)
    }

    @Test("Synthetic account financial publication cost profile")
    func syntheticFinancialPublicationCostProfile() {
        let categories = makeFinancialCategories(count: 100)
        let transactions = makeFinancialTransactions(count: 2_000, categoryCount: categories.count)
        let invoices = makeFinancialInvoices(count: 200, transactions: transactions)
        let policy = FinancialAccessPolicy(
            access: .limited,
            allowedFeeCategoryIds: Set((0..<10).map { "category-\($0)" })
        )

        let visibleTransactions = benchmark(iterations: 10) {
            policy.visibleTransactions(transactions, categories: categories).count
        }
        let visibleInvoices = benchmark(iterations: 10) {
            policy.visibleInvoices(invoices, transactions: transactions, categories: categories).count
        }

        #expect(visibleTransactions.result > 0)
        #expect(visibleInvoices.result > 0)
        print(
            "FINANCIAL_PUBLICATION_BENCHMARK " +
            "transactions=2000 categories=100 invoices=200 " +
            "transaction_filter_ms=\(formatMilliseconds(visibleTransactions.millisecondsPerIteration)) " +
            "invoice_filter_ms=\(formatMilliseconds(visibleInvoices.millisecondsPerIteration))"
        )
    }
}

private func makeBrowsingItems(count: Int) -> [Item] {
    (0..<count).map { index in
        var item = Item()
        item.id = "item-\(index)"
        item.name = "Item \(index % 120)"
        item.sku = "SKU-\(index % 180)"
        item.source = "Vendor \(index % 30)"
        item.currentSource = item.source
        item.spaceId = "space-\(index % 80)"
        item.budgetCategoryId = "category-\(index % 40)"
        item.purchasePriceCents = 1_000 + index
        item.projectPriceCents = 1_500 + index
        item.createdAt = Date(timeIntervalSince1970: TimeInterval(index))
        return item
    }
}

private func makeBrowsingSpaces(count: Int) -> [Space] {
    (0..<count).map { index in
        var space = Space()
        space.id = "space-\(index)"
        space.name = "Space \(index)"
        return space
    }
}

private func makeBrowsingCategories(count: Int) -> [BudgetCategory] {
    (0..<count).map { index in
        var category = BudgetCategory()
        category.id = "category-\(index)"
        category.name = "Category \(index)"
        return category
    }
}

private func makeBrowsingInvoices(items: [Item], count: Int) -> [Invoice] {
    (0..<count).map { invoiceIndex in
        var invoice = Invoice()
        invoice.id = "invoice-\(invoiceIndex)"
        invoice.status = invoiceIndex.isMultiple(of: 3) ? .paid : .sent
        invoice.itemIds = stride(from: invoiceIndex, to: items.count, by: count)
            .compactMap { items[$0].id }
        return invoice
    }
}

private func makeFinancialCategories(count: Int) -> [BudgetCategory] {
    (0..<count).map { index in
        var category = BudgetCategory()
        category.id = "category-\(index)"
        category.name = "Category \(index)"
        category.metadata = BudgetCategoryMetadata(
            categoryType: index < 20 ? .fee : .general,
            excludeFromOverallBudget: false
        )
        return category
    }
}

private func makeFinancialTransactions(count: Int, categoryCount: Int) -> [Transaction] {
    (0..<count).map { index in
        var transaction = Transaction()
        transaction.id = "transaction-\(index)"
        transaction.transactionType = .purchase
        transaction.budgetCategoryId = "category-\(index % categoryCount)"
        transaction.amountCents = 1_000 + index
        return transaction
    }
}

private func makeFinancialInvoices(count: Int, transactions: [Transaction]) -> [Invoice] {
    (0..<count).map { invoiceIndex in
        var invoice = Invoice()
        invoice.id = "financial-invoice-\(invoiceIndex)"
        invoice.status = .sent
        invoice.transactionIds = (0..<10).compactMap { offset in
            transactions[(invoiceIndex * 10 + offset) % transactions.count].id
        }
        return invoice
    }
}

private func browsingLinearLookupChecksum(
    items: [Item],
    spaces: [Space],
    categories: [BudgetCategory],
    invoices: [Invoice]
) -> Int {
    items.reduce(into: 0) { checksum, item in
        if let spaceId = item.spaceId,
           let name = spaces.first(where: { $0.id == spaceId })?.name {
            checksum += name.count
        }
        if let categoryId = item.budgetCategoryId,
           let name = categories.first(where: { $0.id == categoryId })?.name {
            checksum += name.count
        }
        if let itemId = item.id,
           let status = firstNonCanceledInvoiceStatus(forItemId: itemId, in: invoices) {
            checksum += browsingInvoiceStatusWeight(status)
        }
    }
}

private func browsingIndexedLookupChecksum(
    items: [Item],
    spaceById: [String: String],
    categoryById: [String: String],
    invoiceStatusByItemId: [String: InvoiceStatus]
) -> Int {
    items.reduce(into: 0) { checksum, item in
        if let spaceId = item.spaceId, let name = spaceById[spaceId] {
            checksum += name.count
        }
        if let categoryId = item.budgetCategoryId, let name = categoryById[categoryId] {
            checksum += name.count
        }
        if let itemId = item.id, let status = invoiceStatusByItemId[itemId] {
            checksum += browsingInvoiceStatusWeight(status)
        }
    }
}

private func browsingInvoiceStatusWeight(_ status: InvoiceStatus) -> Int {
    switch status {
    case .created: 1
    case .sent: 2
    case .paid: 3
    case .canceled: 0
    }
}

private func benchmark<T>(iterations: Int, operation: () -> T) -> (result: T, millisecondsPerIteration: Double) {
    var result = operation()
    let startedAt = DispatchTime.now().uptimeNanoseconds
    for _ in 0..<iterations {
        result = operation()
    }
    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
    return (result, elapsed / Double(iterations))
}

private func formatMilliseconds(_ value: Double) -> String {
    String(format: "%.3f", value)
}
