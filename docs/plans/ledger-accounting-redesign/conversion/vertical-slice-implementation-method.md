# Workflow Implementation Method

Status: required for redesigned target implementation; method version 3

## Purpose

Implement Ledger as coherent user workflows while preserving the controls that
prevent accounting, authorization, offline, migration, and cutover mistakes.
The process must make the product easier to finish and understand. It must not
become a second product.

The normal unit of delivery is a user-visible workflow such as “create a
Project,” “browse and edit a Space,” or “collect an Invoice.” Internal types,
ports, SQL functions, adapters, and views are parts of that workflow, not
separate delivery units.

## Authority and Precedence

For product behavior, precedence is:

1. canonical target specs;
2. confirmed redesign decisions;
3. reviewed preserve/correct/improve/redesign/retire conclusions; and
4. target architecture for technical realization.

Current-product and historical specs may establish shipped behavior and
migration evidence. They do not authorize redesigned behavior. Architecture
does not settle an open product decision.

If these sources conflict or omit a choice that changes user-visible behavior,
schema, accounting, authorization, offline conflict resolution, or migration,
stop only the affected workflow and record the decision needed. Select another
unblocked workflow instead of inventing an answer.

## Non-Negotiable Engineering Boundaries

- The redesigned application has one target authority: Supabase Postgres plus
  PowerSync-backed local state. Do not implement redesigned behavior in
  Firebase.
- App and MCP entry points use the same domain commands and queries.
- Multi-row accounting changes are one authoritative database transaction.
- Tenant isolation requires explicit grants, RLS, and negative cross-tenant
  tests. `authenticated` alone is not authorization.
- Offline mutations require durable local acceptance, deterministic replay,
  idempotency, rejection handling, and restart proof.
- Migration requires source preservation and count, relationship, amount, and
  provenance reconciliation. Unknown evidence is quarantined, never guessed.
- Hosted resources, production access, source freeze, migration, release, and
  cutover require explicit user authorization.

## Unit of Delivery

### The One Active Workflow Record

`current-execution-state.json` is the compact resume pointer. It names the
active workflow and, after selection, its durable record under
`workflow-records/<workflow-id>.json`. The workflow record contains:

- the user outcome;
- whether it is a product UI, backend/control, or migration workflow;
- exact canonical spec/decision references;
- applicable risk domains;
- the source and target pages in the journey, every visible control and option,
  each resulting transition or operation, and loading/empty/error/offline states;
- exact behavior-level references into the current-product catalog—not merely a
  page, source file, or broad journey ID;
- exact story IDs from `target-product-story-catalog.json` for the redesigned
  outcomes the workflow fully implements; broad stories must not be claimed by
  a partial screen or technical layer;
- exact spec or decision-log headings that govern each UI journey;
- affected technical components, at component level rather than an exhaustive
  file allowlist;
- executable acceptance checks; and
- the next one to five actions.

Update the compact pointer when the active workflow or verified checkpoint
changes. Update the workflow record as behavior and verification become known;
keep it after completion so detailed UI and control-flow coverage is cumulative,
not overwritten by the next workflow. Do not create comment-only implementation
or test files, a separate readiness commit, per-component dossiers, evidence
essays, or promotion-only commits for an ordinary workflow.

The implementation tracker is the workflow backlog and program-level status
view. A completed row should say what works, what remains excluded, and identify
the implementation commit and CI run. It should not narrate every intermediate
type or control-plane transition.

The exhaustive code-surface catalog remains the coverage backstop. It currently
includes the discovered UI components and views as well as services, state,
queries, MCP tools, tests, and operational surfaces. Workflow planning groups
those detailed surfaces into a journey; it does not discard them. Before a
workflow is complete, its UI coverage must be checked against both the catalog
and the current app so every control, menu choice, sheet, navigation result,
disabled rule, and visible data state has an explicit preserve, redesign, or
retire outcome. That code inventory answers **where the implementation lives**.
The Product Behavior Catalog answers **what a person can see, choose, do, and
observe**. Neither substitutes for the other.

