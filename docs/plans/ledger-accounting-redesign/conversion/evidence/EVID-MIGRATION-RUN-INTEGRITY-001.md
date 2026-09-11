# EVID-MIGRATION-RUN-INTEGRITY-001 — Migration Run Plan and Journal Integrity

- Timestamp: 2026-09-01
- Class: implementation / migration evidence integrity / operational control
- Exact implementation commit:
  `34d52dba8960e6cd96621db10e2769c17cc86a4e` on
  `codex/supabase-powersync-implementation`
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree, current application, reverse migration
  package, profilers and release scripts are not modified or invoked
- Claimed target surfaces: `SWIFT-CBE990F49610`, `TEST-05A1A0F4E72C`
- Slice dossier:
  `conversion/implementation-slices/migration-run-plan-and-journal-integrity.json`

## Ready-Gate Scope

The provider-free ready dossier traces exact migration architecture headings
into a separate target tooling contract for:

- one immutable source-export, explicit target-environment, opaque Account-
  scope, repository, artifact, mapping and contract-version plan;
- unique expected entity work and exact planned counts/hashes;
- ordered, monotonic, replay-safe journal events and restart-stable resume
  evidence;
- terminal applied/skipped/blocked/failed entity counts and named
  reconciliation results;
- deterministic canonical plan/journal/manifest bytes and content digests;
- stable refusal for environment, plan, sequence, stage, count, hash, digest,
  canonical-shape and size mismatch; and
- an evidence-only disposition that cannot represent signing, operator
  approval, migration execution, production apply, rollback or cutover.

The implementation and test files were comment-only scaffolds when this gate
passed. Only then was the separate package product and behavior added.

## Implemented Contract

`LedgerTargetMigrationCore/MigrationRunIntegrity.swift` now provides:

- closed source-environment, run-mode, stage, journal-state, reconciliation,
  terminal-disposition and permanently evidence-only authority values;
- bounded opaque run/export identity, stable entity/artifact/rule/reason codes,
  safe versions, 40/64-character repository revisions and exact SHA-256 values;
- an immutable source snapshot plus a target binding derived from an already
  validated `LedgerEnvironmentManifest`, exposing only target kind and hashes
  of the environment/structured-data/Storage resources;
- a policy-validated `MigrationRunPlan` that binds opaque Account scope, exact
  contracts, migration/mapping artifacts and unique sorted per-entity expected
  counts/source hashes/transform versions;
- deterministic canonical plan bytes and content digest with fixed entity,
  mapping and byte ceilings;
- `MigrationRunJournal` events bound to the exact plan and its validator
  policy, with every public start/append/encode/decode boundary revalidating
  target, contract and artifact identity before accepting evidence, contiguous
  sequence, legal stage transitions, nondecreasing timestamps and counts,
  exact entity coverage, replay-idempotency, conflicting-replay refusal,
  interruption/resume semantics and a restart-stable resume fingerprint;
- overflow-safe examined/applied/skipped/blocked/failed counts constrained by
  each planned entity total;
- a terminal `MigrationRunManifest` that embeds the exact plan and journal,
  requires the complete named reconciliation rule set and distinguishes
  completed, interrupted, blocked and aborted evidence; and
- canonical plan/journal/manifest decode-and-revalidate boundaries with stable
  wrong-target, version/artifact, sequence/stage/time/count, reconciliation,
  digest, noncanonical and size failures.

Dry-run completion requires every planned entity to be examined with zero
applied writes. Apply-shaped completion requires applied plus skipped counts to
close the plan. In both cases the manifest remains `evidenceOnly`; no type in
this module can authorize or perform the run.

The Swift package exports this as `LedgerTargetMigrationCore`, depending only
on `LedgerTargetCore`. `LedgerTargetStaging` still links only
`LedgerTargetCore`, and the source Firebase Xcode project links neither target
module.

## Ready-Gate Verification

The comment-only scaffolds, reviewed classification, exact architecture
requirements, complete contract applicability and six reciprocal verification
obligations pass `npm run conversion:sync`, `npm run conversion:check`,
`npm run conversion:report` and the M0 gate with 725 recorded / 710 currently
discovered surfaces, zero errors and only the three documented retired-path
warnings. Behavioral verification remains planned and no implementation status
was claimed at that checkpoint.

## Local Verification

Local results on 2026-09-01:

- `swift test --package-path LedgeriOS --filter MigrationRunIntegrityTests`:
  pass, four tests;
- `swift test --package-path LedgeriOS`: pass, 55 tests across ten suites;
- `npm run target:environment:check`: pass, including explicit package-edge,
  provider-import and application-link isolation for migration tooling;
- `npm run target:contracts:check`: pass, including strict target TypeScript;
- `npm run target:project:generate`: pass with no tracked project rewrite;
- `npm run target:staging:build:macos`: pass;
- `npm run target:staging:build:ios`: pass for generic iOS Simulator; and
- conversion synchronization/checking passes at 725 recorded / 710 discovered
  surfaces with zero errors and the same three documented retired-path
  warnings.

Immutable GitHub Actions run
[`33573298495`](https://github.com/nine4-team/ledger-mobile/actions/runs/33573298495)
passed on that exact implementation commit. Its `Conversion state and
traceability` and `Isolated target environment` jobs both passed, including
conversion coverage and generated-artifact cleanliness, target dependency and
environment boundaries, generated app/MCP contracts, the complete 55-test
target package suite, the macOS build, the generic iOS Simulator build and the
final clean-diff guard.

## Verification Status

- `MIGRATION-RUN-TEST-001`: passed locally. Closed values, exact plan identity,
  legal journal state and terminal evidence are deterministic and evidence-
  only.
- `MIGRATION-RUN-TEST-002`: passed locally. Canonical journal evidence restores
  offline, identical replay is idempotent, and interruption resumes from the
  same fingerprint without duplicate counts.
- `MIGRATION-RUN-TEST-003`: passed locally. Wrong target, direct-decoded plan
  policy bypass, conflicting replay, count/stage regression, unsafe values,
  digest tamper, noncanonical bytes and oversize fail closed.
- `MIGRATION-RUN-TEST-004`: passed locally using synthetic dry-run/apply,
  interruption/resume and idempotent evidence without provider or file access.
- `MIGRATION-RUN-TEST-005`: passed locally. Completed evidence requires exact
  entity closure and the complete named reconciliation set with no unexplained
  or failed result.
- `MIGRATION-RUN-TEST-006`: passed in immutable GitHub Actions run
  `33573298495` on exact implementation commit `34d52dba`, including the full
  55-test package suite, graph guard, contract validation, both target builds
  and clean tracked artifacts.

All six obligations pass, so the slice and exactly its two target-only surfaces
are `verified`.

## Explicit Limits

This evidence does not read a Firebase export, production profile, file,
Storage object, database or provider. It does not define a transformation,
open a Supabase connection, create schema, persist a journal, sign a plan,
identify an operator, approve apply mode, execute, resume, abort or roll back a
migration, activate target authority, deploy, release or cut over. The current
reverse Supabase-to-Firebase package is source history only and is not reused.
