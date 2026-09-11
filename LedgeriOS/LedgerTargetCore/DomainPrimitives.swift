import Foundation

public enum MoneyArithmeticOperation: String, Codable, CaseIterable, Sendable {
    case addition
    case subtraction
    case negation
}

public enum MoneyOrdering: String, Codable, CaseIterable, Sendable {
    case less
    case equal
    case greater
}

public enum MoneySign: String, Codable, CaseIterable, Sendable {
    case negative
    case zero
    case positive
}

public enum DomainPrimitiveFailure: Error, Equatable, Sendable {
    case invalidEntityIdentifier
    case invalidEncodedEntityIdentifier
    case invalidCurrencyCode
    case invalidEncodedCurrencyCode
    case invalidEncodedMoney
    case currencyMismatch
    case arithmeticOverflow(MoneyArithmeticOperation)

    public var diagnosticCode: String {
        switch self {
        case .invalidEntityIdentifier:
            "domain_entity_identifier_invalid"
        case .invalidEncodedEntityIdentifier:
            "domain_entity_identifier_encoding_invalid"
        case .invalidCurrencyCode:
            "domain_currency_code_invalid"
        case .invalidEncodedCurrencyCode:
            "domain_currency_code_encoding_invalid"
        case .invalidEncodedMoney:
            "domain_money_encoding_invalid"
        case .currencyMismatch:
            "domain_money_currency_mismatch"
        case .arithmeticOverflow:
            "domain_money_arithmetic_overflow"
        }
    }
}

public struct DomainEntityIdentifier<Tag: Sendable>: Codable, Hashable, Sendable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        let validatedRawValue: String
        do {
            validatedRawValue = try LedgerIdentifier<Tag>(validating: rawValue).rawValue
        } catch {
            throw DomainPrimitiveFailure.invalidEntityIdentifier
        }
        self.rawValue = validatedRawValue
    }

    public init(from decoder: Decoder) throws {
        let container: SingleValueDecodingContainer
        do {
            container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            try self.init(validating: rawValue)
        } catch let failure as DomainPrimitiveFailure {
            if failure == .invalidEntityIdentifier {
                throw DomainPrimitiveFailure.invalidEncodedEntityIdentifier
            }
            throw failure
        } catch {
            throw DomainPrimitiveFailure.invalidEncodedEntityIdentifier
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum ClientIDTag: Sendable {}
public enum ProjectIDTag: Sendable {}
public enum ItemIDTag: Sendable {}
public enum InvoiceIDTag: Sendable {}
public enum TransactionIDTag: Sendable {}
public enum ExpenseIDTag: Sendable {}
public enum FeeIDTag: Sendable {}
public enum SpaceIDTag: Sendable {}
public enum AttachmentIDTag: Sendable {}

public typealias ClientID = DomainEntityIdentifier<ClientIDTag>
public typealias ProjectID = DomainEntityIdentifier<ProjectIDTag>
public typealias ItemID = DomainEntityIdentifier<ItemIDTag>
public typealias InvoiceID = DomainEntityIdentifier<InvoiceIDTag>
public typealias TransactionID = DomainEntityIdentifier<TransactionIDTag>
public typealias ExpenseID = DomainEntityIdentifier<ExpenseIDTag>
public typealias FeeID = DomainEntityIdentifier<FeeIDTag>
public typealias SpaceID = DomainEntityIdentifier<SpaceIDTag>
public typealias AttachmentID = DomainEntityIdentifier<AttachmentIDTag>

public struct CurrencyCode: Codable, Hashable, Comparable, Sendable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        guard rawValue.utf8.count == 3,
              rawValue.unicodeScalars.allSatisfy({
                  $0.value >= 65 && $0.value <= 90
              }) else {
            throw DomainPrimitiveFailure.invalidCurrencyCode
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            try self.init(validating: rawValue)
        } catch let failure as DomainPrimitiveFailure {
            if failure == .invalidCurrencyCode {
                throw DomainPrimitiveFailure.invalidEncodedCurrencyCode
            }
            throw failure
        } catch {
            throw DomainPrimitiveFailure.invalidEncodedCurrencyCode
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct Money: Codable, Hashable, Sendable {
    public let minorUnits: Int64
    public let currency: CurrencyCode

    public init(minorUnits: Int64, currency: CurrencyCode) {
        self.minorUnits = minorUnits
        self.currency = currency
    }

    public static func zero(currency: CurrencyCode) -> Self {
        Self(minorUnits: 0, currency: currency)
    }

    public var sign: MoneySign {
        if minorUnits < 0 {
            return .negative
        }
        if minorUnits > 0 {
            return .positive
        }
        return .zero
    }

    public var isZero: Bool {
        minorUnits == 0
    }

    public func hasSameAmount(as other: Self) throws -> Bool {
        try requireSameCurrency(as: other)
        return minorUnits == other.minorUnits
    }

    public func ordering(comparedTo other: Self) throws -> MoneyOrdering {
        try requireSameCurrency(as: other)
        if minorUnits < other.minorUnits {
            return .less
        }
        if minorUnits > other.minorUnits {
            return .greater
        }
        return .equal
    }

    public func adding(_ other: Self) throws -> Self {
        try requireSameCurrency(as: other)
        let result = minorUnits.addingReportingOverflow(other.minorUnits)
        guard !result.overflow else {
            throw DomainPrimitiveFailure.arithmeticOverflow(.addition)
        }
        return Self(minorUnits: result.partialValue, currency: currency)
    }

    public func subtracting(_ other: Self) throws -> Self {
        try requireSameCurrency(as: other)
        let result = minorUnits.subtractingReportingOverflow(other.minorUnits)
        guard !result.overflow else {
            throw DomainPrimitiveFailure.arithmeticOverflow(.subtraction)
        }
        return Self(minorUnits: result.partialValue, currency: currency)
    }

    public func negated() throws -> Self {
        let result = Int64.zero.subtractingReportingOverflow(minorUnits)
        guard !result.overflow else {
            throw DomainPrimitiveFailure.arithmeticOverflow(.negation)
        }
        return Self(minorUnits: result.partialValue, currency: currency)
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let minorUnits = try container.decode(Int64.self, forKey: .minorUnits)
            let currency = try container.decode(CurrencyCode.self, forKey: .currency)
            self.init(minorUnits: minorUnits, currency: currency)
        } catch let failure as DomainPrimitiveFailure {
            throw failure
        } catch {
            throw DomainPrimitiveFailure.invalidEncodedMoney
        }
    }

    private func requireSameCurrency(as other: Self) throws {
        guard currency == other.currency else {
            throw DomainPrimitiveFailure.currencyMismatch
        }
    }

    private enum CodingKeys: String, CodingKey {
        case minorUnits
        case currency
    }
}
