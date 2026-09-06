#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const OUTPUT_DIR = path.join(ROOT, "docs/plans/ledger-accounting-redesign/conversion");
const JSON_PATH = path.join(OUTPUT_DIR, "capability-surfaces.generated.json");
const MARKDOWN_PATH = path.join(OUTPUT_DIR, "capability-surfaces.generated.md");
const SOURCE_ROOTS = [
  ["LedgeriOS/LedgeriOS/Auth", ".swift", "swift"],
  ["LedgeriOS/LedgeriOS/Services", ".swift", "swift"],
  ["mcp-server/src", ".ts", "mcp"],
];

function relative(filePath) {
  return path.relative(ROOT, filePath).split(path.sep).join("/");
}

function sha(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function walk(directory, extension) {
  const files = [];
  const visit = (current) => {
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      if (["node_modules", "build", "DerivedData", ".git"].includes(entry.name)) continue;
      const fullPath = path.join(current, entry.name);
      if (entry.isDirectory()) visit(fullPath);
      else if (entry.name.endsWith(extension)) files.push(fullPath);
    }
  };
  if (fs.existsSync(directory)) visit(directory);
  return files.sort();
}

function swiftCapability(baseName) {
  if (/^(AuthManager|AccountMembersService|AccountsService|InviteLinks|InvitesService)$/.test(baseName)) {
    return "identity_accounts_and_invites";
  }
  if (/^(AccountPresetsService|BudgetCategoriesService|ProjectBudgetCategoriesService|ProjectPreferencesService|SpaceTemplatesService|VendorDefaultsService|SettingsServiceProtocols|BudgetServiceProtocols)$/.test(baseName)) {
    return "settings_and_reference_data";
  }
  if (/^(ProjectService|ProjectServiceProtocol|ProjectNotesService|ProjectNotesServiceProtocol)$/.test(baseName)) {
    return "projects_and_clients";
  }
  if (/^(SpacesService|SpacesServiceProtocol|SpaceReviewNotesService)$/.test(baseName)) {
    return "spaces_and_review";
  }
  if (/^(ItemsService|ItemsServiceProtocol|ProtoItemsService|ProtoItemsServiceProtocol|ItemTagExtractionService)$/.test(baseName)) {
    return "items_and_quick_capture";
  }
  if (/^(InventoryOperationsService|LineageEdgesService)$/.test(baseName)) {
    return "inventory_movement_and_provenance";
  }
  if (/^(TransactionsService|TransactionsServiceProtocol)$/.test(baseName)) {
    return "transactions_receipts_and_corrections";
  }
  if (/^(InvoiceService|InvoiceServiceProtocol|BudgetProgressService)$/.test(baseName)) {
    return "invoicing_collection_and_budget";
  }
  if (/^(ImageCache|ImageThumbnailGenerator|MediaService|MediaUploadQueue|StorageURLResolver)$/.test(baseName)) {
    return "media_and_attachments";
  }
  if (/^(FirebaseEmulatorConfig|FirestoreRepository|BatchWriting|RepositoryProtocol)$/.test(baseName)) {
    return "platform_transport_and_legacy_persistence";
  }
  return null;
}

