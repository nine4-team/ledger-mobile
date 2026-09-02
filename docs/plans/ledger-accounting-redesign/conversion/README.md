# Supabase Conversion Control Plane

Status: M0 inventory classification complete; 361 of 525 target-relevant
surfaces are target-mapped or later and the remaining 164 are explicitly tied
to decisions/spikes/production evidence. Decision-independent target
foundations are in progress. M1 is blocked only by canonical production-profile
evidence and O-022 hard-cutover evidence; production migration is not authorized
by this directory. The Client/Project directory read-contract slice is verified
at exact implementation commit `3c0b58b6`; the provider-free Transaction
taxonomy/Transfer-identity slice is verified at exact implementation commit
`031a240a`. The provider-free exact same-Client Transfer destination-selection
slice is verified at exact implementation commit `6dc7d0c2`, including all 80
target tests and both staging builds. The provider-free non-item receipt-line/
exact-reconstruction slice is verified at exact implementation commit
`594aec1e`, including all 84 target tests and both staging builds, without
choosing billing, rounding, Item-tax-basis or Transaction-posting policy.
The provider-free Project Item relationship-derived accounting-section slice is
verified at exact implementation commit `92e0b565`, including all 88 target
tests and both staging builds. It chooses no Item/Link, occurrence persistence,
credit settlement, media, provider or migration behavior. Broader app/schema/
provider and migration surfaces remain unadvanced. The provider-free attachment
capture/local-durability receipt slice is verified at exact implementation
commit `1792a862`, including all 92 target tests and both staging builds. It
explicitly does not claim physical byte persistence, encryption, upload,
display, Storage, retention or provider behavior. The provider-free Client
creation operation slice is verified at exact implementation commit `3b837af3`,
including all 96 target tests and both staging builds. It defines no server row,
authorization, Auth/provider, schema, Sync, app/MCP, migration or production
behavior. The provider-free Project setup operation slice is verified at exact
implementation commit `8d8cd30f`, including all 100 target tests and both
staging builds, without introducing rows, authorization, media, providers or
production behavior. The provider-free Project archive operation slice is
verified at exact implementation commit `7b30bd25`, including all 104 target
tests and both staging builds, without introducing lifecycle storage,
authorization, providers, migration or production behavior. The provider-free
budget-category reference read slice is verified at exact implementation commit
`713dcf57`, including all 108 target tests and both staging builds. It defines
no hidden fee visibility, mutation, server authorization, provider, migration
or production behavior. The provider-free Project category configuration read
slice is verified at exact implementation commit `40d20efb`, including all 112
target tests and both staging builds. It defines no budget arithmetic, hidden
visibility, mutation, provider, migration or production behavior.
The provider-free Client rename command slice is verified at exact
implementation commit `3282f8e3`, including all 116 target tests and both
staging builds. It preserves stable Client identity, replacement display text,
expected revision and the shared operation lifecycle without deciding Client
archive/merge, Project reassignment, provider, migration or production
behavior.
The provider-free Project rename command slice is verified at exact
implementation commit `7f395bbe`, including all 120 target tests and both
staging builds. It preserves stable Project identity, replacement display text,
expected revision and Client-relationship separation without deciding Project
deletion, Client reassignment, provider, migration or production behavior.
The provider-free Project-note read slice is verified at exact implementation
commit `b421f419`, including all 124 target tests and both staging builds.
Exactly two target surfaces preserve stable Account/Project/note identity,
audit and tombstone evidence, deterministic bounded order and explicit offline-
history readiness without authorizing mutation, provider, migration or
production behavior.
The provider-free Project-note creation slice is verified at exact
implementation commit `15566c8d`, including all 128 target tests and both
staging builds. Exactly two target surfaces preallocate stable note identity, bind
exact Project/text/requested-source intent to the shared operation lifecycle,
exclude caller-authored authoritative creator/time/source evidence and reserve
non-enumerating parent preflight for a later trusted handler. No note row,
provider, app/MCP, migration or production behavior exists at this checkpoint.
The provider-free current-Principal Project preference read slice is verified at
exact implementation commit `59526ccc`, including all 132 target tests and both
staging builds. Exactly two target surfaces preserve ordered stable pin
identities, revision, exact Account/Principal/Project binding and authoritative
absence versus incomplete local evidence. Preference writes,
authentication, schema/RLS/Sync/provider behavior, category resolution, budget
calculation, app/MCP, migration and production remain excluded.
The provider-free current-Principal Project preference update slice is
verified. Exactly two target surfaces define a complete ordered pin replacement,
explicit not-stored versus exact-revision concurrency, canonical restart/refusal
and the shared operation lifecycle. Exact implementation commit `0e652548`
and immutable Actions run `33628801064` pass all 136 target tests, graph/
generated-contract checks, both staging builds and clean artifacts.
Authentication, category mutation/resolution, defaults, physical persistence,
schema/RLS/Sync/provider behavior, app/MCP, migration and production remain
excluded.
The provider-free vendor-suggestion reference read slice is verified. Exactly
two target surfaces define stable Account-scoped suggestion identity, bounded
preserved display spelling, normalized duplicate detection, lifecycle/revision/
order, canonical readiness/restart/refusal and source-text-only selection.
Exact implementation commit `519b4338` and immutable Actions run `33632364285`
pass all 140 target tests, graph/generated-contract checks, both staging builds
and clean artifacts. O-026 mutation authority, default seeding, physical
persistence, schema/RLS/Sync/provider behavior, app/MCP, migration and
production remain excluded.
The provider-free Space-template reference read slice is verified. Exactly two
target surfaces define stable Account/template/checklist/item identity, text,
lifecycle/revision/order, structure without checked state, readiness/restart/
refusal and one narrow query port. Exact implementation commit `f23afce3` and
immutable Actions run `33636359059` pass all 144 target tests, graph/generated-
contract checks, both staging builds and clean artifacts.
O-026 mutation authority, template apply/save, Space creation, physical
persistence, schema/RLS/Sync/provider behavior, app/MCP, migration and
production remain excluded.
The provider-free Client archive operation slice is verified.
Exactly two target surfaces define one stable Client archive intent, exact
expected-revision precondition, shared operation lifecycle and explicit no-
cascade/no-delete/no-merge/no-reassignment boundary. Exact ready commit
`9f3a03dd` and immutable Actions run `33638235220` pass all 144 then-existing
tests and both builds. Exact implementation commit `e10be9ec` and immutable
Actions run `33639210706` pass four focused/all 148 target tests, graph/
generated-contract checks, both staging builds and clean artifacts.
O-025, physical persistence, schema/RLS/Sync/Auth/provider behavior, app/MCP,
migration and production remain excluded.
The provider-free Project details update slice is verified. Exactly
two target surfaces define one canonical optional-description replacement,
stable Project identity, exact expected revision, shared operation lifecycle
and explicit separation from rename, Client/category/media/lifecycle/child/
accounting/history mutation. Exact ready commit `119e0455` and immutable
Actions run `33641244740` pass all 148 then-existing tests and both builds.
Exact implementation commit `a532ac9d` and immutable Actions run `33642777864`
pass four focused/all 152 target tests, graph/generated-contract checks, both
staging builds and clean artifacts. O-023/O-024/O-025, physical persistence,
schema/RLS/Sync/Auth/provider behavior, app/MCP, migration and production remain
excluded.
The provider-free direct Space creation slice is verified. Exactly two target
surfaces implement a stable
Space ID, exact Project-or-Business-Inventory scope, normalized required name
and optional notes, zero expected-revision preconditions, shared operation
lifecycle, canonical restart/refusal and a narrow port. Exact implementation
commit `03b545df` and immutable Actions run `33647113450` pass four focused/all
156 target tests, graph/generated-contract checks, both staging builds and clean
artifacts. Checklist/template/media/
Item/review/lifecycle/accounting mutation, authorization, physical persistence,
schema/RLS/Sync/provider behavior, app/MCP, migration and production remain
excluded. O-023/O-026/O-037 stay open; `EVID-SPACE-CREATION-001`.
The provider-free Space details update slice is verified. Exactly two target
surfaces implement one
complete normalized name/optional-notes replacement, stable Space identity,
exact same-Space expected revision, shared operation lifecycle, canonical
restart/refusal and a narrow port. Exact implementation commit `1c8c12b4` and
immutable Actions run `33654631876` pass four focused/all 160 target tests,
graph/generated-contract checks, both staging builds and clean artifacts.
Scope/checklist/template/media/Item/review/
lifecycle/accounting mutation, authorization, physical persistence, schema/RLS/
Sync/provider behavior, app/MCP, migration and production remain excluded.
O-023/O-026/O-037 stay open; `EVID-SPACE-DETAILS-UPDATE-001`.
The provider-free Space checklist revision slice is verified. Exactly two
target surfaces implement one complete canonical ordered
checklist hierarchy replacement, stable distinct nested identities, checked-
state progress, exact same-Space expected revision, shared operation lifecycle
and a narrow port. Exact implementation commit `8131e857` and immutable
Actions run `33659853864` pass four focused/all 164 target tests, graph/
generated-contract checks, both staging builds and clean artifacts.
Scope/details/template/media/Item/review/Space-completion/
lifecycle/accounting mutation, authorization, physical persistence, schema/RLS/
Sync/provider behavior, app/MCP, migration and production remain excluded.
O-023/O-026/O-032/O-037 stay open; `EVID-SPACE-CHECKLIST-REVISION-001`.
The provider-free session-ending pending-work slice is verified. Exactly two
target surfaces define one
environment/Principal/Account-scoped
summary with exact queued, applying, unresolved-rejected and unverified-
attachment counts, plus clean, sync-first and exact-confirmed destructive
dispositions, canonical fingerprint/restart/refusal, cancellation no-call and
one narrow port. Exact ready commit `caa9a900` / run `33662071456` and four
focused/all 168 target tests in 39 suites, graph/contracts, both staging builds,
and clean artifacts pass at exact implementation commit `bf9a00ca` in immutable
run `33663785835`. Auth provider and offline lease choices, final UI copy/policy,
physical synchronization/cleanup, O-023 media retention, schema/RLS/Sync,
app/MCP, migration, hosted resources and production remain excluded;
`EVID-SESSION-ENDING-POLICY-001`.
The provider-free Account discovery and explicit selection slice is verified.
Exact ready commit `ae16ed4e` passed immutable Actions run `33666363647`, and
exact implementation commit `e2972b9c` passed immutable Actions run
`33668715587`. Exactly two target surfaces define environment/Principal-scoped,
visibility-safe Account rows; ready/partial/stale/authoritative-empty/failure
distinction; deterministic remembered-first presentation with no automatic
selection; exact-snapshot-bound non-authorizing selection intent; canonical
restart/refusal; stable diagnostics; and one narrow query port. Four focused/
all 172 target tests in 40 suites, graph/contracts, both staging builds and
clean artifacts pass locally and at the immutable implementation checkpoint.
A-007/A-016/O-023,
current authorization, physical workspace activation/switching, membership/
Account writers, schema/RLS/Sync, app/MCP, migration, hosted resources and
production remain excluded; `EVID-ACCOUNT-DISCOVERY-SELECTION-001`.
The provider-free Item-to-Space assignment slice is verified after
exact ready commit `30f4ab88` passed immutable Actions run `33670383410`.
Exactly two target surfaces define one story-specific `AssignItemsToSpace`
intent: exact Account/actor/Operation scope, one stable Project-or-Business-
Inventory destination Space and revision, a canonical nonempty duplicate-free
Item/revision set, deterministic active/revision/scope preconditions, atomic
refusal, restart/replay, stable diagnostics and one narrow port. Four focused
and all 176 target tests in 41 suites, graph/contracts, both staging builds,
repeatable project generation and clean artifacts pass locally and at exact
implementation commit `c5fdf5c7` in immutable run `33672006836`. O-037 remains
open because archive is excluded; Item scope/
accounting, physical persistence, schema/RLS/Sync, app/MCP, migration, hosted
resources and production remain absent; `EVID-ITEM-SPACE-ASSIGNMENT-001`.
The provider-free Item Space-clearing slice is verified after exact
ready commit `2a201de4` passed immutable Actions run `33675190031`. Exactly two
target surfaces define one story-specific
`ClearItemSpaceAssignments` intent: exact Account/actor/Operation scope, one
immutable Project-or-Business-Inventory scope, a canonical nonempty duplicate-
free Item/revision/current-Space set that may span different source Spaces,
deterministic scope/current-placement preconditions, atomic refusal, restart/
replay, marker-relationship closure without media deletion and one narrow port.
Four focused and all 180 target tests in 42 suites, graph/contracts, both staging
builds, repeatable project generation and clean artifacts pass locally and at
exact implementation commit `f5a7ac75` in immutable run `33677087616`. O-037
remains open because archive is excluded; O-023 remains open because no
attachment reference or byte is removed; destination assignment, Item scope/
accounting, physical persistence, schema/RLS/Sync, app/MCP, migration, hosted
resources and production remain absent; `EVID-ITEM-SPACE-CLEARING-001`.
The provider-free Space assignment-destination directory slice is implemented
pending the complete integration gate and exact integration-commit CI. Exactly
two target surfaces now define one
exact Account and Project-or-Business-Inventory request, active stable Space
identity/name/revision rows, deterministic duplicate-name ordering, explicit
ready/authoritative-empty/partial/stale/failure truth, canonical restart,
bounded refusal and one narrow query port. The exact ready commit passed both
CI jobs. The first isolated worker candidate changed only the two allowlisted
files; the integration agent reviewed every line and reran four focused/all 184
tests, and an independent adversarial reviewer found no P0-P2 defect. One P3
documentation ambiguity was corrected so legitimate later revisions/readiness
are not described as tamper. The complete local integration gate passes all
184 tests in 43 suites, conversion/target checks, repeatable generation and
both staging builds; exact integration-commit CI remains pending.
Authorization, physical persistence, schema/RLS/Sync,
assignment mutation, app/MCP, migration, hosted resources and production remain
excluded; `EVID-SPACE-ASSIGNMENT-DESTINATION-001`.

