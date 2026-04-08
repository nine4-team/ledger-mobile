import Foundation

// MARK: - Invoice Report Types

/// A single line on the invoice — either an item or a non-item transaction.
struct InvoiceLineEntry {
    let name: String
    let priceCents: Int
    let isMissingPrice: Bool
}

struct InvoiceReportData {
    let chargeLines: [InvoiceLineEntry]
    let creditLines: [InvoiceLineEntry]
    var chargesSubtotalCents: Int { chargeLines.reduce(0) { $0 + $1.priceCents } }
    var creditsSubtotalCents: Int { creditLines.reduce(0) { $0 + $1.priceCents } }
    var netDueCents: Int { chargesSubtotalCents - creditsSubtotalCents }
    var hasFallbackPrices: Bool {
        chargeLines.contains { $0.isMissingPrice } || creditLines.contains { $0.isMissingPrice }
    }
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
    var marketValueCents: Int { items.reduce(0) { $0 + ReportAggregationCalculations.propertyValueCents(for: $1) } }
}

// MARK: - Reimbursement Direction

/// Unified direction derived from explicit `reimbursementType` OR canonical sale direction.
enum ReimbursementDirection {
    case owedToCompany
    case owedToClient
}

// MARK: - Aggregation Functions

enum ReportAggregationCalculations {

    /// Determines reimbursement direction from explicit field or canonical sale direction.
    static func reimbursementDirection(for tx: Transaction) -> ReimbursementDirection? {
        if tx.reimbursementType == "owed-to-company" { return .owedToCompany }
        if tx.reimbursementType == "owed-to-client" { return .owedToClient }

        if tx.isCanonicalInventorySale == true {
            switch tx.inventorySaleDirection {
            case .businessToProject: return .owedToCompany
            case .projectToBusiness: return .owedToClient
            case nil: return nil
            }
        }

        return nil
    }

    // MARK: - Invoice Report

    static func computeInvoiceReport(
        transactions: [Transaction],
        items: [Item],
        categories: [BudgetCategory]
    ) -> InvoiceReportData {
        // Fee categories (categoryType == .fee) represent income received from the client,
        // not charges passed through to them. They are intentionally excluded from the invoice.
        let feeCategoryIds = Set(
            categories.compactMap { cat -> String? in
                guard cat.metadata?.categoryType == .fee, let id = cat.id else { return nil }
                return id
            }
        )

        let active = transactions.filter { tx in
            guard tx.status != .canceled else { return false }
            if let catId = tx.budgetCategoryId, feeCategoryIds.contains(catId) { return false }
            return true
        }

        let itemMap = Dictionary(
            items.compactMap { item -> (String, Item)? in
                guard let id = item.id else { return nil }
                return (id, item)
            },
            uniquingKeysWith: { first, _ in first }
        )

        var chargeLines: [InvoiceLineEntry] = []
        var creditLines: [InvoiceLineEntry] = []
        for tx in active {
            guard let direction = reimbursementDirection(for: tx) else { continue }

            let txItemIds = tx.itemIds ?? []
            let linkedItems = txItemIds.compactMap { itemMap[$0] }

            if linkedItems.isEmpty {
                // Non-item transaction (e.g., service fee) — use transaction amount
                let entry = InvoiceLineEntry(
                    name: tx.source ?? tx.notes ?? "Adjustment",
                    priceCents: tx.amountCents ?? 0,
                    isMissingPrice: false
                )
                switch direction {
                case .owedToCompany: chargeLines.append(entry)
                case .owedToClient: creditLines.append(entry)
                }
            } else {
                // Flatten items as individual line entries
                for item in linkedItems {
                    let projectPrice = item.projectPriceCents ?? 0
                    let priceCents = projectPrice > 0
                        ? projectPrice
                        : (item.purchasePriceCents ?? 0)
                    let isMissing = projectPrice == 0
                    let entry = InvoiceLineEntry(
                        name: item.displayName.isEmpty ? "Unnamed Item" : item.displayName,
                        priceCents: priceCents,
                        isMissingPrice: isMissing
                    )
                    switch direction {
                    case .owedToCompany: chargeLines.append(entry)
                    case .owedToClient: creditLines.append(entry)
                    }
                }
            }
        }

        chargeLines.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        creditLines.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return InvoiceReportData(
            chargeLines: chargeLines,
            creditLines: creditLines
        )
    }

