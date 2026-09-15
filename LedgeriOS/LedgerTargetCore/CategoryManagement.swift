import Foundation

public enum CategoryManagementFailure: Error, Equatable, Sendable {
    case invalidCommand
    case wrongAccount
    case incompleteDirectory
    case categoryUnavailable
    case protectedCategory
    case revisionConflict
    case duplicateName
    case invalidOrder
    case receiptMismatch
}

/// One shared command vocabulary for Settings and inline Project creation.
/// Revisions travel as decimal text so JavaScript and Postgres agree exactly.
public struct CategoryManagementPayload: Codable, Equatable, Sendable {
    public enum Action: String, Codable, Sendable {
        case create, edit, archive, restore, reorder
    }

    public let action: Action
    public let categoryId: BudgetCategoryID?
    public let expectedRevision: String?
    public let name: BudgetCategoryName?
    public let kind: BudgetCategoryKind?
    public let excludesFromOverallBudget: Bool?
    public let order: [CategoryOrderEntry]?

    public init(action: Action, categoryId: BudgetCategoryID? = nil,
                expectedRevision: UInt64? = nil, name: BudgetCategoryName? = nil,
                kind: BudgetCategoryKind? = nil, excludesFromOverallBudget: Bool? = nil,
                order: [CategoryOrderEntry]? = nil) {
        self.action = action
        self.categoryId = categoryId
        self.expectedRevision = expectedRevision.map(String.init)
        self.name = name
        self.kind = kind
        self.excludesFromOverallBudget = excludesFromOverallBudget
        self.order = order
    }

    public func validate() throws {
        let hasDefinition = name != nil && kind != nil && excludesFromOverallBudget != nil
        let noDefinition = name == nil && kind == nil && excludesFromOverallBudget == nil
        switch action {
        case .create:
            guard categoryId != nil, expectedRevision == nil, hasDefinition, order == nil else {
                throw CategoryManagementFailure.invalidCommand
            }
        case .edit:
            guard categoryId != nil, hasDefinition, order == nil else {
                throw CategoryManagementFailure.invalidCommand
            }
            try Self.validateRevision(expectedRevision)
        case .archive, .restore:
            guard categoryId != nil, noDefinition, order == nil else {
                throw CategoryManagementFailure.invalidCommand
            }
            try Self.validateRevision(expectedRevision)
        case .reorder:
            guard categoryId == nil, expectedRevision == nil, noDefinition,
                  let order, !order.isEmpty, Set(order.map(\.categoryId)).count == order.count else {
                throw CategoryManagementFailure.invalidOrder
            }
            for row in order { try Self.validateRevision(row.expectedRevision) }
        }
    }

    static func validateRevision(_ text: String?) throws {
        guard let text, let revision = UInt64(text), revision > 0,
              revision < UInt64(Int64.max), text == String(revision) else {
            throw CategoryManagementFailure.invalidCommand
        }
    }
}

public struct CategoryOrderEntry: Codable, Equatable, Sendable {
    public let categoryId: BudgetCategoryID
    public let expectedRevision: String

    public init(categoryId: BudgetCategoryID, expectedRevision: UInt64) {
        self.categoryId = categoryId
        self.expectedRevision = String(expectedRevision)
    }
}

public struct CategoryManagementCommand: Codable, Sendable {
    public let envelope: OperationEnvelope<CategoryManagementPayload>
    public var fingerprint: OperationFingerprint { get throws { try .make(for: envelope) } }

    public init(operationId: OperationID, accountId: AccountID, actorPrincipalId: PrincipalID,
                capturedAt: Date, payload: CategoryManagementPayload) throws {
        let milliseconds = (capturedAt.timeIntervalSince1970 * 1000).rounded(.down)
        guard milliseconds.isFinite, abs(milliseconds) < 1_000_000_000_000_000 else {
            throw CategoryManagementFailure.invalidCommand
        }
        try self.init(envelope: OperationEnvelope(
            operationId: operationId,
            contractVersion: try OperationContractVersion(validating: "category-management-v1"),
            accountId: accountId, actorPrincipalId: actorPrincipalId,
            clientCreatedAt: Date(timeIntervalSince1970: milliseconds / 1000), payload: payload
        ))
    }

    private init(envelope: OperationEnvelope<CategoryManagementPayload>) throws {
        guard envelope.contractVersion.rawValue == "category-management-v1",
              envelope.preconditions.isEmpty,
              envelope.clientCreatedAt.timeIntervalSince1970.isFinite else {
            throw CategoryManagementFailure.invalidCommand
        }
        try envelope.payload.validate()
        self.envelope = envelope
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(envelope: container.decode(OperationEnvelope<CategoryManagementPayload>.self,
                                                forKey: .envelope))
    }