This directory makes whole-application conversion progress durable across long
agent runs, context compaction, task handoffs, and restarts. Conversation memory
is never the authority for what has been covered or verified.

## Long-Running Goal Operating Model

Run the redesign as one coherent long-running goal, but never as one
conversation-memory-sized unit of work. The goal owns the overall outcome; the
repository owns authority, progress, evidence, and the next executable action.

- `AGENTS.md` is the always-loaded constitution: it names the boot sequence,
  prohibited work, required checks, and approval boundaries.
- This README and `execution-state.md` are the resumable execution plan. The
  latter must identify the current checkpoint, honest blockers, and exact next
  action rather than narrating what an agent remembers.
- `conversion-manifest.json`, generated audits, slice dossiers, and the evidence
  index are the machine-enforced state. Conversation summaries cannot advance
  them.
- `.github/workflows/supabase-conversion-control.yml` reruns the deterministic
  control checks for every pull request. Configure its `Conversion state and
  traceability` job as a required branch-protection check so an agent cannot
  merge stale coverage or invalid slice claims merely by skipping a local
  command.
- One active implementation slice is the normal unit of delivery. Its dossier
  is updated alongside requirements, code, migrations, tests, and evidence—not
  reconstructed only at the end of a long turn.
- Write-capable subagents follow
  `parallel-subagent-workflow.md` and `parallel-work-registry.json`: the primary
  agent remains the sole control-plane/integration writer, workers own one
  frozen slice in isolated worktrees, and the first two pilots receive complete
  primary-agent line review plus an independent adversarial review before
  integration or status promotion.
