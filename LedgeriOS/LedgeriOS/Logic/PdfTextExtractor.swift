import Foundation
import PDFKit

/// Extracts text from PDF data using native PDFKit.
/// Replaces the pdf.js WebView bridge used in the RN app.
enum PdfTextExtractor {

    struct ExtractionStats {
        let pageCount: Int
        let charCount: Int
        let lineCount: Int
        let durationMs: Int
    }

    struct PdfTextResult {
        let pages: [String]
        let fullText: String
        let stats: ExtractionStats
    }

    /// Extracts text from PDF data, returning per-page text, full text, and extraction stats.
    static func extractText(from data: Data) -> PdfTextResult? {
        let start = CFAbsoluteTimeGetCurrent()

        guard let document = PDFDocument(data: data) else { return nil }

        var pages: [String] = []
        for i in 0..<document.pageCount {
            let pageText = document.page(at: i)?.string ?? ""
            pages.append(pageText)
        }

        let fullText = pages.joined(separator: "\n")
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        let stats = ExtractionStats(
            pageCount: document.pageCount,
            charCount: fullText.count,
            lineCount: fullText.components(separatedBy: .newlines).count,
            durationMs: Int(elapsed * 1000)
        )

        return PdfTextResult(pages: pages, fullText: fullText, stats: stats)
    }
}
