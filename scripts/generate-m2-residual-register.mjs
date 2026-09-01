#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "..");
const conversionDir = path.join(
  repoRoot,
  "docs/plans/ledger-accounting-redesign/conversion",
);
const batchesDir = path.join(conversionDir, "classification-batches");
const jsonPath = path.join(conversionDir, "residual-decision-register.generated.json");
const markdownPath = path.join(conversionDir, "residual-decision-register.generated.md");
const traceabilityPath = path.join(
  repoRoot,
  "docs/architecture/redesign/product-decision-traceability.md",
);
const architectureDecisionsPath = path.join(
  repoRoot,
  "docs/architecture/redesign/architecture-decisions.md",
);
const manifestPath = path.join(conversionDir, "conversion-manifest.json");

function parseTable(file, prefix) {
  const rows = new Map();
  for (const line of fs.readFileSync(file, "utf8").split("\n")) {
    if (!line.startsWith(`| ${prefix}-`)) continue;
    const cells = line
      .split("|")
      .slice(1, -1)
      .map((cell) => cell.trim());
    rows.set(cells[0], cells);
  }
  return rows;
}

const productRows = parseTable(traceabilityPath, "O");
const architectureRows = parseTable(architectureDecisionsPath, "A");
const evidenceBlockers = {
  "Canonical production profile": {
    kind: "production evidence",
    owner: "Source data profiling and migration",
    requirement:
      "Approve and hash a canonical immutable production export/profile that proves extant paths, shapes, variants, orphans and counts.",
  },
  "Canonical production reference/object profile": {
    kind: "production evidence",
    owner: "Attachment source profiling and migration",
    requirement:
      "Approve and hash the production Firestore-reference/Storage-object graph, including shared, dangling, missing and retained evidence variants.",
  },
  "Physical target verification": {
    kind: "target verification",
    owner: "Offline target spike and physical-device acceptance",
    requirement:
      "Run the isolated Supabase/PowerSync target on physical devices and prove restart, offline lease, queue, readiness and reconnect behavior.",
  },
};

function blockerMetadata(blocker) {
  if (productRows.has(blocker)) {
    const row = productRows.get(blocker);
    return {
      kind: "product decision",
      owner: row[1],
      requirement: row[3],
      authority: "docs/plans/ledger-accounting-redesign/decision-log.md",
      traceability: "docs/architecture/redesign/product-decision-traceability.md",
    };
  }
  if (architectureRows.has(blocker)) {
    const row = architectureRows.get(blocker);
    return {
      kind: "architecture decision",
      owner: "Architecture and target spike",
      requirement: `${row[1]}: ${row[2]}`,
      authority: "docs/architecture/redesign/architecture-decisions.md",
    };
  }
  if (evidenceBlockers[blocker]) return evidenceBlockers[blocker];
  throw new Error(`Unknown residual blocker metadata: ${blocker}`);
}

const batchFiles = fs
  .readdirSync(batchesDir)
  .filter((file) => file.endsWith(".json"))
  .sort();
const batches = batchFiles.map((file) =>
  JSON.parse(fs.readFileSync(path.join(batchesDir, file), "utf8")),
);
const targetRelevant = batches.flatMap((batch) =>
  batch.surfaces
    .filter((surface) => ["replace", "redesign", "migrate"].includes(surface.disposition))
    .map((surface) => ({ batchId: batch.batchId, ...surface })),
);
const mapped = targetRelevant.filter((surface) => surface.status === "target_mapped");
const residual = targetRelevant.filter((surface) => surface.status !== "target_mapped");

for (const surface of residual) {
  if (!Array.isArray(surface.blockers) || surface.blockers.length === 0) {
    throw new Error(`Residual surface has no blocker: ${surface.id}`);
  }
}

const grouped = new Map();
for (const surface of residual) {
  for (const blocker of surface.blockers) {
    if (!grouped.has(blocker)) grouped.set(blocker, []);
    grouped.get(blocker).push({
      batchId: surface.batchId,
      id: surface.id,
      disposition: surface.disposition,
      status: surface.status,
      currentBehavior: surface.currentBehavior,
    });
  }
}

const blockers = [...grouped.entries()]
  .map(([id, surfaces]) => ({
    id,
    ...blockerMetadata(id),
    count: surfaces.length,
    surfaces: surfaces.sort((a, b) =>
      `${a.batchId}:${a.id}`.localeCompare(`${b.batchId}:${b.id}`),
    ),
  }))
  .sort((a, b) => b.count - a.count || a.id.localeCompare(b.id));

