import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  ARTIFACT_RELATIVE,
  AUTHORITY_ROLES,
  DATA_DOMAINS,
  DECISION_IDS,
  INVENTORY_RELATIVE,
  LOGICAL_AXIS_STATES,
  REGISTRY_RELATIVE,
  REVIEW_CLASSES,
  UNRESOLVED_AXIS_NAMES,
  artifactPath,
  buildCrosswalk,
  buildRepositoryCrosswalk,
  canonicalMinifiedJson,
  checkArtifact,
  deriveMappingHash,
  deriveTaccessId,
  execute,
  executeArguments,
  parsePackedAuthorityReference,
  renderArtifact,
  validateLiteralHeading,
  validateRegistry,
  writeArtifact,
} from "../generate-target-query-logical-authority-crosswalk.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const INVENTORY = JSON.parse(fs.readFileSync(path.join(ROOT, INVENTORY_RELATIVE), "utf8"));
const REGISTRY = JSON.parse(fs.readFileSync(path.join(ROOT, REGISTRY_RELATIVE), "utf8"));

function clone(value) {
  return structuredClone(value);
}

function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function refreshInventoryDigest(inventory) {
  inventory.inventoryDigest = sha256(
    inventory.methods
      .map((method) =>
        [method.id, method.ownerSurfaceId, method.protocol, method.selector, method.signatureHash].join(
          "\u0000",
        ),
      )
      .join("\n"),
  );
}

function expectFailure(callback, pattern) {
  assert.throws(callback, (error) => {
    assert.match(error.message, /^target-query-logical-authority:/);
    assert.match(error.message, pattern);
    return true;
  });
}

function validate(registry = REGISTRY, inventory = INVENTORY) {
  return validateRegistry(registry, inventory, { root: ROOT });
}

function build(registry = REGISTRY, inventory = INVENTORY, options = {}) {
  return buildCrosswalk(registry, inventory, { root: ROOT, ...options });
}

function replaceObject(target, value) {
  for (const key of Object.keys(target)) delete target[key];
  Object.assign(target, value);
}

function reverseObjectKeys(value) {
  if (Array.isArray(value)) return value.map(reverseObjectKeys);
  if (value === null || typeof value !== "object") return value;
  return Object.fromEntries(
    Object.entries(value)
      .reverse()
      .map(([key, nested]) => [key, reverseObjectKeys(nested)]),
  );
}

function copyFileIntoRoot(sourceRoot, targetRoot, relativePath) {
  const destination = path.join(targetRoot, relativePath);
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  fs.copyFileSync(path.join(sourceRoot, relativePath), destination);
}

function makeFixtureRepository() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "target-query-authority-"));
  copyFileIntoRoot(ROOT, root, INVENTORY_RELATIVE);
  copyFileIntoRoot(ROOT, root, REGISTRY_RELATIVE);
  const references = new Set();
  for (const row of REGISTRY.rows) {
    for (const reference of row.authorityRefs) references.add(reference.path);
    for (const axis of [...Object.values(row.logicalAxes), ...row.unresolvedAxes]) {
      for (const packed of axis.authorityRefs ?? []) {
        references.add(parsePackedAuthorityReference(packed, "fixture reference").path);
      }
    }
  }
  for (const relativePath of references) copyFileIntoRoot(ROOT, root, relativePath);
  return root;
}

