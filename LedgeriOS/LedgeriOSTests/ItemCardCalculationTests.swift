import Foundation
import SwiftUI
import Testing
@testable import LedgeriOS

@Suite("Item Card Calculation Tests")
struct ItemCardCalculationTests {

    // MARK: - badgeItems

    @Test("All badge fields present returns 3 badges")
    func badgeItemsAllPresent() {
        let badges = ItemCardCalculations.badgeItems(
            statusLabel: "Purchased",
            budgetCategoryName: "Furnishings",
            indexLabel: "1/4"
        )
        #expect(badges.count == 3)
        #expect(badges[0].text == "1/4")
        #expect(badges[1].text == "Furnishings")
        #expect(badges[2].text == "Purchased")
    }

    @Test("Only status label returns 1 badge")
    func badgeItemsOnlyStatus() {
        let badges = ItemCardCalculations.badgeItems(
            statusLabel: "Active",
            budgetCategoryName: nil,
            indexLabel: nil
        )
        #expect(badges.count == 1)
        #expect(badges[0].text == "Active")
    }

    @Test("Only category returns 1 badge")
    func badgeItemsOnlyCategory() {
        let badges = ItemCardCalculations.badgeItems(
            statusLabel: nil,
            budgetCategoryName: "Kitchen",
            indexLabel: nil
        )
        #expect(badges.count == 1)
        #expect(badges[0].text == "Kitchen")
    }

    @Test("All nil returns empty array")
    func badgeItemsAllNil() {
        let badges = ItemCardCalculations.badgeItems(
            statusLabel: nil,
            budgetCategoryName: nil,
            indexLabel: nil
        )
        #expect(badges.isEmpty)
    }

    @Test("Empty strings treated as nil")
    func badgeItemsEmptyStrings() {
        let badges = ItemCardCalculations.badgeItems(
            statusLabel: "",
            budgetCategoryName: "",
            indexLabel: ""
        )
        #expect(badges.isEmpty)
    }

    // MARK: - metadataLines

    @Test("All metadata fields returns expected lines (stacked)")
    func metadataLinesAllFieldsStacked() {
        let lines = ItemCardCalculations.metadataLines(
            name: "Gold vase",
            sku: "400293670643",
            sourceLabel: "Ross",
            locationLabel: "Living Room",
            priceLabel: "$10.99",
            stackSkuAndSource: true
        )
        #expect(lines.count == 4)
        #expect(lines[0] == "$10.99")
        #expect(lines[1] == "Source: Ross")
        #expect(lines[2] == "SKU: 400293670643")
        #expect(lines[3] == "Location: Living Room")
    }

    @Test("All metadata fields combined (not stacked)")
    func metadataLinesAllFieldsCombined() {
        let lines = ItemCardCalculations.metadataLines(
            name: "Gold vase",
            sku: "400293670643",
            sourceLabel: "Ross",
            locationLabel: "Living Room",
            priceLabel: "$10.99",
            stackSkuAndSource: false
        )
        #expect(lines.count == 3)
        #expect(lines[0] == "$10.99")
        #expect(lines[1] == "SKU: 400293670643 · Source: Ross")
        #expect(lines[2] == "Location: Living Room")
    }

    @Test("Some nil fields filtered out")
    func metadataLinesSomeNil() {
        let lines = ItemCardCalculations.metadataLines(
            name: "Pillow",
            sku: nil,
            sourceLabel: "Homegoods",
            locationLabel: nil,
            priceLabel: "$24.99",
            stackSkuAndSource: true
        )
        #expect(lines.count == 2)
        #expect(lines[0] == "$24.99")
        #expect(lines[1] == "Source: Homegoods")
    }

    @Test("All nil returns empty")
    func metadataLinesAllNil() {
        let lines = ItemCardCalculations.metadataLines(
            name: nil,
            sku: nil,
            sourceLabel: nil,
            locationLabel: nil,
            priceLabel: nil,
            stackSkuAndSource: true
        )
        #expect(lines.isEmpty)
    }

    @Test("Only SKU with combined mode")
    func metadataLinesOnlySkuCombined() {
        let lines = ItemCardCalculations.metadataLines(
            name: nil,
            sku: "ABC123",
            sourceLabel: nil,
            locationLabel: nil,
            priceLabel: nil,
            stackSkuAndSource: false
        )
        #expect(lines.count == 1)
        #expect(lines[0] == "SKU: ABC123")
    }

    @Test("Only source with combined mode")
    func metadataLinesOnlySourceCombined() {
        let lines = ItemCardCalculations.metadataLines(
            name: nil,
            sku: nil,
            sourceLabel: "Target",
            locationLabel: nil,
            priceLabel: nil,
            stackSkuAndSource: false
        )
        #expect(lines.count == 1)
        #expect(lines[0] == "Source: Target")
    }

    // MARK: - thumbnailUrl

    @Test("Valid URL string returns URL")
    func thumbnailUrlValid() {
        let url = ItemCardCalculations.thumbnailUrl(from: "https://example.com/image.jpg")
        #expect(url != nil)
        #expect(url?.absoluteString == "https://example.com/image.jpg")
    }

    @Test("Nil returns nil")
    func thumbnailUrlNil() {
        let url = ItemCardCalculations.thumbnailUrl(from: nil)
        #expect(url == nil)
    }

    @Test("Empty string returns nil")
    func thumbnailUrlEmpty() {
        let url = ItemCardCalculations.thumbnailUrl(from: "")
        #expect(url == nil)
    }

    // MARK: - resolvedSelected

    @Test("External selected overrides internal")
    func resolvedSelectedExternal() {
        let result = ItemCardCalculations.resolvedSelected(
            externalSelected: true,
            internalSelected: false
        )
        #expect(result == true)
    }

    @Test("External false overrides internal true")
    func resolvedSelectedExternalFalse() {
        let result = ItemCardCalculations.resolvedSelected(
            externalSelected: false,
            internalSelected: true
        )
        #expect(result == false)
    }

    @Test("No external uses internal state")
    func resolvedSelectedInternal() {
        let result = ItemCardCalculations.resolvedSelected(
            externalSelected: nil,
            internalSelected: true
        )
        #expect(result == true)
    }

    @Test("No external with false internal")
    func resolvedSelectedInternalFalse() {
        let result = ItemCardCalculations.resolvedSelected(
            externalSelected: nil,
            internalSelected: false
        )
        #expect(result == false)
    }
}
