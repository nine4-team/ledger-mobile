# EVID-DETERMINISTIC-TEST-SUPPORT-001 — Deterministic Target Test Support

- Timestamp: 2026-09-01
- Class: implementation / provider-free reference test adapters
- Exact implementation commit: pending this bounded checkpoint on
  `codex/supabase-powersync-implementation`; immutable hosted CI is still
  required before verification
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and current test helpers remain unchanged
- Claimed target surfaces: `SWIFT-8AB5414F20CE`, `TEST-77875A971729`
- Slice dossier:
  `conversion/implementation-slices/deterministic-target-test-support.json`
- Slice state: implemented; three local obligations pass and exact-commit
  hosted CI remains planned

## Surface Selection

The reviewed platform mapping identifies `TEST-6A6B0926E2EE` and
`FILE-F29942C1A7F4` as broader current Swift/MCP test-helper outcomes. This
foundation does not claim either source surface. A provider-free reference
adapter module alone does not provide domain-specific semantic fixtures or
prove app, MCP, local database and cloud-staging contract parity.

Exactly two new target-only comment scaffolds are claimed. They isolate the
shared deterministic values and in-memory/failure reference adapters required
by Phase 1 without linking test support into the target staging app or the
released Firebase app.

## Ready-Gate Scope

The dossier traces exact architecture headings into a provider-free contract
for:

- validated non-production environment plus synthetic Principal/Account/
  scenario identity;
- fixed integer-millisecond time, domain-separated identifiers and monotonic
  revisions with explicit finite-schedule exhaustion;
- immutable scripted `OperationQuerying` and `SyncHealthProviding` reference
  adapters for cached/local, queued, authoritative, retry, rejection, required-
  update, maintenance and context-switch outcomes;
- bounded canonical scenario evidence that reconstructs the same outputs after
  restart and input reordering;
- stable atomic refusal for unsafe/production binding, nonfixture/cross-Account
  identity, duplicate/conflicting/nonmonotonic scripts, exhaustion, tamper,
  noncanonical bytes and size overflow; and
- a separate Swift package target that depends only on `LedgerTargetCore` and
  is linked by neither application project.

## Ready-Gate Verification

The comment-only scaffold hashes are acknowledged through the reviewed
platform-control batch and each surface is `target_mapped`. The dossier has no
blocker, every exact requirement is reciprocally covered, and domain,
offline-restart, offline-rejection and operational obligations are planned.
Postgres, handlers, Data API, RLS, PowerSync Streams, Storage/media, concrete
app/MCP integration, migration and observability are explicitly out of scope
rather than silently omitted.

## Implemented Contract

`LedgerTargetTestSupport/DeterministicTargetTestSupport.swift` now provides:

- a normalized `DeterministicTargetTestContext` that accepts only an already
  validated target-local/staging environment, synthetic `test-principal-*`,
  `test-account-*` and `test-scenario-*` identities, a nonzero seed and bounded
  integer epoch-millisecond base time;
- a finite `DeterministicTargetValueSource` that derives domain-separated
  timestamps, Operation/Entity IDs and monotonic revisions by stable key/index
  and refuses exhaustion or arithmetic overflow without reading clocks, UUIDs,
  randomness or global state;
- validated operation and unresolved-operation sequences with stable Account,
  contract, fingerprint, acceptance-time, ordering and lifecycle progression;
- immutable `ScriptedOperationQueryAdapter` and `ScriptedSyncHealthAdapter`
  implementations of the existing `LedgerTargetCore` ports, including finite
  success/failure streams and explicit durability outcomes;
- scenario-wide cross-reference, uniqueness and Account-isolation validation;
  and
- bounded sorted-key JSON evidence with integer-millisecond dates, SHA-256
  digest, canonical re-encoding and decode-through-constructor revalidation for
  context, schedules, operation scripts and Sync health invariants.

`LedgerTargetTestSupport` is a separate package product depending only on
`LedgerTargetCore`. Its self-test target depends only on those two products.
The graph guard scans both directories for provider imports and refuses either
test-support product in the target staging or Firebase application project.

## Local Verification

Local results on 2026-09-01:

- `swift test --package-path LedgeriOS --filter DeterministicTargetTestSupportTests`:
  pass, four tests;
- `swift test --package-path LedgeriOS`: pass, 63 tests across twelve suites;
- `npm run target:environment:check`: pass; exact package edges, provider-import
  scan and application/source-project exclusion are valid;
- `npm run target:contracts:check`: pass; generated Swift/TypeScript/MCP
  contract projections remain current;
- `npm run target:staging:build:macos`: pass; and
- `npm run target:staging:build:ios`: pass for generic iOS Simulator.

Fixtures prove exact deterministic values; local/queued/applying/applied/
rejected outcomes; offline-ready versus online-unsynchronized health; required-
update and maintenance blocks; successful and failed local durability; restart
and input-order equivalence; and stable refusal for production binding,
nonfixture identity, credential-shaped environment material, cross-Account
queries, missing/duplicate/out-of-order scripts, finite-schedule exhaustion,
digest tamper, noncanonical bytes and oversized evidence.

`TESTSUPPORT-TEST-001`, `TESTSUPPORT-TEST-002` and
`TESTSUPPORT-TEST-003` pass locally. `TESTSUPPORT-TEST-004` remains planned
until immutable GitHub Actions passes on the exact implementation commit with
conversion/contract/graph checks, all 63 tests, both target builds and clean
tracked artifacts. The slice and exactly its two target-only surfaces are
therefore `implemented`, not `verified`.

## Permanent Limits

This implementation and its ready-gate evidence cannot:

- choose or emulate a Supabase/PowerSync provider architecture;
- establish database, RLS, Sync Stream, encrypted-local-store or physical-
  device fidelity;
- define product-specific Client, Item, Transaction, Invoice, Space or media
  fixtures while their owning slice is unopened;
- replace current Swift/MCP helpers without concrete semantic and entry-point
  coverage;
- read Firebase, import an export, contact hosted services or use production
  credentials; or
- authorize migration, deployment, release or cutover.

No production read or mutation, Firebase implementation, provider connection,
hosted resource, migration, deployment or cutover occurred.
