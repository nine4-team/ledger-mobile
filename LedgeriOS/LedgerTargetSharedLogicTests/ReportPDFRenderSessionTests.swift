import Foundation
import Darwin
import PDFKit
import Testing

@Suite("Invoice renderer lifetime", .serialized)
@MainActor
struct ReportPDFRenderSessionTests {
    @Test(arguments: [false, true])
    func interruptionWaitsForNativeWriter(navigationFailure: Bool) async throws {
        #if os(macOS)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("invoice-interruption-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("render.pdf")
        let session = ReportPDFRenderSession(outputURL: output, didStartPrinting: { session in
            if navigationFailure { session.navigationFailed() }
            else { session.cancel() }
        })
        do {
            _ = try await session.render(html: "<html><body>PRINT-COMPLETION-BEFORE-CLEANUP</body></html>")
            Issue.record("Interrupted render must not return exportable bytes")
        } catch is CancellationError {
            #expect(!navigationFailure)
        } catch ReportPDFSharing.RenderFailure.loadFailed {
            #expect(navigationFailure)
        }
        // The caller may now remove the file: the real native writer has
        // completed, even though the operation reports cancellation/failure.
        let bytes = try Data(contentsOf: output)
        #expect(PDFDocument(data: bytes)?.string?.contains("PRINT-COMPLETION-BEFORE-CLEANUP") == true)
        #endif
    }

    @Test func nativeRendererUsesOwnedScratchOutput() async throws {
        let path = try #require(realpath(FileManager.default.temporaryDirectory.path, nil))
        defer { free(path) }
        let parent = URL(fileURLWithPath: String(cString: path))
            .appendingPathComponent("invoice-render-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = parent.appendingPathComponent(ReportScratchStore.directoryName)
        let store = try ReportScratchStore(rootDirectory: root)
        let data = try await store.generatePDF { url in
            await #expect(throws: ReportScratchFailure.artifactsPending) { try await store.close() }
            let bytes = try await ReportPDFSharing.renderData(
                html: "<html><body>OWNED-INVOICE-OUTPUT</body></html>", outputURL: url)
            #expect(try Data(contentsOf: url) == bytes)
            return bytes
        }
        #expect(PDFDocument(data: data)?.string?.contains("OWNED-INVOICE-OUTPUT") == true)
        try await store.close()
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test func simultaneousExportsKeepTheirOwnContents() async throws {
        async let first = ReportPDFSharing.renderData(html: "<html><body>FIRST-INVOICE-ONLY</body></html>")
        async let second = ReportPDFSharing.renderData(html: "<html><body>SECOND-INVOICE-ONLY</body></html>")
        let (firstData, secondData) = try await (first, second)
        let firstText = try #require(PDFDocument(data: firstData)?.string)
        let secondText = try #require(PDFDocument(data: secondData)?.string)
        #expect(firstText.contains("FIRST-INVOICE-ONLY") && !firstText.contains("SECOND-INVOICE-ONLY"))
        #expect(secondText.contains("SECOND-INVOICE-ONLY") && !secondText.contains("FIRST-INVOICE-ONLY"))
    }

    @Test func nativeRendererProducesCompleteDocument() async throws {
        let rows = (0..<80).map {
            InvoiceLineEntry(name: "Invoice line \($0)", priceCents: 101,
                isMissingPrice: false)
        }
        let html = ReportHTMLBuilder.invoice(data: InvoiceReportData(chargeLines: rows, creditLines: []),
            projectName: "PDF QA Project", clientName: "PDF QA Client", businessName: "Design Studio",
            logoBase64: nil, invoiceName: "QA-001", invoiceStatusLabel: "Paid",
            notes: "Final note", totalLabel: "Invoice Total", provenance: "Collected by Purchase QA-payment")
        let data = try await ReportPDFSharing.renderData(html: html)
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount > 1)
        let text = document.string ?? ""
        for index in 0..<80 { #expect(text.contains("Invoice line \(index)")) }
        #expect(text.contains("Invoice Total") && text.contains("80.80"))
        #expect(text.contains("Final note") && text.contains("QA-payment"))
        if ProcessInfo.processInfo.environment["LEDGER_RETAIN_PDF_QA"] == "1" {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-invoice-qa-\(UUID().uuidString).pdf")
            try data.write(to: url, options: .atomic)
            print("Retained synthetic Invoice QA PDF: \(url.path)")
        }
    }

    @Test func loadingTimeoutReturnsFailure() async throws {
        let session = ReportPDFRenderSession(loadTimeoutDuration: .zero)
        do {
            _ = try await session.render(html: "<html><body>Invoice</body></html>")
            Issue.record("Expected loading deadline to fail before WebKit navigation completes")
        } catch ReportPDFSharing.RenderFailure.loadTimedOut {
            // Cancellation after completion must not resume the continuation twice.
            session.cancel()
        }
    }

    @Test func cancellationBeforeLoadingReturnsImmediately() async throws {
        let session = ReportPDFRenderSession()
        session.cancel()
        do {
            _ = try await session.render(html: "<html><body>Invoice</body></html>")
            Issue.record("Canceled renderer must not produce bytes")
        } catch is CancellationError { }
    }
}
