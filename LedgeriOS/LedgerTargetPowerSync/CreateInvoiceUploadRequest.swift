import CryptoKit
import Foundation
import LedgerTargetCore

/// Provider encoding only. Preserve exact money/revisions as decimal strings.
struct CreateInvoiceUploadRequest: Sendable {
    let commandJSON: String
    let fingerprint: String
    init(_ command: CreateInvoiceCommand) throws {
        let e = command.envelope, p = e.payload
        guard let project = p.selection.scope.projectId, let client = p.selection.scope.clientId else {
            throw LiveInvoiceSelection.Failure.requiresProject
        }
        let wire = Wire(operationId: e.operationId.rawValue, accountId: e.accountId.rawValue,
            actorPrincipalId: e.actorPrincipalId.rawValue, projectId: project.rawValue, clientId: client.rawValue,
            invoiceId: p.invoiceId.rawValue, contractVersion: e.contractVersion.rawValue,
            createdAtMs: String(Int64((e.clientCreatedAt.timeIntervalSince1970 * 1000).rounded())),
            name: p.name, notes: p.notes, sources: p.selection.lines.map(Source.init))
        let data = try OperationContractCodec.encode(wire)
        commandJSON = String(decoding: data, as: UTF8.self)
        fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    var rpcBody: Data { get throws { try OperationContractCodec.encode(Body(p_command: commandJSON)) } }
    private struct Body: Encodable { let p_command: String }
    private struct Wire: Encodable {
        let operationId, accountId, actorPrincipalId, projectId, clientId, invoiceId, contractVersion, createdAtMs: String
        let name, notes: String
        let sources: [Source]
    }
    private struct Source: Encodable {
        let kind, sourceId, expectedRevision, amountMinorUnits, currency: String
        init(_ line: LiveInvoiceSelection.Line) {
            switch line.source {
            case .itemOccurrence(let id): kind = "item"; sourceId = id.rawValue
            case .expense(let id): kind = "expense"; sourceId = id.rawValue
            case .feeInstallment(let id): kind = "fee_installment"; sourceId = id.rawValue
            }
            expectedRevision = String(line.expectedRevision)
            amountMinorUnits = String(line.reviewedAmount.minorUnits)
            currency = line.reviewedAmount.currency.rawValue
        }
    }
}
