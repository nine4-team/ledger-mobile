#if canImport(PDFKit)
import Foundation
import PDFKit
import Testing
import LedgerTargetCore
import LedgerTargetAppModel

@Suite("ClientSummaryPhysicalReport PDF")
struct ClientSummaryPhysicalReportPDFTests {
    @Test func paginatesEveryItemAndPreservesMetadata() throws {
        let snapshot = try fixture(count: 60)
        let profile = try AccountBusinessProfile(accountId: snapshot.project.accountId,
            name: AccountDisplayName(validating: "Design business"), logo: .notDownloaded, isStale: true)
        let pdf = try #require(PDFDocument(data: ClientSummaryPhysicalReportPDF.render(snapshot, profile: profile)))
        let text = try #require(pdf.string)
        #expect(pdf.pageCount > 1)
        for index in 0..<60 { #expect(text.contains("Item ID: item-\(index)\n")) }
        for value in ["Client: Client person", "Design business", "Business logo not downloaded",
                      "Category: Furnishings", "Space ID: space", "Space: No Space", "SKU: SKU-0"] {
            #expect(text.contains(value))
        }
        for forbidden in ["Total Spent", "Market value", "Total Saved", "Budget", "Receipt", "http"] {
            #expect(!text.contains(forbidden))
        }
        let pages = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }
        for index in 0..<60 {
            #expect(pages.contains { $0.contains("SKU: SKU-\(index)\n") && $0.contains("Item ID: item-\(index)\n") })
        }
    }

    @Test func missingEvidenceCannotExportAndForeignBrandingFails() throws {
        #expect(throws: ClientSummaryPhysicalReportPDFFailure.incompleteDetail) {
            try ClientSummaryPhysicalReportPDF.render(fixture(count: 1, knownAccounting: false))
        }
        #expect(throws: ClientSummaryPhysicalReportPDFFailure.incompleteDetail) {
            try ClientSummaryPhysicalReportPDF.render(fixture(count: 1, knownCategory: false))
        }
        let snapshot = try fixture(count: 1)
        let foreign = try AccountBusinessProfile(accountId: AccountID(validating: "foreign"),
            name: AccountDisplayName(validating: "Foreign"), logo: .absent, isStale: false)
        #expect(throws: ClientSummaryPhysicalReportPDFFailure.accountProfileMismatch) {
            try ClientSummaryPhysicalReportPDF.render(snapshot, profile: foreign)
        }
    }

    @Test func emptyAndOversizedTextRemainVisible() throws {
        let empty = try #require(PDFDocument(data: ClientSummaryPhysicalReportPDF.render(fixture(count: 0))))
        #expect(empty.string?.contains("No data for this report") == true)
        let long = try #require(PDFDocument(data: ClientSummaryPhysicalReportPDF.render(fixture(count: 1, longName: true))))
        #expect(long.pageCount > 1)
        #expect(long.string?.contains("END-LONG-NAME") == true)
        #expect(long.string?.contains("Item ID: item-0") == true)
    }

    @Test func unaccountedPhysicalItemNeverAppearsInPDF() throws {
        let base = try fixture(count: 2), item = base.items[0]
        let unaccounted = ClientSummaryPhysicalReportItem(accountId: item.accountId, projectId: item.projectId,
            itemId: item.itemId, placementId: item.placementId, spaceId: item.spaceId, name: item.name,
            sku: item.sku, category: item.category, itemRevision: item.itemRevision,
            accounting: .init(evidence: try ProjectItemAccountingEvidence(accountId: item.accountId,
                projectId: item.projectId, clientId: ClientID(validating: "client"), itemId: item.itemId,
                spaceId: item.spaceId), relationshipAbsenceIsAuthoritative: true))
        let snapshot = try ClientSummaryPhysicalReportSnapshot.build(project: base.project, client: base.client,
            spaces: base.spaces, items: [unaccounted, base.items[1]], provenance: base.provenance)
        let text = try #require(PDFDocument(data: ClientSummaryPhysicalReportPDF.render(snapshot))?.string)
        #expect(!text.contains("Item ID: item-0"))
        #expect(text.contains("Item ID: item-1"))
    }

    private func fixture(count: Int, knownCategory: Bool = true, longName: Bool = false,
                         knownAccounting: Bool = true) throws -> ClientSummaryPhysicalReportSnapshot {
        let account = try AccountID(validating: "account"), project = try ProjectID(validating: "project")
        let space = try SpaceID(validating: "space")
        return try .build(project: .init(accountId: account, projectId: project, name: "Project house", address: "Example street", revision: 1),
            client: .known(clientId: ClientID(validating: "client"), name: "Client person", revision: 1),
            spaces: [.init(accountId: account, projectId: project, spaceId: space, name: "Living Room", revision: 1)],
            items: (0..<count).map { index in
                .init(accountId: account, projectId: project, itemId: try ItemID(validating: "item-\(index)"),
                    placementId: try EntityID(validating: "placement-\(index)"), spaceId: index % 2 == 0 ? space : nil,
                    name: longName ? String(repeating: "Long Item description. ", count: 1200) + "END-LONG-NAME" : "Item \(index)",
                    sku: "SKU-\(index)", category: knownCategory ?
                        .known(categoryId: try BudgetCategoryID(validating: "category"), name: "Furnishings") : .unavailable, itemRevision: 1,
                    accounting: knownAccounting ? .init(evidence: try ProjectItemAccountingEvidence(
                        accountId: account, projectId: project, clientId: ClientID(validating: "client"),
                        itemId: ItemID(validating: "item-\(index)"), spaceId: index % 2 == 0 ? space : nil,
                        billableOccurrences: [.init(id: BillableItemOccurrenceID(validating: "charge-\(index)"),
                            accountId: account, projectId: project, itemId: ItemID(validating: "item-\(index)"),
                            polarity: .charge, phase: .availableToInvoice)]), relationshipAbsenceIsAuthoritative: true) : nil)
            }, provenance: .init(accountId: account, projectId: project, principalId: PrincipalID(validating: "principal"),
                visibilityScopeID: .make(bytes: Data("scope".utf8)), localDataVersion: .init(validating: "v1"),
                authorityVersion: .init(validating: "authority1"), asOf: .init(validating: 1_800_000_000_000),
                readiness: .ready, lastSyncedAt: .init(validating: 1_800_000_000_000)))
    }
}
#endif
