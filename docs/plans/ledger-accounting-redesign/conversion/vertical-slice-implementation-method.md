# Vertical Slice Implementation Method

Status: required before any redesigned target surface advances beyond
`target_mapped`

## Purpose

This method turns an approved Ledger product slice into one traceable,
testable implementation across backend-neutral domain/application code,
Supabase Postgres, RLS, PowerSync, local reads, app and MCP entry points,
migration, reconciliation, observability and rollback.

It closes the gap between “the relevant specs were reviewed” and “the code is
proven to implement the exact approved behavior.” Conversation history, a broad
tracker row, compilation, or one happy-path test is never implementation proof.

Every active slice has one machine-readable dossier in
`implementation-slices/<slice-id>.json`. The conversion checker validates the
dossier and refuses status advancement when traceability or evidence is
missing.

## Authority and Precedence

For product behavior, precedence is:

1. canonical target specs;
2. confirmed entries in the redesign decision log;
3. the capability dossier's reviewed preserve/correct/improve/redesign/retire
   outcome; and
4. the target architecture for technical realization.

Current-product and historical specs may establish shipped behavior,
migration evidence, or regression fixtures. They cannot authorize redesigned
behavior. Architecture cannot settle an open product decision.

If sources disagree, stop the affected slice. Update the canonical spec and
decision log when authority is clear, or record a blocker. Never resolve the
conflict only in SQL, Swift, TypeScript, RLS, Sync rules, or tests.

Before a product slice becomes `ready`, perform a feature-specific authority
audit: every promised user-visible outcome must already appear in a canonical
target-spec heading or confirmed D decision. Batch-level association with broad
specs, current shipped behavior, an architecture interface, a capability
dossier, or a `target_mapped` manifest status does not establish that outcome.
Do not add new target-spec language during ready preparation merely to make a
candidate appear authorized; when the missing language represents a product
choice, record an O blocker/decision packet and select another slice.

## Unit of Delivery

A vertical slice is the smallest user-meaningful or operational outcome that
can be implemented and verified through all affected layers. Good examples are
“create a Project with authoritative Client identity,” “place an Inventory Item
in a Project and create open Item demand,” or “collect one whole Invoice.” A
table, view, SDK wrapper, screen, or migration script by itself is not a product
slice.

Each manifest surface has one primary implementation slice. Several source
surfaces may converge on the same slice. One slice may span several source
surfaces when they collectively deliver one outcome. Shared infrastructure is a
separate technical-control slice with explicit downstream contracts.

### Delivery batches

The traceability unit remains a slice, but the normal execution unit is a
delivery batch containing several tightly related slices that together produce
an end-user workflow. A batch should normally include the required schema,
trusted reads/commands, grants/RLS, PowerSync behavior, app/MCP entry points,
offline/restart proof, and reconciliation support for that workflow.

Do not create a separate implementation cycle for every two-file contract,
adapter, presenter, or read projection when those pieces can be reviewed and
verified safely as one feature batch. A smaller slice remains appropriate when
it resolves a reusable high-risk invariant, blocks several downstream paths, or
must be isolated to answer an architectural spike question.

Progress is reported primarily by complete locally working workflows, hosted
rehearsals, and cutover-ready workflows. Surface counts and planning coverage
remain audit controls; they are not substitutes for product completion.

Before executable work, the active batch must be durably recorded in a
machine-checked implementation-slice dossier (one umbrella user-workflow slice
is preferred when practical) with its exact base commit, dependent verified
slices, union change boundary, risk domains, requirement-to-test map, reviewers,
rollback boundary, and unresolved blockers. Normal batches contain one coherent
workflow and no more than four independently understandable sub-slices.

Do not combine two distinct high-risk authorities merely to save a CI cycle.
Auth/identity, financial accounting, destructive migration, Sync authorization,
and retention/deletion each require an explicit boundary and specialist review.
Every batch includes cross-slice tests for shared identity, authorization,
revision, readiness, operation ordering, and rollback behavior. Financial
batches additionally prove conservation, reconciliation, and concurrent
interleavings.

Parallel agents receive disjoint executable/test ownership. The integrating
agent alone edits ordered migrations, shared runtime composition, generated
projects, manifests, and status/evidence records. If a constituent slice fails
review or CI, the exact batch cannot be promoted; remove or correct it in a new
synchronized checkpoint and rerun the batch gate. Never reuse a failed exact
commit's evidence to promote neighboring work.

## Required Slice Dossier

Copy `_template.json` to a stable lower-kebab-case slice filename. Delete the
template comments by replacing every placeholder; do not weaken validation or
mark an obligation not applicable merely to pass the checker.