test("repository crosswalk is exactly the reviewed 19-row logical-authority baseline", () => {
  const crosswalk = buildRepositoryCrosswalk(ROOT);
  assert.equal(crosswalk.inventoryDigest, INVENTORY.inventoryDigest);
  assert.deepEqual(crosswalk.physicalPlanes, {
    postgres: { status: "deferred", decision: "A-003" },
    local: { status: "deferred", decision: "A-004" },
  });
  assert.deepEqual(crosswalk.totals, {
    queries: 19,
    mapped: 7,
    mappedWithUnresolvedAxes: 11,
    decisionBlocked: 1,
  });
  assert.equal(new Set(crosswalk.queries.map((query) => query.tqueryId)).size, 19);
  assert.ok(crosswalk.queries.every((query) => /^TACCESS-[A-F0-9]{12}$/.test(query.taccessId)));
  assert.ok(crosswalk.queries.every((query) => /^[a-f0-9]{64}$/.test(query.mappingHash)));
  assert.ok(
    REGISTRY.rows.every((row) =>
      row.authorityRefs.some((reference) => reference.role === "verification_evidence"),
    ),
  );

  const item = crosswalk.queries.find((query) => query.tqueryId === "TQUERY-C7BD4AEAAB98");
  assert.equal(
    item.logicalAxes.ordering.value,
    "Unaccounted For first, Accounted For second; preserve upstream Item order within each section.",
  );
  assert.deepEqual(
    item.unresolvedAxes.map((axis) => axis.axis),
    ["occurrence_and_provenance_persistence", "deterministic_storage_order"],
  );

  const budget = crosswalk.queries.find((query) => query.tqueryId === "TQUERY-961BF10129CC");
  assert.equal(budget.reviewClass, "mapped_with_unresolved_axes");
  assert.deepEqual(budget.unresolvedAxes.map((axis) => axis.axis), [
    "contribution_source_eligibility_and_taxonomy",
  ]);
  assert.doesNotMatch(JSON.stringify(budget), /O-007|O-015/);

  const spaces = crosswalk.queries.find((query) => query.tqueryId === "TQUERY-038289DD7D2C");
  assert.equal(spaces.reviewClass, "mapped");
  assert.equal(spaces.logicalAxes.scope.value, "Exact Account and exact Project-or-Business-Inventory Space scope.");
  assert.equal(spaces.logicalAxes.readiness.value, "Ready complete source-exhaustive evidence alone can establish authoritative active-list emptiness; partial, stale, incomplete and failed evidence cannot.");
  assert.deepEqual(spaces.unresolvedAxes, []);

  const unresolved = crosswalk.queries.find(
    (query) => query.tqueryId === "TQUERY-BAFDEB7B1FDF",
  );
  assert.equal(
    unresolved.logicalAxes.readiness.value,
    "Only queued, applying, and rejected operations are unresolved; draft, applied, superseded, and resolved operations are excluded. Transient failure requeues rather than creating a new unresolved state.",
  );
});

test("generated rows join exact inventory ownership facts without copying them into registry", () => {
  const crosswalk = build();
  const methods = new Map(INVENTORY.methods.map((method) => [method.id, method]));
  assert.deepEqual(
    Object.keys(crosswalk).sort(),
    [
      "schemaVersion",
      "generator",
      "sourceInventory",
      "sourceRegistry",
      "inventoryDigest",
      "physicalPlanes",
      "totals",
      "queries",
    ].sort(),
  );
  for (const query of crosswalk.queries) {
    const method = methods.get(query.tqueryId);
    assert.deepEqual(
      {
        ownerSurfaceId: query.ownerSurfaceId,
        ownerPath: query.ownerPath,
        protocol: query.protocol,
        selector: query.selector,
        category: query.category,
        signatureHash: query.signatureHash,
      },
      {
        ownerSurfaceId: method.ownerSurfaceId,
        ownerPath: method.ownerPath,
        protocol: method.protocol,
        selector: method.selector,
        category: method.category,
        signatureHash: method.signatureHash,
      },
    );
  }
  for (const row of REGISTRY.rows) {
    for (const key of ["ownerSurfaceId", "ownerPath", "protocol", "selector", "category"]) {
      assert.equal(Object.hasOwn(row, key), false);
    }
  }
});

test("logical authority accepts implemented-or-later input but remains byte-stable across lifecycle promotion", () => {
  const rendered = [];
  for (const status of ["implemented", "verified", "rehearsed", "cutover_ready"]) {
    const inventory = clone(INVENTORY);
    inventory.methods.find((method) => method.id === "TQUERY-038289DD7D2C").ownerStatus = status;
    const crosswalk = build(REGISTRY, inventory);
    assert.equal(
      Object.hasOwn(
        crosswalk.queries.find((query) => query.tqueryId === "TQUERY-038289DD7D2C"),
        "ownerStatus",
      ),
      false,
    );
    rendered.push(renderArtifact(crosswalk));
  }
  assert.equal(new Set(rendered).size, 1);

  for (const status of [
    "discovered",
    "characterized",
    "target_mapped",
    "blocked",
    "retired",
    "unknown",
  ]) {
    const inventory = clone(INVENTORY);
    inventory.methods.find((method) => method.id === "TQUERY-038289DD7D2C").ownerStatus = status;
    expectFailure(() => build(REGISTRY, inventory), /ownerStatus.*unsupported value/);
  }
});

