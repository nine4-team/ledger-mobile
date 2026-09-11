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

### Reuse boundary

Preserve existing UI and backend-independent utilities by default. Replace or
extract their Firebase dependencies through target interfaces within the Supabase
worktree; this does not authorize a Firebase adapter or changes to its checkout.
The approved implementation plan must resolve known reuse/adaptation choices and
identify justified replacement exceptions up front, using existing workflow
records and architecture decisions rather than a new registry. A product-behavior
checklist entry is not an instruction to reimplement its existing component.
Approved redesigned behavior permits its required changes, not unrelated wholesale
replacement. Separate target builds, new data loading, and passing replacement
tests do not themselves justify rebuilding presentation or pure utilities.

If implementation reveals an unplanned replacement, pause only that replacement.
Explain the specific obstacle, the reuse/adaptation alternative, and the proposed
exception to the user; obtain approval and update the existing plan/decision before
proceeding. Continue independent authorized work. Follow already-resolved choices
without repeating the investigation for every task. This boundary neither approves
existing duplicate implementations nor authorizes their deletion or rollback.

### Workflow boundary

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

`activeWorkflow.baseCommit` identifies the exact start of the current batch;
keep it fixed until that batch ends. `verifiedCheckpoint` independently records
the last fully verified commit and must not advance without its evidence.
Current file-ownership checks compare against the batch base, not all work since
the last green run. Starting a new batch does not waive unfinished verification
or authorize declaring earlier work complete. The active outcome must match the
checklist record so the resume pointer cannot silently redefine its scope.

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
   Review the changed outcome, acceptance checks, and exclusions together when
   checks are added and at batch closure. A navigation shell is not the owner of
   every feature reached through it. Move unrelated checks to their owning
   record; an intentional scope change must reconcile all three fields. This is
   part of the existing diff review, not a new approval document. Machine checks
   enforce the batch base and outcome agreement, not semantic truth of prose.
   Check new counterparts to existing UI/utilities against the plan's approved
   replacement exceptions. Flag unapproved departures before accepting the batch;
   do not turn this diff check into another per-task reuse audit.
6. At the integrated boundary, run `npm run conversion:check` and obtain the
   applicable broader verification. Use normal exact-commit CI for its required
   broad suites; do not automatically run the same broad suites locally first.
   A broad local run needs a concrete reason, such as unavailable CI, a local-only
   risk, or diagnosing a native failure. Never manually dispatch duplicate CI
   merely to obtain another green result.
   Follow "Quiet CI waiting" below while long-running verification executes.
7. Record concrete file/test/review/commit/CI evidence in the unified checklist,
   update the compact resume pointer, and continue.

Do not create comment-only scaffolds, new dossiers, standalone evidence essays,
READY commits, promotion-only commits, or a new management schema for ordinary
work.

### Verification execution

These are command entry points, not a per-feature test-selection registry. Select
tests from the changed behavior and its consumers; do not re-inventory the test
system for each batch. Existing suites do not establish coverage of untested
behavior. Add missing tests when implementing that behavior.

- During development, use focused local unit/model checks for calculations and
  state changes, and integration checks for affected database, authorization,
  sync, replay and durability boundaries. Fast tests do not replace risk evidence.
- Run targeted UI scenarios when rendering, interaction, navigation or the
  UI-to-data integration changes. Include affected consumers of shared components
  and relevant platforms, not only screens whose files changed. Logic-only work
  does not by itself require UI automation.
- Broaden regression when impact cannot be bounded confidently, at integrated
  checkpoints, and for release readiness. Do not postpone all UI verification
  until release. The existing CI workflow currently runs both platform UI suites;
  this guidance does not disable those jobs or waive any required gate.
- After failure, diagnose the relevant output and verify a fix narrowly before
  broader verification. Do not rerun unchanged passing suites during each edit or
  retry until green. A retry for a suspected flake needs a stated diagnostic reason;
  preserve the failure. Confirm a narrowed run actually executed matching tests.

Commands below run from the Supabase worktree unless noted. Substitute an existing
suite/test/file name for placeholders; no production credentials or Firebase app
launches. Do not use `--skip-build` after source changes.
For the PowerSync service parser/environment checks use Node 24.14.0, matching
native CI. The current default shell Node 20 cannot parse that dependency. If the
shell has the older runtime, invoke the existing command through
`npx --yes --package=node@24.14.0 node ...`; do not treat a runtime syntax error as
a product failure or repeatedly retry with the same incompatible runtime.