### Identity and ownership

- stable `sliceId`, title, kind, owner and lifecycle status;
- every stable conversion-manifest `surfaceId` primarily implemented by the
  slice; and
- every unresolved blocker that can still change behavior or architecture.

### Exact requirements

Each requirement records:

- a slice-stable requirement ID;
- an authority role;
- repository path and exact Markdown section heading;
- a concise invariant or observable story stated independently of
  implementation;
- applicable confirmed decision IDs; and
- the verification IDs that prove it.

The checker confirms that the file and heading exist, the authority is allowed
by the claimed surfaces' reviewed authority batches, decision IDs exist, and
every requirement is covered by a named verification obligation.

### Contract map

Every category below contains concrete items or a specific `notApplicable`
reason:

1. backend-neutral domain values, commands, queries and results;
2. Postgres tables, relationships, checks, uniqueness and indexes;
3. authoritative transactional handlers, locking, idempotency and stable
   rejection results;
4. Data API schema exposure and explicit grants;
5. RLS policies and authorization predicates;
6. PowerSync Sync Streams, local tables, visibility and readiness;
7. encrypted local state, optimistic/rejected state and restart behavior;
8. Storage/media policies and durable-byte behavior;
9. app and MCP entry points using the same command/query authority;
10. source transforms, target migrations and reconciliation;
11. metrics, alerts and runbook effects; and
12. rollout, feature-authority activation and rollback.

For exposed Supabase tables, Data API grants and RLS are separate obligations.
`authenticated` is never sufficient authorization by itself. Views, privileged
functions, Storage upserts, JWT claim freshness, session revocation and service
credentials receive explicit review where relevant.

### Verification map

Every verification obligation has a stable ID, test kind, executable owner,
covered requirement IDs, expected result, status and evidence references.
Required kinds are derived from the non-empty contract categories. Examples
include domain/property tests, database invariants/concurrency, handler
idempotency, positive and negative RLS matrices, Sync authorization/local-row
absence, offline restart and rejection, migration/reconciliation, app/MCP
contract parity, Supabase security/performance advisors and end-to-end stories.

A test name is a plan, not proof. `verified` requires every obligation to be
recorded as passed with durable evidence.

## Lifecycle and Gates

| Slice status | Meaning | Minimum gate |
|---|---|---|
| `draft` | Requirements or mapping are still incomplete | May contain blockers; no implementation status claim |
| `ready` | Exact authority, contracts and test obligations are complete | Claimed target surfaces are `target_mapped`; blockers empty |
| `in_progress` | Target implementation has started | Same gate as `ready`; dossier changes with the code |
| `implemented` | Required target code/DDL/config exists | Claimed target surfaces are `implemented`; implementation evidence recorded; tests may still be pending |
| `verified` | All required tests and advisors pass | Claimed target surfaces are `verified`; every verification has passing evidence |
| `rehearsed` | Required isolated staging, migration and physical offline/fault evidence passes | Claimed target surfaces are `rehearsed`; rehearsal evidence recorded |
| `cutover_ready` | Slice satisfies the approved coordinated cutover gate | Claimed surfaces are `cutover_ready`; never inferred from lower gates |

The checker also enforces the inverse: no target-relevant manifest surface may
advance to `implemented` or later without exactly one implementation slice that
has reached the corresponding status.

## Required Work Sequence

1. **Select the slice.** Identify stable manifest surfaces and owning capability
   dossier. Do not organize work around Firebase files or target tables.
2. **Freeze authority for the slice.** Independently confirm that the exact
   feature exists in pre-existing canonical target authority, then record its
   headings, invariants, confirmed decisions and blockers. An open or newly
   discovered mapping-changing decision keeps the slice `draft`.
3. **Complete the contract map.** Name domain/application contracts first, then
   schema/handlers/RLS/Sync/local/app-MCP/migration/operations. Record explicit
   non-applicability instead of silent omission.
4. **Define verification before implementation.** Give every invariant one or
   more executable verification IDs and include negative authorization,
   concurrency, offline/restart/rejection and reconciliation cases where the
   contracts require them.
5. **Move to `ready`.** Run `conversion:check`; review the dossier, SQL/RLS/Sync
   design and proposed tests. No code begins while this gate fails.
6. **Implement one authority.** App and MCP use the same domain commands and
   queries. Multi-row accounting changes occur in one authoritative target
   transaction. Do not implement redesigned behavior in Firebase.
7. **Verify locally and in isolated staging.** Before provider-specific work,
   check the current Supabase changelog/docs. Run migrations, database tests,
   positive/negative RLS tests, Sync/offline/fault tests, app/MCP parity,
   migration/reconciliation fixtures and relevant advisors.
