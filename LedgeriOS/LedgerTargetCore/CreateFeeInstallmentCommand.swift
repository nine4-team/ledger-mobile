import Foundation

public protocol ProjectFeeInstallmentCreating: Sendable {
    func createFeeInstallment(_ draft: FeeInstallmentDraft, operationUUID: UUID, capturedAt: Date) async throws -> OperationReceipt
}

/// Planned Fee demand, not client cash or a Transaction. The server resolves
/// category eligibility, the current configured total and all existing installments.
public struct FeeInstallmentDraft: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let projectId: ProjectID
    public let installmentId: FeeInstallmentID
    public let categoryId: BudgetCategoryID
    public let label: String
    public let amount: Money
    public let sortOrder: Int64?

    public init(accountId: AccountID, projectId: ProjectID, installmentId: FeeInstallmentID,
                categoryId: BudgetCategoryID, label: String, amount: Money, sortOrder: Int64? = nil) throws {
        guard amount.minorUnits > 0, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.invalidDraft
        }
        // Match the persisted integer column before accepting an offline command.
        if let sortOrder, Int32(exactly: sortOrder) == nil { throw Failure.invalidDraft }
        self.accountId = accountId; self.projectId = projectId; self.installmentId = installmentId
        self.categoryId = categoryId; self.label = label; self.amount = amount; self.sortOrder = sortOrder
    }

    /// Nil means explicitly no configured cap, never an incomplete download.
    /// Includes collected installments: collection does not free up the Fee budget.
    public func validateBudget(configuredTotal: Money?, alreadyAllocated: Money) throws {
        guard alreadyAllocated.minorUnits >= 0 else { throw Failure.invalidDraft }
        let proposed = try alreadyAllocated.adding(amount)
        if let configuredTotal {
            guard configuredTotal.currency == amount.currency else { throw Failure.currencyMismatch }
            guard proposed.minorUnits <= configuredTotal.minorUnits else { throw Failure.exceedsFeeTotal }
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(accountId: c.decode(AccountID.self, forKey: .accountId),
            projectId: c.decode(ProjectID.self, forKey: .projectId), installmentId: c.decode(FeeInstallmentID.self, forKey: .installmentId),
            categoryId: c.decode(BudgetCategoryID.self, forKey: .categoryId), label: c.decode(String.self, forKey: .label),
            amount: c.decode(Money.self, forKey: .amount), sortOrder: c.decodeIfPresent(Int64.self, forKey: .sortOrder))
    }
    public enum Failure: Error, Equatable, Sendable { case invalidDraft, currencyMismatch, exceedsFeeTotal }
    private enum CodingKeys: String, CodingKey { case accountId, projectId, installmentId, categoryId, label, amount, sortOrder }
}

public struct CreateFeeInstallmentCommand: Codable, Sendable {
    public let envelope: OperationEnvelope<FeeInstallmentDraft>
    public init(operationId: OperationID, actorPrincipalId: PrincipalID, capturedAt: Date, draft: FeeInstallmentDraft) throws {
        let milliseconds = (capturedAt.timeIntervalSince1970 * 1000).rounded(.down)
        guard milliseconds.isFinite, milliseconds >= 0, milliseconds < 1_000_000_000_000_000 else { throw Failure.invalidEnvelope }
        try self.init(envelope: .init(operationId: operationId, contractVersion: .init(validating: "fee-installment-create-v1"),
            accountId: draft.accountId, actorPrincipalId: actorPrincipalId,
            clientCreatedAt: Date(timeIntervalSince1970: milliseconds / 1000), payload: draft))
    }
    private init(envelope: OperationEnvelope<FeeInstallmentDraft>) throws {
        let milliseconds = envelope.clientCreatedAt.timeIntervalSince1970 * 1000
        guard envelope.contractVersion.rawValue == "fee-installment-create-v1", envelope.preconditions.isEmpty,
              envelope.accountId == envelope.payload.accountId, milliseconds.isFinite,
              milliseconds >= 0, milliseconds < 1_000_000_000_000_000 else { throw Failure.invalidEnvelope }
        self.envelope = envelope
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(envelope: c.decode(OperationEnvelope<FeeInstallmentDraft>.self, forKey: .envelope))
    }
    public enum Failure: Error, Equatable, Sendable { case invalidEnvelope }
    private enum CodingKeys: String, CodingKey { case envelope }
}