Risk domains use a fixed vocabulary, and every selected risk must have at least
one matching acceptance check in addition to the general end-to-end check. UI
controls record their label, result, and preserve/redesign/retire disposition;
the state checker derives minimum layers and risks from affected component paths
and from every target file changed since the verified checkpoint. A workflow
cannot declare itself low-risk while changing Postgres/RLS, PowerSync/offline,
accounting, authentication, media, deletion, migration, app UI, or MCP paths.
Human judgment may add risks; it may not remove the derived minimum.
free-form “tested” claims are insufficient.

A completed target workflow also records `implementationEvidence`: exact
repository files grouped by layer. Directory names, declared layer labels, and
test prose do not count. Every layer required by a claimed target story must
have a matching concrete file, and every required risk must have a passed check
whose `coversStoryIds` explicitly names that story. This prevents a UI-only
slice from claiming database, RLS, PowerSync, or offline completion by metadata.

### Product Behavior Catalog

The durable record
`workflow-records/current-app-ui-control-flow-baseline.json` is Ledger's Product
Behavior Catalog. It covers all 167 currently discovered Swift UI components
and views. The historical filename remains stable so links and CI evidence do
not churn; its role is not a code inventory or a one-time audit.

Its `sourceBaseline` records the reviewed Firebase branch and commit. Before a
product milestone can pass, the gate verifies the remote branch still matches
that revision. Later Firebase support changes require a fresh behavior review,
so the checklist cannot silently become stale while the existing app evolves.

For every page or shared component it records:

- its stable surface IDs and source/target page names;
- every visible control and every selectable option;
- what each interaction does and where it navigates;
- loading, empty, partial, error, disabled, offline, pending, and conflict states
  that apply; and
- whether the behavior is preserved, redesigned, or retired, with the governing
  spec or decision.

The catalog maintains explicit covered and uncovered source-surface sets. Its
completion gate requires their union to equal the manifest's complete UI set,
with no duplicates and no uncovered IDs. Later product workflows reference the
exact catalog controls, options, transitions, and states they implement—not just
the containing journey—and may add newly discovered details. The state checker
derives a concise claimed/verified behavior count from those references. A
workflow can therefore implement one control on a large page without pretending
the entire page is complete. This is the durable answer to “did we reproduce
what the app does?”; file-level surface discovery alone is not sufficient.

Before cutover readiness, every catalog behavior must be accounted for by a
completed target workflow as preserved, deliberately redesigned, or explicitly
retired. Open or deferred behavior remains visibly unverified rather than being
hidden inside a page-level completion claim.

### Target Product Story Catalog

`target-product-story-catalog.json` is the complementary checklist for behavior
introduced or materially changed by the redesign specs. The Product Behavior
Catalog answers “did we preserve, redesign, or retire everything people can do
today?” The target story catalog answers “did we build every outcome required by
the new specs?” The code-surface catalog answers only where relevant code lives.

Each target story names one canonical spec heading, its milestone, and whether
it is required, blocked by named open decisions, or retired by confirmed
authority. A product workflow lists only the story IDs it completely exercises.
At least one passed acceptance check must explicitly cover every story claimed
by a completed workflow. A partial implementation may cite the governing spec
without claiming its broader story complete.

The catalog also contains three machine-checked ledgers:

- `authorityCoverage` accounts for every spec indexed by `docs/specs/README.md`
  as audited, partial, or an explicitly allowlisted source-only artifact. Every
  entry is pinned to the SHA-256 of the reviewed source. An `audited` entry must
  disposition every current Markdown heading exactly once and map each claimed
  story through that heading inventory;
- `decisionCoverage` accounts for every ID in the exact Confirmed and Open
  Product Decisions sections as mapped or pending. A mapped open decision can
  point only to a blocked story that names that exact decision, and the reverse
  link is required once the decision audit is mapped. The whole decision log is
  content-hashed, so changed meaning under an unchanged ID invalidates the
  audit;