test("closed top-level, physical-plane, row, and inventory schemas reject drift", () => {
  const cases = [
    ["registry extra", (r) => (r.extra = true), /registry keys mismatch.*unexpected extra/],
    ["registry missing", (r) => delete r.inventoryDigest, /registry keys mismatch.*missing inventoryDigest/],
    ["physical extra", (r) => (r.physicalPlanes.postgres.indexName = "x"), /keys mismatch.*indexName/],
    ["physical status", (r) => (r.physicalPlanes.local.status = "implemented"), /must be deferred/],
    ["physical decision", (r) => (r.physicalPlanes.postgres.decision = "A-004"), /A-003/],
    ["row missing", (r) => delete r.rows[0].logicalAxes, /keys mismatch.*missing logicalAxes/],
    ["row unknown", (r) => (r.rows[0].ownerSurfaceId = "SWIFT-DECOY000000"), /unexpected ownerSurfaceId/],
  ];
  for (const [label, mutate, pattern] of cases) {
    const registry = clone(REGISTRY);
    mutate(registry);
    expectFailure(() => validate(registry), pattern, label);
  }

  const inventory = clone(INVENTORY);
  inventory.methods[0].physicalAccess = true;
  expectFailure(() => validate(REGISTRY, inventory), /inventory\.methods\[0\] keys mismatch/);
});

test("upstream inventory is fully closed, derived, related, and deterministically ordered", () => {
  const cases = [
    [(i) => (i.generator = "scripts/other.mjs"), /inventory\.generator must equal/],
    [(i) => (i.sourceRoot = "LedgeriOS"), /inventory\.sourceRoot must equal/],
    [(i) => (i.protocols[0].extra = true), /inventory\.protocols\[0\] keys mismatch/],
    [(i) => (i.protocols[0].name = "NotExact"), /protocols\[0\]\.name has invalid format/],
    [(i) => (i.protocols[0].ownerSurfaceId = "bad"), /ownerSurfaceId has invalid format/],
    [(i) => (i.protocols[0].ownerPath = "../Owner.swift"), /ownerPath has invalid format/],
    [(i) => (i.protocols[0].methodCount = 0), /methodCount must be a positive integer/],
    [(i) => (i.protocols[1].name = i.protocols[0].name), /protocol names contains duplicate/],
    [(i) => (i.protocols[1].ownerSurfaceId = i.protocols[0].ownerSurfaceId), /owner IDs contains duplicate/],
    [(i) => (i.protocols[1].ownerPath = i.protocols[0].ownerPath), /owner paths contains duplicate/],
    [(i) => i.protocols.reverse(), /deterministic owner\/protocol order/],
    [(i) => i.methods.reverse(), /deterministic owner\/protocol\/selector order/],
    [(i) => (i.methods[0].ownerPath = i.protocols[1].ownerPath), /does not join exactly one protocol/],
    [(i) => (i.methods[0].protocol = i.protocols[1].name), /does not join exactly one protocol/],
    [(i) => (i.methods[0].signatureHash = "0".repeat(64)), /signatureHash does not match signature/],
    [(i) => (i.methods[0].category = "request_response"), /category does not match selector/],
    [(i) => (i.methods[0].id = "TQUERY-000000000000"), /id does not match target-query identity/],
    [(i) => (i.protocols[0].methodCount += 1), /methodCount does not match methods/],
    [(i) => (i.totals.ownerSurfaces -= 1), /totals\.ownerSurfaces must equal/],
    [(i) => (i.totals.protocols -= 1), /totals\.protocols must equal/],
    [(i) => (i.totals.methods -= 1), /totals\.methods must equal/],
    [(i) => (i.totals.observationMethods -= 1), /totals\.observationMethods must equal/],
    [(i) => (i.totals.requestResponseMethods += 1), /totals\.requestResponseMethods must equal/],
  ];
  for (const [mutate, pattern] of cases) {
    const inventory = clone(INVENTORY);
    mutate(inventory);
    refreshInventoryDigest(inventory);
    expectFailure(() => validate(REGISTRY, inventory), pattern);
  }

  const signature = clone(INVENTORY);
  signature.methods[0].signature += " async";
  refreshInventoryDigest(signature);
  expectFailure(() => validate(REGISTRY, signature), /signatureHash does not match signature/);

  const selector = clone(INVENTORY);
  selector.methods[0].selector = "fetchProjectItemAccountingSections";
  selector.methods[0].category = "request_response";
  refreshInventoryDigest(selector);
  expectFailure(() => validate(REGISTRY, selector), /id does not match target-query identity/);
});