| Need | Existing command / entry point |
|---|---|
| Focused native unit/model/provider test | `swift test --package-path LedgeriOS --no-parallel --filter '<SuiteName>[/<testName>]'` (for example `TargetEnvironmentManifestTests`). Tests live in the package's `LedgerTarget*Tests` directories. |
| Full native package, when warranted | `swift test --package-path LedgeriOS --no-parallel`. Preserve serial suite execution for native database lifetime safety; CI uses `scripts/run-target-native-tests-with-diagnostics.sh` around this command for stall evidence. |
| Focused script test | `node --test scripts/tests/<file>.test.mjs`; use an existing file. |
| MCP | `npm run target:mcp:test` for the suite; from `LedgerTargetMCP/`, `./node_modules/.bin/tsx --test tests/<file>.test.ts` for one existing file. |
| Local SQL / provider integration | `npm run target:supabase:test:db` for SQL tests; narrow with `npx --yes supabase@2.116.0 test db --local supabase/tests/<file>.test.sql`. Existing narrower provider commands include `npm run target:supabase:test:project-note-read` and `npm run target:supabase:test:space-assignment-destination-read`; see `package.json` and the affected `scripts/test-local-*.mjs`. These require the isolated local stack and may seed/mutate local fixtures; inspect prerequisites, never substitute hosted endpoints. |
| Target UI | Use the focused `xcodebuild` command below. The existing `npm run target:staging:ui:test:macos` runs the entire UI class, not a single scenario. |
| Conversion continuity | `npm run conversion:check`; not a substitute for behavioral tests. |

Focused macOS UI template (replace `<testMethod>` with an existing method in
`LedgeriOS/LedgerTargetStagingUITests/WorkspaceChecklistUITests.swift`):

```sh
TEST_RUNNER_LEDGER_ISOLATED_CI_CLIPBOARD=true xcodebuild \
  -project LedgeriOS/LedgerTarget.xcodeproj -scheme LedgerTargetStaging \
  -configuration Debug -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- -parallel-testing-enabled NO \
  '-only-testing:LedgerTargetStagingUITests/WorkspaceChecklistUITests/<testMethod>' test
```

For iOS, select an available supported simulator using `xcrun simctl list devices
available`, replace the destination with `platform=iOS Simulator,id=<UDID>`, use
`CODE_SIGNING_ALLOWED=NO`, and omit `CODE_SIGN_IDENTITY=-`. Keep the single-method
selector (repeat it for multiple affected scenarios); do not also pass the broad
class selector. Use a fresh `-resultBundlePath` when native evidence is needed.
If the target project is absent or its project spec changed, generate it using
`npm run target:project:generate`; ordinary source edits do not require regeneration.
Use the isolated `LedgerTargetStaging` scheme, never the production launch workflow.

### Quiet CI waiting

Keep all required tests; change how the agent waits, not what verification proves.

1. Start the selected test command or normal exact-commit CI once. Save the
   command/session or run URL, revision (including dirty-work caveats), CI attempt,
   result location, and next action in the existing resume pointer when yielding.
   Include a follow-up identifier only if one actually exists. Reuse that record
   after compaction; do not create duplicate runs, watchers, or monitoring ledgers.
2. Prefer existing process completion/wait tools or a verified completion callback.
   Local command exit supplies completion and exit status; retain its session
   instead of starting another test. For CI, the installed CLI supports
   `gh run watch <run-id> --compact --interval 60 --exit-status`: its polling does
   not require model turns. Keep repetitive watcher output out of model context.
   On completion, summarize the exact attempt with
   `gh run view <run-id> --attempt <n> --json headSha,attempt,status,conclusion,jobs`;
   inspect failed-job logs only as needed. `watch` follows the current run, so
   verify its attempt before treating it as the saved attempt's evidence.
   A CLI watcher alone does NOT guarantee the agent resumes after ending a turn.
   Confirm the available notification/wake-up path before relying on it. If a
   scheduled return is the only available path, base it on the selected suite's
   recent elapsed time, including build/queue time; never default to an hour for
   a minutes-long run. With no runtime evidence, make one early status check and
   adjust from actual progress. Respect tool wait limits; do not build a new
   monitoring service or claim automatic notification without verifying it.
3. Continue useful, already-authorized independent work if available. When only
   waiting remains, end the active turn. Do not replace waiting with minute-by-
   minute model polling, repetitive commentary, log reads, or unrelated audits.
   A non-AI watcher may poll internally. Short focused tests may return directly;
   active diagnosis of an observed failure is not unchanged-status polling.
4. On return, read status once for the saved attempt/session. If still running,
   adjust any scheduled return to remaining work rather than blindly repeating
   an interval. Investigate a concrete stall or
   timeout, not ordinary unchanged state. On completion, review required job and
   test summaries, then detailed logs only for failures or missing evidence.
   Save concise results and the next action, not full logs or another report.
   Do not reread historical output or rerun completed checks just to recover context.
   Record failures under their existing workflow; do not rerun until green or
   mistake an earlier successful attempt for the current result.
5. Pause/remove that follow-up on completion, cancellation, supersession, or an
   access blocker; retain the normal evidence and next action. Quiet waiting
   never waives review or permits promotion of a failing batch.

This is the default operating rule, not a claim that a machine check can enforce
agent waiting behavior. The September 11 trial demonstrated zero polling during
idle time; its cost estimate was not a controlled whole-batch or subscription
savings measurement. Do not add routine token audits to normal feature work.

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