    /// Per-invoice aggregation: builds an InvoiceReportData containing exactly the
    /// items and non-itemized expenses referenced by the given Invoice. Credits are
    /// unused on this path (per-invoice billing is charges-only).
    static func computeInvoiceReport(
        for invoice: Invoice,
        items: [Item],
        transactions: [Transaction]
    ) -> InvoiceReportData {
        let itemMap = Dictionary(
            items.compactMap { item -> (String, Item)? in
                guard let id = item.id else { return nil }
                return (id, item)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let txMap = Dictionary(
            transactions.compactMap { tx -> (String, Transaction)? in
                guard let id = tx.id else { return nil }
                return (id, tx)
            },
            uniquingKeysWith: { first, _ in first }
        )

        var chargeLines: [InvoiceLineEntry] = []

        for itemId in invoice.itemIds ?? [] {
            guard let item = itemMap[itemId] else { continue }
            let projectPrice = item.projectPriceCents ?? 0
            let priceCents = projectPrice > 0 ? projectPrice : (item.purchasePriceCents ?? 0)
            let isMissing = projectPrice == 0
            chargeLines.append(InvoiceLineEntry(
                name: item.displayName.isEmpty ? "Unnamed Item" : item.displayName,
                priceCents: priceCents,
                isMissingPrice: isMissing
            ))
        }

        for txId in invoice.transactionIds ?? [] {
            guard let tx = txMap[txId] else { continue }
            chargeLines.append(InvoiceLineEntry(
                name: tx.source ?? tx.notes ?? "Adjustment",
                priceCents: tx.amountCents ?? 0,
                isMissingPrice: false
            ))
        }

        chargeLines.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return InvoiceReportData(chargeLines: chargeLines, creditLines: [])
    }

    // MARK: - Client Summary

    /// Project price with fallback to purchase price for client-facing reports.
    static func clientPriceCents(for item: Item) -> Int {
        item.projectPriceCents ?? item.purchasePriceCents ?? 0
    }

    static func computeClientSummary(
        items: [Item],
        transactions: [Transaction],
        spaces: [Space],
        categories: [BudgetCategory]
    ) -> ClientSummaryData {
        // Exclude returned items — they stayed in the project (projectId unchanged)
        // but shouldn't appear in client-facing reports. Sold items are already
        // excluded at the Firestore query level (projectId is cleared on sell).
        let activeItems = items.filter { $0.status != .returned }

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

        let totalSpentCents = activeItems.reduce(0) { $0 + clientPriceCents(for: $1) }
        let totalMarketValueCents = activeItems.reduce(0) { $0 + ($1.marketValueCents ?? 0) }

        let totalSavedCents = activeItems.reduce(0) { sum, item in
            let marketValue = item.marketValueCents ?? 0
            let clientPrice = clientPriceCents(for: item)
            guard marketValue > 0 else { return sum }
            return sum + (marketValue - clientPrice)
        }

        // Category breakdown
        var categoryTotals: [String: Int] = [:]
        for item in activeItems {
            let categoryId = resolveItemCategoryId(item, transactionMap: transactionMap)
            if let categoryId {
                let categoryName = categoryMap[categoryId]?.name ?? "Unknown Category"
                categoryTotals[categoryName, default: 0] += clientPriceCents(for: item)
            }
        }

        let categoryBreakdowns = categoryTotals
            .map { CategoryBreakdown(categoryName: $0.key, spentCents: $0.value) }
            .sorted { $0.categoryName < $1.categoryName }

        // Build item list with receipt links
        let clientItems = activeItems.map { item in
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

    /// Market value with fallback to project price, then purchase price.
    static func propertyValueCents(for item: Item) -> Int {
        item.marketValueCents ?? item.projectPriceCents ?? item.purchasePriceCents ?? 0
    }

    static func computePropertyManagement(
        items: [Item],
        spaces: [Space]
    ) -> PropertyManagementData {
        let activeItems = items.filter { $0.status != .returned }

        let spaceMap = Dictionary(
            spaces.compactMap { s -> (String, Space)? in
                guard let id = s.id else { return nil }
                return (id, s)
            },
            uniquingKeysWith: { first, _ in first }
        )

        var grouped: [String: [Item]] = [:]
        var noSpaceItems: [Item] = []

        for item in activeItems {
            if let spaceId = item.spaceId {
                grouped[spaceId, default: []].append(item)
            } else {
                noSpaceItems.append(item)
            }
        }

        var spaceGroupsArray: [SpaceGroup] = []
        for (spaceId, groupItems) in grouped {
            if let space = spaceMap[spaceId] {
                spaceGroupsArray.append(SpaceGroup(space: space, items: groupItems))
            } else {
                noSpaceItems.append(contentsOf: groupItems)
            }
        }
        let spaceGroups = spaceGroupsArray.sorted { $0.space.name < $1.space.name }

        let totalMarketValueCents = activeItems.reduce(0) { $0 + propertyValueCents(for: $1) }

        return PropertyManagementData(
            spaceGroups: spaceGroups,
            noSpaceItems: noSpaceItems,
            totalItemCount: activeItems.count,
            totalMarketValueCents: totalMarketValueCents
        )
    }
}
