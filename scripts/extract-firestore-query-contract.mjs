#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const OUTPUT_DIR = path.join(
  ROOT,
  "docs/plans/ledger-accounting-redesign/conversion",
);
const JSON_PATH = path.join(OUTPUT_DIR, "query-contract.generated.json");
const MARKDOWN_PATH = path.join(OUTPUT_DIR, "query-contract.generated.md");

const SOURCE_ROOTS = [
  ["LedgeriOS/LedgeriOS", new Set([".swift"])],
  ["mcp-server/src", new Set([".ts"])],
  ["firebase/functions/src", new Set([".ts"])],
  ["firebase/functions/scripts", new Set([".js", ".mjs", ".ts"])],
  ["migration/src", new Set([".ts"])],
  ["scripts", new Set([".js", ".mjs", ".ts"])],
];

const OPERATIONS = [
  ["collection_group", /\bcollectionGroup\s*\(/],
  ["filter", /\.whereField\s*\(|\.where\s*\(/],
  ["order", /\.order\s*\(|\.orderBy\s*\(/],
  ["limit", /\.limit\s*\(|\.limitToLast\s*\(/],
  ["offset", /\.offset\s*\(/],
  ["cursor", /\.(?:startAt|startAfter|endAt|endBefore)\s*\(/],
  ["listener", /\.addSnapshotListener\b|\.snapshots\s*\(/],
  ["document_read", /\.getDocument\s*\(|\bgetDoc\s*\(/],
  ["collection_read", /\.getDocuments\s*\(|\bqueryDocs\s*\(/],
  ["bulk_document_read", /\.getAll\s*\(|\bgetDocs\s*\(/],
  ["admin_sdk_get", /\.get\s*\(/],
  ["aggregate", /\.count\s*\(|\.aggregate\s*\(/],
  ["projection", /\.select\s*\(/],
];

function relative(filePath) {
  return path.relative(ROOT, filePath).split(path.sep).join("/");
}

function sha(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function walk(directory, extensions) {
  if (!fs.existsSync(directory)) return [];
  const files = [];
  const visit = (current) => {
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      if (["node_modules", "build", "DerivedData", ".git"].includes(entry.name)) {
        continue;
      }
      const fullPath = path.join(current, entry.name);
      if (entry.isDirectory()) visit(fullPath);
      else if (extensions.has(path.extname(entry.name))) files.push(fullPath);
    }
  };
  visit(directory);
  return files.sort();
}

function subsystem(sourcePath) {
  if (sourcePath.startsWith("LedgeriOS/")) return "ios";
  if (sourcePath.startsWith("mcp-server/")) return "mcp";
  if (sourcePath.startsWith("firebase/functions/")) return "functions";
  if (sourcePath.startsWith("migration/")) return "migration";
  return "audit_or_repair_tooling";
}

function isFirestoreSource(text) {
  return /FirebaseFirestore|firebase-admin\/firestore|Firestore|firestore|accountCollection|subcollection|collectionGroup|queryDocs/.test(
    text,
  );
}

function nearestSymbol(lines, index, extension) {
  const swift = /^\s*(?:(?:private|fileprivate|internal|public|open|static|class|actor|nonisolated)\s+)*(?:func|var|let|init)\s+([A-Za-z_][A-Za-z0-9_]*)/;
  const typescript = /^\s*(?:export\s+)?(?:async\s+)?(?:function|const|let)\s+([A-Za-z_][A-Za-z0-9_]*)/;
  const pattern = extension === ".swift" ? swift : typescript;
  for (let cursor = index; cursor >= 0; cursor -= 1) {
    const match = lines[cursor].match(pattern);
    if (match) return match[1];
  }
  return "<module>";
}

function queryWindow(lines, index) {
  let start = index;
  let end = index;
  while (start > 0 && /^\s*\./.test(lines[start])) start -= 1;
  while (
    end + 1 < lines.length &&
    end - start < 8 &&
    (/^\s*\./.test(lines[end + 1]) || /[.(,]$/.test(lines[end].trim()))
  ) {
    end += 1;
  }
  return lines
    .slice(start, end + 1)
    .map((line) => line.trim())
    .filter(Boolean)
    .join(" ")
    .replace(/\s+/g, " ")
    .slice(0, 600);
}

function extract() {
  const occurrences = [];
  const sourceFiles = [];
  let candidateFilesInspected = 0;
  for (const [sourceRoot, extensions] of SOURCE_ROOTS) {
    for (const filePath of walk(path.join(ROOT, sourceRoot), extensions)) {
      const sourcePath = relative(filePath);
      if (
        sourcePath === "scripts/extract-firestore-query-contract.mjs" ||
        sourcePath === "scripts/generate-source-query-reconciliation.mjs" ||
        sourcePath === "scripts/tests/generate-source-query-reconciliation.test.mjs" ||
        sourcePath === "scripts/tests/generate-target-query-logical-authority-crosswalk.test.mjs" ||
        sourcePath.startsWith("scripts/check-target-") ||
        sourcePath.startsWith("scripts/generate-target-")
      ) {
        continue;
      }
      const text = fs.readFileSync(filePath, "utf8");
      if (!isFirestoreSource(text)) continue;
      candidateFilesInspected += 1;
      const lines = text.split("\n");
      let occurrenceCount = 0;
      for (let index = 0; index < lines.length; index += 1) {
        const trimmedLine = lines[index].trim();
        if (trimmedLine.startsWith("//") || trimmedLine.startsWith("*")) continue;
        for (const [operation, pattern] of OPERATIONS) {
          if (!pattern.test(lines[index])) continue;
          const expression = queryWindow(lines, index);
          if (
            operation === "admin_sdk_get" &&
            path.extname(filePath) === ".swift"
          ) {
            continue;
          }
          if (
            operation === "admin_sdk_get" &&
            !/\bawait\b|\b(?:db|tx|firestoreTransaction|transaction|documentRef|collectionRef|query|ref)\s*\.\s*get\s*\(/.test(expression)
          ) {
            continue;
          }
          if (
            operation === "offset" &&
            path.extname(filePath) === ".swift" &&
            /\.offset\s*\(\s*[xy]\s*:/.test(lines[index])
          ) {
            continue;
          }
          occurrences.push({
            id: `QUERY-${sha(`${sourcePath}:${index + 1}:${operation}`).slice(0, 12).toUpperCase()}`,
            subsystem: subsystem(sourcePath),
            sourcePath,
            line: index + 1,
            symbol: nearestSymbol(lines, index, path.extname(filePath)),
            operation,
            expression,
          });
          occurrenceCount += 1;
        }
      }
      if (occurrenceCount > 0) {
        sourceFiles.push({
          sourcePath,
          sourceHash: sha(text),
          occurrenceCount,
        });
      }
    }
  }
  occurrences.sort(
    (a, b) =>
      a.sourcePath.localeCompare(b.sourcePath) ||
      a.line - b.line ||
      a.operation.localeCompare(b.operation),
  );
  sourceFiles.sort((a, b) => a.sourcePath.localeCompare(b.sourcePath));
  return { candidateFilesInspected, sourceFiles, occurrences };
}

function countBy(items, key) {
  const counts = new Map();
  for (const item of items) {
    const value = item[key];
    counts.set(value, (counts.get(value) ?? 0) + 1);
  }
  return Object.fromEntries(
    [...counts.entries()].sort((a, b) => a[0].localeCompare(b[0])),
  );
}

function buildArtifacts() {
  const extracted = extract();
  const sourceDigest = sha(
    extracted.sourceFiles
      .map((source) => `${source.sourcePath}:${source.sourceHash}`)
      .join("\n"),
  );
  const artifact = {
    schemaVersion: 1,
    generator: "scripts/extract-firestore-query-contract.mjs",
    sourceDigest,
    scope: SOURCE_ROOTS.map(([sourceRoot]) => sourceRoot),
    limitations: [
      "This is a lexical, symbol-level inventory; semantic families and offline expectations are reviewed in current-query-contract.md.",
      "Dynamic collection names and deployed index usage require the read-only production profile or Firebase console evidence.",
      "An occurrence proves a source reference, not that the path is exercised in production.",
    ],
    totals: {
      candidateFilesInspected: extracted.candidateFilesInspected,
      sourceFilesWithOccurrences: extracted.sourceFiles.length,
      occurrences: extracted.occurrences.length,
    },
    bySubsystem: countBy(extracted.occurrences, "subsystem"),
    byOperation: countBy(extracted.occurrences, "operation"),
    sourceFiles: extracted.sourceFiles,
    occurrences: extracted.occurrences,
  };
  const json = `${JSON.stringify(artifact, null, 2)}\n`;

  const lines = [
    "# Generated Firestore Query Occurrence Catalog",
    "",
    "> Generated by `node scripts/extract-firestore-query-contract.mjs generate`.",
    "> Do not edit manually. Semantic review lives in `current-query-contract.md`.",
    "",
    `Source digest: \`${sourceDigest}\``,
    "",
    "## Coverage",
    "",
    `- ${artifact.totals.candidateFilesInspected} Firestore-candidate source files inspected`,
    `- ${artifact.totals.sourceFilesWithOccurrences} source files contain recognized occurrences`,
    `- ${artifact.totals.occurrences} query, read, listener, ordering, or pagination occurrences cataloged`,
    "",
    "| Subsystem | Occurrences |",
    "|---|---:|",
    ...Object.entries(artifact.bySubsystem).map(([name, count]) => `| ${name} | ${count} |`),
    "",
    "| Operation | Occurrences |",
    "|---|---:|",
    ...Object.entries(artifact.byOperation).map(([name, count]) => `| ${name} | ${count} |`),
    "",
    "## Source Files",
    "",
    "| Source | Occurrences |",
    "|---|---:|",
    ...artifact.sourceFiles.map(
      (source) => `| \`${source.sourcePath}\` | ${source.occurrenceCount} |`,
    ),
    "",
    "The complete line-level catalog, including stable occurrence IDs, enclosing",
    "symbols, operation types, and normalized expressions, is in",
    "`query-contract.generated.json`.",
    "",
  ];
  return { json, markdown: lines.join("\n") };
}

function writeIfChanged(filePath, value) {
  if (fs.existsSync(filePath) && fs.readFileSync(filePath, "utf8") === value) return;
  fs.writeFileSync(filePath, value);
}

const command = process.argv[2] ?? "check";
const artifacts = buildArtifacts();
if (command === "generate") {
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });
  writeIfChanged(JSON_PATH, artifacts.json);
  writeIfChanged(MARKDOWN_PATH, artifacts.markdown);
  console.log(`Generated ${relative(JSON_PATH)} and ${relative(MARKDOWN_PATH)}.`);
} else if (command === "check") {
  const mismatches = [
    [JSON_PATH, artifacts.json],
    [MARKDOWN_PATH, artifacts.markdown],
  ].filter(([filePath, expected]) =>
    !fs.existsSync(filePath) || fs.readFileSync(filePath, "utf8") !== expected
  );
  if (mismatches.length > 0) {
    console.error(
      `Query contract is stale: ${mismatches.map(([filePath]) => relative(filePath)).join(", ")}`,
    );
    process.exitCode = 1;
  } else {
    console.log("Query contract generated artifacts are current.");
  }
} else {
  console.error("Usage: extract-firestore-query-contract.mjs [generate|check]");
  process.exitCode = 2;
}
