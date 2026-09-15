import Foundation

/// Backend-independent input to the existing Invoice screen and PDF report.
struct InvoiceLineEntry {
    let name: String
    let priceCents: Decimal
    let isMissingPrice: Bool
    let categoryId: String?
    let categoryName: String?

    init(name: String, priceCents: Int, isMissingPrice: Bool) {
        self.init(name: name, exactPriceCents: Decimal(priceCents), isMissingPrice: isMissingPrice)
    }

    init(name: String, exactPriceCents: Decimal, isMissingPrice: Bool,
         categoryId: String? = nil, categoryName: String? = nil) {
        self.name = name
        self.priceCents = exactPriceCents
        self.isMissingPrice = isMissingPrice
        self.categoryId = categoryId
        self.categoryName = categoryName
    }
}

struct InvoiceReportData {
    struct Group {
        let categoryId: String?
        let categoryName: String?
        var lines: [InvoiceLineEntry]
        var subtotalCents: Decimal { lines.reduce(0) { $0 + $1.priceCents } }
    }

    /// Stable first-appearance order; equal/missing names never merge different
    /// category identities. Legacy inputs without a category remain ungrouped.
    static func groups(_ lines: [InvoiceLineEntry]) -> [Group] {
        var groups: [Group] = []
        var indices: [[UInt8]?: Int] = [:]
        for line in lines {
            let key = line.categoryId.map { Array($0.utf8) }
            if let index = indices[key] { groups[index].lines.append(line) }
            else {
                indices[key] = groups.count
                groups.append(Group(categoryId: line.categoryId, categoryName: line.categoryName, lines: [line]))
            }
        }
        return groups
    }
    let chargeLines: [InvoiceLineEntry]
    let creditLines: [InvoiceLineEntry]
    var chargesSubtotalCents: Decimal { chargeLines.reduce(0) { $0 + $1.priceCents } }
    var creditsSubtotalCents: Decimal { creditLines.reduce(0) { $0 + $1.priceCents } }
    var netDueCents: Decimal { chargesSubtotalCents - creditsSubtotalCents }
    var hasFallbackPrices: Bool {
        chargeLines.contains { $0.isMissingPrice } || creditLines.contains { $0.isMissingPrice }
    }
}
