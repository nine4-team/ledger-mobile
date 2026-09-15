import Foundation

/// Shared presentation grouping for downloaded Items and receipt Item evidence.
/// Grouping never changes physical identities, membership or accounting amounts.
public enum ItemGrouping {
    public enum Key: Hashable, Sendable {
        case sku(source: String, sku: String)
        case name(source: String, name: String)
    }
    public struct Group<Row: Sendable>: Sendable, Identifiable {
        public let id: Key
        public let representative: Row
        public let rows: [Row]
    }

    /// SKU-less copies join a SKU group only if the full supplied context is
    /// unambiguous. Preserve requested row/group order and ignore repeated IDs.
    public static func groups<Row: Sendable, ID: Hashable>(in context: [Row], selectedIDs: [ID],
        id: (Row) -> ID, name: (Row) -> String?, sku: (Row) -> String?, source: (Row) -> String?) -> [Group<Row>] {
        func normalized(_ value: String?) -> String {
            (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        var candidates: [Key: Set<Key>] = [:]
        for row in context {
            let source = normalized(source(row)), name = normalized(name(row)), sku = normalized(sku(row))
            if !name.isEmpty, !sku.isEmpty {
                candidates[.name(source: source, name: name), default: []].insert(.sku(source: source, sku: sku))
            }
        }
        let byID = Dictionary(context.map { (id($0), $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<ID>(), order: [Key] = [], grouped: [Key: [Row]] = [:]
        for itemID in selectedIDs {
            guard seen.insert(itemID).inserted, let row = byID[itemID] else { continue }
            let source = normalized(source(row)), sku = normalized(sku(row))
            let nameKey = Key.name(source: source, name: normalized(name(row)))
            let key: Key
            if !sku.isEmpty { key = .sku(source: source, sku: sku) }
            else if let matches = candidates[nameKey], matches.count == 1, let match = matches.first { key = match }
            else { key = nameKey }
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(row)
        }
        return order.compactMap { key in
            guard let members = grouped[key], let first = members.first else { return nil }
            return Group(id: key, representative: members.first { !normalized(sku($0)).isEmpty } ?? first, rows: members)
        }
    }
}
