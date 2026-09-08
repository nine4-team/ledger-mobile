import Foundation
import LedgerTargetCore

public enum FirebaseClientPaymentConversionFailure: Equatable, Sendable {
    case invalidSourceDocument
    case sourceScopeMismatch
    case targetRequiresProjectScope
    case requiresDifferentEconomicMapping
    case requiresExactPositiveAmount
    case requiresCancellationMapping
    case requiresStatusMapping
}

public enum FirebaseClientPaymentConversionResult: Equatable, Sendable {
    case mapped(source: FirebaseSourceDocument, classification: TransactionClassification, amountCents: Int64)
    case unresolved(source: FirebaseSourceDocument, reason: FirebaseClientPaymentConversionFailure)
}

/// Converts the explicit legacy client-payment meaning, not a movement or a
/// purchase whose payer must first be established. Original settlement links
/// remain on the retained source document. No Invoice/Item paid state is inferred.
public enum FirebaseClientPaymentConversion {
    /// The caller supplies a previously reconciled source→target Project scope
    /// mapping. This package-internal transform is not an import/authorization
    /// entry point and does not allocate IDs, persist rows or merge payments.
    package static func convert(
        _ document: FirebaseSourceDocument,
        sourceAccountID: String,
        sourceProjectID: String,
        targetScope: TransactionScope
    ) -> FirebaseClientPaymentConversionResult {
        func unresolved(_ reason: FirebaseClientPaymentConversionFailure) -> FirebaseClientPaymentConversionResult {
            .unresolved(source: document, reason: reason)
        }
        let path = document.documentPathSegments
        guard document.evidenceKind == .record, path.count == 4,
              path[0] == "accounts", path[2] == "transactions",
              (try? FirebaseSourceValue.reference(segments: path).validated()) != nil,
              case .map(let fields) = document.fields,
              (try? document.fields.validated()) != nil else {
            return unresolved(.invalidSourceDocument)
        }
        func value(_ key: String) -> FirebaseSourceValue? {
            fields.first { $0.key.utf8.elementsEqual(key.utf8) }?.value
        }
        guard document.accountScopeID.utf8.elementsEqual(sourceAccountID.utf8),
              path[1].utf8.elementsEqual(sourceAccountID.utf8),
              (try? FirebaseSourceValue.reference(segments: ["accounts", sourceAccountID, "projects", sourceProjectID]).validated()) != nil,
              case .string(let projectID) = value("projectId"),
              projectID.utf8.elementsEqual(sourceProjectID.utf8) else {
            return unresolved(.sourceScopeMismatch)
        }
        if let account = value("accountId") {
            guard case .string(let embedded) = account,
                  embedded.utf8.elementsEqual(sourceAccountID.utf8) else {
                return unresolved(.sourceScopeMismatch)
            }
        }
        guard targetScope.ownerKind == .project else {
            return unresolved(.targetRequiresProjectScope)
        }
        guard case .string(let type) = value("type"),
              ["paymenttobusiness", "payment_to_business", "payment-to-business"].contains(type.lowercased()) else {
            return unresolved(.requiresDifferentEconomicMapping)
        }
        // Canceled payment corrections retain their source/history but are not
        // active Client money. Preserve unknown status as an explicit mapping
        // gap rather than inheriting the source reader's unknown-string fallback.
        if let status = value("status"), status != .null {
            guard case .string(let rawStatus) = status else {
                return unresolved(.requiresStatusMapping)
            }
            switch rawStatus.lowercased() {
            case "canceled", "cancelled": return unresolved(.requiresCancellationMapping)
            case "pending", "completed": break // Known legacy non-cancellation values.
            default: return unresolved(.requiresStatusMapping)
            }
        }
        // Do not round doubles or infer a refund/zero-dollar collection policy.
        guard case .integer(let rawAmount) = value("amountCents"),
              let amount = Int64(rawAmount), amount > 0 else {
            return unresolved(.requiresExactPositiveAmount)
        }
        guard let classification = try? TransactionClassification(type: .purchase,
            scope: targetScope, role: .standalone) else {
            return unresolved(.targetRequiresProjectScope)
        }
        return .mapped(source: document, classification: classification, amountCents: amount)
    }
}
