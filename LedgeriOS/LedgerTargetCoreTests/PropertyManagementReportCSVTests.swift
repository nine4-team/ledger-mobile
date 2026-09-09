import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Property report CSV presentation")
struct PropertyManagementReportCSVTests {
    @Test("Quoted user text stays in one cell; formula text is inert without changing exact numbers")
    func escapingAndPrecision() throws {
        let dangerous = ["=SUM(1,2)", "+cmd", "-user-text", "@formula", "  =formula", "\tformula", "\rformula", "\nformula"]
        let items = try dangerous.enumerated().map { index, name in
            try item("item-\(index)", name: name, value: index == 0 ? -1 : nil)
        } + [item("quoted", name: "Chair, \"blue\"\r\nsecond line", value: 0)]
        let snapshot = try snapshot(items: items)
        let original = try snapshot.canonicalData()
        let csv = PropertyManagementReportCSV.render(snapshot)
        let rows = try parse(csv)
        for (index, name) in dangerous.enumerated() {
            let row = try #require(rows.first { $0["item_id"] == "item-\(index)" })
            #expect(row["item_name"] == "'" + name)
        }
        let quoted = try #require(rows.first { $0["item_id"] == "quoted" })
        #expect(quoted["item_name"] == "Chair, \"blue\"\r\nsecond line")
        #expect(quoted["sku"] == "'@SKU")
        #expect(rows.first { $0["item_id"] == "item-0" }?["market_value_minor_units"] == "-1")
        #expect(quoted["market_value_minor_units"] == "0")
        #expect(try snapshot.canonicalData() == original)
        #expect(csv.hasSuffix("\r\n"))
        for value in [Int64.min, Int64.max, 9_007_199_254_740_993] {
            let exact = try parse(PropertyManagementReportCSV.render(self.snapshot(items: [item("exact", value: value)])))
            #expect(exact.first { $0["row_type"] == "item" }?["market_value_minor_units"] == String(value))
            #expect(exact.first { $0["row_type"] == "report_total" }?["total_market_value_minor_units"] == String(value))
        }
    }

