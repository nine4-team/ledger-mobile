import Foundation

/// Original, revision-bound inputs for vendor-order pricing. Inclusive edits
/// retain their exact inverse as a fraction, including repeating decimals.
public enum LiveItemAdjustments {
    public enum Issue: String, Codable, Sendable {
        case unknownInput, nonpositiveBase, zeroFactor, arithmeticRange
    }

    public struct Input: Codable, Equatable, Sendable {
        public let itemId: String
        public let numerator: String?
        public let denominator: String?
        public let requestedProjectPriceMinorUnits: Int64?
        public let issue: Issue?

        public init(itemId: String, numerator: String?, denominator: String?,
                    requestedProjectPriceMinorUnits: Int64?, issue: Issue?) {
            self.itemId = itemId; self.numerator = numerator; self.denominator = denominator
            self.requestedProjectPriceMinorUnits = requestedProjectPriceMinorUnits; self.issue = issue
        }

        public init(itemId: String, unadjustedMinorUnits: Int64?) {
            self.itemId = itemId
            numerator = unadjustedMinorUnits.map(String.init)
            denominator = unadjustedMinorUnits == nil ? nil : "1"
            requestedProjectPriceMinorUnits = nil
            issue = unadjustedMinorUnits == nil ? .unknownInput : nil
        }

        public init(itemId: String, requestedProjectPriceMinorUnits: Int64,
                    totalMinorUnits: Int64, adjustmentsMinorUnits: Int64) {
            self.itemId = itemId
            self.requestedProjectPriceMinorUnits = requestedProjectPriceMinorUnits
            let base = Decimal(totalMinorUnits) - Decimal(adjustmentsMinorUnits)
            if base <= 0 {
                numerator = nil; denominator = nil; issue = .nonpositiveBase
            } else if totalMinorUnits == 0 && requestedProjectPriceMinorUnits != 0 {
                numerator = nil; denominator = nil; issue = .zeroFactor
            } else if let value = try? Fraction(Decimal(requestedProjectPriceMinorUnits), 1)
                .multiplied(by: Fraction(base, totalMinorUnits == 0 ? 1 : Decimal(totalMinorUnits))) {
                numerator = value.n.description; denominator = value.d.description; issue = nil
            } else {
                numerator = nil; denominator = nil; issue = .arithmeticRange
            }
        }
    }

    public struct Price: Equatable, Sendable {
        public let itemId: String
        public let unadjustedMinorUnits: Int64?
        public let adjustmentsMinorUnits: Int64?
        public let projectPriceMinorUnits: Int64?
        public let issue: Issue?
    }

    public struct Result: Equatable, Sendable {
        public let prices: [Price]
        /// Exact rational Difference, not a rounded-cent balance verdict.
        public let differenceNumerator: String?
        public let differenceDenominator: String?
        public var isBalanced: Bool { differenceNumerator == "0" }
        public var isProvisional: Bool { !isBalanced }
    }