test("every explicit copied, physical, source, and provider row key fails closed", () => {
  const forbidden = [
    "ownerSurfaceId",
    "ownerPath",
    "protocol",
    "selector",
    "category",
    "tindexId",
    "indexId",
    "indexName",
    "primaryKeyCandidate",
    "secondaryRequired",
    "physicalAccess",
    "sql",
    "rls",
    "syncStream",
    "provider",
    "sourceQueryIds",
    "firestoreQuery",
    "firestoreIndex",
  ];
  for (const key of forbidden) {
    const registry = clone(REGISTRY);
    registry.rows[0][key] = "forbidden";
    expectFailure(() => validate(registry), new RegExp(`unexpected ${key}`));
  }
});

test("reviewed, not-defined, and blocked logical axes enforce exact discriminated shapes", () => {
  const cases = [
    [{ state: "reviewed" }, /missing value/],
    [{ state: "reviewed", value: "" }, /value must be a nonempty string/],
    [{ state: "reviewed", value: "ok", blockerIds: ["O-040"] }, /unexpected blockerIds/],
    [{ state: "not_defined_by_current_contract" }, /missing authorityRefs/],
    [{ state: "not_defined_by_current_contract", authorityRefs: [] }, /must not be empty/],
    [
      { state: "not_defined_by_current_contract", authorityRefs: ["docs/example.md#One"], value: "x" },
      /unexpected value/,
    ],
    [{ state: "decision_blocked" }, /missing blockerIds/],
    [{ state: "decision_blocked", blockerIds: [] }, /must not be empty/],
    [{ state: "decision_blocked", blockerIds: ["O-040"], value: "x" }, /unexpected value/],
    [{ state: "invented", value: "x" }, /unsupported value invented/],
  ];
  for (const [axis, pattern] of cases) {
    const registry = clone(REGISTRY);
    replaceObject(registry.rows[0].logicalAxes.scope, axis);
    expectFailure(() => validate(registry), pattern);
  }
});

test("review classes are structurally consistent even when aggregate counts are preserved", () => {
  const mappedIndex = REGISTRY.rows.findIndex((row) => row.reviewClass === "mapped");
  const unresolvedIndex = REGISTRY.rows.findIndex(
    (row) => row.reviewClass === "mapped_with_unresolved_axes",
  );
  const blockedIndex = REGISTRY.rows.findIndex((row) => row.reviewClass === "decision_blocked");

  const mappedSwap = clone(REGISTRY);
  [mappedSwap.rows[mappedIndex].reviewClass, mappedSwap.rows[unresolvedIndex].reviewClass] = [
    mappedSwap.rows[unresolvedIndex].reviewClass,
    mappedSwap.rows[mappedIndex].reviewClass,
  ];
  expectFailure(() => validate(mappedSwap), /reviewClass .* requires/);

  const blockedSwap = clone(REGISTRY);
  [blockedSwap.rows[mappedIndex].reviewClass, blockedSwap.rows[blockedIndex].reviewClass] = [
    blockedSwap.rows[blockedIndex].reviewClass,
    blockedSwap.rows[mappedIndex].reviewClass,
  ];
  expectFailure(() => validate(blockedSwap), /reviewClass .* requires/);

  const noBlocked = clone(REGISTRY);
  const row = noBlocked.rows[blockedIndex];
  row.logicalAxes.authorization = { state: "reviewed", value: "Already authorized." };
  row.unresolvedAxes = [];
  expectFailure(() => validate(noBlocked), /decision_blocked requires a blocked axis/);
});

