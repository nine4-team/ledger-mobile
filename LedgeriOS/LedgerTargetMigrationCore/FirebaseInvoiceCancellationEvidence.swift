import Foundation

package enum FirebaseInvoiceCancellationIssue: Equatable, Sendable {
    case invalidInvoice, missingEvent, duplicateDocument, invalidEvent, eventScopeMismatch
    case invalidTransition, invalidTimestamp, invalidPaymentReferences, duplicatePaymentReference
    case missingPayment, invalidPayment, paymentScopeMismatch, paymentNotCanceled, wrongPaymentType
    case unclaimedCanceledPayment
}

package struct FirebaseInvoiceCancellationEventEvidence: Sendable {
    package let event: FirebaseSourceDocument
    package let referencedPayments: [FirebaseSourceDocument]
    package let issues: [FirebaseInvoiceCancellationIssue]
}

/// Historical evidence only: resolving an explicit cancellation never creates a
/// cash refund, approves an import, or reconstructs an Invoice's paid state.
/// This relation review does not validate or map canceled payment amounts.
package struct FirebaseInvoiceCancellationEvidence: Sendable {
    package let invoice: FirebaseSourceDocument
    package let suppliedDocuments: [FirebaseSourceDocument]
    package let events: [FirebaseInvoiceCancellationEventEvidence]
    package let unclaimedCanceledPayments: [FirebaseSourceDocument]
    /// Invoice/batch issues only. Consumers must also inspect every event's issues;
    /// an empty array here does not establish that the event evidence is resolved.
    package let issues: [FirebaseInvoiceCancellationIssue]

    /// Pass candidate invoiceEvents and payments, including rejected/conflicting
    /// copies. Current Invoice status may be paid again after recollection.
    package static func review(invoice: FirebaseSourceDocument, documents: [FirebaseSourceDocument],
                               sourceAccountID: String) -> Self {
        typealias V = CancellationSource
        var issues: [FirebaseInvoiceCancellationIssue] = []
        var events: [FirebaseInvoiceCancellationEventEvidence] = []
        var unclaimed: [FirebaseSourceDocument] = []
        func result() -> Self {
            .init(invoice: invoice, suppliedDocuments: documents, events: events,
                  unclaimedCanceledPayments: unclaimed, issues: issues)
        }
        let path = invoice.documentPathSegments
        guard V.valid(invoice, collection: "invoices", account: sourceAccountID),
              let project = V.id(V.field(invoice, "projectId")) else {
            issues.append(.invalidInvoice); return result()
        }
        let invoiceID = path[3]
        // Group before filtering by links: a second copy with changed or missing
        // links cannot disappear from the ambiguity check.
        let copies = Dictionary(grouping: documents) { V.path($0) }
        if let invoiceCopies = copies[V.path(invoice)],
           invoiceCopies.count > 1 || invoiceCopies.contains(where: { !V.sameDocument($0, invoice) }) {
            issues.append(.duplicateDocument)
        }
        let candidates = documents.filter {
            let p = $0.documentPathSegments
            return p.count >= 3 && V.equal(p[2], "invoiceEvents")
        }
        if candidates.isEmpty { issues.append(.missingEvent) }
        // References repeated within or across events remain ambiguous, even if
        // one event has a malformed payload or points to a different Invoice.
        let references = candidates.flatMap { V.partialReferences($0) }
        let referenceCounts = Dictionary(grouping: references) { Data($0.utf8) }.mapValues(\.count)
        var claimed = Set<Data>()
        for event in candidates {
            var eventIssues: [FirebaseInvoiceCancellationIssue] = []
            var payments: [FirebaseSourceDocument] = []
            if (copies[V.path(event)]?.count ?? 0) > 1 { eventIssues.append(.duplicateDocument) }
            if !V.valid(event, collection: "invoiceEvents", account: sourceAccountID) {
                eventIssues.append(.invalidEvent)
            }
            if !V.matches(event, "accountId", sourceAccountID)
                || !V.matches(event, "projectId", project) || !V.matches(event, "invoiceId", invoiceID) {
                eventIssues.append(.eventScopeMismatch)
            }
            if !V.matches(event, "kind", "paymentCanceled") || !V.matches(event, "fromStatus", "paid")
                || !V.matches(event, "toStatus", "sent") { eventIssues.append(.invalidTransition) }
            if case .timestamp = V.field(event, "createdAt"),
               let timestamp = V.field(event, "createdAt"), (try? timestamp.validated()) != nil {} else {
                eventIssues.append(.invalidTimestamp)
            }
            let ids = V.references(event)
            if ids?.isEmpty != false { eventIssues.append(.invalidPaymentReferences) }
            for id in V.partialReferences(event) {
                if (referenceCounts[Data(id.utf8)] ?? 0) > 1 { eventIssues.append(.duplicatePaymentReference) }
                let paymentPath = ["accounts", sourceAccountID, "transactions", id].map { Data($0.utf8) }
                guard let matches = copies[paymentPath], !matches.isEmpty else {
                    eventIssues.append(.missingPayment); continue
                }
                payments.append(contentsOf: matches)
                if matches.count > 1 { eventIssues.append(.duplicateDocument) }
                for payment in matches {
                    if !V.valid(payment, collection: "transactions", account: sourceAccountID) {
                        eventIssues.append(.invalidPayment)
                    }
                    if !V.matches(payment, "projectId", project) || !V.matches(payment, "settlementInvoiceId", invoiceID) {
                        eventIssues.append(.paymentScopeMismatch)
                    }
                    if !V.canceled(payment) { eventIssues.append(.paymentNotCanceled) }
                    let type = V.string(V.field(payment, "type"))?.lowercased() ?? ""
                    if !["paymenttobusiness", "payment_to_business", "payment-to-business"].contains(type) {
                        eventIssues.append(.wrongPaymentType)
                    }
                }
            }
            if eventIssues.isEmpty { claimed.formUnion((ids ?? []).map { Data($0.utf8) }) }
            events.append(.init(event: event, referencedPayments: payments, issues: eventIssues))
        }
        unclaimed = documents.filter { payment in
            let p = payment.documentPathSegments
            return p.count == 4 && V.equal(p[2], "transactions") && V.canceled(payment)
                && V.matches(payment, "settlementInvoiceId", invoiceID)
                && (!V.valid(payment, collection: "transactions", account: sourceAccountID)
                    || !V.matches(payment, "projectId", project) || !claimed.contains(Data(p[3].utf8)))
        }
        if !unclaimed.isEmpty { issues.append(.unclaimedCanceledPayment) }
        return result()
    }
}

