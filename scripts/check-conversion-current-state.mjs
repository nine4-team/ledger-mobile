import { execFileSync } from "node:child_process";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, isAbsolute, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(scriptDirectory, "..");
const stateRelativePath =
  "docs/plans/ledger-accounting-redesign/conversion/current-execution-state.json";
const statePath = join(repositoryRoot, stateRelativePath);
const workflowRecordsRelative =
  "docs/plans/ledger-accounting-redesign/conversion/workflow-records";
const workflowRecordsPath = join(repositoryRoot, workflowRecordsRelative);
const manifest = JSON.parse(
  readFileSync(
    join(repositoryRoot, "docs/plans/ledger-accounting-redesign/conversion/conversion-manifest.json"),
    "utf8",
  ),
);
const authorityCrosswalk = JSON.parse(
  readFileSync(
    join(repositoryRoot, "docs/plans/ledger-accounting-redesign/conversion/product-authority-crosswalk.json"),
    "utf8",
  ),
);
const surfacesById = new Map((manifest.surfaces ?? []).map((surface) => [surface.id, surface]));
const canonicalTargetSpecs = new Set(authorityCrosswalk.canonicalTargetSpecs ?? []);
const errors = [];

const workflowStatuses = new Set([
  "planning",
  "implementation",
  "review",
  "local_verification",
  "ci_verification",
  "blocked",
  "complete",
]);
const workflowKinds = new Set(["product_ui", "backend_control", "migration", "coverage_audit"]);
const layers = new Set([
  "domain",
  "app_ui",
  "app_mcp",
  "postgres_schema",
  "postgres_handler",
  "rls",
  "powersync_sync",
  "local_offline",
  "accounting",
  "media",
  "migration",
  "auth",
  "deletion",
  "observability",
]);
const risks = new Set([
  "ui_fidelity",
  "offline_durability",
  "tenant_authorization",
  "accounting",
  "sync_visibility",
  "media_durability",
  "migration_fidelity",
  "identity_auth",
  "deletion_retention",
  "database_integrity",
  "handler_idempotency",
  "app_mcp_parity",
  "none",
]);
const riskByLayer = new Map([
  ["app_ui", "ui_fidelity"],
  ["rls", "tenant_authorization"],
  ["powersync_sync", "sync_visibility"],
  ["local_offline", "offline_durability"],
  ["accounting", "accounting"],
  ["media", "media_durability"],
  ["migration", "migration_fidelity"],
  ["auth", "identity_auth"],
  ["deletion", "deletion_retention"],
  ["postgres_schema", "database_integrity"],
  ["postgres_handler", "handler_idempotency"],
  ["app_mcp", "app_mcp_parity"],
]);
const specialistReviewRisks = new Set([
  "offline_durability",
  "tenant_authorization",
  "accounting",
  "sync_visibility",
  "media_durability",
  "migration_fidelity",
  "identity_auth",
  "deletion_retention",
  "database_integrity",
  "handler_idempotency",
]);

function requireCondition(condition, message) {
  if (!condition) errors.push(message);
}

function requireString(value, field) {
  requireCondition(
    typeof value === "string" && value.trim().length > 0,
    `${field} must be a non-empty string.`,
  );
}

function repositoryEntry(value, field, { fileOnly = false } = {}) {
  requireString(value, field);
  if (typeof value !== "string" || value.length === 0) return undefined;
  requireCondition(!isAbsolute(value), `${field} must be repository-relative.`);
  const candidate = resolve(repositoryRoot, value);
  const repositoryRelative = relative(repositoryRoot, candidate);
  requireCondition(
    repositoryRelative !== "" && !repositoryRelative.startsWith(".."),
    `${field} must remain inside the repository.`,
  );
  try {
    requireCondition(
      fileOnly ? statSync(candidate).isFile() : true,
      `${field} must be a regular file.`,
    );
    return candidate;
  } catch {
    errors.push(`${field} does not exist: ${value}`);
    return undefined;
  }
}

function repositoryFile(value, field) {
  return repositoryEntry(value, field, { fileOnly: true });
}