function mcpCapability(sourcePath) {
  if (/\/tools\/accounts\.ts$|\/(?:auth|oauth|userState)\.ts$/.test(sourcePath)) {
    return "identity_accounts_and_invites";
  }
  if (/\/tools\/(?:projects|project-notes)\.ts$|\/util\/notes\.ts$/.test(sourcePath)) {
    return "projects_and_clients";
  }
  if (/\/tools\/spaces\.ts$|\/util\/space-assignments\.ts$/.test(sourcePath)) {
    return "spaces_and_review";
  }
  if (/\/tools\/(?:items|quick-draft-items)\.ts$/.test(sourcePath)) {
    return "items_and_quick_capture";
  }
  if (/\/tools\/(?:inventory-operations|lineage|purchase-intents)\.ts$|\/util\/(?:inventory|item-pricing)\.ts$/.test(sourcePath)) {
    return "inventory_movement_and_provenance";
  }
  if (/\/tools\/(?:transactions|transaction-item-corrections)\.ts$|\/util\/transaction-deletion\.ts$/.test(sourcePath)) {
    return "transactions_receipts_and_corrections";
  }
  if (/\/tools\/(?:invoices|budget)\.ts$|\/util\/budget\.ts$/.test(sourcePath)) {
    return "invoicing_collection_and_budget";
  }
  if (/\/storage\.ts$|\/util\/(?:attachment-primary|item-image-storage|item-images|thumbnail)\.ts$/.test(sourcePath)) {
    return "media_and_attachments";
  }
  if (/\/tools\/(?:analytics|bulk-getters|composite)\.ts$|\/resources\/|\/util\/search\.ts$/.test(sourcePath)) {
    return "reporting_search_and_cross_domain_queries";
  }
  if (/\/(?:config|context|firebase|http|index|server)\.ts$|\/tools\/(?:schema|server-info)\.ts$|\/(?:types)\.ts$|\/util\/(?:enums|errors|format|projections|query|telemetry)\.ts$/.test(sourcePath)) {
    return "platform_transport_and_legacy_persistence";
  }
  return null;
}

