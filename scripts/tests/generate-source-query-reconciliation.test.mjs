import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  ARTIFACT_RELATIVE,
  DOSSIER_RELATIVE,
  REGISTRY_RELATIVE,
  buildReconciliation,
  buildRepositoryReconciliation,
  canonicalMinifiedJson,
  checkArtifact,
  deriveOccurrenceHash,
  deriveQueryId,
  deriveSourceOwnerHash,
  deriveTargetMappingHash,
  execute,
  executeArguments,
  extractHeadingSection,
  renderArtifact,
  validateIntegrationHooks,
  writeArtifact,
} from "../generate-source-query-reconciliation.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const SOURCE_RELATIVE =
  "docs/plans/ledger-accounting-redesign/conversion/query-contract.generated.json";
const TARGET_RELATIVE =
  "docs/plans/ledger-accounting-redesign/conversion/target-query-logical-authority-crosswalk.generated.json";
const MANIFEST_RELATIVE =
  "docs/plans/ledger-accounting-redesign/conversion/conversion-manifest.json";

function readJson(relativePath) {
  return JSON.parse(fs.readFileSync(path.join(ROOT, relativePath), "utf8"));
}

const BASE = (() => {
  const dossier = readJson(DOSSIER_RELATIVE);
  const registry = readJson(REGISTRY_RELATIVE);
  return {
    root: ROOT,
    dossier,
    registry,
    sourceInventory: readJson(SOURCE_RELATIVE),
    sourceInventoryBytes: fs.readFileSync(path.join(ROOT, SOURCE_RELATIVE)),
    targetAuthority: readJson(TARGET_RELATIVE),
    targetAuthorityBytes: fs.readFileSync(path.join(ROOT, TARGET_RELATIVE)),
    manifest: readJson(MANIFEST_RELATIVE),
    batches: registry.batches.map((descriptor) => ({
      descriptor,
      batch: readJson(descriptor.path),
    })),
  };
})();

function inputs() {
  return structuredClone(BASE);
}

function build(value = inputs()) {
  return buildReconciliation(value, { enforceRepositoryDiff: false });
}

function expectFailure(callback, pattern) {
  assert.throws(callback, (error) => {
    assert.match(error.message, /^source-query-reconciliation:/);
    assert.match(error.message, pattern);
    return true;
  });
}

function allRows(value) {
  return value.batches.flatMap(({ batch }) => batch.rows);
}

function findRow(value, predicate) {
  const match = allRows(value).find(predicate);
  assert.ok(match, "fixture row exists");
  return match;
}

function findOutcome(value, predicate) {
  for (const { batch } of value.batches) {
    for (const row of batch.rows) {
      const outcome = row.outcomes.find(predicate);
      if (outcome) return { batch, row, outcome };
    }
  }
  assert.fail("fixture outcome exists");
}

test("repository data yields the exact reviewed 386-query / 584-outcome baseline", () => {
  const artifact = build();
  assert.equal(artifact.lifecycle, BASE.dossier.status);
  assert.equal(artifact.totals.queries, 386);
  assert.equal(artifact.totals.outcomes, 584);
  assert.equal(artifact.totals.batches, 10);
  assert.deepEqual(artifact.totals.byCategory, {
    approved_future_target_query: 73,
    approved_target_nonquery_surface: 38,
    authority_blocked: 115,
    evidence_blocked: 6,
    retired: 210,
    source_only: 137,
    verified_target_query_port: 5,
  });
  assert.deepEqual(artifact.totals.authorityBlocked, {
    rows: 115,
    outcomes: 115,
    byScope: {
      retirement: 3,
      source_disposition: 100,
      target_nonquery_contract: 1,
      target_query_contract: 11,
    },
  });
  assert.deepEqual(artifact.totals.evidenceBlocked, {
    rows: 6,
    outcomes: 6,
    byScope: { source_reference_safety: 2, source_runtime_use: 4 },
  });
  assert.deepEqual(
    artifact.batches.map((batch) => [batch.totals.queries, batch.totals.outcomes]),
    [
      [29, 50],
      [10, 16],
      [123, 126],
      [35, 40],
      [18, 19],
      [3, 6],
      [8, 12],
      [13, 18],
      [129, 258],
      [18, 39],
    ],
  );
});

