#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const PROGRAM_DIR = path.join(
  ROOT,
  "docs/plans/ledger-accounting-redesign/conversion",
);
const MANIFEST_PATH = path.join(PROGRAM_DIR, "conversion-manifest.json");
const REPORT_PATH = path.join(PROGRAM_DIR, "conversion-coverage.md");
const BATCH_DIR = path.join(PROGRAM_DIR, "classification-batches");
const PRODUCT_AUTHORITY_CROSSWALK_PATH = path.join(
  PROGRAM_DIR,
  "product-authority-crosswalk.json",
);
const PRODUCT_AUTHORITY_AUDIT_JSON_PATH = path.join(
  PROGRAM_DIR,
  "product-authority-audit.generated.json",
);
const PRODUCT_AUTHORITY_AUDIT_MARKDOWN_PATH = path.join(
  PROGRAM_DIR,
  "product-authority-audit.generated.md",
);
const IMPLEMENTATION_SLICE_DIR = path.join(PROGRAM_DIR, "implementation-slices");
const IMPLEMENTATION_SLICE_AUDIT_JSON_PATH = path.join(
  PROGRAM_DIR,
  "implementation-slice-audit.generated.json",
);
const IMPLEMENTATION_SLICE_AUDIT_MARKDOWN_PATH = path.join(
  PROGRAM_DIR,
  "implementation-slice-audit.generated.md",
);

const allowedStatuses = new Set([
  "discovered",
  "characterized",
  "target_mapped",
  "implemented",
  "verified",
  "rehearsed",
  "cutover_ready",
  "retired",
  "blocked",
]);

const allowedDispositions = new Set([
  "unclassified",
  "preserve",
  "replace",
  "redesign",
  "migrate",
  "retire",
  "externalize",
  "source_only",
]);

const targetRequiredDispositions = new Set([
  "replace",
  "redesign",
  "migrate",
]);

const allowedAuthorityScopes = new Set(["product", "technical_control"]);
const allowedAuthorityRoles = new Set([
  "canonical_target",
  "current_product",
  "historical_evidence",
  "decision_authority",
  "architecture_authority",
  "conversion_control",
]);

const allowedSliceKinds = new Set(["product", "technical_control"]);
const allowedSliceStatuses = new Set([
  "draft",
  "ready",
  "in_progress",
  "implemented",
  "verified",
  "rehearsed",
  "cutover_ready",
]);
const allowedVerificationKinds = new Set([
  "domain",
  "database_invariant",
  "handler_idempotency",
  "rls_positive",
  "rls_negative",
  "sync_authorization",
  "offline_restart",
  "offline_rejection",
  "media_fault",
  "migration",
  "reconciliation",
  "app_mcp_contract",
  "advisor",
  "end_to_end",
  "operational",
]);
const allowedVerificationStatuses = new Set([
  "planned",
  "passed",
  "failed",
  "blocked",
]);
const requiredSliceContractKeys = [
  "domain",
  "postgresSchema",
  "serverHandlers",
  "dataApiGrants",
  "rlsPolicies",
  "syncStreams",
  "localOffline",
  "storageMedia",
  "appMcp",
  "migrationReconciliation",
  "observabilityRunbooks",
  "rolloutRollback",
];
const implementationSurfaceStatuses = new Set([
  "implemented",
  "verified",
  "rehearsed",
  "cutover_ready",
]);

function relative(filePath) {
  return path.relative(ROOT, filePath).split(path.sep).join("/");
}

function read(filePath) {
  return fs.readFileSync(filePath, "utf8");
}

function sha(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function stableId(prefix, key) {
  return `${prefix}-${sha(key).slice(0, 12).toUpperCase()}`;
}

function walk(directory, predicate = () => true) {
  if (!fs.existsSync(directory)) return [];
  const files = [];
  const visit = (current) => {
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      if (["node_modules", "DerivedData", "build", ".git"].includes(entry.name)) {
        continue;
      }
      const fullPath = path.join(current, entry.name);
      if (entry.isDirectory()) visit(fullPath);
      else if (predicate(fullPath)) files.push(fullPath);
    }
  };
  visit(directory);
  return files.sort();
}

function lineNumber(text, offset) {
  return text.slice(0, offset).split("\n").length;
}

function swiftKind(filePath) {
  const rel = relative(filePath);
  if (
    rel.includes("/LedgerTargetCore/") ||
    rel.includes("/LedgerTargetAppModel/") ||
    rel.includes("/LedgerTargetComposition/") ||
    rel.includes("/LedgerTargetMigrationCore/") ||
    rel.includes("/LedgerTargetTestSupport/")
  ) {
    return "swift_platform";
  }
  if (rel.includes("/Auth/")) return "swift_auth";
  if (rel.includes("/Services/")) return "swift_service";
  if (rel.includes("/Views/")) return "swift_view";
  if (rel.includes("/Models/")) return "swift_model";
  if (rel.includes("/State/")) return "swift_state";
  if (rel.includes("/Logic/")) return "swift_logic";
  if (rel.includes("/Components/") || rel.includes("/Modals/")) {
    return "swift_ui_component";
  }
  if (rel.includes("/Platform/")) return "swift_platform";
  return "swift_application_file";
}

function makeSurface({
  id,
  kind,
  name,
  sourceRefs,
  sourceHash,
  metadata = {},
  discovery = "automatic",
}) {
  return {
    id,
    kind,
    name,
    discovery,
    sourcePresence: "present",
    sourceRefs,
    observedSourceHash: sourceHash,
    acknowledgedSourceHash: null,
    metadata,
    currentBehavior: "",
    disposition: "unclassified",
    target: {
      owner: "",
      surfaces: [],
      securityRequirements: [],
      syncRequirements: [],
    },
    migration: {
      rule: "",
      reconciliation: [],
    },
    verification: {
      tests: [],
      acceptance: [],
    },
    status: "discovered",
    blockers: [],
    evidence: [],
    notes: "",
    classificationBatch: null,
  };
}

function loadClassificationBatches() {
  return walk(BATCH_DIR, (filePath) => filePath.endsWith(".json")).map(
    (filePath) => {
      const batch = JSON.parse(read(filePath));
      return { ...batch, filePath: relative(filePath) };
    },
  );
}

function loadProductAuthorityCrosswalk() {
  if (!fs.existsSync(PRODUCT_AUTHORITY_CROSSWALK_PATH)) {
    throw new Error(
      `Missing product authority crosswalk: ${relative(PRODUCT_AUTHORITY_CROSSWALK_PATH)}`,
    );
  }
  return JSON.parse(read(PRODUCT_AUTHORITY_CROSSWALK_PATH));
}

