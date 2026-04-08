import SwiftUI
import WebKit

enum ReportPDFSharing {

    /// Retained until PDF generation completes.
    @MainActor
    private static var activeWebView: WKWebView?
    @MainActor
    private static var activeDelegate: PDFNavigationDelegate?

    @MainActor
    static func sharePDF(
        html: String,
        fileName: String
    ) {
        renderPDF(html: html, fileName: fileName, sink: .share)
    }

    @MainActor
    static func downloadPDF(
        html: String,
        fileName: String
    ) {
        renderPDF(html: html, fileName: fileName, sink: .download)
    }

    @MainActor
    private static func renderPDF(html: String, fileName: String, sink: PDFSink) {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 612, height: 792))
        let delegate = PDFNavigationDelegate(fileName: fileName, sink: sink) {
            activeWebView = nil
            activeDelegate = nil
        }
        webView.navigationDelegate = delegate

        activeWebView = webView
        activeDelegate = delegate

        webView.loadHTMLString(html, baseURL: nil)
    }
}

enum PDFSink {
    case share
    case download
}

@MainActor
private final class PDFNavigationDelegate: NSObject, WKNavigationDelegate {
    let fileName: String
    let sink: PDFSink
    let cleanup: @MainActor () -> Void

    init(fileName: String, sink: PDFSink, cleanup: @escaping @MainActor () -> Void) {
        self.fileName = fileName
        self.sink = sink
        self.cleanup = cleanup
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            // Brief delay to let layout settle
            try? await Task.sleep(for: .milliseconds(100))

            let config = WKPDFConfiguration()
            config.rect = CGRect(x: 0, y: 0, width: 612, height: 792)

            do {
                let data = try await webView.pdf(configuration: config)
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(self.fileName)
                try data.write(to: tempURL)
                switch self.sink {
                case .share:    ShareHelper.share(url: tempURL)
                case .download: PDFDownloadHelper.download(url: tempURL)
                }
            } catch {
                print("⚠️ ReportPDFSharing: PDF generation failed: \(error)")
            }

            self.cleanup()
        }
    }
}
