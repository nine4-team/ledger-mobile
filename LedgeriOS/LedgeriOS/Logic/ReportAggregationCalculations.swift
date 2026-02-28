import Foundation

// MARK: - Invoice Report Types

struct InvoiceLineItem {
    let transaction: Transaction
    let displayName: String
    let formattedDate: String
    let notes: String?
    let amountCents: Int
    let categoryName: String?
    let linkedItems: [InvoiceItem]
    let isMissingProjectPrices: Bool
}

struct InvoiceItem {
    let name: String?
    let projectPriceCents: Int?
    let isMissingPrice: Bool
}

struct InvoiceReportData {
    let chargeLines: [InvoiceLineItem]
    let creditLines: [InvoiceLineItem]
    var chargesSubtotalCents: Int { chargeLines.reduce(0) { $0 + $1.amountCents } }
    var creditsSubtotalCents: Int { creditLines.reduce(0) { $0 + $1.amountCents } }
    var netDueCents: Int { chargesSubtotalCents - creditsSubtotalCents }
}

// MARK: - Client Summary Types

struct ClientSummaryData {
    let totalSpentCents: Int
    let totalMarketValueCents: Int
    let totalSavedCents: Int
    let categoryBreakdowns: [CategoryBreakdown]
    let items: [ClientSummaryItem]
}

struct CategoryBreakdown {
    let categoryName: String
    let spentCents: Int
}

struct ClientSummaryItem {
    let item: Item
    let spaceName: String?
    let receiptLink: ReceiptLink
}

enum ReceiptLink {
    case invoice
    case receiptURL(String)
    case none
}

// MARK: - Property Management Types

struct PropertyManagementData {
    let spaceGroups: [SpaceGroup]
    let noSpaceItems: [Item]
    let totalItemCount: Int
    let totalMarketValueCents: Int
}

struct SpaceGroup {
    let space: Space
    let items: [Item]
    var marketValueCents: Int { items.reduce(0) { $0 + ($1.marketValueCents ?? 0) } }
}

// MARK: - Aggregation Functions

enum ReportAggregationCalculations {

    // MARK: - Invoice Report

    static func computeInvoiceReport(
        transactions: [Transaction],
        items: [Item],
        categories: [BudgetCategory]
    ) -> InvoiceReportData {
        let categoryMap = Dictionary(
            categories.compactMap { cat -> (String, BudgetCategory)? in
                guard let id = cat.id else { return nil }
                return (id, cat)
            },
            uniquingKeysWith: { first, _ in first }
        )

        let active = transactions.filter { $0.isCanceled != true }

        let charges = active
            .filter { $0.reimbursementType == "owed-to-company" }
            .sorted { compareDatesAscending($0.transactionDate, $1.transactionDate) }

        let credits = active
            .filter { $0.reimbursementType == "owed-to-client" }
            .sorted { compareDatesAscending($0.transactionDate, $1.transactionDate) }

        let chargeLines = charges.map { buildInvoiceLine($0, items: items, categoryMap: categoryMap) }
        let creditLines = credits.map { buildInvoiceLine($0, items: items, categoryMap: categoryMap) }

        return InvoiceReportData(chargeLines: chargeLines, creditLines: creditLines)
    }

    private static func buildInvoiceLine(
        _ transaction: Transaction,
        items: [Item],
        categoryMap: [String: BudgetCategory]
    ) -> InvoiceLineItem {
        let txItemIds = transaction.itemIds ?? []
        let linkedItems = items.filter { item in
            guard let itemId = item.id else { return false }
            return txItemIds.contains(itemId)
        }

        let hasItems = !linkedItems.isEmpty
        var amountCents: Int
        var invoiceItems: [InvoiceItem] = []
        var hasMissingPrices = false

        if hasItems {
            amountCents = 0
            for item in linkedItems {
                let priceCents = item.projectPriceCents ?? 0
                let isMissing = item.projectPriceCents == nil || item.projectPriceCents == 0
                if isMissing { hasMissingPrices = true }
                amountCents += priceCents
                invoiceItems.append(InvoiceItem(
                    name: item.name,
                    projectPriceCents: item.projectPriceCents,
                    isMissingPrice: isMissing
                ))
            }
        } else {
            amountCents = transaction.amountCents ?? 0
        }

        let categoryId = transaction.budgetCategoryId
        let categoryName = categoryId.flatMap { categoryMap[$0]?.name }

        let displayName = transaction.source ?? "Transaction"
        let formattedDate = transaction.transactionDate ?? ""

        return InvoiceLineItem(
            transaction: transaction,
            displayName: displayName,
            formattedDate: formattedDate,
            notes: transaction.notes,
            amountCents: amountCents,
            categoryName: categoryName,
            linkedItems: invoiceItems,
            isMissingProjectPrices: hasMissingPrices
        )
    }