    public static func calculate(totalMinorUnits: Int64, adjustmentsMinorUnits: Int64,
                                 inputs: [Input]) -> Result {
        let base = Decimal(totalMinorUnits) - Decimal(adjustmentsMinorUnits)
        let resolved = inputs.map { input in
            if input.numerator == nil, let requested = input.requestedProjectPriceMinorUnits {
                return Input(itemId: input.itemId, requestedProjectPriceMinorUnits: requested,
                             totalMinorUnits: totalMinorUnits, adjustmentsMinorUnits: adjustmentsMinorUnits)
            }
            return input
        }
        let values: [Fraction?] = resolved.map { input in
            guard let n = input.numerator, let d = input.denominator,
                  let numerator = decimalInteger(n), let denominator = decimalInteger(d) else { return nil }
            return try? Fraction(numerator, denominator)
        }
        var difference: Fraction? = try? {
            guard values.allSatisfy({ $0 != nil }) else { throw IssueError() }
            return try values.reduce(Fraction(base, 1)) { try $0.adding($1!.negated) }
        }()
        var shares = [Fraction?](repeating: nil, count: inputs.count)
        var finals = shares
        var failures = [Issue?](repeating: nil, count: inputs.count)
        for i in inputs.indices {
            if let value = values[i], (try? value.rounded()) == nil {
                failures[i] = .arithmeticRange; continue
            }
            guard base > 0 else { failures[i] = .nonpositiveBase; continue }
            guard let value = values[i] else { failures[i] = resolved[i].issue ?? .unknownInput; continue }
            do {
                shares[i] = try value.multiplied(by: Fraction(Decimal(adjustmentsMinorUnits), base))
                finals[i] = try value.multiplied(by: Fraction(Decimal(totalMinorUnits), base))
                _ = try shares[i]!.rounded(); _ = try finals[i]!.rounded()
            } catch { failures[i] = .arithmeticRange }
        }
        if failures.contains(.arithmeticRange) { difference = nil }
        let balanced = difference?.n == 0
        let allocatePennies = balanced && failures.allSatisfy { $0 == nil }
        let roundedShares = rounded(shares, ids: inputs.map(\.itemId), total: allocatePennies ? adjustmentsMinorUnits : nil)
        let roundedFinals = rounded(finals, ids: inputs.map(\.itemId), total: allocatePennies ? totalMinorUnits : nil)
        let prices = inputs.indices.map { i in
            var issue = failures[i] ?? ((roundedShares[i] == nil || roundedFinals[i] == nil) ? Issue.arithmeticRange : nil)
            var displayedUnadjusted = try? values[i]?.rounded()
            if issue == nil, let price = roundedFinals[i], let share = roundedShares[i] {
                let (unadjusted, overflow) = price.subtractingReportingOverflow(share)
                if overflow { issue = .arithmeticRange } else { displayedUnadjusted = unadjusted }
            }
            return Price(itemId: inputs[i].itemId, unadjustedMinorUnits: displayedUnadjusted,
                  adjustmentsMinorUnits: issue == nil ? roundedShares[i] : nil,
                  projectPriceMinorUnits: issue == nil ? roundedFinals[i] : nil, issue: issue)
        }
        if prices.contains(where: { $0.issue == .arithmeticRange }) { difference = nil }
        return .init(prices: prices, differenceNumerator: difference?.n.description,
                     differenceDenominator: difference?.d.description)
    }

    private static func rounded(_ values: [Fraction?], ids: [String], total: Int64?) -> [Int64?] {
        var result = values.map { try? $0?.rounded() }
        guard let total, result.allSatisfy({ $0 != nil }) else { return result }
        let delta = Decimal(total) - result.compactMap { $0 }.reduce(Decimal(0)) { $0 + Decimal($1) }
        guard let count = Int(abs(delta).description), count <= values.count else {
            return [Int64?](repeating: nil, count: values.count)
        }
        let residuals = values.indices.map { i in try? values[i]!.adding(Fraction(-Decimal(result[i]!), 1)) }
        guard residuals.allSatisfy({ $0 != nil }) else { return [Int64?](repeating: nil, count: values.count) }
        let order = values.indices.sorted { a, b in
            let left = residuals[a]!, right = residuals[b]!
            if left.n == right.n && left.d == right.d { return ids[a] < ids[b] }
            return delta > 0 ? right.lessThan(left) : left.lessThan(right)
        }
        for i in order.prefix(count) {
            let (value, overflow) = result[i]!.addingReportingOverflow(delta > 0 ? 1 : -1)
            result[i] = overflow ? nil : value
        }
        return result
    }

    private static func decimalInteger(_ text: String) -> Decimal? {
        guard text.range(of: "^-?(0|[1-9][0-9]*)$", options: .regularExpression) != nil,
              text.filter({ $0.isNumber }).count <= 38,
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              value.description == text else { return nil }
        return value
    }