- A repo-local Codex hook at `.codex/hooks.json` runs after context compaction.
  It re-injects the persisted checkpoint and a fresh conversion-check result
  before the immediate continuation. The hook is recovery context, not product
  authority and not permission to proceed through a failed gate.
- Parallel tasks may research or test bounded, non-overlapping work. They must
  return durable repository artifacts, and two tasks must never write the same
  checkout or slice concurrently.
- The goal continues through routine checkpoints without asking the user to say
  “proceed.” It pauses only at the explicit decision, credential, spend,
  production, migration, release, or cutover boundaries recorded here.

Automatic compaction may happen in the middle of a bounded slice. The resumed
agent must inspect the slice dossier and working-tree diff, rerun the check, and
continue or repair the same slice. It must not infer completion from the compacted
summary or select a different slice merely because the prior reasoning is gone.

## Authority and Files

- `conversion-manifest.json` is the machine-readable coverage source of truth.
- `conversion-coverage.md` is generated from the manifest and must not be edited
  manually.
- `execution-state.md` records the exact safe resumption point.
- `evidence-index.md` defines and indexes acceptable proof.
- `current-backend-contract.md` is the reviewed description of the existing
  Firebase data, Auth, security, Functions, and media boundary.
- `current-query-contract.md` is the reviewed Firestore query/listener, offline
  expectation, pagination, and index contract.
