# Supabase Conversion Control Plane

Status: M0 inventory classification complete; 325 of 489 target-relevant
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
ready, with exactly two comment-only target surfaces and no executable behavior
yet.

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
  surface resolves through its batch to an authority set and that all five new
  target specs remain represented. Generated artifacts must not be edited.
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