- `deliveryRequirements` assigns every story one required workflow kind plus
  the minimum layers and risk proofs that must be concretely evidenced in its
  completed workflow. A migration record therefore cannot satisfy a UI story
  merely by citing its ID.

The catalog remains `partial` until every canonical redesign spec and decision
has been audited into stable stories. M3, M4, and M5 must fail while it is
partial; changing that status requires an exhaustive authority audit, not an
estimate or a surface count.

## When a Separate Design Note Is Worth It

A short design note is required only when a workflow introduces or materially
changes one of these boundaries:

- financial conservation or accounting authority;
- authentication, identity, tenant authorization, or RLS policy structure;
- Sync Stream visibility or offline conflict/rejection policy;
- destructive migration, retention, or deletion;
- a shared architectural dependency whose result controls several workflows.

The note answers the unresolved design question, records the chosen invariant,
and names the tests. It is not a second tracker. Existing
`implementation-slices/*.json` and `evidence/*.md` files remain historical audit
records; new workflows do not need new files in those directories.

## Required Slice Dossier

This heading is retained so historical dossiers can continue to validate their
original authority references. Method v3 replaces the required per-slice
dossier with the single active workflow record above. Existing dossiers remain
immutable audit history; do not create new ones for ordinary workflow delivery.

## Required Work Sequence

1. **Choose an unblocked workflow.** Prefer the next user-meaningful path, not a
   two-file abstraction or a source file family.
2. **Check authority.** Read only the relevant target-spec sections and confirmed
   decisions. Put their paths and headings in `activeWorkflow.authority`.
3. **Write acceptance checks.** Cite the exact current behavior elements in
   `baselineBehaviorRefs` and the fully implemented redesigned outcomes in
   `targetStoryIds`, then state the happy path and the applicable negative,
   offline, replay, security, accounting, and reconciliation cases in concise
   testable language. Record the page-by-page UI journey, including controls,
   options, transitions, loading/empty/error/offline states and accessibility.
4. **Implement through the affected layers.** Keep business rules in shared
   domain/application code and authoritative transactions, with thin UI, MCP,
   and provider adapters.
5. **Test while building.** Run focused tests that can quickly falsify the work.
6. **Review by risk.** The integrating agent reviews the complete diff. Request
   an independent specialist review when a high-risk boundary above changes or
   for the first implementations delegated to a new subagent.
7. **Verify once.** Run the complete applicable local workflow gate on the
   integrated change, then use the pull-request CI run on that exact commit.
   Do not manually dispatch a duplicate run for the same commit.
8. **Record the result.** Update the tracker and current state with the commit,
   CI run, what now works, and honest exclusions. Keep the completed workflow
   record and link it from the tracker before continuing.

Do not split these steps into separate status commits unless a high-risk design
decision genuinely needs approval before executable work.

## Test Obligations by Risk

Every workflow needs domain/application tests and at least one end-to-end path
through its implemented layers. Add the following only when applicable:

| Changed boundary | Required proof |
|---|---|
| Postgres schema or handler | constraints, transactionality, concurrency, idempotency |
| Grants or RLS | allowed matrix plus denied cross-tenant and unauthenticated cases |
| PowerSync/local mutation | offline acceptance, encrypted restart, replay, rejection, authoritative readback |
| Sync visibility | allowed rows plus absence of unauthorized local rows and revocation behavior |
| Accounting | conservation, rounding, concurrent interleavings, reconciliation |
| Media | durable-byte lifecycle, retry, orphan/reference and retention behavior |
| Migration | deterministic transform, quarantine, counts, relationships, money, provenance, resumability |
| App and MCP | both invoke the same typed authority and return compatible results |
| UI journey | every specifically claimed catalog control/option/transition/state is preserved, deliberately redesigned, or explicitly retired; interaction and accessibility tests cover the target result; unclaimed behavior remains visibly outstanding |

Compilation or a named test plan is not proof. A workflow is verified only when
the applicable executable checks pass.

## Status Meanings

