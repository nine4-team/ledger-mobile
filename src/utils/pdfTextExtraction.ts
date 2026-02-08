/**
 * PDF Text Extraction — mobile type definitions and re-exports.
 *
 * The actual extraction runs inside a hidden WebView via pdfjs-dist.
 * See `src/invoice-import/PdfExtractionBridge.tsx` for the bridge component
 * and `src/invoice-import/pdfExtractionWebView.html` for the extraction logic.
 *
 * These types mirror the web app's `pdfTextExtraction.ts` result shape so that
 * downstream consumers (invoice parsers, etc.) can use the same interfaces on
 * both platforms.
 */

/** Result returned by PdfExtractionBridge.extractText(). */
export type PdfTextExtractionResult = {
  /** Extracted text for each page, one string per page. */
  pages: string[];
  /** All pages joined with double newlines. */
  fullText: string;
  /** Extraction statistics. */
  stats: {
    /** Total number of pages in the PDF. */
    pageCount: number;
    /** Total character count in fullText. */
    charCount: number;
    /** Total line count in fullText. */
    lineCount: number;
    /** Wall-clock extraction time in milliseconds. */
    durationMs: number;
  };
};
