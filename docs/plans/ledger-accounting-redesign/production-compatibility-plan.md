# Ledger Accounting Redesign — Production Compatibility and Rollout Plan

Status: Firebase baseline prepared; isolated redesign implementation in progress; no redesign deployment authorized
Created: 2026-08-31
Last updated: 2026-09-01
Program: [Ledger Accounting Redesign](README.md)
Pre-cutover validation: [Isolated Testing Plan](pre-cutover-testing-plan.md)

Architecture note: the [Redesign Architecture Foundation](../../architecture/redesign/README.md)
defines Supabase + PowerSync as the target and Firebase only as the legacy
production system and migration source. The redesigned app does not implement
Firebase repositories, Firebase versions of target commands, or a bridge
release. Firebase-specific work below is operational cutover work only.

## Objective

Develop, commit, and test the redesign without changing the behavior or data
contract used by the current production app. A pre-update user must be able to
keep creating, editing, invoicing, collecting, and reviewing current records
until Ledger deliberately activates the new accounting authority.

This plan treats three operations as different things:

1. **Commit or push source code** — affects Git history, not production data by
   itself.
2. **Provision and test the isolated target** — may create non-production
   Supabase/PowerSync environments and release candidates, but does not change
   the running Firebase app or deploy v2 behavior to Firebase.
3. **Activate the redesign** — permits new record shapes and accounting
   semantics. This is a coordinated cutover, not an ordinary deploy.

No feature branch, app build, MCP deployment, Cloud Function deployment, rule
deployment, migration, or authority switch is implied by this document.

## Repository and Branch Baseline

Current authority after the coordinated baseline preparation and branch rename:

- local/remote `firebase` and local/remote `main` resolve to
  `fe018501d67cc84b6f140b2645b8a8149ea5c4f6`;
- GitHub's default branch and `origin/HEAD` are `firebase`; remote `dev` is
  absent;
- the Firebase checkout is clean at
  `/Users/benjaminmackenzie/Dev/ledger_mobile` and must remain unchanged by
  redesign implementation;
- the redesign runs only in the dedicated
  `codex/supabase-powersync-implementation` branch/worktree; and
- the complete preparation evidence is
  [git-baseline-preparation-2026-09-01.md](git-baseline-preparation-2026-09-01.md).

The following bullets are the historical read-only audit snapshot from
2026-08-31; they explain the starting state and are not current branch guidance:

- the checked-out branch is local `dev` at `93095593`;
- local `dev` is one commit behind `origin/dev`;
- `origin/dev` is `cd4c7c86`, the Sparkle build 82 publication commit;
- `origin/main` is `48cd1dd6`;
- `origin/main` is an ancestor of `origin/dev`, with `origin/dev` 220 commits
  ahead and no commits unique to `origin/main`;
- the remote's configured HEAD is `dev`, not `main`;
- no branch named `prod` exists in the fetched branch set; and
- Firebase's default configured project is `ledger-nine4`, and the MCP defaults
  to that production Firestore project when no override is supplied; and
- the current worktree contains many modified and untracked app, MCP, script,
  plan, and spec files from overlapping work.

Current consequences:

- Do not run redesign implementation, branch/ref operations, or releases from
  the clean Firebase checkout.
- Do not treat a backend command as a harmless development deploy. The repository
  defaults point at production unless deliberately overridden.
- A commit or push on the redesign branch does not deploy the app, MCP,
  Functions, rules, or a data migration and does not authorize any such action.
- The current source baseline is already established. Any later Firebase release
  is managed independently on `firebase`; it must not absorb target redesign
  files or behavior.
- Any unrelated release of the current app is managed separately. The redesign
  requires a recorded source baseline, not an intermediate Firebase release.

## Audited Current-System Assumptions

The compatibility decisions below are grounded in the current repository:

- Swift Firestore list/listener reads use a tolerant document wrapper that logs
  decode errors and drops undecodable documents from the returned collection.
  This prevents a process crash but can silently hide a Transaction or Invoice.
- Swift string enums throw on unknown values. `TransactionType` has no
  `transfer`; `InvoiceLineSourceType` accepts only `item`, `transaction`,
  `feeInstallment`, and `manual`.
- Swift `Item` and `Project` decoders ignore unknown additive fields, but that
  does not make new semantics safe for old calculations or mutations.
- Swift `ItemsService` already permits a project Item with a real category and
  `transactionId == null`. The app exposes a **No Transaction** correction
  state and can later attach the Item.
- The MCP `create_item` and `bulk_create_items` paths reject a project Item
  without a Transaction, despite the Swift service allowing it.
- Current project/category invariants require a real category for every project
  Item and no category for Business Inventory Items.
