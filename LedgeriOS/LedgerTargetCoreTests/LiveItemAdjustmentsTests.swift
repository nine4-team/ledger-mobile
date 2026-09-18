import Testing
import Foundation
@testable import LedgerTargetCore

@Suite("Live vendor-order Item adjustments")
struct LiveItemAdjustmentsTests {
    @Test func outOfRangeUnadjustedIsInvalidAcrossServerAndNative() throws {
        let input = LiveItemAdjustments.Input(itemId:"a", requestedProjectPriceMinorUnits:.max,
            totalMinorUnits:1, adjustmentsMinorUnits:-1)
        #expect(input.numerator == "18446744073709551614")
        let result = LiveItemAdjustments.calculate(totalMinorUnits:1, adjustmentsMinorUnits:-1, inputs:[input])
        #expect(result.prices[0].issue == .arithmeticRange)
        #expect(result.prices[0].projectPriceMinorUnits == nil)
        #expect(result.prices[0].adjustmentsMinorUnits == nil)
        #expect(result.differenceNumerator == nil)
        let server = #"{"totalMinorUnits":"1","adjustmentsMinorUnits":"-1","differenceNumerator":null,"differenceDenominator":null,"isBalanced":false,"isProvisional":true,"items":[{"itemId":"a","numerator":"18446744073709551614","denominator":"1","requestedProjectPriceMinorUnits":"9223372036854775807","unadjustedMinorUnits":null,"adjustmentsMinorUnits":null,"projectPriceMinorUnits":null,"issue":"arithmeticRange"}]}"#
        let decoded = try JSONDecoder().decode(LiveItemAdjustmentOrder.self, from:Data(server.utf8))
        #expect(decoded.items[0].issue == .arithmeticRange)
        let forged = server.replacingOccurrences(of: #""unadjustedMinorUnits":null"#, with: #""unadjustedMinorUnits":"0""#)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(LiveItemAdjustmentOrder.self,from:Data(forged.utf8))
        }
    }

