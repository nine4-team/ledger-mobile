#if canImport(PDFKit)
import Foundation
import PDFKit
import ImageIO
import Testing
import LedgerTargetCore
import LedgerTargetAppModel

@Suite("Property report PDF rendering")
struct PropertyManagementReportPDFTests {
    @Test("Large logo is downsampled and branded PDF preserves all report rows")
    func boundedLogoPDF() throws {
        let bitmap = try #require(CGContext(data: nil, width: 2048, height: 1024,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        bitmap.setFillColor(CGColor(red: 0.1, green: 0.3, blue: 0.6, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: 2048, height: 1024))
        let original = try #require(bitmap.makeImage())
        let encoded = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(encoded, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, original, nil)
        #expect(CGImageDestinationFinalize(destination))
        let decoded = try #require(AccountBusinessLogoImage.decode(encoded as Data))
        #expect(decoded.width == 1024 && decoded.height == 512)
        #expect(AccountBusinessLogoImage.decode(Data([1, 2, 3])) == nil)
        let snapshot = try fixture(count: 30)
        let profile = try AccountBusinessProfile(accountId: snapshot.project.accountId,
            name: AccountDisplayName(validating: "Design studio"), logo: .downloaded(encoded as Data), isStale: true)
        let bytes = try PropertyManagementReportPDF.render(snapshot, profile: profile)
        let document = try #require(PDFDocument(data: bytes))
        let text = try #require(document.string)
        #expect(document.pageCount > 1 && text.contains("Design studio"))
        #expect(!text.contains("Business logo unavailable"))
        for index in 0..<30 { #expect(text.contains("Item ID: item-\(String(format: "%03d", index))")) }
        if let path = ProcessInfo.processInfo.environment["LEDGER_BRANDED_PDF_QA_OUTPUT"] {
            try bytes.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }

    @Test("PDF uses selected Account branding, reports unavailable logos, and rejects foreign branding")
    func accountBranding() throws {
        let snapshot = try fixture(count: 2)
        for logo: AccountBusinessProfile.Logo in [.absent, .notDownloaded, .unavailable, .downloaded(Data([0, 1]))] {
            let profile = try AccountBusinessProfile(accountId: snapshot.project.accountId,
                name: AccountDisplayName(validating: "Design studio"), logo: logo, isStale: true)
            let document = try #require(PDFDocument(data: PropertyManagementReportPDF.render(snapshot, profile: profile)))
            let text = try #require(document.string)
            #expect(text.contains("Design studio") && text.contains("Saved business profile"))
            #expect(text.contains("Report totals"))
            switch logo {
            case .absent: #expect(text.contains("No business logo"))
            case .notDownloaded: #expect(text.contains("Business logo not downloaded"))
            default: #expect(text.contains("Business logo unavailable"))
            }
        }
        let foreign = try AccountBusinessProfile(accountId: AccountID(validating: "foreign-account"),
            name: AccountDisplayName(validating: "Foreign studio"), logo: .absent, isStale: false)
        #expect(throws: PropertyManagementReportPDFFailure.self) {
            try PropertyManagementReportPDF.render(snapshot, profile: foreign)
        }
    }

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
