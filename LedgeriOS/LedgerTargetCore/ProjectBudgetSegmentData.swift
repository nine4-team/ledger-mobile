import CryptoKit
import Foundation

public enum ProjectBudgetSegmentFailure: Error, Equatable, Sendable {
    case accountScopeMismatch
    case projectScopeMismatch
    case currencyMismatch
    case duplicateCategoryIdentity
    case duplicatePresentationOrder
    case visibleCountMismatch
    case invalidSnapshotAsOf
    case invalidAccountingProjectionRevision
    case arithmeticOverflow
    case recognizedValueMismatch
    case requestFingerprintMismatch
    case queryFingerprintMismatch
    case localReadFailed
    case invalidEncodedRequest
    case invalidEncodedSegment
    case invalidEncodedSnapshot

    public var diagnosticCode: String {
        switch self {
        case .accountScopeMismatch:
            "project_budget_segment_account_scope_mismatch"
        case .projectScopeMismatch:
            "project_budget_segment_project_scope_mismatch"
        case .currencyMismatch:
            "project_budget_segment_currency_mismatch"
        case .duplicateCategoryIdentity:
            "project_budget_segment_category_identity_duplicate"
        case .duplicatePresentationOrder:
            "project_budget_segment_category_order_duplicate"
        case .visibleCountMismatch:
            "project_budget_segment_visible_count_mismatch"
        case .invalidSnapshotAsOf:
            "project_budget_segment_as_of_invalid"
        case .invalidAccountingProjectionRevision:
            "project_budget_segment_accounting_projection_revision_invalid"
        case .arithmeticOverflow:
            "project_budget_segment_arithmetic_overflow"
        case .recognizedValueMismatch:
            "project_budget_segment_recognized_value_mismatch"
        case .requestFingerprintMismatch:
            "project_budget_segment_request_fingerprint_mismatch"
        case .queryFingerprintMismatch:
            "project_budget_segment_query_fingerprint_mismatch"
        case .localReadFailed:
            "project_budget_segment_local_read_failed"
        case .invalidEncodedRequest:
            "project_budget_segment_request_encoding_invalid"
        case .invalidEncodedSegment:
            "project_budget_segment_row_encoding_invalid"
        case .invalidEncodedSnapshot:
            "project_budget_segment_snapshot_encoding_invalid"
        }
    }
}

public struct ProjectBudgetSegmentRequest: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let projectId: ProjectID
    public let currency: CurrencyCode
    public let queryFingerprint: ListQueryFingerprint

    public init(
        accountId: AccountID,
        projectId: ProjectID,
        currency: CurrencyCode
    ) throws {
        self.accountId = accountId
        self.projectId = projectId
        self.currency = currency
        queryFingerprint = try Self.makeFingerprint(
            accountId: accountId,
            projectId: projectId,
            currency: currency
        )
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let accountId = try container.decode(AccountID.self, forKey: .accountId)
            let projectId = try container.decode(ProjectID.self, forKey: .projectId)
            let currency = try container.decode(CurrencyCode.self, forKey: .currency)
            let encodedFingerprint = try container.decode(
                ListQueryFingerprint.self,
                forKey: .queryFingerprint
            )
            try self.init(
                accountId: accountId,
                projectId: projectId,
                currency: currency
            )
            guard queryFingerprint == encodedFingerprint else {
                throw ProjectBudgetSegmentFailure.requestFingerprintMismatch
            }
        } catch let failure as ProjectBudgetSegmentFailure {
            throw failure
        } catch {
            throw ProjectBudgetSegmentFailure.invalidEncodedRequest
        }
    }

    private static func makeFingerprint(
        accountId: AccountID,
        projectId: ProjectID,
        currency: CurrencyCode
    ) throws -> ListQueryFingerprint {
        do {
            let basis = FingerprintBasis(
                contractVersion: "project-budget-segment-v1",
                accountId: accountId,
                projectId: projectId,
                currency: currency
            )
            let bytes = try OperationContractCodec.encode(basis)
            let digest = SHA256.hash(data: bytes)
                .map { String(format: "%02x", $0) }
                .joined()
            return try ListQueryFingerprint(validating: digest)
        } catch let failure as ProjectBudgetSegmentFailure {
            throw failure
        } catch {
            throw ProjectBudgetSegmentFailure.invalidEncodedRequest
        }
    }

    private struct FingerprintBasis: Codable {
        let contractVersion: String
        let accountId: AccountID
        let projectId: ProjectID
        let currency: CurrencyCode
    }

    private enum CodingKeys: String, CodingKey {
        case accountId
        case projectId
        case currency
        case queryFingerprint
    }
}

public struct ProjectBudgetCategorySegment: Codable, Equatable, Sendable {
    public let category: BudgetCategoryDefinitionSnapshot
    public let clientPaid: Money
    public let invoicingUnpaid: Money
    public let recognized: Money

