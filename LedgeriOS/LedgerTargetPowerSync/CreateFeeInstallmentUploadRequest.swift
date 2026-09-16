import CryptoKit
import Foundation
import LedgerTargetCore

public protocol CreateFeeInstallmentCommandApplying: Sendable {
    func apply(_ command: CreateFeeInstallmentCommand) async throws -> CreateFeeInstallmentServerResult
}

public struct CreateFeeInstallmentServerResult: Decodable, Sendable {
    enum Failure: Error { case receiptMismatch }
    let operation_id, account_id, actor_principal_id, command_type, contract_version: String
    let command_fingerprint, envelope_sha256, subject_id, phase: String
    let request_sha256, result_code, error_code: String?
    let client_created_at_ms, server_received_at_ms, completed_at_ms: Int64

    func validate(for command: CreateFeeInstallmentCommand) throws {
        let e = command.envelope, request = try CreateFeeInstallmentUploadRequest(command)
        guard operation_id == e.operationId.rawValue, account_id == e.accountId.rawValue,
              actor_principal_id == e.actorPrincipalId.rawValue, subject_id == e.payload.installmentId.rawValue,
              command_type == "create_fee_installment", contract_version == "fee-installment-create-v1",
              command_fingerprint == request.fingerprint, envelope_sha256 == request.fingerprint,
              request_sha256 == nil,
              client_created_at_ms == Int64((e.clientCreatedAt.timeIntervalSince1970 * 1000).rounded()),
              server_received_at_ms >= 0, completed_at_ms >= server_received_at_ms,
              (phase == "applied" && result_code == "fee_installment_created" && error_code == nil)
                || (phase == "rejected" && result_code == nil && Self.rejections.contains(error_code ?? "")) else {
            throw Failure.receiptMismatch
        }
    }
    static let rejections: Set<String> = ["fee_invalid_draft", "fee_project_unavailable",
        "fee_category_unavailable", "fee_currency_mismatch", "fee_total_overflow",
        "fee_total_exceeded", "fee_integrity_conflict"]
}

/// Exact provider encoding; an absent ordering is an empty string, not zero.
struct CreateFeeInstallmentUploadRequest: Sendable {
    let commandJSON: String
    let fingerprint: String
    init(_ command: CreateFeeInstallmentCommand) throws {
        let e = command.envelope, p = e.payload
        let wire: [String: String] = [
            "operationId": e.operationId.rawValue, "accountId": e.accountId.rawValue,
            "actorPrincipalId": e.actorPrincipalId.rawValue, "projectId": p.projectId.rawValue,
            "installmentId": p.installmentId.rawValue, "categoryId": p.categoryId.rawValue,
            "contractVersion": e.contractVersion.rawValue,
            "createdAtMs": String(Int64((e.clientCreatedAt.timeIntervalSince1970 * 1000).rounded())),
            "label": p.label, "amountMinorUnits": String(p.amount.minorUnits),
            "currency": p.amount.currency.rawValue, "sortOrder": p.sortOrder.map(String.init) ?? ""
        ]
        let data = try OperationContractCodec.encode(wire)
        commandJSON = String(decoding: data, as: UTF8.self)
        fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    var rpcBody: Data { get throws { try OperationContractCodec.encode(["p_command": commandJSON]) } }
}
