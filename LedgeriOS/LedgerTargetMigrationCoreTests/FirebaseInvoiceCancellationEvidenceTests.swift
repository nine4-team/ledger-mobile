import Foundation
import Testing
@testable import LedgerTargetMigrationCore

@Suite("Source Invoice payment cancellation evidence")
struct FirebaseInvoiceCancellationEvidenceTests {
    private static func document(_ collection: String, _ id: String, _ fields: [String: FirebaseSourceValue],
                                 account: String = "account") -> FirebaseSourceDocument {
        .init(accountScopeID: account, documentPathSegments: ["accounts", account, collection, id],
              entityCode: "semantic-label", evidenceKind: .record,
              fields: .map(fields.keys.sorted().map { .init(key: $0, value: fields[$0]!) }), sourceRecordID: id)
    }
    private static var invoice: FirebaseSourceDocument {
        document("invoices", "invoice", ["projectId": .string("project"), "status": .string("paid")])
    }
    private static func event(_ id: String = "event", refs: [String] = ["old"],
                              overrides: [String: FirebaseSourceValue] = [:], account: String = "account") -> FirebaseSourceDocument {
        var fields: [String: FirebaseSourceValue] = ["accountId": .string(account), "projectId": .string("project"),
            "invoiceId": .string("invoice"), "kind": .string("paymentCanceled"), "fromStatus": .string("paid"),
            "toStatus": .string("sent"), "createdAt": .timestamp(seconds: "100", nanoseconds: 42),
            "settlementTransactionIds": .array(refs.map { .string($0) }), "unknown": .bytes(base64: "AA==")]
        fields.merge(overrides) { _, new in new }
        return document("invoiceEvents", id, fields, account: account)
    }
    private static func payment(_ id: String = "old", overrides: [String: FirebaseSourceValue] = [:],
                                account: String = "account") -> FirebaseSourceDocument {
        var fields: [String: FirebaseSourceValue] = ["projectId": .string("project"), "settlementInvoiceId": .string("invoice"),
            "type": .string("paymentToBusiness"), "status": .string("canceled"), "amountCents": .integer("100")]
        fields.merge(overrides) { _, new in new }
        return document("transactions", id, fields, account: account)
    }
    private static func review(_ documents: [FirebaseSourceDocument]) -> FirebaseInvoiceCancellationEvidence {
        .review(invoice: invoice, documents: documents, sourceAccountID: "account")
    }
    private static func removing(_ key: String, from document: FirebaseSourceDocument) -> FirebaseSourceDocument {
        guard case .map(let fields) = document.fields else { preconditionFailure("Expected map") }
        return .init(accountScopeID: document.accountScopeID, documentPathSegments: document.documentPathSegments,
            entityCode: document.entityCode, evidenceKind: document.evidenceKind,
            fields: .map(fields.filter { !$0.key.utf8.elementsEqual(key.utf8) }), sourceRecordID: document.sourceRecordID)
    }

    @Test("Explicit cancellation resolves old payment while recollected active money remains separate")
    func canceledThenRecollected() {
        let documents = [Self.event(), Self.payment(), Self.payment("new", overrides: ["status": .null])]
        let result = Self.review(documents)
        #expect(result.issues.isEmpty)
        #expect(result.events.count == 1)
        #expect(result.events[0].issues.isEmpty)
        #expect(result.events[0].referencedPayments == [documents[1]])
        #expect(result.unclaimedCanceledPayments.isEmpty)
        #expect(result.suppliedDocuments == documents)
        #expect(result.invoice == Self.invoice)
    }

    @Test("Missing evidence never becomes a cancellation inferred from status")
    func missingEvidence() {
        let noEvent = Self.review([Self.payment()])
        #expect(noEvent.issues.contains(.missingEvent))
        #expect(noEvent.unclaimedCanceledPayments == [Self.payment()])
        let noPayment = Self.review([Self.event()])
        #expect(noPayment.events[0].issues.contains(.missingPayment))
        let unclaimed = Self.review([Self.event(), Self.payment(), Self.payment("another")])
        #expect(unclaimed.unclaimedCanceledPayments == [Self.payment("another")])
    }

    @Test("Conflicting duplicate paths remain visible even when links change or disappear")
    func duplicateDocuments() {
        for replacement in [FirebaseSourceValue.string("different"), .null] {
            let payments = [Self.event(), Self.payment(), Self.payment(overrides: ["settlementInvoiceId": replacement])]
            let result = Self.review(payments)
            #expect(result.events[0].issues.contains(.duplicateDocument))
            #expect(result.events[0].referencedPayments.count == 2)
            #expect(result.suppliedDocuments == payments)
            let events = Self.review([Self.event(), Self.event(overrides: ["invoiceId": replacement]), Self.payment()])
            #expect(events.events.allSatisfy { $0.issues.contains(.duplicateDocument) })
            #expect(events.unclaimedCanceledPayments.count == 1)
        }
        let missingPaymentLink = Self.removing("settlementInvoiceId", from: Self.payment())
        let payments = Self.review([Self.event(), Self.payment(), missingPaymentLink])
        #expect(payments.events[0].issues.contains(.duplicateDocument))
        #expect(payments.events[0].referencedPayments.count == 2)
        #expect(payments.events[0].issues.contains(.paymentScopeMismatch))
        let missingEventLink = Self.removing("invoiceId", from: Self.event())
        let events = Self.review([Self.event(), missingEventLink, Self.payment()])
        #expect(events.events.allSatisfy { $0.issues.contains(.duplicateDocument) })
        #expect(events.events[1].issues.contains(.eventScopeMismatch))
        #expect(events.suppliedDocuments[1] == missingEventLink)
    }