| Status | Meaning |
|---|---|
| `planning` | Authority and acceptance checks are being confirmed |
| `implementation` | Executable target work is in progress |
| `review` | The integrated diff is being checked for correctness and scope |
| `local_verification` | The complete applicable local gate is running or being corrected |
| `ci_verification` | Exact-commit CI is running or being corrected |
| `blocked` | A named decision, permission, or external dependency prevents this workflow |
| `complete` | Applicable local checks and exact-commit CI passed |

“Complete” here means complete for the workflow’s stated scope. It does not mean
hosted rehearsal, migration, or cutover is authorized.

## Passive Completeness Controls

The 1,019-surface conversion catalog—including 112 discovered Swift UI
components and 55 Swift views—target-query inventory, logical-authority
crosswalk, source-query reconciliation, and historical slice audit remain useful
for detecting omissions. They are passive audit tools, not the unit of work and
not a reason to create scaffolds or status-promotion commits.

Run focused checks during implementation. Run `npm run conversion:check` and
the complete relevant target tests at the integrated workflow boundary. Run the
whole-catalog M0/M1/M2 gates when their inputs change and before migration or
cutover readiness; do not repeatedly promote individual source surfaces merely
to report feature progress.

The conversion checker may validate historical dossiers, but a newly
implemented target surface does not require a new dossier. Product completion
is measured by working workflows, not mapped or promoted surface counts.

M3 remains the complete target-implementation gate, M4 remains migration and
rehearsal proof, and M5 remains explicit cutover readiness. Method v3 changes
delivery bookkeeping only; it does not weaken or remove M3, M4, M5, hosted
authentication/Sync evidence, rollback, or explicit cutover authorization.
For M3 and later, the gate is composite: all required conversion controls must
pass, the target story catalog must be exhaustively audited, every cumulative
target story through that milestone must be covered by a passed completed
workflow or authority-retired, and all 1,919 current-product behavior
obligations must be covered by passed completed workflows. Surface promotion by
itself can never satisfy M3, M4, or M5.
At the product gate, the non-status workflow evidence payload must also match
the record stored at its exact CI commit, including passed acceptance checks,
local commands, specialist review, and concrete layer files. The gate queries
the recorded GitHub Actions run and requires that it succeeded on that commit
through `.github/workflows/supabase-conversion-control.yml`; a positive integer
typed into a record is not CI evidence. Adding or changing a story, behavior,
test result, review, or implementation-file reference after that run requires another CI
verification. The authoritative baseline is fixed to its reviewed identity and
91-journey/1,919-behavior threshold, so a thinner second audit cannot silently
replace it.

## Context Continuity

After context compaction or handoff:

1. read `current-execution-state.json`;
2. inspect Git status and the diff since its verified checkpoint;
3. run `npm run conversion:state:check`;
4. read only the authority sections named for the active workflow; and
5. continue its next action.

Conversation history, the large conversion README, generated catalogs, old
dossiers, and execution history are reference material. Load them only when a
specific discrepancy requires them.

## Pull Request and Checkpoint Evidence

For a normal workflow, the active workflow record and implementation-tracker row
record the exact commit, automatic pull-request CI run, applicable test results,
review outcome, blockers, and excluded scope. Store separate durable artifacts
only when a security, accounting, offline, or migration claim needs structured
evidence that cannot be recovered from executable tests and CI output.

## Reviewer Stop Conditions

Stop the affected workflow if:

- target behavior lacks canonical product authority;
- an open product decision was silently chosen;
- app, MCP, and database layers implement competing business rules;
- a tenant-visible table lacks explicit authorization and negative tests;
- offline success exists only in memory or only on a successful reconnect;
- idempotency lacks lost-response/replay or concurrency proof;
- accounting changes lack conservation and reconciliation proof;
- migration invents meaning for ambiguous source evidence; or
- production, hosted, migration, or cutover activity would exceed current
  authorization.

Do not stop an otherwise sound workflow because a comment-only scaffold,
per-surface promotion, dossier field, or standalone evidence narrative is
missing.