function inferredLayersForPath(path) {
  const inferred = new Set();
  const lower = path.toLowerCase();
  if (
    path.startsWith("LedgeriOS/LedgeriOS/Views") ||
    path.startsWith("LedgeriOS/LedgeriOS/Components") ||
    path.startsWith("LedgeriOS/LedgerTargetApp/") ||
    path.startsWith("LedgeriOS/LedgerTargetAppModel/")
  ) inferred.add("app_ui");
  if (path.startsWith("LedgeriOS/LedgerTargetCore/")) inferred.add("domain");
  if (path.startsWith("LedgeriOS/LedgerTargetPowerSync/")) {
    inferred.add("powersync_sync");
    inferred.add("local_offline");
  }
  if (path.startsWith("LedgerTargetMCP/")) inferred.add("app_mcp");
  if (path.startsWith("LedgeriOS/LedgerTargetMigrationCore/")) inferred.add("migration");
  if (path.startsWith("supabase/migrations/") || path.startsWith("supabase/tests/")) {
    inferred.add("postgres_schema");
    inferred.add("postgres_handler");
    inferred.add("rls");
  }
  if (/(attachment|media|image|photo|receipt)/.test(lower)) inferred.add("media");
  if (/(auth|principal|session|keychain|identity)/.test(lower)) inferred.add("auth");
  if (/(delete|deletion|retention)/.test(lower)) inferred.add("deletion");
  if (/(invoice|purchase|expense|transaction|transfer|budget|accounting|refund|payment)/.test(lower)) {
    inferred.add("accounting");
  }
  return inferred;
}

function validateDerivedLayers(record, paths, prefix) {
  const declaredLayers = new Set(record?.layers ?? []);
  const declaredRisks = new Set(record?.riskDomains ?? []);
  for (const path of paths) {
    for (const layer of inferredLayersForPath(path)) {
      requireCondition(
        declaredLayers.has(layer),
        `${prefix}: affected path ${path} requires layer ${layer}.`,
      );
      const risk = riskByLayer.get(layer);
      if (risk) {
        requireCondition(
          declaredRisks.has(risk),
          `${prefix}: affected path ${path} requires risk ${risk}.`,
        );
      }
    }
  }
}