    @Test("References cannot claim active, wrong-kind or foreign-scope payments")
    func rejectedPayments() {
        let cases: [(String, FirebaseSourceValue, FirebaseInvoiceCancellationIssue)] = [
            ("status", .null, .paymentNotCanceled), ("type", .string("refund"), .wrongPaymentType),
            ("projectId", .string("other"), .paymentScopeMismatch),
            ("settlementInvoiceId", .string("other"), .paymentScopeMismatch),
            ("accountId", .string("other"), .invalidPayment)]
        for (field, value, issue) in cases {
            let result = Self.review([Self.event(), Self.payment(overrides: [field: value])])
            #expect(result.events[0].issues.contains(issue))
        }
        #expect(Self.review([Self.event(), Self.payment(account: "foreign")]).events[0].issues.contains(.missingPayment))
        #expect(Self.review([Self.event(account: "foreign"), Self.payment()]).events[0].issues.contains(.eventScopeMismatch))
    }

    @Test("Malformed event shape, transitions, timestamps and references stay unresolved")
    func malformedEvents() {
        let cases: [(String, FirebaseSourceValue, FirebaseInvoiceCancellationIssue)] = [
            ("kind", .string("refund"), .invalidTransition), ("fromStatus", .string("draft"), .invalidTransition),
            ("toStatus", .string("paid"), .invalidTransition), ("projectId", .null, .eventScopeMismatch),
            ("createdAt", .string("yesterday"), .invalidTimestamp),
            ("createdAt", .timestamp(seconds: "100", nanoseconds: -1), .invalidTimestamp),
            ("settlementTransactionIds", .array([]), .invalidPaymentReferences),
            ("settlementTransactionIds", .array([.integer("1")]), .invalidPaymentReferences)]
        for (field, value, issue) in cases {
            let documents = [Self.event(overrides: [field: value]), Self.payment()]
            let result = Self.review(documents)
            #expect(result.events[0].issues.contains(issue))
            #expect(result.unclaimedCanceledPayments == [documents[1]])
            #expect(result.suppliedDocuments == documents)
        }
    }

    @Test("Duplicate references within and across events are ambiguous; UTF8 IDs stay distinct")
    func referenceIdentity() {
        let repeated = Self.review([Self.event(refs: ["old", "old"]), Self.payment()])
        #expect(repeated.events[0].issues.contains(.duplicatePaymentReference))
        let shared = Self.review([Self.event(), Self.event("second"), Self.payment()])
        #expect(shared.events.allSatisfy { $0.issues.contains(.duplicatePaymentReference) })
        let partial = Self.review([Self.event(), Self.event("malformed", overrides: [
            "settlementTransactionIds": .array([.string("old"), .integer("7")])]), Self.payment()])
        #expect(partial.events.allSatisfy { $0.issues.contains(.duplicatePaymentReference) })
        #expect(partial.events[1].issues.contains(.invalidPaymentReferences))
        #expect(partial.unclaimedCanceledPayments.count == 1)
        let composed = "é", decomposed = "e\u{301}"
        let distinct = Self.review([Self.event(refs: [composed, decomposed]), Self.payment(composed), Self.payment(decomposed)])
        #expect(distinct.events[0].issues.isEmpty)
        #expect(distinct.events[0].referencedPayments.count == 2)
        #expect(distinct.unclaimedCanceledPayments.isEmpty)
    }

    @Test("Invalid Invoice scope and conflicting Invoice copies remain explicit")
    func invoiceIdentity() {
        let wrong = Self.document("invoices", "invoice", ["projectId": .string("project")], account: "other")
        let result = FirebaseInvoiceCancellationEvidence.review(invoice: wrong, documents: [Self.event(), Self.payment()], sourceAccountID: "account")
        #expect(result.issues.contains(.invalidInvoice))
        #expect(result.suppliedDocuments.count == 2)
        let duplicate = Self.document("invoices", "invoice", ["projectId": .string("different")])
        #expect(Self.review([Self.event(), Self.payment(), duplicate]).issues.contains(.duplicateDocument))
        #expect(Self.review([Self.event(), Self.payment(), duplicate, duplicate]).issues.contains(.duplicateDocument))
        #expect(Self.review([Self.event(), Self.payment(), Self.invoice, Self.invoice]).issues.contains(.duplicateDocument))
        #expect(Self.review([Self.event(), Self.payment(), Self.invoice]).issues.isEmpty)
    }
}
