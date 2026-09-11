import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Exact Money and Domain Identity")
struct DomainPrimitivesTests {
    @Test("Typed IDs and exact same-currency Money remain deterministic")
    func validPrimitivesAndArithmetic() throws {
        let identifiers = try Self.identifiers()
        #expect(identifiers.clientId.rawValue == "client-001")
        #expect(identifiers.projectId.rawValue == "project-001")
        #expect(identifiers.itemId.rawValue == "item-001")
        #expect(identifiers.invoiceId.rawValue == "invoice-001")
        #expect(identifiers.transactionId.rawValue == "transaction-001")
        #expect(identifiers.expenseId.rawValue == "expense-001")
        #expect(identifiers.feeId.rawValue == "fee-001")
        #expect(identifiers.spaceId.rawValue == "space-001")
        #expect(identifiers.attachmentId.rawValue == "attachment-001")

        let usd = try CurrencyCode(validating: "USD")
        let charge = Money(minorUnits: 12_345, currency: usd)
        let credit = Money(minorUnits: -2_345, currency: usd)
        let total = try charge.adding(credit)

        #expect(charge.sign == .positive)
        #expect(credit.sign == .negative)
        #expect(Money.zero(currency: usd).sign == .zero)
        #expect(Money.zero(currency: usd).isZero)
        #expect(total == Money(minorUnits: 10_000, currency: usd))
        #expect(try total.ordering(comparedTo: charge) == .less)
        #expect(try total.hasSameAmount(as: Money(minorUnits: 10_000, currency: usd)))
        #expect(try charge.subtracting(credit).minorUnits == 14_690)
        #expect(try credit.negated().minorUnits == 2_345)
    }

    @Test("Domain primitives round-trip exact integer boundaries across restart")
    func canonicalRestart() throws {
        let identifiers = try Self.identifiers()
        let usd = try CurrencyCode(validating: "USD")
        let fixture = PrimitiveFixture(
            identifiers: identifiers,
            values: [
                Money(minorUnits: Int64.min, currency: usd),
                Money.zero(currency: usd),
                Money(minorUnits: Int64.max, currency: usd)
            ]
        )

        let bytes = try OperationContractCodec.encode(fixture)
        let restored = try OperationContractCodec.decode(
            PrimitiveFixture.self,
            from: bytes
        )

        #expect(restored == fixture)
        #expect(try OperationContractCodec.encode(restored) == bytes)
        #expect(String(decoding: bytes, as: UTF8.self).contains("9223372036854775807"))
        #expect(String(decoding: bytes, as: UTF8.self).contains("-9223372036854775808"))
        #expect(!String(decoding: bytes, as: UTF8.self).contains("."))
    }