- The shipped Billing Summary adds every project Item's `purchasePriceCents` to
  Total Spent, even when the Item has no Transaction. The main budget rollup is
  Transaction-based. A priced Unaccounted For Item would therefore create
  inconsistent old-client reporting.
- The current Cloud Function `onTransactionWritten` replaces the existing
  `project.budgetSummary` using current Transaction semantics.
- Current item Functions maintain the price floor, Transaction membership,
  lineage, movement repricing, and completeness. An Item with no Transaction
  avoids movement repricing, but later Link must coordinate these triggers.
- Invoice collection currently writes `paymentToBusiness` settlement
  Transactions. The target instead writes one project Purchase, whose old-client
  meaning is ordinary spend.
- Current rules explicitly cover existing collections, including `protoItems`,
  and broadly permit member CRUD on several domain collections. New collections
  need additive rules; tightening existing rules can reject offline old-client
  writes.
- Existing proto Item documents, media paths, app writers, and MCP tools are
  live compatibility surfaces.
- Ledger has no current server-controlled minimum-supported-build or forced
  accounting-update gate. Sparkle can offer a macOS update, but neither the
  shipped macOS nor iOS app proves its build number to Firestore rules. An
  authority field alone therefore cannot hide same-collection v2 documents from
  a pre-update reader or distinguish its direct write by binary version.

## Compatibility Matrix

| Target change | Pre-update behavior at risk | Safe before cutover | Activation requirement |
|---|---|---|---|
| Unified Item wizard and new labels | None if UI/code remains unreleased | Local implementation and tests | Release only with the Item writer policy below |
| Real Unaccounted For project Item | Old Firebase app has no new sections and may count a Firebase-shaped Item incorrectly | Implement only in isolated Supabase/PowerSync target staging; legacy Firebase proto capture remains authoritative before cutover | Target app/budget contracts pass and Firebase source writes are frozen at cutover |
| Stop new proto writes | Old app and old MCP still write Firebase `protoItems` | Keep production collection, rules, indexes, media, readers, and old tools; target creates real Items only | Stale Firebase write rejection, pending-write recovery, and open-proto audit |
| Migrate existing proto Items | Duplicate Items, media loss, or source edits after export | Read-only source audit and idempotent Firebase→Supabase transform | Backup, durable source/target correlation, retry tests, reviewed dry run |
| Add Client and authoritative `project.clientId` | Old Firebase app still relies on free-text `clientName` | Create target Postgres Client/FK only; audit source names read-only | Target import/reconciliation complete; do not mutate/remove Firebase `clientName` before retirement |
| Add `transfer` Transaction type | Old Swift/Firebase readers reject or misunderstand it | Implement only in target domain/Postgres/PowerSync; keep Firebase source taxonomy unchanged | Target paired handler/tests pass; Firebase source frozen before activation |
| Retire Sale/paymentToBusiness/Fee/Expense writes | Old Firebase app/MCP still uses current taxonomy | Leave the existing Firebase app and MCP behavior unchanged | Activate target app/MCP together and reject late writes to the frozen Firebase source |
| Whole-Invoice collection creates one Purchase | Current Firebase collection expects paymentToBusiness | Compare target result against source fixtures; leave Firebase writer unchanged | Target Postgres collection handler, target budget authority, and target reader activate atomically |
| New Item/Expense Invoice source types | Old Firebase readers reject unknown values | Keep target values in Supabase only; the old app never reads them | Target release required before target activation |
| Expense entity | Old clients cannot explain its budget effect | Create target Postgres/RLS/Sync Stream implementation only | Target Invoicing UI, handler, and budget authority activate together |
| Item charge/credit occurrence entity | Old clients may manufacture current movement Transactions | Create target Postgres/RLS/Sync Stream implementation only | Target Link/movement handlers and budget authority active; Firebase source writers frozen |
| Two-segment budget progress | Changing Firebase `budgetSummary` changes every old project card | Leave Firebase calculation authoritative for v1; calculate/reconcile target projection from imported source | Target authority switches only after zero unexplained source/target differences |
| Additional Requests becomes tag/overlay | Repurposing current Firebase category changes old totals/pickers | Model and backfill in target; preserve Firebase category/current calculations | Target UI/projection activation; legacy field retirement is later cleanup |
| NonItemReceiptLine | Current full-document Firebase writers could erase additive fields | Keep Firebase documents unchanged; map target values during import and audit source evidence | Target completeness handler and migration parity tests pass |
| Split Item acquisition/placement/billing/paid links | Clearing Firebase `item.transactionId` breaks current lists/actions/lineage/MCP | Preserve Firebase field; build normalized relationships in target | Import/reconcile, activate target resolvers, retain source through rollback window |
| Firebase rules/indexes | Tightening or deleting them early breaks old/offline clients | Preserve current behavior before the cutover window; prepare only the minimum reviewed source-write freeze needed for the window | No v2 schema, paid locks, Transfer authority, indexes, or read model implemented in Firestore |
| Firebase Cloud Functions | New triggers could mutate current data/rollups | Leave current v1 Functions unchanged before cutover | No v2 budget, repricing, occurrence, Invoice, or reconciliation authority in Functions |
| MCP redesign | MCP can target the wrong authority independently | Leave the current Firebase MCP deployed; build the target MCP separately against Supabase | Activate the target MCP at cutoff and disable the old Firebase mutators |
| Storage migration/cleanup | Existing proto media may become unreadable or be deleted | Preserve Firebase objects; copy only through idempotent target manifest | Cleanup only after correlation audit, backup, and rollback expiry |
| Already-shipped Firebase client | Old binary can still write Firebase after final export even though it cannot see Supabase | Inventory pending-write risk and rehearse fail-closed source maintenance, write rejection, and user recovery | Adopt and test O-022 before final delta/target activation |