    @Test("CSV preserves Item and Space identity, unknown values, precomputed totals and provenance")
    func snapshotParity() throws {
        let space = try PropertyManagementReportSpace(accountId: AccountID(validating: "account"),
            projectId: ProjectID(validating: "project"), spaceId: SpaceID(validating: "room"), name: "No Space", revision: 7)
        let snapshot = try snapshot(spaces: [space], items: [
            item("known", space: space.spaceId, value: 200), item("unknown")])
        let rows = try parse(PropertyManagementReportCSV.render(snapshot))
        #expect(rows.filter { $0["row_type"] == "item" }.map { $0["item_id"]! }
            == snapshot.groups.flatMap(\.rows).map { $0.itemId.rawValue })
        #expect(rows.filter { $0["row_type"] == "group_total" }.map { $0["space_id"]! } == ["room", ""])
        #expect(rows.first { $0["item_id"] == "unknown" }?["market_value_minor_units"] == "")
        #expect(rows.first { $0["row_type"] == "space" }?["revision"] == "7")
        let total = try #require(rows.first { $0["row_type"] == "report_total" })
        #expect(total["item_count"] == String(snapshot.totals.itemCount))
        #expect(total["known_market_value_subtotal_minor_units"] == "200")
        #expect(total["unknown_market_value_count"] == "1")
        #expect(total["total_market_value_minor_units"] == "")
        for (key, value) in [("snapshot_hash", snapshot.reference.snapshotHash.rawValue),
                             ("source_set_hash", snapshot.sourceSetHash.rawValue),
                             ("local_data_version", snapshot.provenance.localDataVersion?.rawValue),
                             ("as_of_epoch_milliseconds", String(snapshot.provenance.asOf.rawValue))] {
            #expect(rows.first { $0["metadata_key"] == key }?["metadata_value"] == value)
        }
        #expect(rows.allSatisfy { $0["account_id"] == "account" && $0["project_id"] == "project" })
        #expect(PropertyManagementReportCSV.render(snapshot) == PropertyManagementReportCSV.render(snapshot))
    }

    @Test("Empty report includes metadata and a real zero total, not a fabricated Item")
    func empty() throws {
        let rows = try parse(PropertyManagementReportCSV.render(snapshot()))
        #expect(!rows.contains { $0["row_type"] == "item" || $0["row_type"] == "group_total" })
        #expect(rows.first { $0["row_type"] == "report_total" }?["total_market_value_minor_units"] == "0")
        #expect(rows.first { $0["metadata_key"] == "property_address_known" }?["metadata_value"] == "false")
    }

    private func item(_ id: String, space: SpaceID? = nil, name: String = "Item", value: Int64? = nil) throws -> PropertyManagementReportItem {
        let account = try AccountID(validating: "account"), project = try ProjectID(validating: "project")
        let itemId = try ItemID(validating: id)
        let accounting = try ProjectItemAccountingRow(evidence: .init(accountId: account, projectId: project,
            clientId: ClientID(validating: "client"), itemId: itemId, spaceId: space,
            billableOccurrences: [.init(id: BillableItemOccurrenceID(validating: "charge-" + id),
                accountId: account, projectId: project, itemId: itemId, polarity: .charge,
                phase: .availableToInvoice)]), relationshipAbsenceIsAuthoritative: true)
        return try .init(accountId: account, projectId: project,
                  itemId: itemId, placementId: EntityID(validating: "placement-" + id),
                  spaceId: space, name: name, sku: "@SKU",
                  marketValue: value.map { Money(minorUnits: $0, currency: try! CurrencyCode(validating: "USD")) },
                  itemRevision: 4, accounting: accounting)
    }
    private func snapshot(spaces: [PropertyManagementReportSpace] = [], items: [PropertyManagementReportItem] = []) throws -> PropertyManagementReportSnapshot {
        let account = try AccountID(validating: "account"), project = try ProjectID(validating: "project")
        return try .build(project: .init(accountId: account, projectId: project, name: "=Property", address: nil, revision: 3),
            spaces: spaces, items: items, currency: CurrencyCode(validating: "USD"),
            provenance: .init(accountId: account, projectId: project, principalId: PrincipalID(validating: "principal"),
                visibilityScopeID: .make(bytes: Data("scope".utf8)), localDataVersion: LocalDataVersion(validating: "local-7"),
                authorityVersion: .init(validating: "report-v1"), asOf: .init(validating: 1_800_000_001_000),
                readiness: .ready, lastSyncedAt: .init(validating: 1_800_000_000_000)))
    }

    // Independent CSV reader validates record/cell boundaries, including CRLF
    // within quoted cells; simple line splitting would hide escaping defects.
    private func parse(_ csv: String) throws -> [[String: String]] {
        let characters = Array(csv.utf8)
        var rows: [[String]] = [], row: [String] = [], cell: [UInt8] = []
        var quoted = false, index = 0
        while index < characters.count {
            let byte = characters[index]
            if byte == 34 {
                if quoted && index + 1 < characters.count && characters[index + 1] == 34 {
                    cell.append(34); index += 1
                } else { quoted.toggle() }
            } else if !quoted && byte == 44 {
                row.append(String(decoding: cell, as: UTF8.self)); cell = []
            } else if !quoted && byte == 13 {
                #expect(index + 1 < characters.count && characters[index + 1] == 10)
                row.append(String(decoding: cell, as: UTF8.self)); cell = []
                rows.append(row); row = []; index += 1
            } else { cell.append(byte) }
            index += 1
        }
        #expect(!quoted && cell.isEmpty && row.isEmpty)
        let columns = try #require(rows.first)
        return rows.dropFirst().map {
            #expect($0.count == columns.count)
            return Dictionary(uniqueKeysWithValues: zip(columns, $0))
        }
    }
}