    public init(
        category: BudgetCategoryDefinitionSnapshot,
        clientPaid: Money,
        invoicingUnpaid: Money
    ) throws {
        let recognized: Money
        do {
            recognized = try clientPaid.adding(invoicingUnpaid)
        } catch DomainPrimitiveFailure.currencyMismatch {
            throw ProjectBudgetSegmentFailure.currencyMismatch
        } catch DomainPrimitiveFailure.arithmeticOverflow {
            throw ProjectBudgetSegmentFailure.arithmeticOverflow
        } catch {
            throw ProjectBudgetSegmentFailure.invalidEncodedSegment
        }

        self.category = category
        self.clientPaid = clientPaid
        self.invoicingUnpaid = invoicingUnpaid
        self.recognized = recognized
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let encodedRecognized = try container.decode(Money.self, forKey: .recognized)
            try self.init(
                category: container.decode(
                    BudgetCategoryDefinitionSnapshot.self,
                    forKey: .category
                ),
                clientPaid: container.decode(Money.self, forKey: .clientPaid),
                invoicingUnpaid: container.decode(Money.self, forKey: .invoicingUnpaid)
            )
            guard recognized == encodedRecognized else {
                throw ProjectBudgetSegmentFailure.recognizedValueMismatch
            }
        } catch let failure as ProjectBudgetSegmentFailure {
            throw failure
        } catch {
            throw ProjectBudgetSegmentFailure.invalidEncodedSegment
        }
    }

    private enum CodingKeys: String, CodingKey {
        case category
        case clientPaid
        case invoicingUnpaid
        case recognized
    }
}

public struct ProjectBudgetSegmentSnapshot: Codable, Equatable, Sendable {
    public let request: ProjectBudgetSegmentRequest
    public let accountingProjectionRevision: UInt64
    public let local: ListLocalSnapshot<ProjectBudgetCategorySegment>

    public init(
        request: ProjectBudgetSegmentRequest,
        accountingProjectionRevision: UInt64,
        local: ListLocalSnapshot<ProjectBudgetCategorySegment>
    ) throws {
        guard accountingProjectionRevision > 0 else {
            throw ProjectBudgetSegmentFailure.invalidAccountingProjectionRevision
        }
        guard local.asOf.timeIntervalSinceReferenceDate.isFinite else {
            throw ProjectBudgetSegmentFailure.invalidSnapshotAsOf
        }
        guard local.queryFingerprint == request.queryFingerprint else {
            throw ProjectBudgetSegmentFailure.queryFingerprintMismatch
        }
        guard local.rows.allSatisfy({ $0.category.accountId == request.accountId }) else {
            throw ProjectBudgetSegmentFailure.accountScopeMismatch
        }
        guard local.rows.allSatisfy({
            $0.clientPaid.currency == request.currency
                && $0.invoicingUnpaid.currency == request.currency
                && $0.recognized.currency == request.currency
        }) else {
            throw ProjectBudgetSegmentFailure.currencyMismatch
        }
        guard local.visibleRowCountBeforeFiltering == local.rows.count else {
            throw ProjectBudgetSegmentFailure.visibleCountMismatch
        }
        guard Self.firstDuplicate(local.rows.map(\.category.id)) == nil else {
            throw ProjectBudgetSegmentFailure.duplicateCategoryIdentity
        }
        guard Self.firstDuplicate(local.rows.map(\.category.presentationOrder)) == nil else {
            throw ProjectBudgetSegmentFailure.duplicatePresentationOrder
        }

        let rows = local.rows.sorted(by: Self.precedes)
        self.request = request
        self.accountingProjectionRevision = accountingProjectionRevision
        self.local = try ListLocalSnapshot(
            queryFingerprint: local.queryFingerprint,
            rows: rows,
            visibleRowCountBeforeFiltering: local.visibleRowCountBeforeFiltering,
            isCompleteForQuery: local.isCompleteForQuery,
            quality: local.quality,
            localDataVersion: local.localDataVersion,
            asOf: local.asOf
        )
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                request: container.decode(
                    ProjectBudgetSegmentRequest.self,
                    forKey: .request
                ),
                accountingProjectionRevision: container.decode(
                    UInt64.self,
                    forKey: .accountingProjectionRevision
                ),
                local: container.decode(
                    ListLocalSnapshot<ProjectBudgetCategorySegment>.self,
                    forKey: .local
                )
            )
        } catch let failure as ProjectBudgetSegmentFailure {
            throw failure
        } catch let failure as ListQueryContractFailure {
            throw failure
        } catch {
            throw ProjectBudgetSegmentFailure.invalidEncodedSnapshot
        }
    }

    private static func precedes(
        _ lhs: ProjectBudgetCategorySegment,
        _ rhs: ProjectBudgetCategorySegment
    ) -> Bool {
        if lhs.category.presentationOrder != rhs.category.presentationOrder {
            return lhs.category.presentationOrder < rhs.category.presentationOrder
        }
        return lhs.category.id.rawValue < rhs.category.id.rawValue
    }

    private static func firstDuplicate<Value: Hashable>(_ values: [Value]) -> Value? {
        var seen: Set<Value> = []
        return values.first { !seen.insert($0).inserted }
    }

    private enum CodingKeys: String, CodingKey {
        case request
        case accountingProjectionRevision
        case local
    }
}

public protocol ProjectBudgetSegmentQuerying: Sendable {
    func watchProjectBudgetSegments(
        _ request: ProjectBudgetSegmentRequest
    ) -> AsyncThrowingStream<ProjectBudgetSegmentSnapshot, Error>
}
