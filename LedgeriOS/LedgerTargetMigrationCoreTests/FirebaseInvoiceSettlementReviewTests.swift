import Foundation
import Testing
import LedgerTargetCore
@testable import LedgerTargetMigrationCore

@Suite("Source Invoice settlement coverage")
struct FirebaseInvoiceSettlementReviewTests {
    private static func map(_ fields: [String: FirebaseSourceValue]) -> FirebaseSourceValue {
        .map(fields.keys.sorted().map { .init(key: $0, value: fields[$0]!) })
    }
    private static func document(_ collection: String, _ id: String, _ fields: [String: FirebaseSourceValue]) -> FirebaseSourceDocument {
        .init(accountScopeID: "source-account", documentPathSegments: ["accounts", "source-account", collection, id],
            entityCode: collection, evidenceKind: .record, fields: map(fields), sourceRecordID: id)
    }
    private static func line(_ id: String = "line", amount: String = "100", sign: String = "1",
                             reverse: [String] = []) -> FirebaseSourceValue {
        map(["id": .string(id), "amountCents": .integer(amount), "sign": .integer(sign),
             "sourceType": .string("item"), "sourceId": .string("physical-item"),
             "settlementTransactionIds": .array(reverse.map { .string($0) })])
    }
    private static func invoice(lines: [FirebaseSourceValue]? = nil, total: String = "100", status: String = "paid") -> FirebaseSourceDocument {
        document("invoices", "invoice", ["projectId": .string("source-project"), "status": .string(status),
            "totalCents": .integer(total), "lines": .array(lines ?? [line()]), "unknown": .string("preserved")])
    }
    private static func payment(_ id: String = "payment", lines: [String] = ["line"], amount: String = "100",
                                status: String? = nil, project: String = "source-project") -> FirebaseSourceDocument {
        var fields: [String: FirebaseSourceValue] = ["type": .string("paymentToBusiness"), "amountCents": .integer(amount),
            "projectId": .string(project), "settlementInvoiceId": .string("invoice"),
            "settlementInvoiceLineIds": .array(lines.map { .string($0) })]
        if let status { fields["status"] = .string(status) }
        return document("transactions", id, fields)
    }
    private static func review(_ invoice: FirebaseSourceDocument, _ payments: [FirebaseSourceDocument]) throws -> FirebaseInvoiceSettlementReview {
        .review(invoice: invoice, payments: payments, sourceAccountID: "source-account",
            targetScope: .project(accountId: try AccountID(validating: "target-account"),
                projectId: try ProjectID(validating: "target-project"), clientId: try ClientID(validating: "target-client")))
    }

    @Test("Exact signed lines and one explicit payment establish only source line coverage")
    func exactCoverage() throws {
        let source = Self.invoice(lines: [Self.line("charge", amount: "120"), Self.line("credit", amount: "20", sign: "-1")])
        let payments = [Self.payment(lines: ["credit", "charge"])]
        let result = try Self.review(source, payments)
        #expect(result.hasSinglePaymentLineCoverage)
        #expect(result.invoice == source)
        #expect(result.suppliedPayments == payments)
    }

    @Test("Canceled and recollected history is retained, never resurrected by surviving links")
    func canceledHistory() throws {
        let source = Self.invoice(lines: [Self.line(reverse: ["old", "new"])])
        let payments = [Self.payment("old", status: "CANCELLED"), Self.payment("new")]
        let result = try Self.review(source, payments)
        #expect(result.issues.contains(.canceledPaymentHistory))
        #expect(!result.hasSinglePaymentLineCoverage)
        #expect(result.suppliedPayments == payments)
        let canceledOnly = try Self.review(Self.invoice(status: "sent"), [payments[0]])
        #expect(canceledOnly.issues.contains(.noActivePayment))
        #expect(canceledOnly.issues.contains(.invoiceNotPaid))
    }

