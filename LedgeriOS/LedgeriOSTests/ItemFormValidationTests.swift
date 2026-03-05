import Foundation
import Testing
@testable import LedgeriOS

@Suite("Item Form Validation Tests")
struct ItemFormValidationTests {

    // MARK: - validateItem — OR condition (name OR images)

    @Test("Empty name with no images fails validation")
    func emptyNameNoImagesFails() {
        let errors = ItemFormValidation.validateItem(name: "", imageCount: 0)
        #expect(errors.contains(ValidationError(field: "name", message: "Add a name or at least one image")))
    }

    @Test("Whitespace-only name with no images fails validation")
    func whitespaceOnlyNameNoImagesFails() {
        let errors = ItemFormValidation.validateItem(name: "   ", imageCount: 0)
        #expect(errors.contains(ValidationError(field: "name", message: "Add a name or at least one image")))
    }

    @Test("Valid name with no images passes validation")
    func validNameNoImagesPasses() {
        let errors = ItemFormValidation.validateItem(name: "Marble Countertop", imageCount: 0)
        #expect(!errors.contains { $0.field == "name" })
    }

    @Test("Empty name with images passes validation")
    func emptyNameWithImagesPasses() {
        let errors = ItemFormValidation.validateItem(name: "", imageCount: 1)
        #expect(!errors.contains { $0.field == "name" })
    }

    @Test("Both name and images passes validation")
    func bothNameAndImagesPasses() {
        let errors = ItemFormValidation.validateItem(name: "Tile", imageCount: 3)
        #expect(errors.isEmpty)
    }

    // MARK: - validateItem — price validation

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

    @Test("Multiple errors returned for no name/images and negative price")
    func multipleErrors() {
        let errors = ItemFormValidation.validateItem(name: "", imageCount: 0, purchasePriceCents: -100)
        #expect(errors.count == 2)
    }

    // MARK: - isValidItem — OR condition

    @Test("isValidItem true with name only")
    func isValidItemNameOnly() {
        #expect(ItemFormValidation.isValidItem(name: "Marble Countertop", imageCount: 0))
    }

    @Test("isValidItem true with images only")
    func isValidItemImagesOnly() {
        #expect(ItemFormValidation.isValidItem(name: "", imageCount: 2))
    }

    @Test("isValidItem true with both name and images")
    func isValidItemBoth() {
        #expect(ItemFormValidation.isValidItem(name: "Tile", imageCount: 1))
    }

    @Test("isValidItem false with neither name nor images")
    func isValidItemNeither() {
        #expect(!ItemFormValidation.isValidItem(name: "", imageCount: 0))
    }

    @Test("isValidItem false with whitespace name and no images")
    func isValidItemWhitespaceNoImages() {
        #expect(!ItemFormValidation.isValidItem(name: "   ", imageCount: 0))
    }

    @Test("isValidItem with default imageCount (backward compat)")
    func isValidItemDefaultImageCount() {
        #expect(ItemFormValidation.isValidItem(name: "Tile"))
        #expect(!ItemFormValidation.isValidItem(name: ""))
    }
}