- `capability-evolution-method.md` defines how observed source behavior and
  possibly stale specs become deliberate preserve/correct/improve/redesign/
  retire decisions before target design.
- `target-mapping-method.md` defines the required M2 owner/surface/security/
  sync/migration/verification record and honest status rules.
- `vertical-slice-implementation-method.md` defines the mandatory implementation
  lifecycle from exact spec sections and invariants through domain contracts,
  Postgres, grants/RLS, Sync Streams, offline behavior, app/MCP parity,
  migration, reconciliation, evidence and rollback.
- `../vertical-spike-protocol.md` defines the resumable S0–S9 evidence needed to
  resolve the remaining provider, Auth, optimistic-operation, offline-lease and
  physical-target architecture gates; prose alone closes none of them.
- `current-capability-register.md` groups the current service/MCP layer by user
  and operational outcome and owns the dossier review queue.
- `capability-surfaces.generated.json` and `.md` are the deterministic complete
  Swift service/Auth and MCP file/symbol assignment for that register.
- `query-contract.generated.json` and `.md` are deterministic line/symbol-level
  query occurrence artifacts; regenerate rather than editing them.
- `residual-decision-register.generated.json` and `.md` are the deterministic
  M2 queue of every target-relevant surface that is not yet mapped, grouped by
  its exact product, architecture, spike, or production-evidence blocker.