    @Test("Category-grouped, partial and status-only collection are not silently consolidated")
    func ambiguousSettlements() throws {
        let source = Self.invoice(lines: [Self.line("a", amount: "40"), Self.line("b", amount: "60")])
        #expect(try Self.review(source, [Self.payment("a", lines: ["a"], amount: "40"),
            Self.payment("b", lines: ["b"], amount: "60")]).issues.contains(.multipleActivePayments))
        let partial = try Self.review(source, [Self.payment(lines: ["a"], amount: "40")])
        #expect(partial.issues.contains(.paymentLineCoverageMismatch))
        #expect(partial.issues.contains(.paymentAmountMismatch))
        #expect(try Self.review(source, []).issues.contains(.noActivePayment))
    }

    @Test("Missing legacy line identity, duplicate IDs, foreign scope and dangling history block mapping")
    func identityAndScope() throws {
        let noID = Self.map(["amountCents": .integer("100"), "sign": .integer("1"), "sourceType": .string("manual")])
        #expect(try Self.review(Self.invoice(lines: [noID]), [Self.payment()]).issues.contains(.missingOrInvalidLines))
        #expect(try Self.review(Self.invoice(lines: [Self.line(), Self.line()], total: "200"), [Self.payment()]).issues.contains(.duplicateLineID))
        #expect(try Self.review(Self.invoice(), [Self.payment(project: "foreign")]).issues.contains(.paymentScopeOrShape))
        #expect(try Self.review(Self.invoice(), [Self.payment(), Self.payment()]).issues.contains(.duplicatePayment))
        #expect(try Self.review(Self.invoice(lines: [Self.line(reverse: ["missing"])]), [Self.payment()]).issues.contains(.paymentScopeOrShape))
        #expect(try Self.review(Self.invoice(), [Self.payment(lines: ["line", "line"])]).issues.contains(.paymentLineCoverageMismatch))
    }

    @Test("Integer overflow and mismatched invoice totals never become plausible balances")
    func moneyIntegrity() throws {
        #expect(try Self.review(Self.invoice(total: "99"), [Self.payment()]).issues.contains(.lineTotalMismatch))
        let overflow = Self.invoice(lines: [Self.line("a", amount: "9223372036854775807"), Self.line("b", amount: "1")])
        #expect(try Self.review(overflow, [Self.payment()]).issues.contains(.lineTotalMismatch))
        let exact = Self.invoice(lines: [Self.line(amount: "9007199254740993")], total: "9007199254740993")
        #expect(try Self.review(exact, [Self.payment(amount: "9007199254740993")]).hasSinglePaymentLineCoverage)
    }

    @Test("Conflicting payment copies cannot hide behind a different or missing Invoice link")
    func conflictingLinkedIdentity() throws {
        for link: FirebaseSourceValue? in [.string("another-invoice"), .null, nil] {
            var fields: [String: FirebaseSourceValue] = ["type": .string("paymentToBusiness"),
                "projectId": .string("source-project"), "amountCents": .integer("100")]
            if let link { fields["settlementInvoiceId"] = link }
            let conflicting = Self.document("transactions", "payment", fields)
            let records = [Self.payment(), conflicting]
            let result = try Self.review(Self.invoice(), records)
            #expect(result.issues.contains(.duplicatePayment))
            #expect(!result.hasSinglePaymentLineCoverage)
            #expect(result.suppliedPayments == records)
        }
    }

    @Test("Byte-distinct line identities are not merged by Unicode normalization")
    func exactIdentityBytes() throws {
        let composed = "\u{00e9}", decomposed = "e\u{0301}"
        let source = Self.invoice(lines: [Self.line(composed, amount: "40"), Self.line(decomposed, amount: "60")])
        #expect(try Self.review(source, [Self.payment(lines: [composed, decomposed])]).hasSinglePaymentLineCoverage)
        #expect(try Self.review(source, [Self.payment(lines: [composed, composed])]).issues.contains(.paymentLineCoverageMismatch))
    }
}
