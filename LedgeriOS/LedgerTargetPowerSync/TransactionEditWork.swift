import Foundation
import LedgerTargetCore
import PowerSync

/// The two Transaction editors share local admission and recovery, not their
/// product payloads or concurrency rules.
enum TransactionEditWork: Sendable {
    case details(EditTransactionDetailsCommand)
    case receiptLines(EditTransactionReceiptLinesCommand)

    enum Kind: Sendable {
        case details, receiptLines
        var namespace: AccountBoundOperationFamily {
            self == .details ? .transactionDetailsEdit : .transactionReceiptLinesEdit
        }
        var family: LocalOperationCommandFamily {
            self == .details ? .editTransactionDetails : .editTransactionReceiptLines
        }
        var table: String { family.insertOnlyCommandTable! }
        var resultCode: String { self == .details ? "transaction_details_updated" : "transaction_receipt_lines_updated" }
        var rejections: Set<String> {
            self == .details ? EditTransactionDetailsServerResult.rejections : EditTransactionReceiptLinesServerResult.rejections
        }
        func decode(_ json: String) throws -> TransactionEditWork {
            let bytes = Data("{\"envelope\":\(json)}".utf8)
            switch self {
            case .details: return .details(try OperationContractCodec.decode(EditTransactionDetailsCommand.self, from: bytes))
            case .receiptLines: return .receiptLines(try OperationContractCodec.decode(EditTransactionReceiptLinesCommand.self, from: bytes))
            }
        }
    }
    var kind: Kind { switch self { case .details: .details; case .receiptLines: .receiptLines } }
    var operationId: OperationID {
        switch self { case .details(let c): c.envelope.operationId; case .receiptLines(let c): c.envelope.operationId }
    }
    var accountId: AccountID { scope.accountId }
    var actorPrincipalId: PrincipalID {
        switch self { case .details(let c): c.envelope.actorPrincipalId; case .receiptLines(let c): c.envelope.actorPrincipalId }
    }
    var contractVersion: OperationContractVersion {
        switch self { case .details(let c): c.envelope.contractVersion; case .receiptLines(let c): c.envelope.contractVersion }
    }
    var scope: TransactionScope {
        switch self { case .details(let c): c.envelope.payload.scope; case .receiptLines(let c): c.envelope.payload.scope }
    }
    var transactionId: TransactionID {
        switch self { case .details(let c): c.envelope.payload.transactionId; case .receiptLines(let c): c.envelope.payload.transactionId }
    }
    var fingerprint: String {
        get throws {
            switch self {
            case .details(let c): try EditTransactionDetailsUploadRequest(c).fingerprint
            case .receiptLines(let c): try EditTransactionReceiptLinesUploadRequest(c).fingerprint
            }
        }
    }
    var json: String {
        get throws {
            let bytes: Data
            switch self {
            case .details(let c): bytes = try OperationContractCodec.encode(c.envelope)
            case .receiptLines(let c): bytes = try OperationContractCodec.encode(c.envelope)
            }
            return String(decoding: bytes, as: UTF8.self)
        }
    }
    func matchesReview(_ current: TransactionDetailSnapshot) -> Bool {
        switch self {
        case .details(let c): current.detailsRevision == c.envelope.payload.expectedRevision
        case .receiptLines(let c): current.amount.currency == c.envelope.payload.currency
            && current.receipt?.lines == c.envelope.payload.expectedLines
        }
    }

    /// Call only after LocalOperationIdentityGuard validates local/result identity.
    /// A result may arrive before its Transaction; a later Transaction edit still
    /// proves readback. Stream timestamps and current line equality do not.
    func hasReadback(_ current: TransactionDetailSnapshot, local: any Transaction) throws -> Bool {
        switch self {
        case .details(let c):
            return current.detailsRevision.map { $0 > c.envelope.payload.expectedRevision } ?? false
        case .receiptLines:
            let revision = try local.getOptional(sql: """
                SELECT result.receipt_lines_revision, payment.receipt_lines_revision
                FROM spike_operation_results result JOIN spike_transactions payment
                  ON payment.account_id=result.account_id AND payment.id=result.subject_id
                WHERE result.id=? AND result.phase='applied' AND result.account_id=? AND payment.id=?
                """, parameters: [operationId.rawValue,accountId.rawValue,transactionId.rawValue]) {
                    (try $0.getStringOptional(index: 0), try $0.getStringOptional(index: 1))
                }
            guard let revision, let applied = revision.0, let downloaded = revision.1 else { return false }
            guard let target = Int64(applied), target > 0, String(target) == applied,
                  let actual = Int64(downloaded), actual > 0, String(actual) == downloaded else {
                throw LocalOperationIdentityGuardFailure.malformedEvidence
            }
            return actual >= target
        }
    }
}