test("generated output is deterministic and excludes volatile, physical, and provider authority", () => {
  const first = renderArtifact(build());
  const second = renderArtifact(build());
  assert.equal(first, second);
  assert.ok(first.endsWith("\n"));
  assert.equal(first.endsWith("\n\n"), false);
  assert.doesNotMatch(first, /lastSynchronizedAt|conversionManifestHash|artifactSha256/);
  assert.doesNotMatch(first, /"(?:sql|rls|syncStream|provider|physicalAccess|indexName)"/);
  assert.doesNotMatch(first, /A-003|A-004/);
  assert.doesNotMatch(first, new RegExp(ROOT.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
});

test("dossier and control authority reject top-level, requirements, lifecycle, and matrix drift", () => {
  const cases = [
    [(value) => (value.dossier.extra = true), /dossier keys mismatch.*unexpected extra/],
    [(value) => (value.dossier.verification[0] = null), /verification stable entry must be an object/],
    [(value) => (value.dossier.requirements[0].invariant = "weakened"), /requirements projection is stale/],
    [(value) => (value.dossier.verification[0].expected = "weakened"), /verification projection is stale/],
    [
      (value) => value.dossier.contracts.postgresSchema.items.push({ table: "secret", sql: "create table secret" }),
      /contracts projection is stale/,
    ],
    [(value) => (value.dossier.status = "cutover_ready"), /unsupported value/],
    [
      (value) => (value.dossier.controlModel.outcomeConflictMatrix.matrix.target_preservation.behavior_retirement = "allow"),
      /controlModel is stale/,
    ],
    [
      (value) => value.dossier.controlModel.lifecycleAllowlists.implementation.paths.push("LedgeriOS/Bad.swift"),
      /controlModel is stale/,
    ],
  ];
  for (const [mutate, pattern] of cases) {
    const value = inputs();
    mutate(value);
    expectFailure(() => build(value), pattern);
  }
});

test("registry, batch, row, sourceRef, and outcome schemas are closed", () => {
  const cases = [
    [(value) => (value.registry.extra = true), /registry keys mismatch.*unexpected extra/],
    [(value) => (value.batches[0] = null), /input batches\[0\] must be an object/],
    [(value) => (value.batches[0].batch.extra = true), /keys mismatch.*unexpected extra/],
    [(value) => (value.batches[0].batch.rows[0].extra = true), /keys mismatch.*unexpected extra/],
    [(value) => (value.batches[0].batch.rows[0].sourceRef.extra = true), /keys mismatch.*unexpected extra/],
    [
      (value) => (value.batches[0].batch.rows[0].outcomes[0].physicalAccess = null),
      /keys mismatch.*unexpected physicalAccess/,
    ],
    [
      (value) => (value.registry.evidenceRequirements[0].ownerBindings[0].extra = true),
      /keys mismatch.*unexpected extra/,
    ],
    [(value) => (value.batches[0].batch.rows[0] = null), /rows\[0\] is malformed/],
    [
      (value) => (value.batches[0].batch.rows[0].outcomes[0] = null),
      /outcomes\[0\] must be an object/,
    ],
    [(value) => (value.targetAuthority.queries[0] = null), /queries\[0\] is malformed/],
    [
      (value) => (value.manifest.surfaces[0] = null),
      /conversion manifest\.surfaces\[0\] must be an object/,
    ],
    [
      (value) => (value.manifest.surfaces[0].physicalAccess = { sql: "select secret" }),
      /conversion manifest\.surfaces\[0\] keys mismatch.*unexpected physicalAccess/,
    ],
    [
      (value) => (value.manifest.surfaces[0].target.sql = "select secret"),
      /target keys mismatch.*unexpected sql/,
    ],
    [(value) => (value.registry.retirementAuthorities[0].extra = true), /retirement authorities/],
  ];
  for (const [mutate, pattern] of cases) {
    const value = inputs();
    mutate(value);
    expectFailure(() => build(value), pattern);
  }
});

test("source inventory identity, ordering, hashes, membership, and totals are independently checked", () => {
  const occurrence = BASE.sourceInventory.occurrences[0];
  assert.equal(deriveQueryId(occurrence), occurrence.id);
  assert.match(deriveOccurrenceHash(occurrence), /^[a-f0-9]{64}$/);
  const cases = [
    [(value) => (value.sourceInventory.extra = true), /source inventory keys mismatch/],
    [
      (value) => (value.sourceInventory.sourceFiles[0] = null),
      /source inventory\.sourceFiles\[0\] must be an object/,
    ],
    [(value) => (value.sourceInventory.occurrences[0].id = "QUERY-000000000000"), /id does not match derivation/],
    [(value) => (value.sourceInventory.occurrences[0].expression += " altered"), /expectedOccurrenceHash is stale/],
    [(value) => value.sourceInventory.occurrences.reverse(), /not deterministically ordered/],
    [(value) => (value.sourceInventory.sourceFiles[0].occurrenceCount += 1), /occurrence count is stale/],
    [(value) => (value.sourceInventory.byOperation.admin_sdk_get += 1), /operation totals/],
    [(value) => (value.sourceInventory.totals.occurrences -= 1), /occurrence total is stale/],
    [(value) => (value.registry.sourceInventory.artifactSha256 = "0".repeat(64)), /binding/],
  ];
  for (const [mutate, pattern] of cases) {
    const value = inputs();
    mutate(value);
    expectFailure(() => build(value), pattern);
  }
});

test("parsed source and target authority objects must match their exact artifact bytes", () => {
  const source = inputs();
  source.sourceInventory.limitations[0] += " altered only in memory";
  expectFailure(() => build(source), /source inventory parsed bytes/);

  const target = inputs();
  target.targetAuthority.totals.queries += 1;
  expectFailure(() => build(target), /target authority parsed bytes/);
});

test("package scripts and Linux-before-Swift workflow hooks are exact and fail closed", () => {
  const packageJson = readJson("package.json");
  const workflow = fs.readFileSync(
    path.join(ROOT, ".github/workflows/supabase-conversion-control.yml"),
    "utf8",
  );
  validateIntegrationHooks(packageJson, workflow);

  const missingScript = structuredClone(packageJson);
  delete missingScript.scripts["source:query-reconciliation:check"];
  expectFailure(
    () => validateIntegrationHooks(missingScript, workflow),
    /script source:query-reconciliation:check/,
  );
  const lifecycleBypass = structuredClone(packageJson);
  lifecycleBypass.scripts["presource:query-reconciliation:check"] = "echo bypass";
  expectFailure(
    () => validateIntegrationHooks(lifecycleBypass, workflow),
    /must not define presource:query-reconciliation:check/,
  );
  expectFailure(
    () => validateIntegrationHooks(packageJson, workflow.replace("    needs: conversion-control\n", "")),
    /must depend on conversion-control/,
  );
  expectFailure(
    () => validateIntegrationHooks(
      packageJson,
      workflow.replace(
        "          npm run source:query-reconciliation:test\n          npm run source:query-reconciliation:check",
        "          npm run source:query-reconciliation:check\n          npm run source:query-reconciliation:test",
      ),
    ),
    /conversion validation command order/,
  );
  expectFailure(
    () => validateIntegrationHooks(
      packageJson,
      workflow.replace(
        "swift test --package-path LedgeriOS --no-parallel",
        "swift test --package-path LedgeriOS",
      ),
    ),
    /nonparallel Swift test gate/,
  );
  expectFailure(
    () => validateIntegrationHooks(
      packageJson,
      workflow.replace("    runs-on: ubuntu-latest\n", "    if : ${{ false }}\n    runs-on: ubuntu-latest\n"),
    ),
    /must not conditionally skip/,
  );
  expectFailure(
    () => validateIntegrationHooks(
      packageJson,
      workflow.replace(
        "      - name: Stop isolated local Supabase\n        if: always()",
        "      - name: Stop isolated local Supabase\n        if: success()",
      ),
    ),
    /must not conditionally skip/,
  );
  expectFailure(
    () => validateIntegrationHooks(
      packageJson,
      workflow.replace(
        "      - name: Confirm target checks did not rewrite tracked artifacts\n        run: git diff --exit-code",
        "      - name: Confirm target checks did not rewrite tracked artifacts\n        if: always()\n        run: git diff --exit-code",
      ),
    ),
    /must not conditionally skip/,
  );
  expectFailure(
    () => validateIntegrationHooks(
      packageJson,
      workflow.replace(
        "      - name: Confirm checks did not rewrite tracked artifacts\n        run: git diff --exit-code",
        "      - name: No-op\n        run: echo ok",
      ),
    ),
    /exact read-only diff guard/,
  );
  expectFailure(
    () => validateIntegrationHooks(packageJson, workflow.replace("  pull_request:\n", "")),
    /conversion workflow triggers/,
  );
  expectFailure(
    () => validateIntegrationHooks(
      packageJson,
      workflow.replace(
        "    runs-on: ubuntu-latest\n",
        "    env:\n      NODE_OPTIONS: --require ./bypass.cjs\n    runs-on: ubuntu-latest\n",
      ),
    ),
    /conversion workflow integration artifact is stale/,
  );
});

test("assignment topology is disjoint, exhaustive, ordered, and lifecycle-synchronized", () => {
  const cases = [
    [(value) => value.batches[0].batch.assignedQueryIds.reverse(), /must be byte-sorted/],
    [
      (value) => (value.batches[1].batch.assignedQueryIds[0] = value.batches[0].batch.assignedQueryIds[0]),
      /global assignedQueryIds contains duplicate/,
    ],
    [(value) => value.batches[0].batch.rows.pop(), /READY row assignment/],
    [(value) => value.batches[0].batch.rows.reverse(), /must be byte-sorted/],
    [(value) => (value.batches[0].batch.status = "draft"), /lifecycle is not synchronized/],
    [(value) => (value.registry.batches[0].owner = "Wrong"), /batch metadata/],
    [(value) => value.registry.batches.reverse(), /batch metadata/],
  ];
  for (const [mutate, pattern] of cases) {
    const value = inputs();
    mutate(value);
    expectFailure(() => build(value), pattern);
  }
});

test("draft lifecycle permits a reviewed row subset while preserving exhaustive assignments", () => {
  const value = inputs();
  value.dossier.status = "draft";
  value.registry.status = "draft";
  for (const { batch } of value.batches) batch.status = "draft";
  const removed = value.batches[0].batch.rows.pop();
  const artifact = build(value);
  assert.equal(artifact.classificationState, "draft_partial");
  assert.equal(artifact.totals.queries, 385);
  assert.equal(artifact.totals.outcomes, 584 - removed.outcomes.length);

  value.batches[0].batch.rows.push(structuredClone(value.batches[1].batch.rows[0]));
  value.batches[0].batch.rows.sort((left, right) => Buffer.compare(Buffer.from(left.queryId), Buffer.from(right.queryId)));
  expectFailure(() => build(value), /draft rows are not a subset of assignments/);
});

test("selected source-owner projection rejects owner, reference, disposition, and hash substitution", () => {
  const value = inputs();
  const row = value.batches[0].batch.rows[0];
  const surface = value.manifest.surfaces.find((entry) => entry.id === row.sourceOwnerSurfaceId);
  assert.equal(deriveSourceOwnerHash(surface, row.sourceRef), row.expectedSourceOwnerHash);
  const cases = [
    [(candidate) => (candidate.batches[0].batch.rows[0].expectedSourceOwnerHash = "0".repeat(64)), /expectedSourceOwnerHash is stale/],
    [(candidate) => (candidate.batches[0].batch.rows[0].sourceRef.path = "package.json"), /differs from occurrence/],
    [(candidate) => (candidate.batches[0].batch.rows[0].sourceOwnerSurfaceId = "MISSING-OWNER"), /missing source owner/],
    [
      (candidate) => {
        const targetRow = candidate.batches[0].batch.rows[0];
        const targetSurface = candidate.manifest.surfaces.find((entry) => entry.id === targetRow.sourceOwnerSurfaceId);
        targetSurface.disposition = targetSurface.disposition === "replace" ? "preserve" : "replace";
      },
      /expectedSourceOwnerHash is stale/,
    ],
  ];
  for (const [mutate, pattern] of cases) {
    const candidate = inputs();
    mutate(candidate);
    expectFailure(() => build(candidate), pattern);
  }
});

test("verified target queries bind exact nonblocked TQUERY/TACCESS/mapping triples", () => {
  const { outcome } = findOutcome(BASE, (entry) => entry.category === "verified_target_query_port");
  const cases = [
    [(value) => (findOutcome(value, (entry) => entry.category === "verified_target_query_port").outcome.taccessId = "TACCESS-000000000000"), /exact target-query authority/],
    [(value) => (findOutcome(value, (entry) => entry.category === "verified_target_query_port").outcome.expectedMappingHash = "0".repeat(64)), /exact target-query authority/],
    [
      (value) => {
        const found = findOutcome(value, (entry) => entry.category === "verified_target_query_port").outcome;
        value.targetAuthority.queries.find((query) => query.tqueryId === found.tqueryId).reviewClass = "decision_blocked";
      },
      /decision-blocked TQUERY/,
    ],
    [
      (value) => {
        const found = findOutcome(value, (entry) => entry.category === "verified_target_query_port").outcome;
        const implemented = value.targetAuthority.queries.find(
          (query) => query.tqueryId === "TQUERY-038289DD7D2C",
        );
        value.manifest.surfaces.find(
          (surface) => surface.id === implemented.ownerSurfaceId,
        ).status = "implemented";
        found.tqueryId = implemented.tqueryId;
        found.taccessId = implemented.taccessId;
        found.expectedMappingHash = implemented.mappingHash;
      },
      /owner below verified lifecycle/,
    ],
  ];
  assert.match(outcome.tqueryId, /^TQUERY-/);
  for (const [mutate, pattern] of cases) {
    const value = inputs();
    mutate(value);
    expectFailure(() => build(value), pattern);
  }
});

test("verified target-query outcomes accept every exact verified-or-later owner lifecycle", () => {
  for (const status of ["verified", "rehearsed", "cutover_ready"]) {
    const value = inputs();
    const found = findOutcome(value, (entry) => entry.category === "verified_target_query_port").outcome;
    const query = value.targetAuthority.queries.find(
      (entry) => entry.tqueryId === "TQUERY-038289DD7D2C",
    );
    found.tqueryId = query.tqueryId;
    found.taccessId = query.taccessId;
    found.expectedMappingHash = query.mappingHash;
    value.manifest.surfaces.find((entry) => entry.id === query.ownerSurfaceId).status = status;
    assert.doesNotThrow(() => build(value), status);
  }
});

test("verified target-query outcomes reject every below-verified owner lifecycle and missing current owner", () => {
  const statuses = [
    "discovered",
    "characterized",
    "target_mapped",
    "implemented",
    "blocked",
    "retired",
    "unknown",
  ];
  for (const status of statuses) {
    const value = inputs();
    const found = findOutcome(value, (entry) => entry.category === "verified_target_query_port").outcome;
    const query = value.targetAuthority.queries.find(
      (entry) => entry.tqueryId === "TQUERY-038289DD7D2C",
    );
    found.tqueryId = query.tqueryId;
    found.taccessId = query.taccessId;
    found.expectedMappingHash = query.mappingHash;
    value.manifest.surfaces.find((entry) => entry.id === query.ownerSurfaceId).status = status;
    expectFailure(() => build(value), /owner below verified lifecycle/);
  }

  const missing = inputs();
  const found = findOutcome(missing, (entry) => entry.category === "verified_target_query_port").outcome;
  const query = missing.targetAuthority.queries.find(
    (entry) => entry.tqueryId === "TQUERY-038289DD7D2C",
  );
  found.tqueryId = query.tqueryId;
  found.taccessId = query.taccessId;
  found.expectedMappingHash = query.mappingHash;
  missing.manifest.surfaces = missing.manifest.surfaces.filter(
    (entry) => entry.id !== query.ownerSurfaceId,
  );
  expectFailure(() => build(missing), /missing manifest owner/);
});

test("future and nonquery mappings bind exact manifest members, status, disposition, target, and hash", () => {
  const found = findOutcome(
    BASE,
    (entry) => entry.category === "approved_target_nonquery_surface",
  );
  const surface = BASE.manifest.surfaces.find((entry) => entry.id === found.outcome.targetSurfaceId);
  assert.equal(deriveTargetMappingHash(surface), found.outcome.expectedTargetMappingHash);
  const cases = [
    [
      (value) => (findOutcome(value, (entry) => entry.category === "approved_target_nonquery_surface").outcome.expectedTargetMappingHash = "0".repeat(64)),
      /expectedTargetMappingHash is stale/,
    ],
    [
      (value) => {
        const selected = findOutcome(value, (entry) => entry.category === "approved_target_nonquery_surface").outcome;
        value.manifest.surfaces.find((entry) => entry.id === selected.targetSurfaceId).status = "blocked";
      },
      /target status has unsupported value/,
    ],
    [
      (value) => {
        const selected = findOutcome(value, (entry) => entry.category === "approved_target_nonquery_surface").outcome;
        value.manifest.surfaces.find((entry) => entry.id === selected.targetSurfaceId).disposition = "source_only";
      },
      /target disposition has unsupported value/,
    ],
    [
      (value) => (findOutcome(value, (entry) => entry.category === "approved_target_nonquery_surface").outcome.targetSurface = "missing member"),
      /not an exact target member/,
    ],
  ];
  for (const [mutate, pattern] of cases) {
    const value = inputs();
    mutate(value);
    expectFailure(() => build(value), pattern);
  }
});

test("authority blockers cannot be laundered across scopes, batches, or refs", () => {
  const cases = [
    [
      (value) => {
        const selected = findOutcome(value, (entry) => entry.category === "authority_blocked");
        selected.outcome.blockerIds = ["O-021"];
        selected.outcome.authorityRefs = [];
      },
      /forbidden blocker|not batch-allowed/,
    ],
    [
      (value) => (findOutcome(value, (entry) => entry.category === "authority_blocked").outcome.blockerIds = []),
      /must not be empty/,
    ],
    [
      (value) => findOutcome(value, (entry) => entry.category === "authority_blocked").outcome.blockerIds.reverse(),
      /must be byte-sorted/,
    ],
    [
      (value) => (findOutcome(value, (entry) => entry.category === "authority_blocked").outcome.authorityRefs[0].section = "Wrong"),
      /authorityRefs/,
    ],
    [
      (value) => {
        const authority = value.registry.blockerAuthorities.find((entry) => entry.id.startsWith("O-"));
        authority.path = "docs/architecture/redesign/architecture-decisions.md";
        authority.section = "A-007 — Target Authentication Choice";
      },
      /exact product-decision authority/,
    ],
  ];
  for (const [mutate, pattern] of cases) {
    const value = inputs();
    mutate(value);
    expectFailure(() => build(value), pattern);
  }
});

test("evidence requirements bind the complete selected owner tuple and exact blocker text", () => {
  const cases = [
    [
      (value) => (findOutcome(value, (entry) => entry.category === "evidence_blocked").outcome.ownerBindings[0].expectedBindingHash = "0".repeat(64)),
      /ownerBindings/,
    ],
    [
      (value) => (findOutcome(value, (entry) => entry.category === "evidence_blocked").outcome.ownerBindings[0].surfaceId = "WRONG"),
      /complete selected row owner|ownerBindings/,
    ],
    [
      (value) => (value.registry.evidenceRequirements[0].ownerBindings[0].blocker += " altered"),
      /selected manifest owner/,
    ],
    [
      (value) => (findOutcome(value, (entry) => entry.category === "evidence_blocked").outcome.evidenceRefs[0].requiredArtifact = "altered"),
      /evidenceRefs/,
    ],
  ];
  for (const [mutate, pattern] of cases) {
    const value = inputs();
    mutate(value);
    expectFailure(() => build(value), pattern);
  }
});

test("source-only compatibility is frozen to two BatchWriting document reads", () => {
  const artifact = build();
  const compatibilityRows = artifact.batches
    .flatMap((batch) => batch.rows)
    .filter((row) => row.outcomes.some((outcome) => outcome.purpose === "current_source_compatibility"));
  assert.deepEqual(
    compatibilityRows.map((row) => row.queryId).sort(),
    ["QUERY-241AE9EE0E3F", "QUERY-57FA49B52A1C"],
  );
  const value = inputs();
  const { outcome } = findOutcome(value, (entry) => entry.purpose === "current_source_compatibility");
  outcome.purpose = "audit";
  expectFailure(() => build(value), /compatibility coverage/);
});

test("retirement authority hashes, mechanism authority, and retention ordering fail closed", () => {
  const cases = [
    [(value) => (value.registry.retirementAuthorities[0].contentSha256 = "0".repeat(64)), /retirement authorities/],
    [
      (value) => (findOutcome(value, (entry) => entry.category === "retired").outcome.expectedRetirementAuthorityHash = "0".repeat(64)),
      /expectedRetirementAuthorityHash is stale/,
    ],
    [
      (value) => {
        const row = findRow(
          value,
          (entry) =>
            entry.outcomes.some((outcome) => outcome.category === "source_only") &&
            entry.outcomes.some(
              (outcome) => outcome.category === "retired" && outcome.scope === "source_query_mechanism_only",
            ),
        );
        row.outcomes.find((outcome) => outcome.category === "source_only").retentionGate =
          "through_verified_cutover_reconciliation";
        row.outcomes.find((outcome) => outcome.category === "retired").retirementGate =
          "after_verified_target_cutover";
      },
      /retention_before_retirement|does not follow source retention/,
    ],
  ];
  for (const [mutate, pattern] of cases) {
    const value = inputs();
    mutate(value);
    expectFailure(() => build(value), pattern);
  }
});

test("canonical outcome order, identities, cardinality, and conflict rules reject drift", () => {
  const cases = [
    [(value) => findRow(value, (row) => row.outcomes.length > 1).outcomes.reverse(), /canonical order/],
    [
      (value) => {
        const row = findRow(value, (entry) => entry.outcomes.some((outcome) => outcome.category === "source_only"));
        row.outcomes.splice(1, 0, structuredClone(row.outcomes.find((outcome) => outcome.category === "source_only")));
      },
      /canonical order|duplicate|more than one source_retention/,
    ],
    [
      (value) => {
        const row = findRow(value, (entry) => entry.outcomes.some((outcome) => outcome.category === "retired"));
        row.outcomes.find((outcome) => outcome.category === "retired").scope = "physical_index";
      },
      /unsupported discriminator|unsupported value/,
    ],
  ];
  for (const [mutate, pattern] of cases) {
    const value = inputs();
    mutate(value);
    expectFailure(() => build(value), pattern);
  }
});

test("Markdown authority extraction ignores fences, requires uniqueness, and normalizes CRLF", () => {
  const bytes = Buffer.from("# Root\r\n\r\n```md\r\n## Exact\r\n```\r\n## Exact\r\nBody\r\n## Next\r\n");
  assert.equal(extractHeadingSection(bytes, "Exact"), "## Exact\nBody\n");
  expectFailure(
    () => extractHeadingSection(Buffer.from("## Exact\nA\n## Exact\nB\n"), "Exact"),
    /must occur exactly once/,
  );
});

test("atomic writer refuses outside paths and precreated temp symlinks without touching targets", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "source-query-write-"));
  const outputDirectory = path.join(root, "out");
  fs.mkdirSync(outputDirectory);
  const output = path.join(outputDirectory, "artifact.json");
  expectFailure(() => writeArtifact("{}\n", path.join(root, "..", "outside.json"), { root }), /safe repository-relative path|escapes/);

  const sentinel = path.join(root, "sentinel");
  fs.writeFileSync(sentinel, "unchanged");
  const token = Buffer.alloc(16, 0);
  const temporary = path.join(outputDirectory, `.artifact.json.${process.pid}.${token.toString("hex")}.tmp`);
  fs.symlinkSync(sentinel, temporary);
  expectFailure(
    () => writeArtifact("new\n", output, { root, randomBytes: () => token }),
    /could not atomically write/,
  );
  assert.equal(fs.readFileSync(sentinel, "utf8"), "unchanged");
  assert.equal(fs.lstatSync(temporary).isSymbolicLink(), true);
  fs.unlinkSync(temporary);
  fs.symlinkSync(path.join(root, "missing-target"), output);
  expectFailure(
    () => writeArtifact("new\n", output, { root, randomBytes: () => Buffer.alloc(16, 1) }),
    /regular non-symlink file/,
  );
  assert.equal(fs.lstatSync(output).isSymbolicLink(), true);
  fs.unlinkSync(output);
  writeArtifact("ok\n", output, { root, randomBytes: () => Buffer.alloc(16, 1) });
  assert.equal(fs.readFileSync(output, "utf8"), "ok\n");
  assert.equal(fs.statSync(output).mode & 0o777, 0o644);
});

