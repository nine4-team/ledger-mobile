import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Property Management report snapshot")
struct PropertyManagementReportTests {
    @Test("Online provenance never invents local download evidence and changes the content hash")
    func sourceProvenance() throws {
        let f = Fixture(), offline = try Fixture().provenance()
        let online = PropertyManagementReportProvenance(accountId: offline.accountId, projectId: offline.projectId,
            principalId: offline.principalId, visibilityScopeID: offline.visibilityScopeID, source: .authoritative,
            authorityVersion: offline.authorityVersion, asOf: offline.asOf, readiness: .ready)
        let room = try f.space("real-no-space", name: "No Space")
        let items = try [f.item("exact", value: 9_007_199_254_740_993, name: "Chair / \"青\"\nblue"),
            f.item("unknown", space: room.spaceId)]
        let project = PropertyManagementReportProject(accountId: f.account, projectId: f.projectID,
            name: "Property / \"Example\"", address: nil, revision: 3)
        let downloaded = try PropertyManagementReportSnapshot.build(project: project, spaces: [room], items: items,
            currency: f.currency, provenance: offline)
        let authoritative = try PropertyManagementReportSnapshot.build(project: project, spaces: [room], items: items,
            currency: f.currency, provenance: online)
        #expect(authoritative.groups == downloaded.groups)
        #expect(authoritative.totals == downloaded.totals)
        #expect(authoritative.sourceSetHash == downloaded.sourceSetHash)
        #expect(authoritative.reference.snapshotHash != downloaded.reference.snapshotHash)
        #expect(online.localDataVersion == nil && online.lastSyncedAt == nil)
        let envelope = try #require(JSONSerialization.jsonObject(with: authoritative.canonicalData()) as? [String: Any])
        let provenance = try #require(envelope["provenance"] as? [String: Any])
        let source = try #require(provenance["source"] as? [String: Any])
        #expect(source.count == 1 && source["kind"] as? String == "authoritative")
        #expect(provenance["localDataVersion"] == nil && provenance["lastSyncedAt"] == nil)
        let csv = PropertyManagementReportCSV.render(authoritative)
        #expect(csv.contains("source_kind") && csv.contains("authoritative"))
        #expect(!csv.contains("last_synced_at") && !csv.contains("local_data_version"))
        #expect(PropertyManagementReportHTML.render(authoritative).contains("Source: authoritative"))
        if let path = ProcessInfo.processInfo.environment["LEDGER_REPORT_ONLINE_GOLDEN_OUTPUT"] {
            try authoritative.canonicalData().write(to: URL(fileURLWithPath: path), options: .atomic)
        } else {
            let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
            let fixture = repository.appendingPathComponent("LedgerTargetMCP/tests/fixtures/property-management-report-online.json")
            #expect(try String(contentsOf: fixture, encoding: .utf8).trimmingCharacters(in: .newlines)
                == String(decoding: authoritative.canonicalData(), as: UTF8.self))
        }
    }

    @Test("HTML escapes user content and keeps unknown valuation visibly incomplete")
    func safeHTML() throws {
        let f = Fixture()
        let room = try f.space("room", name: "<img src=x onerror=alert(1)>")
        let snapshot = try f.snapshot(spaces: [room], items: [
            f.item("known", space: room.spaceId, value: 0, name: "<script>alert('x')</script>"),
            f.item("unknown", name: "A & B")
        ])
        let html = PropertyManagementReportHTML.render(snapshot)
        #expect(!html.contains("<script>"))
        #expect(!html.contains("<img"))
        #expect(html.contains("&lt;script&gt;alert(&#39;x&#39;)&lt;/script&gt;"))
        #expect(html.contains("A &amp; B"))
        #expect(html.contains("Known market value subtotal: USD 0.00"))
        #expect(html.contains("Unknown values: 1"))
        #expect(html.contains("<td class=\"amount\">Unknown</td>"))
        #expect(html.contains("Data version: local-7"))
        #expect(html.contains("default-src 'none'"))
    }

    @Test("Report HTML shows complete empty state and formats cents without floating-point rounding")
    func emptyHTMLAndFormatting() throws {
        let f = Fixture()
        let html = PropertyManagementReportHTML.render(try f.snapshot())
        #expect(html.contains("No data for this report"))
        #expect(html.contains("Items: 0 · Total market value: USD 0.00"))
        #expect(PropertyManagementReportHTML.value(nil) == "Unknown")
        #expect(PropertyManagementReportHTML.value(Money(minorUnits: 9_007_199_254_740_993, currency: f.currency)) == "USD 90071992547409.93")
        #expect(PropertyManagementReportHTML.value(Money(minorUnits: Int64.min, currency: f.currency)) == "USD -92233720368547758.08")
        #expect(PropertyManagementReportHTML.value(Money(minorUnits: -1, currency: f.currency)) == "USD -0.01")
    }

    private struct Fixture {
        let account = try! AccountID(validating: "account")
        let projectID = try! ProjectID(validating: "project")
        let currency = try! CurrencyCode(validating: "USD")
        var project: PropertyManagementReportProject {
            .init(accountId: account, projectId: projectID, name: "Example Property", address: "12 Example Street", revision: 3)
        }
        func provenance(quality: ListSnapshotQuality = .ready, version: String = "local-7", visibility: String = "member-a") throws -> PropertyManagementReportProvenance {
            try .init(accountId: account, projectId: projectID, principalId: PrincipalID(validating: "principal"),
                visibilityScopeID: .make(bytes: Data(visibility.utf8)), localDataVersion: LocalDataVersion(validating: version),
                authorityVersion: .init(validating: "physical-market-value-v1"), asOf: .init(validating: 1_800_000_001_000),
                readiness: quality, lastSyncedAt: .init(validating: 1_800_000_000_000))
        }
        func space(_ id: String, name: String) throws -> PropertyManagementReportSpace {
            try .init(accountId: account, projectId: projectID, spaceId: SpaceID(validating: id), name: name, revision: 2)
        }
        func item(_ id: String, space: SpaceID? = nil, value: Int64? = nil, name: String? = nil) throws -> PropertyManagementReportItem {
            try .init(accountId: account, projectId: projectID, itemId: ItemID(validating: id),
                placementId: EntityID(validating: "placement-" + id), spaceId: space, name: name ?? id, sku: "SKU-" + id,
                marketValue: value.map { Money(minorUnits: $0, currency: currency) }, itemRevision: 9,
                accounting: accounting(id, space: space))
        }
        func accounting(_ id: String, space: SpaceID? = nil) throws -> ProjectItemAccountingRow {
            let itemId = try ItemID(validating: id)
            return try .init(evidence: .init(accountId: account, projectId: projectID,
                clientId: ClientID(validating: "client"), itemId: itemId, spaceId: space,
                billableOccurrences: [.init(id: BillableItemOccurrenceID(validating: "charge-" + id),
                    accountId: account, projectId: projectID, itemId: itemId,
                    polarity: .charge, phase: .availableToInvoice)]), relationshipAbsenceIsAuthoritative: true)
        }
        func snapshot(spaces: [PropertyManagementReportSpace] = [], items: [PropertyManagementReportItem] = [],
                      provenance: PropertyManagementReportProvenance? = nil) throws -> PropertyManagementReportSnapshot {
            try .build(project: project, spaces: spaces, items: items, currency: currency, provenance: provenance ?? self.provenance())
        }
    }

    @Test("Deterministic physical groups preserve exact money, unknown prices and real No Space names")
    func groupedSnapshot() throws {
        let f = Fixture()
        let kitchen = try f.space("kitchen", name: "Kitchen")
        let namedNoSpace = try f.space("named-no-space", name: "No Space")
        let rows = try [f.item("large", space: kitchen.spaceId, value: 9_007_199_254_740_993),
            f.item("zero", space: namedNoSpace.spaceId, value: 0), f.item("unknown")]
        let snapshot = try f.snapshot(spaces: [namedNoSpace, kitchen], items: Array(rows.reversed()))
        #expect(snapshot.groups.map(\.spaceId) == [kitchen.spaceId, namedNoSpace.spaceId, nil])
        #expect(snapshot.totals.itemCount == 3)
        #expect(snapshot.totals.knownMarketValueSubtotal.minorUnits == 9_007_199_254_740_993)
        #expect(snapshot.totals.unknownMarketValueCount == 1)
        #expect(snapshot.totals.totalMarketValue == nil)
        #expect(snapshot.groups[1].totals.totalMarketValue?.minorUnits == 0)
        #expect(snapshot.groups[2].rows[0].marketValue == nil)
        #expect(snapshot.project.address == "12 Example Street")
        let permuted = try f.snapshot(spaces: [kitchen, namedNoSpace], items: rows)
        #expect(try snapshot.canonicalData() == permuted.canonicalData())
        #expect(snapshot.reference == permuted.reference)
        let json = try #require(JSONSerialization.jsonObject(with: snapshot.canonicalData()) as? [String: Any])
        let totals = try #require(json["totals"] as? [String: Any])
        #expect(totals["knownMarketValueSubtotalMinorUnits"] as? String == "9007199254740993")
        #expect(totals["totalMarketValueMinorUnits"] is NSNull)
    }

    @Test("Partial and stale downloads cannot produce a report; provenance remains bound to identity")
    func readinessAndBinding() throws {
        let f = Fixture()
        for quality: ListSnapshotQuality in [.partial, .stale] {
            #expect(throws: PropertyManagementReportFailure.incompleteReadiness) {
                try f.snapshot(provenance: f.provenance(quality: quality))
            }
        }
        let first = try f.snapshot()
        let changedLocalVersion = try f.snapshot(provenance: f.provenance(version: "local-8"))
        let changedVisibility = try f.snapshot(provenance: f.provenance(visibility: "member-b"))
        #expect(first.reference.snapshotHash != changedLocalVersion.reference.snapshotHash)
        #expect(first.reference.snapshotHash != changedVisibility.reference.snapshotHash)
        #expect(first.sourceSetHash == changedLocalVersion.sourceSetHash)
        #expect(first.reference.visibilityScopeID == first.provenance.visibilityScopeID)
        #expect(first.provenance.lastSyncedAt?.rawValue == 1_800_000_000_000)
    }

    @Test("Duplicate identities, foreign parents and dangling placement never become valid groups")
    func identitiesAndScope() throws {
        let f = Fixture()
        let space = try f.space("room", name: "Room")
        let item = try f.item("item", space: space.spaceId)
        #expect(throws: PropertyManagementReportFailure.duplicateItem) { try f.snapshot(spaces: [space], items: [item, item]) }
        #expect(throws: PropertyManagementReportFailure.duplicateSpace) { try f.snapshot(spaces: [space, space]) }
        #expect(throws: PropertyManagementReportFailure.missingSpace) { try f.snapshot(items: [item]) }
        let foreign = try PropertyManagementReportSpace(accountId: AccountID(validating: "foreign"), projectId: f.projectID,
            spaceId: space.spaceId, name: "Room", revision: 1)
        #expect(throws: PropertyManagementReportFailure.scopeMismatch) { try f.snapshot(spaces: [foreign], items: [item]) }
        let otherItem = try PropertyManagementReportItem(accountId: f.account, projectId: ProjectID(validating: "other-project"),
            itemId: item.itemId, placementId: item.placementId, spaceId: nil, name: "Wrong Project", sku: nil, marketValue: nil, itemRevision: 1)
        #expect(throws: PropertyManagementReportFailure.scopeMismatch) { try f.snapshot(items: [otherItem]) }
        let repeatedPlacement = try PropertyManagementReportItem(accountId: f.account, projectId: f.projectID,
            itemId: ItemID(validating: "second"), placementId: item.placementId, spaceId: nil, name: "Second", sku: nil, marketValue: nil, itemRevision: 1)
        #expect(throws: PropertyManagementReportFailure.duplicatePlacement) {
            try f.snapshot(spaces: [space], items: [item, repeatedPlacement])
        }
    }

    @Test("Currency mismatch and arithmetic overflow fail rather than yielding plausible totals")
    func exactArithmetic() throws {
        let f = Fixture()
        let eur = try Money(minorUnits: 1, currency: CurrencyCode(validating: "EUR"))
        let item = try PropertyManagementReportItem(accountId: f.account, projectId: f.projectID,
            itemId: ItemID(validating: "item"), placementId: EntityID(validating: "placement"), spaceId: nil,
            name: "Item", sku: nil, marketValue: eur, itemRevision: 1,
            accounting: f.accounting("item"))
        #expect(throws: PropertyManagementReportFailure.mixedCurrency) { try f.snapshot(items: [item]) }
        #expect(throws: DomainPrimitiveFailure.arithmeticOverflow(.addition)) {
            try f.snapshot(items: [f.item("a", value: Int64.max), f.item("b", value: 1)])
        }
        let invalid = PropertyManagementReportProject(accountId: f.account, projectId: f.projectID, name: "Project", address: nil, revision: 0)
        #expect(throws: PropertyManagementReportFailure.invalidRevision) {
            try PropertyManagementReportSnapshot.build(project: invalid, spaces: [], items: [], currency: f.currency, provenance: f.provenance())
        }
    }

    @Test("An authoritative empty report differs from an Item whose value is unknown")
    func emptyAndUnknown() throws {
        let f = Fixture()
        let empty = try f.snapshot()
        #expect(empty.groups.isEmpty)
        #expect(empty.totals.itemCount == 0)
        #expect(empty.totals.totalMarketValue?.minorUnits == 0)
        let unknown = try f.snapshot(items: [f.item("unknown")])
        #expect(unknown.totals.itemCount == 1)
        #expect(unknown.totals.knownMarketValueSubtotal.minorUnits == 0)
        #expect(unknown.totals.unknownMarketValueCount == 1)
        #expect(unknown.totals.totalMarketValue == nil)
        #expect(empty.reference.snapshotID != unknown.reference.snapshotID)
    }

    @Test("A complete downloaded snapshot has no arbitrary offline time expiry")
    func oldCompleteCheckpoint() throws {
        let f = Fixture()
        let previous = try f.provenance()
        let provenance = try PropertyManagementReportProvenance(accountId: f.account, projectId: f.projectID,
            principalId: previous.principalId, visibilityScopeID: previous.visibilityScopeID,
            localDataVersion: #require(previous.localDataVersion), authorityVersion: previous.authorityVersion,
            asOf: previous.asOf, readiness: .ready, lastSyncedAt: .init(validating: 1_000))
        let snapshot = try f.snapshot(items: [f.item("retained", value: 500)], provenance: provenance)
        #expect(snapshot.totals.totalMarketValue?.minorUnits == 500)
        #expect(snapshot.provenance.lastSyncedAt?.rawValue == 1_000)
    }

    @Test("Revision evidence uses decimal strings and the snapshot reference hashes its explicit content")
    func revisionAndContentEncoding() throws {
        let f = Fixture()
        let project = PropertyManagementReportProject(accountId: f.account, projectId: f.projectID,
            name: "Project", address: nil, revision: UInt64.max)
        let space = try PropertyManagementReportSpace(accountId: f.account, projectId: f.projectID,
            spaceId: SpaceID(validating: "space"), name: "Space", revision: UInt64.max)
        let item = try PropertyManagementReportItem(accountId: f.account, projectId: f.projectID,
            itemId: ItemID(validating: "item"), placementId: EntityID(validating: "placement"), spaceId: space.spaceId,
            name: "Item", sku: nil, marketValue: nil, itemRevision: UInt64.max,
            accounting: f.accounting("item", space: space.spaceId))
        let snapshot = try PropertyManagementReportSnapshot.build(project: project, spaces: [space], items: [item],
            currency: f.currency, provenance: f.provenance())
        #expect(try ProtectedArtifactSHA256.make(bytes: snapshot.canonicalContentData()) == snapshot.reference.snapshotHash)
        let envelope = try #require(JSONSerialization.jsonObject(with: snapshot.canonicalData()) as? [String: Any])
        #expect(envelope["reference"] != nil)
        let encodedProject = try #require(envelope["project"] as? [String: Any])
        let encodedSpaces = try #require(envelope["spaces"] as? [[String: Any]])
        let encodedGroups = try #require(envelope["groups"] as? [[String: Any]])
        let encodedRows = try #require(encodedGroups[0]["rows"] as? [[String: Any]])
        #expect(encodedProject["revision"] as? String == String(UInt64.max))
        #expect(encodedSpaces[0]["revision"] as? String == String(UInt64.max))
        #expect(encodedRows[0]["itemRevision"] as? String == String(UInt64.max))
    }
}
