import Foundation
import Testing
@testable import LedgeriOS

@Suite("Progress Bar Calculation Tests")
struct ProgressBarCalculationTests {

    // MARK: - clampPercentage

    @Test("Clamps value within range unchanged")
    func clampWithinRange() {
        #expect(ProgressBarCalculations.clampPercentage(50) == 50)
    }

    @Test("Clamps zero")
    func clampZero() {
        #expect(ProgressBarCalculations.clampPercentage(0) == 0)
    }

    @Test("Clamps 100")
    func clampHundred() {
        #expect(ProgressBarCalculations.clampPercentage(100) == 100)
    }

    @Test("Clamps negative to zero")
    func clampNegative() {
        #expect(ProgressBarCalculations.clampPercentage(-10) == 0)
    }

    @Test("Clamps over 100 to 100")
    func clampOver() {
        #expect(ProgressBarCalculations.clampPercentage(150) == 100)
    }

    @Test("Clamps fractional value")
    func clampFractional() {
        #expect(ProgressBarCalculations.clampPercentage(33.3) == 33.3)
    }

    // MARK: - overflowPercentage

    @Test("No overflow when under budget")
    func noOverflowUnder() {
        #expect(ProgressBarCalculations.overflowPercentage(spent: 500, budget: 1000) == 0)
    }

    @Test("No overflow when equal to budget")
    func noOverflowEqual() {
        #expect(ProgressBarCalculations.overflowPercentage(spent: 1000, budget: 1000) == 0)
    }

    @Test("Overflow at 150% spending")
    func overflowFiftyPercent() {
        #expect(ProgressBarCalculations.overflowPercentage(spent: 1500, budget: 1000) == 50)
    }

    @Test("Overflow capped at 100%")
    func overflowCapped() {
        #expect(ProgressBarCalculations.overflowPercentage(spent: 5000, budget: 1000) == 100)
    }

    @Test("Overflow with zero budget returns 0")
    func overflowZeroBudget() {
        #expect(ProgressBarCalculations.overflowPercentage(spent: 500, budget: 0) == 0)
    }

    @Test("Overflow with negative budget returns 0")
    func overflowNegativeBudget() {
        #expect(ProgressBarCalculations.overflowPercentage(spent: 500, budget: -100) == 0)
    }
}