## Item-Creation Compatibility Decision

The target Unaccounted For Item should use the existing project Item invariant:

```text
projectId = current project
budgetCategoryId = enabled Furnishings category
transactionId = null
billable occurrence = none
```

Category is placement metadata here; it is not proof that the Item is Accounted
For and must not create budget contribution by itself.

This is a target Supabase contract. Current Swift behavior is useful source
evidence, but it is not a reason to add the target state to Firestore or modify
the current production repositories. Old billing arithmetic and MCP behavior
are migration constraints to capture in fixtures and reconciliation tests.

Required transition:

1. Change all new clients' accounting projections to derive Accounted For from
   a project Purchase or Item occurrence, not category or project placement.
2. Update Billing Summary, reports, exports, search warnings, and any aggregate
   that treats every project Item as financial evidence.
3. Make the target Swift app, MCP, Postgres handler/RLS, and PowerSync schema
   accept the same categorized No-Transaction Item contract.
4. Leave the existing production Firebase app and its data contract unchanged;
   do not add target Item states or target readers to Firestore.
5. Let the existing production app continue writing its current records until maintenance,
   final export, stale-writer rejection, and target activation occur.

## Authority and Version Strategy

Use one explicit authority state in the signed release/cutover manifest and
enforce it in target activation plus the operational Firebase write freeze. It
must answer which backend owns writes and calculations, not which app version
last touched a project.

Recommended shape:

```text
accountingAuthorityVersion: 1 | 2
```

- Version 1 keeps Firebase Transactions, proto writer, Invoice collection, and
  `budgetSummary` authoritative.
- Version 2 makes Supabase/PowerSync authoritative for direct Unaccounted For
  Items, occurrence-backed Invoicing, Client Transfers, the three-value
  taxonomy, and target budget resolver.
- Target commands compare the authority/contract version inside their Postgres
  transaction; Firebase independently enforces maintenance/stale-writer policy.
- A v1 writer cannot write the frozen source after final export. A v2 writer
  cannot activate before the target scope passes migration/reconciliation.
- Switching the marker occurs only after that account/project passes migration
  and reconciliation preconditions.

The authority state does **not** identify the calling app build. Supabase already
isolates target records from pre-update Firebase readers, so Ledger must not add
parallel v2 Firestore collections. O-022 instead controls how the final export
and Firebase source freeze reject/recover writes from already-shipped clients.
The hard cutover must not depend on an intermediate app release. If late-write
rejection and recovery cannot be proven, cutover remains blocked or uses an
explicitly approved per-account maintenance/isolation policy. A Remote
Config/settings document read only by the new app does not disable a binary
that never reads it.

Calculate the target budget projection in Supabase staging/production shadow
imports and reconcile it against Firebase source evidence. Never change the
existing Firebase `budgetSummary` formula merely to preview target numbers.

## Rollout Sequence

### Phase 0 — Record the current production baseline

1. Confirm what “prod” means: Git `main`, released app artifacts, deployed MCP,
   Firebase Functions/rules, or all of them.
2. Use the recorded clean `origin/firebase` baseline; do not perform redesign
   implementation in that checkout.
3. Verify the already-released build-82 state and any unshipped MCP/backend
   changes independently.
4. Record exact commit and deployed component versions without publishing a new
   Firebase build or backend deployment for this migration program.

### Phase 1 — Isolated redesign development

- Branch from the verified baseline with the repository's `codex/` prefix.
- Keep redesign code, tests, migrations, and specs off the release branch.
- Do not deploy new shapes or mutate production data.
- Build migration tools with dry-run as the default and explicit account scope.
- Build and use the dedicated Supabase/PowerSync staging app and MCP lane defined
  in the [Isolated Testing Plan](pre-cutover-testing-plan.md). Test source
  translation using immutable Firebase export fixtures; do not build or deploy
  a Firebase version of the redesigned application.

