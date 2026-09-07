import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
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
const targetStoryCatalogRelative =
  "docs/plans/ledger-accounting-redesign/conversion/target-product-story-catalog.json";
const targetStoryCatalogPath = join(repositoryRoot, targetStoryCatalogRelative);
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
const targetStoryCatalog = JSON.parse(readFileSync(targetStoryCatalogPath, "utf8"));
const targetStoriesById = new Map(
  (targetStoryCatalog.stories ?? []).map((story) => [story.storyId, story]),
);
const targetDeliveryRequirementsByStory = new Map();
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
const productMilestoneRanks = new Map([["M3", 3], ["M4", 4], ["M5", 5]]);
const requestedProductGate = process.argv[2] === "--gate" ? process.argv[3] : undefined;
const allowedSourceOnlyAuthorities = new Set([
  "docs/specs/write-tiers.md",
  "docs/specs/canonical-sales.md",
  "docs/specs/transaction-audit.md",
  "docs/specs/vendor-credits.md",
]);
const completionWorkflowPath = ".github/workflows/supabase-conversion-control.yml";

const layerEvidencePredicates = new Map([
  ["domain", (path) => path.startsWith("LedgeriOS/LedgerTargetCore/")],
  ["app_ui", (path) =>
    path.startsWith("LedgeriOS/LedgerTargetApp/") ||
    path.startsWith("LedgeriOS/LedgerTargetAppModel/")],
  ["app_mcp", (path) => path.startsWith("LedgerTargetMCP/")],
  ["postgres_schema", (path) => path.startsWith("supabase/migrations/")],
  ["postgres_handler", (path) => path.startsWith("supabase/migrations/")],
  ["rls", (path) =>
    path.startsWith("supabase/migrations/") || path.startsWith("supabase/tests/")],
  ["powersync_sync", (path) => path.startsWith("LedgeriOS/LedgerTargetPowerSync/")],
  ["local_offline", (path) => path.startsWith("LedgeriOS/LedgerTargetPowerSync/")],
  ["accounting", (path) =>
    /(invoice|purchase|expense|transaction|transfer|budget|accounting|refund|payment)/i.test(path)],
  ["media", (path) => /(attachment|media|image|photo|receipt)/i.test(path)],
  ["migration", (path) =>
    path.startsWith("LedgeriOS/LedgerTargetMigrationCore/") ||
    /(^|\/)(migration|migrations)(\/|$)/i.test(path)],
  ["auth", (path) =>
    /(auth|principal|session|keychain|identity)/i.test(path) ||
    /^LedgeriOS\/LedgerTargetPowerSync\/Supabase.+RPC\.swift$/.test(path)],
  ["deletion", (path) => /(delete|deletion|retention)/i.test(path)],
  ["observability", (path) => /(observability|telemetry|metric|reconciliation|cutover|health)/i.test(path)],
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

function baselineTransitionReference(transition) {
  return `${transition.from} | ${transition.event} | ${transition.to}`;
}

function catalogBehaviorKey(journeyId, kind, ...parts) {
  return [journeyId, kind, ...parts].join("::");
}

function catalogBehaviorKeys(baseline) {
  const keys = new Set();
  for (const journey of baseline?.uiJourneys ?? []) {
    for (const control of journey.controls ?? []) {
      keys.add(catalogBehaviorKey(journey.journeyId, "control", control.label));
      for (const option of control.options ?? []) {
        keys.add(catalogBehaviorKey(journey.journeyId, "option", control.label, option.label));
      }
    }
    for (const transition of journey.transitions ?? []) {
      keys.add(catalogBehaviorKey(journey.journeyId, "transition", baselineTransitionReference(transition)));
    }
    for (const state of journey.states ?? []) {
      keys.add(catalogBehaviorKey(journey.journeyId, "state", state.name));
    }
  }
  return keys;
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

function sha256(filePath) {
  return createHash("sha256").update(readFileSync(filePath)).digest("hex");
}

function markdownHeadingInventory(filePath) {
  const occurrences = new Map();
  return readFileSync(filePath, "utf8")
    .split(/\r?\n/)
    .flatMap((line) => {
      const match = line.match(/^(#{1,6})\s+(.+?)\s*#*\s*$/);
      if (!match) return [];
      const heading = match[2].trim();
      const occurrence = (occurrences.get(heading) ?? 0) + 1;
      occurrences.set(heading, occurrence);
      return [{ heading, occurrence }];
    });
}

function headingInventoryKey(entry) {
  return `${entry.heading}::${entry.occurrence}`;
}

function pathSupportsLayer(path, layer) {
  return layerEvidencePredicates.get(layer)?.(path) ?? false;
}

function originGithubRepository() {
  const origin = execFileSync("git", ["remote", "get-url", "origin"], {
    cwd: repositoryRoot,
    encoding: "utf8",
  }).trim();
  const match = origin.match(/github\.com[/:]([^/\s]+\/[^/\s]+?)(?:\.git)?$/);
  if (!match) throw new Error(`origin is not a GitHub repository: ${origin}`);
  return match[1];
}

function validateGithubCompletionRun(commit, runId, prefix) {
  try {
    const repository = originGithubRepository();
    const run = JSON.parse(
      execFileSync("gh", ["api", `repos/${repository}/actions/runs/${runId}`], {
        cwd: repositoryRoot,
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe"],
      }),
    );
    requireCondition(run.head_sha === commit, `${prefix}: CI run ${runId} did not execute commit ${commit}.`);
    requireCondition(run.status === "completed", `${prefix}: CI run ${runId} is not completed.`);
    requireCondition(run.conclusion === "success", `${prefix}: CI run ${runId} did not succeed.`);
    requireCondition(run.path === completionWorkflowPath, `${prefix}: CI run ${runId} did not execute ${completionWorkflowPath}.`);
    requireCondition(["pull_request", "push"].includes(run.event), `${prefix}: CI run ${runId} has unsupported event ${run.event}.`);
    const jobs = JSON.parse(
      execFileSync("gh", ["api", `repos/${repository}/actions/runs/${runId}/jobs`, "--paginate"], {
        cwd: repositoryRoot,
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe"],
      }),
    );
    const jobConclusions = new Map((jobs.jobs ?? []).map((job) => [job.name, job.conclusion]));
    for (const requiredJob of [
      "Conversion state and traceability",
      "Isolated target environment",
      "Local Supabase provider slices",
    ]) {
      requireCondition(
        jobConclusions.get(requiredJob) === "success",
        `${prefix}: CI run ${runId} lacks successful required job ${requiredJob}.`,
      );
    }
  } catch (error) {
    errors.push(`${prefix}: unable to verify GitHub CI run ${runId}: ${error.message}`);
  }
}

function remoteBranchCommit(branch, prefix) {
  try {
    const output = execFileSync(
      "git",
      ["ls-remote", "--heads", "origin", `refs/heads/${branch}`],
      { cwd: repositoryRoot, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] },
    ).trim();
    const commit = output.split(/\s+/)[0];
    if (!/^[0-9a-f]{40}$/.test(commit ?? "")) {
      errors.push(`${prefix}: origin/${branch} did not resolve to an exact commit.`);
      return undefined;
    }
    return commit;
  } catch (error) {
    errors.push(`${prefix}: unable to resolve origin/${branch}: ${error.message}`);
    return undefined;
  }
}

function canonicalJson(value) {
  if (Array.isArray(value)) return value.map(canonicalJson);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value).sort().map((key) => [key, canonicalJson(value[key])]),
    );
  }
  return value;
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

function markdownSectionLines(filePath, section) {
  const lines = readFileSync(filePath, "utf8").split(/\r?\n/);
  const escaped = section.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const headingPattern = new RegExp(`^(#{1,6})\\s+${escaped}\\s*$`);
  const start = lines.findIndex((line) => headingPattern.test(line));
  if (start < 0) return [];
  const level = lines[start].match(/^#+/)?.[0].length ?? 6;
  let end = lines.length;
  for (let index = start + 1; index < lines.length; index += 1) {
    const match = lines[index].match(/^(#{1,6})\s+/);
    if (match && match[1].length <= level) {
      end = index;
      break;
    }
  }
  return lines.slice(start + 1, end);
}

function decisionRowExists(filePath, section, decisionId) {
  return markdownSectionLines(filePath, section)
    .some((line) => line.startsWith(`| ${decisionId} |`));
}

function decisionIdsInSection(filePath, section, prefix) {
  const ids = markdownSectionLines(filePath, section)
    .map((line) => line.match(/^\|\s+([DO]-[0-9]{3})\s+\|/)?.[1])
    .filter(Boolean);
  requireCondition(ids.length > 0, `${prefix}: no decision rows found in ${section}.`);
  requireCondition(new Set(ids).size === ids.length, `${prefix}: duplicate decision IDs in ${section}.`);
  return new Set(ids);
}

function indexedSpecPaths(indexPath) {
  const markdown = readFileSync(indexPath, "utf8");
  const indexSection = markdownSectionLines(indexPath, "Spec Index");
  const paths = [];
  for (const line of indexSection) {
    const link = line.match(/^\|\s*\[[^\]]+\]\(([^)#]+\.md)(?:#[^)]+)?\)\s*\|/)?.[1];
    if (!link) continue;
    const resolved = resolve(dirname(indexPath), link);
    const repositoryPath = relative(repositoryRoot, resolved).replaceAll("\\", "/");
    requireCondition(!repositoryPath.startsWith("../"), `${targetStoryCatalogRelative}: indexed spec escapes repository: ${link}.`);
    paths.push(repositoryPath);
  }
  requireCondition(markdown.includes("## Spec Index"), `${targetStoryCatalogRelative}: authority index lacks Spec Index.`);
  requireCondition(new Set(paths).size === paths.length, `${targetStoryCatalogRelative}: authority index contains duplicate spec paths.`);
  return new Set(paths);
}

function workflowEvidencePayload(record) {
  const payload = structuredClone(record);
  delete payload.status;
  if (payload.verification) delete payload.verification.ci;
  return payload;
}

function validateTargetStoryCatalog(catalog, prefix = targetStoryCatalogRelative) {
  requireCondition(catalog?.schemaVersion === 1, `${prefix}: schemaVersion must equal 1.`);
  requireCondition(catalog?.catalogId === "ledger-target-product-stories", `${prefix}: catalogId is invalid.`);
  requireCondition(catalog?.authorityIndex === "docs/specs/README.md", `${prefix}: authorityIndex must be docs/specs/README.md.`);
  repositoryFile(catalog?.authorityIndex, `${prefix}: authorityIndex`);
  requireCondition(
    catalog?.decisionLog?.path === "docs/plans/ledger-accounting-redesign/decision-log.md",
    `${prefix}: decisionLog.path must be the redesign decision log.`,
  );
  const catalogDecisionLogPath = repositoryFile(catalog?.decisionLog?.path, `${prefix}: decisionLog.path`);
  requireCondition(/^[0-9a-f]{64}$/.test(catalog?.decisionLog?.sourceHash ?? ""), `${prefix}: decisionLog.sourceHash must be SHA-256.`);
  if (catalogDecisionLogPath && /^[0-9a-f]{64}$/.test(catalog?.decisionLog?.sourceHash ?? "")) {
    requireCondition(
      sha256(catalogDecisionLogPath) === catalog.decisionLog.sourceHash,
      `${prefix}: decisionLog.sourceHash is stale; re-audit decision mappings after the log changed.`,
    );
  }
  requireCondition(
    ["partial", "complete"].includes(catalog?.completeness?.status),
    `${prefix}: completeness.status must be partial or complete.`,
  );
  requireString(catalog?.completeness?.reason, `${prefix}: completeness.reason`);
  requireCondition(Array.isArray(catalog?.stories) && catalog.stories.length > 0, `${prefix}: stories must not be empty.`);

  const storyIds = new Set();
  const catalogStoriesById = new Map();
  for (const [index, story] of (catalog?.stories ?? []).entries()) {
    const storyPrefix = `${prefix}: stories[${index}]`;
    requireCondition(
      /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(story?.storyId ?? ""),
      `${storyPrefix}.storyId must be lower-kebab-case.`,
    );
    requireCondition(!storyIds.has(story?.storyId), `${storyPrefix}.storyId is duplicated.`);
    storyIds.add(story?.storyId);
    catalogStoriesById.set(story?.storyId, story);
    requireString(story?.title, `${storyPrefix}.title`);
    requireString(story?.outcome, `${storyPrefix}.outcome`);
    requireCondition(
      typeof story?.outcome !== "string" || story.outcome.length <= 320,
      `${storyPrefix}.outcome must remain concise.`,
    );
    requireCondition(productMilestoneRanks.has(story?.milestone), `${storyPrefix}.milestone must be M3, M4, or M5.`);
    requireCondition(["required", "blocked", "retired"].includes(story?.status), `${storyPrefix}.status is invalid.`);

    const authority = story?.authority ?? {};
    const authorityPath = repositoryFile(authority.path, `${storyPrefix}.authority.path`);
    requireString(authority.section, `${storyPrefix}.authority.section`);
    requireCondition(
      canonicalTargetSpecs.has(authority.path),
      `${storyPrefix}.authority.path is not a registered canonical target spec.`,
    );
    if (authorityPath && typeof authority.section === "string") {
      requireCondition(hasHeading(authorityPath, authority.section), `${storyPrefix}.authority.section does not exist.`);
    }

    if (story?.status === "blocked") {
      const blocker = story?.blocker ?? {};
      requireStrings(blocker.decisionIds, `${storyPrefix}.blocker.decisionIds`);
      requireCondition(
        new Set(blocker.decisionIds ?? []).size === (blocker.decisionIds ?? []).length,
        `${storyPrefix}.blocker.decisionIds contains duplicates.`,
      );
      requireCondition(
        blocker.path === "docs/plans/ledger-accounting-redesign/decision-log.md",
        `${storyPrefix}.blocker.path must be the decision log.`,
      );
      const blockerPath = repositoryFile(blocker.path, `${storyPrefix}.blocker.path`);
      requireString(blocker.section, `${storyPrefix}.blocker.section`);
      requireCondition(
        blocker.section === "Open Product Decisions",
        `${storyPrefix}.blocker.section must be Open Product Decisions.`,
      );
      if (blockerPath && typeof blocker.section === "string") {
        requireCondition(hasHeading(blockerPath, blocker.section), `${storyPrefix}.blocker.section does not exist.`);
        for (const decisionId of blocker.decisionIds ?? []) {
          requireCondition(/^O-[0-9]{3}$/.test(decisionId), `${storyPrefix}: blocker decision ${decisionId} is not open.`);
          requireCondition(decisionRowExists(blockerPath, blocker.section, decisionId), `${storyPrefix}: blocker decision ${decisionId} is not present in ${blocker.section}.`);
        }
      }
      requireCondition(story.retirementAuthority === undefined, `${storyPrefix}: blocked story cannot have retirementAuthority.`);
    } else if (story?.status === "retired") {
      const retirement = story?.retirementAuthority ?? {};
      requireCondition(
        retirement.path === "docs/plans/ledger-accounting-redesign/decision-log.md",
        `${storyPrefix}.retirementAuthority.path must be the decision log.`,
      );
      const retirementPath = repositoryFile(retirement.path, `${storyPrefix}.retirementAuthority.path`);
      requireString(retirement.section, `${storyPrefix}.retirementAuthority.section`);
      requireCondition(
        retirement.section === "Confirmed Decisions",
        `${storyPrefix}.retirementAuthority.section must be Confirmed Decisions.`,
      );
      requireString(retirement.decisionId, `${storyPrefix}.retirementAuthority.decisionId`);
      if (retirementPath && typeof retirement.section === "string") {
        requireCondition(hasHeading(retirementPath, retirement.section), `${storyPrefix}.retirementAuthority.section does not exist.`);
        requireCondition(/^D-[0-9]{3}$/.test(retirement.decisionId ?? ""), `${storyPrefix}: retirement requires a confirmed D- decision.`);
        requireCondition(decisionRowExists(retirementPath, retirement.section, retirement.decisionId), `${storyPrefix}: retirement decision ${retirement.decisionId} is not present in ${retirement.section}.`);
      }
      requireCondition(story.blocker === undefined, `${storyPrefix}: retired story cannot have blocker.`);
    } else {
      requireCondition(story.blocker === undefined, `${storyPrefix}: required story cannot have blocker.`);
      requireCondition(story.retirementAuthority === undefined, `${storyPrefix}: required story cannot have retirementAuthority.`);
    }
  }

  requireCondition(Array.isArray(catalog?.deliveryRequirements), `${prefix}: deliveryRequirements must be an array.`);
  const deliveryProfiles = new Set();
  const deliveryStoryIds = new Set();
  for (const [index, requirement] of (catalog?.deliveryRequirements ?? []).entries()) {
    const requirementPrefix = `${prefix}: deliveryRequirements[${index}]`;
    requireString(requirement?.profile, `${requirementPrefix}.profile`);
    requireCondition(!deliveryProfiles.has(requirement?.profile), `${requirementPrefix}.profile is duplicated.`);
    deliveryProfiles.add(requirement?.profile);
    requireStrings(requirement?.storyIds, `${requirementPrefix}.storyIds`);
    requireStrings(requirement?.workflowKinds, `${requirementPrefix}.workflowKinds`);
    requireStrings(requirement?.requiredLayers, `${requirementPrefix}.requiredLayers`);
    requireStrings(requirement?.requiredRisks, `${requirementPrefix}.requiredRisks`);
    for (const kind of requirement?.workflowKinds ?? []) {
      requireCondition(["product_ui", "backend_control", "migration"].includes(kind), `${requirementPrefix}: invalid workflow kind ${kind}.`);
    }
    for (const layer of requirement?.requiredLayers ?? []) {
      requireCondition(layers.has(layer), `${requirementPrefix}: invalid layer ${layer}.`);
    }
    for (const risk of requirement?.requiredRisks ?? []) {
      requireCondition(risks.has(risk) && risk !== "none", `${requirementPrefix}: invalid risk ${risk}.`);
    }
    for (const storyId of requirement?.storyIds ?? []) {
      requireCondition(storyIds.has(storyId), `${requirementPrefix}: unknown story ${storyId}.`);
      requireCondition(!deliveryStoryIds.has(storyId), `${requirementPrefix}: story ${storyId} has more than one delivery requirement.`);
      deliveryStoryIds.add(storyId);
      targetDeliveryRequirementsByStory.set(storyId, requirement);
    }
  }
  requireCondition(
    deliveryStoryIds.size === storyIds.size && [...storyIds].every((storyId) => deliveryStoryIds.has(storyId)),
    `${prefix}: every target story must have exactly one delivery requirement.`,
  );

  const authorityIndexPath = join(repositoryRoot, catalog.authorityIndex);
  const indexedAuthorities = indexedSpecPaths(authorityIndexPath);
  requireCondition(Array.isArray(catalog.authorityCoverage), `${prefix}: authorityCoverage must be an array.`);
  const authorityPaths = new Set();
  const coveredStoryIds = new Set();
  let incompleteAuthorityCount = 0;
  for (const [index, entry] of (catalog.authorityCoverage ?? []).entries()) {
    const entryPrefix = `${prefix}: authorityCoverage[${index}]`;
    requireString(entry?.path, `${entryPrefix}.path`);
    requireCondition(!authorityPaths.has(entry?.path), `${entryPrefix}.path is duplicated.`);
    authorityPaths.add(entry?.path);
    requireCondition(indexedAuthorities.has(entry?.path), `${entryPrefix}.path is not in the authority index.`);
    const authorityFile = repositoryFile(entry?.path, `${entryPrefix}.path`);
    requireCondition(/^[0-9a-f]{64}$/.test(entry?.sourceHash ?? ""), `${entryPrefix}.sourceHash must be SHA-256.`);
    if (authorityFile && /^[0-9a-f]{64}$/.test(entry?.sourceHash ?? "")) {
      requireCondition(
        sha256(authorityFile) === entry.sourceHash,
        `${entryPrefix}: sourceHash is stale; re-audit this authority after its content changed.`,
      );
    }
    requireCondition(
      ["audited", "partial", "source_only"].includes(entry?.auditStatus),
      `${entryPrefix}.auditStatus must be audited, partial, or source_only.`,
    );
    if (entry?.storyIds !== undefined) {
      requireStrings(entry.storyIds, `${entryPrefix}.storyIds`, { allowEmpty: true });
    }
    if (entry?.auditStatus === "source_only") {
      requireCondition(allowedSourceOnlyAuthorities.has(entry.path), `${entryPrefix}: source_only is not approved for this authority.`);
      requireCondition((entry.storyIds ?? []).length === 0, `${entryPrefix}: source_only authority cannot claim target stories.`);
      requireString(entry?.reason, `${entryPrefix}.reason`);
    } else {
      if (entry.auditStatus === "partial") incompleteAuthorityCount += 1;
    }
    if (entry?.auditStatus === "audited") {
      requireCondition(Array.isArray(entry.headingCoverage), `${entryPrefix}: audited authority requires headingCoverage.`);
      const expectedHeadings = authorityFile ? markdownHeadingInventory(authorityFile) : [];
      const expectedHeadingKeys = new Set(expectedHeadings.map(headingInventoryKey));
      const recordedHeadingKeys = new Set();
      const headingStoryIds = new Set();
      for (const [headingIndex, headingEntry] of (entry.headingCoverage ?? []).entries()) {
        const headingPrefix = `${entryPrefix}.headingCoverage[${headingIndex}]`;
        requireString(headingEntry?.heading, `${headingPrefix}.heading`);
        requireCondition(Number.isInteger(headingEntry?.occurrence) && headingEntry.occurrence > 0, `${headingPrefix}.occurrence must be positive.`);
        requireCondition(["story", "supporting_or_nonproduct"].includes(headingEntry?.disposition), `${headingPrefix}.disposition is invalid.`);
        const key = headingInventoryKey(headingEntry ?? {});
        requireCondition(!recordedHeadingKeys.has(key), `${headingPrefix}: heading occurrence is duplicated.`);
        recordedHeadingKeys.add(key);
        requireCondition(expectedHeadingKeys.has(key), `${headingPrefix}: heading occurrence is not in the current authority file.`);
        if (headingEntry?.disposition === "story") {
          requireStrings(headingEntry?.storyIds, `${headingPrefix}.storyIds`);
          for (const storyId of headingEntry?.storyIds ?? []) {
            // A heading may restate a story owned by a companion spec. Keep
            // one canonical owner while allowing explicit shared references.
            requireCondition(catalogStoriesById.has(storyId), `${headingPrefix}: unknown story ${storyId}.`);
            headingStoryIds.add(storyId);
          }
          requireCondition(headingEntry?.reason === undefined, `${headingPrefix}: story disposition cannot use a reason instead of storyIds.`);
        } else {
          requireString(headingEntry?.reason, `${headingPrefix}.reason`);
          requireCondition((headingEntry?.storyIds ?? []).length === 0, `${headingPrefix}: supporting_or_nonproduct cannot claim stories.`);
        }
      }
      requireCondition(
        recordedHeadingKeys.size === expectedHeadingKeys.size &&
          [...expectedHeadingKeys].every((key) => recordedHeadingKeys.has(key)),
        `${entryPrefix}: headingCoverage must account for every current Markdown heading exactly once.`,
      );
      // Companion specs may clarify canonical stories without owning new ones.
      // Require real story references; ownership stays unique below.
      requireCondition(headingStoryIds.size > 0, `${entryPrefix}: audited authority must map at least one story.`);
      for (const storyId of entry.storyIds ?? []) {
        requireCondition(headingStoryIds.has(storyId), `${entryPrefix}: audited story ${storyId} is absent from headingCoverage.`);
      }
    } else {
      requireCondition(entry?.headingCoverage === undefined, `${entryPrefix}: headingCoverage is allowed only after the authority is audited.`);
    }
    for (const storyId of entry?.storyIds ?? []) {
      requireCondition(!coveredStoryIds.has(storyId), `${entryPrefix}: story ${storyId} is mapped by more than one authority entry.`);
      coveredStoryIds.add(storyId);
      const story = catalogStoriesById.get(storyId);
      requireCondition(Boolean(story), `${entryPrefix}: unknown story ${storyId}.`);
      requireCondition(story?.authority?.path === entry.path, `${entryPrefix}: story ${storyId} authority path does not match.`);
    }
  }
  requireCondition(
    authorityPaths.size === indexedAuthorities.size && [...indexedAuthorities].every((path) => authorityPaths.has(path)),
    `${prefix}: authorityCoverage must account for every indexed spec exactly once.`,
  );
  requireCondition(
    coveredStoryIds.size === storyIds.size && [...storyIds].every((storyId) => coveredStoryIds.has(storyId)),
    `${prefix}: every target story must appear exactly once in authorityCoverage.`,
  );

  const decisionLogPath = join(repositoryRoot, "docs/plans/ledger-accounting-redesign/decision-log.md");
  const expectedDecisionSets = new Map([
    ["confirmed", decisionIdsInSection(decisionLogPath, "Confirmed Decisions", prefix)],
    ["open", decisionIdsInSection(decisionLogPath, "Open Product Decisions", prefix)],
  ]);
  const openDecisionStoryLinks = new Map();
  const openDecisionEntriesById = new Map();
  let pendingDecisionCount = 0;
  for (const [group, expectedIds] of expectedDecisionSets) {
    const entries = catalog?.decisionCoverage?.[group];
    requireCondition(Array.isArray(entries), `${prefix}: decisionCoverage.${group} must be an array.`);
    const recordedIds = new Set();
    for (const [index, entry] of (entries ?? []).entries()) {
      const entryPrefix = `${prefix}: decisionCoverage.${group}[${index}]`;
      requireString(entry?.decisionId, `${entryPrefix}.decisionId`);
      requireCondition(!recordedIds.has(entry?.decisionId), `${entryPrefix}.decisionId is duplicated.`);
      recordedIds.add(entry?.decisionId);
      requireCondition(expectedIds.has(entry?.decisionId), `${entryPrefix}.decisionId is not in the declared decision-log section.`);
      if (group === "open") openDecisionEntriesById.set(entry.decisionId, entry);
      requireCondition(["mapped", "pending"].includes(entry?.auditStatus), `${entryPrefix}.auditStatus must be mapped or pending.`);
      if (entry?.storyIds !== undefined) {
        requireStrings(entry.storyIds, `${entryPrefix}.storyIds`, { allowEmpty: true });
      }
      if (entry?.auditStatus === "mapped") {
        requireCondition((entry.storyIds ?? []).length > 0, `${entryPrefix}: mapped decision requires storyIds.`);
        for (const storyId of entry.storyIds ?? []) {
          requireCondition(storyIds.has(storyId), `${entryPrefix}: unknown story ${storyId}.`);
          if (group === "open") {
            const story = catalogStoriesById.get(storyId);
            requireCondition(story?.status === "blocked", `${entryPrefix}: open decision may map only to a blocked story.`);
            requireCondition(
              (story?.blocker?.decisionIds ?? []).includes(entry.decisionId),
              `${entryPrefix}: blocked story ${storyId} does not declare ${entry.decisionId}.`,
            );
            if (!openDecisionStoryLinks.has(entry.decisionId)) openDecisionStoryLinks.set(entry.decisionId, new Set());
            openDecisionStoryLinks.get(entry.decisionId).add(storyId);
          }
        }
      } else {
        pendingDecisionCount += 1;
      }
    }
    requireCondition(
      recordedIds.size === expectedIds.size && [...expectedIds].every((id) => recordedIds.has(id)),
      `${prefix}: decisionCoverage.${group} must account for every ${group} decision exactly once.`,
    );
  }
  for (const story of catalog?.stories ?? []) {
    if (story.status !== "blocked") continue;
    for (const decisionId of story.blocker?.decisionIds ?? []) {
      const decisionEntry = openDecisionEntriesById.get(decisionId);
      requireCondition(
        decisionEntry?.auditStatus === "pending" ||
          (openDecisionStoryLinks.get(decisionId)?.has(story.storyId) ?? false),
        `${prefix}: blocked story ${story.storyId} lacks reverse mapped decisionCoverage.open evidence for ${decisionId}.`,
      );
    }
  }
  if (catalog?.completeness?.status === "complete") {
    requireCondition(incompleteAuthorityCount === 0, `${prefix}: complete catalog cannot contain partial authority audits.`);
    requireCondition(pendingDecisionCount === 0, `${prefix}: complete catalog cannot contain pending decision audits.`);
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

  if (record?.implementationEvidence !== undefined) {
    requireCondition(Array.isArray(record.implementationEvidence), `${prefix}: implementationEvidence must be an array.`);
  }
  const evidenceLayers = new Set();
  for (const [index, evidence] of (record?.implementationEvidence ?? []).entries()) {
    const evidencePrefix = `${prefix}: implementationEvidence[${index}]`;
    requireCondition(layers.has(evidence?.layer), `${evidencePrefix}.layer is invalid.`);
    requireCondition(!evidenceLayers.has(evidence?.layer), `${evidencePrefix}.layer is duplicated.`);
    evidenceLayers.add(evidence?.layer);
    requireStrings(evidence?.paths, `${evidencePrefix}.paths`);
    requireCondition(new Set(evidence?.paths ?? []).size === (evidence?.paths ?? []).length, `${evidencePrefix}.paths contains duplicates.`);
    for (const [pathIndex, path] of (evidence?.paths ?? []).entries()) {
      repositoryFile(path, `${evidencePrefix}.paths[${pathIndex}]`);
      requireCondition(
        (record?.affectedComponents ?? []).some(
          (component) => path === component || path.startsWith(`${component}/`),
        ),
        `${evidencePrefix}: ${path} is outside affectedComponents.`,
      );
      requireCondition(pathSupportsLayer(path, evidence?.layer), `${evidencePrefix}: ${path} is not concrete evidence for ${evidence?.layer}.`);
    }
  }

  requireStrings(record?.layers, `${prefix}: layers`);
  for (const layer of record?.layers ?? []) {
    requireCondition(layers.has(layer), `${prefix}: unknown layer ${layer}.`);
  }
  requireCondition(
    new Set(record?.layers ?? []).size === (record?.layers ?? []).length,
    `${prefix}: layers must not contain duplicates.`,
  );
  for (const evidenceLayer of evidenceLayers) {
    requireCondition((record?.layers ?? []).includes(evidenceLayer), `${prefix}: implementationEvidence declares undeclared layer ${evidenceLayer}.`);
  }
  if (record?.status === "complete" && (record?.targetStoryIds ?? []).length > 0) {
    requireCondition((record?.implementationEvidence ?? []).length > 0, `${prefix}: completed target stories require concrete implementationEvidence.`);
    for (const layer of record?.layers ?? []) {
      requireCondition(evidenceLayers.has(layer), `${prefix}: completed target workflow lacks concrete file evidence for layer ${layer}.`);
    }
  }

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
    const controlLabels = new Set();
    for (const [controlIndex, control] of (journey?.controls ?? []).entries()) {
      const controlPrefix = `${journeyPrefix}.controls[${controlIndex}]`;
      requireString(control?.label, `${controlPrefix}.label`);
      requireCondition(!controlLabels.has(control?.label), `${controlPrefix}.label is duplicated in the journey.`);
      controlLabels.add(control?.label);
      requireCondition(Array.isArray(control?.options), `${controlPrefix}.options must be an array.`);
      const optionLabels = new Set();
      for (const [optionIndex, option] of (control?.options ?? []).entries()) {
        const optionPrefix = `${controlPrefix}.options[${optionIndex}]`;
        requireString(option?.label, `${optionPrefix}.label`);
        requireCondition(!optionLabels.has(option?.label), `${optionPrefix}.label is duplicated in the control.`);
        optionLabels.add(option?.label);
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
    const transitionReferences = new Set();
    for (const [transitionIndex, transition] of (journey?.transitions ?? []).entries()) {
      const transitionPrefix = `${journeyPrefix}.transitions[${transitionIndex}]`;
      requireString(transition?.from, `${transitionPrefix}.from`);
      requireString(transition?.event, `${transitionPrefix}.event`);
      requireString(transition?.to, `${transitionPrefix}.to`);
      const transitionReference = baselineTransitionReference(transition);
      requireCondition(!transitionReferences.has(transitionReference), `${transitionPrefix} is duplicated in the journey.`);
      transitionReferences.add(transitionReference);
      requireCondition(
        ["preserve", "redesign", "retire"].includes(transition?.disposition),
        `${transitionPrefix}.disposition is not allowed.`,
      );
    }
    requireCondition(
      Array.isArray(journey?.states) && journey.states.length > 0,
      `${journeyPrefix}.states must not be empty.`,
    );
    const stateNames = new Set();
    for (const [stateIndex, state] of (journey?.states ?? []).entries()) {
      const statePrefix = `${journeyPrefix}.states[${stateIndex}]`;
      requireString(state?.name, `${statePrefix}.name`);
      requireString(state?.expected, `${statePrefix}.expected`);
      requireCondition(!stateNames.has(state?.name), `${statePrefix}.name is duplicated in the journey.`);
      stateNames.add(state?.name);
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
    requireCondition(
      record?.catalogRole === "authoritative_current_behavior_checklist",
      `${prefix}: coverage audit must declare the Product Behavior Catalog role.`,
    );
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
    if (check?.coversBehaviorRefs !== undefined) {
      requireStrings(check.coversBehaviorRefs, `${checkPrefix}.coversBehaviorRefs`, { allowEmpty: true });
      requireCondition(
        new Set(check.coversBehaviorRefs).size === check.coversBehaviorRefs.length,
        `${checkPrefix}.coversBehaviorRefs contains duplicates.`,
      );
    }
    if (check?.coversStoryIds !== undefined) {
      requireStrings(check.coversStoryIds, `${checkPrefix}.coversStoryIds`, { allowEmpty: true });
      requireCondition(
        new Set(check.coversStoryIds).size === check.coversStoryIds.length,
        `${checkPrefix}.coversStoryIds contains duplicates.`,
      );
    }
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
        execFileSync("git", ["merge-base", "--is-ancestor", verification.ci.commit, "HEAD"], {
          cwd: repositoryRoot,
          stdio: "ignore",
        });
        if (requestedProductGate) {
          const committedRecord = JSON.parse(
            execFileSync("git", ["show", `${verification.ci.commit}:${relativePath}`], {
              cwd: repositoryRoot,
              encoding: "utf8",
            }),
          );
          requireCondition(
            JSON.stringify(canonicalJson(workflowEvidencePayload(committedRecord))) ===
              JSON.stringify(canonicalJson(workflowEvidencePayload(record))),
            `${prefix}: completion evidence changed since its exact CI commit; rerun CI for the amended workflow.`,
          );
          validateGithubCompletionRun(verification.ci.commit, verification.ci.run, prefix);
        }
      } catch {
        errors.push(`${prefix}: verification.ci.commit is missing, not an ancestor of HEAD, or does not contain this workflow record.`);
      }
    }
  }
}

function validateWorkflowSet(
  records,
  storiesById = targetStoriesById,
  baselineExpectation = {
    workflowId: "current-app-ui-control-flow-baseline",
    journeys: 91,
    behaviors: 1_919,
  },
) {
  const authoritativeBaselines = records.filter(
    (record) =>
      record.kind === "coverage_audit" &&
      record.status === "complete" &&
      record.uiCoverage?.scope === "all_current_app_ui" &&
      record.catalogRole === "authoritative_current_behavior_checklist",
  );
  requireCondition(
    authoritativeBaselines.length === 1 &&
      authoritativeBaselines[0]?.workflowId === baselineExpectation.workflowId,
    `Exactly one authoritative Product Behavior Catalog must exist with workflowId ${baselineExpectation.workflowId}.`,
  );
  const completedUiBaseline = authoritativeBaselines[0];
  requireCondition(
    completedUiBaseline?.sourceBaseline?.branch === "firebase",
    "Product Behavior Catalog sourceBaseline.branch must be firebase.",
  );
  requireCondition(
    /^[0-9a-f]{40}$/.test(completedUiBaseline?.sourceBaseline?.commit ?? ""),
    "Product Behavior Catalog sourceBaseline.commit must be exact.",
  );
  if (/^[0-9a-f]{40}$/.test(completedUiBaseline?.sourceBaseline?.commit ?? "")) {
    try {
      execFileSync("git", ["cat-file", "-e", `${completedUiBaseline.sourceBaseline.commit}^{commit}`], {
        cwd: repositoryRoot,
        stdio: "ignore",
      });
    } catch {
      errors.push("Product Behavior Catalog sourceBaseline.commit is missing from local Git history.");
    }
  }
  const baselineJourneyIds = new Set(
    (completedUiBaseline?.uiJourneys ?? []).map((journey) => journey.journeyId),
  );
  const baselineJourneys = new Map(
    (completedUiBaseline?.uiJourneys ?? []).map((journey) => [journey.journeyId, journey]),
  );
  const claimedBehaviorKeys = new Set();
  const verifiedBehaviorKeys = new Set();
  const claimedStoryIds = new Set();
  const verifiedStoryIds = new Set();

  // Target stories may be delivered by UI, backend/control, or migration
  // workflows. Current-product behavior obligations remain UI-only.
  for (const record of records) {
    if (record.kind === "coverage_audit") continue;
    const hasTargetStories = record.targetStoryIds !== undefined;
    if (record.kind === "product_ui" || hasTargetStories) {
      requireStrings(record.targetStoryIds, `${record.workflowId}: targetStoryIds`);
      requireCondition(
        new Set(record.targetStoryIds ?? []).size === (record.targetStoryIds ?? []).length,
        `${record.workflowId}: targetStoryIds contains duplicates.`,
      );
    }
    const recordTargetStoryIds = new Set(record.targetStoryIds ?? []);
    for (const storyId of recordTargetStoryIds) {
      requireCondition(storiesById.has(storyId), `${record.workflowId}: unknown target story ${storyId}.`);
      claimedStoryIds.add(storyId);
      if (record.status === "complete") {
        const story = storiesById.get(storyId);
        requireCondition(story?.status !== "blocked", `${record.workflowId}: complete workflow cites blocked target story ${storyId}.`);
        requireCondition(story?.status !== "retired", `${record.workflowId}: complete workflow must not implement retired target story ${storyId}.`);
        const requirement = targetDeliveryRequirementsByStory.get(storyId);
        const kindMatches = requirement?.workflowKinds?.includes(record.kind) ?? false;
        const missingLayers = (requirement?.requiredLayers ?? []).filter(
          (layer) => !(record.layers ?? []).includes(layer),
        );
        const missingRisks = (requirement?.requiredRisks ?? []).filter(
          (risk) => !(record.riskDomains ?? []).includes(risk),
        );
        const evidenceLayers = new Set(
          (record.implementationEvidence ?? []).map((entry) => entry.layer),
        );
        const missingLayerEvidence = (requirement?.requiredLayers ?? []).filter(
          (layer) => !evidenceLayers.has(layer),
        );
        const missingRiskEvidence = (requirement?.requiredRisks ?? []).filter(
          (risk) => !(record.acceptanceChecks ?? []).some(
            (check) =>
              check.status === "passed" &&
              check.risk === risk &&
              (check.coversStoryIds ?? []).includes(storyId),
          ),
        );
        requireCondition(kindMatches, `${record.workflowId}: target story ${storyId} requires workflow kind ${(requirement?.workflowKinds ?? []).join(" or ")}.`);
        requireCondition(missingLayers.length === 0, `${record.workflowId}: target story ${storyId} lacks required layers: ${missingLayers.join(", ")}.`);
        requireCondition(missingRisks.length === 0, `${record.workflowId}: target story ${storyId} lacks required risks: ${missingRisks.join(", ")}.`);
        requireCondition(missingLayerEvidence.length === 0, `${record.workflowId}: target story ${storyId} lacks concrete file evidence for layers: ${missingLayerEvidence.join(", ")}.`);
        requireCondition(missingRiskEvidence.length === 0, `${record.workflowId}: target story ${storyId} lacks passed story-specific checks for risks: ${missingRiskEvidence.join(", ")}.`);
        if (
          story?.status === "required" &&
          kindMatches &&
          missingLayers.length === 0 &&
          missingRisks.length === 0 &&
          missingLayerEvidence.length === 0 &&
          missingRiskEvidence.length === 0
        ) {
          verifiedStoryIds.add(storyId);
        }
      }
    }
    const passedStoryCoverage = new Set();
    for (const check of record.acceptanceChecks ?? []) {
      for (const storyId of check.coversStoryIds ?? []) {
        requireCondition(recordTargetStoryIds.has(storyId), `${record.workflowId}: acceptance check ${check.id} covers unclaimed story ${storyId}.`);
        if (check.status === "passed") passedStoryCoverage.add(storyId);
      }
    }
    if (record.status === "complete") {
      for (const storyId of recordTargetStoryIds) {
        requireCondition(passedStoryCoverage.has(storyId), `${record.workflowId}: completed workflow target story lacks passed acceptance coverage: ${storyId}.`);
      }
    }
  }

  for (const record of records) {
    if (record.kind !== "product_ui") continue;
    requireCondition(
      Boolean(completedUiBaseline),
      `${record.workflowId}: product UI work requires the Product Behavior Catalog.`,
    );
    const recordTargetStoryIds = new Set(record.targetStoryIds ?? []);
    const hasBaselineBehavior =
      Array.isArray(record.baselineBehaviorRefs) && record.baselineBehaviorRefs.length > 0;
    const hasNoCurrentBaselineReason =
      typeof record.noCurrentBaselineReason === "string" && record.noCurrentBaselineReason.trim().length > 0;
    requireCondition(
      hasBaselineBehavior !== hasNoCurrentBaselineReason,
      `${record.workflowId}: provide exact baselineBehaviorRefs or one explicit noCurrentBaselineReason, but not both.`,
    );
    const referencedJourneyIds = new Set();
    const recordBehaviorKeys = new Set();
    if (hasBaselineBehavior) {
      requireStrings(record.baselineJourneyIds, `${record.workflowId}: baselineJourneyIds`);
      requireCondition(
        new Set(record.baselineJourneyIds ?? []).size === (record.baselineJourneyIds ?? []).length,
        `${record.workflowId}: baselineJourneyIds contains duplicates.`,
      );
      for (const journeyId of record.baselineJourneyIds ?? []) {
        requireCondition(
          baselineJourneyIds.has(journeyId),
          `${record.workflowId}: unknown baseline journey ${journeyId}.`,
        );
      }

      for (const [referenceIndex, reference] of (record.baselineBehaviorRefs ?? []).entries()) {
        const referencePrefix = `${record.workflowId}: baselineBehaviorRefs[${referenceIndex}]`;
        requireString(reference?.journeyId, `${referencePrefix}.journeyId`);
        requireCondition(
          !referencedJourneyIds.has(reference?.journeyId),
          `${referencePrefix}: journey is referenced twice.`,
        );
        referencedJourneyIds.add(reference?.journeyId);
        const journey = baselineJourneys.get(reference?.journeyId);
        requireCondition(Boolean(journey), `${referencePrefix}: unknown journey ${reference?.journeyId}.`);

        requireCondition(Array.isArray(reference?.controls), `${referencePrefix}.controls must be an array.`);
        requireStrings(reference?.transitions, `${referencePrefix}.transitions`, { allowEmpty: true });
        requireStrings(reference?.states, `${referencePrefix}.states`, { allowEmpty: true });
        let referenceBehaviorCount = 0;
        const referencedControls = new Set();
        for (const [controlIndex, controlReference] of (reference?.controls ?? []).entries()) {
          const controlPrefix = `${referencePrefix}.controls[${controlIndex}]`;
          requireString(controlReference?.label, `${controlPrefix}.label`);
          requireCondition(
            typeof controlReference?.includeControl === "boolean",
            `${controlPrefix}.includeControl must be boolean.`,
          );
          requireStrings(controlReference?.options, `${controlPrefix}.options`, { allowEmpty: true });
          requireCondition(
            !referencedControls.has(controlReference?.label),
            `${controlPrefix}: control is referenced twice.`,
          );
          referencedControls.add(controlReference?.label);
          const catalogControl = (journey?.controls ?? []).find(
            (candidate) => candidate.label === controlReference?.label,
          );
          requireCondition(Boolean(catalogControl), `${controlPrefix}: unknown catalog control ${controlReference?.label}.`);
          if (controlReference?.includeControl) {
            const key = catalogBehaviorKey(reference.journeyId, "control", controlReference.label);
            requireCondition(!recordBehaviorKeys.has(key), `${controlPrefix}: duplicate behavior claim.`);
            recordBehaviorKeys.add(key);
            referenceBehaviorCount += 1;
          }
          const optionLabels = new Set((catalogControl?.options ?? []).map((option) => option.label));
          const referencedOptions = new Set();
          for (const option of controlReference?.options ?? []) {
            requireCondition(optionLabels.has(option), `${controlPrefix}: unknown option ${option}.`);
            requireCondition(!referencedOptions.has(option), `${controlPrefix}: option ${option} is referenced twice.`);
            referencedOptions.add(option);
            const key = catalogBehaviorKey(reference.journeyId, "option", controlReference.label, option);
            requireCondition(!recordBehaviorKeys.has(key), `${controlPrefix}: duplicate option behavior claim.`);
            recordBehaviorKeys.add(key);
            referenceBehaviorCount += 1;
          }
        }

        const transitionKeys = new Set(
          (journey?.transitions ?? []).map((transition) => baselineTransitionReference(transition)),
        );
        const referencedTransitions = new Set();
        for (const transition of reference?.transitions ?? []) {
          requireCondition(transitionKeys.has(transition), `${referencePrefix}: unknown transition ${transition}.`);
          requireCondition(!referencedTransitions.has(transition), `${referencePrefix}: transition is referenced twice.`);
          referencedTransitions.add(transition);
          const key = catalogBehaviorKey(reference.journeyId, "transition", transition);
          requireCondition(!recordBehaviorKeys.has(key), `${referencePrefix}: duplicate transition behavior claim.`);
          recordBehaviorKeys.add(key);
          referenceBehaviorCount += 1;
        }

        const stateNames = new Set((journey?.states ?? []).map((state) => state.name));
        const referencedStates = new Set();
        for (const stateName of reference?.states ?? []) {
          requireCondition(stateNames.has(stateName), `${referencePrefix}: unknown state ${stateName}.`);
          requireCondition(!referencedStates.has(stateName), `${referencePrefix}: state is referenced twice.`);
          referencedStates.add(stateName);
          const key = catalogBehaviorKey(reference.journeyId, "state", stateName);
          requireCondition(!recordBehaviorKeys.has(key), `${referencePrefix}: duplicate state behavior claim.`);
          recordBehaviorKeys.add(key);
          referenceBehaviorCount += 1;
        }
        requireCondition(referenceBehaviorCount > 0, `${referencePrefix}: no catalog behavior is claimed.`);
      }

      requireCondition(
        referencedJourneyIds.size === (record.baselineJourneyIds ?? []).length &&
          (record.baselineJourneyIds ?? []).every((journeyId) => referencedJourneyIds.has(journeyId)),
        `${record.workflowId}: baselineJourneyIds and baselineBehaviorRefs journeys must match exactly.`,
      );
    } else {
      requireCondition(
        !Array.isArray(record.baselineJourneyIds) || record.baselineJourneyIds.length === 0,
        `${record.workflowId}: target-only workflow cannot cite baselineJourneyIds.`,
      );
      requireCondition(
        !Array.isArray(record.baselineBehaviorRefs) || record.baselineBehaviorRefs.length === 0,
        `${record.workflowId}: target-only workflow cannot cite baselineBehaviorRefs.`,
      );
    }

    const passedBehaviorCoverage = new Set();
    const passedStoryCoverage = new Set();
    for (const check of record.acceptanceChecks ?? []) {
      for (const key of check.coversBehaviorRefs ?? []) {
        requireCondition(recordBehaviorKeys.has(key), `${record.workflowId}: acceptance check ${check.id} covers unclaimed behavior ${key}.`);
        if (check.status === "passed") passedBehaviorCoverage.add(key);
      }
      for (const storyId of check.coversStoryIds ?? []) {
        requireCondition(recordTargetStoryIds.has(storyId), `${record.workflowId}: acceptance check ${check.id} covers unclaimed story ${storyId}.`);
        if (check.status === "passed") passedStoryCoverage.add(storyId);
      }
    }

    if (record.status === "complete") {
      for (const key of recordBehaviorKeys) {
        requireCondition(passedBehaviorCoverage.has(key), `${record.workflowId}: completed workflow behavior lacks passed acceptance coverage: ${key}.`);
      }
      for (const storyId of recordTargetStoryIds) {
        requireCondition(passedStoryCoverage.has(storyId), `${record.workflowId}: completed workflow target story lacks passed acceptance coverage: ${storyId}.`);
      }
    }

    for (const key of recordBehaviorKeys) {
      claimedBehaviorKeys.add(key);
      if (record.status === "complete") verifiedBehaviorKeys.add(key);
    }
  }

  const totalBehaviorKeys = catalogBehaviorKeys(completedUiBaseline);
  requireCondition(
    baselineJourneyIds.size === baselineExpectation.journeys &&
      totalBehaviorKeys.size === baselineExpectation.behaviors,
    `Product Behavior Catalog baseline changed from the reviewed ${baselineExpectation.journeys} journeys / ${baselineExpectation.behaviors} exact behaviors; re-audit and deliberately update the checker threshold.`,
  );
  return {
    journeys: baselineJourneyIds.size,
    total: totalBehaviorKeys.size,
    claimed: claimedBehaviorKeys.size,
    verified: verifiedBehaviorKeys.size,
    claimedBehaviorKeys,
    verifiedBehaviorKeys,
    claimedStoryIds,
    verifiedStoryIds,
    sourceBaseline: completedUiBaseline?.sourceBaseline,
  };
}

function productGateBlockers(summary, catalog, requestedMilestone) {
  const requestedRank = productMilestoneRanks.get(requestedMilestone);
  if (!requestedRank) return [`Unknown product milestone ${requestedMilestone}.`];
  const blockers = [];
  if (summary?.sourceBaseline?.branch !== "firebase" || !/^[0-9a-f]{40}$/.test(summary?.sourceBaseline?.commit ?? "")) {
    blockers.push("Product Behavior Catalog lacks an exact Firebase source baseline.");
  } else {
    const currentFirebaseCommit = remoteBranchCommit("firebase", "Product Behavior Catalog");
    if (!currentFirebaseCommit) {
      blockers.push("Unable to verify the current Firebase source baseline; retry when the remote can be read.");
    }
    if (currentFirebaseCommit && currentFirebaseCommit !== summary.sourceBaseline.commit) {
      blockers.push(
        `Product Behavior Catalog covers Firebase ${summary.sourceBaseline.commit}, but origin/firebase is ${currentFirebaseCommit}; refresh and re-review current behavior.`,
      );
    }
  }
  if (catalog?.completeness?.status !== "complete") {
    blockers.push(`Target story catalog is ${catalog?.completeness?.status ?? "invalid"}, not complete.`);
  }
  if (summary.verified !== summary.total) {
    blockers.push(`Product Behavior Catalog is ${summary.verified}/${summary.total} verified.`);
  }
  for (const story of catalog?.stories ?? []) {
    if ((productMilestoneRanks.get(story.milestone) ?? Infinity) > requestedRank) continue;
    if (story.status === "retired") continue;
    if (story.status === "blocked") {
      blockers.push(`${story.storyId} is blocked by ${(story.blocker?.decisionIds ?? []).join(", ") || "an unresolved decision"}.`);
    } else if (!summary.verifiedStoryIds.has(story.storyId)) {
      blockers.push(`${story.storyId} is not verified by a complete workflow.`);
    }
  }
  return blockers;
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
    catalogRole: "authoritative_current_behavior_checklist",
    sourceBaseline: {
      branch: "firebase",
      commit: "fe018501d67cc84b6f140b2645b8a8149ea5c4f6",
    },
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
  const validateSelfWorkflowSet = (records) => validateWorkflowSet(
    records,
    targetStoriesById,
    { workflowId: "self-test-ui-baseline", journeys: 1, behaviors: 4 },
  );

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
    targetStoryIds: ["space-checklist-toggle"],
    baselineJourneyIds: ["self-journey"],
    baselineBehaviorRefs: [
      {
        journeyId: "self-journey",
        controls: [{ label: "Control", includeControl: true, options: ["Option"] }],
        transitions: ["A | Act | B"],
        states: ["Ready"],
      },
    ],
    verification: {
      local: { status: "not_run", commands: [] },
      review: { required: false, status: "not_required", summary: "UI-only self-test." },
      ci: { status: "not_run", commit: null, run: null },
    },
  };
  delete product.uiCoverage;
  expectFailure("missing completed baseline", () => validateSelfWorkflowSet([baseCoverage, product]), /requires the Product Behavior Catalog/);

  expectFailure("journey-only product coverage", () => {
    const value = structuredClone(product);
    delete value.baselineBehaviorRefs;
    const completeBaseline = structuredClone(baseCoverage);
    completeBaseline.status = "complete";
    completeBaseline.uiCoverage.uncoveredSurfaceIds = [];
    completeBaseline.uiJourneys = [{ ...structuredClone(journey), sourceSurfaceIds: allUiIds }];
    validateSelfWorkflowSet([completeBaseline, value]);
  }, /provide exact baselineBehaviorRefs or one explicit noCurrentBaselineReason/);

  const completeBaseline = structuredClone(baseCoverage);
  completeBaseline.status = "complete";
  completeBaseline.uiCoverage.uncoveredSurfaceIds = [];
  completeBaseline.uiJourneys = [{ ...structuredClone(journey), sourceSurfaceIds: allUiIds }];

  expectFailure("completed workflow uncovered claim", () => {
    const value = structuredClone(product);
    value.status = "complete";
    value.acceptanceChecks.forEach((check) => { check.status = "passed"; });
    validateSelfWorkflowSet([completeBaseline, value]);
  }, /completed workflow behavior lacks passed acceptance coverage/);

  expectFailure("target-only workflow missing reason", () => {
    const value = structuredClone(product);
    delete value.baselineJourneyIds;
    delete value.baselineBehaviorRefs;
    validateSelfWorkflowSet([completeBaseline, value]);
  }, /explicit noCurrentBaselineReason/);

  {
    const start = errors.length;
    const value = structuredClone(product);
    delete value.baselineJourneyIds;
    delete value.baselineBehaviorRefs;
    value.noCurrentBaselineReason = "This target-only workflow has no shipped control or state.";
    validateSelfWorkflowSet([completeBaseline, value]);
    const messages = errors.splice(start);
    if (messages.length > 0) {
      throw new Error(`target-only workflow with reason failed unexpectedly: ${messages.join(" | ")}`);
    }
  }

  expectFailure("migration cannot satisfy UI story", () => {
    const migrationWorkflow = {
      workflowId: "self-test-wrong-kind-story",
      kind: "migration",
      status: "complete",
      targetStoryIds: ["space-checklist-toggle"],
      layers: ["domain", "app_ui", "postgres_schema", "postgres_handler", "rls", "powersync_sync", "local_offline"],
      riskDomains: ["ui_fidelity", "database_integrity", "handler_idempotency", "tenant_authorization", "sync_visibility", "offline_durability"],
      acceptanceChecks: [{ id: "SELF-WRONG-KIND", status: "passed", coversStoryIds: ["space-checklist-toggle"] }],
    };
    validateSelfWorkflowSet([completeBaseline, migrationWorkflow]);
  }, /requires workflow kind product_ui/);

  expectFailure("duplicate authoritative baseline", () => {
    const duplicate = structuredClone(completeBaseline);
    duplicate.workflowId = "self-test-ui-baseline-duplicate";
    validateSelfWorkflowSet([completeBaseline, duplicate]);
  }, /Exactly one authoritative Product Behavior Catalog/);

  expectFailure("complete catalog with pending audits", () => {
    const value = structuredClone(targetStoryCatalog);
    value.completeness.status = "complete";
    validateTargetStoryCatalog(value, "self-test-incomplete-target-catalog");
  }, /complete catalog cannot contain partial authority audits/);

  expectFailure("blocked story uses wrong decision section", () => {
    const value = structuredClone(targetStoryCatalog);
    const blocked = value.stories.find((story) => story.status === "blocked");
    blocked.blocker.section = "Confirmed Decisions";
    validateTargetStoryCatalog(value, "self-test-wrong-decision-section");
  }, /blocker.section must be Open Product Decisions/);

  {
    const blockers = productGateBlockers(
      { total: 1, verified: 1, verifiedStoryIds: new Set(["m4-story"]) },
      {
        completeness: { status: "complete" },
        stories: [
          { storyId: "m3-story", milestone: "M3", status: "required" },
          { storyId: "m4-story", milestone: "M4", status: "required" },
        ],
      },
      "M4",
    );
    if (!blockers.some((message) => /m3-story is not verified/.test(message))) {
      throw new Error("M4 failed to accumulate the unverified M3 story.");
    }
  }

  {
    const start = errors.length;
    const migrationRequirement = targetDeliveryRequirementsByStory.get("non-item-line-migration");
    const migrationWorkflow = {
      workflowId: "self-test-migration-story",
      kind: "migration",
      status: "complete",
      targetStoryIds: ["non-item-line-migration"],
      layers: [...migrationRequirement.requiredLayers],
      riskDomains: [...migrationRequirement.requiredRisks],
      implementationEvidence: migrationRequirement.requiredLayers.map((layer) => ({
        layer,
        paths: ["supabase/migrations/20260907050142_active_space_checklist_item_toggle.sql"],
      })),
      acceptanceChecks: migrationRequirement.requiredRisks.map((risk) => ({
        id: `SELF-MIGRATION-STORY-${risk}`,
        risk,
        status: "passed",
        coversStoryIds: ["non-item-line-migration"],
      })),
    };
    // Exercise non-UI delivery without declaring the real product decisions
    // resolved. Synthetic evidence checks validator shape, not implementation.
    const fixtureStories = new Map(targetStoriesById);
    fixtureStories.set("non-item-line-migration", {
      ...fixtureStories.get("non-item-line-migration"), status: "required",
    });
    const summary = validateWorkflowSet(
      [completeBaseline, migrationWorkflow], fixtureStories,
      { workflowId: "self-test-ui-baseline", journeys: 1, behaviors: 4 },
    );
    const messages = errors.splice(start);
    if (messages.length > 0 || !summary.verifiedStoryIds.has("non-item-line-migration")) {
      throw new Error(`non-UI target-story workflow failed unexpectedly: ${messages.join(" | ")}`);
    }
  }

  expectFailure("unauthorized retirement", () => {
    validateTargetStoryCatalog({
      schemaVersion: 1,
      catalogId: "ledger-target-product-stories",
      authorityIndex: "docs/specs/README.md",
      completeness: { status: "complete", reason: "Self-test fixture." },
      stories: [{
        storyId: "retired-without-authority",
        title: "Retired without authority",
        outcome: "This intentionally malformed story proves retirement cannot be asserted without authority.",
        authority: { path: "docs/specs/projects.md", section: "Creation Flow" },
        milestone: "M3",
        status: "retired",
      }],
    }, "self-test-target-story-catalog");
  }, /retirementAuthority/);

  {
    const incompleteSummary = {
      total: 1,
      verified: 0,
      verifiedStoryIds: new Set(),
    };
    const surfaceOnlyBlockers = productGateBlockers(
      incompleteSummary,
      { completeness: { status: "complete" }, stories: [] },
      "M3",
    );
    if (!surfaceOnlyBlockers.some((message) => /Product Behavior Catalog is 0\/1 verified/.test(message))) {
      throw new Error("surface-only M3 did not fail on incomplete product behavior.");
    }
  }

  {
    const uncitedStoryBlockers = productGateBlockers(
      { total: 1, verified: 1, verifiedStoryIds: new Set() },
      {
        completeness: { status: "complete" },
        stories: [{ storyId: "uncited-story", milestone: "M3", status: "required" }],
      },
      "M3",
    );
    if (!uncitedStoryBlockers.some((message) => /uncited-story is not verified/.test(message))) {
      throw new Error("uncited target story did not block M3.");
    }
  }

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
  }, /missing, not an ancestor of HEAD, or does not contain this workflow record/);

  expectFailure("open decision mapped to unrelated story", () => {
    const value = structuredClone(targetStoryCatalog);
    const decision = value.decisionCoverage.open.find((entry) => entry.decisionId === "O-002");
    decision.auditStatus = "mapped";
    decision.storyIds = ["project-list"];
    validateTargetStoryCatalog(value, "self-test-unrelated-open-decision");
  }, /open decision may map only to a blocked story/);

  expectFailure("stale authority source hash", () => {
    const value = structuredClone(targetStoryCatalog);
    value.authorityCoverage[0].sourceHash = "0".repeat(64);
    validateTargetStoryCatalog(value, "self-test-stale-authority-hash");
  }, /sourceHash is stale/);

  expectFailure("stale decision-log source hash", () => {
    const value = structuredClone(targetStoryCatalog);
    value.decisionLog.sourceHash = "0".repeat(64);
    validateTargetStoryCatalog(value, "self-test-stale-decision-log-hash");
  }, /decisionLog.sourceHash is stale/);

  const companionFixture = () => {
    const value = structuredClone(targetStoryCatalog);
    const entry = value.authorityCoverage.find((entry) => entry.path === "docs/specs/lineage-tracking.md");
    entry.auditStatus = "audited";
    entry.storyIds = [];
    entry.headingCoverage = markdownHeadingInventory(join(repositoryRoot, entry.path)).map((heading) => (
      heading.heading === "Target History Contract"
        ? { ...heading, disposition: "story", storyIds: ["item-cycle-provenance"] }
        : { ...heading, disposition: "supporting_or_nonproduct", reason: "Synthetic source-context fixture." }
    ));
    return { value, entry };
  };
  {
    const { value } = companionFixture();
    const start = errors.length;
    validateTargetStoryCatalog(value, "self-test-companion-authority");
    const messages = errors.splice(start);
    if (messages.length) throw new Error(`companion authority rejected: ${messages.join("; ")}`);
  }
  expectFailure("companion without target coverage", () => {
    const { value, entry } = companionFixture();
    entry.headingCoverage = entry.headingCoverage.map(({ storyIds, ...heading }) => (
      { ...heading, disposition: "supporting_or_nonproduct", reason: "Synthetic missing-coverage fixture." }
    ));
    validateTargetStoryCatalog(value, "self-test-empty-companion");
  }, /audited authority must map at least one story/);
  expectFailure("companion with unknown story", () => {
    const { value, entry } = companionFixture();
    entry.headingCoverage.find((heading) => heading.disposition === "story").storyIds = ["not-a-real-story"];
    validateTargetStoryCatalog(value, "self-test-unknown-companion-story");
  }, /unknown story not-a-real-story/);

  expectFailure("declared layers without concrete files", () => {
    const value = {
      workflowId: "self-test-label-only-layers",
      kind: "product_ui",
      status: "complete",
      targetStoryIds: ["space-checklist-toggle"],
      layers: ["domain", "app_ui", "postgres_schema", "postgres_handler", "rls", "powersync_sync", "local_offline"],
      riskDomains: ["ui_fidelity", "database_integrity", "handler_idempotency", "tenant_authorization", "sync_visibility", "offline_durability"],
      acceptanceChecks: [{
        id: "SELF-LABEL-ONLY",
        risk: "ui_fidelity",
        status: "passed",
        coversStoryIds: ["space-checklist-toggle"],
      }],
    };
    validateSelfWorkflowSet([completeBaseline, value]);
  }, /lacks concrete file evidence for layers/);

  {
    const planned = structuredClone(baseCoverage);
    const completed = structuredClone(baseCoverage);
    completed.acceptanceChecks.forEach((check) => { check.status = "passed"; });
    completed.verification.local = { status: "passed", commands: ["self-general", "self-ui"] };
    completed.verification.review = { required: true, status: "passed", summary: "Passed." };
    if (JSON.stringify(workflowEvidencePayload(planned)) === JSON.stringify(workflowEvidencePayload(completed))) {
      throw new Error("completion evidence normalization erased local, review, or acceptance proof.");
    }
  }

  {
    const left = { b: [{ z: 1, a: 2 }], a: true };
    const right = { a: true, b: [{ a: 2, z: 1 }] };
    if (JSON.stringify(canonicalJson(left)) !== JSON.stringify(canonicalJson(right))) {
      throw new Error("canonical JSON comparison remains sensitive to object-key order.");
    }
  }

  expectFailure("undeclared database risks", () => {
    const value = structuredClone(baseCoverage);
    validateDerivedLayers(value, ["supabase/migrations/example.sql"], value.workflowId);
  }, /requires layer postgres_schema/);

  console.log("Conversion current-state self-tests passed: 22 negative cases and 6 positive/cumulative cases.");
}

validateTargetStoryCatalog(targetStoryCatalog);

if (process.argv[2] === "--self-test") {
  if (errors.length > 0) {
    throw new Error(`Target story catalog is invalid before self-tests: ${errors.join(" | ")}`);
  }
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

const productBehaviorSummary = validateWorkflowSet(workflowRecords);

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

if (process.argv[2] === "--gate" && !productMilestoneRanks.has(requestedProductGate)) {
  console.error("Product gate requires M3, M4, or M5.");
  process.exit(1);
}
if (requestedProductGate) {
  const gateBlockers = productGateBlockers(productBehaviorSummary, targetStoryCatalog, requestedProductGate);
  if (gateBlockers.length > 0) {
    console.error(`${requestedProductGate} product gate BLOCKED: ${gateBlockers.length} blockers`);
    for (const blocker of gateBlockers) console.error(`- ${blocker}`);
    process.exit(1);
  }
  console.log(`${requestedProductGate} product gate PASS.`);
}

console.log(
  `Conversion current state is valid: ${state.activeWorkflow.id} at ${state.verifiedCheckpoint.commit.slice(0, 8)}.`,
);
console.log(
  `Product Behavior Catalog: ${productBehaviorSummary.journeys} journeys, ${productBehaviorSummary.total} exact behaviors; ` +
    `${productBehaviorSummary.claimed} claimed by target workflows, ${productBehaviorSummary.verified} verified complete.`,
);