test("unresolved axes enforce exact names, states, references, blockers, and uniqueness", () => {
  const cases = [
    [
      { axis: "invented", state: "decision_blocked", blockerIds: ["O-040"] },
      /unsupported value invented/,
    ],
    [{ axis: "deterministic_storage_order", state: "reviewed", value: "x" }, /state has unsupported/],
    [
      { axis: "deterministic_storage_order", state: "not_defined_by_current_contract" },
      /missing authorityRefs/,
    ],
    [
      { axis: "deterministic_storage_order", state: "decision_blocked", blockerIds: [] },
      /must not be empty/,
    ],
    [
      {
        axis: "deterministic_storage_order",
        state: "decision_blocked",
        blockerIds: ["O-040"],
        authorityRefs: ["docs/example.md#One"],
      },
      /unexpected authorityRefs/,
    ],
  ];
  for (const [axis, pattern] of cases) {
    const registry = clone(REGISTRY);
    replaceObject(registry.rows[0].unresolvedAxes[1], axis);
    expectFailure(() => validate(registry), pattern);
  }

  const duplicate = clone(REGISTRY);
  duplicate.rows[0].unresolvedAxes.push(clone(duplicate.rows[0].unresolvedAxes[1]));
  expectFailure(() => validate(duplicate), /unresolvedAxes contains duplicate/);
});

test("exact review, authority, state, domain, unresolved, and decision allowlists reject additions", () => {
  assert.deepEqual(REVIEW_CLASSES, ["mapped", "mapped_with_unresolved_axes", "decision_blocked"]);
  assert.deepEqual(AUTHORITY_ROLES, [
    "canonical_target",
    "architecture_authority",
    "conversion_control",
    "verification_evidence",
  ]);
  assert.deepEqual(LOGICAL_AXIS_STATES, [
    "reviewed",
    "not_defined_by_current_contract",
    "decision_blocked",
  ]);
  assert.equal(DATA_DOMAINS.length, 7);
  assert.equal(UNRESOLVED_AXIS_NAMES.length, 11);
  assert.deepEqual(DECISION_IDS, [
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

  const mutations = [
    [(r) => (r.rows[0].reviewClass = "approved"), /reviewClass.*approved/],
    [(r) => (r.rows[0].authorityRefs[0].role = "source"), /role.*source/],
    [(r) => (r.rows[0].proposedDataDomains[0].state = "implemented"), /must equal/],
    [(r) => (r.rows[0].proposedDataDomains[0].value = "inventory"), /unsupported value inventory/],
    [(r) => (r.rows[0].unresolvedAxes[0].blockerIds = ["O-999"]), /unsupported value O-999/],
  ];
  for (const [mutate, pattern] of mutations) {
    const registry = clone(REGISTRY);
    mutate(registry);
    expectFailure(() => validate(registry), pattern);
  }
});

test("authority references require safe paths and exact literal headings without status parsing", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "target-query-authority-headings-"));
  const relative = "docs/authority.md";
  const absolute = path.join(root, relative);
  fs.mkdirSync(path.dirname(absolute), { recursive: true });
  fs.writeFileSync(
    absolute,
    "# Authority\n\n## A-003 — Supabase Postgres as Target Authority\n\nStatus: rejected prose is not parsed.\n",
  );
  assert.doesNotThrow(() =>
    validateLiteralHeading(root, relative, "A-003 — Supabase Postgres as Target Authority"),
  );
  expectFailure(() => validateLiteralHeading(root, relative, "A-003"), /missing exact authority heading/);
  expectFailure(() => validateLiteralHeading(root, "../authority.md", "Authority"), /invalid authority path/);
  expectFailure(() => validateLiteralHeading(root, absolute, "Authority"), /invalid authority path/);
  expectFailure(() => validateLiteralHeading(root, "docs/missing.md", "Authority"), /missing authority/);
  expectFailure(() => parsePackedAuthorityReference("docs/authority.md", "reference"), /must use/);
});