    @Test("Malformed, cross-currency, and overflow boundaries fail atomically")
    func rejectsInvalidPrimitives() throws {
        for rawValue in ["", " client", "project/path", String(repeating: "a", count: 129)] {
            #expect(Self.captureFailure {
                _ = try ClientID(validating: rawValue)
            } == .invalidEntityIdentifier)
        }
        for rawValue in ["", "US", "USDD", "usd", "ÜSD", " USD"] {
            #expect(Self.captureFailure {
                _ = try CurrencyCode(validating: rawValue)
            } == .invalidCurrencyCode)
        }

        let usd = try CurrencyCode(validating: "USD")
        let eur = try CurrencyCode(validating: "EUR")
        let oneDollar = Money(minorUnits: 100, currency: usd)
        let oneEuro = Money(minorUnits: 100, currency: eur)
        #expect(Self.captureFailure {
            _ = try oneDollar.hasSameAmount(as: oneEuro)
        } == .currencyMismatch)
        #expect(Self.captureFailure {
            _ = try oneDollar.ordering(comparedTo: oneEuro)
        } == .currencyMismatch)
        #expect(Self.captureFailure {
            _ = try oneDollar.adding(oneEuro)
        } == .currencyMismatch)
        #expect(Self.captureFailure {
            _ = try oneDollar.subtracting(oneEuro)
        } == .currencyMismatch)

        #expect(Self.captureFailure {
            _ = try Money(minorUnits: Int64.max, currency: usd)
                .adding(Money(minorUnits: 1, currency: usd))
        } == .arithmeticOverflow(.addition))
        #expect(Self.captureFailure {
            _ = try Money(minorUnits: Int64.min, currency: usd)
                .adding(Money(minorUnits: -1, currency: usd))
        } == .arithmeticOverflow(.addition))
        #expect(Self.captureFailure {
            _ = try Money(minorUnits: Int64.min, currency: usd)
                .subtracting(Money(minorUnits: 1, currency: usd))
        } == .arithmeticOverflow(.subtraction))
        #expect(Self.captureFailure {
            _ = try Money(minorUnits: Int64.max, currency: usd)
                .subtracting(Money(minorUnits: -1, currency: usd))
        } == .arithmeticOverflow(.subtraction))
        #expect(Self.captureFailure {
            _ = try Money(minorUnits: Int64.min, currency: usd).negated()
        } == .arithmeticOverflow(.negation))

        let invalidIdentifier = Data("\"project/path\"".utf8)
        let invalidCurrency = Data("\"usd\"".utf8)
        let fractionalMoney = Data(
            #"{"currency":"USD","minorUnits":1.25}"#.utf8
        )
        #expect(Self.captureFailure {
            _ = try OperationContractCodec.decode(
                ProjectID.self,
                from: invalidIdentifier
            )
        } == .invalidEncodedEntityIdentifier)
        #expect(Self.captureFailure {
            _ = try OperationContractCodec.decode(
                CurrencyCode.self,
                from: invalidCurrency
            )
        } == .invalidEncodedCurrencyCode)
        #expect(Self.captureFailure {
            _ = try OperationContractCodec.decode(
                Money.self,
                from: fractionalMoney
            )
        } == .invalidEncodedMoney)
        #expect(
            Self.captureFailure {
                _ = try Money(minorUnits: Int64.max, currency: usd)
                    .adding(Money(minorUnits: 1, currency: usd))
            }?.diagnosticCode == "domain_money_arithmetic_overflow"
        )

        let diagnostics: [(DomainPrimitiveFailure, String)] = [
            (.invalidEntityIdentifier, "domain_entity_identifier_invalid"),
            (.invalidEncodedEntityIdentifier, "domain_entity_identifier_encoding_invalid"),
            (.invalidCurrencyCode, "domain_currency_code_invalid"),
            (.invalidEncodedCurrencyCode, "domain_currency_code_encoding_invalid"),
            (.invalidEncodedMoney, "domain_money_encoding_invalid"),
            (.currencyMismatch, "domain_money_currency_mismatch"),
            (.arithmeticOverflow(.negation), "domain_money_arithmetic_overflow")
        ]
        for (failure, diagnosticCode) in diagnostics {
            #expect(failure.diagnosticCode == diagnosticCode)
        }
    }

    private struct PrimitiveIdentifiers: Codable, Equatable, Sendable {
        let clientId: ClientID
        let projectId: ProjectID
        let itemId: ItemID
        let invoiceId: InvoiceID
        let transactionId: TransactionID
        let expenseId: ExpenseID
        let feeId: FeeID
        let spaceId: SpaceID
        let attachmentId: AttachmentID
    }

    private struct PrimitiveFixture: Codable, Equatable, Sendable {
        let identifiers: PrimitiveIdentifiers
        let values: [Money]
    }

    private static func identifiers() throws -> PrimitiveIdentifiers {
        PrimitiveIdentifiers(
            clientId: try ClientID(validating: "client-001"),
            projectId: try ProjectID(validating: "project-001"),
            itemId: try ItemID(validating: "item-001"),
            invoiceId: try InvoiceID(validating: "invoice-001"),
            transactionId: try TransactionID(validating: "transaction-001"),
            expenseId: try ExpenseID(validating: "expense-001"),
            feeId: try FeeID(validating: "fee-001"),
            spaceId: try SpaceID(validating: "space-001"),
            attachmentId: try AttachmentID(validating: "attachment-001")
        )
    }

    private static func captureFailure<Value>(
        _ body: () throws -> Value
    ) -> DomainPrimitiveFailure? {
        do {
            _ = try body()
            return nil
        } catch let failure as DomainPrimitiveFailure {
            return failure
        } catch {
            return nil
        }
    }
}