- `product-authority-crosswalk.json` maps every classification batch to its
  reviewed canonical-target, current-product, historical-evidence,
  decision-log, architecture, or conversion-control authorities.
- `product-authority-audit.generated.json` and `.md` prove that every stable
  surface resolves through its batch to an authority set and that all nine
  registered target specs remain represented. Generated artifacts must not be
  edited.
- `implementation-slices/*.json` contains one machine-readable dossier per
  active target slice. `_template.json` is ignored by validation and must be
  copied/renamed before use.
- `implementation-slice-audit.generated.json` and `.md` report slice ownership,
  requirements, verification obligations, blockers and surface coverage.
- `classification-batches/*.json` contains reviewable, bounded M0 decisions;
  `sync` applies them to the manifest without re-acknowledging later source
  changes.
- `scripts/supabase-conversion-ledger.mjs` discovers repository surfaces,
  merges them without discarding classifications, validates the ledger, and
  generates coverage. Discovery includes app/test source, rules, Functions,
  MCP, migration/repair tooling, and build/release/backend configuration; the
  manifest also carries cross-cutting surfaces that code scanning cannot prove.
- `scripts/generate-m2-residual-register.mjs` validates every residual blocker
  against the decision/architecture authorities and regenerates the grouped
  decision queue. Unknown blockers or stale generated output fail its check.

Product behavior remains authoritative in the canonical specs and decision log.
Architecture remains authoritative in `docs/architecture/redesign`. The
implementation tracker owns sequencing. This directory owns the answer to:
“Has every source surface been found, classified, mapped, implemented, tested,
rehearsed, and made ready for cutover?”

## Required Start/Resume Sequence

Before continuing conversion work, including immediately after context
compaction:

1. Read `AGENTS.md`.
2. Read the redesign program README and decision log.
3. Read this file and `execution-state.md`.
4. If target implementation is active, read
   `vertical-slice-implementation-method.md` and the entire active slice dossier.
