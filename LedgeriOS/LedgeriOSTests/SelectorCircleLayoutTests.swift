import Foundation
import Testing
@testable import LedgeriOS

@Suite("Selector Circle Layout Tests")
struct SelectorCircleLayoutTests {

    // MARK: - dotSize(for:)

    @Test("Dot size is 56% of circle size at default 18pt")
    func dotSizeDefault() {
        let result = SelectorCircle.dotSize(for: 18)
        #expect(result == 18 * 0.56)
    }

    @Test("Dot size scales with circle size")
    func dotSizeScaled() {
        let result = SelectorCircle.dotSize(for: 24)
        #expect(result == 24 * 0.56)
    }

    @Test("Dot size at zero")
    func dotSizeZero() {
        #expect(SelectorCircle.dotSize(for: 0) == 0)
    }

    @Test("Dot size at large value")
    func dotSizeLarge() {
        let result = SelectorCircle.dotSize(for: 100)
        #expect(result == 100 * 0.56)
    }

    // MARK: - checkmarkSize(for:)

    @Test("Checkmark size is 60% of circle size at default 18pt")
    func checkmarkSizeDefault() {
        let result = SelectorCircle.checkmarkSize(for: 18)
        #expect(result == 18 * 0.6)
    }

    @Test("Checkmark size scales with circle size")
    func checkmarkSizeScaled() {
        let result = SelectorCircle.checkmarkSize(for: 24)
        #expect(result == 24 * 0.6)
    }

    @Test("Checkmark size at zero")
    func checkmarkSizeZero() {
        #expect(SelectorCircle.checkmarkSize(for: 0) == 0)
    }

    @Test("Checkmark size at large value")
    func checkmarkSizeLarge() {
        let result = SelectorCircle.checkmarkSize(for: 100)
        #expect(result == 100 * 0.6)
    }
}