function validateProductAuthorityCrosswalk(manifest, batches, crosswalk) {
  const errors = [];
  if (crosswalk.schemaVersion !== 1) {
    errors.push("product authority crosswalk schemaVersion must be 1");
  }
  if (!crosswalk.rule?.trim()) {
    errors.push("product authority crosswalk lacks its precedence rule");
  }

  const canonicalTargetSpecs = crosswalk.canonicalTargetSpecs;
  if (!Array.isArray(canonicalTargetSpecs) || canonicalTargetSpecs.length === 0) {
    errors.push("product authority crosswalk canonicalTargetSpecs must not be empty");
  }
  const canonicalSet = new Set(canonicalTargetSpecs ?? []);
  if (canonicalSet.size !== (canonicalTargetSpecs ?? []).length) {
    errors.push("product authority crosswalk canonicalTargetSpecs contains duplicates");
  }
  for (const specPath of canonicalSet) {
    if (!fs.existsSync(path.join(ROOT, specPath))) {
      errors.push(`canonical target spec does not exist: ${specPath}`);
    }
  }

  const entries = crosswalk.batches;
  if (!entries || typeof entries !== "object" || Array.isArray(entries)) {
    errors.push("product authority crosswalk batches must be an object");
    return errors;
  }

  const knownBatchIds = new Set(batches.map((batch) => batch.batchId));
  for (const batchId of Object.keys(entries)) {
    if (!knownBatchIds.has(batchId)) {
      errors.push(`product authority crosswalk references unknown batch ${batchId}`);
    }
  }

  for (const batch of batches) {
    const entry = entries[batch.batchId];
    if (!entry) {
      errors.push(`product authority crosswalk lacks batch ${batch.batchId}`);
      continue;
    }
    if (!allowedAuthorityScopes.has(entry.scope)) {
      errors.push(`${batch.batchId}: invalid product authority scope ${entry.scope}`);
    }
    if (!entry.rationale?.trim()) {
      errors.push(`${batch.batchId}: product authority rationale is empty`);
    }
    if (!Array.isArray(entry.authorities) || entry.authorities.length === 0) {
      errors.push(`${batch.batchId}: authorities must not be empty`);
      continue;
    }

    const seenPaths = new Set();
    let hasCanonicalTarget = false;
    let hasTechnicalAuthority = false;
    for (const authority of entry.authorities) {
      if (!authority?.path || typeof authority.path !== "string") {
        errors.push(`${batch.batchId}: authority path is missing`);
        continue;
      }
      if (seenPaths.has(authority.path)) {
        errors.push(`${batch.batchId}: duplicate authority path ${authority.path}`);
      }
      seenPaths.add(authority.path);
      if (!allowedAuthorityRoles.has(authority.role)) {
        errors.push(
          `${batch.batchId}: invalid authority role ${authority.role} for ${authority.path}`,
        );
      }
      if (!fs.existsSync(path.join(ROOT, authority.path))) {
        errors.push(`${batch.batchId}: authority does not exist: ${authority.path}`);
      }
      if (authority.role === "canonical_target") {
        hasCanonicalTarget = true;
        if (!canonicalSet.has(authority.path)) {
          errors.push(
            `${batch.batchId}: canonical_target is absent from canonicalTargetSpecs: ${authority.path}`,
          );
        }
      }
      if (
        authority.role === "architecture_authority" ||
        authority.role === "conversion_control"
      ) {
        hasTechnicalAuthority = true;
      }
    }
    if (entry.scope === "product" && !hasCanonicalTarget) {
      errors.push(`${batch.batchId}: product scope lacks a canonical target spec`);
    }
    if (entry.scope === "technical_control" && !hasTechnicalAuthority) {
      errors.push(`${batch.batchId}: technical-control scope lacks technical authority`);
    }
  }

  const usedCanonicalSpecs = new Set(
    Object.values(entries)
      .flatMap((entry) => entry.authorities ?? [])
      .filter((authority) => authority.role === "canonical_target")
      .map((authority) => authority.path),
  );
  for (const specPath of canonicalSet) {
    if (!usedCanonicalSpecs.has(specPath)) {
      errors.push(`canonical target spec is not assigned to any batch: ${specPath}`);
    }
  }

  for (const surface of manifest.surfaces ?? []) {
    if (!surface.classificationBatch) {
      errors.push(`${surface.id}: lacks classificationBatch for product authority`);
    } else if (!entries[surface.classificationBatch]) {
      errors.push(
        `${surface.id}: classification batch ${surface.classificationBatch} lacks product authority`,
      );
    }
  }
  return errors;
}

function buildProductAuthorityAudit(manifest, batches, crosswalk) {
  const surfacesByBatch = new Map();
  for (const surface of manifest.surfaces) {
    const group = surfacesByBatch.get(surface.classificationBatch) ?? [];
    group.push(surface);
    surfacesByBatch.set(surface.classificationBatch, group);
  }

  const batchRows = batches
    .map((batch) => {
      const entry = crosswalk.batches[batch.batchId];
      const surfaces = surfacesByBatch.get(batch.batchId) ?? [];
      return {
        batchId: batch.batchId,
        title: batch.title,
        scope: entry?.scope ?? "missing",
        rationale: entry?.rationale ?? "",
        surfaceCount: surfaces.length,
        targetRelevantSurfaceCount: surfaces.filter((surface) =>
          targetRequiredDispositions.has(surface.disposition),
        ).length,
        authorities: entry?.authorities ?? [],
        surfaceIds: surfaces.map((surface) => surface.id).sort(),
      };
    })
    .sort((a, b) => a.batchId.localeCompare(b.batchId));

  const canonicalCoverage = crosswalk.canonicalTargetSpecs.map((specPath) => {
    const matchingBatches = batchRows.filter((batch) =>
      batch.authorities.some(
        (authority) =>
          authority.role === "canonical_target" && authority.path === specPath,
      ),
    );
    return {
      path: specPath,
      batchIds: matchingBatches.map((batch) => batch.batchId),
      surfaceCount: matchingBatches.reduce(
        (sum, batch) => sum + batch.surfaceCount,
        0,
      ),
      targetRelevantSurfaceCount: matchingBatches.reduce(
        (sum, batch) => sum + batch.targetRelevantSurfaceCount,
        0,
      ),
    };
  });

  const audit = {
    schemaVersion: 1,
    generatedFromManifestSync: manifest.discovery.lastSynchronizedAt,
    rule: crosswalk.rule,
    totals: {
      surfaces: manifest.surfaces.length,
      targetRelevantSurfaces: manifest.surfaces.filter((surface) =>
        targetRequiredDispositions.has(surface.disposition),
      ).length,
      batches: batchRows.length,
      productScopeSurfaces: batchRows
        .filter((batch) => batch.scope === "product")
        .reduce((sum, batch) => sum + batch.surfaceCount, 0),
      technicalControlSurfaces: batchRows
        .filter((batch) => batch.scope === "technical_control")
        .reduce((sum, batch) => sum + batch.surfaceCount, 0),
    },
    canonicalTargetCoverage: canonicalCoverage,
    batches: batchRows,
  };

  const displayName = (filePath) => path.basename(filePath, path.extname(filePath));
  const markdown = [
    "# Product Authority to Conversion Surface Audit",
    "",
    "> Generated by `node scripts/supabase-conversion-ledger.mjs report`.",
    "> Do not edit this file manually; edit `product-authority-crosswalk.json`.",
    "",
    `Manifest synchronization: ${audit.generatedFromManifestSync}`,
    "",
    "## Result",
    "",
    `${audit.totals.surfaces} of ${audit.totals.surfaces} conversion surfaces resolve through ${audit.totals.batches} reviewed classification batches to an explicit product or technical authority set. ${audit.totals.targetRelevantSurfaces} surfaces are target-relevant. Product authority remains the canonical specs plus confirmed decision-log entries; current and historical specs cannot define redesigned target behavior.`,
    "",
    markdownTable([
      ["Authority scope", "Surfaces"],
      ["---", "---:"],
      ["Product-governed", String(audit.totals.productScopeSurfaces)],
      ["Technical/control", String(audit.totals.technicalControlSurfaces)],
      ["Total", String(audit.totals.surfaces)],
    ]),
    "",
    "## Canonical Target-Spec Coverage",
    "",
    markdownTable([
      ["Canonical target spec", "Batches", "Surfaces", "Target-relevant"],
      ["---", "---:", "---:", "---:"],
      ...canonicalCoverage.map((coverage) => [
        `\`${coverage.path}\``,
        String(coverage.batchIds.length),
        String(coverage.surfaceCount),
        String(coverage.targetRelevantSurfaceCount),
      ]),
    ]),
    "",
    "A surface can be governed by more than one target spec, so canonical-spec counts overlap.",
    "",
    "## Batch Crosswalk",
    "",
    markdownTable([
      [
        "Classification batch",
        "Scope",
        "Surfaces",
        "Target-relevant",
        "Canonical target specs",
        "Other authorities",
      ],
      ["---", "---", "---:", "---:", "---", "---"],
      ...batchRows.map((batch) => [
        `\`${batch.batchId}\``,
        batch.scope,
        String(batch.surfaceCount),
        String(batch.targetRelevantSurfaceCount),
        batch.authorities
          .filter((authority) => authority.role === "canonical_target")
          .map((authority) => `\`${displayName(authority.path)}\``)
          .join(", ") || "n/a",
        batch.authorities
          .filter((authority) => authority.role !== "canonical_target")
          .map((authority) => `\`${displayName(authority.path)}\` (${authority.role})`)
          .join(", "),
      ]),
    ]),
    "",
    "The generated JSON companion records every stable surface ID under its batch. The exact target owner, commands/queries/schema, security, Sync, migration, verification, and unresolved blocker remain in `conversion-manifest.json`.",
    "",
  ].join("\n");

  return {
    json: `${JSON.stringify(audit, null, 2)}\n`,
    markdown,
  };
}

function productAuthorityArtifactErrors(artifacts) {
  const errors = [];
  const expected = [
    [PRODUCT_AUTHORITY_AUDIT_JSON_PATH, artifacts.json],
    [PRODUCT_AUTHORITY_AUDIT_MARKDOWN_PATH, artifacts.markdown],
  ];
  for (const [filePath, content] of expected) {
    if (!fs.existsSync(filePath)) {
      errors.push(`missing generated product authority audit: ${relative(filePath)}`);
    } else if (read(filePath) !== content) {
      errors.push(`stale generated product authority audit: ${relative(filePath)}`);
    }
  }
  return errors;
}

