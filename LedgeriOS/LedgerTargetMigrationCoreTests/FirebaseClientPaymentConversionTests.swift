import Foundation
import Testing
import LedgerTargetCore
@testable import LedgerTargetMigrationCore

@Suite("Source client payment conversion")
struct FirebaseClientPaymentConversionTests {
    @Test("Explicit client payments map to Project Purchases without losing amount or settlement evidence")
    func paymentMapping() throws {
        let scope = try Self.scope()
        for type in ["paymentToBusiness", "PAYMENTTOBUSINESS", "payment_to_business", "payment-to-business"] {
            let source = Self.document(type: type, amount: .integer("9007199254740993"))
            let result = FirebaseClientPaymentConversion.convert(source,
                sourceAccountID: "source-account", sourceProjectID: "source-project", targetScope: scope)
            guard case .mapped(let retained, let classification, let amount) = result else {
                Issue.record("Explicit payment did not map: \(result)"); continue
            }
            #expect(retained == source)
            #expect(amount == 9_007_199_254_740_993)
            #expect(classification.type == .purchase)
            #expect(classification.scope == scope)
            #expect(classification.economicMeaning == .scopeOwnerPaid)
            #expect(classification.role == .standalone)
        }
    }

    @Test("Movement and legacy purchases never become client cash payments by type or amount alone")
    func ambiguousTypesAndAmounts() throws {
        let scope = try Self.scope()
        for type in ["purchase", "sale", "return", "fee", "expense", "returned", "unknown", " paymentToBusiness "] {
            let source = Self.document(type: type)
            #expect(FirebaseClientPaymentConversion.convert(source, sourceAccountID: "source-account",
                sourceProjectID: "source-project", targetScope: scope)
                == .unresolved(source: source, reason: .requiresDifferentEconomicMapping))
        }
        for amount: FirebaseSourceValue in [.integer("0"), .integer("-1"), .string("12"),
            .double(bits: "4028000000000000"), .null] {
            let source = Self.document(amount: amount)
            #expect(FirebaseClientPaymentConversion.convert(source, sourceAccountID: "source-account",
                sourceProjectID: "source-project", targetScope: scope)
                == .unresolved(source: source, reason: .requiresExactPositiveAmount))
        }
        let invalid = Self.document(amount: .integer("9223372036854775808"))
        #expect(FirebaseClientPaymentConversion.convert(invalid, sourceAccountID: "source-account",
            sourceProjectID: "source-project", targetScope: scope)
            == .unresolved(source: invalid, reason: .invalidSourceDocument))
    }

    @Test("Source Account and Project mappings cannot be substituted and Inventory cannot receive client payments")
    func scopeDenials() throws {
        let scope = try Self.scope()
        let source = Self.document()
        for (account, project) in [("foreign", "source-project"), ("source-account", "foreign")] {
            #expect(FirebaseClientPaymentConversion.convert(source, sourceAccountID: account,
                sourceProjectID: project, targetScope: scope)
                == .unresolved(source: source, reason: .sourceScopeMismatch))
        }
        let foreignPath = Self.document(pathAccount: "foreign")
        #expect(FirebaseClientPaymentConversion.convert(foreignPath, sourceAccountID: "source-account",
            sourceProjectID: "source-project", targetScope: scope)
            == .unresolved(source: foreignPath, reason: .sourceScopeMismatch))
        let ambiguous = Self.document(kind: .ambiguous)
        #expect(FirebaseClientPaymentConversion.convert(ambiguous, sourceAccountID: "source-account",
            sourceProjectID: "source-project", targetScope: scope)
            == .unresolved(source: ambiguous, reason: .invalidSourceDocument))
        #expect(FirebaseClientPaymentConversion.convert(source, sourceAccountID: "source-account",
            sourceProjectID: "source-project", targetScope: .businessInventory(accountId: scope.accountId))
            == .unresolved(source: source, reason: .targetRequiresProjectScope))
    }

    @Test("Canceled and unknown-status payments retain evidence but cannot export active money")
    func statusMapping() throws {
        let scope = try Self.scope()
        for status: FirebaseSourceValue in [.null, .string("pending"), .string("COMPLETED")] {
            let source = Self.document(status: status)
            guard case .mapped(let retained, _, _) = FirebaseClientPaymentConversion.convert(source,
                sourceAccountID: "source-account", sourceProjectID: "source-project", targetScope: scope) else {
                Issue.record("Known non-canceled legacy payment rejected"); continue
            }
            #expect(retained == source)
        }
        let rejected: [(FirebaseSourceValue, FirebaseClientPaymentConversionFailure)] = [
            (.string("canceled"), .requiresCancellationMapping),
            (.string("CANCELLED"), .requiresCancellationMapping),
            (.string("unexpected"), .requiresStatusMapping),
            (.string(" canceled "), .requiresStatusMapping),
            (.integer("1"), .requiresStatusMapping)
        ]
        let project = FirebaseSourceDocument(accountScopeID: "source-account",
            documentPathSegments: ["accounts", "source-account", "projects", "source-project"],
            entityCode: "projects", evidenceKind: .record, fields: .map([]), sourceRecordID: "source-project")
        for (status, reason) in rejected {
            let source = Self.document(status: status)
            #expect(FirebaseClientPaymentConversion.convert(source, sourceAccountID: "source-account",
                sourceProjectID: "source-project", targetScope: scope) == .unresolved(source: source, reason: reason))
            let batch = FirebaseClientPaymentBatch.convert(transactions: [source], projects: [project],
                sourceAccountID: "source-account", targetAccountID: scope.accountId,
                projectMappings: [.init(sourceProject: project, targetScope: scope)],
                identityMappings: [.init(sourcePath: source.documentPathSegments, targetID: try TransactionID(validating: "payment"))])
            #expect(batch.entries[0].source == source)
            #expect(batch.unresolvedCount == 1)
            #expect(batch.mappedTotalCents == 0)
            #expect(throws: FirebaseClientPaymentImportFailure.self) {
                try FirebaseClientPaymentImportParameters.make(batch: batch, currency: CurrencyCode(validating: "USD"))
            }
        }
    }

    private static func scope() throws -> TransactionScope {
        .project(accountId: try AccountID(validating: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"),
            projectId: try ProjectID(validating: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"),
            clientId: try ClientID(validating: "cccccccc-cccc-4ccc-8ccc-cccccccccccc"))
    }

    private static func document(type: String = "paymentToBusiness", amount: FirebaseSourceValue = .integer("1200"),
        pathAccount: String = "source-account", kind: FirebaseSourceEvidenceKind = .record,
        status: FirebaseSourceValue? = nil) -> FirebaseSourceDocument {
        var values: [String: FirebaseSourceValue] = [
            "amountCents": amount, "projectId": .string("source-project"), "type": .string(type),
            "settlementInvoiceId": .string("original-invoice"),
            "settlementInvoiceLineIds": .array([.string("original-line")]),
            "unknownFutureField": .string("preserved")
        ]
        if let status { values["status"] = status }
        return .init(accountScopeID: "source-account",
            documentPathSegments: ["accounts", pathAccount, "transactions", "payment"],
            entityCode: "transactions", evidenceKind: kind,
            fields: .map(values.keys.sorted().map { .init(key: $0, value: values[$0]!) }), sourceRecordID: "payment-evidence")
    }
}