5. Run `node scripts/supabase-conversion-ledger.mjs check`.
6. Inspect `git status --short` and preserve unrelated work.
7. Reconcile any partial diff with the active dossier; do not silently discard,
   reclassify, or claim it.
8. Resume only the `Next Action` recorded in `execution-state.md`, unless a new
   user instruction supersedes it.

## Checkpoint Rule

For every bounded work item:

1. identify the stable surface IDs being changed;
2. link the surface to its user or operational capability and document current
   behavior in a bounded classification batch;
3. complete or update the capability dossier: source evidence, governing specs,
   stale/contradictory spec concerns, and the explicit preserve/correct/improve/
   redesign/retire decision;
4. update the product-authority crosswalk when a batch's governing specs or
   authority roles change; canonical target specs and confirmed decisions must
   remain distinguishable from current or historical evidence;
5. map target ownership, schema/port/command/query, RLS, Sync Streams, migration,
   and verification before marking `target_mapped`;
6. before implementation, create/update the slice dossier with exact authority
   headings, invariants, contracts and verification obligations and make its
   `ready` gate pass;
7. implement and run applicable tests, advisors and reconciliation, attaching
   durable evidence before status advancement;
8. update the manifest and evidence index;
9. synchronize and validate the ledger; and
10. update `execution-state.md` with the next exact action before ending the turn.

No item becomes `verified`, `rehearsed`, or `cutover_ready` based on prose or a
successful compile alone.

## Commands

```bash
node scripts/supabase-conversion-ledger.mjs sync
node scripts/supabase-conversion-ledger.mjs check
node scripts/supabase-conversion-ledger.mjs report
node scripts/supabase-conversion-ledger.mjs gate M0
npm run conversion:queries:generate
npm run conversion:queries:check
npm run conversion:capabilities:generate
npm run conversion:capabilities:check
npm run conversion:residuals:generate
npm run conversion:residuals:check
npm run conversion:profiles:check-readonly
```

`sync` discovers new repository surfaces and preserves existing manual
classification fields, then applies reviewed classification batches. The first
application may acknowledge the exact current source hash; subsequent source
changes remain visible as drift. A previously discovered source that disappears
remains in the manifest and fails validation until its retirement is evidenced.

When a characterized source is deliberately changed, re-acknowledgment requires
an explicit `acknowledgeSourceHash` in exactly one reviewed classification batch;
the requested hash must equal the newly observed hash. `acknowledgeCurrentSource`
only acknowledges an automatic source the first time. Never edit a hash merely
to silence drift.

`check` validates structure, detects unrecorded surfaces and source drift, and
does not pretend that an incomplete milestone has passed. It also rejects a
missing/broken authority mapping, stale generated authority/slice audits, an
invalid slice dossier, or an implemented-or-later target surface without
exactly one correspondingly advanced slice.

`gate M0` through `gate M5` are cumulative and fail until that milestone and
every prerequisite milestone are satisfied.

The two production source profilers default to local preflight and refuse to
initialize Firebase without the exact reviewed project/account, an external
chmod-600 project-matching service-account key, the fixed gitignored artifact
directory, and an explicit read-only execution confirmation. See their `--help`
output and `evidence/EVID-PROFILER-001.md`. Never weaken those gates to make a
profile run convenient.

## Permanent Guardrails

- Do not implement the redesigned application in Firebase.
- Do not treat source mechanics, current bugs, or stale specs as parity
  requirements; resolve them through a capability dossier.
- Do not mutate production during discovery or rehearsal.
- Do not silently omit a source surface because it appears obsolete.
- Do not expose a target table without explicit grants, RLS, and Sync Stream
  review where applicable.
- Do not begin a target implementation slice until its machine-readable dossier
  passes the `ready` requirements in `vertical-slice-implementation-method.md`.
- Do not use user-editable Auth metadata for authorization.
- Do not put a service-role/secret key in the app.
- Do not mark a migrated record covered without source-to-target correlation or
  an approved omission/quarantine reason.
- Do not authorize cutover from percentage completion; every mandatory gate must
  pass.
- Do not merge target implementation while the required `Conversion state and
  traceability` pull-request check is absent or failing.
