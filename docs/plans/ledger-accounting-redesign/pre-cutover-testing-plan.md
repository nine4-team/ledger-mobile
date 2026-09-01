# Ledger Accounting Redesign — Isolated Pre-Cutover Testing Plan

Status: proposed implementation architecture; required before redesign database work
Created: 2026-08-31
Last updated: 2026-08-31
Program: [Ledger Accounting Redesign](README.md)
Rollout control: [Production Compatibility and Rollout Plan](production-compatibility-plan.md)
Vertical spike: [Executable Supabase/PowerSync protocol](vertical-spike-protocol.md)

## Purpose

Ledger must be able to exercise the complete redesign—including source export,
target schema migration, RLS, command functions, PowerSync synchronization,
Storage, app behavior, and MCP behavior—without writing to either the production
Firebase source or the production Supabase/PowerSync target.

The hard cutover does not provide this test environment. Pre-cutover confidence
requires a separate Supabase/PowerSync backend whose data can be destroyed,
reset, and migrated repeatedly.

## Current Repository Finding

Ledger does not currently have a cloud staging environment:

- the only bundled `GoogleService-Info.plist` points to `ledger-nine4`;
- `FirebaseApp.configure()` always loads that production configuration;
- the normal `LedgeriOS` scheme therefore uses production;
- the only alternate scheme uses local Firebase emulators;
- `.firebaserc` defaults to `ledger-nine4`;
- the MCP defaults `FIREBASE_PROJECT_ID` to `ledger-nine4`;
- MCP Storage uses a hard-coded `ledger-nine4.firebasestorage.app` bucket even
  if Firestore is pointed somewhere else; and
- many audit/migration scripts default or are hard-coded to `ledger-nine4`.

Consequently, setting one environment variable is not sufficient isolation.
Using the current app, MCP, or scripts for staging could still read or mutate a
production service.

The authoritative target architecture and migration sequence are defined in the
[Redesign Architecture Foundation](../../architecture/redesign/README.md).
Firebase is only a source-export/migration fixture and eventual cutover boundary;
the redesigned app is tested entirely on Supabase + PowerSync.

## Required Test Environments

### 1. Versioned Firebase Source Fixtures

Maintain sanitized, versioned exports representing the known production
Firestore/Storage shapes. Use them for deterministic tests of:

- source decoding and legacy variants;
- migration idempotency and failure injection;
- source-to-target ID/relationship mapping;
- malformed and ambiguous blocker reporting; and
- source/target reconciliation.

The Firebase emulator may be used only if the export tool itself requires a
live Firestore-shaped source. Do not launch the redesigned app against it, build
a Firebase application adapter, or create a Firebase cloud staging project.

### 2. Local Target Stack

Use local Supabase/Postgres and a local PowerSync service/test client where
supported for destructive, deterministic tests of:

- schema migrations, constraints, triggers, and SQL command functions;
- RLS and Principal/membership resolution;
- Sync Stream definitions and upload-queue behavior;
- adapter contract and conflict tests;
- local database reset/encryption lifecycle; and
- target Storage policies and attachment-state transitions.

### 3. Dedicated Supabase + PowerSync Staging

Provision an organization-owned staging environment with separate:

- Supabase project, Postgres database, schemas, and migrations;
- PowerSync instance, Sync Streams, and backend connector;
- staging identities and Principal mappings;
- Supabase Storage buckets and policies;
- Edge Functions or other target services actually used by the design;
- iOS/macOS target-backend configuration;
- service accounts/IAM;
- MCP deployment or local MCP credentials; and
- observability/logging.

No staging credential may write to `ledger-nine4` or any production target
resource.

### 4. Production Read-Only Rehearsal

Production may be audited before cutover, but only through read-only tooling.
The production rehearsal produces the migration plan, counts, hashes, blockers,
and expected financial reconciliation. It does not modify documents, deploy
rules, or invoke mutating target Functions.

