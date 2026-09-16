import CryptoKit
import Foundation
import LedgerTargetCore

public protocol CreateInvoiceCommandApplying: Sendable {
    func apply(_ command: CreateInvoiceCommand) async throws -> CreateInvoiceServerResult
}
public protocol ReviseCreatedInvoiceCommandApplying: Sendable {
    func apply(_ command: ReviseCreatedInvoiceCommand) async throws -> CreateInvoiceServerResult
}

public struct CreateInvoiceServerResult: Decodable, Sendable {
    enum Failure: Error { case receiptMismatch }
    let operation_id, account_id, actor_principal_id, command_type, contract_version: String
    let command_fingerprint, envelope_sha256, subject_id, phase: String
    let request_sha256, result_code, error_code: String?
    let client_created_at_ms, server_received_at_ms, completed_at_ms: Int64

    func validate(for command: CreateInvoiceCommand) throws {
        let e = command.envelope, request = try CreateInvoiceUploadRequest(command)
        try validate(operation: e.operationId, account: e.accountId, actor: e.actorPrincipalId,
            invoice: e.payload.invoiceId, capturedAt: e.clientCreatedAt, request: request, revision: false)
    }
    func validate(for command: ReviseCreatedInvoiceCommand) throws {
        let e = command.envelope, request = try CreateInvoiceUploadRequest(command)
        try validate(operation: e.operationId, account: e.accountId, actor: e.actorPrincipalId,
            invoice: e.payload.invoice.invoiceId, capturedAt: e.clientCreatedAt, request: request, revision: true)
    }
    private func validate(operation: OperationID, account: AccountID, actor: PrincipalID, invoice: InvoiceID,
                          capturedAt: Date, request: CreateInvoiceUploadRequest, revision: Bool) throws {
        let allowedRejections = revision ? Self.rejections.union(Self.revisionRejections) : Self.rejections
        guard operation_id == operation.rawValue, account_id == account.rawValue,
              actor_principal_id == actor.rawValue, subject_id == invoice.rawValue,
              command_type == (revision ? "revise_created_invoice" : "create_invoice"),
              contract_version == (revision ? "invoice-revise-created-v1" : "invoice-create-v1"),
              command_fingerprint == request.fingerprint, envelope_sha256 == request.fingerprint,
              request_sha256 == nil,
              client_created_at_ms == Int64((capturedAt.timeIntervalSince1970 * 1000).rounded()),
              server_received_at_ms >= 0, completed_at_ms >= server_received_at_ms,
              (phase == "applied" && result_code == (revision ? "invoice_revised" : "invoice_created") && error_code == nil)
                || (phase == "rejected" && result_code == nil && allowedRejections.contains(error_code ?? "")) else {
            throw Failure.receiptMismatch
        }
    }
    static let revisionRejections: Set<String> = ["invoice_unavailable", "invoice_not_editable", "invoice_revision_conflict"]
    static let rejections: Set<String> = ["invoice_project_unavailable", "invoice_empty_selection",
        "invoice_duplicate_source", "invoice_source_invalid", "invoice_source_unavailable", "invoice_source_changed",
        "invoice_source_collected", "invoice_source_reserved", "invoice_currency_mismatch",
        "invoice_total_overflow", "invoice_integrity_conflict"]
}

/// Provider encoding only. Preserve exact money/revisions as decimal strings.
struct CreateInvoiceUploadRequest: Sendable {
    let commandJSON: String
    let fingerprint: String
    init(_ command: CreateInvoiceCommand) throws {
        let e = command.envelope, p = e.payload
        try self.init(operationId: e.operationId, actor: e.actorPrincipalId, capturedAt: e.clientCreatedAt,
            contractVersion: e.contractVersion.rawValue, payload: p, expectedRevision: nil)
    }
    init(_ command: ReviseCreatedInvoiceCommand) throws {
        let e = command.envelope
        try self.init(operationId: e.operationId, actor: e.actorPrincipalId, capturedAt: e.clientCreatedAt,
            contractVersion: e.contractVersion.rawValue, payload: e.payload.invoice,
            expectedRevision: String(e.payload.expectedRevision))
    }
    private init(operationId: OperationID, actor: PrincipalID, capturedAt: Date,
                 contractVersion: String, payload p: CreateInvoiceCommand.Payload, expectedRevision: String?) throws {
        guard let project = p.selection.scope.projectId, let client = p.selection.scope.clientId else {
            throw LiveInvoiceSelection.Failure.requiresProject
        }
        let wire = Wire(operationId: operationId.rawValue, accountId: p.selection.scope.accountId.rawValue,
            actorPrincipalId: actor.rawValue, projectId: project.rawValue, clientId: client.rawValue,
            invoiceId: p.invoiceId.rawValue, contractVersion: contractVersion,
            createdAtMs: String(Int64((capturedAt.timeIntervalSince1970 * 1000).rounded())),
            name: p.name, notes: p.notes, sources: p.selection.lines.map(Source.init), expectedRevision: expectedRevision)
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
        let expectedRevision: String?
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
