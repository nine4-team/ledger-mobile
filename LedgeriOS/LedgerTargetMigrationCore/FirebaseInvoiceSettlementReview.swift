import Foundation
import LedgerTargetCore

package enum FirebaseInvoiceSettlementIssue: Equatable, Sendable {
    case invalidInvoice, invoiceNotPaid, missingOrInvalidLines, duplicateLineID
    case lineTotalMismatch, paymentScopeOrShape, duplicatePayment
    case canceledPaymentHistory, noActivePayment, multipleActivePayments
    case paymentLineCoverageMismatch, paymentAmountMismatch
}

package enum FirebaseInvoiceLineSourceIssue: Equatable, Sendable {
    case invalidLine, missingSource, duplicateSource, invalidSource, projectMismatch
    case itemOccurrenceNotMapped, transactionMeaningNotMapped, feeNotMapped, manualAdjustmentNotMapped
}

package struct FirebaseInvoiceLineSourceReview: Sendable {
    package let line: FirebaseSourceValue
    package let source: FirebaseSourceDocument?
    package let issues: [FirebaseInvoiceLineSourceIssue]
}

package struct FirebaseInvoiceSourcesReview: Sendable {
    package let settlement: FirebaseInvoiceSettlementReview
    package let suppliedDocuments: [FirebaseSourceDocument]
    package let lines: [FirebaseInvoiceLineSourceReview]
}