8. **Attach evidence and advance statuses together.** Update the slice dossier,
   manifest entries, evidence index, generated audits and execution state in the
   same bounded checkpoint. A surface and its slice may not disagree.
9. **Rehearse and activate separately.** Staging rehearsal does not authorize
   production. Authority activation, source freeze, final import, rollback and
   monitoring remain coordinated program gates requiring explicit approval.

### Immutable-CI checkpoint sequencing

The conversion manifest records content hashes, so an executable-only commit
above synchronized classifications is knowingly traceability-red. Use this
sequence for each delivery batch:

1. prepare and review the authority, contract, verification and change-boundary
   records for every slice in the batch before implementing its behavior;
2. in one bounded implementation checkpoint, change only the reviewed batch
   surfaces and synchronize their hashes, dossiers, manifest, evidence,
   tracker and generated controls at honest `implemented` status;
3. run focused checks while developing, then pass the complete immutable
   workflow once on that exact implemented batch commit; and
4. record the green run and advance eligible surfaces to `verified` in the next
   natural control checkpoint. A dedicated promotion commit is optional unless
   release tooling, a reviewer, or a higher lifecycle gate requires it.

A separate comment-only READY commit and full CI run is reserved for high-risk
or independently deployable boundaries—especially new financial authority,
security/RLS, destructive migration, identity/Auth, Sync authorization, or a
spike whose result controls architecture. It is not required for every small
target-local adapter or presentation leaf. One independent review may cover the
whole batch; additional specialist review is required only for materially
different risk domains such as SQL/RLS and offline concurrency.

Do not push a known-red executable-only checkpoint merely to preserve a
two-leaf implementation diff. Prove that allowlist relative to the READY commit
inside the synchronized implementation checkpoint's evidence and review. If a
legacy executable-only checkpoint already exists, record its isolated-target
and traceability jobs separately, synchronize at honest `implemented` status,
require a complete green immutable run on that recovery checkpoint, and only
then promote. Never describe a partially failed workflow as passed.

## Change Control During Implementation

When a spec, confirmed decision, security model, Sync boundary, migration rule,
or acceptance invariant changes:

1. stop affected implementation;
2. update product authority first;
3. update the product-authority crosswalk and capability dossier;
4. update affected slice requirements/contracts/tests;
5. return the slice and affected surfaces to the earliest honest status;
6. regenerate/check all control artifacts; and
7. resume only after review.

Do not preserve a higher status because code already exists.

## Pull Request and Checkpoint Evidence

Every slice PR or bounded checkpoint includes:

- slice dossier diff and claimed surface IDs;
- canonical spec sections and decisions changed or confirmed;
- implementation/migration identifiers;
- exact commands used for tests, advisors and generated checks;
- passing/failing results and durable artifact links;
- known blockers and excluded scope;
- environment and production-isolation statement; and
- manifest/evidence/execution-state updates.

Required local control commands remain:

```bash
npm run conversion:check
npm run conversion:report
npm run conversion:gate:m0
npm run conversion:gate:m1
npm run conversion:gate:m2
```

Later gates remain expected to fail until their real prerequisites and slice
evidence exist. Never weaken a gate to make progress look complete.

## Reviewer Stop Conditions

Reject or pause a slice when any of these is true:

- requirement text lacks an exact product/architecture authority section;
- a current or historical spec is being used as target authority;
- an open decision was silently chosen in code;
- domain behavior exists only in a view, MCP tool, SQL trigger or adapter;
- app and MCP calculate or mutate the same concept independently;
- exposed tables lack explicit grants or RLS review;
- positive authorization tests exist without negative/cross-tenant tests;
- Sync tests inspect server results but not unauthorized local-row absence;
- offline acceptance is only an in-memory mock or successful reconnect;
- idempotency is asserted without lost-response/replay/concurrency cases;
- migration counts exist without relationship/amount/provenance reconciliation;
- a test is named but no executable owner or evidence exists;
- implementation status advances without a corresponding slice dossier; or
- production access, deployment or cutover is inferred from design evidence.

## Relationship to Existing Controls

- `capability-evolution-method.md` decides what outcome should change or remain.
- `target-mapping-method.md` assigns every source surface to target ownership.
- `product-authority-crosswalk.json` supplies the reviewed authority set.
- this method governs actual slice implementation and proof;
- `conversion-manifest.json` holds per-surface lifecycle status;
- `08-verification-observability-and-operations.md` defines system-wide tests,
  operations and vertical-slice done criteria; and
- the implementation tracker sequences slices and program gates.

None of these documents authorizes production migration by itself.
