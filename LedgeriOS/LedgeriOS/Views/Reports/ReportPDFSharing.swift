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
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 612, height: 792))
        let delegate = PDFNavigationDelegate(fileName: fileName) {
            // Cleanup after PDF is shared
            activeWebView = nil
            activeDelegate = nil
        }
        webView.navigationDelegate = delegate

        // Retain until done
        activeWebView = webView
        activeDelegate = delegate

        webView.loadHTMLString(html, baseURL: nil)
    }
}

@MainActor
private final class PDFNavigationDelegate: NSObject, WKNavigationDelegate {
    let fileName: String
    let cleanup: @MainActor () -> Void

    init(fileName: String, cleanup: @escaping @MainActor () -> Void) {
        self.fileName = fileName
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
                ShareHelper.share(url: tempURL)
            } catch {
                print("⚠️ ReportPDFSharing: PDF generation failed: \(error)")
            }

            self.cleanup()
        }
    }
}