## Staging App Isolation

Add a staging build configuration and `LedgeriOS (Staging)` scheme with:

- compiled staging Supabase, PowerSync, Storage, and identity configuration;
- staging identity configuration for the chosen launch Auth strategy; a
  Firebase Auth configuration is permitted only if proposed A-007 selects that
  integration and does not include Firestore/Storage target access;
- a distinct bundle identifier, such as an approved `.staging` variant, so it
  can coexist with production and has separate keychain/container state;
- a permanent, unmistakable **STAGING** banner and app-name suffix;
- startup assertions that every resolved service matches the compiled staging
  allowlist;
- startup refusal if any service resolves `ledger-nine4` or a production target
  identifier; and
- no production invite, hosting, Sparkle, or universal-link configuration.

Environment selection must be compiled into the scheme. Do not add an in-app
toggle that could switch a running production build to staging or vice versa.

The ordinary `LedgeriOS` scheme remains production-backed under the repository
development rules. Staging QA must deliberately select the staging scheme.

## Staging MCP and Script Isolation

Before staging is usable:

1. Keep target MCP/Storage configuration entirely Supabase/PowerSync. Give the
   separate migration/export tool an explicit source Firebase and target
   environment contract; remove production defaults from staging/test entry
   points.
2. Give staging MCP a staging-only service account and endpoint/configuration.
3. Make every redesign audit/migration command require explicit:
   - environment;
   - source Firebase project when used;
   - target Supabase project/database and PowerSync instance;
   - source and target Storage resources;
   - account ID;
   - credentials whose embedded resources match the requested environment; and
   - dry-run versus commit mode.
4. Default migration commands to dry-run.
5. Refuse production commits unless a separate production-only acknowledgement
   and reviewed plan artifact are supplied.
6. Refuse staging commands if any resolved service equals a production
   identifier.
7. Write a machine-readable run manifest containing commit, source and target
   resources, account, mode, input snapshot, planned counts, and output
   reconciliation.

Production IDs and buckets must not be general-purpose defaults. Explicit
production tools may retain them only when their entire purpose is a narrowly
reviewed production repair and they already fail closed around scope.

## Production-Like Staging Data

Two datasets serve different purposes:

### Curated deterministic fixtures

Maintain small version-controlled v1 fixtures covering every important story,
including legacy enum values, proto Items, movement lineage, live and paid
Invoices, missing relationships, mixed categories, returns, credits, and
receipt-completeness edge cases. These run locally and in staging smoke tests.

### Restricted production snapshot

For migration rehearsal, transform a point-in-time Firestore snapshot into the
resettable Supabase staging database under restricted organizational access. Do
not connect staging Auth to production users.

In plain language, a rehearsal is:

1. take a read-only point-in-time export of production Firebase;
2. preserve that export as immutable input;
3. run the candidate Firebase-to-Supabase transformer against the copy;
4. load the result into a disposable, isolated Supabase/PowerSync staging
   environment;
5. run the target app and its migration, offline, security, accounting, and
   reconciliation suites there; and
6. discard/reset staging, capture a newer export later, and repeat.

No rehearsal writes back to production Firebase, changes the current app, or
creates a Firebase implementation of the redesigned app. “Production snapshot”
means production-shaped source data, not production credentials attached to the
staging app.

- Create separate staging test users and account memberships.
- Preserve document IDs and relationships required for migration accuracy.
- Record the production source timestamp and export identifier.
- Treat names, notes, addresses, receipts, and client records as sensitive even
  in staging.
- Do not copy production Storage blindly.
  Migration tests can preserve attachment metadata and use placeholder media;
  copy only a reviewed fixture subset into target staging for media flows.
- Rewrite every copied Storage URL that staging operations may delete or move so
  it targets staging, never the production bucket.

The snapshot importer and membership rewrite must themselves be idempotent and
must reject a production destination.

## How Destructive Changes Are Tested

For every migration version:

