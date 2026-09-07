import Foundation
import LedgerTargetCore

/// An explicit migration assignment, not a name-match inference or authorization.
/// Import approval must cover this exact source Project and target Client scope.
package struct FirebasePaymentProjectMapping: Sendable {
    let sourceProject: FirebaseSourceDocument
    let targetScope: TransactionScope
}

package struct FirebasePaymentIdentityMapping: Sendable {
    let sourcePath: [String]
    let targetID: TransactionID
}

package enum FirebasePaymentBatchIssue: Equatable, Sendable {
    case duplicateSourcePath, unresolvedProjectMapping, unresolvedIdentityMapping, duplicateTargetID
}

package struct FirebasePaymentBatchEntry: Equatable, Sendable {
    let source: FirebaseSourceDocument
    let targetID: TransactionID?
    let conversion: FirebaseClientPaymentConversionResult?
    let issues: [FirebasePaymentBatchIssue]

    var isMapped: Bool {
        guard issues.isEmpty, targetID != nil, case .mapped = conversion else { return false }
        return true
    }
}

package struct FirebasePaymentBatchResult: Equatable, Sendable {
    let entries: [FirebasePaymentBatchEntry]
    /// Nil on overflow; never use a wrapped or partial sum as reconciliation.
    let mappedTotalCents: Int64?
    var mappedCount: Int { entries.filter(\.isMapped).count }
    var unresolvedCount: Int { entries.count - mappedCount }
    /// Only the supplied Transaction inputs, not export completeness, unused
    /// mapping rows, target persistence or external approval of the import plan.
    var isFullyReconciled: Bool { unresolvedCount == 0 && mappedTotalCents != nil }
}

/// Pure batch planning. Preserves one result per input, exact source evidence,
/// stable supplied target identities and explicit unresolved results. It performs
/// no database writes and cannot authorize the operator's Client assignments.
/// Mapping arrays may cover a larger import plan. Unreferenced rows create no
/// payment and are not approved/validated by this result; identity collisions
/// anywhere in that plan still disqualify affected input payments.
package enum FirebaseClientPaymentBatch {
    static func convert(
        transactions: [FirebaseSourceDocument],
        projects: [FirebaseSourceDocument],
        sourceAccountID: String,
        targetAccountID: AccountID,
        projectMappings: [FirebasePaymentProjectMapping],
        identityMappings: [FirebasePaymentIdentityMapping]
    ) -> FirebasePaymentBatchResult {
        func key(_ path: [String]) -> [Data] { path.map { Data($0.utf8) } }
        let sources = Dictionary(grouping: transactions, by: { key($0.documentPathSegments) })
        let sourceProjects = Dictionary(grouping: projects, by: { key($0.documentPathSegments) })
        let assignments = Dictionary(grouping: projectMappings, by: { key($0.sourceProject.documentPathSegments) })
        let targetProjects = Dictionary(grouping: projectMappings, by: { $0.targetScope.projectId })
        let identities = Dictionary(grouping: identityMappings, by: { key($0.sourcePath) })
        let targets = Dictionary(grouping: identityMappings, by: \.targetID)
        let entries = transactions.map { source -> FirebasePaymentBatchEntry in
            var issues: [FirebasePaymentBatchIssue] = []
            let path = key(source.documentPathSegments)
            if sources[path]?.count != 1 { issues.append(.duplicateSourcePath) }
            let identity = identities[path]
            var targetID: TransactionID?
            if identity?.count == 1, let candidate = identity?.first {
                targetID = candidate.targetID
                if targets[candidate.targetID]?.count != 1 { issues.append(.duplicateTargetID) }
            } else { issues.append(.unresolvedIdentityMapping) }

            var conversion: FirebaseClientPaymentConversionResult?
            if case .map(let fields) = source.fields,
               case .string(let projectID) = fields.first(where: { $0.key == "projectId" })?.value {
                let projectPath = key(["accounts", sourceAccountID, "projects", projectID])
                if let mapping = assignments[projectPath]?.only,
                   let project = sourceProjects[projectPath]?.only,
                   Self.matches(project, mapping.sourceProject),
                   Self.validProject(project, sourceAccountID: sourceAccountID),
                   mapping.targetScope.ownerKind == .project,
                   targetProjects[mapping.targetScope.projectId]?.count == 1,
                   mapping.targetScope.accountId == targetAccountID {
                    conversion = FirebaseClientPaymentConversion.convert(source,
                        sourceAccountID: sourceAccountID, sourceProjectID: projectID,
                        targetScope: mapping.targetScope)
                } else { issues.append(.unresolvedProjectMapping) }
            } else { issues.append(.unresolvedProjectMapping) }
            return .init(source: source, targetID: targetID,
                conversion: issues.isEmpty ? conversion : nil, issues: issues)
        }
        var total: Int64? = 0
        for entry in entries where entry.isMapped {
            guard case .mapped(_, _, let amount) = entry.conversion, let current = total else { continue }
            let addition = current.addingReportingOverflow(amount)
            total = addition.overflow ? nil : addition.partialValue
        }
        return .init(entries: entries, mappedTotalCents: total)
    }

    private static func validProject(_ project: FirebaseSourceDocument, sourceAccountID: String) -> Bool {
        guard project.evidenceKind == .record,
              project.accountScopeID.utf8.elementsEqual(sourceAccountID.utf8),
              (try? FirebaseSourceValue.reference(segments: project.documentPathSegments).validated()) != nil,
              case .map(let fields) = project.fields,
              (try? project.fields.validated()) != nil else { return false }
        if let account = fields.first(where: { $0.key == "accountId" }) {
            guard case .string(let id) = account.value,
                  id.utf8.elementsEqual(sourceAccountID.utf8) else { return false }
        }
        return true
    }

    private static func matches(_ a: FirebaseSourceDocument, _ b: FirebaseSourceDocument) -> Bool {
        a.accountScopeID.utf8.elementsEqual(b.accountScopeID.utf8)
            && a.sourceRecordID.utf8.elementsEqual(b.sourceRecordID.utf8)
            && a.documentPathSegments.map { Data($0.utf8) } == b.documentPathSegments.map { Data($0.utf8) }
            && a.entityCode.utf8.elementsEqual(b.entityCode.utf8) && a.evidenceKind == b.evidenceKind
            && (try? FirebaseSourceFixtureCatalog.canonicalData(for: a.fields)) != nil
            && (try? FirebaseSourceFixtureCatalog.canonicalData(for: a.fields))
                == (try? FirebaseSourceFixtureCatalog.canonicalData(for: b.fields))
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
