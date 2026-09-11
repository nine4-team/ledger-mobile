import Foundation
import LedgerTargetCore

package enum FirebaseClientPaymentImportFailure: Error {
    case unresolvedBatch
}

/// Parameter data for the private SQL primitive, never executable SQL or import
/// authorization. Cents cross JSON as decimal text, preserving all Int64 values.
package struct FirebaseClientPaymentImportParameters: Encodable, Equatable, Sendable {
    package let p_id: String
    package let p_account_id: String
    package let p_project_id: String
    package let p_client_id: String
    package let p_amount: String
    package let p_currency: String
    package let p_source_account: String
    package let p_source_document: String
    package let p_source_bytes: String

    package static func make(batch: FirebasePaymentBatchResult, currency: CurrencyCode) throws -> [Self] {
        guard batch.isFullyReconciled else { throw FirebaseClientPaymentImportFailure.unresolvedBatch }
        return try batch.entries.map { entry in
            guard entry.issues.isEmpty, let id = entry.targetID,
                  case .mapped(let source, let classification, let cents) = entry.conversion,
                  let project = classification.scope.projectId, let client = classification.scope.clientId,
                  source.documentPathSegments.count == 4 else {
                throw FirebaseClientPaymentImportFailure.unresolvedBatch
            }
            // Preserve the whole source envelope, not merely the amount or fields.
            let bytes = try source.canonicalEvidenceData()
            return .init(p_id: id.rawValue, p_account_id: classification.scope.accountId.rawValue,
                p_project_id: project.rawValue, p_client_id: client.rawValue, p_amount: String(cents),
                p_currency: currency.rawValue, p_source_account: source.accountScopeID,
                p_source_document: source.documentPathSegments[3],
                p_source_bytes: "\\x" + bytes.map { String(format: "%02x", $0) }.joined())
        }
    }
}
