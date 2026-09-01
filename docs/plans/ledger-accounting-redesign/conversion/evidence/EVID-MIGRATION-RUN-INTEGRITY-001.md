# EVID-MIGRATION-RUN-INTEGRITY-001 — Migration Run Plan and Journal Integrity

- Timestamp: 2026-09-01
- Class: implementation planning / migration evidence integrity / operational control
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

The implementation and test files are comment-only scaffolds. The separate
module is not yet declared in the Swift package and is not linked into the
target application. No behavioral implementation starts until the dossier and
conversion controls pass `ready`.

## Ready-Gate Verification

The comment-only scaffolds, reviewed classification, exact architecture
requirements, complete contract applicability and six reciprocal verification
obligations pass `npm run conversion:sync`, `npm run conversion:check`,
`npm run conversion:report` and the M0 gate with 725 recorded / 710 currently
discovered surfaces, zero errors and only the three documented retired-path
warnings. Behavioral verification remains planned and no implementation status
is claimed at this checkpoint.

## Explicit Limits

This evidence does not read a Firebase export, production profile, file,
Storage object, database or provider. It does not define a transformation,
open a Supabase connection, create schema, persist a journal, sign a plan,
identify an operator, approve apply mode, execute, resume, abort or roll back a
migration, activate target authority, deploy, release or cut over. The current
reverse Supabase-to-Firebase package is source history only and is not reused.
