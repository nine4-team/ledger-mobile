import Foundation
import LedgerTargetCore
import Observation

@MainActor @Observable
public final class TransactionBrowserSession {
    public enum State: Equatable { case loading, incomplete, partial, ready, unavailable, failed }
    public enum Sort: String, CaseIterable, Sendable {
        case dateDesc, dateAsc, amountDesc, amountAsc, createdDesc, createdAsc, sourceAsc, sourceDesc
        public var label: String {
            switch self {
            case .dateDesc: "Date: Newest First"
            case .dateAsc: "Date: Oldest First"
            case .amountDesc: "Amount: High to Low"
            case .amountAsc: "Amount: Low to High"
            case .createdDesc: "Created: Newest First"
            case .createdAsc: "Created: Oldest First"
            case .sourceAsc: "Source: A to Z"
            case .sourceDesc: "Source: Z to A"
            }
        }
    }
    public enum Filter: String, CaseIterable { case type, category, source, emailReceipt, payer, audit }
    public let scope: TransactionScope
    public private(set) var state: State = .loading
    public private(set) var rows: [TransactionDetailSnapshot] = []
    public var search = "" { didSet { pruneSelection() } }
    public var sort: Sort = .dateDesc
    public private(set) var filters: [Filter: Set<String>] = [:]
    public private(set) var selectedIds: Set<TransactionID> = []
    private let watch: @Sendable () -> AsyncThrowingStream<TransactionBrowserUpdate, Error>
    private var generation = UUID()
    private var navigationSelection: Set<TransactionID> = []

    public init(scope: TransactionScope, watch: @escaping @Sendable () -> AsyncThrowingStream<TransactionBrowserUpdate, Error>) {
        self.scope = scope; self.watch = watch
    }

