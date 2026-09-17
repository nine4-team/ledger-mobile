import Foundation

/// Interpretation of the audited Swift app's physical writers, not accounting
/// events or a claim that the complete custody timeline has been imported.
public enum FirebasePhysicalMovementEvidence {
    public enum Scope: Equatable, Sendable {
        case inventory
        case project(String)

        public static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.inventory, .inventory): return true
            case (.project(let a), .project(let b)): return a.utf8.elementsEqual(b.utf8)
            default: return false
            }
        }
    }
    public enum Interpretation: Equatable, Sendable {
        case movement(from: Scope, to: Scope)
        case unchanged(Scope)
        case unresolved
    }

    public struct Transition: Equatable, Sendable {
        public let at: FirebaseLineageTimestamp
        public let from: Scope
        public let to: Scope
        public let sourceDocumentIDs: [String]
    }
    public struct Timeline: Sendable {
        public let transitions: [Transition]
        public let unresolvedDocumentIDs: [String]
        /// Initial custody's start is not encoded by a movement edge.
        public var initialStartIsUnknown: Bool { true }
    }

    /// Produces a conservative, ordered movement chain for ONE exact Item.
    /// Callers retain the records themselves; no accounting facts are produced.
    public static func timeline(_ records: [ReconciledFirebaseLineageEvidence],
                                accountID: String, itemID: String, currentScope: Scope) -> Timeline {
        struct Instant: Hashable, Comparable {
            let seconds: Int64
            let nanos: Int
            static func < (a: Self, b: Self) -> Bool {
                a.seconds == b.seconds ? a.nanos < b.nanos : a.seconds < b.seconds
            }
        }
        var groups: [Instant:[ReconciledFirebaseLineageEvidence]] = [:]
        var unresolved: [String] = []
        for record in records {
            let edge = record.source
            guard edge.sourceAccountScopeID.utf8.elementsEqual(accountID.utf8),
                  edge.itemID?.utf8.elementsEqual(itemID.utf8) == true,
                  record.canAttemptMapping, let time = edge.createdAt,
                  let seconds = Int64(time.seconds), time.nanoseconds.isMultiple(of: 1000),
                  interpret(record) != .unresolved else {
                unresolved.append(edge.lineageDocumentID); continue
            }
            groups[.init(seconds: seconds, nanos: time.nanoseconds),default:[]].append(record)
        }
        var transitions: [Transition] = []
        var prior: Scope?
        for instant in groups.keys.sorted() {
            let group = groups[instant]!.sorted { $0.source.lineageDocumentID.utf8.lexicographicallyPrecedes($1.source.lineageDocumentID.utf8) }
            let moves = group.filter { if case .movement = interpret($0) { return true }; return false }
            var selected = moves.first
            if moves.count > 1 {
                // Audited two-hop writer emits a source->Inventory leg and a
                // source->destination sold leg in ONE server-timestamp batch.
                let sold = moves.filter { $0.source.movementKind == .sold }
                let exits = moves.filter { [.returned,.soldToInventory].contains($0.source.movementKind) }
                if moves.count == 2, sold.count == 1, exits.count == 1,
                   let transaction = sold[0].source.fromTransactionID,
                   exits[0].source.fromTransactionID?.utf8.elementsEqual(transaction.utf8) == true,
                   case .movement(let from, let to) = interpret(sold[0]),
                   case .project = from, case .project = to,
                   case .movement(let exitFrom, .inventory) = interpret(exits[0]), from == exitFrom {
                    selected = sold[0]
                } else {
                    unresolved += group.map { $0.source.lineageDocumentID }; continue
                }
            }
            if let selected, case .movement(let from, let to) = interpret(selected) {
                if let prior, prior != from { unresolved += group.map { $0.source.lineageDocumentID } }
                for record in group where !moves.contains(where: { $0.source.lineageDocumentID.utf8.elementsEqual(record.source.lineageDocumentID.utf8) }) {
                    if case .unchanged(let scope) = interpret(record), scope != from && scope != to {
                        unresolved.append(record.source.lineageDocumentID)
                    }
                }
                transitions.append(.init(at: selected.source.createdAt!, from: from, to: to,
                    sourceDocumentIDs: group.map { $0.source.lineageDocumentID }))
                prior = to
            } else {
                for record in group {
                    if case .unchanged(let scope) = interpret(record) {
                        if let prior, prior != scope { unresolved.append(record.source.lineageDocumentID) }
                        prior = scope
                    }
                }
            }
        }
        if let prior, prior != currentScope { unresolved += records.map { $0.source.lineageDocumentID } }
        // Never offer a partial chain as importable after a missing/conflicting hop.
        let unique = Dictionary(unresolved.map { (Data($0.utf8),$0) },uniquingKeysWith: { first,_ in first })
        return .init(transitions: unresolved.isEmpty ? transitions : [],
            unresolvedDocumentIDs: unique.values.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) })
    }

    public static func interpret(_ record: ReconciledFirebaseLineageEvidence) -> Interpretation {
        guard record.canAttemptMapping, record.source.source == "app" else { return .unresolved }
        let edge = record.source
        func result(_ from: Scope, _ to: Scope) -> Interpretation {
            // Source IDs are opaque UTF-8, not Unicode-normalized identifiers.
            switch (from, to) {
            case (.inventory, .inventory): return .unchanged(from)
            case (.project(let a), .project(let b)) where a.utf8.elementsEqual(b.utf8): return .unchanged(from)
            default: return .movement(from: from, to: to)
            }
        }
        switch edge.movementKind {
        case .sold:
            guard let destination = edge.toProjectID else { return .unresolved }
            // InventoryOperationsService's sold writer omits fromProjectId
            // precisely when source Item.projectId is nil.
            return result(edge.fromProjectID.map(Scope.project) ?? .inventory, .project(destination))
        case .returned:
            guard let source = edge.fromProjectID else { return .unresolved }
            // Same-Project returned is a transaction-link change, not custody.
            // Physical return/acquisition writers omit the destination Project.
            if let destination = edge.toProjectID {
                guard source.utf8.elementsEqual(destination.utf8) else { return .unresolved }
                return .unchanged(.project(source))
            }
            return .movement(from: .project(source), to: .inventory)
        case .soldToInventory:
            guard let source = edge.fromProjectID, edge.toProjectID == nil else { return .unresolved }
            return .movement(from: .project(source), to: .inventory)
        case .correction:
            // Correction writers are not uniform. Infer Inventory only from an
            // explicitly stored null, never a missing field.
            func explicit(_ key: String) -> Scope? {
                guard let value = edge.rawFields.first(where: { $0.key == key })?.value else { return nil }
                switch value {
                case .null: return .inventory
                case .string(let id): return .project(id)
                default: return nil
                }
            }
            guard let from = explicit("fromProjectId"), let to = explicit("toProjectId") else { return .unresolved }
            return result(from, to)
        case .association, nil: return .unresolved
        }
    }
}