function writeProductAuthorityArtifacts(artifacts) {
  fs.writeFileSync(PRODUCT_AUTHORITY_AUDIT_JSON_PATH, artifacts.json);
  fs.writeFileSync(PRODUCT_AUTHORITY_AUDIT_MARKDOWN_PATH, artifacts.markdown);
}

function loadImplementationSlices() {
  return walk(
    IMPLEMENTATION_SLICE_DIR,
    (filePath) =>
      filePath.endsWith(".json") && !path.basename(filePath).startsWith("_"),
  ).map((filePath) => ({
    ...JSON.parse(read(filePath)),
    filePath: relative(filePath),
  }));
}

function markdownHeadings(filePath) {
  if (!fs.existsSync(filePath)) return new Set();
  return new Set(
    read(filePath)
      .split("\n")
      .map((line) => line.match(/^#{1,6}\s+(.+?)\s*#*\s*$/)?.[1]?.trim())
      .filter(Boolean),
  );
}

function sliceStatusRank(status) {
  return {
    draft: 0,
    ready: 1,
    in_progress: 1,
    implemented: 2,
    verified: 3,
    rehearsed: 4,
    cutover_ready: 5,
  }[status] ?? -1;
}

function manifestImplementationRank(status) {
  return {
    discovered: 0,
    characterized: 0,
    blocked: 0,
    target_mapped: 1,
    implemented: 2,
    verified: 3,
    rehearsed: 4,
    cutover_ready: 5,
    retired: 5,
  }[status] ?? -1;
}

function contractHasItems(contract) {
  return Array.isArray(contract?.items) && contract.items.length > 0;
}

function validateImplementationSlices(manifest, crosswalk, slices) {
  const errors = [];
  const manifestById = new Map(
    manifest.surfaces.map((surface) => [surface.id, surface]),
  );
  const claimedSurfaceToSlice = new Map();
  const sliceIds = new Set();
  const decisionCorpus = [
    path.join(ROOT, "docs/plans/ledger-accounting-redesign/decision-log.md"),
    path.join(ROOT, "docs/architecture/redesign/architecture-decisions.md"),
    path.join(ROOT, "docs/architecture/redesign/product-decision-traceability.md"),
  ]
    .filter((filePath) => fs.existsSync(filePath))
    .map(read)
    .join("\n");

  for (const slice of slices) {
    const prefix = slice.filePath ?? slice.sliceId ?? "implementation slice";
    if (slice.schemaVersion !== 1) {
      errors.push(`${prefix}: schemaVersion must be 1`);
    }
    if (!slice.sliceId || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slice.sliceId)) {
      errors.push(`${prefix}: sliceId must be lower-kebab-case`);
    } else {
      if (sliceIds.has(slice.sliceId)) {
        errors.push(`${prefix}: duplicate sliceId ${slice.sliceId}`);
      }
      sliceIds.add(slice.sliceId);
      if (path.basename(slice.filePath, ".json") !== slice.sliceId) {
        errors.push(`${prefix}: filename must equal sliceId`);
      }
    }
    if (!slice.title?.trim()) errors.push(`${prefix}: title is empty`);
    if (!slice.owner?.trim()) errors.push(`${prefix}: owner is empty`);
    if (!allowedSliceKinds.has(slice.kind)) {
      errors.push(`${prefix}: invalid kind ${slice.kind}`);
    }
    if (!allowedSliceStatuses.has(slice.status)) {
      errors.push(`${prefix}: invalid status ${slice.status}`);
    }
    if (!Array.isArray(slice.surfaceIds) || slice.surfaceIds.length === 0) {
      errors.push(`${prefix}: surfaceIds must not be empty`);
    }

    const claimedSurfaces = [];
    const localSurfaceIds = new Set();
    for (const surfaceId of slice.surfaceIds ?? []) {
      if (localSurfaceIds.has(surfaceId)) {
        errors.push(`${prefix}: duplicate surfaceId ${surfaceId}`);
        continue;
      }
      localSurfaceIds.add(surfaceId);
      const surface = manifestById.get(surfaceId);
      if (!surface) {
        errors.push(`${prefix}: unknown surfaceId ${surfaceId}`);
        continue;
      }
      if (!targetRequiredDispositions.has(surface.disposition)) {
        errors.push(
          `${prefix}: ${surfaceId} is not a replace/redesign/migrate target surface`,
        );
      }
      if (claimedSurfaceToSlice.has(surfaceId)) {
        errors.push(
          `${prefix}: ${surfaceId} is already owned by ${claimedSurfaceToSlice.get(surfaceId)}`,
        );
      } else {
        claimedSurfaceToSlice.set(surfaceId, slice.sliceId);
      }
      claimedSurfaces.push(surface);
    }

    const sliceRank = sliceStatusRank(slice.status);
    if (sliceRank >= 1 && (slice.blockers ?? []).length > 0) {
      errors.push(`${prefix}: ${slice.status} slice must not retain blockers`);
    }
    if (!Array.isArray(slice.blockers)) {
      errors.push(`${prefix}: blockers must be an array`);
    }

    const allowedAuthorities = new Set();
    for (const surface of claimedSurfaces) {
      const entry = crosswalk.batches[surface.classificationBatch];
      for (const authority of entry?.authorities ?? []) {
        allowedAuthorities.add(`${authority.role}\u0000${authority.path}`);
      }
      if (sliceRank >= 1 && manifestImplementationRank(surface.status) < 1) {
        errors.push(
          `${prefix}: ready or later slice claims unmapped surface ${surface.id}`,
        );
      }
      if (sliceRank >= 2 && manifestImplementationRank(surface.status) < sliceRank) {
        errors.push(
          `${prefix}: ${slice.status} exceeds manifest status ${surface.status} for ${surface.id}`,
        );
      }
    }

    const requirements = slice.requirements;
    if (sliceRank >= 1 && (!Array.isArray(requirements) || requirements.length === 0)) {
      errors.push(`${prefix}: ready or later slice requires exact requirements`);
    }
    const requirementIds = new Set();
    let hasCanonicalTargetRequirement = false;
    for (const requirement of requirements ?? []) {
      const reqPrefix = `${prefix}: requirement ${requirement?.id ?? "<missing>"}`;
      if (!requirement?.id || !/^[A-Z0-9]+(?:-[A-Z0-9]+)*-REQ-\d{3}$/.test(requirement.id)) {
        errors.push(`${reqPrefix}: id must end in -REQ-NNN`);
      } else if (requirementIds.has(requirement.id)) {
        errors.push(`${reqPrefix}: duplicate requirement id`);
      } else {
        requirementIds.add(requirement.id);
      }
      if (
        !new Set([
          "canonical_target",
          "decision_authority",
          "architecture_authority",
          "conversion_control",
        ]).has(requirement.authorityRole)
      ) {
        errors.push(`${reqPrefix}: invalid implementation authority role`);
      }
      if (requirement.authorityRole === "canonical_target") {
        hasCanonicalTargetRequirement = true;
      }
      if (!requirement.authorityPath?.trim()) {
        errors.push(`${reqPrefix}: authorityPath is empty`);
      } else {
        const authorityFile = path.join(ROOT, requirement.authorityPath);
        if (!fs.existsSync(authorityFile)) {
          errors.push(`${reqPrefix}: authority file does not exist`);
        } else if (
          !requirement.section?.trim() ||
          !markdownHeadings(authorityFile).has(requirement.section)
        ) {
          errors.push(
            `${reqPrefix}: exact Markdown section does not exist: ${requirement.section}`,
          );
        }
        if (
          !allowedAuthorities.has(
            `${requirement.authorityRole}\u0000${requirement.authorityPath}`,
          )
        ) {
          errors.push(
            `${reqPrefix}: authority is not in the claimed surfaces' reviewed crosswalk`,
          );
        }
      }
      if (!requirement.invariant?.trim()) {
        errors.push(`${reqPrefix}: invariant is empty`);
      }
      if (!Array.isArray(requirement.decisionIds)) {
        errors.push(`${reqPrefix}: decisionIds must be an array`);
      }
      for (const decisionId of requirement.decisionIds ?? []) {
        if (!/^[ADO]-\d{3}$/.test(decisionId) || !decisionCorpus.includes(decisionId)) {
          errors.push(`${reqPrefix}: unknown decision ID ${decisionId}`);
        }
      }
      if (
        !Array.isArray(requirement.verificationIds) ||
        requirement.verificationIds.length === 0
      ) {
        errors.push(`${reqPrefix}: verificationIds must not be empty`);
      }
    }
    if (sliceRank >= 1 && slice.kind === "product" && !hasCanonicalTargetRequirement) {
      errors.push(`${prefix}: product slice lacks a canonical-target requirement`);
    }

    const applicableContracts = new Set();
    if (sliceRank >= 1 && (!slice.contracts || typeof slice.contracts !== "object")) {
      errors.push(`${prefix}: ready or later slice requires contracts`);
    }
    for (const key of requiredSliceContractKeys) {
      const contract = slice.contracts?.[key];
      if (sliceRank < 1 && !contract) continue;
      if (!contract || typeof contract !== "object") {
        errors.push(`${prefix}: missing contract category ${key}`);
        continue;
      }
      const hasItems = contractHasItems(contract);
      const hasReason = Boolean(contract.notApplicable?.trim());
      if (hasItems === hasReason) {
        errors.push(
          `${prefix}: ${key} must contain items or one notApplicable reason, never both/neither`,
        );
      }
      if (hasItems) {
        applicableContracts.add(key);
        for (const item of contract.items) {
          if (typeof item !== "string" || !item.trim()) {
            errors.push(`${prefix}: ${key} contains an empty contract item`);
          }
        }
      }
    }

    const verificationById = new Map();
    if (
      sliceRank >= 1 &&
      (!Array.isArray(slice.verification) || slice.verification.length === 0)
    ) {
      errors.push(`${prefix}: ready or later slice requires verification obligations`);
    }
    for (const verification of slice.verification ?? []) {
      const testPrefix = `${prefix}: verification ${verification?.id ?? "<missing>"}`;
      if (!verification?.id || !/^[A-Z0-9]+(?:-[A-Z0-9]+)*-TEST-\d{3}$/.test(verification.id)) {
        errors.push(`${testPrefix}: id must end in -TEST-NNN`);
      } else if (verificationById.has(verification.id)) {
        errors.push(`${testPrefix}: duplicate verification id`);
      } else {
        verificationById.set(verification.id, verification);
      }
      if (!allowedVerificationKinds.has(verification.kind)) {
        errors.push(`${testPrefix}: invalid kind ${verification.kind}`);
      }
      if (!verification.owner?.trim()) errors.push(`${testPrefix}: owner is empty`);
      if (!verification.expected?.trim()) errors.push(`${testPrefix}: expected is empty`);
      if (!allowedVerificationStatuses.has(verification.status)) {
        errors.push(`${testPrefix}: invalid status ${verification.status}`);
      }
      if (!Array.isArray(verification.covers) || verification.covers.length === 0) {
        errors.push(`${testPrefix}: covers must not be empty`);
      }
      for (const requirementId of verification.covers ?? []) {
        if (!requirementIds.has(requirementId)) {
          errors.push(`${testPrefix}: covers unknown requirement ${requirementId}`);
        }
      }
      if (!Array.isArray(verification.evidence)) {
        errors.push(`${testPrefix}: evidence must be an array`);
      }
      if (sliceRank >= 3) {
        if (verification.status !== "passed") {
          errors.push(`${testPrefix}: verified slice requires passed status`);
        }
        if (!Array.isArray(verification.evidence) || verification.evidence.length === 0) {
          errors.push(`${testPrefix}: verified slice requires durable evidence`);
        }
      }
    }

    for (const requirement of requirements ?? []) {
      for (const verificationId of requirement.verificationIds ?? []) {
        const verification = verificationById.get(verificationId);
        if (!verification) {
          errors.push(
            `${prefix}: requirement ${requirement.id} references unknown verification ${verificationId}`,
          );
        } else if (!(verification.covers ?? []).includes(requirement.id)) {
          errors.push(
            `${prefix}: verification ${verificationId} does not cover reciprocal requirement ${requirement.id}`,
          );
        }
      }
    }

    const requiredKinds = new Set();
    const requireKinds = (...kinds) => kinds.forEach((kind) => requiredKinds.add(kind));
    if (applicableContracts.has("domain")) requireKinds("domain");
    if (applicableContracts.has("postgresSchema")) {
      requireKinds("database_invariant", "advisor");
    }
    if (applicableContracts.has("serverHandlers")) requireKinds("handler_idempotency");
    if (
      applicableContracts.has("dataApiGrants") ||
      applicableContracts.has("rlsPolicies")
    ) {
      requireKinds("rls_positive", "rls_negative");
    }
    if (applicableContracts.has("syncStreams")) requireKinds("sync_authorization");
    if (applicableContracts.has("localOffline")) {
      requireKinds("offline_restart", "offline_rejection");
    }
    if (applicableContracts.has("storageMedia")) requireKinds("media_fault");
    if (applicableContracts.has("appMcp")) requireKinds("app_mcp_contract");
    if (applicableContracts.has("migrationReconciliation")) {
      requireKinds("migration", "reconciliation");
    }
    if (applicableContracts.has("observabilityRunbooks")) requireKinds("operational");
    if (slice.kind === "product") requireKinds("end_to_end");
    const actualKinds = new Set(
      [...verificationById.values()].map((verification) => verification.kind),
    );
    if (sliceRank >= 1) {
      for (const kind of requiredKinds) {
        if (!actualKinds.has(kind)) {
          errors.push(`${prefix}: applicable contracts require ${kind} verification`);
        }
      }
    }

    if (!Array.isArray(slice.implementationEvidence)) {
      errors.push(`${prefix}: implementationEvidence must be an array`);
    }
    if (sliceRank >= 2 && (slice.implementationEvidence ?? []).length === 0) {
      errors.push(`${prefix}: implemented or later slice requires implementationEvidence`);
    }
    if (!Array.isArray(slice.rehearsalEvidence)) {
      errors.push(`${prefix}: rehearsalEvidence must be an array`);
    }
    if (sliceRank >= 4 && (slice.rehearsalEvidence ?? []).length === 0) {
      errors.push(`${prefix}: rehearsed or later slice requires rehearsalEvidence`);
    }
  }

  for (const surface of manifest.surfaces) {
    if (
      targetRequiredDispositions.has(surface.disposition) &&
      implementationSurfaceStatuses.has(surface.status)
    ) {
      const sliceId = claimedSurfaceToSlice.get(surface.id);
      if (!sliceId) {
        errors.push(
          `${surface.id}: ${surface.status} target surface lacks an implementation slice`,
        );
        continue;
      }
      const slice = slices.find((candidate) => candidate.sliceId === sliceId);
      if (sliceStatusRank(slice.status) < manifestImplementationRank(surface.status)) {
        errors.push(
          `${surface.id}: manifest status ${surface.status} exceeds slice ${sliceId} status ${slice.status}`,
        );
      }
    }
  }

  return errors;
}

function buildImplementationSliceAudit(manifest, slices) {
  const targetSurfaces = manifest.surfaces.filter((surface) =>
    targetRequiredDispositions.has(surface.disposition),
  );
  const claimedIds = new Set(slices.flatMap((slice) => slice.surfaceIds ?? []));
  const rows = slices
    .map((slice) => ({
      sliceId: slice.sliceId,
      title: slice.title,
      kind: slice.kind,
      status: slice.status,
      owner: slice.owner,
      surfaceIds: [...(slice.surfaceIds ?? [])].sort(),
      requirementCount: (slice.requirements ?? []).length,
      verificationCount: (slice.verification ?? []).length,
      blockerCount: (slice.blockers ?? []).length,
      filePath: slice.filePath,
    }))
    .sort((a, b) => a.sliceId.localeCompare(b.sliceId));
  const statusCounts = Object.fromEntries(
    [...allowedSliceStatuses].map((status) => [
      status,
      rows.filter((row) => row.status === status).length,
    ]),
  );
  const audit = {
    schemaVersion: 1,
    generatedFromManifestSync: manifest.discovery.lastSynchronizedAt,
    totals: {
      slices: rows.length,
      claimedTargetSurfaces: targetSurfaces.filter((surface) =>
        claimedIds.has(surface.id),
      ).length,
      unclaimedTargetSurfaces: targetSurfaces.filter(
        (surface) => !claimedIds.has(surface.id),
      ).length,
      implementationAdvancedTargetSurfaces: targetSurfaces.filter((surface) =>
        implementationSurfaceStatuses.has(surface.status),
      ).length,
    },
    statusCounts,
    slices: rows,
  };
  const markdownRows = rows.length
    ? rows.map((row) => [
        `\`${row.sliceId}\``,
        row.kind,
        row.status,
        String(row.surfaceIds.length),
        String(row.requirementCount),
        String(row.verificationCount),
        String(row.blockerCount),
      ])
    : [["_none yet_", "—", "—", "0", "0", "0", "0"]];
  const markdown = [
    "# Vertical Slice Implementation Audit",
    "",
    "> Generated by `node scripts/supabase-conversion-ledger.mjs report`.",
    "> Do not edit this file manually; edit `implementation-slices/*.json`.",
    "",
    `Manifest synchronization: ${audit.generatedFromManifestSync}`,
    "",
    "## Result",
    "",
    `${audit.totals.slices} implementation slices currently claim ${audit.totals.claimedTargetSurfaces} of ${targetSurfaces.length} target-relevant surfaces. ${audit.totals.implementationAdvancedTargetSurfaces} target surfaces have advanced to implemented or later. Unclaimed target-mapped surfaces are expected until their bounded slice begins; an implemented or later surface without exactly one corresponding slice fails conversion checking.`,
    "",
    markdownTable([
      ["Metric", "Count"],
      ["---", "---:"],
      ["Slices", String(audit.totals.slices)],
      ["Claimed target surfaces", String(audit.totals.claimedTargetSurfaces)],
      ["Unclaimed target surfaces", String(audit.totals.unclaimedTargetSurfaces)],
      [
        "Implemented-or-later target surfaces",
        String(audit.totals.implementationAdvancedTargetSurfaces),
      ],
    ]),
    "",
    "## Slice Register",
    "",
    markdownTable([
      [
        "Slice",
        "Kind",
        "Status",
        "Surfaces",
        "Requirements",
        "Verifications",
        "Blockers",
      ],
      ["---", "---", "---", "---:", "---:", "---:", "---:"],
      ...markdownRows,
    ]),
    "",
    "See `vertical-slice-implementation-method.md` for the required lifecycle, contract map, verification obligations, evidence, and reviewer stop conditions.",
    "",
  ].join("\n");
  return {
    json: `${JSON.stringify(audit, null, 2)}\n`,
    markdown,
  };
}

function implementationSliceArtifactErrors(artifacts) {
  const errors = [];
  for (const [filePath, content] of [
    [IMPLEMENTATION_SLICE_AUDIT_JSON_PATH, artifacts.json],
    [IMPLEMENTATION_SLICE_AUDIT_MARKDOWN_PATH, artifacts.markdown],
  ]) {
    if (!fs.existsSync(filePath)) {
      errors.push(`missing generated implementation-slice audit: ${relative(filePath)}`);
    } else if (read(filePath) !== content) {
      errors.push(`stale generated implementation-slice audit: ${relative(filePath)}`);
    }
  }
  return errors;
}

function writeImplementationSliceArtifacts(artifacts) {
  fs.writeFileSync(IMPLEMENTATION_SLICE_AUDIT_JSON_PATH, artifacts.json);
  fs.writeFileSync(IMPLEMENTATION_SLICE_AUDIT_MARKDOWN_PATH, artifacts.markdown);
}

function applyClassificationBatches(manifest, batches) {
  const errors = [];
  const surfacesById = new Map(manifest.surfaces.map((surface) => [surface.id, surface]));
  const batchIds = new Set();
  const patchedIds = new Set();

  for (const batch of batches) {
    if (!batch.batchId || typeof batch.batchId !== "string") {
      errors.push(`${batch.filePath}: missing batchId`);
      continue;
    }
    if (batchIds.has(batch.batchId)) {
      errors.push(`${batch.filePath}: duplicate batchId ${batch.batchId}`);
    }
    batchIds.add(batch.batchId);
    if (!Array.isArray(batch.surfaces)) {
      errors.push(`${batch.filePath}: surfaces must be an array`);
      continue;
    }

    for (const patch of batch.surfaces) {
      if (!patch.id || typeof patch.id !== "string") {
        errors.push(`${batch.filePath}: surface patch missing id`);
        continue;
      }
      if (patchedIds.has(patch.id)) {
        errors.push(`${patch.id}: classified by more than one batch`);
        continue;
      }
      patchedIds.add(patch.id);
      const surface = surfacesById.get(patch.id);
      if (!surface) {
        errors.push(`${batch.filePath}: unknown surface ${patch.id}`);
        continue;
      }
      const {
        id: _id,
        acknowledgeCurrentSource,
        acknowledgeSourceHash,
        ...fields
      } = patch;
      Object.assign(surface, fields, { classificationBatch: batch.batchId });
      if (acknowledgeSourceHash !== undefined) {
        if (surface.discovery !== "automatic") {
          errors.push(`${patch.id}: acknowledgeSourceHash is valid only for automatic surfaces`);
        } else if (acknowledgeSourceHash !== surface.observedSourceHash) {
          errors.push(
            `${patch.id}: requested source acknowledgment ${acknowledgeSourceHash} does not match observed ${surface.observedSourceHash}`,
          );
        } else {
          surface.acknowledgedSourceHash = acknowledgeSourceHash;
        }
      } else if (
        acknowledgeCurrentSource === true &&
        surface.discovery === "automatic" &&
        !surface.acknowledgedSourceHash
      ) {
        surface.acknowledgedSourceHash = surface.observedSourceHash;
      }
    }
  }
  return errors;
}

function discoverSwiftApplication() {
  const directories = [
    path.join(ROOT, "LedgeriOS/LedgeriOS"),
    path.join(ROOT, "LedgeriOS/LedgerTargetApp"),
    path.join(ROOT, "LedgeriOS/LedgerTargetAppModel"),
    path.join(ROOT, "LedgeriOS/LedgerTargetCore"),
    path.join(ROOT, "LedgeriOS/LedgerTargetComposition"),
    path.join(ROOT, "LedgeriOS/LedgerTargetMigrationCore"),
    path.join(ROOT, "LedgeriOS/LedgerTargetPowerSync"),
    path.join(ROOT, "LedgeriOS/LedgerTargetTestSupport"),
  ];
  return directories.flatMap((directory) =>
    walk(directory, (filePath) => filePath.endsWith(".swift")),
  ).map(
    (filePath) => {
      const rel = relative(filePath);
      const text = read(filePath);
      const directFirebaseImport = /^\s*(?:@preconcurrency\s+)?import\s+Firebase/m.test(text);
      const firebaseApiReference = /Firestore|FirebaseAuth|FirebaseStorage|FirebaseFunctions|StorageReference|DocumentSnapshot|QuerySnapshot|ListenerRegistration|WriteBatch|FieldValue|Timestamp/.test(
        text,
      );
      return makeSurface({
        id: stableId("SWIFT", rel),
        kind: swiftKind(filePath),
        name: rel,
        sourceRefs: [{ path: rel }],
        sourceHash: sha(text),
        metadata: {
          firebaseCoupling: directFirebaseImport
            ? "direct_import"
            : firebaseApiReference
              ? "api_reference"
              : "none_detected",
        },
      });
    },
  );
}

function discoverSwiftTests() {
  const directories = [
    path.join(ROOT, "LedgeriOS/LedgeriOSTests"),
    path.join(ROOT, "LedgeriOS/LedgerTargetCoreTests"),
    path.join(ROOT, "LedgeriOS/LedgerTargetAppModelTests"),
    path.join(ROOT, "LedgeriOS/LedgerTargetCompositionTests"),
    path.join(ROOT, "LedgeriOS/LedgerTargetMigrationCoreTests"),
    path.join(ROOT, "LedgeriOS/LedgerTargetPowerSyncTests"),
    path.join(ROOT, "LedgeriOS/LedgerTargetTestSupportTests"),
  ];
  return directories.flatMap((directory) =>
    walk(directory, (filePath) => filePath.endsWith(".swift")),
  ).map(
    (filePath) => {
      const rel = relative(filePath);
      const text = read(filePath);
      return makeSurface({
        id: stableId("TEST", rel),
        kind: "existing_test_evidence",
        name: rel,
        sourceRefs: [{ path: rel }],
        sourceHash: sha(text),
        metadata: {
          firebaseCoupled: /Firebase|Firestore|StorageReference|Timestamp/.test(text),
        },
      });
    },
  );
}

function discoverFirestoreRules() {
  const filePath = path.join(ROOT, "firebase/firestore.rules");
  if (!fs.existsSync(filePath)) return [];
  const rel = relative(filePath);
  const text = read(filePath);
  const lines = text.split("\n");
  const surfaces = [];
  lines.forEach((line, index) => {
    const trimmed = line.trim();
    if (!trimmed.startsWith("match /")) return;
    const suffix = trimmed.slice("match ".length);
    const end = suffix.lastIndexOf(" {");
    const matchPath = end >= 0 ? suffix.slice(0, end) : suffix;
    surfaces.push(
      makeSurface({
        id: stableId("RULE", matchPath),
        kind: "firestore_rule_surface",
        name: matchPath,
        sourceRefs: [{ path: rel, line: index + 1 }],
        // A rule's behavior is defined by its body and shared helper functions,
        // not only by the match declaration. Conservatively invalidate every
        // rule characterization when the ruleset changes.
        sourceHash: sha(`${matchPath}\n${text}`),
      }),
    );
  });
  return surfaces;
}

function discoverCloudFunctionModules() {
  const directory = path.join(ROOT, "firebase/functions/src");
  return walk(directory, (filePath) => filePath.endsWith(".ts")).map(
    (filePath) => {
      const rel = relative(filePath);
      const text = read(filePath);
      return makeSurface({
        id: stableId("FUNCMOD", rel),
        kind: "firebase_function_module",
        name: rel,
        sourceRefs: [{ path: rel }],
        sourceHash: sha(text),
      });
    },
  );
}

function discoverCloudFunctions() {
  const filePath = path.join(ROOT, "firebase/functions/src/index.ts");
  if (!fs.existsSync(filePath)) return [];
  const rel = relative(filePath);
  const text = read(filePath);
  const surfaces = [];
  const regex = /^export const\s+([A-Za-z0-9_]+)\s*=/gm;
  for (const match of text.matchAll(regex)) {
    surfaces.push(
      makeSurface({
        id: stableId("FUNCTION", match[1]),
        kind: "firebase_cloud_function",
        name: match[1],
        sourceRefs: [{ path: rel, line: lineNumber(text, match.index) }],
        sourceHash: sha(text),
      }),
    );
  }
  return surfaces;
}

function discoverMcp() {
  const directories = [
    path.join(ROOT, "mcp-server/src"),
    path.join(ROOT, "LedgerTargetMCP"),
  ];
  const files = directories.flatMap((directory) =>
    walk(directory, (filePath) => filePath.endsWith(".ts")),
  );
  const surfaces = [];
  for (const filePath of files) {
    const rel = relative(filePath);
    const text = read(filePath);
    surfaces.push(
      makeSurface({
        id: stableId("MCPMOD", rel),
        kind: "mcp_module",
        name: rel,
        sourceRefs: [{ path: rel }],
        sourceHash: sha(text),
        metadata: {
          firebaseCoupled: /Firestore|firebase-admin|\.\/firebase/.test(text),
        },
      }),
    );

    for (const match of text.matchAll(/server\.tool\(\s*["']([^"']+)["']/gm)) {
      surfaces.push(
        makeSurface({
          id: stableId("MCPTOOL", match[1]),
          kind: "mcp_tool",
          name: match[1],
          sourceRefs: [{ path: rel, line: lineNumber(text, match.index) }],
          sourceHash: sha(text),
        }),
      );
    }
    for (const match of text.matchAll(/server\.resource\(\s*["']([^"']+)["']/gm)) {
      surfaces.push(
        makeSurface({
          id: stableId("MCPRESOURCE", match[1]),
          kind: "mcp_resource",
          name: match[1],
          sourceRefs: [{ path: rel, line: lineNumber(text, match.index) }],
          sourceHash: sha(text),
        }),
      );
    }
  }
  return surfaces;
}

function discoverTooling() {
  const surfaces = [];
  const groups = [
    {
      directory: path.join(ROOT, "migration/src"),
      kind: "firebase_migration_tool",
      predicate: (filePath) => filePath.endsWith(".ts"),
    },
    {
      directory: path.join(ROOT, "scripts"),
      kind: "firebase_audit_repair_script",
      predicate: (filePath) =>
        /\.(mjs|js|ts|sh)$/.test(filePath) &&
        !new Set([
          "scripts/generate-source-query-reconciliation.mjs",
          "scripts/generate-target-query-logical-authority-crosswalk.mjs",
          "scripts/generate-target-query-port-inventory.mjs",
          "scripts/tests/generate-source-query-reconciliation.test.mjs",
          "scripts/tests/generate-target-query-logical-authority-crosswalk.test.mjs",
          "scripts/tests/generate-target-query-port-inventory.test.mjs",
        ]).has(relative(filePath)),
      contentPredicate: (text) =>
        /firebase-admin|Firestore|firestore|FIREBASE_PROJECT|ledger-nine4/.test(text),
    },
    {
      directory: path.join(ROOT, "firebase"),
      kind: "firebase_configuration_or_test",
      predicate: (filePath) =>
        !filePath.includes("/functions/src/") &&
        !filePath.includes("/functions/node_modules/") &&
        /\.(json|rules|md|mjs|ts)$/.test(filePath),
    },
    {
      directory: path.join(ROOT, "mcp-server/test"),
      kind: "existing_test_evidence",
      predicate: (filePath) => /\.(ts|js|json)$/.test(filePath),
    },
  ];

  for (const group of groups) {
    for (const filePath of walk(group.directory, group.predicate)) {
      const text = read(filePath);
      if (group.contentPredicate && !group.contentPredicate(text)) continue;
      const rel = relative(filePath);
      const isControlTool = rel === "scripts/supabase-conversion-ledger.mjs";
      surfaces.push(
        makeSurface({
          id: stableId("FILE", `${group.kind}:${rel}`),
          kind: isControlTool ? "conversion_control_tool" : group.kind,
          name: rel,
          sourceRefs: [{ path: rel }],
          sourceHash: sha(text),
        }),
      );
    }
  }
  return surfaces;
}

function discoverConfiguration() {
  const candidates = [
    ".firebaserc",
    ".github/workflows/supabase-conversion-control.yml",
    "firebase.json",
    "LedgeriOS/Package.swift",
    "LedgeriOS/Package.resolved",
    "LedgeriOS/LedgerTargetProject.yml",
    "LedgeriOS/LedgerTarget.xcodeproj/project.pbxproj",
    "LedgeriOS/LedgerTarget.xcodeproj/xcshareddata/xcschemes/LedgerTargetStaging.xcscheme",
    "LedgeriOS/LedgeriOS.xcodeproj/project.pbxproj",
    "LedgeriOS/LedgeriOS.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
    "LedgeriOS/LedgeriOS.xcodeproj/xcshareddata/xcschemes/LedgeriOS (Archive).xcscheme",
    "LedgeriOS/LedgeriOS.xcodeproj/xcshareddata/xcschemes/LedgeriOS (Emulator).xcscheme",
    "LedgeriOS/LedgeriOS.xcodeproj/xcshareddata/xcschemes/LedgeriOS.xcscheme",
    "LedgeriOS/LedgeriOS/GoogleService-Info.plist",
    "LedgeriOS/LedgeriOS/Info.plist",
    "LedgeriOS/LedgeriOS/LedgeriOS.entitlements",
    "LedgerTargetContracts/catalog.json",
    "LedgerTargetMCP/package.json",
    "LedgerTargetMCP/package-lock.json",
    "LedgerTargetMCP/tsconfig.json",
    "LedgerTargetMCP/resources/contract-catalog.json",
    "powersync/sync-streams.yaml",
    "supabase/config.toml",
    "supabase/migrations/20260904135741_client_creation_vertical_slice.sql",
    "supabase/migrations/20260904151946_project_setup_vertical_slice.sql",
    "supabase/migrations/20260904181245_client_rename_vertical_slice.sql",
    "supabase/migrations/20260905095803_project_archive_vertical_slice.sql",
    "supabase/migrations/20260905125208_client_archive_vertical_slice.sql",
    "supabase/migrations/20260905164622_space_assignment_destination_picker.sql",
    "supabase/migrations/20260905192135_space_creation_vertical_slice.sql",
    "supabase/migrations/20260905213332_project_note_archival_review.sql",
    "supabase/migrations/20260905234410_space_core_details_read.sql",
    "supabase/migrations/20260906014441_project_category_configuration_revision.sql",
    "supabase/seed.sql",
    "supabase/tests/client_creation_vertical_slice.test.sql",
    "supabase/tests/client_rename_vertical_slice.test.sql",
    "supabase/tests/client_archive_vertical_slice.test.sql",
    "supabase/tests/client_archive_vertical_slice.test.sql.ready",
    "supabase/tests/project_archive_vertical_slice.test.sql",
    "supabase/tests/project_archive_vertical_slice.test.sql.ready",
    "supabase/tests/project_note_archival_review.test.sql",
    "supabase/tests/project_setup_vertical_slice.test.sql",
    "supabase/tests/space_assignment_destination_picker.test.sql",
    "supabase/tests/space_creation_vertical_slice.test.sql",
    "supabase/tests/space_core_details_read.test.sql",
    "supabase/tests/project_category_configuration_revision.test.sql",
    "mcp-server/Dockerfile",
    "mcp-server/package.json",
    "mcp-server/tsconfig.json",
    "migration/package.json",
    "migration/tsconfig.json",
    "package.json",
    "scripts/package.json",
    "scripts/build-macos-dmg.sh",
    "scripts/build-macos-sparkle-update.sh",
    "scripts/build-testflight.sh",
    "scripts/check-target-environment.mjs",
    "scripts/distribute-testflight-external.sh",
    "scripts/generate-source-query-reconciliation.mjs",
    "scripts/generate-target-query-logical-authority-crosswalk.mjs",
    "scripts/generate-target-query-port-inventory.mjs",
    "scripts/test-local-client-creation-rpc.mjs",
    "scripts/test-local-client-rename-rpc.mjs",
    "scripts/test-local-client-archive-rpc.mjs",
    "scripts/test-local-project-archive-rpc.mjs",
    "scripts/test-local-project-creation-rpc.mjs",
    "scripts/test-local-project-note-read.mjs",
    "scripts/test-local-space-assignment-destination-read.mjs",
    "scripts/test-local-space-creation-rpc.mjs",
    "scripts/release-testflight.sh",
    "scripts/tests/generate-source-query-reconciliation.test.mjs",
    "scripts/tests/generate-target-query-logical-authority-crosswalk.test.mjs",
    "scripts/tests/generate-target-query-port-inventory.test.mjs",
  ];
  return candidates.flatMap((rel) => {
    const filePath = path.join(ROOT, rel);
    if (!fs.existsSync(filePath)) return [];
    const text = read(filePath);
    return [
      makeSurface({
        id: stableId("CONFIG", rel),
        kind: rel.startsWith("scripts/")
          ? "release_or_build_tool"
          : "application_or_backend_configuration",
        name: rel,
        sourceRefs: [{ path: rel }],
        sourceHash: sha(text),
      }),
    ];
  });
}

function discoverAll() {
  const discovered = [
    ...discoverSwiftApplication(),
    ...discoverSwiftTests(),
    ...discoverFirestoreRules(),
    ...discoverCloudFunctionModules(),
    ...discoverCloudFunctions(),
    ...discoverMcp(),
    ...discoverTooling(),
    ...discoverConfiguration(),
  ];
  const byId = new Map();
  for (const surface of discovered) {
    const existing = byId.get(surface.id);
    if (existing) {
      throw new Error(
        `Discovery ID collision ${surface.id}: ${existing.name} and ${surface.name}`,
      );
    }
    byId.set(surface.id, surface);
  }
  return [...byId.values()].sort((a, b) => a.id.localeCompare(b.id));
}

function loadManifest() {
  return JSON.parse(read(MANIFEST_PATH));
}

function mergeDiscovery(manifest, discovered) {
  const previousById = new Map(manifest.surfaces.map((surface) => [surface.id, surface]));
  const discoveredIds = new Set(discovered.map((surface) => surface.id));
  const merged = [];

  for (const current of discovered) {
    const previous = previousById.get(current.id);
    if (!previous) {
      merged.push(current);
      continue;
    }
    merged.push({
      ...current,
      ...previous,
      kind: current.kind,
      name: current.name,
      discovery: "automatic",
      sourcePresence: "present",
      sourceRefs: current.sourceRefs,
      observedSourceHash: current.observedSourceHash,
      metadata: { ...previous.metadata, ...current.metadata },
    });
  }

  for (const previous of manifest.surfaces) {
    if (previous.discovery === "manual") {
      merged.push(previous);
    } else if (!discoveredIds.has(previous.id)) {
      merged.push({ ...previous, sourcePresence: "missing" });
    }
  }

  manifest.surfaces = merged.sort((a, b) => a.id.localeCompare(b.id));
  manifest.discovery.lastSynchronizedAt = new Date().toISOString();
  return manifest;
}

function validate(manifest, discovered, initialErrors = []) {
  const errors = [...initialErrors];
  const warnings = [];
  if (manifest.schemaVersion !== 1) errors.push("schemaVersion must be 1");
  if (!Array.isArray(manifest.surfaces)) errors.push("surfaces must be an array");

  const discoveredById = new Map(
    discovered.map((surface) => [surface.id, surface]),
  );
  const discoveredIds = new Set(discoveredById.keys());
  const manifestIds = new Set();
  for (const surface of manifest.surfaces ?? []) {
    if (!surface.id) errors.push("surface missing id");
    if (manifestIds.has(surface.id)) errors.push(`duplicate surface id ${surface.id}`);
    manifestIds.add(surface.id);
    if (!allowedStatuses.has(surface.status)) {
      errors.push(`${surface.id}: invalid status ${surface.status}`);
    }
    if (!allowedDispositions.has(surface.disposition)) {
      errors.push(`${surface.id}: invalid disposition ${surface.disposition}`);
    }
    if (!Array.isArray(surface.sourceRefs) || surface.sourceRefs.length === 0) {
      errors.push(`${surface.id}: sourceRefs must not be empty`);
    }
    if (surface.discovery === "automatic" && surface.sourcePresence === "missing") {
      if (!new Set(["retired", "cutover_ready"]).has(surface.status)) {
        errors.push(`${surface.id}: source disappeared without retirement evidence`);
      }
    }
    const liveSurface = discoveredById.get(surface.id);
    if (
      surface.discovery === "automatic" &&
      liveSurface &&
      surface.observedSourceHash !== liveSurface.observedSourceHash
    ) {
      errors.push(
        `${surface.id}: discovered source hash changed since the manifest was synchronized`,
      );
    }
    if (
      surface.acknowledgedSourceHash &&
      surface.observedSourceHash &&
      surface.acknowledgedSourceHash !== surface.observedSourceHash &&
      !new Set(["discovered", "blocked"]).has(surface.status)
    ) {
      errors.push(`${surface.id}: source changed after characterization`);
    }
    const characterized = !new Set(["discovered", "blocked"]).has(surface.status);
    if (characterized) {
      if (!surface.currentBehavior?.trim()) {
        errors.push(`${surface.id}: characterized surface lacks currentBehavior`);
      }
      if (surface.disposition === "unclassified") {
        errors.push(`${surface.id}: characterized surface is unclassified`);
      }
      if (
        surface.discovery === "automatic" &&
        !surface.acknowledgedSourceHash
      ) {
        errors.push(`${surface.id}: characterized source hash is not acknowledged`);
      }
    }
    const targetMapped = new Set([
      "target_mapped",
      "implemented",
      "verified",
      "rehearsed",
      "cutover_ready",
    ]).has(surface.status);
    if (targetMapped && targetRequiredDispositions.has(surface.disposition)) {
      if (!surface.target?.owner?.trim()) {
        errors.push(`${surface.id}: target-mapped surface lacks target.owner`);
      }
      if (!Array.isArray(surface.target?.surfaces) || surface.target.surfaces.length === 0) {
        errors.push(`${surface.id}: target-mapped surface lacks target.surfaces`);
      }
      if (!Array.isArray(surface.target?.securityRequirements)) {
        errors.push(`${surface.id}: target.securityRequirements must be an array`);
      }
      if (!Array.isArray(surface.target?.syncRequirements)) {
        errors.push(`${surface.id}: target.syncRequirements must be an array`);
      }
    }
    const verified = new Set(["verified", "rehearsed", "cutover_ready"]).has(
      surface.status,
    );
    if (verified) {
      if (!Array.isArray(surface.verification?.tests) || surface.verification.tests.length === 0) {
        errors.push(`${surface.id}: verified surface lacks tests`);
      }
      if (!Array.isArray(surface.evidence) || surface.evidence.length === 0) {
        errors.push(`${surface.id}: verified surface lacks evidence`);
      }
    }
  }

  for (const surface of discovered) {
    if (!manifestIds.has(surface.id)) {
      errors.push(`new unrecorded source surface ${surface.id}: ${surface.name}`);
    }
  }
  for (const surface of manifest.surfaces ?? []) {
    if (surface.discovery === "automatic" && !discoveredIds.has(surface.id)) {
      warnings.push(`recorded automatic surface no longer discovered: ${surface.id}`);
    }
  }

  return { errors, warnings };
}

function milestoneResults(manifest) {
  const active = manifest.surfaces.filter((surface) => surface.status !== "retired");
  const statusAtLeast = (surface, required) => {
    const rank = {
      discovered: 0,
      blocked: 0,
      characterized: 1,
      target_mapped: 2,
      implemented: 3,
      verified: 4,
      rehearsed: 5,
      cutover_ready: 6,
      retired: 6,
    };
    return rank[surface.status] >= rank[required];
  };
  const targetRelevant = active.filter((surface) =>
    targetRequiredDispositions.has(surface.disposition),
  );
  const byMilestone = [
    {
      id: "M0",
      name: "Inventory classified",
      blockers: active.filter(
        (surface) =>
          surface.sourcePresence !== "present" || surface.disposition === "unclassified",
      ),
    },
    {
      id: "M1",
      name: "Current behavior characterized",
      blockers: active.filter(
        (surface) =>
          !surface.currentBehavior?.trim() || !statusAtLeast(surface, "characterized"),
      ),
    },
    {
      id: "M2",
      name: "Target mapped",
      blockers: targetRelevant.filter((surface) => !statusAtLeast(surface, "target_mapped")),
    },
    {
      id: "M3",
      name: "Implementation verified",
      blockers: targetRelevant.filter((surface) => !statusAtLeast(surface, "verified")),
    },
    {
      id: "M4",
      name: "Migration rehearsed",
      blockers: targetRelevant.filter((surface) => !statusAtLeast(surface, "rehearsed")),
    },
    {
      id: "M5",
      name: "Cutover ready",
      blockers: active.filter((surface) => !statusAtLeast(surface, "cutover_ready")),
    },
  ];
  // Gates are ordered program checkpoints. A later milestone cannot pass, or
  // look nearly complete, while an earlier milestone is still incomplete.
  let cumulativeBlockerIds = new Set();
  return byMilestone.map((milestone) => {
    cumulativeBlockerIds = new Set([
      ...cumulativeBlockerIds,
      ...milestone.blockers.map((surface) => surface.id),
    ]);
    return {
      ...milestone,
      blockers: active.filter((surface) => cumulativeBlockerIds.has(surface.id)),
    };
  });
}

function countBy(items, key) {
  const counts = new Map();
  for (const item of items) counts.set(item[key], (counts.get(item[key]) ?? 0) + 1);
  return [...counts.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));
}

function markdownTable(rows) {
  return rows.map((row) => `| ${row.join(" | ")} |`).join("\n");
}

function report(manifest, validation) {
  const milestones = milestoneResults(manifest);
  const unclassified = manifest.surfaces.filter(
    (surface) => surface.disposition === "unclassified",
  );
  const missing = manifest.surfaces.filter(
    (surface) => surface.sourcePresence === "missing",
  );
  const lines = [
    "# Supabase Conversion Coverage",
    "",
    "> Generated by `node scripts/supabase-conversion-ledger.mjs report`.",
    "> Do not edit this file manually; edit the manifest or source inventory.",
    "",
    `Last synchronized: ${manifest.discovery.lastSynchronizedAt}`,
    `Source baseline commit: \`${manifest.sourceBaseline.commit}\` on \`${manifest.sourceBaseline.branch}\``,
    "",
    "## Overall",
    "",
    markdownTable([
      ["Metric", "Count"],
      ["---", "---:"],
      ["Recorded surfaces", String(manifest.surfaces.length)],
      ["Automatically discovered", String(manifest.surfaces.filter((s) => s.discovery === "automatic").length)],
      ["Manual cross-cutting surfaces", String(manifest.surfaces.filter((s) => s.discovery === "manual").length)],
      ["Unclassified", String(unclassified.length)],
      ["Missing from source", String(missing.length)],
      ["Structural validation errors", String(validation.errors.length)],
      ["Validation warnings", String(validation.warnings.length)],
    ]),
    "",
    "## Milestone Gates",
    "",
    markdownTable([
      ["Gate", "Meaning", "Result", "Blocking surfaces"],
      ["---", "---", "---", "---:"],
      ...milestones.map((milestone) => [
        milestone.id,
        milestone.name,
        milestone.blockers.length === 0 ? "PASS" : "BLOCKED",
        String(milestone.blockers.length),
      ]),
    ]),
    "",
    "## Surfaces by Kind",
    "",
    markdownTable([
      ["Kind", "Count"],
      ["---", "---:"],
      ...countBy(manifest.surfaces, "kind").map(([key, value]) => [key, String(value)]),
    ]),
    "",
    "## Surfaces by Status",
    "",
    markdownTable([
      ["Status", "Count"],
      ["---", "---:"],
      ...countBy(manifest.surfaces, "status").map(([key, value]) => [key, String(value)]),
    ]),
    "",
    "## Surfaces by Disposition",
    "",
    markdownTable([
      ["Disposition", "Count"],
      ["---", "---:"],
      ...countBy(manifest.surfaces, "disposition").map(([key, value]) => [key, String(value)]),
    ]),
    "",
    "## Immediate Inventory Queue",
    "",
    "The complete queue is in `conversion-manifest.json`. The first 50 unclassified surfaces are:",
    "",
    ...unclassified.slice(0, 50).map(
      (surface) => `- \`${surface.id}\` — ${surface.kind} — ${surface.name}`,
    ),
    "",
    "## Commands",
    "",
    "```bash",
    "node scripts/supabase-conversion-ledger.mjs sync",
    "node scripts/supabase-conversion-ledger.mjs check",
    "node scripts/supabase-conversion-ledger.mjs gate M0",
    "```",
    "",
  ];
  fs.writeFileSync(REPORT_PATH, lines.join("\n"));
}

function printValidation(validation) {
  for (const warning of validation.warnings) console.warn(`warning: ${warning}`);
  for (const error of validation.errors) console.error(`error: ${error}`);
}

function main() {
  const command = process.argv[2] ?? "check";
  if (!fs.existsSync(MANIFEST_PATH)) {
    throw new Error(`Missing manifest: ${relative(MANIFEST_PATH)}`);
  }
  const discovered = discoverAll();
  const batches = loadClassificationBatches();
  const productAuthorityCrosswalk = loadProductAuthorityCrosswalk();
  const implementationSlices = loadImplementationSlices();
  let manifest = loadManifest();
  let batchErrors = [];

  if (command === "sync") {
    manifest = mergeDiscovery(manifest, discovered);
    batchErrors = applyClassificationBatches(manifest, batches);
    fs.writeFileSync(MANIFEST_PATH, `${JSON.stringify(manifest, null, 2)}\n`);
  } else if (!new Set(["check", "report", "gate"]).has(command)) {
    throw new Error(`Unknown command ${command}; use sync, check, report, or gate`);
  } else {
    const expectedManifest = structuredClone(manifest);
    batchErrors = applyClassificationBatches(expectedManifest, batches);
    if (JSON.stringify(expectedManifest.surfaces) !== JSON.stringify(manifest.surfaces)) {
      batchErrors.push("classification batches are not synchronized; run sync");
    }
  }

  const productAuthorityErrors = validateProductAuthorityCrosswalk(
    manifest,
    batches,
    productAuthorityCrosswalk,
  );
  const productAuthorityArtifacts = buildProductAuthorityAudit(
    manifest,
    batches,
    productAuthorityCrosswalk,
  );
  if (command === "sync" || command === "report") {
    writeProductAuthorityArtifacts(productAuthorityArtifacts);
  } else {
    productAuthorityErrors.push(
      ...productAuthorityArtifactErrors(productAuthorityArtifacts),
    );
  }

  const implementationSliceErrors = validateImplementationSlices(
    manifest,
    productAuthorityCrosswalk,
    implementationSlices,
  );
  const implementationSliceArtifacts = buildImplementationSliceAudit(
    manifest,
    implementationSlices,
  );
  if (command === "sync" || command === "report") {
    writeImplementationSliceArtifacts(implementationSliceArtifacts);
  } else {
    implementationSliceErrors.push(
      ...implementationSliceArtifactErrors(implementationSliceArtifacts),
    );
  }

  const validation = validate(manifest, discovered, [
    ...batchErrors,
    ...productAuthorityErrors,
    ...implementationSliceErrors,
  ]);
  printValidation(validation);
  if (command === "sync" || command === "report") report(manifest, validation);

  if (command === "gate") {
    const requested = process.argv[3];
    const milestone = milestoneResults(manifest).find((entry) => entry.id === requested);
    if (!milestone) throw new Error("gate requires M0, M1, M2, M3, M4, or M5");
    if (validation.errors.length > 0 || milestone.blockers.length > 0) {
      console.error(
        `${requested} BLOCKED: ${milestone.blockers.length} coverage blockers, ${validation.errors.length} structural errors`,
      );
      process.exit(1);
    }
    console.log(`${requested} PASS: ${milestone.name}`);
    return;
  }

  console.log(
    `conversion-ledger: ${manifest.surfaces.length} recorded surfaces, ${discovered.length} currently discovered, ${validation.errors.length} errors, ${validation.warnings.length} warnings`,
  );
  if (validation.errors.length > 0) process.exit(1);
}

main();