package struct FirebaseInvoiceSettlementReview: Sendable {
    package let invoice: FirebaseSourceDocument
    package let suppliedPayments: [FirebaseSourceDocument]
    package let issues: [FirebaseInvoiceSettlementIssue]
    /// Narrow source evidence only. Does not resolve Item occurrences, cancellation
    /// events, export completeness or authorize a target collection/paid snapshot.
    package var hasSinglePaymentLineCoverage: Bool { issues.isEmpty }

    /// Resolve raw source identity, not accounting meaning. An Item may now be in
    /// Inventory or another Project; its current location cannot rewrite a paid
    /// Invoice's historical occurrence. Fee installments use their real nested
    /// Project collection, never an Account-wide ID/name match.
    package func resolveSources(in documents: [FirebaseSourceDocument]) -> FirebaseInvoiceSourcesReview {
        func field(_ value: FirebaseSourceValue, _ key: String) -> FirebaseSourceValue? {
            guard case .map(let entries) = value else { return nil }
            return entries.first { $0.key.utf8.elementsEqual(key.utf8) }?.value
        }
        func string(_ value: FirebaseSourceValue?) -> String? {
            guard case .string(let result) = value else { return nil }
            return result
        }
        guard !issues.contains(.invalidInvoice), invoice.documentPathSegments.count == 4,
              let project = string(field(invoice.fields, "projectId")),
              case .array(let rawLines) = field(invoice.fields, "lines") else {
            return .init(settlement: self, suppliedDocuments: documents, lines: [])
        }
        let account = invoice.documentPathSegments[1]
        let copies = Dictionary(grouping: documents) { $0.documentPathSegments.map { Data($0.utf8) } }
        let resolved: [FirebaseInvoiceLineSourceReview] = rawLines.map { line in
            func reject(_ issue: FirebaseInvoiceLineSourceIssue) -> FirebaseInvoiceLineSourceReview {
                .init(line: line, source: nil, issues: [issue])
            }
            guard let lineID = string(field(line, "id")),
                  (try? FirebaseSourceValue.reference(segments: ["lines", lineID]).validated()) != nil,
                  let type = string(field(line, "sourceType"))?.lowercased(),
                  (try? line.validated()) != nil else { return reject(.invalidLine) }
            if type == "manual" { return reject(.manualAdjustmentNotMapped) }
            guard let id = string(field(line, "sourceId")) else { return reject(.invalidLine) }
            let path: [String]
            let mappingIssue: FirebaseInvoiceLineSourceIssue
            switch type {
            case "item": path = ["accounts", account, "items", id]; mappingIssue = .itemOccurrenceNotMapped
            case "transaction": path = ["accounts", account, "transactions", id]; mappingIssue = .transactionMeaningNotMapped
            case "feeinstallment": path = ["accounts", account, "projects", project, "feeInstallments", id]; mappingIssue = .feeNotMapped
            default: return reject(.invalidLine)
            }
            guard (try? FirebaseSourceValue.reference(segments: path).validated()) != nil else { return reject(.invalidLine) }
            guard let matches = copies[path.map { Data($0.utf8) }], !matches.isEmpty else { return reject(.missingSource) }
            guard matches.count == 1 else { return reject(.duplicateSource) }
            let source = matches[0]
            guard source.evidenceKind == .record, source.accountScopeID.utf8.elementsEqual(account.utf8),
                  case .map = source.fields, (try? source.fields.validated()) != nil else { return reject(.invalidSource) }
            if let embedded = field(source.fields, "accountId"),
               string(embedded).map({ $0.utf8.elementsEqual(account.utf8) }) != true { return reject(.invalidSource) }
            if type == "transaction", string(field(source.fields, "projectId")).map({ $0.utf8.elementsEqual(project.utf8) }) != true {
                return reject(.projectMismatch)
            }
            if type == "feeinstallment", let embeddedProject = field(source.fields, "projectId"),
               string(embeddedProject).map({ $0.utf8.elementsEqual(project.utf8) }) != true { return reject(.projectMismatch) }
            return .init(line: line, source: source, issues: [mappingIssue])
        }
        return .init(settlement: self, suppliedDocuments: documents, lines: resolved)
    }

    package static func review(invoice: FirebaseSourceDocument, payments: [FirebaseSourceDocument],
                               sourceAccountID: String, targetScope: TransactionScope) -> Self {
        var issues: [FirebaseInvoiceSettlementIssue] = []
        func result() -> Self { .init(invoice: invoice, suppliedPayments: payments, issues: issues) }
        func equal(_ lhs: String, _ rhs: String) -> Bool { lhs.utf8.elementsEqual(rhs.utf8) }
        func field(_ value: FirebaseSourceValue, _ key: String) -> FirebaseSourceValue? {
            guard case .map(let entries) = value else { return nil }
            return entries.first { equal($0.key, key) }?.value
        }
        func string(_ value: FirebaseSourceValue?) -> String? {
            guard case .string(let raw) = value else { return nil }
            return raw
        }
        func identifier(_ value: FirebaseSourceValue?) -> String? {
            guard let raw = string(value),
                  (try? FirebaseSourceValue.reference(segments: ["references", raw]).validated()) != nil else { return nil }
            return raw
        }
        let path = invoice.documentPathSegments
        guard invoice.evidenceKind == .record, path.count == 4,
              path[0] == "accounts", path[2] == "invoices", equal(path[1], sourceAccountID),
              equal(invoice.accountScopeID, sourceAccountID),
              (try? FirebaseSourceValue.reference(segments: path).validated()) != nil,
              (try? invoice.fields.validated()) != nil,
              let project = identifier(field(invoice.fields, "projectId")),
              targetScope.ownerKind == .project else {
            issues.append(.invalidInvoice); return result()
        }
        if let embedded = field(invoice.fields, "accountId"),
           string(embedded).map({ equal($0, sourceAccountID) }) != true {
            issues.append(.invalidInvoice); return result()
        }
        if string(field(invoice.fields, "status"))?.lowercased() != "paid" { issues.append(.invoiceNotPaid) }
        guard case .array(let lines) = field(invoice.fields, "lines"), !lines.isEmpty else {
            issues.append(.missingOrInvalidLines); return result()
        }
        var lineIDs = Set<Data>()
        var reversePaymentIDs = Set<Data>()
        var lineTotal: Int64 = 0
        for line in lines {
            guard let id = identifier(field(line, "id")),
                  case .integer(let amountText) = field(line, "amountCents"), let amount = Int64(amountText), amount >= 0,
                  case .integer(let sign) = field(line, "sign"), ["1", "-1"].contains(sign),
                  let sourceType = string(field(line, "sourceType"))?.lowercased(),
                  ["item", "transaction", "feeinstallment", "manual"].contains(sourceType),
                  sourceType == "manual" || identifier(field(line, "sourceId")) != nil else {
                issues.append(.missingOrInvalidLines); return result()
            }
            if !lineIDs.insert(Data(id.utf8)).inserted { issues.append(.duplicateLineID) }
            if let reverse = field(line, "settlementTransactionIds"), reverse != .null {
                guard case .array(let refs) = reverse else { issues.append(.paymentScopeOrShape); return result() }
                let ids = refs.compactMap { identifier($0) }
                guard ids.count == refs.count else { issues.append(.paymentScopeOrShape); return result() }
                reversePaymentIDs.formUnion(ids.map { Data($0.utf8) })
            }
            let sum = lineTotal.addingReportingOverflow(sign == "1" ? amount : -amount)
            guard !sum.overflow else { issues.append(.lineTotalMismatch); return result() }
            lineTotal = sum.partialValue
        }
        if case .integer(let totalText) = field(invoice.fields, "totalCents"),
           let total = Int64(totalText), total == lineTotal, total > 0 {} else { issues.append(.lineTotalMismatch) }
        let linked = payments.filter { string(field($0.fields, "settlementInvoiceId")).map { equal($0, path[3]) } == true }
        // A conflicting copy may point elsewhere or omit its link; filtering
        // first must not hide ambiguity in an otherwise eligible payment ID.
        let paymentCopies = Dictionary(grouping: payments) { $0.documentPathSegments.map { Data($0.utf8) } }
        let linkedIDs = Set(linked.compactMap { $0.documentPathSegments.last }.map { Data($0.utf8) })
        if !reversePaymentIDs.isSubset(of: linkedIDs) { issues.append(.paymentScopeOrShape) }
        var active: [(FirebaseSourceDocument, Int64)] = []
        for payment in linked {
            if (paymentCopies[payment.documentPathSegments.map { Data($0.utf8) }]?.count ?? 0) > 1 {
                issues.append(.duplicatePayment)
            }
            switch FirebaseClientPaymentConversion.convert(payment, sourceAccountID: sourceAccountID,
                sourceProjectID: project, targetScope: targetScope) {
            case .mapped(_, _, let amount): active.append((payment, amount))
            case .unresolved(_, .requiresCancellationMapping): issues.append(.canceledPaymentHistory)
            case .unresolved: issues.append(.paymentScopeOrShape)
            }
        }
        guard active.count == 1 else {
            issues.append(active.isEmpty ? .noActivePayment : .multipleActivePayments); return result()
        }
        let (payment, amount) = active[0]
        if amount != lineTotal { issues.append(.paymentAmountMismatch) }
        if case .array(let selected) = field(payment.fields, "settlementInvoiceLineIds") {
            let selectedIDs = selected.compactMap { identifier($0) }
            let selectedSet = Set(selectedIDs.map { Data($0.utf8) })
            if selectedIDs.count != selected.count || selectedSet.count != selected.count || selectedSet != lineIDs {
                issues.append(.paymentLineCoverageMismatch)
            }
        } else { issues.append(.paymentLineCoverageMismatch) }
        return result()
    }
}