const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
const generated = {
  schemaVersion: 1,
  generatedAt: null,
  sourceBaseline: manifest.sourceBaseline,
  summary: {
    targetRelevant: targetRelevant.length,
    targetMapped: mapped.length,
    residualSurfaces: residual.length,
    distinctBlockers: blockers.length,
  },
  blockers,
};

function mdEscape(value) {
  return value.replaceAll("|", "\\|").replaceAll("\n", " ");
}

const md = [];
md.push("# M2 Residual Decision Register", "");
md.push(
  "Status: generated; do not edit manually. Regenerate with `npm run conversion:residuals:generate`.",
  "",
  "This register is the deterministic queue for target-relevant surfaces that cannot yet be mapped without a product/architecture decision or required evidence. Product specs and the decision log remain authority; this file never resolves a decision.",
  "",
  "## Summary",
  "",
  `- Target-relevant surfaces: ${targetRelevant.length}`,
  `- Exactly target-mapped: ${mapped.length}`,
  `- Residual surfaces: ${residual.length}`,
  `- Distinct blockers: ${blockers.length}`,
  "",
  "A surface may depend on more than one blocker, so blocker counts do not sum to the residual-surface count.",
  "",
  "## Priority Queue",
  "",
  "| Priority | Blocker | Surfaces | Kind | Owning context | Required closure |",
  "|---:|---|---:|---|---|---|",
);
blockers.forEach((blocker, index) => {
  md.push(
    `| ${index + 1} | \`${blocker.id}\` | ${blocker.count} | ${mdEscape(blocker.kind)} | ${mdEscape(blocker.owner)} | ${mdEscape(blocker.requirement)} |`,
  );
});

md.push("", "## Exact Affected Surfaces", "");
for (const blocker of blockers) {
  md.push(
    `### ${blocker.id} — ${blocker.count} surface${blocker.count === 1 ? "" : "s"}`,
    "",
    `- Kind: ${blocker.kind}`,
    `- Owning context: ${blocker.owner}`,
    `- Required closure: ${blocker.requirement}`,
  );
  if (blocker.authority) md.push(`- Authority: \`${blocker.authority}\``);
  if (blocker.traceability) md.push(`- Traceability: \`${blocker.traceability}\``);
  md.push("", "Affected surfaces:", "");
  for (const surface of blocker.surfaces) {
    md.push(
      `- \`${surface.id}\` — \`${surface.batchId}\` — ${surface.disposition}/${surface.status}: ${surface.currentBehavior}`,
    );
  }
  md.push("");
}

md.push(
  "## Update Rule",
  "",
  "When a decision closes, update the canonical spec/decision log first, then traceability and architecture, then the affected classification entries and target-mapping evidence. Regenerate this register and require `npm run conversion:residuals:check` to pass. Do not reduce the count by replacing an exact blocker with a generic implementation placeholder.",
  "",
);

const jsonOutput = `${JSON.stringify(generated, null, 2)}\n`;
const markdownOutput = `${md.join("\n").trimEnd()}\n`;
const command = process.argv[2] ?? "check";

if (command === "generate") {
  fs.writeFileSync(jsonPath, jsonOutput);
  fs.writeFileSync(markdownPath, markdownOutput);
  console.log(
    `Generated M2 residual register: ${mapped.length} mapped, ${residual.length} residual, ${blockers.length} blockers.`,
  );
} else if (command === "check") {
  const actualJson = fs.existsSync(jsonPath) ? fs.readFileSync(jsonPath, "utf8") : "";
  const actualMarkdown = fs.existsSync(markdownPath)
    ? fs.readFileSync(markdownPath, "utf8")
    : "";
  if (actualJson !== jsonOutput || actualMarkdown !== markdownOutput) {
    console.error(
      "M2 residual generated artifacts are stale. Run npm run conversion:residuals:generate.",
    );
    process.exit(1);
  }
  console.log(
    `M2 residual register is current: ${mapped.length} mapped, ${residual.length} residual, ${blockers.length} blockers.`,
  );
} else {
  console.error("Usage: generate-m2-residual-register.mjs [generate|check]");
  process.exit(2);
}