test("check mode is byte-exact and read-only", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "source-query-check-"));
  const directory = path.join(root, "out");
  fs.mkdirSync(directory);
  const output = path.join(directory, "artifact.json");
  fs.writeFileSync(output, "current\n");
  const before = fs.statSync(output);
  checkArtifact("current\n", output, { root });
  const after = fs.statSync(output);
  assert.equal(after.mtimeMs, before.mtimeMs);
  expectFailure(() => checkArtifact("different\n", output, { root }), /stale generated artifact/);
  assert.equal(fs.readFileSync(output, "utf8"), "current\n");
});

test("CLI arity is exact and module import has no execution side effect", () => {
  for (const argv of [[], ["generate", "extra"], ["Generate"], ["--check"], ["check", "check"]]) {
    expectFailure(() => executeArguments(argv), /usage:/);
  }
  expectFailure(
    () => execute("generate", { root: ROOT, artifactPath: path.join(ROOT, "package.json") }),
    /execute output must equal/,
  );
});

test("current repository lifecycle allowlist, baseline scaffolds, and artifact all validate", () => {
  const artifact = buildRepositoryReconciliation(ROOT);
  const rendered = renderArtifact(artifact);
  checkArtifact(rendered, path.join(ROOT, ARTIFACT_RELATIVE), { root: ROOT });
});

test("canonical object-key permutations are stable while semantic arrays remain ordered", () => {
  assert.equal(
    canonicalMinifiedJson({ b: 2, a: { d: 4, c: 3 } }),
    canonicalMinifiedJson({ a: { c: 3, d: 4 }, b: 2 }),
  );
  assert.notEqual(canonicalMinifiedJson({ values: [1, 2] }), canonicalMinifiedJson({ values: [2, 1] }));
});
