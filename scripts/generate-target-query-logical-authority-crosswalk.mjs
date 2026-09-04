#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
export const GENERATOR_RELATIVE =
  "scripts/generate-target-query-logical-authority-crosswalk.mjs";
export const INVENTORY_RELATIVE =
  "docs/plans/ledger-accounting-redesign/conversion/target-query-port-inventory.generated.json";
export const REGISTRY_RELATIVE =
  "docs/plans/ledger-accounting-redesign/conversion/target-query-logical-authority-registry.json";
export const ARTIFACT_RELATIVE =
  "docs/plans/ledger-accounting-redesign/conversion/target-query-logical-authority-crosswalk.generated.json";

export const REVIEW_CLASSES = Object.freeze([
  "mapped",
  "mapped_with_unresolved_axes",
  "decision_blocked",
]);
export const AUTHORITY_ROLES = Object.freeze([
  "canonical_target",
  "architecture_authority",
  "conversion_control",
  "verification_evidence",
]);
export const LOGICAL_AXIS_STATES = Object.freeze([
  "reviewed",
  "not_defined_by_current_contract",
  "decision_blocked",
]);
export const DECISION_IDS = Object.freeze([
  "A-003",
  "A-004",
  "A-007",
  "A-010",
  "A-015",
  "A-016",
  "O-007",
  "O-015",
  "O-026",
  "O-040",
]);
export const DATA_DOMAINS = Object.freeze([
  "identity_bootstrap",
  "account_catalog",
  "project_workspace",
  "project_workspace_or_inventory_by_immutable_scope",
  "derived_from_project_directory_without_separate_canonical_authority",
  "multi_domain_local_journal_and_authoritative_outcomes",
  "multi_domain_identity_project_inventory_and_local_journal",
]);
export const UNRESOLVED_AXIS_NAMES = Object.freeze([
  "occurrence_and_provenance_persistence",
  "deterministic_storage_order",
  "exact_visibility_download_capability",
  "canonical_directory_order",
  "contribution_source_eligibility_and_taxonomy",
  "authorization_merge_and_domain_routing",
  "optimistic_projection_representation_if_required",
  "issuer_subject_to_principal_resolution",
  "offline_unlock_and_revocation_window",
  "feature_retention_target_stream_authorization_and_migration",
  "project_workspace_dependency_if_retained",
]);

const LOGICAL_AXIS_NAMES = Object.freeze([
  "scope",
  "result",
  "ordering",
  "pagination",
  "readiness",
  "authorization",
]);
const EXPECTED_COUNTS = Object.freeze({
  ownerSurfaces: 16,
  protocols: 16,
  methods: 18,
  observationMethods: 18,
  requestResponseMethods: 0,
});
const EXPECTED_REVIEW_COUNTS = Object.freeze({
  mapped: 6,
  mapped_with_unresolved_axes: 11,
  decision_blocked: 1,
});
const INVENTORY_GENERATOR = "scripts/generate-target-query-port-inventory.mjs";
const INVENTORY_SOURCE_ROOT = "LedgeriOS/LedgerTargetCore";

function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function fail(message) {
  throw new Error(`target-query-logical-authority: ${message}`);
}

