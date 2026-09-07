# Workflow Implementation Method

Status: required for redesigned target implementation; method version 4

## Purpose

Finish Ledger by implementing coherent user workflows, with one checklist that
answers both “did we preserve what the app does?” and “did we implement the
redesign correctly?” The method exists to protect product fidelity and the
high-risk boundaries; it must not become a second product or an implementation
project of its own.

## Authority and Precedence

Product authority remains, in order:

1. canonical target specs;
2. confirmed redesign decisions;
3. reviewed preserve/correct/improve/redesign/retire dispositions; and
4. target architecture for technical realization.

Current-product material establishes shipped behavior and migration evidence.
Architecture and proposed decision packets do not settle open product choices.
When authority is missing or conflicting, block only the affected outcome and
continue another unblocked audit or implementation task.

## Non-Negotiable Engineering Boundaries

- Supabase Postgres is target authority; PowerSync provides authorized local
  state. Do not implement redesigned behavior in Firebase.
- App and MCP use the same typed domain commands and queries.
- Multi-row accounting changes are atomic and conserve exact amounts.
- Grants, RLS, and PowerSync visibility require allowed and denied tenant tests.
- Offline writes require durable local acceptance, restart, replay, idempotency,
  rejection, cancellation/drainage, and authoritative-readback proof.
- Media requires protected durable bytes, scoped identity, retry, verification,
  reference/orphan handling, and explicit retention/deletion behavior.
- Migration preserves source evidence and reconciles counts, relationships,
  amounts, provenance, quarantine, retries, and resumability.
- Production/hosted access, source freeze, migration, release, and cutover need
  explicit user authorization. Do not touch the Firebase checkout.

## Unit of Delivery

One user-meaningful workflow is the implementation unit. UI, app model, MCP,
domain, Postgres/RLS, PowerSync/offline, media, and migration pieces are layers
of that workflow, not separately promoted accomplishments. Reuse working code
and add an abstraction only when a concrete shared problem justifies it.

### The One Active Workflow Record

`docs/plans/ledger-accounting-redesign/conversion/product-behavior-checklist.json`
(called the unified checklist below) is the single active audit, workflow, and
completion ledger. For each current or target outcome it directly records:

- current controls, selectable options, transitions, disabled rules, and
  loading/empty/error/offline/pending/conflict states;
- background, lifecycle, operational, and MCP behavior;
- preserve, correct, improve, redesign, retire, or unresolved disposition;
- exact governing spec/decision authority and affected open decisions;
- its delivery profile and required technical layers/risk proofs;
- review gaps and the finite audit area that still owns them; and
- workflow acceptance plus concrete implementation, test, review, commit, and
  CI evidence.

Do not duplicate these facts in another tracker. A workflow claims only the
outcomes it completely exercises; a partial screen or technical layer cannot
claim a broad outcome.

`current-execution-state.json` is only the compact resume pointer. Keep the exact
checkpoint, active workflow, next actions, blockers, and exclusions there. It
does not own behavior, authority, acceptance criteria, or evidence history.

### Product Behavior Catalog

This compatibility heading remains for historical links. Method v4 folds the
former current-app Product Behavior Catalog into
`product-behavior-checklist.json`. The old workflow-record baseline remains
immutable historical evidence and is not updated in parallel.

### Target Product Story Catalog

This compatibility heading remains for historical links. Method v4 folds the
former target story, authority-coverage, decision-coverage, and delivery-profile
ledgers into direct fields on `product-behavior-checklist.json`. The old target
catalog remains historical evidence and is not synchronized.

## Audit Completion

The product audit is finite and complete when:

1. every inventoried UI surface and every background/MCP surface has been
   reviewed;
2. every redesign spec and decision area has been reviewed;
3. every known behavior has an explicit disposition; and
4. every unresolved product decision is linked to each affected outcome.

An unresolved decision does not prevent audit completion. It blocks only the
affected implementation outcomes. Audit completion also does not require a
premature command, table, schema, RLS, Sync rule, or test design for every
Markdown heading. Design those details when the approved workflow needs them.

Source inventory remains a passive omission check: newly discovered source UI,
background, or MCP behavior must enter the unified checklist before the audit
can stay complete. It is not an implementation queue or progress metric.

The background/MCP area closes only when its `capabilityDispositions` account
for the finite product-source scope and bind it to the reviewed source digest
and Firebase baseline. Group related source IDs under shared outcomes; do not
create a story or dossier per file. `--audit-sources` lists source kinds/counts;
`--audit-sources KIND` lists the exact references for a chosen kind. The scope is
derived from the existing inventory, not maintained as another registry.

## When a Separate Design Note Is Worth It

Use a short design note only for a genuinely new or materially changed boundary:
accounting conservation, identity/authorization/RLS, Sync visibility or offline
conflict/rejection, destructive retention/migration, or a shared dependency
controlling several workflows. The note records the invariant and tests; it is
not another tracker or schema.