    public var processed: [TransactionDetailSnapshot] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return rows.filter { row in
            for (group, selected) in filters where !selected.isEmpty {
                guard selected.contains(value(row, group: group)) else { return false }
            }
            return query.isEmpty || [row.transactionId.rawValue, row.source, row.notes,
                row.classification.type.rawValue, row.category?.name, value(row, group: .payer),
                String(row.amount.minorUnits), Self.amountText(row, locale: Locale(identifier: "en_US"))]
                .compactMap { $0 }.contains { $0.localizedCaseInsensitiveContains(query) }
        }.sorted { a, b in
            let ascending = [.dateAsc, .amountAsc, .createdAsc, .sourceAsc].contains(sort)
            func compare<T: Comparable>(_ x: T?, _ y: T?) -> Bool {
                if x == y { return ascending ? a.transactionId.rawValue < b.transactionId.rawValue
                    : a.transactionId.rawValue > b.transactionId.rawValue }
                guard let x else { return false }; guard let y else { return true }
                return ascending ? x < y : x > y
            }
            switch sort {
            case .dateAsc, .dateDesc: return compare(Self.sortDate(a), Self.sortDate(b))
            case .createdAsc, .createdDesc: return compare(a.createdAtMilliseconds, b.createdAtMilliseconds)
            case .sourceAsc, .sourceDesc: return compare(a.source?.lowercased(), b.source?.lowercased())
            case .amountAsc, .amountDesc:
                // Different currencies have no meaningful shared amount ordering.
                if a.amount.currency != b.amount.currency { return a.amount.currency < b.amount.currency }
                return compare(a.amount.minorUnits, b.amount.minorUnits)
            }
        }
    }

    public func value(_ row: TransactionDetailSnapshot, group: Filter) -> String {
        switch group {
        case .type: row.classification.type.rawValue
        case .category: row.category?.id.rawValue ?? "uncategorized"
        case .source: row.source ?? ""
        case .emailReceipt: row.hasEmailReceipt.map { $0 ? "yes" : "no" } ?? "unknown"
        case .payer: row.classification.scope.ownerKind == .project ? "client" : "1584"
        case .audit:
            row.origin != .vendorPayment || row.category?.kind != .itemized ? "notApplicable"
                : row.receipt?.auditStatus.rawValue ?? "unknown"
        }
    }

    public func toggleFilter(_ group: Filter, value: String?, allOptionValues: Set<String> = []) {
        guard let value else { filters[group] = []; pruneSelection(); return }
        var selected = filters[group] ?? []
        if !selected.insert(value).inserted { selected.remove(value) }
        if !allOptionValues.isEmpty && selected == allOptionValues { selected = [] }
        filters[group] = selected
        pruneSelection()
    }
    public func resetFilters() { filters = [:]; pruneSelection() }
    public func toggleSelection(_ id: TransactionID) {
        guard processed.contains(where: { $0.transactionId == id }) else { return }
        if !selectedIds.insert(id).inserted { selectedIds.remove(id) }
    }
    public func selectAllVisible() {
        guard scope.ownerKind == .project else { return }
        let ids = Set(processed.map(\.transactionId))
        selectedIds = selectedIds == ids ? [] : ids
    }
    public func clearSelection() { selectedIds = [] }
    public var selected: [TransactionDetailSnapshot] { processed.filter { selectedIds.contains($0.transactionId) } }
    public var selectedIDText: String { selected.map(\.transactionId.rawValue).joined(separator: "\n") }
    public func selectedTotal() throws -> Money? {
        guard let currency = selected.first?.amount.currency else { return nil }
        return try selected.reduce(Money.zero(currency: currency)) { total, row in
            row.classification.type == .return ? try total.subtracting(row.amount) : try total.adding(row.amount)
        }
    }

    public func receive(_ update: TransactionBrowserUpdate) throws {
        switch update {
        case .ready(let values), .partial(let values):
            guard values.allSatisfy({ $0.classification.scope == scope }),
                  Set(values.map(\.transactionId)).count == values.count,
                  Set(values.map(\.principalId)).count <= 1 else {
                clear(.failed); throw TransactionDetailSnapshot.Failure.scopeMismatch
            }
            rows = values
            selectedIds.formUnion(navigationSelection)
            navigationSelection = []
            if case .ready = update { state = .ready } else { state = .partial }
            pruneSelection()
        case .incomplete: clear(.incomplete)
        case .unavailable: clear(.unavailable)
        }
    }
    public func observe() async {
        let active = UUID(); generation = active; clear(.loading, preservingNavigationSelection: true)
        do {
            for try await update in watch() {
                try Task.checkCancellation()
                guard generation == active else { return }
                try receive(update)
            }
            if generation == active { clear(.unavailable) }
        } catch is CancellationError {
            if generation == active { clear(.unavailable) }
        } catch { if generation == active { clear(.failed) } }
    }
    public func invalidate() { generation = UUID(); clear(.unavailable) }
    /// Preserve selection intent, not stale rows; restore only IDs in the next
    /// authorized and filtered read when returning from Transaction details.
    public func suspendForDetailNavigation() {
        navigationSelection = selectedIds
        generation = UUID()
        clear(.unavailable, preservingNavigationSelection: true)
    }
    private func clear(_ next: State, preservingNavigationSelection: Bool = false) {
        rows = []; selectedIds = []; state = next
        if !preservingNavigationSelection { navigationSelection = [] }
    }
    private func pruneSelection() { selectedIds.formIntersection(processed.map(\.transactionId)) }

    public static func title(_ row: TransactionDetailSnapshot) -> String {
        let source = row.source?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if source.isEmpty { return row.transactionId.rawValue }
        return row.classification.type == .return ? "Return to \(source)" : source
    }
    public static func amountText(_ row: TransactionDetailSnapshot, locale: Locale = .autoupdatingCurrent) -> String {
        let magnitude = Decimal(row.amount.minorUnits) / 100
        return (row.classification.type == .return ? -magnitude : magnitude)
            .formatted(.currency(code: row.amount.currency.rawValue).locale(locale))
    }
    private static func sortDate(_ row: TransactionDetailSnapshot) -> String? {
        if let date = row.transactionDate { return date }
        guard let ms = row.createdAtMilliseconds else { return nil }
        let date = Date(timeIntervalSince1970: Double(ms) / 1000)
        return date.ISO8601Format(.init(timeZone: TimeZone(secondsFromGMT: 0)!).year().month().day().dateSeparator(.dash))
    }
}