### Phase 2 — Build the isolated Supabase/PowerSync target

- Build Client, occurrence, Expense, Invoice, Transfer, and relationship models
  in target Postgres/PowerSync staging only.
- Add target RLS, Sync Streams, command handlers, indexes, and versioned MCP
  commands without adding their v2 equivalents to Firebase.
- Calculate target budgets from imported fixtures/snapshots and compare them
  with current Firebase source evidence.
- Add observability for dropped source records, incompatible writes, target sync,
  operation outcomes, and reconciliation drift.
- Design and rehearse O-022 as cutover operations: quiescence, inspection of
  pending work, source-write freeze, rejected-write recovery, and operator
  rollback. Do not refactor the running Firebase application to accomplish it.

### Phase 3 — Audit, migrate, and shadow

- Back up affected Firebase collections and attachment metadata.
- Inventory legacy enum values, open proto records, Invoice line shapes,
  settlement links, item/Transaction memberships, and category/tag candidates.
- Produce reviewed, idempotent mapping artifacts.
- Transform snapshots into resettable Supabase staging and calculate target
  budgets there; reconcile every difference to Firebase source IDs.
- Rehearse the exact Firebase→Supabase migration against production-like
  snapshots before any production target write.

### Phase 4 — Qualify the target release

- Distribute the target app only through internal/TestFlight release-candidate
  channels connected to isolated Supabase/PowerSync staging.
- Keep the public Firebase app and production data contract unchanged.
- Verify target offline behavior and cutover readiness without requiring public
  adoption of an intermediate build.

### Phase 5 — Coordinated authority cutover

For each eligible scope, operationally as one controlled window:

- enter Firebase accounting maintenance and resolve or explicitly disposition
  pending writes;
- freeze/reject stale Firebase accounting writes;
- take the final source backup/export and apply the rehearsed target delta;
- reconcile target Postgres before opening writes;
- activate Supabase/PowerSync authority, direct Item/Link,
  occurrence/Expense/Transfer, Invoice collection, and budget commands together;
- route target MCP mutators through the same target contract/authority version;
  and
- surface recoverable, user-visible handling for rejected stale source writes.

### Phase 6 — Reconcile, monitor, and retain rollback

- Compare source-level accounting and budget totals immediately and repeatedly.
- Monitor source decode drops, rejected stale writes, orphaned membership,
  PowerSync lag, duplicate idempotency keys, and source/target drift.
- If target invariants fail, freeze target writers and retain source/target
  evidence. Do not point clients back to Firebase after target-only writes exist;
  restoring source authority is safe only before target writes open or after an
  explicit reconciled back-migration.
- Continue resolving legacy proto records without breaking correlation.

### Phase 7 — Deferred cleanup

Only after the support and rollback windows expire:

- stop old proto/MCP writers;
- remove legacy UI entry points;
- retire legacy enum writes and fallback calculations;
- retire obsolete Firebase Functions/rules/indexes/fields only after manifest
  verification; and
- archive, rather than silently discard, migration evidence.

## Release Gates

The redesign cannot activate until all are true:

- [ ] Production baseline commit and every deployed component version recorded.
- [ ] Current dirty work separated from the read-only source-baseline audit.
- [ ] No target enum or Invoice source can disappear in a supported client.
- [ ] Unaccounted For Items do not affect budget, billing summary, reports, or
      exports until Linked.
- [ ] Legacy proto create/edit/media paths work for supported old clients.
- [ ] The existing Firebase rules, Functions, repositories, and MCP remain
      unchanged before cutoff; no v2 accounting implementation has been added
      to them.
- [ ] Client IDs and Transfer eligibility are reconciled.
- [ ] Invoice collection is atomic/idempotent and cannot double count budgets.
- [ ] Firebase-source and Supabase-target budget reconciliation explains every
      difference by source ID.
- [ ] Backups and tested rollback exist for every migration write phase.
- [ ] MCP and app share the same authority gate and domain commands.
- [ ] The adopted stale-client enforcement and recovery mechanism is ready.
- [ ] O-022 proves an already-shipped client cannot write the frozen Firebase
      source after final export without explicit rejection/recovery.
- [ ] Post-cutover alarms and an accountable operator are assigned.

## Immediate Next Actions

1. Keep the clean `firebase` checkout and its running implementation unchanged
   while target work proceeds in the dedicated Supabase branch/worktree.
2. Continue decision-independent target foundations through the manifest and
   machine-checked slice dossiers.
3. Resolve each mapping-changing product decision in the canonical spec and
   decision log before adding its active target writer.
4. Provision or contact no hosted staging service until isolated resource IDs,
   staging-only credentials, spend/run-rate bounds, cleanup ownership, and spike
   authority are explicit.
5. Treat source export, final freeze, deployment, release, and cutover as later
   separately authorized operations.