function compareText(left, right) {
  return left < right ? -1 : left > right ? 1 : 0;
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

function requireExactKeys(value, expected, label) {
  requirePlainObject(value, label);
  const actual = Object.keys(value).sort(compareText);
  const wanted = [...expected].sort(compareText);
  if (actual.length !== wanted.length || actual.some((key, index) => key !== wanted[index])) {
    const unexpected = actual.filter((key) => !wanted.includes(key));
    const missing = wanted.filter((key) => !actual.includes(key));
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

function requireSafeRelativePath(relativePath, label) {
  requireString(relativePath, label);
  if (
    path.isAbsolute(relativePath) ||
    relativePath.includes("\\") ||
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
    relative.startsWith(`..${path.sep}`) ||
    relative === ".." ||
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
      fail(`missing ${label}: ${cursor}`);
    }
    if (metadata.isSymbolicLink()) fail(`${label} must not traverse a symlink: ${cursor}`);
    if (index < limit - 1 && !metadata.isDirectory()) {
      fail(`${label} parent must be a directory: ${cursor}`);
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
  const realCandidate = fs.realpathSync(candidate);
  requireContained(realRoot, realCandidate, label);
  return candidate;
}

function artifactParent(root, filePath) {
  const lexicalRoot = path.resolve(root);
  const realRoot = repositoryRoot(root);
  const lexicalCandidate = path.resolve(filePath);
  const relative = path.relative(lexicalRoot, lexicalCandidate);
  if (
    relative === "" ||
    relative.startsWith(`..${path.sep}`) ||
    relative === ".." ||
    path.isAbsolute(relative)
  ) {
    fail("generated artifact escapes repository root");
  }
  const candidate = path.join(realRoot, relative);
  validatePathComponents(realRoot, candidate, "generated artifact", { includeFinal: false });
  const parent = path.dirname(candidate);
  const metadata = fs.lstatSync(parent);
  if (metadata.isSymbolicLink() || !metadata.isDirectory()) {
    fail(`generated artifact parent must be a non-symlink directory: ${parent}`);
  }
  requireContained(realRoot, fs.realpathSync(parent), "generated artifact parent", {
    allowRoot: true,
  });
  return { realRoot, candidate, parent };
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

export function deriveTaccessId(tqueryId, hashFunction = sha256) {
  requireString(tqueryId, "TQUERY identity", /^TQUERY-[A-F0-9]{12}$/);
  const digest = hashFunction(`target-query-logical-authority-v1\u0000${tqueryId}`);
  requireString(digest, "TACCESS hash", /^[a-fA-F0-9]{64}$/);
  return `TACCESS-${digest.slice(0, 12).toUpperCase()}`;
}

export function deriveMappingHash(registryRow, hashFunction = sha256) {
  const digest = hashFunction(
    `target-query-logical-authority-mapping-v1\u0000${canonicalMinifiedJson(registryRow)}`,
  );
  requireString(digest, "mapping hash", /^[a-fA-F0-9]{64}$/);
  return digest.toLowerCase();
}

export function parsePackedAuthorityReference(value, label) {
  requireString(value, label);
  const separator = value.lastIndexOf("#");
  if (separator <= 0 || separator === value.length - 1) {
    fail(`${label} must use <relative-path>#<exact-heading>`);
  }
  return { path: value.slice(0, separator), section: value.slice(separator + 1) };
}

export function validateLiteralHeading(root, relativePath, section) {
  requireString(section, "authority heading");
  if (!relativePath.endsWith?.(".md")) fail(`invalid authority path ${relativePath}`);
  let absolutePath;
  try {
    absolutePath = repositoryFile(root, relativePath, "authority");
  } catch (error) {
    if (error.message.includes("safe repository-relative")) fail(`invalid authority path ${relativePath}`);
    throw error;
  }
  const found = fs
    .readFileSync(absolutePath, "utf8")
    .replaceAll("\r\n", "\n")
    .replaceAll("\r", "\n")
    .split("\n")
    .some(
      (line) =>
        /^#{1,6}\s+/.test(line) && line.replace(/^#{1,6}\s+/, "").trim() === section,
    );
  if (!found) fail(`missing exact authority heading ${relativePath}#${section}`);
}

function validateReferenceObject(reference, label, root, validateHeadings) {
  requireExactKeys(reference, ["role", "path", "section"], label);
  requireEnum(reference.role, AUTHORITY_ROLES, `${label}.role`);
  requireString(reference.path, `${label}.path`);
  requireString(reference.section, `${label}.section`);
  if (validateHeadings) validateLiteralHeading(root, reference.path, reference.section);
  return `${reference.role}\u0000${reference.path}\u0000${reference.section}`;
}

function validatePackedReferences(references, label, root, validateHeadings) {
  requireArray(references, label, { nonempty: true });
  const identities = references.map((reference, index) => {
    const parsed = parsePackedAuthorityReference(reference, `${label}[${index}]`);
    if (validateHeadings) validateLiteralHeading(root, parsed.path, parsed.section);
    return `${parsed.path}\u0000${parsed.section}`;
  });
  requireUnique(identities, label);
}

function validateDecisionIds(ids, label) {
  requireArray(ids, label, { nonempty: true });
  for (const [index, id] of ids.entries()) {
    requireEnum(id, DECISION_IDS, `${label}[${index}]`);
  }
  requireUnique(ids, label);
}

function validateLogicalAxis(axis, label, root, validateHeadings) {
  requirePlainObject(axis, label);
  requireEnum(axis.state, LOGICAL_AXIS_STATES, `${label}.state`);
  if (axis.state === "reviewed") {
    requireExactKeys(axis, ["state", "value"], label);
    requireString(axis.value, `${label}.value`);
  } else if (axis.state === "not_defined_by_current_contract") {
    requireExactKeys(axis, ["state", "authorityRefs"], label);
    validatePackedReferences(axis.authorityRefs, `${label}.authorityRefs`, root, validateHeadings);
  } else {
    requireExactKeys(axis, ["state", "blockerIds"], label);
    validateDecisionIds(axis.blockerIds, `${label}.blockerIds`);
  }
}

function validateUnresolvedAxis(axis, label, root, validateHeadings) {
  requirePlainObject(axis, label);
  requireEnum(axis.axis, UNRESOLVED_AXIS_NAMES, `${label}.axis`);
  if (axis.state === "not_defined_by_current_contract") {
    requireExactKeys(axis, ["axis", "state", "authorityRefs"], label);
    validatePackedReferences(axis.authorityRefs, `${label}.authorityRefs`, root, validateHeadings);
  } else if (axis.state === "decision_blocked") {
    requireExactKeys(axis, ["axis", "state", "blockerIds"], label);
    validateDecisionIds(axis.blockerIds, `${label}.blockerIds`);
  } else {
    fail(`${label}.state has unsupported value ${String(axis.state)}`);
  }
}

function validateInventory(inventory) {
  requireExactKeys(
    inventory,
    ["schemaVersion", "generator", "sourceRoot", "inventoryDigest", "totals", "protocols", "methods"],
    "inventory",
  );
  if (inventory.schemaVersion !== 1) fail("inventory.schemaVersion must equal 1");
  if (inventory.generator !== INVENTORY_GENERATOR) {
    fail(`inventory.generator must equal ${INVENTORY_GENERATOR}`);
  }
  if (inventory.sourceRoot !== INVENTORY_SOURCE_ROOT) {
    fail(`inventory.sourceRoot must equal ${INVENTORY_SOURCE_ROOT}`);
  }
  requireString(inventory.inventoryDigest, "inventory.inventoryDigest", /^[a-f0-9]{64}$/);
  requireExactKeys(inventory.totals, Object.keys(EXPECTED_COUNTS), "inventory.totals");
  for (const [name, count] of Object.entries(EXPECTED_COUNTS)) {
    if (inventory.totals[name] !== count) fail(`inventory.totals.${name} must equal ${count}`);
  }
  requireArray(inventory.protocols, "inventory.protocols", { nonempty: true });
  requireArray(inventory.methods, "inventory.methods", { nonempty: true });
  if (inventory.protocols.length !== EXPECTED_COUNTS.protocols) {
    fail(`inventory.protocols must contain exactly ${EXPECTED_COUNTS.protocols} rows`);
  }
  const protocolIdentities = [];
  const protocolNames = [];
  const protocolOwnerIds = [];
  const protocolOwnerPaths = [];
  const protocolByIdentity = new Map();
  for (const [index, protocol] of inventory.protocols.entries()) {
    const label = `inventory.protocols[${index}]`;
    requireExactKeys(protocol, ["name", "ownerSurfaceId", "ownerPath", "methodCount"], label);
    requireString(protocol.name, `${label}.name`, /^[A-Za-z_][A-Za-z0-9_]*Querying$/);
    requireString(protocol.ownerSurfaceId, `${label}.ownerSurfaceId`, /^SWIFT-[A-F0-9]{12}$/);
    requireString(
      protocol.ownerPath,
      `${label}.ownerPath`,
      /^LedgeriOS\/LedgerTargetCore\/[A-Za-z0-9_/-]+\.swift$/,
    );
    if (!Number.isInteger(protocol.methodCount) || protocol.methodCount < 1) {
      fail(`${label}.methodCount must be a positive integer`);
    }
    const identity = [protocol.ownerSurfaceId, protocol.name].join("\u0000");
    protocolIdentities.push(identity);
    protocolNames.push(protocol.name);
    protocolOwnerIds.push(protocol.ownerSurfaceId);
    protocolOwnerPaths.push(protocol.ownerPath);
    protocolByIdentity.set(
      [protocol.ownerSurfaceId, protocol.ownerPath, protocol.name].join("\u0000"),
      protocol,
    );
  }
  requireUnique(protocolIdentities, "inventory protocol identities");
  requireUnique(protocolNames, "inventory protocol names");
  requireUnique(protocolOwnerIds, "inventory protocol owner IDs");
  requireUnique(protocolOwnerPaths, "inventory protocol owner paths");
  const sortedProtocols = [...protocolIdentities].sort(compareText);
  if (protocolIdentities.some((identity, index) => identity !== sortedProtocols[index])) {
    fail("inventory.protocols must use deterministic owner/protocol order");
  }
  const ids = [];
  const identityRows = [];
  const methodIdentities = [];
  const methodCountByProtocol = new Map();
  let observationMethods = 0;
  let requestResponseMethods = 0;
  for (const [index, method] of inventory.methods.entries()) {
    const label = `inventory.methods[${index}]`;
    requireExactKeys(
      method,
      [
        "id",
        "ownerSurfaceId",
        "ownerPath",
        "ownerStatus",
        "protocol",
        "selector",
        "category",
        "signature",
        "signatureHash",
      ],
      label,
    );
    requireString(method.id, `${label}.id`, /^TQUERY-[A-F0-9]{12}$/);
    requireString(method.ownerSurfaceId, `${label}.ownerSurfaceId`, /^SWIFT-[A-F0-9]{12}$/);
    requireString(
      method.ownerPath,
      `${label}.ownerPath`,
      /^LedgeriOS\/LedgerTargetCore\/[A-Za-z0-9_/-]+\.swift$/,
    );
    if (method.ownerStatus !== "verified") fail(`${label}.ownerStatus must equal verified`);
    requireString(method.protocol, `${label}.protocol`, /^[A-Za-z_][A-Za-z0-9_]*Querying$/);
    requireString(method.selector, `${label}.selector`, /^[A-Za-z_][A-Za-z0-9_]*$/);
    requireEnum(method.category, ["observation", "request_response"], `${label}.category`);
    requireString(method.signature, `${label}.signature`);
    requireString(method.signatureHash, `${label}.signatureHash`, /^[a-f0-9]{64}$/);
    const protocolIdentity = [method.ownerSurfaceId, method.ownerPath, method.protocol].join("\u0000");
    if (!protocolByIdentity.has(protocolIdentity)) {
      fail(`${label} does not join exactly one protocol owner/path`);
    }
    const expectedCategory = method.selector.startsWith("watch")
      ? "observation"
      : "request_response";
    if (method.category !== expectedCategory) {
      fail(`${label}.category does not match selector ${method.selector}`);
    }
    if (sha256(method.signature) !== method.signatureHash) {
      fail(`${label}.signatureHash does not match signature`);
    }
    const identityInput = `${method.ownerSurfaceId}\u0000${method.protocol}\u0000${method.selector}`;
    const expectedId = `TQUERY-${sha256(identityInput).slice(0, 12).toUpperCase()}`;
    if (method.id !== expectedId) fail(`${label}.id does not match target-query identity`);
    ids.push(method.id);
    methodIdentities.push(identityInput);
    methodCountByProtocol.set(
      protocolIdentity,
      (methodCountByProtocol.get(protocolIdentity) ?? 0) + 1,
    );
    if (method.category === "observation") observationMethods += 1;
    else requestResponseMethods += 1;
    identityRows.push(
      [method.id, method.ownerSurfaceId, method.protocol, method.selector, method.signatureHash].join(
        "\u0000",
      ),
    );
  }
  requireUnique(ids, "inventory method IDs");
  requireUnique(methodIdentities, "inventory method identities");
  if (inventory.methods.length !== EXPECTED_COUNTS.methods) {
    fail(`inventory.methods must contain exactly ${EXPECTED_COUNTS.methods} rows`);
  }
  const sortedMethodIdentities = [...methodIdentities].sort(compareText);
  if (methodIdentities.some((identity, index) => identity !== sortedMethodIdentities[index])) {
    fail("inventory.methods must use deterministic owner/protocol/selector order");
  }
  for (const [identity, protocol] of protocolByIdentity.entries()) {
    if ((methodCountByProtocol.get(identity) ?? 0) !== protocol.methodCount) {
      fail(`inventory protocol ${protocol.name} methodCount does not match methods`);
    }
  }
  const recomputedTotals = {
    ownerSurfaces: new Set(protocolOwnerIds).size,
    protocols: inventory.protocols.length,
    methods: inventory.methods.length,
    observationMethods,
    requestResponseMethods,
  };
  for (const [name, count] of Object.entries(recomputedTotals)) {
    if (inventory.totals[name] !== count) {
      fail(`inventory.totals.${name} does not match inventory rows`);
    }
  }
  const recomputedDigest = sha256(identityRows.join("\n"));
  if (recomputedDigest !== inventory.inventoryDigest) fail("inventory digest does not match methods");
}

export function validateRegistry(
  registry,
  inventory,
  { root = ROOT, validateHeadings = true } = {},
) {
  validateInventory(inventory);
  requireExactKeys(registry, ["inventoryDigest", "physicalPlanes", "rows"], "registry");
  requireString(registry.inventoryDigest, "registry.inventoryDigest", /^[a-f0-9]{64}$/);
  if (registry.inventoryDigest !== inventory.inventoryDigest) {
    fail("registry inventoryDigest does not match generated TQUERY inventory");
  }
  requireExactKeys(registry.physicalPlanes, ["postgres", "local"], "registry.physicalPlanes");
  for (const [plane, decision] of [
    ["postgres", "A-003"],
    ["local", "A-004"],
  ]) {
    const value = registry.physicalPlanes[plane];
    requireExactKeys(value, ["status", "decision"], `registry.physicalPlanes.${plane}`);
    if (value.status !== "deferred" || value.decision !== decision) {
      fail(`registry.physicalPlanes.${plane} must be deferred under ${decision}`);
    }
  }
  requireArray(registry.rows, "registry.rows", { nonempty: true });
  if (registry.rows.length !== EXPECTED_COUNTS.methods) {
    fail(`registry.rows must contain exactly ${EXPECTED_COUNTS.methods} rows`);
  }
  const inventoryById = new Map(inventory.methods.map((method) => [method.id, method]));
  const rowIds = [];
  const reviewCounts = Object.fromEntries(REVIEW_CLASSES.map((value) => [value, 0]));
  for (const [index, row] of registry.rows.entries()) {
    const label = `registry.rows[${index}]`;
    requireExactKeys(
      row,
      [
        "tqueryId",
        "expectedSignatureHash",
        "reviewClass",
        "authorityRefs",
        "logicalAxes",
        "proposedDataDomains",
        "unresolvedAxes",
      ],
      label,
    );
    requireString(row.tqueryId, `${label}.tqueryId`, /^TQUERY-[A-F0-9]{12}$/);
    requireString(row.expectedSignatureHash, `${label}.expectedSignatureHash`, /^[a-f0-9]{64}$/);
    requireEnum(row.reviewClass, REVIEW_CLASSES, `${label}.reviewClass`);
    reviewCounts[row.reviewClass] += 1;
    const method = inventoryById.get(row.tqueryId);
    if (!method) fail(`${label} references orphan ${row.tqueryId}`);
    if (method.signatureHash !== row.expectedSignatureHash) {
      fail(`${label} signature hash is stale for ${row.tqueryId}`);
    }
    rowIds.push(row.tqueryId);

    requireArray(row.authorityRefs, `${label}.authorityRefs`, { nonempty: true });
    const referenceIdentities = row.authorityRefs.map((reference, referenceIndex) =>
      validateReferenceObject(
        reference,
        `${label}.authorityRefs[${referenceIndex}]`,
        root,
        validateHeadings,
      ),
    );
    requireUnique(referenceIdentities, `${label}.authorityRefs`);
    if (!row.authorityRefs.some((reference) => reference.role === "verification_evidence")) {
      fail(`${label}.authorityRefs requires owning verification_evidence`);
    }

    requireExactKeys(row.logicalAxes, LOGICAL_AXIS_NAMES, `${label}.logicalAxes`);
    for (const axisName of LOGICAL_AXIS_NAMES) {
      validateLogicalAxis(
        row.logicalAxes[axisName],
        `${label}.logicalAxes.${axisName}`,
        root,
        validateHeadings,
      );
    }

    requireArray(row.proposedDataDomains, `${label}.proposedDataDomains`);
    const domainValues = row.proposedDataDomains.map((domain, domainIndex) => {
      const domainLabel = `${label}.proposedDataDomains[${domainIndex}]`;
      requireExactKeys(domain, ["state", "value"], domainLabel);
      if (domain.state !== "proposed_architecture_dependency") {
        fail(`${domainLabel}.state must equal proposed_architecture_dependency`);
      }
      requireEnum(domain.value, DATA_DOMAINS, `${domainLabel}.value`);
      return domain.value;
    });
    requireUnique(domainValues, `${label}.proposedDataDomains`);

    requireArray(row.unresolvedAxes, `${label}.unresolvedAxes`);
    const unresolvedNames = row.unresolvedAxes.map((axis, axisIndex) => {
      validateUnresolvedAxis(
        axis,
        `${label}.unresolvedAxes[${axisIndex}]`,
        root,
        validateHeadings,
      );
      return axis.axis;
    });
    requireUnique(unresolvedNames, `${label}.unresolvedAxes`);
    const logicalStates = LOGICAL_AXIS_NAMES.map((axisName) => row.logicalAxes[axisName].state);
    const allReviewed = logicalStates.every((state) => state === "reviewed");
    const hasUnresolved = row.unresolvedAxes.length > 0;
    const hasBlocked =
      logicalStates.includes("decision_blocked") ||
      row.unresolvedAxes.some((axis) => axis.state === "decision_blocked");
    if (row.reviewClass === "mapped" && (!allReviewed || hasUnresolved)) {
      fail(`${label}.reviewClass mapped requires six reviewed axes and no unresolved axes`);
    }
    if (row.reviewClass === "mapped_with_unresolved_axes" && allReviewed && !hasUnresolved) {
      fail(`${label}.reviewClass mapped_with_unresolved_axes requires unresolved structure`);
    }
    if (row.reviewClass === "decision_blocked" && !hasBlocked) {
      fail(`${label}.reviewClass decision_blocked requires a blocked axis`);
    }
  }
  requireUnique(rowIds, "registry TQUERY IDs");
  for (const methodId of inventoryById.keys()) {
    if (!rowIds.includes(methodId)) fail(`registry is missing ${methodId}`);
  }
  for (const [reviewClass, expected] of Object.entries(EXPECTED_REVIEW_COUNTS)) {
    if (reviewCounts[reviewClass] !== expected) {
      fail(`registry review count ${reviewClass} must equal ${expected}`);
    }
  }
}

export function buildCrosswalk(
  registry,
  inventory,
  { root = ROOT, validateHeadings = true, hashFunction = sha256 } = {},
) {
  validateRegistry(registry, inventory, { root, validateHeadings });
  const methodById = new Map(inventory.methods.map((method) => [method.id, method]));
  const identities = new Map();
  const queries = registry.rows
    .map((row) => {
      const method = methodById.get(row.tqueryId);
      const canonicalRow = canonicalize(row);
      const taccessId = deriveTaccessId(row.tqueryId, hashFunction);
      const previous = identities.get(taccessId);
      if (previous && previous !== row.tqueryId) {
        fail(`TACCESS identity collision ${taccessId} for ${previous} and ${row.tqueryId}`);
      }
      identities.set(taccessId, row.tqueryId);
      return {
        taccessId,
        tqueryId: row.tqueryId,
        ownerSurfaceId: method.ownerSurfaceId,
        ownerPath: method.ownerPath,
        protocol: method.protocol,
        selector: method.selector,
        category: method.category,
        signatureHash: method.signatureHash,
        mappingHash: deriveMappingHash(row, hashFunction),
        reviewClass: canonicalRow.reviewClass,
        authorityRefs: canonicalRow.authorityRefs,
        logicalAxes: canonicalRow.logicalAxes,
        proposedDataDomains: canonicalRow.proposedDataDomains,
        unresolvedAxes: canonicalRow.unresolvedAxes,
      };
    })
    .sort((left, right) => compareText(left.tqueryId, right.tqueryId));
  return {
    schemaVersion: 1,
    generator: GENERATOR_RELATIVE,
    sourceInventory: INVENTORY_RELATIVE,
    sourceRegistry: REGISTRY_RELATIVE,
    inventoryDigest: inventory.inventoryDigest,
    physicalPlanes: canonicalize(registry.physicalPlanes),
    totals: {
      queries: queries.length,
      mapped: queries.filter((query) => query.reviewClass === "mapped").length,
      mappedWithUnresolvedAxes: queries.filter(
        (query) => query.reviewClass === "mapped_with_unresolved_axes",
      ).length,
      decisionBlocked: queries.filter((query) => query.reviewClass === "decision_blocked").length,
    },
    queries,
  };
}

function readRepositoryJson(root, relativePath, label) {
  const filePath = repositoryFile(root, relativePath, label);
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch (error) {
    fail(`invalid ${label} JSON: ${error.message}`);
  }
}

export function buildRepositoryCrosswalk(root = ROOT) {
  const inventory = readRepositoryJson(root, INVENTORY_RELATIVE, "TQUERY inventory");
  const registry = readRepositoryJson(root, REGISTRY_RELATIVE, "logical-authority registry");
  return buildCrosswalk(registry, inventory, { root });
}

export function renderArtifact(crosswalk) {
  return `${JSON.stringify(crosswalk, null, 2)}\n`;
}

export function artifactPath(root = ROOT) {
  return path.join(root, ARTIFACT_RELATIVE);
}

export function writeArtifact(
  bytes,
  filePath = artifactPath(),
  { root = ROOT, randomBytesFunction = crypto.randomBytes } = {},
) {
  const { candidate, parent } = artifactParent(root, filePath);
  if (fs.existsSync(candidate)) {
    const metadata = fs.lstatSync(candidate);
    if (metadata.isSymbolicLink() || !metadata.isFile()) {
      fail(`generated artifact must be a regular non-symlink file: ${candidate}`);
    }
  }
  const token = randomBytesFunction(16);
  if (!Buffer.isBuffer(token) || token.length < 16) {
    fail("temporary artifact token must contain at least 16 random bytes");
  }
  const temporary = path.join(parent, `.${path.basename(candidate)}.tmp-${token.toString("hex")}`);
  const flags =
    fs.constants.O_WRONLY |
    fs.constants.O_CREAT |
    fs.constants.O_EXCL |
    (fs.constants.O_NOFOLLOW ?? 0);
  let descriptor;
  let created = false;
  try {
    descriptor = fs.openSync(temporary, flags, 0o600);
    created = true;
    fs.writeFileSync(descriptor, bytes, "utf8");
    fs.fsyncSync(descriptor);
    fs.closeSync(descriptor);
    descriptor = undefined;
    artifactParent(root, filePath);
    if (fs.existsSync(candidate)) {
      const metadata = fs.lstatSync(candidate);
      if (metadata.isSymbolicLink() || !metadata.isFile()) {
        fail(`generated artifact must be a regular non-symlink file: ${candidate}`);
      }
    }
    fs.renameSync(temporary, candidate);
    created = false;
  } catch (error) {
    if (error.message?.startsWith("target-query-logical-authority:")) throw error;
    fail(`unable to write generated artifact safely: ${error.message}`);
  } finally {
    if (descriptor !== undefined) fs.closeSync(descriptor);
    if (created && fs.existsSync(temporary)) fs.unlinkSync(temporary);
  }
}

export function checkArtifact(bytes, filePath = artifactPath(), { root = ROOT } = {}) {
  const { candidate } = artifactParent(root, filePath);
  if (!fs.existsSync(candidate)) fail(`missing generated artifact: ${candidate}`);
  const metadata = fs.lstatSync(candidate);
  if (metadata.isSymbolicLink() || !metadata.isFile()) {
    fail(`generated artifact must be a regular non-symlink file: ${candidate}`);
  }
  requireContained(repositoryRoot(root), fs.realpathSync(candidate), "generated artifact");
  if (fs.readFileSync(candidate, "utf8") !== bytes) {
    fail(`stale generated artifact: ${candidate}`);
  }
}

export function execute(mode, root = ROOT) {
  if (!new Set(["generate", "check"]).has(mode)) {
    fail(
      "usage: node scripts/generate-target-query-logical-authority-crosswalk.mjs <generate|check>",
    );
  }
  const crosswalk = buildRepositoryCrosswalk(root);
  const bytes = renderArtifact(crosswalk);
  if (mode === "generate") writeArtifact(bytes, artifactPath(root), { root });
  else checkArtifact(bytes, artifactPath(root), { root });
  return crosswalk;
}

export function executeArguments(args, root = ROOT) {
  if (!Array.isArray(args) || args.length !== 1) {
    fail(
      "usage: node scripts/generate-target-query-logical-authority-crosswalk.mjs <generate|check>",
    );
  }
  return execute(args[0], root);
}

function main() {
  const args = process.argv.slice(2);
  const mode = args[0];
  const crosswalk = executeArguments(args);
  process.stdout.write(
    `target-query-logical-authority: ${mode} passed for ${crosswalk.totals.queries} queries (${crosswalk.inventoryDigest})\n`,
  );
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  }
}