function hasHeading(filePath, heading) {
  return readFileSync(filePath, "utf8")
    .split(/\r?\n/)
    .some(
      (line) =>
        /^#{1,6}\s+/.test(line) &&
        line.replace(/^#{1,6}\s+/, "").trim() === heading,
    );
}

function requireStrings(values, field, { allowEmpty = false } = {}) {
  requireCondition(
    Array.isArray(values) && (allowEmpty || values.length > 0),
    `${field} must be ${allowEmpty ? "an array" : "a non-empty array"}.`,
  );
  for (const [index, value] of (values ?? []).entries()) {
    requireString(value, `${field}[${index}]`);
  }
}

function validateAuthority(entries, prefix, kind) {
  requireCondition(Array.isArray(entries) && entries.length > 0, `${prefix} must not be empty.`);
  let hasCanonicalTarget = false;
  for (const [index, entry] of (entries ?? []).entries()) {
    const label = `${prefix}[${index}]`;
    requireCondition(
      ["canonical_target", "decision_authority", "architecture_authority", "current_product", "conversion_control"].includes(entry?.role),
      `${label}.role is not allowed.`,
    );
    const filePath = repositoryFile(entry?.path, `${label}.path`);
    requireString(entry?.section, `${label}.section`);
    if (filePath && typeof entry?.section === "string") {
      try {
        requireCondition(hasHeading(filePath, entry.section), `${label}.section does not exist.`);
      } catch (error) {
        errors.push(`${label} could not be read: ${error.message}`);
      }
    }
    if (entry?.role === "canonical_target") {
      hasCanonicalTarget = true;
      requireCondition(
        canonicalTargetSpecs.has(entry.path),
        `${label}.path is not a registered canonical target spec.`,
      );
    }
    if (entry?.role === "decision_authority") {
      requireCondition(
        entry.path === "docs/plans/ledger-accounting-redesign/decision-log.md",
        `${label}.path is not the decision log.`,
      );
    }
  }
  if (kind === "product_ui") {
    requireCondition(hasCanonicalTarget, `${prefix} must include a canonical target spec.`);
  }
}

function validateWorkflowRecord(record, relativePath) {
  const prefix = relativePath;
  requireCondition(record?.schemaVersion === 1, `${prefix}: schemaVersion must equal 1.`);
  requireCondition(
    /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(record?.workflowId ?? ""),
    `${prefix}: workflowId must be lower-kebab-case.`,
  );
  requireCondition(
    relativePath.endsWith(`/${record?.workflowId}.json`),
    `${prefix}: filename must equal workflowId.`,
  );
  requireString(record?.title, `${prefix}: title`);
  requireCondition(workflowKinds.has(record?.kind), `${prefix}: kind is not allowed.`);
  requireCondition(workflowStatuses.has(record?.status), `${prefix}: status is not allowed.`);
  requireString(record?.outcome, `${prefix}: outcome`);
  validateAuthority(record?.authority, `${prefix}: authority`, record?.kind);

  requireStrings(record?.affectedComponents, `${prefix}: affectedComponents`);
  for (const [index, path] of (record?.affectedComponents ?? []).entries()) {
    repositoryEntry(path, `${prefix}: affectedComponents[${index}]`);
  }
  requireCondition(
    new Set(record?.affectedComponents ?? []).size === (record?.affectedComponents ?? []).length,
    `${prefix}: affectedComponents must not contain duplicates.`,
  );

  requireStrings(record?.layers, `${prefix}: layers`);
  for (const layer of record?.layers ?? []) {
    requireCondition(layers.has(layer), `${prefix}: unknown layer ${layer}.`);
  }
  requireCondition(
    new Set(record?.layers ?? []).size === (record?.layers ?? []).length,
    `${prefix}: layers must not contain duplicates.`,
  );

  requireStrings(record?.riskDomains, `${prefix}: riskDomains`);
  for (const risk of record?.riskDomains ?? []) {
    requireCondition(risks.has(risk), `${prefix}: unknown risk ${risk}.`);
  }
  requireCondition(
    !(record?.riskDomains ?? []).includes("none") || record.riskDomains.length === 1,
    `${prefix}: none cannot be combined with another risk.`,
  );
  for (const layer of record?.layers ?? []) {
    const risk = riskByLayer.get(layer);
    if (risk) {
      requireCondition(
        (record?.riskDomains ?? []).includes(risk),
        `${prefix}: layer ${layer} requires risk ${risk}.`,
      );
    }
  }
  if (["product_ui", "coverage_audit"].includes(record?.kind)) {
    requireCondition((record.layers ?? []).includes("app_ui"), `${prefix}: ${record.kind} requires app_ui layer.`);
    requireCondition((record.riskDomains ?? []).includes("ui_fidelity"), `${prefix}: ${record.kind} requires ui_fidelity risk.`);
  }
  if (record?.kind === "migration") {
    requireCondition((record.layers ?? []).includes("migration"), `${prefix}: migration kind requires migration layer.`);
    requireCondition((record.riskDomains ?? []).includes("migration_fidelity"), `${prefix}: migration kind requires migration_fidelity risk.`);
  }
  if ((record?.layers ?? []).includes("postgres_handler")) {
    requireCondition(
      (record.riskDomains ?? []).includes("database_integrity"),
      `${prefix}: postgres_handler requires database_integrity risk.`,
    );
  }
  validateDerivedLayers(record, record?.affectedComponents ?? [], prefix);

  const journeys = record?.uiJourneys;
  if (record?.kind === "product_ui") {
    requireCondition(Array.isArray(journeys) && journeys.length > 0, `${prefix}: uiJourneys must not be empty.`);
  } else {
    requireCondition(Array.isArray(journeys), `${prefix}: uiJourneys must be an array.`);
  }
  const journeyIds = new Set();
  const coveredUiSurfaceIds = new Set();
  for (const [journeyIndex, journey] of (journeys ?? []).entries()) {
    const journeyPrefix = `${prefix}: uiJourneys[${journeyIndex}]`;
    requireString(journey?.journeyId, `${journeyPrefix}.journeyId`);
    requireCondition(!journeyIds.has(journey?.journeyId), `${journeyPrefix}.journeyId is duplicated.`);
    journeyIds.add(journey?.journeyId);
    requireString(journey?.sourcePage, `${journeyPrefix}.sourcePage`);
    requireString(journey?.targetPage, `${journeyPrefix}.targetPage`);
    validateAuthority(journey?.authority, `${journeyPrefix}.authority`, record?.kind);
    requireStrings(journey?.sourceSurfaceIds, `${journeyPrefix}.sourceSurfaceIds`);
    for (const surfaceId of journey?.sourceSurfaceIds ?? []) {
      const surface = surfacesById.get(surfaceId);
      requireCondition(Boolean(surface), `${journeyPrefix}: unknown source surface ${surfaceId}.`);
      requireCondition(
        ["swift_ui_component", "swift_view"].includes(surface?.kind),
        `${journeyPrefix}: ${surfaceId} is not an inventoried UI component or view.`,
      );
      requireCondition(!coveredUiSurfaceIds.has(surfaceId), `${journeyPrefix}: ${surfaceId} is covered twice.`);
      coveredUiSurfaceIds.add(surfaceId);
    }
    requireCondition(
      Array.isArray(journey?.controls) && journey.controls.length > 0,
      `${journeyPrefix}.controls must not be empty.`,
    );
    for (const [controlIndex, control] of (journey?.controls ?? []).entries()) {
      const controlPrefix = `${journeyPrefix}.controls[${controlIndex}]`;
      requireString(control?.label, `${controlPrefix}.label`);
      requireCondition(Array.isArray(control?.options), `${controlPrefix}.options must be an array.`);
      for (const [optionIndex, option] of (control?.options ?? []).entries()) {
        const optionPrefix = `${controlPrefix}.options[${optionIndex}]`;
        requireString(option?.label, `${optionPrefix}.label`);
        requireString(option?.result, `${optionPrefix}.result`);
        requireCondition(
          ["preserve", "redesign", "retire"].includes(option?.disposition),
          `${optionPrefix}.disposition is not allowed.`,
        );
      }
      requireString(control?.action, `${controlPrefix}.action`);
      requireString(control?.result, `${controlPrefix}.result`);
      requireCondition(
        ["preserve", "redesign", "retire"].includes(control?.disposition),
        `${controlPrefix}.disposition is not allowed.`,
      );
    }
    requireCondition(
      Array.isArray(journey?.transitions) && journey.transitions.length > 0,
      `${journeyPrefix}.transitions must not be empty.`,
    );
    for (const [transitionIndex, transition] of (journey?.transitions ?? []).entries()) {
      const transitionPrefix = `${journeyPrefix}.transitions[${transitionIndex}]`;
      requireString(transition?.from, `${transitionPrefix}.from`);
      requireString(transition?.event, `${transitionPrefix}.event`);
      requireString(transition?.to, `${transitionPrefix}.to`);
      requireCondition(
        ["preserve", "redesign", "retire"].includes(transition?.disposition),
        `${transitionPrefix}.disposition is not allowed.`,
      );
    }
    requireCondition(
      Array.isArray(journey?.states) && journey.states.length > 0,
      `${journeyPrefix}.states must not be empty.`,
    );
    for (const [stateIndex, state] of (journey?.states ?? []).entries()) {
      const statePrefix = `${journeyPrefix}.states[${stateIndex}]`;
      requireString(state?.name, `${statePrefix}.name`);
      requireString(state?.expected, `${statePrefix}.expected`);
      requireCondition(
        ["preserve", "redesign", "retire"].includes(state?.disposition),
        `${statePrefix}.disposition is not allowed.`,
      );
    }
  }

  if (record?.kind === "coverage_audit") {
    const allUiSurfaceIds = new Set(
      [...surfacesById.values()]
        .filter((surface) => ["swift_ui_component", "swift_view"].includes(surface.kind))
        .map((surface) => surface.id),
    );
    requireCondition(record?.uiCoverage?.scope === "all_current_app_ui", `${prefix}: UI coverage scope is invalid.`);
    requireCondition(record?.uiCoverage?.expectedSurfaceCount === allUiSurfaceIds.size, `${prefix}: expected UI surface count is stale.`);
    requireStrings(record?.uiCoverage?.uncoveredSurfaceIds, `${prefix}: uiCoverage.uncoveredSurfaceIds`, { allowEmpty: true });
    const uncovered = new Set(record?.uiCoverage?.uncoveredSurfaceIds ?? []);
    requireCondition(uncovered.size === (record?.uiCoverage?.uncoveredSurfaceIds ?? []).length, `${prefix}: uncovered UI IDs contain duplicates.`);
    for (const surfaceId of uncovered) {
      requireCondition(allUiSurfaceIds.has(surfaceId), `${prefix}: unknown uncovered UI surface ${surfaceId}.`);
      requireCondition(!coveredUiSurfaceIds.has(surfaceId), `${prefix}: ${surfaceId} is both covered and uncovered.`);
    }
    const accounted = new Set([...coveredUiSurfaceIds, ...uncovered]);
    requireCondition(accounted.size === allUiSurfaceIds.size, `${prefix}: covered plus uncovered UI surfaces is not exhaustive.`);
    for (const surfaceId of allUiSurfaceIds) {
      requireCondition(accounted.has(surfaceId), `${prefix}: UI surface ${surfaceId} is neither covered nor uncovered.`);
    }
    if (record?.status === "complete") {
      requireCondition(uncovered.size === 0, `${prefix}: complete UI baseline still has uncovered surfaces.`);
    }
  }

  requireCondition(
    Array.isArray(record?.acceptanceChecks) && record.acceptanceChecks.length > 0,
    `${prefix}: acceptanceChecks must not be empty.`,
  );
  const acceptanceIds = new Set();
  const coveredRisks = new Set();
  for (const [index, check] of (record?.acceptanceChecks ?? []).entries()) {
    const checkPrefix = `${prefix}: acceptanceChecks[${index}]`;
    requireString(check?.id, `${checkPrefix}.id`);
    requireCondition(!acceptanceIds.has(check?.id), `${checkPrefix}.id is duplicated.`);
    acceptanceIds.add(check?.id);
    requireCondition(
      check?.risk === "general" || risks.has(check?.risk),
      `${checkPrefix}.risk is not allowed.`,
    );
    requireString(check?.expected, `${checkPrefix}.expected`);
    requireString(check?.command, `${checkPrefix}.command`);
    requireCondition(
      ["planned", "passed", "failed"].includes(check?.status),
      `${checkPrefix}.status is not allowed.`,
    );
    if (typeof check?.risk === "string") coveredRisks.add(check.risk);
  }
  requireCondition(coveredRisks.has("general"), `${prefix}: general acceptance proof is required.`);
  for (const risk of record?.riskDomains ?? []) {
    if (risk !== "none") {
      requireCondition(coveredRisks.has(risk), `${prefix}: acceptanceChecks do not cover ${risk}.`);
    }
  }

  requireStrings(record?.blockers, `${prefix}: blockers`, { allowEmpty: true });
  const verification = record?.verification ?? {};
  requireCondition(
    ["not_run", "passed", "failed"].includes(verification.local?.status),
    `${prefix}: verification.local.status is not allowed.`,
  );
  requireStrings(verification.local?.commands, `${prefix}: verification.local.commands`, { allowEmpty: true });
  requireCondition(
    typeof verification.review?.required === "boolean",
    `${prefix}: verification.review.required must be boolean.`,
  );
  requireCondition(
    ["not_run", "passed", "not_required"].includes(verification.review?.status),
    `${prefix}: verification.review.status is not allowed.`,
  );
  requireString(verification.review?.summary, `${prefix}: verification.review.summary`);
  const derivedReviewRequired =
    record?.kind === "coverage_audit" ||
    (record?.riskDomains ?? []).some((risk) => specialistReviewRisks.has(risk));
  requireCondition(
    verification.review?.required === derivedReviewRequired,
    `${prefix}: verification.review.required does not match the workflow risks.`,
  );
  requireCondition(
    ["not_run", "passed", "failed"].includes(verification.ci?.status),
    `${prefix}: verification.ci.status is not allowed.`,
  );
  if (record?.status === "complete") {
    requireCondition((record.blockers ?? []).length === 0, `${prefix}: complete workflow has blockers.`);
    requireCondition(verification.local?.status === "passed", `${prefix}: complete workflow lacks passed local verification.`);
    requireCondition((verification.local?.commands ?? []).length > 0, `${prefix}: complete workflow lacks local commands.`);
    for (const check of record.acceptanceChecks ?? []) {
      requireCondition(check.status === "passed", `${prefix}: complete workflow has an unpassed acceptance check ${check.id}.`);
      requireCondition(
        (verification.local?.commands ?? []).includes(check.command),
        `${prefix}: passed acceptance command is absent from local verification: ${check.command}.`,
      );
    }
    requireCondition(
      verification.review?.required
        ? verification.review.status === "passed"
        : ["passed", "not_required"].includes(verification.review?.status),
      `${prefix}: complete workflow lacks its required review result.`,
    );
    requireCondition(verification.ci?.status === "passed", `${prefix}: complete workflow lacks passed CI.`);
    requireCondition(/^[0-9a-f]{40}$/.test(verification.ci?.commit ?? ""), `${prefix}: complete workflow lacks exact CI commit.`);
    requireCondition(Number.isInteger(verification.ci?.run) && verification.ci.run > 0, `${prefix}: complete workflow lacks CI run ID.`);
    if (/^[0-9a-f]{40}$/.test(verification.ci?.commit ?? "")) {
      try {
        execFileSync("git", ["cat-file", "-e", `${verification.ci.commit}^{commit}`], {
          cwd: repositoryRoot,
          stdio: "ignore",
        });
      } catch {
        errors.push(`${prefix}: verification.ci.commit does not exist in Git.`);
      }
    }
  }
}

function validateWorkflowSet(records) {
  const completedUiBaseline = records.find(
    (record) =>
      record.kind === "coverage_audit" &&
      record.status === "complete" &&
      record.uiCoverage?.scope === "all_current_app_ui",
  );
  const baselineJourneyIds = new Set(
    (completedUiBaseline?.uiJourneys ?? []).map((journey) => journey.journeyId),
  );
  for (const record of records) {
    if (record.kind !== "product_ui" || ["planning", "blocked"].includes(record.status)) continue;
    requireCondition(
      Boolean(completedUiBaseline),
      `${record.workflowId}: product UI implementation requires the completed current-app UI baseline.`,
    );
    requireStrings(record.baselineJourneyIds, `${record.workflowId}: baselineJourneyIds`);
    for (const journeyId of record.baselineJourneyIds ?? []) {
      requireCondition(
        baselineJourneyIds.has(journeyId),
        `${record.workflowId}: unknown baseline journey ${journeyId}.`,
      );
    }
  }
}

function runSelfTests() {
  const allUiIds = [...surfacesById.values()]
    .filter((surface) => ["swift_ui_component", "swift_view"].includes(surface.kind))
    .map((surface) => surface.id)
    .sort();
  const firstUiId = allUiIds[0];
  const baseCoverage = {
    schemaVersion: 1,
    workflowId: "self-test-ui-baseline",
    title: "Self-test UI baseline",
    kind: "coverage_audit",
    status: "implementation",
    outcome: "Exercise workflow validation without changing repository state.",
    authority: [
      { role: "current_product", path: "docs/specs/README.md", section: "Spec Index" },
    ],
    affectedComponents: ["LedgeriOS/LedgeriOS/Views"],
    layers: ["app_ui"],
    riskDomains: ["ui_fidelity"],
    uiCoverage: {
      scope: "all_current_app_ui",
      expectedSurfaceCount: allUiIds.length,
      uncoveredSurfaceIds: allUiIds,
    },
    uiJourneys: [],
    acceptanceChecks: [
      { id: "SELF-GENERAL", risk: "general", expected: "General proof.", command: "self-general", status: "planned" },
      { id: "SELF-UI", risk: "ui_fidelity", expected: "UI proof.", command: "self-ui", status: "planned" },
    ],
    blockers: [],
    verification: {
      local: { status: "not_run", commands: [] },
      review: { required: true, status: "not_run", summary: "Required." },
      ci: { status: "not_run", commit: null, run: null },
    },
  };
  const journey = {
    journeyId: "self-journey",
    sourcePage: "Source",
    targetPage: "Target",
    authority: [
      { role: "current_product", path: "docs/specs/README.md", section: "Spec Index" },
    ],
    sourceSurfaceIds: [firstUiId],
    controls: [
      {
        label: "Control",
        options: [{ label: "Option", result: "Result", disposition: "preserve" }],
        action: "Act",
        result: "Result",
        disposition: "preserve",
      },
    ],
    transitions: [{ from: "A", event: "Act", to: "B", disposition: "preserve" }],
    states: [{ name: "Ready", expected: "Visible", disposition: "preserve" }],
  };
  const expectFailure = (label, action, pattern) => {
    const start = errors.length;
    action();
    const messages = errors.splice(start);
    if (!messages.some((message) => pattern.test(message))) {
      throw new Error(`${label} did not fail as expected: ${messages.join(" | ")}`);
    }
  };

  expectFailure("duplicate UI coverage", () => {
    const value = structuredClone(baseCoverage);
    value.uiJourneys = [journey];
    validateWorkflowRecord(value, `${workflowRecordsRelative}/${value.workflowId}.json`);
  }, /both covered and uncovered/);

  expectFailure("missing UI risk", () => {
    const value = structuredClone(baseCoverage);
    value.riskDomains = ["none"];
    validateWorkflowRecord(value, `${workflowRecordsRelative}/${value.workflowId}.json`);
  }, /requires ui_fidelity risk/);

  expectFailure("malformed option outcome", () => {
    const value = structuredClone(baseCoverage);
    value.uiCoverage.uncoveredSurfaceIds = allUiIds.slice(1);
    value.uiJourneys = [structuredClone(journey)];
    delete value.uiJourneys[0].controls[0].options[0].disposition;
    validateWorkflowRecord(value, `${workflowRecordsRelative}/${value.workflowId}.json`);
  }, /options\[0\]\.disposition/);

  const product = {
    ...structuredClone(baseCoverage),
    workflowId: "self-test-product-ui",
    kind: "product_ui",
    authority: [{ role: "canonical_target", path: "docs/specs/projects.md", section: "Creation Flow" }],
    uiJourneys: [journey],
    baselineJourneyIds: ["self-journey"],
    verification: {
      local: { status: "not_run", commands: [] },
      review: { required: false, status: "not_required", summary: "UI-only self-test." },
      ci: { status: "not_run", commit: null, run: null },
    },
  };
  delete product.uiCoverage;
  expectFailure("missing completed baseline", () => validateWorkflowSet([baseCoverage, product]), /requires the completed current-app UI baseline/);

  expectFailure("fake CI commit", () => {
    const value = structuredClone(baseCoverage);
    value.status = "complete";
    value.uiCoverage.uncoveredSurfaceIds = [];
    value.uiJourneys = [{ ...structuredClone(journey), sourceSurfaceIds: allUiIds }];
    value.acceptanceChecks.forEach((check) => { check.status = "passed"; });
    value.verification = {
      local: { status: "passed", commands: ["self-general", "self-ui"] },
      review: { required: true, status: "passed", summary: "Passed." },
      ci: { status: "passed", commit: "0000000000000000000000000000000000000000", run: 1 },
    };
    validateWorkflowRecord(value, `${workflowRecordsRelative}/${value.workflowId}.json`);
  }, /does not exist in Git/);

  expectFailure("undeclared database risks", () => {
    const value = structuredClone(baseCoverage);
    validateDerivedLayers(value, ["supabase/migrations/example.sql"], value.workflowId);
  }, /requires layer postgres_schema/);

  console.log("Conversion current-state self-tests passed: 6 negative cases.");
}

if (process.argv[2] === "--self-test") {
  runSelfTests();
  process.exit(0);
}

let state;
try {
  const bytes = statSync(statePath).size;
  requireCondition(bytes <= 8_000, `${stateRelativePath} must remain at or below 8000 bytes.`);
  state = JSON.parse(readFileSync(statePath, "utf8"));
} catch (error) {
  errors.push(`Unable to read valid ${stateRelativePath}: ${error.message}`);
}

if (state) {
  requireCondition(state.schemaVersion === 2, "schemaVersion must equal 2.");
  requireCondition(Number.isInteger(state.stateVersion) && state.stateVersion > 0, "stateVersion must be positive.");
  requireCondition(/^\d{4}-\d{2}-\d{2}$/.test(state.updatedAt ?? ""), "updatedAt must be an ISO date.");
  requireCondition(state.branch === "codex/supabase-powersync-implementation", "branch is incorrect.");
  requireCondition(state.worktree === "/Users/benjaminmackenzie/Dev/ledger_mobile_supabase", "worktree is incorrect.");
  repositoryFile(state.method?.path, "method.path");
  requireCondition(state.method?.version === 3, "method.version must equal 3.");

  const checkpoint = state.verifiedCheckpoint ?? {};
  requireString(checkpoint.name, "verifiedCheckpoint.name");
  requireCondition(/^[0-9a-f]{40}$/.test(checkpoint.commit ?? ""), "verifiedCheckpoint.commit must be exact.");
  requireCondition(Number.isInteger(checkpoint.ciRun) && checkpoint.ciRun > 0, "verifiedCheckpoint.ciRun must be positive.");
  requireCondition(checkpoint.ciStatus === "passed", "verifiedCheckpoint.ciStatus must be passed.");
  if (/^[0-9a-f]{40}$/.test(checkpoint.commit ?? "")) {
    try {
      execFileSync("git", ["merge-base", "--is-ancestor", checkpoint.commit, "HEAD"], {
        cwd: repositoryRoot,
        stdio: "ignore",
      });
    } catch {
      errors.push("verifiedCheckpoint.commit must be an ancestor of HEAD.");
    }
  }

  const active = state.activeWorkflow ?? {};
  requireString(active.id, "activeWorkflow.id");
  requireCondition(
    active.kind === "selection" || workflowKinds.has(active.kind),
    "activeWorkflow.kind is not allowed.",
  );
  requireCondition(workflowStatuses.has(active.status), "activeWorkflow.status is not allowed.");
  requireString(active.outcome, "activeWorkflow.outcome");
  requireStrings(active.nextActions, "activeWorkflow.nextActions");
  requireCondition(active.nextActions?.length <= 5, "activeWorkflow.nextActions may contain at most five actions.");

  if (active.kind === "selection") {
    requireCondition(active.status === "planning", "Selection must remain planning.");
    requireCondition(active.recordPath === null, "Selection must not point to a workflow record.");
    if (/^[0-9a-f]{40}$/.test(checkpoint.commit ?? "")) {
      const committedOrTracked = execFileSync(
        "git",
        ["diff", "--name-only", checkpoint.commit],
        { cwd: repositoryRoot, encoding: "utf8" },
      ).split(/\r?\n/).filter(Boolean);
      const statusPaths = execFileSync(
        "git",
        ["status", "--porcelain=v1", "-uall"],
        { cwd: repositoryRoot, encoding: "utf8" },
      ).split(/\r?\n/).filter(Boolean).map((line) => line.slice(3).split(" -> ").at(-1));
      const isTargetPath = (path) =>
        path.startsWith("LedgeriOS/LedgerTarget") ||
        path === "LedgeriOS/Package.swift" ||
        path === "LedgeriOS/project.yml" ||
        path.startsWith("LedgerTargetMCP/") ||
        path.startsWith("supabase/");
      const executableTargetChange = [...new Set([...committedOrTracked, ...statusPaths])].find(isTargetPath);
      requireCondition(
        !executableTargetChange,
        `Selection cannot coexist with target implementation change ${executableTargetChange}.`,
      );
    }
  } else {
    const activeRecordPath = repositoryFile(active.recordPath, "activeWorkflow.recordPath");
    requireCondition(
      active.recordPath?.startsWith(`${workflowRecordsRelative}/`) && active.recordPath?.endsWith(".json"),
      "activeWorkflow.recordPath must point into workflow-records.",
    );
    if (activeRecordPath) {
      try {
        const record = JSON.parse(readFileSync(activeRecordPath, "utf8"));
        requireCondition(record.workflowId === active.id, "Active record workflowId does not match current state.");
        requireCondition(record.kind === active.kind, "Active record kind does not match current state.");
        requireCondition(record.status === active.status, "Active record status does not match current state.");
      } catch (error) {
        errors.push(`Unable to read active workflow record: ${error.message}`);
      }
    }
  }

  for (const field of ["locallyWorkingProviderWorkflows", "hostedAuthenticatedRehearsals", "cutoverReadyWorkflows"]) {
    requireCondition(Number.isInteger(state.progress?.[field]) && state.progress[field] >= 0, `progress.${field} must be non-negative.`);
  }
  const estimate = state.progress?.practicalCompletionEstimatePercent ?? {};
  requireCondition(
    Number.isFinite(estimate.low) && Number.isFinite(estimate.center) && Number.isFinite(estimate.high) &&
      0 <= estimate.low && estimate.low <= estimate.center && estimate.center <= estimate.high && estimate.high <= 100,
    "Practical completion estimate is invalid.",
  );
  requireCondition(
    Array.isArray(state.guardrails) &&
      state.guardrails.some((value) => value.includes("/Users/benjaminmackenzie/Dev/ledger_mobile")) &&
      state.guardrails.some((value) => value.includes("Firebase")) &&
      state.guardrails.some((value) => value.includes("production")),
    "guardrails must preserve Firebase-worktree and production boundaries.",
  );
  requireCondition(
    Array.isArray(state.resume?.requiredReads) && state.resume.requiredReads[0] === stateRelativePath && state.resume.requiredReads.length <= 3,
    "resume.requiredReads must begin with current state and contain at most three files.",
  );
  requireCondition(
    Array.isArray(state.resume?.requiredCommands) && state.resume.requiredCommands.includes("npm run conversion:state:check"),
    "resume.requiredCommands must include the state checker.",
  );
}

const workflowRecords = [];
try {
  const workflowIds = new Set();
  for (const name of readdirSync(workflowRecordsPath).filter((value) => value.endsWith(".json")).sort()) {
    const relativePath = `${workflowRecordsRelative}/${name}`;
    const record = JSON.parse(readFileSync(join(workflowRecordsPath, name), "utf8"));
    requireCondition(!workflowIds.has(record.workflowId), `${relativePath}: duplicate workflowId ${record.workflowId}.`);
    workflowIds.add(record.workflowId);
    validateWorkflowRecord(record, relativePath);
    workflowRecords.push(record);
  }
} catch (error) {
  errors.push(`Unable to validate workflow records: ${error.message}`);
}

validateWorkflowSet(workflowRecords);

if (state?.activeWorkflow?.kind !== "selection" && /^[0-9a-f]{40}$/.test(state?.verifiedCheckpoint?.commit ?? "")) {
  const activeRecord = workflowRecords.find((record) => record.workflowId === state.activeWorkflow.id);
  if (activeRecord) {
    const changedPaths = execFileSync(
      "git",
      ["diff", "--name-only", state.verifiedCheckpoint.commit],
      { cwd: repositoryRoot, encoding: "utf8" },
    ).split(/\r?\n/).filter(Boolean);
    const untrackedPaths = execFileSync(
      "git",
      ["ls-files", "--others", "--exclude-standard"],
      { cwd: repositoryRoot, encoding: "utf8" },
    ).split(/\r?\n/).filter(Boolean);
    const isTargetPath = (path) =>
      path.startsWith("LedgeriOS/LedgerTarget") ||
      path === "LedgeriOS/Package.swift" ||
      path === "LedgeriOS/project.yml" ||
      path.startsWith("LedgerTargetMCP/") ||
      path.startsWith("supabase/");
    const changedTargetPaths = [...new Set([...changedPaths, ...untrackedPaths])].filter(isTargetPath);
    for (const path of changedTargetPaths) {
      requireCondition(
        (activeRecord.affectedComponents ?? []).some(
          (component) => path === component || path.startsWith(`${component}/`),
        ),
        `${activeRecord.workflowId}: changed target path ${path} is absent from affectedComponents.`,
      );
    }
    validateDerivedLayers(activeRecord, changedTargetPaths, activeRecord.workflowId);
  }
}

const agents = readFileSync(join(repositoryRoot, "AGENTS.md"), "utf8");
requireCondition(
  agents.includes(stateRelativePath) && agents.includes("npm run conversion:state:check"),
  "AGENTS.md must require current state and its checker on resume.",
);

if (errors.length > 0) {
  console.error("Conversion current-state check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(
  `Conversion current state is valid: ${state.activeWorkflow.id} at ${state.verifiedCheckpoint.commit.slice(0, 8)}.`,
);