test("repository inputs, authority paths, artifact, and artifact parent reject symlinks and escapes", () => {
  const external = fs.mkdtempSync(path.join(os.tmpdir(), "target-query-authority-external-"));
  const externalFile = path.join(external, "external.md");
  fs.writeFileSync(externalFile, "# Authority\n");

  const authorityRoot = fs.mkdtempSync(path.join(os.tmpdir(), "target-query-authority-links-"));
  fs.mkdirSync(path.join(authorityRoot, "docs"));
  fs.symlinkSync(externalFile, path.join(authorityRoot, "docs", "linked.md"));
  expectFailure(
    () => validateLiteralHeading(authorityRoot, "docs/linked.md", "Authority"),
    /must not traverse a symlink|regular non-symlink/,
  );
  fs.rmSync(path.join(authorityRoot, "docs"), { recursive: true, force: true });
  fs.symlinkSync(external, path.join(authorityRoot, "docs"));
  expectFailure(
    () => validateLiteralHeading(authorityRoot, "docs/external.md", "Authority"),
    /must not traverse a symlink|escapes repository/,
  );

  const realRoot = makeFixtureRepository();
  const linkedRoot = `${realRoot}-link`;
  fs.symlinkSync(realRoot, linkedRoot);
  expectFailure(() => buildRepositoryCrosswalk(linkedRoot), /repository root must be a non-symlink/);

  for (const relativePath of [INVENTORY_RELATIVE, REGISTRY_RELATIVE]) {
    const root = makeFixtureRepository();
    const target = path.join(root, relativePath);
    const outside = path.join(external, path.basename(relativePath));
    fs.copyFileSync(target, outside);
    fs.unlinkSync(target);
    fs.symlinkSync(outside, target);
    expectFailure(
      () => buildRepositoryCrosswalk(root),
      /must not traverse a symlink|regular non-symlink/,
    );
  }

  const bytes = renderArtifact(build());
  const artifactRoot = fs.mkdtempSync(path.join(os.tmpdir(), "target-query-authority-output-"));
  const artifact = path.join(artifactRoot, "crosswalk.json");
  fs.symlinkSync(externalFile, artifact);
  expectFailure(
    () => checkArtifact(bytes, artifact, { root: artifactRoot }),
    /regular non-symlink/,
  );
  expectFailure(
    () => writeArtifact(bytes, artifact, { root: artifactRoot }),
    /regular non-symlink/,
  );
  expectFailure(
    () => checkArtifact(bytes, externalFile, { root: artifactRoot }),
    /escapes repository root/,
  );

  const parentRoot = fs.mkdtempSync(path.join(os.tmpdir(), "target-query-authority-parent-"));
  fs.symlinkSync(external, path.join(parentRoot, "generated"));
  expectFailure(
    () => writeArtifact(bytes, path.join(parentRoot, "generated", "crosswalk.json"), { root: parentRoot }),
    /must not traverse a symlink|escapes repository/,
  );
  expectFailure(
    () => checkArtifact(bytes, path.join(parentRoot, "generated", "crosswalk.json"), { root: parentRoot }),
    /must not traverse a symlink|escapes repository/,
  );
});

test("exclusive unpredictable sibling temp creation refuses a precreated symlink without deleting it", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "target-query-authority-temp-"));
  const artifact = path.join(root, "crosswalk.json");
  const token = Buffer.alloc(16);
  const temporary = path.join(root, `.crosswalk.json.tmp-${token.toString("hex")}`);
  const target = path.join(root, "do-not-touch");
  fs.writeFileSync(target, "sentinel\n");
  fs.symlinkSync(target, temporary);
  expectFailure(
    () => writeArtifact("{}\n", artifact, { root, randomBytesFunction: () => token }),
    /unable to write generated artifact safely/,
  );
  assert.equal(fs.lstatSync(temporary).isSymbolicLink(), true);
  assert.equal(fs.readFileSync(target, "utf8"), "sentinel\n");
  assert.equal(fs.existsSync(artifact), false);
});