    private struct IssueError: Error {}

    /// Decimal is used only as a checked integer container. Division never
    /// becomes a persisted input or the exact balance criterion.
    // Module-internal so export uses the same checked exact arithmetic, rather
    // than reconstructing receipt totals with rounded Item display prices.
    struct Fraction {
        let n: Decimal
        let d: Decimal
        init(_ numerator: Decimal, _ denominator: Decimal) throws {
            guard !numerator.isNaN, !denominator.isNaN, denominator != 0 else { throw IssueError() }
            let divisor = Self.gcd(abs(numerator), abs(denominator))
            n = Self.quotient(abs(numerator), divisor) * (numerator < 0 ? -1 : 1) * (denominator < 0 ? -1 : 1)
            d = Self.quotient(abs(denominator), divisor)
            guard n.description.filter({ $0.isNumber }).count <= 38,
                  d.description.count <= 38 else { throw IssueError() }
        }
        var negated: Fraction { try! Fraction(-n, d) }
        func multiplied(by other: Fraction) throws -> Fraction {
            let a = Self.gcd(abs(n), other.d), b = Self.gcd(abs(other.n), d)
            return try Fraction(Self.product(n / a, other.n / b), Self.product(d / b, other.d / a))
        }
        func adding(_ other: Fraction) throws -> Fraction {
            let common = Self.gcd(d, other.d)
            var left = try Self.product(n, other.d / common)
            var right = try Self.product(other.n, d / common)
            var sum = Decimal()
            guard NSDecimalAdd(&sum, &left, &right, .plain) == .noError,
                  sum.description.filter({ $0.isNumber }).count <= 38 else { throw IssueError() }
            return try Fraction(sum, Self.product(d, other.d / common))
        }
        func rounded() throws -> Int64 {
            let magnitude = abs(n)
            let whole = Self.quotient(magnitude, d)
            let remainder = magnitude - whole * d
            let rounded = (whole + (remainder >= d - remainder ? 1 : 0)) * (n < 0 ? -1 : 1)
            guard let value = Int64(rounded.description) else { throw IssueError() }
            return value
        }
        func lessThan(_ other: Fraction) -> Bool {
            if n < 0 && other.n >= 0 { return true }
            if n >= 0 && other.n < 0 { return false }
            var a = abs(n), b = d, c = abs(other.n), e = other.d
            var reversed = n < 0
            while true {
                let x = Self.quotient(a, b), y = Self.quotient(c, e)
                if x != y { return reversed ? x > y : x < y }
                let ar = a - x * b, cr = c - y * e
                if ar == 0 || cr == 0 {
                    if ar == cr { return false }
                    return reversed ? cr == 0 : ar == 0
                }
                a = b; b = ar; c = e; e = cr; reversed.toggle()
            }
        }
        // Integer long division by doubling never rounds a near-integer
        // quotient. Every intermediate is bounded by the dividend.
        private static func quotient(_ dividend: Decimal, _ divisor: Decimal) -> Decimal {
            var remainder = dividend, result: Decimal = 0
            while remainder >= divisor {
                var multiple = divisor, power: Decimal = 1
                while multiple <= remainder - multiple { multiple += multiple; power += power }
                remainder -= multiple; result += power
            }
            return result
        }
        private static func product(_ a: Decimal, _ b: Decimal) throws -> Decimal {
            var a = a, b = b, value = Decimal()
            guard NSDecimalMultiply(&value, &a, &b, .plain) == .noError,
                  value.description.filter({ $0.isNumber }).count <= 38 else { throw IssueError() }
            return value
        }
        private static func gcd(_ a: Decimal, _ b: Decimal) -> Decimal {
            var a = a, b = b
            while b != 0 {
                let remainder = a - quotient(a, b) * b
                a = b; b = remainder
            }
            return a == 0 ? 1 : a
        }
    }
}
