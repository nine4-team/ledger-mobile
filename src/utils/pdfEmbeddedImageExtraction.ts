/**
 * PDF Embedded Image Extraction — mobile type definitions and re-exports.
 *
 * The actual extraction runs inside a hidden WebView via pdfjs-dist.
 * See `src/invoice-import/PdfExtractionBridge.tsx` for the bridge component
 * and `src/invoice-import/pdfExtractionWebView.html` for the extraction logic.
 *
 * These types mirror the web app's `pdfEmbeddedImageExtraction.ts` result shape
 * so that downstream consumers can use the same interfaces on both platforms.
 */

/** A single embedded image extracted from a PDF. */
export type PdfEmbeddedImage = {
  /** Base64-encoded PNG data URI (e.g. "data:image/png;base64,..."). */
  dataUri: string;
  /** 1-based page number where the image was found. */
  pageNumber: number;
  /** Bounding box in PDF coordinate space (points). */
  bbox: { xMin: number; yMin: number; xMax: number; yMax: number };
  /** Height of the page in PDF points. */
  pageHeight: number;
  /**
   * Quality/relevance score. Higher is better.
   * Based on area in PDF points, penalized for extreme aspect ratios.
   */
  score: number;
};