test("duplicate, missing, orphaned, stale, and malformed inventory bindings reject", () => {
  const duplicate = clone(REGISTRY);
  duplicate.rows[17] = clone(duplicate.rows[0]);
  expectFailure(() => validate(duplicate), /registry TQUERY IDs contains duplicate/);

  const orphan = clone(REGISTRY);
  orphan.rows[0].tqueryId = "TQUERY-FFFFFFFFFFFF";
  expectFailure(() => validate(orphan), /references orphan/);

  const stale = clone(REGISTRY);
  stale.rows[0].expectedSignatureHash = "0".repeat(64);
  expectFailure(() => validate(stale), /signature hash is stale/);

  const digest = clone(REGISTRY);
  digest.inventoryDigest = "0".repeat(64);
  expectFailure(() => validate(digest), /inventoryDigest does not match/);

  const malformed = clone(REGISTRY);
  malformed.rows[0].tqueryId = "TQUERY-bad";
  expectFailure(() => validate(malformed), /tqueryId has invalid format/);

  const duplicateInventory = clone(INVENTORY);
  duplicateInventory.methods[17] = clone(duplicateInventory.methods[0]);
  expectFailure(() => validate(REGISTRY, duplicateInventory), /inventory method IDs contains duplicate/);
});

test("free text is not keyword-scanned or treated as semantic approval", () => {
  const registry = clone(REGISTRY);
  registry.rows[0].logicalAxes.result.value =
    "Contradictory human-review text mentioning SQL Firebase RLS syncStream provider implemented indexName.";
  assert.doesNotThrow(() => validate(registry));
  const original = build();
  const changed = build(registry);
  const originalRow = original.queries.find((query) => query.tqueryId === registry.rows[0].tqueryId);
  const changedRow = changed.queries.find((query) => query.tqueryId === registry.rows[0].tqueryId);
  assert.equal(changedRow.taccessId, originalRow.taccessId);
  assert.notEqual(changedRow.mappingHash, originalRow.mappingHash);
});

test("TACCESS and mapping hashes implement the exact domain-separated formulas", () => {
  const row = REGISTRY.rows[0];
  const expectedId = `TACCESS-${sha256(
    `target-query-logical-authority-v1\u0000${row.tqueryId}`,
  )
    .slice(0, 12)
    .toUpperCase()}`;
  assert.equal(deriveTaccessId(row.tqueryId), expectedId);
  assert.notEqual(deriveTaccessId(REGISTRY.rows[1].tqueryId), expectedId);
  assert.equal(
    deriveMappingHash(row),
    sha256(
      `target-query-logical-authority-mapping-v1\u0000${canonicalMinifiedJson(row)}`,
    ),
  );

  const reordered = Object.fromEntries(Object.entries(row).reverse());
  assert.equal(deriveMappingHash(reordered), deriveMappingHash(row));
  const changedArray = clone(row);
  changedArray.authorityRefs.reverse();
  assert.notEqual(deriveMappingHash(changedArray), deriveMappingHash(row));
  const signatureOnly = clone(row);
  signatureOnly.expectedSignatureHash = "0".repeat(64);
  assert.equal(deriveTaccessId(signatureOnly.tqueryId), deriveTaccessId(row.tqueryId));
  assert.notEqual(deriveMappingHash(signatureOnly), deriveMappingHash(row));
});

test("TACCESS collisions reject before a complete crosswalk is returned", () => {
  const constantHash = () => "a".repeat(64);
  expectFailure(
    () => build(REGISTRY, INVENTORY, { hashFunction: constantHash }),
    /TACCESS identity collision TACCESS-AAAAAAAAAAAA/,
  );
});

test("registry row order does not change deterministic generated bytes", () => {
  const reversed = clone(REGISTRY);
  reversed.rows.reverse();
  assert.equal(renderArtifact(build(reversed)), renderArtifact(build(REGISTRY)));
  const bytes = renderArtifact(build());
  assert.ok(bytes.endsWith("\n"));
  assert.doesNotMatch(bytes, /"(?:generatedAt|timestamp|lastSynchronizedAt)"\s*:/);
  const ids = JSON.parse(bytes).queries.map((query) => query.tqueryId);
  assert.deepEqual(ids, [...ids].sort());
});

test("all row-derived nested objects canonicalize while array order remains meaningful", () => {
  const reordered = reverseObjectKeys(REGISTRY);
  assert.equal(renderArtifact(build(reordered)), renderArtifact(build(REGISTRY)));

  const arrayReordered = clone(REGISTRY);
  arrayReordered.rows[0].authorityRefs.reverse();
  assert.notEqual(renderArtifact(build(arrayReordered)), renderArtifact(build(REGISTRY)));
});

