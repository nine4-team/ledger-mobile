import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { sharedVendorParserPaths, validateLocalVendorParserBoundary } from "../local-vendor-parser-boundary.mjs";

const spec = readFileSync("LedgeriOS/LedgerTargetProject.yml", "utf8");
const sources = new Map(sharedVendorParserPaths.map(path => [path, readFileSync(`LedgeriOS/${path}`, "utf8")]));
test("target reuses exactly the pure vendor parser sources", () => {
  assert.deepEqual(validateLocalVendorParserBoundary(spec, sources), []);
});
test("legacy import helpers and broad source directories cannot join the target", () => {
  for (const path of ["LedgeriOS/Logic", "LedgeriOS/Logic/InvoiceImportCalculations.swift"]) {
    const changed = spec.replace("- path: LedgerTargetApp", `- path: LedgerTargetApp\n      - path: ${path}`);
    assert.ok(validateLocalVendorParserBoundary(changed, sources).length);
  }
});
test("shared parser cannot gain a provider or autonomous data access", () => {
  for (const code of ["import FirebaseFirestore", "import Supabase", "URLSession.shared", "FileManager.default", "Data(contentsOf: url)"]) {
    const changed = new Map(sources);
    changed.set(sharedVendorParserPaths[0], `${changed.get(sharedVendorParserPaths[0])}\n${code}\n`);
    assert.ok(validateLocalVendorParserBoundary(spec, changed).length, code);
  }
});
