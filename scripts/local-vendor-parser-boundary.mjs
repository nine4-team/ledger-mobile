export const sharedVendorParserPaths = [
  "LedgeriOS/Logic/AmazonInvoiceParser.swift",
  "LedgeriOS/Logic/WayfairInvoiceParser.swift",
  "LedgeriOS/Logic/InvoiceMoneyParsing.swift",
  "LedgeriOS/Logic/InvoiceDateParsing.swift",
  "LedgeriOS/Logic/PdfTextExtractor.swift",
];

export function validateLocalVendorParserBoundary(spec, sources) {
  const failures = [];
  const app = spec.split("  LedgerTargetStagingUITests:")[0];
  const paths = [...app.matchAll(/^\s+- path: (.+)$/gm)].map(match => match[1].trim());
  const expected = ["LedgerTargetApp", ...sharedVendorParserPaths];
  if (JSON.stringify([...paths].sort()) !== JSON.stringify([...expected].sort())) {
    failures.push("Target app sources must be its app directory plus the five explicit pure vendor parser files.");
  }
  for (const path of sharedVendorParserPaths) {
    const source = sources.get(path);
    if (typeof source !== "string") { failures.push(`Missing shared parser: ${path}`); continue; }
    const imports = [...source.matchAll(/^\s*import\s+(\w+)/gm)].map(match => match[1]);
    if (!imports.length || imports.some(name => !["Foundation", "PDFKit"].includes(name))) {
      failures.push(`Unreviewed shared parser import: ${path}`);
    }
    if (/\b(?:Firebase\w*|Firestore\w*|Supabase\w*|PowerSync\w*|URLSession|URLRequest|FileManager|FileHandle|Process|UserDefaults)\b|Data\s*\(\s*contentsOf\s*:/.test(source)) {
      failures.push(`Shared parser must operate only on supplied bytes/text: ${path}`);
    }
  }
  return failures;
}