private enum CancellationSource {
    static func equal(_ a: String, _ b: String) -> Bool { a.utf8.elementsEqual(b.utf8) }
    static func path(_ document: FirebaseSourceDocument) -> [Data] { document.documentPathSegments.map { Data($0.utf8) } }
    static func sameDocument(_ a: FirebaseSourceDocument, _ b: FirebaseSourceDocument) -> Bool {
        equal(a.accountScopeID, b.accountScopeID) && path(a) == path(b)
            && equal(a.entityCode, b.entityCode) && a.evidenceKind == b.evidenceKind
            && equal(a.sourceRecordID, b.sourceRecordID)
            && (try? FirebaseSourceFixtureCatalog.canonicalData(for: a.fields))
                == (try? FirebaseSourceFixtureCatalog.canonicalData(for: b.fields))
    }
    static func field(_ document: FirebaseSourceDocument, _ key: String) -> FirebaseSourceValue? {
        guard case .map(let entries) = document.fields else { return nil }
        return entries.first { equal($0.key, key) }?.value
    }
    static func string(_ value: FirebaseSourceValue?) -> String? {
        guard case .string(let raw) = value else { return nil }; return raw
    }
    static func id(_ value: FirebaseSourceValue?) -> String? {
        guard let raw = string(value), (try? FirebaseSourceValue.reference(segments: ["ids", raw]).validated()) != nil else { return nil }
        return raw
    }
    static func matches(_ document: FirebaseSourceDocument, _ key: String, _ expected: String) -> Bool {
        string(field(document, key)).map { equal($0, expected) } == true
    }
    static func valid(_ document: FirebaseSourceDocument, collection: String, account: String) -> Bool {
        let p = document.documentPathSegments
        guard document.evidenceKind == .record, p.count == 4, equal(p[0], "accounts"), equal(p[1], account),
              equal(p[2], collection), equal(document.accountScopeID, account),
              (try? FirebaseSourceValue.reference(segments: p).validated()) != nil,
              case .map = document.fields, (try? document.fields.validated()) != nil else { return false }
        return field(document, "accountId") == nil || matches(document, "accountId", account)
    }
    static func canceled(_ document: FirebaseSourceDocument) -> Bool {
        ["canceled", "cancelled"].contains(string(field(document, "status"))?.lowercased() ?? "")
    }
    static func references(_ document: FirebaseSourceDocument) -> [String]? {
        guard case .array(let raw) = field(document, "settlementTransactionIds") else { return nil }
        let ids = raw.compactMap { id($0) }
        return ids.count == raw.count ? ids : nil
    }
    static func partialReferences(_ document: FirebaseSourceDocument) -> [String] {
        guard case .array(let raw) = field(document, "settlementTransactionIds") else { return [] }
        return raw.compactMap { id($0) }
    }
}