    private enum CodingKeys: String, CodingKey { case envelope }
}

public protocol CategoryManaging: Sendable {
    /// Return only after acceptance is durable, never merely after form dismissal.
    func submit(_ command: CategoryManagementCommand) async throws -> OperationReceipt
}

/// Pure preview/admission rules. Server authorization and validation remain authoritative.
/// Mutates category definitions only: never Transaction amounts, Items or paid snapshots.
public enum CategoryManagement {
    public static func applying(_ payload: CategoryManagementPayload,
                                to snapshot: BudgetCategoryReferenceSnapshot) throws
        -> [BudgetCategoryDefinitionSnapshot] {
        try payload.validate()
        guard snapshot.local.isCompleteForQuery else {
            throw CategoryManagementFailure.incompleteDirectory
        }
        var rows = snapshot.local.rows
        if let name = payload.name,
           rows.contains(where: { $0.id != payload.categoryId &&
               $0.name.comparisonKey == name.comparisonKey }) {
            throw CategoryManagementFailure.duplicateName
        }
        if payload.action == .create {
            guard !rows.contains(where: { $0.id == payload.categoryId }),
                  let id = payload.categoryId, let name = payload.name, let kind = payload.kind,
                  let excluded = payload.excludesFromOverallBudget else {
                throw CategoryManagementFailure.invalidCommand
            }
            let last = rows.map(\.presentationOrder).max()
            guard last != UInt32.max else { throw CategoryManagementFailure.invalidOrder }
            rows.append(BudgetCategoryDefinitionSnapshot(id: id, accountId: snapshot.accountId,
                name: name, kind: kind, lifecycle: .active, isSystem: false,
                excludesFromOverallBudget: excluded, presentationOrder: last.map { $0 + 1 } ?? 0,
                revision: 1))
        } else if payload.action == .reorder {
            let active = rows.filter { $0.lifecycle == .active && !$0.isSystem }
            let order = payload.order!
            guard Set(active.map(\.id)) == Set(order.map(\.categoryId)) else {
                throw CategoryManagementFailure.invalidOrder
            }
            let positions = active.map(\.presentationOrder).sorted()
            for (offset, entry) in order.enumerated() {
                let index = rows.firstIndex { $0.id == entry.categoryId }!
                guard String(rows[index].revision) == entry.expectedRevision else {
                    throw CategoryManagementFailure.revisionConflict
                }
                if rows[index].presentationOrder != positions[offset] {
                    rows[index] = replacing(rows[index], order: positions[offset])
                }
            }
        } else {
            guard let index = rows.firstIndex(where: { $0.id == payload.categoryId }) else {
                throw CategoryManagementFailure.categoryUnavailable
            }
            let row = rows[index]
            guard !row.isSystem else { throw CategoryManagementFailure.protectedCategory }
            guard String(row.revision) == payload.expectedRevision else {
                throw CategoryManagementFailure.revisionConflict
            }
            let lifecycle: DirectoryLifecycleState = payload.action == .archive ? .archived :
                payload.action == .restore ? .active : row.lifecycle
            // Uniqueness uses canonical equivalence, but a saved spelling keeps
            // its bytes. Match Postgres so the next offline edit uses its revision.
            if !row.name.rawValue.utf8.elementsEqual((payload.name ?? row.name).rawValue.utf8) || row.kind != (payload.kind ?? row.kind) ||
                row.excludesFromOverallBudget != (payload.excludesFromOverallBudget ?? row.excludesFromOverallBudget) ||
                row.lifecycle != lifecycle {
                rows[index] = replacing(row, name: payload.name, kind: payload.kind,
                    lifecycle: lifecycle, excluded: payload.excludesFromOverallBudget)
            }
        }
        return rows.sorted { $0.presentationOrder < $1.presentationOrder }
    }

    private static func replacing(_ row: BudgetCategoryDefinitionSnapshot,
                                  name: BudgetCategoryName? = nil, kind: BudgetCategoryKind? = nil,
                                  lifecycle: DirectoryLifecycleState? = nil, excluded: Bool? = nil,
                                  order: UInt32? = nil) -> BudgetCategoryDefinitionSnapshot {
        BudgetCategoryDefinitionSnapshot(id: row.id, accountId: row.accountId, name: name ?? row.name,
            kind: kind ?? row.kind, lifecycle: lifecycle ?? row.lifecycle, isSystem: row.isSystem,
            excludesFromOverallBudget: excluded ?? row.excludesFromOverallBudget,
            presentationOrder: order ?? row.presentationOrder, revision: row.revision + 1)
    }
}