1. Reset staging to a known v1 snapshot.
2. Deploy the exact candidate Postgres migrations, RLS, command functions, Sync
   Streams/backend connector, Storage policies, and MCP configuration to
   staging.
3. Run the migration in dry-run mode and review its per-record plan.
4. Run the real migration against staging, including target-row rewrites and
   any target cleanup that would be destructive. The source snapshot is an
   immutable input.
5. Launch the staging app and exercise every end-to-end accounting story.
6. Run source-level financial reconciliation, relationship/invoice/budget
   invariants, decode-drop checks, and orphan scans.
7. Rerun the migration and prove it is idempotent.
8. Inject interruption after each batch boundary, resume, and prove there are no
   duplicate or half-migrated accounting events.
9. Test rollback/freeze behavior.
10. Reset staging and repeat from a fresher production snapshot.

The staged run produces a signed-off manifest. Production execution must use
the same migration artifact/commit and compare its dry-run results with the
latest staging rehearsal before committing.

## Production Uses Expand–Migrate–Switch–Contract

Testing a deletion does not mean production should delete that structure during
the hard cutover.

### Expand

Build and provision the isolated target stack, new app, and shadow verification
while the existing production Firebase app remains unchanged and authoritative.

### Migrate

Import and transform target relationships while Firebase remains authoritative.
Replay reviewed deltas and validate both projections; do not make clients
general-purpose dual writers.

### Switch

During the hard cutover, stop affected accounting writes, take the final source
backup, run the tested delta migration, verify reconciliation, activate
Supabase/PowerSync authority, and re-enable writes through target commands.

### Contract

Only after the rollback and migration-evidence retention window:

- delete or archive obsolete proto records;
- delete retired fields;
- remove legacy enum fallbacks;
- retire v1 calculations/Functions and the old Firebase application/backend;
- revoke obsolete Firebase rules/IAM; and
- remove obsolete indexes or Storage paths after manifest verification.

The target app must be tested in staging both with retained migration evidence
and after simulated cleanup. This proves that deferred source retirement does
not affect target behavior and that later cleanup is safe.

## Hard-Cutover Runbook

The final production operation is deliberately short because all expensive
discovery happened in staging:

1. Verify target release readiness, source quiescence, and the approved O-022
   late-write recovery procedure. No intermediate Firebase-compatible build is
   required.
2. Enable an accounting maintenance mode that disables affected mutations.
3. Reject old direct accounting writers at the backend boundary.
4. Take and verify a production Firestore backup plus required Storage metadata.
5. Run the exact migration artifact in production dry-run mode.
6. Abort if counts, source hashes, drift, or blockers exceed the reviewed plan.
7. Commit the idempotent delta migration with document preconditions and a
   durable journal.
8. Activate Supabase/PowerSync commands, synchronization, and budget authority
   in the rehearsed order.
9. Run the same reconciliation suite used in staging.
10. Re-enable accounting writes only after the release gates pass.
11. Monitor and retain legacy data for rollback; do not contract immediately.

Unaffected read-only and operational features may remain available if their
queries do not depend on migrating collections. The exact maintenance scope is
determined by the final dependency graph.

## Required Deliverables Before Feature Implementation

- [ ] Approved staging Supabase project, PowerSync instance, Storage, and identity resources.
- [ ] `LedgeriOS (Staging)` configuration with runtime production-resource refusal.
- [ ] Staging MCP/backend configuration with no hard-coded production resource.
- [ ] Fail-closed environment guard shared by redesign migration tools.
- [ ] Versioned curated v1 fixtures.
- [ ] Restricted production-snapshot import/reset procedure.
- [ ] Staging Auth/membership bootstrap.
- [ ] Candidate schema/RLS/functions/Sync Streams/Storage deployment wrapper scoped to staging.
- [ ] Migration run-manifest and reconciliation formats.
- [ ] Accounting maintenance-mode design.
- [ ] Proof that no staging credential can write production.