test("missing and stale checks are read-only while generate then check is byte-identical", () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "target-query-authority-artifact-"));
  const filePath = path.join(directory, "crosswalk.json");
  const bytes = renderArtifact(build());
  expectFailure(() => checkArtifact(bytes, filePath, { root: directory }), /missing generated artifact/);
  assert.equal(fs.existsSync(filePath), false);

  fs.writeFileSync(filePath, "stale\n");
  const staleBefore = fs.statSync(filePath);
  expectFailure(() => checkArtifact(bytes, filePath, { root: directory }), /stale generated artifact/);
  assert.equal(fs.readFileSync(filePath, "utf8"), "stale\n");
  assert.equal(fs.statSync(filePath).mtimeMs, staleBefore.mtimeMs);

  writeArtifact(bytes, filePath, { root: directory });
  const cleanBefore = fs.statSync(filePath);
  assert.doesNotThrow(() => checkArtifact(bytes, filePath, { root: directory }));
  assert.equal(fs.readFileSync(filePath, "utf8"), bytes);
  assert.equal(fs.statSync(filePath).mtimeMs, cleanBefore.mtimeMs);
});

test("invalid repository input fails before generate overwrites an existing artifact", () => {
  const root = makeFixtureRepository();
  const generatedPath = artifactPath(root);
  fs.mkdirSync(path.dirname(generatedPath), { recursive: true });
  fs.writeFileSync(generatedPath, "sentinel\n");
  const invalid = clone(REGISTRY);
  invalid.rows[0].sql = "select *";
  fs.writeFileSync(path.join(root, REGISTRY_RELATIVE), `${JSON.stringify(invalid, null, 2)}\n`);
  expectFailure(() => execute("generate", root), /unexpected sql/);
  assert.equal(fs.readFileSync(generatedPath, "utf8"), "sentinel\n");
});

test("repository generated artifact is current and contains all 19 reviewed rows", () => {
  const expected = renderArtifact(buildRepositoryCrosswalk(ROOT));
  const filePath = path.join(ROOT, ARTIFACT_RELATIVE);
  assert.doesNotThrow(() => checkArtifact(expected, filePath, { root: ROOT }));
  const parsed = JSON.parse(fs.readFileSync(filePath, "utf8"));
  assert.equal(parsed.queries.length, 19);
  assert.deepEqual(parsed.totals, {
    queries: 19,
    mapped: 7,
    mappedWithUnresolvedAxes: 11,
    decisionBlocked: 1,
  });
});

test("root package and CI hooks are the exact query-authority control topology", () => {
  const packageJson = JSON.parse(fs.readFileSync(path.join(ROOT, "package.json"), "utf8"));
  assert.equal(
    packageJson.scripts["target:query-authority:generate"],
    "node scripts/generate-target-query-logical-authority-crosswalk.mjs generate",
  );
  assert.equal(
    packageJson.scripts["target:query-authority:check"],
    "node scripts/generate-target-query-logical-authority-crosswalk.mjs check",
  );
  assert.equal(
    packageJson.scripts["target:query-authority:test"],
    "node --test scripts/tests/generate-target-query-logical-authority-crosswalk.test.mjs",
  );
  const workflow = fs.readFileSync(
    path.join(ROOT, ".github/workflows/supabase-conversion-control.yml"),
    "utf8",
  );
  assert.match(
    workflow,
    /npm run target:query-ports:test\s+npm run target:query-ports:check\s+npm run target:query-authority:test\s+npm run target:query-authority:check\s+npm run conversion:check/,
  );
  assert.match(workflow, /target-environment:\s+name: Isolated target environment\s+needs: conversion-control/);
});

test("CLI rejects missing or unsupported modes with one deterministic diagnostic", () => {
  for (const mode of [undefined, "write", "GENERATE"]) {
    const messages = [];
    for (let attempt = 0; attempt < 2; attempt += 1) {
      expectFailure(() => execute(mode, ROOT), /usage: .*<generate\|check>/);
      try {
        execute(mode, ROOT);
      } catch (error) {
        messages.push(error.message);
      }
    }
    assert.equal(messages[0], messages[1]);
  }
  for (const args of [[], ["check", "extra"], ["generate", "extra", "again"]]) {
    expectFailure(() => executeArguments(args, ROOT), /usage: .*<generate\|check>/);
  }
});
