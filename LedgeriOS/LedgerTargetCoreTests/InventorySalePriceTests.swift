import Testing
@testable import LedgerTargetCore

@Suite("Inventory destination sale price")
struct InventorySalePriceTests {
    @Test("Current Inventory prices preserve unset versus zero without allowing free sales")
    func currentInventoryPrice() throws {
        let usd = try CurrencyCode(validating: "USD")
        for (project, cost, expected): (Int64?, Int64?, Int64?) in [
            (nil, nil, nil), (nil, 0, nil), (0, nil, 0), (0, 0, 0),
            (nil, 100, 100), (0, 100, 100), (50, 100, 100),
            (200, 100, 200), (Int64.max, 100, Int64.max)
        ] {
            let price = project.map { InventorySalePrice.Evidence.known(.init(minorUnits: $0, currency: usd)) } ?? .confirmedAbsent
            let purchase = cost.map { InventorySalePrice.Evidence.known(.init(minorUnits: $0, currency: usd)) } ?? .confirmedAbsent
            #expect(try InventorySalePrice.reviewCurrentPrice(projectPrice: price, purchaseCost: purchase,
                currency: usd)?.minorUnits == expected)
            if (expected ?? 0) == 0 {
                #expect(throws: InventorySalePrice.Failure.priceRequired) {
                    try InventorySalePrice.review(projectPrice: price, purchaseCost: purchase, currency: usd)
                }
            }
        }
        #expect(throws: InventorySalePrice.Failure.evidenceUnavailable) {
            try InventorySalePrice.reviewCurrentPrice(projectPrice: .confirmedAbsent,
                purchaseCost: .unavailable, currency: usd)
        }
    }
    @Test func exactPriceEntry() throws {
        let usd = try CurrencyCode(validating: "USD")
        for (text,amount): (String,Int64) in [("1",100),("1.2",120),(" 1.25 ",125),("$1,234.56",123456),(".50",50),("1.",100),("92233720368547758.07",Int64.max)] {
            #expect(try InventorySalePrice.parseEntry(text,currency: usd).minorUnits == amount)
        }
        for text in ["", "0", ".", "1,2", "-1", "1.234", "1e3", "NaN", "92233720368547758.08", "999999999999999999999999", "1.2x"] {
            #expect(throws: InventorySalePrice.Failure.priceRequired) { try InventorySalePrice.parseEntry(text,currency: usd) }
        }
    }
    @Test("Incomplete downloads cannot masquerade as absent price or cost")
    func incompleteReview() throws {
        let usd = try CurrencyCode(validating: "USD")
        let known = InventorySalePrice.Evidence.known(Money(minorUnits: 100, currency: usd))
        for evidence in [InventorySalePrice.Evidence.confirmedAbsent, known, .unavailable] {
            #expect(throws: InventorySalePrice.Failure.evidenceUnavailable) {
                try InventorySalePrice.review(projectPrice: evidence, purchaseCost: .unavailable, currency: usd)
            }
            #expect(throws: InventorySalePrice.Failure.evidenceUnavailable) {
                try InventorySalePrice.review(projectPrice: .unavailable, purchaseCost: evidence, currency: usd)
            }
        }
        #expect(try InventorySalePrice.review(projectPrice: .confirmedAbsent, purchaseCost: known, currency: usd).minorUnits == 100)
        #expect(throws: InventorySalePrice.Failure.priceRequired) {
            try InventorySalePrice.review(projectPrice: .confirmedAbsent, purchaseCost: .confirmedAbsent, currency: usd)
        }
    }
    @Test("Preserve markup and floor missing or lower project prices at cost")
    func floor() throws {
        let usd = try CurrencyCode(validating: "USD")
        for (project, cost, expected): (Int64?, Int64?, Int64) in [
            (nil, 100, 100), (0, 100, 100), (50, 100, 100),
            (200, 100, 200), (200, nil, 200), (-50, 100, 100),
            (Int64.max, 100, Int64.max)
        ] {
            let result = try InventorySalePrice.review(
                projectPrice: project.map { .known(Money(minorUnits: $0, currency: usd)) } ?? .confirmedAbsent,
                purchaseCost: cost.map { .known(Money(minorUnits: $0, currency: usd)) } ?? .confirmedAbsent, currency: usd)
            #expect(result == Money(minorUnits: expected, currency: usd))
        }
    }

    @Test("No positive price requires review; mixed currencies are never compared")
    func rejectedEvidence() throws {
        let usd = try CurrencyCode(validating: "USD")
        let eur = try CurrencyCode(validating: "EUR")
        #expect(throws: InventorySalePrice.Failure.priceRequired) {
            try InventorySalePrice.review(projectPrice: .confirmedAbsent, purchaseCost: .confirmedAbsent, currency: usd)
        }
        #expect(throws: InventorySalePrice.Failure.priceRequired) {
            try InventorySalePrice.review(projectPrice: .known(.init(minorUnits: 0, currency: usd)),
                purchaseCost: .known(.init(minorUnits: -1, currency: usd)), currency: usd)
        }
        #expect(throws: InventorySalePrice.Failure.currencyMismatch) {
            try InventorySalePrice.review(projectPrice: .known(.init(minorUnits: 200, currency: usd)),
                purchaseCost: .known(.init(minorUnits: 100, currency: eur)), currency: usd)
        }
    }
}