## Required Slice Dossier

Compatibility anchor for historical records: method v4 requires no new slice
dossier. Existing dossiers and their exact Git/CI evidence remain historical and
must not be rewritten, synchronized, or replaced.

## Required Work Sequence

1. Resume from `current-execution-state.json`, `git status`, and the current
   diff; read only the active checklist outcome and its named authority.
2. If auditing, finish the bounded inventory/spec/decision area, record every
   behavior disposition and gap, and link unresolved choices without designing
   premature technical detail.
3. If implementing, choose an approved user workflow and write concise,
   executable acceptance checks for every claimed behavior and applicable risk.
4. Implement the workflow through its required layers with shared domain
   authority and thin UI/MCP/provider adapters.
5. Run focused falsification tests while working; review the integrated diff and
   obtain specialist review for changed high-risk boundaries or early delegated
   implementations.
6. At the integrated boundary, run `npm run conversion:check` and the applicable
   full local test set once. Use the automatic pull-request CI run for the exact
   commit; never manually dispatch duplicate CI for that commit.
7. Record concrete file/test/review/commit/CI evidence in the unified checklist,
   update the compact resume pointer, and continue.

Do not create comment-only scaffolds, new dossiers, standalone evidence essays,
READY commits, promotion-only commits, or a new management schema for ordinary
work.

## Test Obligations by Risk

Every implemented workflow needs domain/application proof and an end-to-end path
through the layers it claims. Additional proof is mandatory when applicable:

| Boundary | Required evidence |
|---|---|
| Postgres or authoritative handler | constraints, atomicity, concurrency, idempotency |
| Grants/RLS/Sync visibility | allowed cases, unauthenticated/cross-tenant denial, revocation/no local leak |
| PowerSync/offline mutation | durable acceptance, encrypted restart, replay, rejection, cancellation/drainage, readback |
| Accounting | conservation, signs, rounding, interleavings, reconciliation |
| Media/deletion | byte durability, upload retry/verification, references/orphans, retention/recovery |
| Migration | deterministic transform, quarantine, counts, relationships, money, provenance, resumability |
| App and MCP | same typed authority, compatible results, equivalent authorization |
| UI | every claimed control/option/transition/state plus interaction and accessibility |

Compilation, prose, labels, or locally edited CI metadata are not proof. Evidence
must name concrete implementation files and passed outcome-specific checks for
every required layer and risk.

## Status Meanings

Use the unified checklist's validated status vocabulary rather than defining a
second status system here. A blocked outcome names its affected decision or
resource. A complete implementation has applicable local checks and exact-commit
CI; it does not authorize migration or cutover.

## Passive Completeness Controls

Historical target catalogs, workflow records, implementation trackers,
code-surface classifications, crosswalks, query inventories, dossiers, and
generated audits remain evidence at their recorded commits. Do not synchronize
them with the unified checklist, promote individual surfaces, or use their stages
as product gates.

`npm run conversion:check` validates the unified checklist and runs the passive
source-omission check. M3-M5 are cumulative product gates:

- M3: finite product audit complete and every required target behavior through
  M3 implemented, reviewed, and verified or explicitly retired by authority;
- M4: M3 plus deterministic migration and isolated rehearsal evidence; and
- M5: M4 plus explicit production cutover readiness and authorization.

Open product decisions may coexist with a completed audit, but their affected
outcomes cannot count as implemented. Code-surface mapping, classification, or
historical stage promotion never satisfies M3-M5.

Preserve immutable historical CI evidence. New or changed completion evidence
must bind to the exact implementation commit and successful automatic CI run.

## Context Continuity

After start, handoff, or compaction:

1. read `current-execution-state.json`;
2. inspect `git status` and the diff from its checkpoint;
3. read the active entries in `product-behavior-checklist.json` and only their
   named authority; and
4. continue the next recorded action.

Conversation history and historical conversion artifacts are optional reference
material. Load them only to resolve a concrete discrepancy; do not run the full
suite merely to recover context.

Use `node scripts/ledger-product-checklist.mjs --audit` for the remaining audit
areas, `--outcome ID` or `--workflow ID` for the named entry, and `--summary` for
counts. These are read-only views of the checklist, not additional records to
maintain. Do not load the entire checklist just to recover the next action.

## Pull Request and Checkpoint Evidence

Compatibility anchor for historical records: preserve their exact commit, CI
run, and evidence payload. New work records that evidence only in
`product-behavior-checklist.json`; the compact resume pointer names the active
checkpoint but does not duplicate the payload.

## Reviewer Stop Conditions

Stop only the affected implementation when product authority is absent, an open
decision was silently chosen, layers disagree on business rules, authorization
or offline/replay proof is missing, accounting does not conserve, migration
guesses ambiguous evidence, or an action exceeds production authorization.

Do not stop an otherwise sound audit or workflow because a historical dossier,
per-surface promotion, generated audit, or standalone evidence narrative was not
updated.
