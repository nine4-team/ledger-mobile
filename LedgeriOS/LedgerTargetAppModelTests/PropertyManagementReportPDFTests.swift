#if canImport(PDFKit)
import Foundation
import PDFKit
import Testing
import LedgerTargetCore
import LedgerTargetAppModel

@Suite("Property report PDF rendering")
struct PropertyManagementReportPDFTests {
    @Test("Multi-page PDF includes every Item, exact values, unknowns and provenance")
    func paginated() throws {
        let snapshot = try fixture(count: 80)
        let bytes = try PropertyManagementReportPDF.render(snapshot)
        let document = try #require(PDFDocument(data: bytes))
        #expect(document.pageCount > 1)
        let text = try #require(document.string)
        for index in 0..<80 {
            #expect(text.contains("Item ID: item-\(String(format: "%03d", index))"))
            let pages = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }
            #expect(pages.contains { $0.contains("SKU: SKU-\(index)\n") && $0.contains("Item ID: item-\(String(format: "%03d", index))") })
        }
        #expect(text.contains("90071992547409.93"))
        #expect(text.contains("Unknown values: 79"))
        #expect(text.contains(snapshot.reference.snapshotID.rawValue))
        #expect(text.contains("property-management-v1"))
        for index in 0..<document.pageCount {
            let page = try #require(document.page(at: index))
            #expect(page.bounds(for: .mediaBox).width == 612)
            #expect(page.bounds(for: .mediaBox).height == 792)
            #expect(page.string?.contains("Page \(index + 1)") == true)
        }
        // Optional explicit local QA output, never a production export path.
        if let path = ProcessInfo.processInfo.environment["LEDGER_REPORT_PDF_QA_OUTPUT"] {
            try bytes.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }

    @Test("Empty and exceptionally long Item text are neither hidden nor clipped away")
    func emptyAndLongText() throws {
        let empty = try #require(PDFDocument(data: PropertyManagementReportPDF.render(fixture(count: 0))))
        #expect(empty.string?.contains("No data for this report") == true)
        let long = try fixture(count: 1, longName: true)
        let document = try #require(PDFDocument(data: PropertyManagementReportPDF.render(long)))
        #expect(document.pageCount > 1)
        #expect(document.string?.contains("END-OF-LONG-NAME") == true)
        #expect(document.string?.contains("Report totals") == true)
    }

    private func fixture(count: Int, longName: Bool = false) throws -> PropertyManagementReportSnapshot {
        let account = try AccountID(validating: "pdf-account")
        let project = try ProjectID(validating: "pdf-project")
        let currency = try CurrencyCode(validating: "USD")
        let space = try SpaceID(validating: "pdf-space")
        let items = try (0..<count).map { index in
            PropertyManagementReportItem(accountId: account, projectId: project,
                itemId: try ItemID(validating: "item-\(String(format: "%03d", index))"),
                placementId: try EntityID(validating: "placement-\(index)"), spaceId: index % 2 == 0 ? space : nil,
                name: longName ? String(repeating: "Long descriptive Item name with dimensions and finishes. ", count: 400) + "END-OF-LONG-NAME" : "Furnishing \(index)",
                sku: "SKU-\(index)", marketValue: index == 0 ? Money(minorUnits: 9_007_199_254_740_993, currency: currency) : nil,
                itemRevision: 1)
        }
        return try .build(project: .init(accountId: account, projectId: project, name: "Synthetic property",
            address: "123 Example Street", revision: 1),
            spaces: [.init(accountId: account, projectId: project, spaceId: space, name: "Living Room", revision: 1)],
            items: items, currency: currency,
            provenance: .init(accountId: account, projectId: project, principalId: PrincipalID(validating: "pdf-principal"),
                visibilityScopeID: .make(bytes: Data("pdf-fixture".utf8)), localDataVersion: .init(validating: "pdf-fixture-1"),
                authorityVersion: .init(validating: "property-management-v1"), asOf: .init(validating: 1_800_000_000_000),
                readiness: .ready, lastSyncedAt: .init(validating: 1_799_999_000_000)))
    }
}
#endif
