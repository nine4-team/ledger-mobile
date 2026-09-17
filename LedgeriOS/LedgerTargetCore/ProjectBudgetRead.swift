import Foundation

/// Current downloaded accounting and local intent. Transfer/Additional Requests
/// coverage is not complete yet; consumers must not label this a final budget.
public struct ProjectBudgetRead: Sendable {
    public let scope: TransactionScope
    public let currency: CurrencyCode
    public let segments: [ProjectBudgetCategorySegment]
    public let allocations: [NullableCategoryAllocation]
    public let localOperations: [OperationReceipt]
    public let overallBudget: Money
    public let overallPaid: Money
    public let overallUnpaid: Money
    public let overallRecognized: Money
    public var isCompleteForProjectBudget: Bool { false }

    public init(scope: TransactionScope, currency: CurrencyCode,
                segments: [ProjectBudgetCategorySegment], allocations: [NullableCategoryAllocation],
                localOperations: [OperationReceipt]) throws {
        guard scope.ownerKind == .project, segments.allSatisfy({ $0.category.accountId == scope.accountId }) else {
            throw ProjectBudgetCalculation.Failure.scopeMismatch
        }
        let categoryIds = Set(segments.map(\.category.id))
        guard categoryIds.count == segments.count,
              Set(allocations.map(\.categoryId)).count == allocations.count,
              Set(localOperations.map(\.operationId)).count == localOperations.count else {
            throw ProjectBudgetCalculation.Failure.duplicateSource
        }
        guard allocations.allSatisfy({ categoryIds.contains($0.categoryId) }) else {
            throw ProjectBudgetCalculation.Failure.missingEvidence
        }
        guard segments.allSatisfy({ $0.recognized.currency == currency }),
              allocations.allSatisfy({ $0.allocation == nil || $0.allocation?.currency == currency }) else {
            throw ProjectBudgetSegmentFailure.currencyMismatch
        }
        self.scope = scope; self.currency = currency; self.segments = segments
        self.allocations = allocations; self.localOperations = localOperations
        let included = segments.filter { !$0.category.excludesFromOverallBudget }
        let includedIds = Set(included.map(\.category.id))
        overallPaid = try included.reduce(.zero(currency: currency)) { try $0.adding($1.clientPaid) }
        overallUnpaid = try included.reduce(.zero(currency: currency)) { try $0.adding($1.invoicingUnpaid) }
        overallRecognized = try overallPaid.adding(overallUnpaid)
        overallBudget = try allocations.filter { includedIds.contains($0.categoryId) }
            .reduce(.zero(currency: currency)) { try $0.adding($1.allocation ?? .zero(currency: currency)) }
    }
}

public protocol ProjectBudgetReading: Sendable {
    func readProjectBudget(accountId: AccountID, projectId: ProjectID, currency: CurrencyCode) async throws -> ProjectBudgetRead
    func watchProjectBudget(accountId: AccountID, projectId: ProjectID, currency: CurrencyCode) -> AsyncThrowingStream<ProjectBudgetRead?, Error>
}