function extractNames(text, subsystem) {
  const names = new Set();
  const patterns = subsystem === "swift"
    ? [
        /\b(?:final\s+)?(?:class|struct|actor|enum|protocol)\s+([A-Za-z_][A-Za-z0-9_]*)/g,
        /^\s*(?:public\s+|private\s+|fileprivate\s+|internal\s+|static\s+|class\s+|nonisolated\s+|mutating\s+)*func\s+([A-Za-z_][A-Za-z0-9_]*)/gm,
      ]
    : [
        /\bexport\s+(?:default\s+)?(?:async\s+)?(?:function|const|let|class|interface|type)\s+([A-Za-z_][A-Za-z0-9_]*)/g,
        /\bserver\.tool\(\s*["']([^"']+)["']/g,
        /\bserver\.resource\(\s*["']([^"']+)["']/g,
      ];
  for (const pattern of patterns) {
    for (const match of text.matchAll(pattern)) names.add(match[1]);
  }
  return [...names].sort();
}

function countMatches(text, pattern) {
  return [...text.matchAll(pattern)].length;
}

function analyze(filePath, subsystem) {
  const sourcePath = relative(filePath);
  const text = fs.readFileSync(filePath, "utf8");
  const baseName = path.basename(filePath, path.extname(filePath));
  const capability = subsystem === "swift"
    ? swiftCapability(baseName)
    : mcpCapability(sourcePath);
  if (!capability) throw new Error(`Unassigned capability surface: ${sourcePath}`);
  return {
    id: `CAPSURF-${sha(sourcePath).slice(0, 12).toUpperCase()}`,
    capability,
    subsystem,
    sourcePath,
    sourceHash: sha(text),
    lineCount: text.split("\n").length,
    declaredSurfaceNames: extractNames(text, subsystem),
    coupling: {
      firebase: /Firebase|Firestore|firebase-admin|accountCollection|DocumentSnapshot|ListenerRegistration/.test(text),
      network: /URLSession|fetch\s*\(|https?:\/\//.test(text),
      media: /Storage|storage|thumbnail|image|attachment|upload/i.test(text),
    },
    signals: {
      observations: countMatches(text, /addSnapshotListener|subscribe|observe|watch[A-Z]/g),
      reads: countMatches(text, /getDocument|getDocuments|queryDocs|getDoc|getAll|\.get\s*\(/g),
      mutations: countMatches(text, /setData|updateData|delete\s*\(|\.set\s*\(|\.update\s*\(|\.create\s*\(|writeBatch|runTransaction/g),
      offlineOrQueue: countMatches(text, /offline|pending|queue|retry|cache/gi),
    },
  };
}

function countBy(records, key) {
  const counts = {};
  for (const record of records) counts[record[key]] = (counts[record[key]] ?? 0) + 1;
  return Object.fromEntries(Object.entries(counts).sort(([a], [b]) => a.localeCompare(b)));
}

function buildArtifacts() {
  const records = [];
  for (const [sourceRoot, extension, subsystem] of SOURCE_ROOTS) {
    for (const filePath of walk(path.join(ROOT, sourceRoot), extension)) {
      records.push(analyze(filePath, subsystem));
    }
  }
  records.sort((a, b) => a.capability.localeCompare(b.capability) || a.sourcePath.localeCompare(b.sourcePath));
  const sourceDigest = sha(records.map((record) => `${record.sourcePath}:${record.sourceHash}`).join("\n"));
  const artifact = {
    schemaVersion: 1,
    generator: "scripts/extract-current-capability-surfaces.mjs",
    sourceDigest,
    scope: SOURCE_ROOTS.map(([sourceRoot]) => sourceRoot),
    totals: {
      surfaces: records.length,
      swift: records.filter((record) => record.subsystem === "swift").length,
      mcp: records.filter((record) => record.subsystem === "mcp").length,
    },
    byCapability: countBy(records, "capability"),
    limitations: [
      "Capability assignment is explicit source triage, not an approved target port or table map.",
      "Signals are lexical evidence and must be reviewed with callers, specs, production shape, and tests in each capability dossier.",
      "UI/view callers, models, tests, Functions, migration tools, and operational configuration remain separate manifest surfaces linked during dossier review.",
    ],
    surfaces: records,
  };
  const json = `${JSON.stringify(artifact, null, 2)}\n`;
  const lines = [
    "# Generated Current Capability Surface Catalog",
    "",
    "> Generated by `node scripts/extract-current-capability-surfaces.mjs generate`.",
    "> Do not edit manually. Capability decisions belong in reviewed dossiers.",
    "",
    `Source digest: \`${sourceDigest}\``,
    "",
    `This catalog assigns all ${artifact.totals.surfaces} current Swift service/Auth and MCP source modules (${artifact.totals.swift} Swift, ${artifact.totals.mcp} MCP) to an initial user or operational capability. Assignment is discovery evidence, not target design.`,
    "",
    "| Capability | Surfaces |",
    "|---|---:|",
    ...Object.entries(artifact.byCapability).map(([capability, count]) => `| \`${capability}\` | ${count} |`),
    "",
  ];
  for (const capability of Object.keys(artifact.byCapability)) {
    lines.push(`## ${capability}`, "", "| Subsystem | Source | Declared surface names |", "|---|---|---|");
    for (const record of records.filter((entry) => entry.capability === capability)) {
      const names = record.declaredSurfaceNames.length > 0
        ? record.declaredSurfaceNames.map((name) => `\`${name}\``).join(", ")
        : "—";
      lines.push(`| ${record.subsystem} | \`${record.sourcePath}\` | ${names} |`);
    }
    lines.push("");
  }
  lines.push(
    "The JSON artifact also records source hashes, line counts, backend/network/media coupling, and lexical read/mutation/observation/offline signals for review.",
    "",
  );
  return { json, markdown: lines.join("\n") };
}

function writeIfChanged(filePath, value) {
  if (fs.existsSync(filePath) && fs.readFileSync(filePath, "utf8") === value) return;
  fs.writeFileSync(filePath, value);
}

const command = process.argv[2] ?? "check";
const artifacts = buildArtifacts();
if (command === "generate") {
  writeIfChanged(JSON_PATH, artifacts.json);
  writeIfChanged(MARKDOWN_PATH, artifacts.markdown);
  console.log(`Generated ${relative(JSON_PATH)} and ${relative(MARKDOWN_PATH)}.`);
} else if (command === "check") {
  const stale = [
    [JSON_PATH, artifacts.json],
    [MARKDOWN_PATH, artifacts.markdown],
  ].filter(([filePath, value]) => !fs.existsSync(filePath) || fs.readFileSync(filePath, "utf8") !== value);
  if (stale.length > 0) {
    console.error(`Capability surface catalog is stale: ${stale.map(([filePath]) => relative(filePath)).join(", ")}`);
    process.exitCode = 1;
  } else {
    console.log("Capability surface generated artifacts are current.");
  }
} else {
  console.error("Usage: extract-current-capability-surfaces.mjs [generate|check]");
  process.exitCode = 2;
}
