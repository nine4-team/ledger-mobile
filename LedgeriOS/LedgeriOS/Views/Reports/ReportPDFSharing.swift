import SwiftUI
import WebKit
import PDFKit

enum ReportPDFSharing {
    enum RenderFailure: Error { case loadFailed, renderFailed, emptyDocument, loadTimedOut }

    /// One retained render per call; no shared web view, presentation or file
    /// handoff. The caller revalidates authorization before exporting these bytes.
    @MainActor
    static func renderData(html: String, outputURL: URL? = nil) async throws -> Data {
        let session = ReportPDFRenderSession(outputURL: outputURL)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await session.render(html: html)
        } onCancel: {
            Task { @MainActor in session.cancel() }
        }
    }

    #if canImport(FirebaseFirestore)
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
    #endif
}

#if canImport(FirebaseFirestore)
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
#endif

@MainActor
final class ReportPDFRenderSession: NSObject, WKNavigationDelegate {
    typealias Failure = ReportPDFSharing.RenderFailure
    private var continuation: CheckedContinuation<Data, Error>?
    private var webView: WKWebView?
    private var canceled = false
    private var loadTimeout: Task<Void, Never>?
    private let loadTimeoutDuration: Duration
    private let outputURL: URL?
    private var printing = false
    private var printingFailure: Failure?
    private let didStartPrinting: (@MainActor (ReportPDFRenderSession) -> Void)?

    init(loadTimeoutDuration: Duration = .seconds(30), outputURL: URL? = nil,
         didStartPrinting: (@MainActor (ReportPDFRenderSession) -> Void)? = nil) {
        self.loadTimeoutDuration = loadTimeoutDuration
        self.outputURL = outputURL
        self.didStartPrinting = didStartPrinting
        super.init()
    }

    func render(html: String) async throws -> Data {
        if canceled { throw CancellationError() }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            configuration.defaultWebpagePreferences.allowsContentJavaScript = false
            let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 612, height: 792), configuration: configuration)
            self.webView = view
            view.navigationDelegate = self
            // HTML and images are already local. A missing WebKit callback
            // must not leave the download button permanently busy.
            let duration = loadTimeoutDuration
            loadTimeout = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: duration) }
                catch { return }
                self?.finish(.failure(Failure.loadTimedOut))
            }
            view.loadHTMLString(html, baseURL: nil)
        }
    }

    func cancel() {
        canceled = true
        // Native printing may still be writing its owned destination. Its
        // completion must precede the caller's scratch-file cleanup.
        if !printing { finish(.failure(CancellationError())) }
    }

    private func finish(_ result: Result<Data, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        loadTimeout?.cancel()
        loadTimeout = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        continuation.resume(with: result)
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in navigationFailed() }
    }
    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in navigationFailed() }
    }
    nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Task { @MainActor in navigationFailed() }
    }
    func navigationFailed() {
        if printing { printingFailure = .loadFailed }
        else { finish(.failure(Failure.loadFailed)) }
    }
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            guard continuation != nil, !canceled else { return }
            // This bounds asynchronous loading, not synchronous platform
            // printing. Cancel it before entering the native print engine.
            loadTimeout?.cancel()
            loadTimeout = nil
            do {
                printing = true
                didStartPrinting?(self)
                let data = try await paginatedData(webView)
                printing = false
                if canceled { throw CancellationError() }
                if let printingFailure { throw printingFailure }
                guard let document = PDFDocument(data: data), document.pageCount > 0 else { throw Failure.emptyDocument }
                finish(.success(data))
            } catch { printing = false; finish(.failure(error)) }
        }
    }

    private func paginatedData(_ view: WKWebView) async throws -> Data {
        #if canImport(UIKit)
        let renderer = InvoicePrintPageRenderer()
        let formatter = view.viewPrintFormatter()
        formatter.perPageContentInsets = UIEdgeInsets(top: 24, left: 24, bottom: 42, right: 24)
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        guard renderer.numberOfPages > 0 else { throw Failure.emptyDocument }
        return UIGraphicsPDFRenderer(bounds: renderer.paperRect).pdfData { context in
            for page in 0..<renderer.numberOfPages {
                context.beginPage()
                renderer.drawPage(at: page, in: renderer.paperRect)
            }
        }
        #else
        // AppKit's print engine writes a PDF URL, not in-memory bytes. This
        // private render-only directory is removed before returning; delivery
        // subsequently uses the existing protected report scratch store.
        var temporaryDirectory: URL?
        let url: URL
        if let outputURL { url = outputURL }
        else {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-pdf-render-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700])
            temporaryDirectory = directory
            url = directory.appendingPathComponent("render.pdf")
        }
        defer { if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) } }
        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 612, height: 792)
        info.topMargin = 24; info.bottomMargin = 24; info.leftMargin = 24; info.rightMargin = 24
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        let operation = view.printOperation(with: info)
        operation.canSpawnSeparateThread = true
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        // The document-modal API lets WebKit compute page rectangles while
        // AppKit owns the printing thread. Synchronous run() used the preview
        // path before pagination was ready and could spool indefinitely.
        let completion = InvoiceMacPrintCompletion()
        guard await completion.run(operation, size: view.bounds.size) else { throw Failure.renderFailed }
        return try Data(contentsOf: url)
        #endif
    }
}

#if canImport(AppKit)
@MainActor
private final class InvoiceMacPrintCompletion: NSObject {
    private var continuation: CheckedContinuation<Bool, Never>?
    private var window: NSWindow?

    func run(_ operation: NSPrintOperation, size: NSSize) async -> Bool {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
            styleMask: .borderless, backing: .buffered, defer: false)
        self.window = window
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            operation.runModal(for: window, delegate: self,
                didRun: #selector(completed(_:success:contextInfo:)), contextInfo: nil)
        }
    }

    @objc nonisolated private func completed(_ operation: NSPrintOperation, success: Bool,
                                 contextInfo: UnsafeMutableRawPointer?) {
        Task { @MainActor in finish(success: success) }
    }

    private func finish(success: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        window?.orderOut(nil)
        window = nil
        continuation.resume(returning: success)
    }
}
#endif

#if canImport(UIKit)
@MainActor private final class InvoicePrintPageRenderer: UIPrintPageRenderer {
    override init() {
        super.init()
        footerHeight = 18
    }
    override var paperRect: CGRect { CGRect(x: 0, y: 0, width: 612, height: 792) }
    override var printableRect: CGRect { paperRect.insetBy(dx: 24, dy: 24) }
    override func drawFooterForPage(at pageIndex: Int, in footerRect: CGRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        ("Page \(pageIndex + 1) of \(numberOfPages)" as NSString).draw(in: footerRect.insetBy(dx: 24, dy: 0), withAttributes: [
            .font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.darkGray,
            .paragraphStyle: paragraph
        ])
    }
}
#endif