    private static func compareDatesAscending(_ a: String?, _ b: String?) -> Bool {
        switch (a, b) {
        case (nil, nil): return false
        case (nil, _): return true
        case (_, nil): return false
        case let (a?, b?): return a < b
        }
    }

    // MARK: - Client Summary

    static func computeClientSummary(
        items: [Item],
        transactions: [Transaction],
        spaces: [Space],
        categories: [BudgetCategory]
    ) -> ClientSummaryData {
        let transactionMap = Dictionary(
            transactions.compactMap { tx -> (String, Transaction)? in
                guard let id = tx.id else { return nil }
                return (id, tx)
            },
            uniquingKeysWith: { first, _ in first }
        )

        let categoryMap = Dictionary(
            categories.compactMap { cat -> (String, BudgetCategory)? in
                guard let id = cat.id else { return nil }
                return (id, cat)
            },
            uniquingKeysWith: { first, _ in first }
        )

        let spaceMap = Dictionary(
            spaces.compactMap { s -> (String, Space)? in
                guard let id = s.id else { return nil }
                return (id, s)
            },
            uniquingKeysWith: { first, _ in first }
        )

        let totalSpentCents = items.reduce(0) { $0 + ($1.projectPriceCents ?? 0) }
        let totalMarketValueCents = items.reduce(0) { $0 + ($1.marketValueCents ?? 0) }

        let totalSavedCents = items.reduce(0) { sum, item in
            let marketValue = item.marketValueCents ?? 0
            let projectPrice = item.projectPriceCents ?? 0
            guard marketValue > 0 else { return sum }
            return sum + (marketValue - projectPrice)
        }

        // Category breakdown
        var categoryTotals: [String: Int] = [:]
        for item in items {
            let categoryId = resolveItemCategoryId(item, transactionMap: transactionMap)
            if let categoryId {
                let categoryName = categoryMap[categoryId]?.name ?? "Unknown Category"
                categoryTotals[categoryName, default: 0] += item.projectPriceCents ?? 0
            }
        }

        let categoryBreakdowns = categoryTotals
            .map { CategoryBreakdown(categoryName: $0.key, spentCents: $0.value) }
            .sorted { $0.categoryName < $1.categoryName }

        // Build item list with receipt links
        let clientItems = items.map { item in
            ClientSummaryItem(
                item: item,
                spaceName: item.spaceId.flatMap { spaceMap[$0]?.name },
                receiptLink: getReceiptLink(item, transactionMap: transactionMap)
            )
        }

        return ClientSummaryData(
            totalSpentCents: totalSpentCents,
            totalMarketValueCents: totalMarketValueCents,
            totalSavedCents: totalSavedCents,
            categoryBreakdowns: categoryBreakdowns,
            items: clientItems
        )
    }

    static func resolveItemCategoryId(
        _ item: Item,
        transactionMap: [String: Transaction]
    ) -> String? {
        if let categoryId = item.budgetCategoryId {
            return categoryId
        }
        if let txId = item.transactionId,
           let tx = transactionMap[txId],
           let txCategoryId = tx.budgetCategoryId {
            return txCategoryId
        }
        return nil
    }

    static func getReceiptLink(
        _ item: Item,
        transactionMap: [String: Transaction]
    ) -> ReceiptLink {
        guard let txId = item.transactionId,
              let tx = transactionMap[txId] else {
            return .none
        }

        let isCanonical = tx.isCanonicalInventorySale == true
        let isInvoiceable = tx.reimbursementType == "owed-to-company"
            || tx.reimbursementType == "owed-to-client"

        if isCanonical || isInvoiceable {
            return .invoice
        }

        if let receiptUrl = tx.receiptImages?.first?.url,
           !receiptUrl.hasPrefix("offline://") {
            return .receiptURL(receiptUrl)
        }

        return .none
    }

    // MARK: - Property Management

    static func computePropertyManagement(
        items: [Item],
        spaces: [Space]
    ) -> PropertyManagementData {
        let spaceMap = Dictionary(
            spaces.compactMap { s -> (String, Space)? in
                guard let id = s.id else { return nil }
                return (id, s)
            },
            uniquingKeysWith: { first, _ in first }
        )

        var grouped: [String: [Item]] = [:]
        var noSpaceItems: [Item] = []

        for item in items {
            if let spaceId = item.spaceId {
                grouped[spaceId, default: []].append(item)
            } else {
                noSpaceItems.append(item)
            }
        }

        let spaceGroups = grouped.compactMap { spaceId, groupItems -> SpaceGroup? in
            guard let space = spaceMap[spaceId] else { return nil }
            return SpaceGroup(space: space, items: groupItems)
        }
        .sorted { ($0.space.name) < ($1.space.name) }

        let totalMarketValueCents = items.reduce(0) { $0 + ($1.marketValueCents ?? 0) }

        return PropertyManagementData(
            spaceGroups: spaceGroups,
            noSpaceItems: noSpaceItems,
            totalItemCount: items.count,
            totalMarketValueCents: totalMarketValueCents
        )
    }
}