    @Test func displayedHalfCentBreakdownsReconcileWithoutChangingInputs() throws {
        let inputs = ["a","b"].map { LiveItemAdjustments.Input(itemId:$0,requestedProjectPriceMinorUnits:1,
            totalMinorUnits:2,adjustmentsMinorUnits:1) }
        let result = LiveItemAdjustments.calculate(totalMinorUnits:2,adjustmentsMinorUnits:1,inputs:inputs)
        #expect(inputs.map(\.numerator) == ["1","1"])
        #expect(inputs.map(\.denominator) == ["2","2"])
        #expect(result.prices.map(\.unadjustedMinorUnits) == [1,0])
        #expect(result.prices.map(\.adjustmentsMinorUnits) == [0,1])
        for price in result.prices {
            #expect(try #require(price.unadjustedMinorUnits) + #require(price.adjustmentsMinorUnits) == price.projectPriceMinorUnits)
        }
        let reverse = LiveItemAdjustments.calculate(totalMinorUnits:2,adjustmentsMinorUnits:1,inputs:inputs.reversed())
        #expect(reverse.prices.reversed() == result.prices)
        let context = try JSONDecoder().decode(LiveItemPricingContext.self,from:Data(#"{"transactionId":"order","revision":"2","priceRevision":"1","totalMinorUnits":"2","adjustmentsMinorUnits":"1","currency":"USD","isProvisional":false,"price":{"itemId":"a","unadjustedMinorUnits":"1","adjustmentsMinorUnits":"0","projectPriceMinorUnits":"1","issue":null}}"#.utf8))
        let preview = try #require(context.preview(requested:Money(minorUnits:1,currency:.init(validating:"USD"))))
        #expect(preview.unadjustedMinorUnits == 1 && preview.adjustmentsMinorUnits == 0)
    }
    @Test func nearHalfCentUsesExactIntegerDivision() {
        let input = LiveItemAdjustments.Input(itemId: "a",
            numerator: "49999999999999999999999999999999999998",
            denominator: "99999999999999999999999999999999999997",
            requestedProjectPriceMinorUnits: nil, issue: nil)
        let result = LiveItemAdjustments.calculate(totalMinorUnits: 2, adjustmentsMinorUnits: 1, inputs: [input])
        #expect(result.prices[0].adjustmentsMinorUnits == 0)
        #expect(result.prices[0].projectPriceMinorUnits == 1)
        #expect(!result.isBalanced)
    }
    @Test func partialEntryUsesWholeOrderBase() {
        let a = LiveItemAdjustments.Input(itemId: "a", unadjustedMinorUnits: 1_000)
        let partial = LiveItemAdjustments.calculate(totalMinorUnits: 12_000, adjustmentsMinorUnits: 2_000, inputs: [a])
        #expect(partial.prices[0].adjustmentsMinorUnits == 200)
        #expect(partial.isProvisional)
        let complete = LiveItemAdjustments.calculate(totalMinorUnits: 12_000, adjustmentsMinorUnits: 2_000,
            inputs: [a, .init(itemId: "b", unadjustedMinorUnits: 9_000)])
        #expect(complete.isBalanced)
        #expect(complete.prices.map(\.projectPriceMinorUnits) == [1_200, 10_800])
    }

    @Test func signedDiscountAndStablePennies() {
        for adjustments: Int64 in [-1, 1] {
            let inputs = ["c", "a", "b"].map { LiveItemAdjustments.Input(itemId: $0, unadjustedMinorUnits: 1) }
            let first = LiveItemAdjustments.calculate(totalMinorUnits: 3 + adjustments,
                adjustmentsMinorUnits: adjustments, inputs: inputs)
            let reversed = LiveItemAdjustments.calculate(totalMinorUnits: 3 + adjustments,
                adjustmentsMinorUnits: adjustments, inputs: inputs.reversed())
            #expect(first.isBalanced)
            #expect(first.prices.compactMap(\.adjustmentsMinorUnits).reduce(0, +) == adjustments)
            #expect(first.prices.compactMap(\.projectPriceMinorUnits).reduce(0, +) == 3 + adjustments)
            #expect(first.prices.sorted { $0.itemId < $1.itemId } == reversed.prices.sorted { $0.itemId < $1.itemId })
        }
    }

    @Test func inclusiveEditsPreserveExactRepeatingInputsAndRoundTrip() {
        let inputs = ["a", "b", "c"].map { LiveItemAdjustments.Input(itemId: $0,
            requestedProjectPriceMinorUnits: 1, totalMinorUnits: 3, adjustmentsMinorUnits: 1) }
        let result = LiveItemAdjustments.calculate(totalMinorUnits: 3, adjustmentsMinorUnits: 1, inputs: inputs)
        #expect(inputs[0].numerator == "2")
        #expect(inputs[0].denominator == "3")
        #expect(result.isBalanced)
        #expect(result.prices.map(\.projectPriceMinorUnits) == [1, 1, 1])
        #expect(result.prices.compactMap(\.adjustmentsMinorUnits).reduce(0, +) == 1)
    }

    @Test func halfCentInputsConserveBothTotals() {
        let inputs = ["a", "b"].map { LiveItemAdjustments.Input(itemId: $0,
            requestedProjectPriceMinorUnits: 2, totalMinorUnits: 4, adjustmentsMinorUnits: 1) }
        let result = LiveItemAdjustments.calculate(totalMinorUnits: 4, adjustmentsMinorUnits: 1, inputs: inputs)
        #expect(result.isBalanced)
        #expect(result.prices.map(\.projectPriceMinorUnits) == [2, 2])
        #expect(result.prices.compactMap(\.adjustmentsMinorUnits).reduce(0, +) == 1)
    }

    @Test func invalidCalculationPreservesIntentAndUnknownIsNotZero() {
        for total: Int64 in [0, 10, 20] {
            let input = LiveItemAdjustments.Input(itemId: "a", requestedProjectPriceMinorUnits: 100,
                totalMinorUnits: total, adjustmentsMinorUnits: 20)
            #expect(input.requestedProjectPriceMinorUnits == 100)
            #expect(input.issue == .nonpositiveBase)
            let result = LiveItemAdjustments.calculate(totalMinorUnits: total, adjustmentsMinorUnits: 20, inputs: [input])
            #expect(result.prices[0].projectPriceMinorUnits == nil)
        }
        let zeroFactor = LiveItemAdjustments.Input(itemId: "a", requestedProjectPriceMinorUnits: 100,
            totalMinorUnits: 0, adjustmentsMinorUnits: -20)
        #expect(zeroFactor.issue == .zeroFactor)
        let missing = LiveItemAdjustments.calculate(totalMinorUnits: 120, adjustmentsMinorUnits: 20,
            inputs: [.init(itemId: "unknown", unadjustedMinorUnits: nil)])
        #expect(missing.differenceNumerator == nil)
        #expect(missing.prices[0].issue == .unknownInput)
        let repaired = LiveItemAdjustments.calculate(totalMinorUnits: 120, adjustmentsMinorUnits: 20, inputs: [zeroFactor])
        #expect(repaired.prices[0].projectPriceMinorUnits == 100)
        #expect(repaired.prices[0].issue == nil)
    }

    @Test func inclusiveRoundTripsAcrossChargesAndDiscounts() throws {
        for total: Int64 in 1...80 {
            for adjustment: Int64 in [-31, -1, 0, 1, 13, 37] where adjustment < total {
                let requested = total / 2
                let input = LiveItemAdjustments.Input(itemId: "a", requestedProjectPriceMinorUnits: requested,
                    totalMinorUnits: total, adjustmentsMinorUnits: adjustment)
                let restored = try OperationContractCodec.decode(LiveItemAdjustments.Input.self,
                    from: OperationContractCodec.encode(input))
                let result = LiveItemAdjustments.calculate(totalMinorUnits: total, adjustmentsMinorUnits: adjustment,
                    inputs: [restored, .init(itemId: "b", requestedProjectPriceMinorUnits: total - requested,
                                            totalMinorUnits: total, adjustmentsMinorUnits: adjustment)])
                #expect(result.isBalanced)
                #expect(result.prices.map(\.projectPriceMinorUnits) == [requested, total - requested])
                #expect(result.prices.compactMap(\.adjustmentsMinorUnits).reduce(0, +) == adjustment)
            }
        }
    }
}
