import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { execFileSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

export const GENERATOR_RELATIVE = "scripts/generate-source-query-reconciliation.mjs";
export const DOSSIER_RELATIVE =
  "docs/plans/ledger-accounting-redesign/conversion/implementation-slices/source-query-reconciliation-control.json";
export const REGISTRY_RELATIVE =
  "docs/plans/ledger-accounting-redesign/conversion/source-query-reconciliation-registry.json";
export const ARTIFACT_RELATIVE =
  "docs/plans/ledger-accounting-redesign/conversion/source-query-reconciliation.generated.json";

const SOURCE_INVENTORY_RELATIVE =
  "docs/plans/ledger-accounting-redesign/conversion/query-contract.generated.json";
const TARGET_AUTHORITY_RELATIVE =
  "docs/plans/ledger-accounting-redesign/conversion/target-query-logical-authority-crosswalk.generated.json";
const MANIFEST_RELATIVE =
  "docs/plans/ledger-accounting-redesign/conversion/conversion-manifest.json";
const PACKAGE_RELATIVE = "package.json";
const WORKFLOW_RELATIVE = ".github/workflows/supabase-conversion-control.yml";
const EXPECTED_SOURCE_SHA =
  "2a43de6e59844d081237c8d9731846662e0862190823ea854c2238256b0a6a14";
const EXPECTED_SOURCE_DIGEST =
  "87a3c1deb568f3e5a5bd35dc316dff38eccaf4fb83e8ecc02c61c77887150da4";
const EXPECTED_TARGET_SHA =
  "9effa187e948004a511731239be2ed47ae6f4de393033551c978609a754b0022";
const EXPECTED_TARGET_DIGEST =
  "1091ac8b8e1cdc9de70767f5e261716109aa1d29e542a57e855a4a405287d941";
const EXPECTED_CONTROL_MODEL_SHA =
  "e34837b80826dd038cd58a7f2e9659011f8ac2b01f4aab3c0186303c56a9d6a7";
const EXPECTED_REQUIREMENTS_SHA =
  "63196e3048b49013a56873294dad3584d4d76e04501f062ff22cc147aaff0fa3";
const EXPECTED_VERIFICATION_STABLE_SHA =
  "62430e5dc93c8e25d02036d9756bdb42fae0ac1e4ab64f78d2e84fbd573b6034";
const EXPECTED_CONTRACTS_SHA =
  "171e3464ca4d26ed9446d7da0b0cc892e433226fd59d4a14e0410c83d657bacd";
const EXPECTED_PACKAGE_INTEGRATION_SHA =
  "ef8cf1572dced7f5a6dcb2e4613ad89595f9d1a4564588e46c0845d80661b51f";
const EXPECTED_WORKFLOW_INTEGRATION_SHA =
  "28fe5052cdbbe198f1f773442ca39c601122fee8e904c4f5f9d9856a7552a000";

const EXPECTED_COUNTS = Object.freeze({ queries: 386, outcomes: 584, batches: 10 });
const LIFECYCLES = Object.freeze(["draft", "ready", "implemented", "verified"]);
const CATEGORY_ORDER = Object.freeze([
  "verified_target_query_port",
  "approved_future_target_query",
  "approved_target_nonquery_surface",
  "source_only",
  "retired",
  "authority_blocked",
  "evidence_blocked",
]);
const TARGET_STATUSES = Object.freeze([
  "target_mapped",
  "implemented",
  "verified",
  "rehearsed",
  "cutover_ready",
]);
const VERIFIED_OR_LATER_TARGET_STATUSES = new Set([
  "verified",
  "rehearsed",
  "cutover_ready",
]);
const TARGET_DISPOSITIONS = Object.freeze(["migrate", "preserve", "redesign", "replace"]);
const SOURCE_ONLY_PURPOSES = Object.freeze([
  "migration",
  "audit",
  "repair",
  "profiling",
  "current_source_compatibility",
]);
const RETENTION_GATES = Object.freeze([
  "through_migration_rehearsal",
  "through_verified_cutover_reconciliation",
  "through_post_cutover_audit_signoff",
]);
const RETIREMENT_GATES = Object.freeze([
  "after_verified_target_cutover",
  "after_verified_cutover_reconciliation",
  "after_post_cutover_audit_signoff",
  "at_verified_target_cutover",
]);
const BLOCKED_SCOPES = Object.freeze([
  "target_query_contract",
  "target_nonquery_contract",
  "source_disposition",
  "retirement",
]);
const EVIDENCE_SCOPES = Object.freeze(["source_runtime_use", "source_reference_safety"]);
const FORBIDDEN_BLOCKERS = new Set(["O-021", "A-003", "A-004"]);
const GATE_RANK = Object.freeze({
  through_migration_rehearsal: 10,
  after_verified_target_cutover: 30,
  through_verified_cutover_reconciliation: 40,
  after_verified_cutover_reconciliation: 50,
  through_post_cutover_audit_signoff: 60,
  after_post_cutover_audit_signoff: 70,
});
const HASH_PREFIX = Object.freeze({
  occurrence: "source-query-occurrence-v1\0",
  owner: "source-query-owner-projection-v1\0",
  target: "source-query-target-mapping-v1\0",
  evidence: "source-query-evidence-owner-binding-v1\0",
  retirementHeading: "source-query-retirement-heading-v1\0",
  retirementDecision: "source-query-retirement-decision-v1\0",
  retirementAuthority: "source-query-retirement-authority-v1\0",
});
const IMPLEMENTATION_BASE = "4618c7e5b9fc3a24cd917239bf795aec6117ea5c";
const IMPLEMENTATION_CHECKPOINT = "aefa7acd57957ebe4e136540b1f6034ae8131130";
const IMPLEMENTATION_PATHS = Object.freeze([
  ".github/workflows/supabase-conversion-control.yml",
  "docs/plans/ledger-accounting-redesign/conversion/classification-batches/M0-CAPABILITY-CONTROL-001.json",
  "docs/plans/ledger-accounting-redesign/conversion/classification-batches/M0-PLATFORM-CONTROL-001.json",
  "docs/plans/ledger-accounting-redesign/conversion/classification-batches/M0-QUERY-PROFILE-001.json",
  "docs/plans/ledger-accounting-redesign/conversion/conversion-coverage.md",
  "docs/plans/ledger-accounting-redesign/conversion/conversion-manifest.json",
  "docs/plans/ledger-accounting-redesign/conversion/evidence-index.md",
  "docs/plans/ledger-accounting-redesign/conversion/evidence/EVID-SOURCE-QUERY-RECONCILIATION-001.md",
  "docs/plans/ledger-accounting-redesign/conversion/execution-state.md",
  "docs/plans/ledger-accounting-redesign/conversion/implementation-slice-audit.generated.json",
  "docs/plans/ledger-accounting-redesign/conversion/implementation-slice-audit.generated.md",
  "docs/plans/ledger-accounting-redesign/conversion/implementation-slices/source-query-reconciliation-control.json",
  "docs/plans/ledger-accounting-redesign/conversion/product-authority-audit.generated.json",
  "docs/plans/ledger-accounting-redesign/conversion/product-authority-audit.generated.md",
  "docs/plans/ledger-accounting-redesign/conversion/source-query-reconciliation-batches/identity-lifecycle.json",
  "docs/plans/ledger-accounting-redesign/conversion/source-query-reconciliation-batches/inventory-transaction.json",
  "docs/plans/ledger-accounting-redesign/conversion/source-query-reconciliation-batches/invoicing-budget.json",
  "docs/plans/ledger-accounting-redesign/conversion/source-query-reconciliation-batches/item-creation-link.json",
  "docs/plans/ledger-accounting-redesign/conversion/source-query-reconciliation-batches/media-lifecycle.json",
  "docs/plans/ledger-accounting-redesign/conversion/source-query-reconciliation-batches/platform-control.json",
  "docs/plans/ledger-accounting-redesign/conversion/source-query-reconciliation-batches/project-client-reference.json",
  "docs/plans/ledger-accounting-redesign/conversion/source-query-reconciliation-batches/reporting-search.json",
  "docs/plans/ledger-accounting-redesign/conversion/source-query-reconciliation-batches/source-migration-audit.json",
  "docs/plans/ledger-accounting-redesign/conversion/source-query-reconciliation-batches/spaces-review.json",
  "docs/plans/ledger-accounting-redesign/conversion/source-query-reconciliation-registry.json",
  "docs/plans/ledger-accounting-redesign/conversion/source-query-reconciliation.generated.json",
  "docs/plans/ledger-accounting-redesign/implementation-tracker.md",
  "package.json",
  "scripts/generate-source-query-reconciliation.mjs",
  "scripts/tests/generate-source-query-reconciliation.test.mjs",
]);
const INTEGRATION_SCRIPTS = Object.freeze({
  "source:query-reconciliation:generate":
    "node scripts/generate-source-query-reconciliation.mjs generate",
  "source:query-reconciliation:check":
    "node scripts/generate-source-query-reconciliation.mjs check",
  "source:query-reconciliation:test":
    "node --test scripts/tests/generate-source-query-reconciliation.test.mjs",
});
const CONVERSION_CONTROL_COMMANDS = Object.freeze([
  "npm run target:query-ports:test",
  "npm run target:query-ports:check",
  "npm run target:query-authority:test",
  "npm run target:query-authority:check",
  "npm run conversion:check",
  "npm run source:query-reconciliation:test",
  "npm run source:query-reconciliation:check",
  "npm run conversion:capabilities:check",
  "npm run conversion:queries:check",
  "npm run conversion:residuals:check",
  "npm run conversion:gate:m0",
]);

export function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function fail(message) {
  throw new Error(`source-query-reconciliation: ${message}`);
}

export function compareText(left, right) {
  return Buffer.compare(Buffer.from(left), Buffer.from(right));
}

function compareInventoryText(left, right) {
  return left.localeCompare(right, "en", { sensitivity: "variant" });
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function requirePlainObject(value, label) {
  if (!isPlainObject(value)) fail(`${label} must be an object`);
}

function requireArray(value, label, { nonempty = false } = {}) {
  if (!Array.isArray(value)) fail(`${label} must be an array`);
  if (nonempty && value.length === 0) fail(`${label} must not be empty`);
}

function requireString(value, label, pattern = null) {
  if (typeof value !== "string" || value.length === 0) {
    fail(`${label} must be a nonempty string`);
  }
  if (pattern && !pattern.test(value)) fail(`${label} has invalid format`);
}

function requireInteger(value, label, { positive = false } = {}) {
  if (!Number.isSafeInteger(value) || (positive && value < 1)) {
    fail(`${label} must be ${positive ? "a positive" : "an"} integer`);
  }
}

function requireExactKeys(value, expected, label) {
  requirePlainObject(value, label);
  const actual = Object.keys(value).sort(compareText);
  const wanted = [...expected].sort(compareText);
  if (actual.length !== wanted.length || actual.some((key, index) => key !== wanted[index])) {
    const missing = wanted.filter((key) => !actual.includes(key));
    const unexpected = actual.filter((key) => !wanted.includes(key));
    fail(
      `${label} keys mismatch` +
        `${missing.length ? `; missing ${missing.join(", ")}` : ""}` +
        `${unexpected.length ? `; unexpected ${unexpected.join(", ")}` : ""}`,
    );
  }
}

function requireEnum(value, allowed, label) {
  requireString(value, label);
  if (!allowed.includes(value)) fail(`${label} has unsupported value ${value}`);
}

function requireUnique(values, label) {
  const seen = new Set();
  for (const value of values) {
    if (seen.has(value)) fail(`${label} contains duplicate ${value}`);
    seen.add(value);
  }
}

function requireSortedUnique(values, label, projector = (value) => value) {
  requireArray(values, label);
  const projected = values.map((value, index) => {
    let projectedValue;
    try {
      projectedValue = projector(value);
    } catch {
      fail(`${label}[${index}] is malformed`);
    }
    requireString(projectedValue, `${label}[${index}] sort key`);
    return projectedValue;
  });
  requireUnique(projected, label);
  const sorted = [...projected].sort(compareText);
  if (projected.some((value, index) => value !== sorted[index])) {
    fail(`${label} must be byte-sorted`);
  }
}

function same(left, right) {
  return canonicalMinifiedJson(left) === canonicalMinifiedJson(right);
}

function requireEqual(actual, expected, label) {
  if (!same(actual, expected)) fail(`${label} does not match frozen authority`);
}

export function canonicalize(value) {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (!isPlainObject(value)) return value;
  return Object.fromEntries(
    Object.keys(value)
      .sort(compareText)
      .map((key) => [key, canonicalize(value[key])]),
  );
}

export function canonicalMinifiedJson(value) {
  return JSON.stringify(canonicalize(value));
}

function requireSafeRelativePath(relativePath, label) {
  requireString(relativePath, label);
  if (
    path.isAbsolute(relativePath) ||
    relativePath.includes("\\") ||
    relativePath.includes("\0") ||
    relativePath.split("/").some((component) => component.length === 0) ||
    path.posix.normalize(relativePath) !== relativePath ||
    relativePath === "." ||
    relativePath.startsWith("../")
  ) {
    fail(`${label} is not a safe repository-relative path`);
  }
}

function repositoryRoot(root) {
  const absolute = path.resolve(root);
  let metadata;
  try {
    metadata = fs.lstatSync(absolute);
  } catch {
    fail(`repository root is missing: ${absolute}`);
  }
  if (metadata.isSymbolicLink() || !metadata.isDirectory()) {
    fail(`repository root must be a non-symlink directory: ${absolute}`);
  }
  return fs.realpathSync(absolute);
}

function requireContained(root, candidate, label, { allowRoot = false } = {}) {
  const relative = path.relative(root, candidate);
  if (
    (!allowRoot && relative === "") ||
    relative === ".." ||
    relative.startsWith(`..${path.sep}`) ||
    path.isAbsolute(relative)
  ) {
    fail(`${label} escapes repository root`);
  }
  return relative;
}

function validatePathComponents(root, candidate, label, { includeFinal = true } = {}) {
  const relative = requireContained(root, candidate, label);
  const components = relative.split(path.sep);
  const limit = includeFinal ? components.length : components.length - 1;
  let cursor = root;
  for (let index = 0; index < limit; index += 1) {
    cursor = path.join(cursor, components[index]);
    let metadata;
    try {
      metadata = fs.lstatSync(cursor);
    } catch {
      fail(`missing ${label}: ${relative}`);
    }
    if (metadata.isSymbolicLink()) fail(`${label} must not traverse a symlink: ${relative}`);
    if (index < limit - 1 && !metadata.isDirectory()) {
      fail(`${label} parent must be a directory: ${relative}`);
    }
  }
}

function repositoryFile(root, relativePath, label) {
  requireSafeRelativePath(relativePath, `${label} path`);
  const realRoot = repositoryRoot(root);
  const candidate = path.resolve(realRoot, relativePath);
  requireContained(realRoot, candidate, label);
  validatePathComponents(realRoot, candidate, label);
  const metadata = fs.lstatSync(candidate);
  if (metadata.isSymbolicLink() || !metadata.isFile()) {
    fail(`${label} must be a regular non-symlink file: ${relativePath}`);
  }
  requireContained(realRoot, fs.realpathSync(candidate), label);
  return candidate;
}

function repositoryDirectory(root, relativePath, label) {
  requireSafeRelativePath(relativePath, `${label} path`);
  const realRoot = repositoryRoot(root);
  const candidate = path.resolve(realRoot, relativePath);
  requireContained(realRoot, candidate, label);
  validatePathComponents(realRoot, candidate, label);
  const metadata = fs.lstatSync(candidate);
  if (metadata.isSymbolicLink() || !metadata.isDirectory()) {
    fail(`${label} must be a non-symlink directory: ${relativePath}`);
  }
  requireContained(realRoot, fs.realpathSync(candidate), label);
  return candidate;
}

function artifactParent(root, filePath) {
  const lexicalRoot = path.resolve(root);
  const realRoot = repositoryRoot(root);
  const lexicalCandidate = path.resolve(filePath);
  const relative = path.relative(lexicalRoot, lexicalCandidate);
  requireSafeRelativePath(relative.split(path.sep).join("/"), "generated artifact path");
  const candidate = path.join(realRoot, relative);
  validatePathComponents(realRoot, candidate, "generated artifact", { includeFinal: false });
  const parent = path.dirname(candidate);
  const metadata = fs.lstatSync(parent);
  if (metadata.isSymbolicLink() || !metadata.isDirectory()) {
    fail(`generated artifact parent must be a non-symlink directory: ${relative}`);
  }
  requireContained(realRoot, fs.realpathSync(parent), "generated artifact parent", {
    allowRoot: true,
  });
  return { realRoot, candidate, parent };
}

function readRepositoryFile(root, relativePath, label) {
  return fs.readFileSync(repositoryFile(root, relativePath, label));
}

function parseJson(buffer, label) {
  try {
    return JSON.parse(Buffer.from(buffer).toString("utf8"));
  } catch (error) {
    fail(`${label} is invalid JSON: ${error.message}`);
  }
}

function readJson(root, relativePath, label) {
  const bytes = readRepositoryFile(root, relativePath, label);
  return { bytes, value: parseJson(bytes, label) };
}

function uniqueLineIndex(lines, pattern, label) {
  const indices = lines.flatMap((line, index) => (pattern.test(line) ? [index] : []));
  if (indices.length !== 1) fail(`${label} must occur exactly once`);
  return indices[0];
}

export function validateIntegrationHooks(packageJson, workflowText) {
  requirePlainObject(packageJson, "package.json");
  requirePlainObject(packageJson.scripts, "package.json scripts");
  for (const [name, command] of Object.entries(INTEGRATION_SCRIPTS)) {
    if (packageJson.scripts[name] !== command) {
      fail(`package.json script ${name} is not the exact reconciliation hook`);
    }
    for (const prefix of ["pre", "post"]) {
      if (Object.hasOwn(packageJson.scripts, `${prefix}${name}`)) {
        fail(`package.json must not define ${prefix}${name}`);
      }
    }
  }
  requireString(workflowText, "conversion workflow");
  const lines = workflowText.replace(/\r\n?/g, "\n").split("\n");
  const triggerStart = uniqueLineIndex(lines, /^on:\s*$/, "workflow trigger root");
  const permissionsStart = uniqueLineIndex(lines, /^permissions:\s*$/, "workflow permissions root");
  if (triggerStart >= permissionsStart) fail("workflow triggers must precede permissions");
  requireEqual(
    lines.slice(triggerStart, permissionsStart).filter((line) => line.trim() !== ""),
    ["on:", "  pull_request:", "  workflow_dispatch:"],
    "conversion workflow triggers",
  );
  const conversionStart = uniqueLineIndex(
    lines,
    /^  conversion-control:\s*$/,
    "conversion-control job",
  );
  const targetStart = uniqueLineIndex(
    lines,
    /^  target-environment:\s*$/,
    "target-environment job",
  );
  const localSupabaseStart = uniqueLineIndex(
    lines,
    /^  local-supabase-provider-slices:\s*$/,
    "local Supabase Client job",
  );
  if (conversionStart >= targetStart) fail("conversion-control job must precede target-environment job");
  if (targetStart >= localSupabaseStart) {
    fail("target-environment job must precede local Supabase Client job");
  }
  const conversionLines = lines.slice(conversionStart, targetStart);
  const targetLines = lines.slice(targetStart, localSupabaseStart);
  if (!conversionLines.some((line) => /^    runs-on: ubuntu-latest\s*$/.test(line))) {
    fail("conversion-control job must run on ubuntu-latest");
  }
  const conditionalKey = /^\s+(?:["']?if["']?|["']?continue-on-error["']?)\s*:/;
  for (const [index, line] of lines.entries()) {
    if (!conditionalKey.test(line)) continue;
    const isUnconditionalCleanup =
      line === "        if: always()" &&
      lines[index - 1] === "      - name: Stop isolated local Supabase" &&
      lines[index + 1] === "        run: npx --yes supabase@2.116.0 stop --no-backup";
    if (!isUnconditionalCleanup) {
      fail("conversion workflow jobs must not conditionally skip or tolerate failures");
    }
  }
  const validationStep = uniqueLineIndex(
    conversionLines,
    /^      - name: Validate conversion control plane\s*$/,
    "conversion validation step",
  );
  const nextStepOffset = conversionLines
    .slice(validationStep + 1)
    .findIndex((line) => /^      - name:/.test(line));
  if (nextStepOffset < 0) fail("conversion validation step must be followed by another named step");
  const validationBlock = conversionLines.slice(
    validationStep + 1,
    validationStep + 1 + nextStepOffset,
  );
  if (validationBlock[0] !== "        run: |") {
    fail("conversion validation step must use an exact run block");
  }
  const commands = validationBlock.slice(1).filter((line) => line.trim() !== "");
  requireEqual(
    commands,
    CONVERSION_CONTROL_COMMANDS.map((command) => `          ${command}`),
    "conversion validation command order",
  );
  const conversionDiffStep = validationStep + 1 + nextStepOffset;
  if (
    conversionLines[conversionDiffStep] !==
      "      - name: Confirm checks did not rewrite tracked artifacts" ||
    conversionLines[conversionDiffStep + 1] !== "        run: git diff --exit-code"
  ) {
    fail("conversion-control job must retain the exact read-only diff guard");
  }
  if (!targetLines.some((line) => /^    needs: conversion-control\s*$/.test(line))) {
    fail("target-environment job must depend on conversion-control");
  }
  if (!targetLines.some((line) => /^    runs-on: macos-26\s*$/.test(line))) {
    fail("target-environment job must run on macos-26");
  }
  if (
    !targetLines.some((line) =>
      /^        run: swift test --package-path LedgeriOS --no-parallel\s*$/.test(line),
    )
  ) {
    fail("target-environment job must retain the nonparallel Swift test gate");
  }
  const targetDiffStep = uniqueLineIndex(
    targetLines,
    /^      - name: Confirm target checks did not rewrite tracked artifacts\s*$/,
    "target read-only diff step",
  );
  if (targetLines[targetDiffStep + 1] !== "        run: git diff --exit-code") {
    fail("target-environment job must retain the exact read-only diff guard");
  }
  const fullHistoryCheckouts = lines.filter((line) => /^          fetch-depth: 0\s*$/.test(line));
  if (fullHistoryCheckouts.length !== 2) {
    fail("conversion workflow must use two full-history checkouts");
  }
  requireExactHash(
    sha256(canonicalMinifiedJson(packageJson)),
    EXPECTED_PACKAGE_INTEGRATION_SHA,
    "package.json integration projection",
  );
  requireExactHash(
    sha256(workflowText),
    EXPECTED_WORKFLOW_INTEGRATION_SHA,
    "conversion workflow integration artifact",
  );
}

function validateRepositoryIntegrationHooks(root) {
  const packageJson = readJson(root, PACKAGE_RELATIVE, "package.json").value;
  const workflowText = readRepositoryFile(root, WORKFLOW_RELATIVE, "conversion workflow")
    .toString("utf8");
  validateIntegrationHooks(packageJson, workflowText);
}

function exactSourceRef(value, label) {
  requirePlainObject(value, label);
  const expected = Object.hasOwn(value, "line") ? ["path", "line"] : ["path"];
  requireExactKeys(value, expected, label);
  requireSafeRelativePath(value.path, `${label}.path`);
  if (Object.hasOwn(value, "line")) requireInteger(value.line, `${label}.line`, { positive: true });
  return canonicalize(value);
}

function hashProjection(prefix, projection) {
  return sha256(`${prefix}${canonicalMinifiedJson(projection)}`);
}

function stripVerificationState(entry) {
  requirePlainObject(entry, "dossier verification stable entry");
  const { status: _status, evidence: _evidence, ...stable } = entry;
  return stable;
}

function requireExactHash(value, expected, label) {
  requireString(value, label, /^[a-f0-9]{64}$/);
  if (value !== expected) fail(`${label} is stale`);
}

function validateDossier(dossier) {
  requireExactKeys(
    dossier,
    [
      "schemaVersion",
      "sliceId",
      "title",
      "kind",
      "status",
      "owner",
      "surfaceIds",
      "requirements",
      "contracts",
      "verification",
      "controlModel",
      "implementationEvidence",
      "rehearsalEvidence",
      "blockers",
      "notes",
    ],
    "dossier",
  );
  if (dossier.schemaVersion !== 1) fail("dossier.schemaVersion must equal 1");
  if (dossier.sliceId !== "source-query-reconciliation-control") {
    fail("dossier.sliceId is not the source-query reconciliation control");
  }
  if (dossier.kind !== "technical_control") fail("dossier.kind must equal technical_control");
  requireEnum(dossier.status, LIFECYCLES, "dossier.status");
  requireEqual(
    dossier.surfaceIds,
    ["CONFIG-A8BD153106B8", "CONFIG-40F01696B8A6"],
    "dossier.surfaceIds",
  );
  requireArray(dossier.requirements, "dossier.requirements", { nonempty: true });
  requireExactHash(
    sha256(canonicalMinifiedJson(dossier.requirements)),
    EXPECTED_REQUIREMENTS_SHA,
    "dossier requirements projection",
  );
  requireArray(dossier.verification, "dossier.verification", { nonempty: true });
  requireExactHash(
    sha256(canonicalMinifiedJson(dossier.verification.map(stripVerificationState))),
    EXPECTED_VERIFICATION_STABLE_SHA,
    "dossier verification projection",
  );
  requirePlainObject(dossier.contracts, "dossier.contracts");
  requireExactHash(
    sha256(canonicalMinifiedJson(dossier.contracts)),
    EXPECTED_CONTRACTS_SHA,
    "dossier contracts projection",
  );
  requireEqual(
    dossier.requirements.map((entry) => entry.id),
    Array.from({ length: 10 }, (_, index) => `SQUERY-REQ-${String(index + 1).padStart(3, "0")}`),
    "dossier requirement IDs",
  );
  requireEqual(
    dossier.verification.map((entry) => entry.id),
    Array.from({ length: 10 }, (_, index) => `SQUERY-TEST-${String(index + 1).padStart(3, "0")}`),
    "dossier verification IDs",
  );
  for (const [index, entry] of dossier.verification.entries()) {
    requireEnum(entry.status, ["planned", "passed"], `dossier.verification[${index}].status`);
    requireArray(entry.evidence, `dossier.verification[${index}].evidence`);
  }
  requireArray(dossier.implementationEvidence, "dossier.implementationEvidence");
  requireArray(dossier.rehearsalEvidence, "dossier.rehearsalEvidence");
  requireArray(dossier.blockers, "dossier.blockers");
  requirePlainObject(dossier.controlModel, "dossier.controlModel");
  requireExactHash(
    sha256(canonicalMinifiedJson(dossier.controlModel)),
    EXPECTED_CONTROL_MODEL_SHA,
    "dossier.controlModel",
  );

  const control = dossier.controlModel;
  requireEqual(control.lifecycleEnums, LIFECYCLES, "control lifecycle enums");
  requireEqual(control.outcomeCategoryOrder, CATEGORY_ORDER, "control category order");
  requireEqual(control.allowedTargetStatuses, TARGET_STATUSES, "control target statuses");
  requireEqual(
    control.allowedTargetDispositions,
    TARGET_DISPOSITIONS,
    "control target dispositions",
  );
  requireEqual(control.sourceOnlyPurposeEnums, SOURCE_ONLY_PURPOSES, "control source purposes");
  requireEqual(control.sourceOnlyRetentionGateEnums, RETENTION_GATES, "control retention gates");
  requireEqual(control.retirementGateEnums, RETIREMENT_GATES, "control retirement gates");
  requireEqual(control.blockedScopeEnums, BLOCKED_SCOPES, "control blocked scopes");
  requireEqual(
    control.evidenceBlockedScopeEnums,
    EVIDENCE_SCOPES,
    "control evidence scopes",
  );
  requireEqual(control.lifecycleGateOrder, GATE_RANK, "control lifecycle gate order");
  requireEqual(
    control.lifecycleAllowlists.implementation,
    { status: "frozen", baseCommit: IMPLEMENTATION_BASE, paths: IMPLEMENTATION_PATHS },
    "implementation allowlist",
  );
  requireSortedUnique(
    control.lifecycleAllowlists.implementation.paths,
    "implementation allowlist paths",
  );
  requireExactKeys(
    control.implementationBaselineScaffolds,
    ["generator", "tests", "rule"],
    "implementation baseline scaffolds",
  );
  for (const key of ["generator", "tests"]) {
    const entry = control.implementationBaselineScaffolds[key];
    requireExactKeys(entry, ["path", "sha256"], `implementation scaffold ${key}`);
    requireSafeRelativePath(entry.path, `implementation scaffold ${key}.path`);
    requireString(entry.sha256, `implementation scaffold ${key}.sha256`, /^[a-f0-9]{64}$/);
  }
  return control;
}

function runGit(root, args, label) {
  try {
    return execFileSync("git", ["-C", root, ...args], {
      encoding: null,
      stdio: ["ignore", "pipe", "pipe"],
      maxBuffer: 32 * 1024 * 1024,
    });
  } catch (error) {
    const detail = error.stderr?.toString("utf8").trim();
    fail(`${label} failed${detail ? `: ${detail}` : ""}`);
  }
}

function parseNulPaths(buffer, label) {
  const bytes = Buffer.from(buffer);
  if (bytes.length === 0) return [];
  if (bytes[bytes.length - 1] !== 0) fail(`${label} is not NUL-terminated`);
  return bytes
    .subarray(0, bytes.length - 1)
    .toString("utf8")
    .split("\0");
}

function validateLifecycleAllowlist(root, dossier, { enforceRepositoryDiff = true } = {}) {
  if (!enforceRepositoryDiff) return;
  const control = dossier.controlModel;
  const key = {
    draft: "draftCompletion",
    ready: "ready",
    implemented: "implementation",
    verified: "promotion",
  }[dossier.status];
  const selected = control.lifecycleAllowlists[key];
  requirePlainObject(selected, `lifecycle allowlist ${key}`);
  requireString(selected.baseCommit, `lifecycle allowlist ${key}.baseCommit`, /^[a-f0-9]{40}$/);
  requireArray(selected.paths, `lifecycle allowlist ${key}.paths`, { nonempty: true });
  requireSortedUnique(selected.paths, `lifecycle allowlist ${key}.paths`);
  for (const candidate of selected.paths) {
    requireSafeRelativePath(candidate, `lifecycle allowlist ${key} member`);
  }

  runGit(root, ["cat-file", "-e", `${selected.baseCommit}^{commit}`], "lifecycle base commit");
  const endpoint = dossier.status === "implemented" ? IMPLEMENTATION_CHECKPOINT : null;
  if (endpoint !== null) {
    runGit(root, ["cat-file", "-e", `${endpoint}^{commit}`], "lifecycle checkpoint commit");
    runGit(
      root,
      ["merge-base", "--is-ancestor", endpoint, "HEAD"],
      "lifecycle checkpoint ancestry",
    );
  }
  const tracked = parseNulPaths(
    runGit(
      root,
      [
        "diff",
        "--name-only",
        "-z",
        selected.baseCommit,
        ...(endpoint === null ? [] : [endpoint]),
        "--",
      ],
      "tracked diff",
    ),
    "tracked diff",
  );
  const untracked = endpoint === null
    ? parseNulPaths(
        runGit(root, ["ls-files", "--others", "--exclude-standard", "-z"], "untracked diff"),
        "untracked diff",
      )
    : [];
  const actual = [...new Set([...tracked, ...untracked])].sort(compareText);
  if (!same(actual, selected.paths)) {
    const missing = selected.paths.filter((entry) => !actual.includes(entry));
    const unexpected = actual.filter((entry) => !selected.paths.includes(entry));
    fail(
      `lifecycle ${key} changed-path set mismatch` +
        `${missing.length ? `; missing ${missing.join(", ")}` : ""}` +
        `${unexpected.length ? `; unexpected ${unexpected.join(", ")}` : ""}`,
    );
  }
  if (endpoint !== null) return;
  for (const relativePath of actual) {
    const candidate = path.join(root, relativePath);
    let metadata;
    try {
      metadata = fs.lstatSync(candidate);
    } catch (error) {
      if (error?.code === "ENOENT") continue;
      fail(`could not inspect changed path ${relativePath}: ${error.message}`);
    }
    if (metadata.isSymbolicLink()) fail(`changed path must not be a symlink: ${relativePath}`);
  }

  if (["implemented", "verified"].includes(dossier.status)) {
    for (const [name, scaffold] of Object.entries(control.implementationBaselineScaffolds)) {
      if (name === "rule") continue;
      const baselineBytes = runGit(
        root,
        ["show", `${control.lifecycleAllowlists.implementation.baseCommit}:${scaffold.path}`],
        `baseline scaffold ${name}`,
      );
      requireExactHash(sha256(baselineBytes), scaffold.sha256, `baseline scaffold ${name}`);
      const currentBytes = readRepositoryFile(root, scaffold.path, `current scaffold ${name}`);
      if (sha256(currentBytes) === scaffold.sha256) {
        fail(`current scaffold ${name} was not replaced at implemented lifecycle`);
      }
    }
  }
}

function normalizeMarkdown(buffer) {
  return buffer.toString("utf8").replace(/\r\n?/g, "\n");
}

function markdownHeadings(text) {
  const lines = text.split("\n");
  const headings = [];
  let fence = null;
  for (let index = 0; index < lines.length; index += 1) {
    const fenceMatch = lines[index].match(/^\s*(`{3,}|~{3,})/);
    if (fenceMatch) {
      const marker = fenceMatch[1][0];
      if (fence === null) fence = marker;
      else if (fence === marker) fence = null;
      continue;
    }
    if (fence !== null) continue;
    const match = lines[index].match(/^(#{1,6})[ \t]+(.+?)[ \t]*#*[ \t]*$/);
    if (match) headings.push({ index, level: match[1].length, title: match[2].trim() });
  }
  return { lines, headings };
}

export function extractHeadingSection(buffer, section, label = "Markdown authority") {
  const parsed = markdownHeadings(normalizeMarkdown(buffer));
  const matches = parsed.headings.filter((heading) => heading.title === section);
  if (matches.length !== 1) fail(`${label} heading ${section} must occur exactly once`);
  const start = matches[0];
  const next = parsed.headings.find(
    (heading) => heading.index > start.index && heading.level <= start.level,
  );
  const lines = parsed.lines.slice(start.index, next?.index ?? parsed.lines.length);
  while (lines.length > 0 && lines[lines.length - 1] === "") lines.pop();
  return `${lines.join("\n")}\n`;
}

function extractDecisionRow(buffer, section, decisionId, label) {
  const sectionBytes = extractHeadingSection(buffer, section, label);
  const rows = sectionBytes
    .split("\n")
    .filter((line) => new RegExp(`^\\|\\s*${decisionId.replace("-", "\\-")}\\s*\\|`).test(line));
  if (rows.length !== 1) fail(`${label} decision ${decisionId} must occur exactly once`);
  return rows[0];
}

function validateAuthorityReference(root, authority, label) {
  requireExactKeys(authority, ["id", "kind", "path", "section"], label);
  requireString(authority.id, `${label}.id`, /^(?:A|O)-\d{3}$/);
  requireEnum(authority.kind, ["architecture_decision", "product_decision"], `${label}.kind`);
  const bytes = readRepositoryFile(root, authority.path, `${label} source`);
  if (authority.id.startsWith("A-")) {
    if (authority.kind !== "architecture_decision") fail(`${label}.kind does not match A decision`);
    if (authority.path !== "docs/architecture/redesign/architecture-decisions.md") {
      fail(`${label}.path is not the architecture decision authority`);
    }
    extractHeadingSection(bytes, authority.section, label);
    if (!authority.section.startsWith(`${authority.id} `)) fail(`${label}.section does not bind ID`);
  } else {
    if (authority.kind !== "product_decision") fail(`${label}.kind does not match O decision`);
    if (
      authority.path !== "docs/plans/ledger-accounting-redesign/decision-log.md" ||
      authority.section !== "Open Product Decisions"
    ) {
      fail(`${label} does not use the exact product-decision authority`);
    }
    extractDecisionRow(bytes, authority.section, authority.id, label);
  }
}

function validateCountObject(value, label) {
  requirePlainObject(value, label);
  const keys = Object.keys(value);
  requireSortedUnique(keys, `${label} keys`);
  for (const key of keys) {
    requireString(key, `${label} key`);
    requireInteger(value[key], `${label}.${key}`, { positive: true });
  }
}

function countBy(items, selector) {
  const counts = new Map();
  for (const item of items) {
    const key = selector(item);
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  return Object.fromEntries([...counts.entries()].sort(([a], [b]) => compareText(a, b)));
}

export function deriveQueryId(occurrence) {
  return `QUERY-${sha256(`${occurrence.sourcePath}:${occurrence.line}:${occurrence.operation}`)
    .slice(0, 12)
    .toUpperCase()}`;
}

export function deriveOccurrenceHash(occurrence) {
  return hashProjection(HASH_PREFIX.occurrence, occurrence);
}

function validateSourceInventory(root, bytes, inventory, registryBinding) {
  requireExactKeys(
    inventory,
    [
      "schemaVersion",
      "generator",
      "sourceDigest",
      "scope",
      "limitations",
      "totals",
      "bySubsystem",
      "byOperation",
      "sourceFiles",
      "occurrences",
    ],
    "source inventory",
  );
  if (inventory.schemaVersion !== 1) fail("source inventory.schemaVersion must equal 1");
  if (inventory.generator !== "scripts/extract-firestore-query-contract.mjs") {
    fail("source inventory.generator is unexpected");
  }
  requireExactHash(inventory.sourceDigest, EXPECTED_SOURCE_DIGEST, "source inventory.sourceDigest");
  requireArray(inventory.scope, "source inventory.scope", { nonempty: true });
  requireUnique(inventory.scope, "source inventory.scope");
  for (const scope of inventory.scope) requireSafeRelativePath(scope, "source inventory scope");
  requireArray(inventory.limitations, "source inventory.limitations", { nonempty: true });
  for (const limitation of inventory.limitations) requireString(limitation, "source limitation");
  requireExactKeys(
    inventory.totals,
    ["candidateFilesInspected", "sourceFilesWithOccurrences", "occurrences"],
    "source inventory.totals",
  );
  for (const [key, value] of Object.entries(inventory.totals)) {
    requireInteger(value, `source inventory.totals.${key}`, { positive: true });
  }
  validateCountObject(inventory.bySubsystem, "source inventory.bySubsystem");
  validateCountObject(inventory.byOperation, "source inventory.byOperation");
  requireArray(inventory.sourceFiles, "source inventory.sourceFiles", { nonempty: true });
  for (const [index, source] of inventory.sourceFiles.entries()) {
    requirePlainObject(source, `source inventory.sourceFiles[${index}]`);
  }
  requireUnique(
    inventory.sourceFiles.map((entry) => entry.sourcePath),
    "source inventory.sourceFiles",
  );
  for (const [index, source] of inventory.sourceFiles.entries()) {
    const label = `source inventory.sourceFiles[${index}]`;
    requireExactKeys(source, ["sourcePath", "sourceHash", "occurrenceCount"], label);
    requireSafeRelativePath(source.sourcePath, `${label}.sourcePath`);
    requireString(source.sourceHash, `${label}.sourceHash`, /^[a-f0-9]{64}$/);
    requireInteger(source.occurrenceCount, `${label}.occurrenceCount`, { positive: true });
    if (
      index > 0 &&
      compareInventoryText(inventory.sourceFiles[index - 1].sourcePath, source.sourcePath) >= 0
    ) {
      fail("source inventory.sourceFiles are not deterministically ordered");
    }
    const sourceBytes = readRepositoryFile(root, source.sourcePath, `${label} source`);
    requireExactHash(sha256(sourceBytes), source.sourceHash, `${label}.sourceHash`);
  }
  const derivedDigest = sha256(
    inventory.sourceFiles.map((source) => `${source.sourcePath}:${source.sourceHash}`).join("\n"),
  );
  requireExactHash(derivedDigest, inventory.sourceDigest, "source inventory derived digest");

  requireArray(inventory.occurrences, "source inventory.occurrences", { nonempty: true });
  const seen = new Set();
  let previous = null;
  for (const [index, occurrence] of inventory.occurrences.entries()) {
    const label = `source inventory.occurrences[${index}]`;
    requireExactKeys(
      occurrence,
      ["id", "subsystem", "sourcePath", "line", "symbol", "operation", "expression"],
      label,
    );
    requireString(occurrence.id, `${label}.id`, /^QUERY-[0-9A-F]{12}$/);
    requireString(occurrence.subsystem, `${label}.subsystem`);
    requireSafeRelativePath(occurrence.sourcePath, `${label}.sourcePath`);
    requireInteger(occurrence.line, `${label}.line`, { positive: true });
    requireString(occurrence.symbol, `${label}.symbol`);
    requireString(occurrence.operation, `${label}.operation`);
    requireString(occurrence.expression, `${label}.expression`);
    if (occurrence.id !== deriveQueryId(occurrence)) fail(`${label}.id does not match derivation`);
    if (seen.has(occurrence.id)) fail(`source inventory duplicate query ${occurrence.id}`);
    seen.add(occurrence.id);
    if (previous) {
      const order =
        compareInventoryText(previous.sourcePath, occurrence.sourcePath) ||
        previous.line - occurrence.line ||
        compareInventoryText(previous.operation, occurrence.operation);
      if (order >= 0) fail("source inventory occurrences are not deterministically ordered");
    }
    previous = occurrence;
  }
  const byFile = countBy(inventory.occurrences, (entry) => entry.sourcePath);
  for (const source of inventory.sourceFiles) {
    if (byFile[source.sourcePath] !== source.occurrenceCount) {
      fail(`source file occurrence count is stale: ${source.sourcePath}`);
    }
  }
  if (Object.keys(byFile).length !== inventory.sourceFiles.length) {
    fail("source inventory source-file membership is stale");
  }
  requireEqual(
    countBy(inventory.occurrences, (entry) => entry.subsystem),
    inventory.bySubsystem,
    "source inventory subsystem totals",
  );
  requireEqual(
    countBy(inventory.occurrences, (entry) => entry.operation),
    inventory.byOperation,
    "source inventory operation totals",
  );
  if (inventory.totals.sourceFilesWithOccurrences !== inventory.sourceFiles.length) {
    fail("source inventory sourceFilesWithOccurrences is stale");
  }
  if (inventory.totals.occurrences !== inventory.occurrences.length) {
    fail("source inventory occurrence total is stale");
  }
  if (inventory.occurrences.length !== EXPECTED_COUNTS.queries) {
    fail(`source inventory must contain ${EXPECTED_COUNTS.queries} occurrences`);
  }
  requireEqual(
    registryBinding,
    {
      path: SOURCE_INVENTORY_RELATIVE,
      artifactSha256: EXPECTED_SOURCE_SHA,
      sourceDigest: EXPECTED_SOURCE_DIGEST,
      expectedOccurrences: EXPECTED_COUNTS.queries,
    },
    "registry source inventory binding",
  );
  return new Map(inventory.occurrences.map((entry) => [entry.id, entry]));
}

function validateTargetAuthority(bytes, authority, registryBinding) {
  requireExactKeys(
    authority,
    [
      "schemaVersion",
      "generator",
      "sourceInventory",
      "sourceRegistry",
      "inventoryDigest",
      "physicalPlanes",
      "totals",
      "queries",
    ],
    "target authority",
  );
  if (authority.schemaVersion !== 1) fail("target authority.schemaVersion must equal 1");
  if (authority.generator !== "scripts/generate-target-query-logical-authority-crosswalk.mjs") {
    fail("target authority.generator is unexpected");
  }
  requireExactHash(authority.inventoryDigest, EXPECTED_TARGET_DIGEST, "target inventory digest");
  requireEqual(
    authority.physicalPlanes,
    {
      postgres: { status: "deferred", decision: "A-003" },
      local: { status: "deferred", decision: "A-004" },
    },
    "target physical-plane deferrals",
  );
  requireArray(authority.queries, "target authority.queries", { nonempty: true });
  requireSortedUnique(authority.queries, "target authority.queries", (entry) => entry.tqueryId);
  const result = new Map();
  for (const [index, query] of authority.queries.entries()) {
    const label = `target authority.queries[${index}]`;
    requireString(query.tqueryId, `${label}.tqueryId`, /^TQUERY-[0-9A-F]{12}$/);
    requireString(query.taccessId, `${label}.taccessId`, /^TACCESS-[0-9A-F]{12}$/);
    requireString(query.mappingHash, `${label}.mappingHash`, /^[a-f0-9]{64}$/);
    requireEnum(
      query.reviewClass,
      ["mapped", "mapped_with_unresolved_axes", "decision_blocked"],
      `${label}.reviewClass`,
    );
    requirePlainObject(query.logicalAxes, `${label}.logicalAxes`);
    requireArray(query.unresolvedAxes, `${label}.unresolvedAxes`);
    result.set(query.tqueryId, query);
  }
  requireEqual(
    registryBinding,
    {
      path: TARGET_AUTHORITY_RELATIVE,
      artifactSha256: EXPECTED_TARGET_SHA,
      inventoryDigest: EXPECTED_TARGET_DIGEST,
    },
    "registry target authority binding",
  );
  return result;
}

function validateManifest(manifest) {
  requireExactKeys(
    manifest,
    [
      "schemaVersion",
      "program",
      "sourceBaseline",
      "authority",
      "discovery",
      "dispositionDefinitions",
      "statusDefinitions",
      "milestones",
      "surfaces",
    ],
    "conversion manifest",
  );
  if (manifest.schemaVersion !== 1) fail("conversion manifest.schemaVersion must equal 1");
  requireArray(manifest.surfaces, "conversion manifest.surfaces", { nonempty: true });
  for (const [index, surface] of manifest.surfaces.entries()) {
    requirePlainObject(surface, `conversion manifest.surfaces[${index}]`);
  }
  const ids = manifest.surfaces.map((surface) => surface.id);
  requireUnique(ids, "conversion manifest surface IDs");
  const result = new Map();
  for (const [index, surface] of manifest.surfaces.entries()) {
    const label = `conversion manifest.surfaces[${index}]`;
    requireExactKeys(
      surface,
      [
        "id",
        "kind",
        "name",
        "discovery",
        "sourcePresence",
        "sourceRefs",
        "observedSourceHash",
        "acknowledgedSourceHash",
        "metadata",
        "currentBehavior",
        "disposition",
        "target",
        "migration",
        "verification",
        "status",
        "blockers",
        "evidence",
        "notes",
        "classificationBatch",
      ],
      label,
    );
    requireString(surface.id, `${label}.id`, /^[A-Z][A-Z0-9-]+$/);
    requireString(surface.disposition, `${label}.disposition`);
    requireString(surface.status, `${label}.status`);
    requireArray(surface.sourceRefs, `${label}.sourceRefs`, { nonempty: true });
    for (const [refIndex, ref] of surface.sourceRefs.entries()) {
      exactSourceRef(ref, `${label}.sourceRefs[${refIndex}]`);
    }
    requireArray(surface.blockers, `${label}.blockers`);
    for (const blocker of surface.blockers) requireString(blocker, `${label}.blocker`);
    requireArray(surface.evidence, `${label}.evidence`);
    for (const evidence of surface.evidence) requireString(evidence, `${label}.evidence member`);
    requirePlainObject(surface.metadata, `${label}.metadata`);
    for (const key of Object.keys(surface.metadata)) {
      if (!["firebaseCoupled", "firebaseCoupling"].includes(key)) {
        fail(`${label}.metadata contains unsupported key ${key}`);
      }
    }
    if (Object.hasOwn(surface.metadata, "firebaseCoupled") && typeof surface.metadata.firebaseCoupled !== "boolean") {
      fail(`${label}.metadata.firebaseCoupled must be boolean`);
    }
    if (Object.hasOwn(surface.metadata, "firebaseCoupling")) {
      requireString(surface.metadata.firebaseCoupling, `${label}.metadata.firebaseCoupling`);
    }
    requirePlainObject(surface.target, `${label}.target`);
    requireExactKeys(
      surface.target,
      ["owner", "surfaces", "securityRequirements", "syncRequirements"],
      `${label}.target`,
    );
    if (typeof surface.target.owner !== "string") fail(`${label}.target.owner must be a string`);
    requireArray(surface.target.surfaces, `${label}.target.surfaces`);
    for (const target of surface.target.surfaces) requireString(target, `${label}.target surface`);
    requireArray(surface.target.securityRequirements, `${label}.target.securityRequirements`);
    for (const requirement of surface.target.securityRequirements) {
      requireString(requirement, `${label}.target security requirement`);
    }
    requireArray(surface.target.syncRequirements, `${label}.target.syncRequirements`);
    for (const requirement of surface.target.syncRequirements) {
      requireString(requirement, `${label}.target sync requirement`);
    }
    requireExactKeys(surface.migration, ["rule", "reconciliation"], `${label}.migration`);
    if (typeof surface.migration.rule !== "string") fail(`${label}.migration.rule must be a string`);
    requireArray(surface.migration.reconciliation, `${label}.migration.reconciliation`);
    for (const statement of surface.migration.reconciliation) {
      requireString(statement, `${label}.migration reconciliation statement`);
    }
    requireExactKeys(surface.verification, ["tests", "acceptance"], `${label}.verification`);
    for (const key of ["tests", "acceptance"]) {
      requireArray(surface.verification[key], `${label}.verification.${key}`);
      for (const statement of surface.verification[key]) {
        requireString(statement, `${label}.verification.${key} member`);
      }
    }
    result.set(surface.id, surface);
  }
  return result;
}

function sourceOwnerProjection(surface, sourceRef) {
  return { surfaceId: surface.id, disposition: surface.disposition, sourceRef };
}

export function deriveSourceOwnerHash(surface, sourceRef) {
  return hashProjection(HASH_PREFIX.owner, sourceOwnerProjection(surface, sourceRef));
}

function targetProjection(surface) {
  return { surfaceId: surface.id, disposition: surface.disposition, target: surface.target };
}

export function deriveTargetMappingHash(surface) {
  return hashProjection(HASH_PREFIX.target, targetProjection(surface));
}

function selectSourceOwner(manifestSurfaces, row, occurrence, label) {
  const surface = manifestSurfaces.get(row.sourceOwnerSurfaceId);
  if (!surface) fail(`${label} references missing source owner ${row.sourceOwnerSurfaceId}`);
  const sourceRef = exactSourceRef(row.sourceRef, `${label}.sourceRef`);
  if (sourceRef.path !== occurrence.sourcePath) fail(`${label}.sourceRef path differs from occurrence`);
  const matches = surface.sourceRefs.filter((candidate) => same(candidate, sourceRef));
  if (matches.length !== 1) fail(`${label}.sourceRef must select exactly one owner reference`);
  const ownerHash = deriveSourceOwnerHash(surface, sourceRef);
  requireExactHash(ownerHash, row.expectedSourceOwnerHash, `${label}.expectedSourceOwnerHash`);
  return { surface, sourceRef, ownerHash };
}

function selectTargetSurface(manifestSurfaces, outcome, label) {
  const surface = manifestSurfaces.get(outcome.targetSurfaceId);
  if (!surface) fail(`${label} references missing target surface ${outcome.targetSurfaceId}`);
  requireEnum(surface.disposition, TARGET_DISPOSITIONS, `${label} target disposition`);
  requireEnum(surface.status, TARGET_STATUSES, `${label} target status`);
  if (!surface.target.surfaces.includes(outcome.targetSurface)) {
    fail(`${label}.targetSurface is not an exact target member`);
  }
  const mappingHash = deriveTargetMappingHash(surface);
  requireExactHash(mappingHash, outcome.expectedTargetMappingHash, `${label}.expectedTargetMappingHash`);
  return surface;
}

function validateRetirementAuthorities(root, registry, control) {
  requireArray(registry.retirementAuthorities, "registry.retirementAuthorities", { nonempty: true });
  const expectedRegistry = control.exactRetirementAuthorityDefinitions.map(
    ({ expectedRetirementAuthorityHash: _hash, ...entry }) => entry,
  );
  requireEqual(registry.retirementAuthorities, expectedRegistry, "registry retirement authorities");
  const result = new Map();
  for (const [index, authority] of registry.retirementAuthorities.entries()) {
    const label = `registry.retirementAuthorities[${index}]`;
    const keys =
      authority.kind === "canonical_target_heading"
        ? control.retirementAuthorityHeadingKeys
        : control.retirementAuthorityDecisionKeys;
    requireExactKeys(authority, keys, label);
    const bytes = readRepositoryFile(root, authority.path, `${label} source`);
    let content;
    let prefix;
    if (authority.kind === "confirmed_decision") {
      content = extractDecisionRow(bytes, authority.section, authority.decisionId, label);
      prefix = HASH_PREFIX.retirementDecision;
    } else {
      content = extractHeadingSection(bytes, authority.section, label);
      prefix = HASH_PREFIX.retirementHeading;
      if (authority.kind === "architecture_decision" && !authority.section.startsWith(`${authority.decisionId} `)) {
        fail(`${label}.section does not bind decisionId`);
      }
    }
    requireExactHash(sha256(`${prefix}${content}`), authority.contentSha256, `${label}.contentSha256`);
    const derivedHash = hashProjection(HASH_PREFIX.retirementAuthority, authority);
    const expected = control.exactRetirementAuthorityDefinitions[index];
    requireExactHash(
      derivedHash,
      expected.expectedRetirementAuthorityHash,
      `${label}.expectedRetirementAuthorityHash`,
    );
    result.set(authority.authorityId, { ...authority, expectedRetirementAuthorityHash: derivedHash });
  }
  return result;
}

function validateBlockerAuthorities(root, registry) {
  requireArray(registry.blockerAuthorities, "registry.blockerAuthorities", { nonempty: true });
  requireSortedUnique(registry.blockerAuthorities, "registry.blockerAuthorities", (entry) => entry.id);
  const result = new Map();
  for (const [index, authority] of registry.blockerAuthorities.entries()) {
    const label = `registry.blockerAuthorities[${index}]`;
    validateAuthorityReference(root, authority, label);
    if (FORBIDDEN_BLOCKERS.has(authority.id)) fail(`${label} uses forbidden blocker ${authority.id}`);
    result.set(authority.id, authority);
  }
  return result;
}

function validateEvidenceRequirements(root, registry, manifestSurfaces, control) {
  requireArray(registry.evidenceRequirements, "registry.evidenceRequirements", { nonempty: true });
  requireSortedUnique(registry.evidenceRequirements, "registry.evidenceRequirements", (entry) => entry.id);
  const result = new Map();
  for (const [index, requirement] of registry.evidenceRequirements.entries()) {
    const label = `registry.evidenceRequirements[${index}]`;
    requireExactKeys(requirement, control.evidenceRequirementKeys, label);
    requireString(requirement.id, `${label}.id`, /^E-\d{3}$/);
    requireString(requirement.kind, `${label}.kind`);
    requireString(requirement.requiredArtifact, `${label}.requiredArtifact`);
    extractHeadingSection(readRepositoryFile(root, requirement.path, `${label} source`), requirement.section, label);
    requireArray(requirement.ownerBindings, `${label}.ownerBindings`, { nonempty: true });
    requireSortedUnique(
      requirement.ownerBindings,
      `${label}.ownerBindings`,
      (binding) => binding.surfaceId,
    );
    for (const [bindingIndex, binding] of requirement.ownerBindings.entries()) {
      const bindingLabel = `${label}.ownerBindings[${bindingIndex}]`;
      requireExactKeys(binding, control.evidenceOwnerBindingKeys, bindingLabel);
      const surface = manifestSurfaces.get(binding.surfaceId);
      if (!surface) fail(`${bindingLabel} references missing manifest surface`);
      const sourceRef = exactSourceRef(binding.sourceRef, `${bindingLabel}.sourceRef`);
      if (surface.sourceRefs.filter((ref) => same(ref, sourceRef)).length !== 1) {
        fail(`${bindingLabel}.sourceRef does not uniquely select the manifest owner`);
      }
      const ownerHash = deriveSourceOwnerHash(surface, sourceRef);
      requireExactHash(ownerHash, binding.expectedSourceOwnerHash, `${bindingLabel}.expectedSourceOwnerHash`);
      requireString(binding.blocker, `${bindingLabel}.blocker`);
      if (!surface.blockers.includes(binding.blocker)) {
        fail(`${bindingLabel}.blocker does not exist on selected manifest owner`);
      }
      const expectedBindingHash = hashProjection(HASH_PREFIX.evidence, {
        surfaceId: binding.surfaceId,
        sourceRef,
        expectedSourceOwnerHash: ownerHash,
        blocker: binding.blocker,
      });
      requireExactHash(expectedBindingHash, binding.expectedBindingHash, `${bindingLabel}.expectedBindingHash`);
    }
    result.set(requirement.id, requirement);
  }
  return result;
}

function validateRegistryHeader(registry, dossier, control) {
  requireExactKeys(registry, control.registryKeys, "registry");
  if (registry.schemaVersion !== 1) fail("registry.schemaVersion must equal 1");
  requireEnum(registry.status, LIFECYCLES, "registry.status");
  if (registry.status !== dossier.status) fail("registry and dossier lifecycle differ");
  if (registry.conversionManifestPath !== MANIFEST_RELATIVE) {
    fail("registry.conversionManifestPath is unexpected");
  }
  if (registry.batchDirectory !== control.batchDirectory) {
    fail("registry.batchDirectory differs from control model");
  }
  if (registry.excludedTemplate !== control.onlyExcludedDirectoryEntry) {
    fail("registry.excludedTemplate differs from control model");
  }
  requireString(registry.notes, "registry.notes");
  requireArray(registry.batches, "registry.batches", { nonempty: true });
  if (registry.batches.length !== EXPECTED_COUNTS.batches) {
    fail(`registry must contain ${EXPECTED_COUNTS.batches} batches`);
  }
  for (const [index, descriptor] of registry.batches.entries()) {
    requireExactKeys(descriptor, control.registryBatchKeys, `registry.batches[${index}]`);
  }
  requireEqual(registry.batches, control.exactBatchMetadata, "registry batch metadata");
  requireUnique(registry.batches.map((entry) => entry.path), "registry batch paths");
  requireUnique(registry.batches.map((entry) => entry.batchId), "registry batch IDs");
  requireUnique(registry.batches.map((entry) => entry.owner), "registry batch owners");
  requireEqual(
    registry.currentSourceCompatibilityBindings,
    control.exactCurrentSourceCompatibilityBindings,
    "registry compatibility bindings",
  );
  return registry;
}

function validateBatchDirectory(root, registry, control) {
  const directory = repositoryDirectory(root, registry.batchDirectory, "batch directory");
  const entries = fs.readdirSync(directory, { withFileTypes: true });
  const expectedNames = [...control.exactBatchOrder, control.onlyExcludedDirectoryEntry].sort(compareText);
  const actualNames = entries.map((entry) => entry.name).sort(compareText);
  requireEqual(actualNames, expectedNames, "batch directory entries");
  for (const entry of entries) {
    if (!entry.isFile() || entry.isSymbolicLink()) {
      fail(`batch directory entry must be a regular non-symlink file: ${entry.name}`);
    }
  }
  const templateRelative = `${registry.batchDirectory}/${control.onlyExcludedDirectoryEntry}`;
  const template = readJson(root, templateRelative, "batch template").value;
  requireExactKeys(template, control.batchKeys, "batch template");
  if (template.schemaVersion !== 1 || template.status !== "draft") {
    fail("excluded batch template must remain schemaVersion 1 and draft");
  }
}

function validateBlockerSelection(ids, refs, batch, blockerAuthorities, allowed, label) {
  requireSortedUnique(ids, `${label}.blockerIds`);
  if (ids.length === 0) fail(`${label}.blockerIds must not be empty`);
  for (const id of ids) {
    if (FORBIDDEN_BLOCKERS.has(id)) fail(`${label} uses forbidden blocker ${id}`);
    if (!batch.allowedBlockerIds.includes(id)) fail(`${label} blocker ${id} is not batch-allowed`);
    if (!blockerAuthorities.has(id)) fail(`${label} blocker ${id} is not registry-authorized`);
    if (!allowed.has(id)) fail(`${label} blocker ${id} is not present on the selected authority`);
  }
  requireArray(refs, `${label}.authorityRefs`, { nonempty: true });
  requireEqual(
    refs,
    ids.map((id) => blockerAuthorities.get(id)),
    `${label}.authorityRefs`,
  );
}

function targetQueryBlockers(query, label) {
  const result = [];
  for (const [axisName, axis] of Object.entries(query.logicalAxes)) {
    requirePlainObject(axis, `${label}.logicalAxes.${axisName}`);
    if (axis.state === "decision_blocked") {
      requireArray(axis.blockerIds, `${label}.logicalAxes.${axisName}.blockerIds`, { nonempty: true });
      result.push(...axis.blockerIds);
    }
  }
  for (const [index, axis] of query.unresolvedAxes.entries()) {
    requirePlainObject(axis, `${label}.unresolvedAxes[${index}]`);
    if (axis.state === "decision_blocked") {
      requireArray(axis.blockerIds, `${label}.unresolvedAxes[${index}].blockerIds`, { nonempty: true });
      result.push(...axis.blockerIds);
    }
  }
  return new Set([...new Set(result)].sort(compareText));
}

function outcomeShapeKey(outcome) {
  if (outcome.category === "retired") return `retired_${outcome.scope}`;
  if (outcome.category === "authority_blocked") {
    return `authority_blocked_${outcome.blockedScope}`;
  }
  return outcome.category;
}

function outcomeIdentity(outcome, control) {
  const key = outcome.category === "retired" ? "retired" : outcomeShapeKey(outcome);
  const identityKeys = control.outcomeIdentity[key];
  if (!identityKeys) fail(`missing outcome identity definition for ${key}`);
  return canonicalMinifiedJson(
    Object.fromEntries(identityKeys.map((identityKey) => [identityKey, outcome[identityKey]])),
  );
}

function categoryRank(category) {
  return CATEGORY_ORDER.indexOf(category);
}

function compareOutcomes(left, right) {
  return categoryRank(left.category) - categoryRank(right.category) ||
    compareText(canonicalMinifiedJson(left), canonicalMinifiedJson(right));
}

function validateOutcomeOrder(outcomes, label, control) {
  requireArray(outcomes, `${label}.outcomes`, { nonempty: true });
  const identities = [];
  for (let index = 0; index < outcomes.length; index += 1) {
    const outcome = outcomes[index];
    requireEnum(outcome.category, CATEGORY_ORDER, `${label}.outcomes[${index}].category`);
    if (index > 0 && compareOutcomes(outcomes[index - 1], outcome) >= 0) {
      fail(`${label}.outcomes must be in canonical order`);
    }
    identities.push(outcomeIdentity(outcome, control));
  }
  requireUnique(identities, `${label} outcome identities`);
}

function authorityRefProjection(requirement) {
  return {
    id: requirement.id,
    kind: requirement.kind,
    path: requirement.path,
    section: requirement.section,
    requiredArtifact: requirement.requiredArtifact,
  };
}

function validateEvidenceOutcome(
  outcome,
  rowOwner,
  batch,
  evidenceRequirements,
  control,
  label,
) {
  requireEnum(outcome.blockedScope, EVIDENCE_SCOPES, `${label}.blockedScope`);
  requireSortedUnique(outcome.evidenceRequirementIds, `${label}.evidenceRequirementIds`);
  if (outcome.evidenceRequirementIds.length === 0) {
    fail(`${label}.evidenceRequirementIds must not be empty`);
  }
  for (const id of outcome.evidenceRequirementIds) {
    if (!batch.allowedEvidenceRequirementIds.includes(id)) {
      fail(`${label} evidence requirement ${id} is not batch-allowed`);
    }
    if (!evidenceRequirements.has(id)) fail(`${label} evidence requirement ${id} is unknown`);
  }
  requireArray(outcome.ownerBindings, `${label}.ownerBindings`, { nonempty: true });
  requireSortedUnique(
    outcome.ownerBindings,
    `${label}.ownerBindings`,
    (binding) => binding.evidenceRequirementId,
  );
  if (outcome.ownerBindings.length !== outcome.evidenceRequirementIds.length) {
    fail(`${label}.ownerBindings must select exactly one binding per requirement`);
  }
  const expectedBindings = [];
  for (const id of outcome.evidenceRequirementIds) {
    const requirement = evidenceRequirements.get(id);
    const matches = requirement.ownerBindings.filter(
      (binding) =>
        binding.surfaceId === rowOwner.surface.id &&
        same(binding.sourceRef, rowOwner.sourceRef) &&
        binding.expectedSourceOwnerHash === rowOwner.ownerHash,
    );
    if (matches.length !== 1) fail(`${label} cannot bind ${id} to the complete selected row owner`);
    expectedBindings.push({ evidenceRequirementId: id, ...matches[0] });
  }
  requireEqual(outcome.ownerBindings, expectedBindings, `${label}.ownerBindings`);
  requireEqual(
    outcome.evidenceRefs,
    outcome.evidenceRequirementIds.map((id) => authorityRefProjection(evidenceRequirements.get(id))),
    `${label}.evidenceRefs`,
  );
}

function validateOutcome(
  outcome,
  context,
  label,
) {
  requirePlainObject(outcome, label);
  const {
    row,
    occurrence,
    rowOwner,
    batch,
    control,
    manifestSurfaces,
    targetQueries,
    blockerAuthorities,
    evidenceRequirements,
    retirementAuthorities,
  } = context;
  const shape = outcomeShapeKey(outcome);
  const expectedKeys = control.outcomeKeys[shape];
  if (!expectedKeys) fail(`${label} has unsupported discriminator ${shape}`);
  requireExactKeys(outcome, expectedKeys, label);

  if (outcome.category === "verified_target_query_port") {
    const query = targetQueries.get(outcome.tqueryId);
    if (!query) fail(`${label} references missing TQUERY ${outcome.tqueryId}`);
    const owner = manifestSurfaces.get(query.ownerSurfaceId);
    if (!owner) fail(`${label} references TQUERY with missing manifest owner`);
    if (!VERIFIED_OR_LATER_TARGET_STATUSES.has(owner.status)) {
      fail(`${label} references TQUERY owner below verified lifecycle ${outcome.tqueryId}`);
    }
    if (query.reviewClass === "decision_blocked") fail(`${label} references decision-blocked TQUERY`);
    if (outcome.taccessId !== query.taccessId || outcome.expectedMappingHash !== query.mappingHash) {
      fail(`${label} does not bind the exact target-query authority row`);
    }
    return;
  }

  if (["approved_future_target_query", "approved_target_nonquery_surface"].includes(outcome.category)) {
    selectTargetSurface(manifestSurfaces, outcome, label);
    return;
  }

  if (outcome.category === "source_only") {
    if (
      outcome.sourceOwnerSurfaceId !== row.sourceOwnerSurfaceId ||
      !same(outcome.sourceRef, rowOwner.sourceRef)
    ) {
      fail(`${label} must reuse the exact row source owner and reference`);
    }
    if (rowOwner.surface.disposition !== "source_only") {
      fail(`${label} source owner disposition must equal source_only`);
    }
    requireEnum(outcome.purpose, SOURCE_ONLY_PURPOSES, `${label}.purpose`);
    requireEnum(outcome.retentionGate, RETENTION_GATES, `${label}.retentionGate`);
    requireEqual(
      {
        sourceLifecycleAuthorityId: outcome.sourceLifecycleAuthorityId,
        expectedSourceLifecycleAuthorityHash: outcome.expectedSourceLifecycleAuthorityHash,
      },
      control.sourceOnlyAuthorityBinding,
      `${label} source lifecycle authority`,
    );
    if (!retirementAuthorities.has(outcome.sourceLifecycleAuthorityId)) {
      fail(`${label} source lifecycle authority is missing`);
    }
    if (outcome.purpose === "current_source_compatibility") {
      const binding = {
        queryId: row.queryId,
        sourceOwnerSurfaceId: row.sourceOwnerSurfaceId,
        sourceRef: rowOwner.sourceRef,
        expectedSourceOwnerHash: rowOwner.ownerHash,
        retentionGate: outcome.retentionGate,
      };
      if (!control.exactCurrentSourceCompatibilityBindings.some((entry) => same(entry, binding))) {
        fail(`${label} widens current_source_compatibility`);
      }
      if (occurrence.operation !== "document_read") {
        fail(`${label} compatibility occurrence must remain document_read`);
      }
    }
    return;
  }

  if (outcome.category === "retired") {
    requireEnum(outcome.scope, control.retirementScopeEnums, `${label}.scope`);
    requireEnum(outcome.retirementGate, RETIREMENT_GATES, `${label}.retirementGate`);
    const authority = retirementAuthorities.get(outcome.retirementAuthorityId);
    if (!authority) fail(`${label} retirement authority is unknown`);
    requireExactHash(
      authority.expectedRetirementAuthorityHash,
      outcome.expectedRetirementAuthorityHash,
      `${label}.expectedRetirementAuthorityHash`,
    );
    if (outcome.scope === "source_query_mechanism_only") {
      requireEqual(
        {
          retirementAuthorityId: outcome.retirementAuthorityId,
          expectedRetirementAuthorityHash: outcome.expectedRetirementAuthorityHash,
        },
        control.mechanismRetirementAuthorityBinding,
        `${label} mechanism retirement authority`,
      );
      if (outcome.retirementGate === "at_verified_target_cutover") {
        fail(`${label} mechanism retirement cannot occur at cutover`);
      }
    } else if (outcome.retirementGate !== "at_verified_target_cutover") {
      fail(`${label} source behavior retirement must occur at verified target cutover`);
    }
    return;
  }

  if (outcome.category === "authority_blocked") {
    requireEnum(outcome.blockedScope, BLOCKED_SCOPES, `${label}.blockedScope`);
    let allowed;
    if (outcome.blockedScope === "target_query_contract") {
      const query = targetQueries.get(outcome.tqueryId);
      if (!query) fail(`${label} references missing blocked TQUERY`);
      if (outcome.taccessId !== query.taccessId || outcome.expectedMappingHash !== query.mappingHash) {
        fail(`${label} does not bind the exact blocked target-query row`);
      }
      allowed = targetQueryBlockers(query, label);
    } else if (outcome.blockedScope === "target_nonquery_contract") {
      const target = selectTargetSurface(manifestSurfaces, outcome, label);
      allowed = new Set(target.blockers);
    } else {
      allowed = new Set(rowOwner.surface.blockers);
    }
    validateBlockerSelection(
      outcome.blockerIds,
      outcome.authorityRefs,
      batch,
      blockerAuthorities,
      allowed,
      label,
    );
    return;
  }

  if (outcome.category === "evidence_blocked") {
    validateEvidenceOutcome(outcome, rowOwner, batch, evidenceRequirements, control, label);
    return;
  }
  fail(`${label} has unsupported category`);
}

function normalizedOutcomeKind(outcome, control) {
  let key = outcome.category;
  if (outcome.category === "retired") key = `retired_${outcome.scope}`;
  if (outcome.category === "authority_blocked") {
    key = `authority_blocked_${outcome.blockedScope}`;
  }
  if (outcome.category === "evidence_blocked") {
    key = `evidence_blocked_${outcome.blockedScope}`;
  }
  const kind = control.outcomeConflictMatrix.categoryKinds[key];
  if (!kind) fail(`outcome conflict kind is missing for ${key}`);
  return kind;
}

function targetIdentity(outcome) {
  if (["verified_target_query_port"].includes(outcome.category)) {
    return `query:${outcome.tqueryId}:${outcome.taccessId}`;
  }
  if (["approved_future_target_query", "approved_target_nonquery_surface"].includes(outcome.category)) {
    return `surface:${outcome.targetSurfaceId}:${outcome.targetSurface}`;
  }
  if (outcome.category === "authority_blocked" && outcome.blockedScope === "target_query_contract") {
    return `query:${outcome.tqueryId}:${outcome.taccessId}`;
  }
  if (outcome.category === "authority_blocked" && outcome.blockedScope === "target_nonquery_contract") {
    return `surface:${outcome.targetSurfaceId}:${outcome.targetSurface}`;
  }
  return null;
}

function evaluateConditional(predicate, left, right) {
  const outcomes = [left, right];
  if (predicate === "target_retirement_gate") {
    const retirement = outcomes.find(
      (outcome) => outcome.category === "retired" && outcome.scope === "source_query_mechanism_only",
    );
    return retirement !== undefined && GATE_RANK[retirement.retirementGate] >= GATE_RANK.after_verified_target_cutover;
  }
  if (predicate === "retention_before_retirement") {
    const retention = outcomes.find((outcome) => outcome.category === "source_only");
    const retirement = outcomes.find(
      (outcome) => outcome.category === "retired" && outcome.scope === "source_query_mechanism_only",
    );
    return (
      retention !== undefined &&
      retirement !== undefined &&
      GATE_RANK[retirement.retirementGate] > GATE_RANK[retention.retentionGate]
    );
  }
  if (predicate === "disjoint_target_identity") {
    const leftIdentity = targetIdentity(left);
    const rightIdentity = targetIdentity(right);
    return leftIdentity !== null && rightIdentity !== null && leftIdentity !== rightIdentity;
  }
  if (predicate === "distinct_evidence_scope") {
    return (
      left.blockedScope !== right.blockedScope &&
      canonicalMinifiedJson(left) !== canonicalMinifiedJson(right)
    );
  }
  fail(`unsupported conflict predicate ${predicate}`);
}

function validateOutcomeConflicts(outcomes, control, label) {
  const matrix = control.outcomeConflictMatrix.matrix;
  const kinds = outcomes.map((outcome) => normalizedOutcomeKind(outcome, control));
  const counts = countBy(kinds, (kind) => kind);
  for (const singleton of ["source_retention", "mechanism_retirement", "behavior_retirement"]) {
    if ((counts[singleton] ?? 0) > 1) fail(`${label} has more than one ${singleton} outcome`);
  }
  const authorityScopes = outcomes
    .filter((outcome) => outcome.category === "authority_blocked")
    .map((outcome) => outcome.blockedScope);
  requireUnique(authorityScopes, `${label} authority-blocked scopes`);
  const evidenceScopes = outcomes
    .filter((outcome) => outcome.category === "evidence_blocked")
    .map((outcome) => outcome.blockedScope);
  requireUnique(evidenceScopes, `${label} evidence-blocked scopes`);

  for (let leftIndex = 0; leftIndex < outcomes.length; leftIndex += 1) {
    for (let rightIndex = leftIndex + 1; rightIndex < outcomes.length; rightIndex += 1) {
      const leftKind = kinds[leftIndex];
      const rightKind = kinds[rightIndex];
      const rule = matrix[leftKind]?.[rightKind];
      if (rule === "allow") continue;
      if (rule === "deny") {
        fail(`${label} outcomes ${leftIndex}/${rightIndex} conflict (${leftKind}/${rightKind})`);
      }
      if (typeof rule !== "string" || !rule.startsWith("conditional:")) {
        fail(`${label} has invalid conflict rule for ${leftKind}/${rightKind}`);
      }
      const predicate = rule.slice("conditional:".length);
      if (!evaluateConditional(predicate, outcomes[leftIndex], outcomes[rightIndex])) {
        fail(`${label} outcomes ${leftIndex}/${rightIndex} fail ${predicate}`);
      }
    }
  }

  const mechanism = outcomes.find(
    (outcome) => outcome.category === "retired" && outcome.scope === "source_query_mechanism_only",
  );
  if (mechanism) {
    const hasTarget = outcomes.some((outcome) =>
      [
        "verified_target_query_port",
        "approved_future_target_query",
        "approved_target_nonquery_surface",
      ].includes(outcome.category),
    );
    const retention = outcomes.filter((outcome) => outcome.category === "source_only");
    if (!hasTarget && retention.length === 0) {
      fail(`${label} mechanism retirement lacks target preservation or source retention`);
    }
    if (hasTarget && GATE_RANK[mechanism.retirementGate] < GATE_RANK.after_verified_target_cutover) {
      fail(`${label} mechanism retirement precedes verified target cutover`);
    }
    for (const sourceOnly of retention) {
      if (GATE_RANK[mechanism.retirementGate] <= GATE_RANK[sourceOnly.retentionGate]) {
        fail(`${label} mechanism retirement does not follow source retention`);
      }
    }
  }
}

function stripLifecycleNarrative(value) {
  if (Array.isArray(value)) return value.map(stripLifecycleNarrative);
  if (!isPlainObject(value)) return value;
  return Object.fromEntries(
    Object.entries(value)
      .filter(([key]) => key !== "status" && key !== "notes")
      .map(([key, nested]) => [key, stripLifecycleNarrative(nested)]),
  );
}

function baselineJson(root, baseCommit, relativePath, label) {
  const bytes = runGit(root, ["show", `${baseCommit}:${relativePath}`], label);
  return parseJson(bytes, label);
}

function validateReadySemanticFreeze(root, dossier, registry, batches, { enforceRepositoryDiff = true } = {}) {
  if (!enforceRepositoryDiff || !["implemented", "verified"].includes(dossier.status)) return;
  const base = dossier.controlModel.lifecycleAllowlists.implementation.baseCommit;
  const baseRegistry = baselineJson(root, base, REGISTRY_RELATIVE, "READY registry baseline");
  const reboundBaseRegistry = structuredClone(baseRegistry);
  reboundBaseRegistry.targetAuthority = registry.targetAuthority;
  requireEqual(
    stripLifecycleNarrative(registry),
    stripLifecycleNarrative(reboundBaseRegistry),
    "registry semantic READY freeze",
  );
  for (const { descriptor, batch } of batches) {
    const baseBatch = baselineJson(root, base, descriptor.path, `READY batch ${descriptor.batchId}`);
    requireEqual(
      stripLifecycleNarrative(batch),
      stripLifecycleNarrative(baseBatch),
      `${descriptor.batchId} semantic READY freeze`,
    );
  }
}

function validateBatch(
  batch,
  descriptor,
  context,
  aggregate,
) {
  const { dossier, registry, control, sourceOccurrences } = context;
  const label = descriptor.batchId;
  requireExactKeys(batch, control.batchKeys, label);
  if (batch.schemaVersion !== 1) fail(`${label}.schemaVersion must equal 1`);
  if (batch.batchId !== descriptor.batchId || batch.owner !== descriptor.owner) {
    fail(`${label} metadata differs from registry descriptor`);
  }
  if (batch.status !== registry.status || batch.status !== dossier.status) {
    fail(`${label} lifecycle is not synchronized`);
  }
  requireSortedUnique(batch.assignedQueryIds, `${label}.assignedQueryIds`);
  requireSortedUnique(batch.allowedBlockerIds, `${label}.allowedBlockerIds`);
  requireSortedUnique(batch.allowedEvidenceRequirementIds, `${label}.allowedEvidenceRequirementIds`);
  requireArray(batch.rows, `${label}.rows`);
  requireSortedUnique(batch.rows, `${label}.rows`, (row) => row.queryId);
  requireString(batch.notes, `${label}.notes`);
  const assigned = new Set(batch.assignedQueryIds);
  const rowIds = batch.rows.map((row) => row.queryId);
  if (LIFECYCLES.indexOf(batch.status) > 0) {
    requireEqual(rowIds, batch.assignedQueryIds, `${label} READY row assignment`);
  } else if (rowIds.some((queryId) => !assigned.has(queryId))) {
    fail(`${label} draft rows are not a subset of assignments`);
  }

  const generatedRows = [];
  for (const [rowIndex, row] of batch.rows.entries()) {
    const rowLabel = `${label}.rows[${rowIndex}]`;
    requireExactKeys(row, control.rowKeys, rowLabel);
    requireString(row.queryId, `${rowLabel}.queryId`, /^QUERY-[0-9A-F]{12}$/);
    const occurrence = sourceOccurrences.get(row.queryId);
    if (!occurrence) fail(`${rowLabel} references missing source occurrence`);
    requireExactHash(
      deriveOccurrenceHash(occurrence),
      row.expectedOccurrenceHash,
      `${rowLabel}.expectedOccurrenceHash`,
    );
    requireString(row.sourceOwnerSurfaceId, `${rowLabel}.sourceOwnerSurfaceId`);
    requireString(row.expectedSourceOwnerHash, `${rowLabel}.expectedSourceOwnerHash`, /^[a-f0-9]{64}$/);
    const rowOwner = selectSourceOwner(
      context.manifestSurfaces,
      row,
      occurrence,
      rowLabel,
    );
    requireArray(row.outcomes, `${rowLabel}.outcomes`, { nonempty: true });
    for (const [outcomeIndex, outcome] of row.outcomes.entries()) {
      validateOutcome(
        outcome,
        { ...context, row, occurrence, rowOwner, batch },
        `${rowLabel}.outcomes[${outcomeIndex}]`,
      );
    }
    validateOutcomeOrder(row.outcomes, rowLabel, control);
    validateOutcomeConflicts(row.outcomes, control, rowLabel);
    for (const outcome of row.outcomes) {
      aggregate.outcomes += 1;
      aggregate.byCategory[outcome.category] = (aggregate.byCategory[outcome.category] ?? 0) + 1;
      if (outcome.category === "authority_blocked") {
        aggregate.authorityOutcomeCount += 1;
        aggregate.authorityRows.add(row.queryId);
        aggregate.authorityByScope[outcome.blockedScope] =
          (aggregate.authorityByScope[outcome.blockedScope] ?? 0) + 1;
      }
      if (outcome.category === "evidence_blocked") {
        aggregate.evidenceOutcomeCount += 1;
        aggregate.evidenceRows.add(row.queryId);
        aggregate.evidenceByScope[outcome.blockedScope] =
          (aggregate.evidenceByScope[outcome.blockedScope] ?? 0) + 1;
      }
      if (outcome.category === "source_only" && outcome.purpose === "current_source_compatibility") {
        aggregate.compatibilityRows.push(row.queryId);
      }
    }
    aggregate.bySubsystem[occurrence.subsystem] =
      (aggregate.bySubsystem[occurrence.subsystem] ?? 0) + 1;
    generatedRows.push({
      queryId: row.queryId,
      occurrence,
      sourceOwner: {
        surfaceId: rowOwner.surface.id,
        sourceRef: rowOwner.sourceRef,
        disposition: rowOwner.surface.disposition,
        sourceOwnerHash: rowOwner.ownerHash,
      },
      outcomes: row.outcomes,
    });
  }
  return {
    batchId: batch.batchId,
    owner: batch.owner,
    lifecycle: batch.status,
    totals: {
      queries: batch.rows.length,
      outcomes: batch.rows.reduce((total, row) => total + row.outcomes.length, 0),
      authorityBlockedOutcomes: batch.rows.reduce(
        (total, row) => total + row.outcomes.filter((outcome) => outcome.category === "authority_blocked").length,
        0,
      ),
      evidenceBlockedOutcomes: batch.rows.reduce(
        (total, row) => total + row.outcomes.filter((outcome) => outcome.category === "evidence_blocked").length,
        0,
      ),
    },
    rows: generatedRows,
  };
}

function validateGlobalAssignments(sourceOccurrences, batches) {
  const assignments = [];
  for (const { batch } of batches) assignments.push(...batch.assignedQueryIds);
  requireUnique(assignments, "global assignedQueryIds");
  const sorted = [...assignments].sort(compareText);
  const sourceIds = [...sourceOccurrences.keys()].sort(compareText);
  requireEqual(sorted, sourceIds, "global source-query assignment");
}

function validateCompatibilityCoverage(control, aggregate) {
  const expected = control.exactCurrentSourceCompatibilityBindings
    .map((entry) => entry.queryId)
    .sort(compareText);
  requireEqual(
    [...aggregate.compatibilityRows].sort(compareText),
    expected,
    "current-source compatibility coverage",
  );
}

const EXPECTED_CATEGORY_COUNTS = Object.freeze({
  approved_future_target_query: 73,
  approved_target_nonquery_surface: 38,
  authority_blocked: 115,
  evidence_blocked: 6,
  retired: 210,
  source_only: 137,
  verified_target_query_port: 5,
});
const EXPECTED_AUTHORITY_SCOPE_COUNTS = Object.freeze({
  retirement: 3,
  source_disposition: 100,
  target_nonquery_contract: 1,
  target_query_contract: 11,
});
const EXPECTED_EVIDENCE_SCOPE_COUNTS = Object.freeze({
  source_reference_safety: 2,
  source_runtime_use: 4,
});

function validateBatchAllowlists(batch, blockerAuthorities, evidenceRequirements) {
  for (const id of batch.allowedBlockerIds) {
    if (FORBIDDEN_BLOCKERS.has(id)) fail(`${batch.batchId} allows forbidden blocker ${id}`);
    if (!blockerAuthorities.has(id)) fail(`${batch.batchId} allows unknown blocker ${id}`);
  }
  for (const id of batch.allowedEvidenceRequirementIds) {
    if (!evidenceRequirements.has(id)) {
      fail(`${batch.batchId} allows unknown evidence requirement ${id}`);
    }
  }
}

function assertGeneratedBoundary(artifact) {
  const forbiddenKeys = new Set([
    "physicalAccess",
    "tindexId",
    "indexId",
    "indexName",
    "primaryKeyCandidate",
    "secondaryRequired",
    "sql",
    "table",
    "column",
    "rls",
    "policy",
    "syncStream",
    "provider",
    "hosted",
    "production",
    "conversionManifestHash",
    "lastSynchronizedAt",
    "artifactSha256",
  ]);
  function visit(value, location) {
    if (Array.isArray(value)) {
      value.forEach((entry, index) => visit(entry, `${location}[${index}]`));
      return;
    }
    if (!isPlainObject(value)) return;
    for (const [key, nested] of Object.entries(value)) {
      if (forbiddenKeys.has(key)) fail(`generated artifact contains forbidden key ${key} at ${location}`);
      visit(nested, `${location}.${key}`);
    }
  }
  visit(artifact, "artifact");
  const rendered = JSON.stringify(artifact);
  if (rendered.includes("A-003") || rendered.includes("A-004")) {
    fail("generated artifact must not contain physical-plane decisions A-003/A-004");
  }
}

export function buildReconciliation(inputs, options = {}) {
  const {
    root,
    dossier,
    registry,
    sourceInventory,
    sourceInventoryBytes,
    targetAuthority,
    targetAuthorityBytes,
    manifest,
    batches,
  } = inputs;
  const control = validateDossier(dossier);
  requireArray(batches, "input batches", { nonempty: true });
  for (const [index, entry] of batches.entries()) {
    requireExactKeys(entry, ["descriptor", "batch"], `input batches[${index}]`);
    requirePlainObject(entry.descriptor, `input batches[${index}].descriptor`);
    requirePlainObject(entry.batch, `input batches[${index}].batch`);
  }
  validateRepositoryIntegrationHooks(root);
  validateRegistryHeader(registry, dossier, control);
  const manifestSurfaces = validateManifest(manifest);
  const sourceOccurrences = validateSourceInventory(
    root,
    sourceInventoryBytes,
    sourceInventory,
    registry.sourceInventory,
  );
  const targetQueries = validateTargetAuthority(
    targetAuthorityBytes,
    targetAuthority,
    registry.targetAuthority,
  );
  const blockerAuthorities = validateBlockerAuthorities(root, registry);
  const evidenceRequirements = validateEvidenceRequirements(
    root,
    registry,
    manifestSurfaces,
    control,
  );
  const retirementAuthorities = validateRetirementAuthorities(root, registry, control);
  validateGlobalAssignments(sourceOccurrences, batches);
  validateReadySemanticFreeze(root, dossier, registry, batches, options);

  const aggregate = {
    outcomes: 0,
    byCategory: {},
    bySubsystem: {},
    authorityOutcomeCount: 0,
    authorityRows: new Set(),
    authorityByScope: {},
    evidenceOutcomeCount: 0,
    evidenceRows: new Set(),
    evidenceByScope: {},
    compatibilityRows: [],
  };
  const generatedBatches = [];
  for (const { descriptor, batch } of batches) {
    validateBatchAllowlists(batch, blockerAuthorities, evidenceRequirements);
    generatedBatches.push(
      validateBatch(
        batch,
        descriptor,
        {
          root,
          dossier,
          registry,
          control,
          sourceOccurrences,
          manifestSurfaces,
          targetQueries,
          blockerAuthorities,
          evidenceRequirements,
          retirementAuthorities,
        },
        aggregate,
      ),
    );
  }
  requireExactHash(sha256(sourceInventoryBytes), EXPECTED_SOURCE_SHA, "source inventory artifact hash");
  requireEqual(
    sourceInventory,
    parseJson(sourceInventoryBytes, "source inventory bytes"),
    "source inventory parsed bytes",
  );
  requireExactHash(sha256(targetAuthorityBytes), EXPECTED_TARGET_SHA, "target authority artifact hash");
  requireEqual(
    targetAuthority,
    parseJson(targetAuthorityBytes, "target authority bytes"),
    "target authority parsed bytes",
  );
  const queryCount = generatedBatches.reduce((total, batch) => total + batch.rows.length, 0);
  const classificationComplete = dossier.status !== "draft";
  if (classificationComplete) {
    if (queryCount !== EXPECTED_COUNTS.queries) {
      fail(`generated query total must equal ${EXPECTED_COUNTS.queries}`);
    }
    if (aggregate.outcomes !== EXPECTED_COUNTS.outcomes) {
      fail(`generated outcome total must equal ${EXPECTED_COUNTS.outcomes}`);
    }
    requireEqual(aggregate.byCategory, EXPECTED_CATEGORY_COUNTS, "outcome category totals");
    requireEqual(
      aggregate.authorityByScope,
      EXPECTED_AUTHORITY_SCOPE_COUNTS,
      "authority-blocked scope totals",
    );
    requireEqual(
      aggregate.evidenceByScope,
      EXPECTED_EVIDENCE_SCOPE_COUNTS,
      "evidence-blocked scope totals",
    );
    requireEqual(aggregate.bySubsystem, sourceInventory.bySubsystem, "generated subsystem totals");
    validateCompatibilityCoverage(control, aggregate);
  }

  const artifact = {
    schemaVersion: 1,
    generator: GENERATOR_RELATIVE,
    sourceRegistry: REGISTRY_RELATIVE,
    lifecycle: dossier.status,
    classificationState: classificationComplete
      ? "complete_with_unresolved_outcomes"
      : "draft_partial",
    sourceInventory: {
      path: SOURCE_INVENTORY_RELATIVE,
      sha256: EXPECTED_SOURCE_SHA,
      sourceDigest: EXPECTED_SOURCE_DIGEST,
      occurrences: EXPECTED_COUNTS.queries,
    },
    targetAuthority: {
      path: TARGET_AUTHORITY_RELATIVE,
      sha256: EXPECTED_TARGET_SHA,
      inventoryDigest: EXPECTED_TARGET_DIGEST,
    },
    unresolvedPromotionGuard: {
      state: "fail_closed",
      authorityBlockedRows: aggregate.authorityRows.size,
      authorityBlockedOutcomes: aggregate.authorityOutcomeCount,
      evidenceBlockedRows: aggregate.evidenceRows.size,
      evidenceBlockedOutcomes: aggregate.evidenceOutcomeCount,
    },
    totals: {
      batches: generatedBatches.length,
      queries: queryCount,
      outcomes: aggregate.outcomes,
      byCategory: aggregate.byCategory,
      bySubsystem: aggregate.bySubsystem,
      authorityBlocked: {
        rows: aggregate.authorityRows.size,
        outcomes: aggregate.authorityOutcomeCount,
        byScope: aggregate.authorityByScope,
      },
      evidenceBlocked: {
        rows: aggregate.evidenceRows.size,
        outcomes: aggregate.evidenceOutcomeCount,
        byScope: aggregate.evidenceByScope,
      },
    },
    batches: generatedBatches,
  };
  assertGeneratedBoundary(artifact);
  return canonicalize(artifact);
}

function loadRepositoryInputs(root) {
  const dossier = readJson(root, DOSSIER_RELATIVE, "source-query reconciliation dossier").value;
  const registry = readJson(root, REGISTRY_RELATIVE, "source-query reconciliation registry").value;
  const control = dossier.controlModel;
  validateBatchDirectory(root, registry, control);
  const source = readJson(root, registry.sourceInventory.path, "source-query inventory");
  const target = readJson(root, registry.targetAuthority.path, "target-query authority");
  const manifest = readJson(root, registry.conversionManifestPath, "conversion manifest").value;
  const batches = registry.batches.map((descriptor, index) => {
    const batch = readJson(root, descriptor.path, `source-query batch ${index}`).value;
    return { descriptor, batch };
  });
  return {
    root,
    dossier,
    registry,
    sourceInventory: source.value,
    sourceInventoryBytes: source.bytes,
    targetAuthority: target.value,
    targetAuthorityBytes: target.bytes,
    manifest,
    batches,
  };
}

export function buildRepositoryReconciliation(root = ROOT, options = {}) {
  const realRoot = repositoryRoot(root);
  const inputs = loadRepositoryInputs(realRoot);
  const artifact = buildReconciliation(inputs, options);
  validateLifecycleAllowlist(realRoot, inputs.dossier, options);
  return artifact;
}

export function renderArtifact(artifact) {
  return `${JSON.stringify(canonicalize(artifact), null, 2)}\n`;
}

export function artifactPath(root = ROOT) {
  return path.join(path.resolve(root), ARTIFACT_RELATIVE);
}

export function writeArtifact(rendered, filePath = artifactPath(), options = {}) {
  const root = options.root ?? ROOT;
  const { candidate, parent } = artifactParent(root, filePath);
  let candidateMetadata;
  try {
    candidateMetadata = fs.lstatSync(candidate);
  } catch (error) {
    if (error?.code !== "ENOENT") {
      fail(`could not inspect generated artifact: ${error.message}`);
    }
  }
  if (candidateMetadata !== undefined) {
    const metadata = candidateMetadata;
    if (metadata.isSymbolicLink() || !metadata.isFile()) {
      fail("generated artifact must be a regular non-symlink file when present");
    }
  }
  const token = (options.randomBytes ?? crypto.randomBytes)(16).toString("hex");
  const temporary = path.join(parent, `.${path.basename(candidate)}.${process.pid}.${token}.tmp`);
  let descriptor;
  let created = false;
  try {
    const flags = fs.constants.O_CREAT | fs.constants.O_EXCL | fs.constants.O_WRONLY |
      (fs.constants.O_NOFOLLOW ?? 0);
    descriptor = fs.openSync(temporary, flags, 0o666);
    created = true;
    const temporaryMetadata = fs.fstatSync(descriptor);
    if (!temporaryMetadata.isFile()) fail("generated temporary must be a regular file");
    fs.writeFileSync(descriptor, rendered, "utf8");
    fs.fsyncSync(descriptor);
    fs.closeSync(descriptor);
    descriptor = undefined;
    fs.renameSync(temporary, candidate);
    created = false;
  } catch (error) {
    if (descriptor !== undefined) {
      try {
        fs.closeSync(descriptor);
      } catch {}
    }
    if (created) {
      try {
        fs.unlinkSync(temporary);
      } catch {}
    }
    if (error?.message?.startsWith("source-query-reconciliation:")) throw error;
    fail(`could not atomically write generated artifact: ${error.message}`);
  }
}

export function checkArtifact(rendered, filePath = artifactPath(), options = {}) {
  const root = options.root ?? ROOT;
  const lexicalRoot = path.resolve(root);
  const relative = path.relative(lexicalRoot, path.resolve(filePath)).split(path.sep).join("/");
  const current = readRepositoryFile(root, relative, "generated artifact").toString("utf8");
  if (current !== rendered) fail(`stale generated artifact: ${relative}`);
}

export function execute(mode, options = {}) {
  const root = options.root ?? ROOT;
  const built = buildRepositoryReconciliation(root, { enforceRepositoryDiff: true });
  const rendered = renderArtifact(built);
  const outputPath = options.artifactPath ?? artifactPath(root);
  if (path.resolve(outputPath) !== path.resolve(artifactPath(root))) {
    fail(`execute output must equal ${ARTIFACT_RELATIVE}`);
  }
  if (mode === "generate") {
    writeArtifact(rendered, outputPath, { root });
    process.stdout.write(
      `source-query-reconciliation: generated ${built.totals.queries} queries / ${built.totals.outcomes} outcomes\n`,
    );
    return;
  }
  if (mode === "check") {
    checkArtifact(rendered, outputPath, { root });
    process.stdout.write(
      `source-query-reconciliation: check passed for ${built.totals.queries} queries / ${built.totals.outcomes} outcomes\n`,
    );
    return;
  }
  fail(`unsupported mode ${mode}`);
}

export function executeArguments(argv, options = {}) {
  if (argv.length !== 1 || !["generate", "check"].includes(argv[0])) {
    fail("usage: node scripts/generate-source-query-reconciliation.mjs <generate|check>");
  }
  execute(argv[0], options);
}

const isDirect =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (isDirect) {
  try {
    executeArguments(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  }
}
