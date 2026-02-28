import Foundation
import Testing
@testable import LedgeriOS

@Suite("Item Form Validation Tests")
struct ItemFormValidationTests {

    // MARK: - validateItem

    @Test("Empty name fails validation")
    func emptyNameFails() {
        let errors = ItemFormValidation.validateItem(name: "")
        #expect(errors.contains(ValidationError(field: "name", message: "Name is required")))
    }

    @Test("Whitespace-only name fails validation")
    func whitespaceOnlyNameFails() {
        let errors = ItemFormValidation.validateItem(name: "   ")
        #expect(errors.contains(ValidationError(field: "name", message: "Name is required")))
    }

    @Test("Valid name passes with no errors")
    func validItemPasses() {
        let errors = ItemFormValidation.validateItem(name: "Marble Countertop")
        #expect(errors.isEmpty)
    }

    @Test("Negative purchase price fails validation")
    func negativePurchasePriceFails() {
        let errors = ItemFormValidation.validateItem(name: "Tile", purchasePriceCents: -100)
        #expect(errors.contains(ValidationError(
            field: "purchasePrice",
            message: "Price must be zero or greater"
        )))
    }

    @Test("Negative project price fails validation")
    func negativeProjectPriceFails() {
        let errors = ItemFormValidation.validateItem(name: "Tile", projectPriceCents: -50)
        #expect(errors.contains(ValidationError(
            field: "projectPrice",
            message: "Price must be zero or greater"
        )))
    }

    @Test("Negative market value fails validation")
    func negativeMarketValueFails() {
        let errors = ItemFormValidation.validateItem(name: "Tile", marketValueCents: -200)
        #expect(errors.contains(ValidationError(
            field: "marketValue",
            message: "Price must be zero or greater"
        )))
    }

    @Test("Zero prices pass validation")
    func zeroPricesPass() {
        let errors = ItemFormValidation.validateItem(
            name: "Tile",
            purchasePriceCents: 0,
            projectPriceCents: 0,
            marketValueCents: 0
        )
        #expect(errors.isEmpty)
    }

    @Test("Positive prices pass validation")
    func positivePricesPass() {
        let errors = ItemFormValidation.validateItem(
            name: "Tile",
            purchasePriceCents: 5000,
            projectPriceCents: 7500,
            marketValueCents: 6000
        )
        #expect(errors.isEmpty)
    }

    @Test("Multiple errors returned for name and price")
    func multipleErrors() {
        let errors = ItemFormValidation.validateItem(name: "", purchasePriceCents: -100)
        #expect(errors.count == 2)
    }

    // MARK: - isValidItem

    @Test("isValidItem returns true for valid name")
    func isValidItemTrue() {
        #expect(ItemFormValidation.isValidItem(name: "Marble Countertop"))
    }

    @Test("isValidItem returns false for empty name")
    func isValidItemEmpty() {
        #expect(!ItemFormValidation.isValidItem(name: ""))
    }

    @Test("isValidItem returns false for whitespace-only name")
    func isValidItemWhitespace() {
        #expect(!ItemFormValidation.isValidItem(name: "  "))
    }
}
