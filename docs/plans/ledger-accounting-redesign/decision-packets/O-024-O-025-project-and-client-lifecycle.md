# Decision Packet — O-024/O-025 Project and Client Lifecycle

Status: proposed recommendation; product decision not yet approved
Last reviewed: 2026-08-31
Owners: Projects, Clients, Corrections, Reporting, Transfer Authorization
Unlocks: 7 unique residual surfaces (O-024: 5; O-025: 5; overlap: 3)
Residual register: [generated M2 queue](../conversion/residual-decision-register.generated.md)

## Decision Requested

Approve or reject this lifecycle policy:

> Every server-accepted Project is archive-only; ordinary app/MCP operations
> never physically delete it. A never-synchronized local Project draft may be
> discarded only when it has no accepted/pending child or media dependency.

> Ordinary Project edits never change `client_id`. A dependency-safe
> `CorrectProjectClient` may reassign an otherwise nonfinancial Project before it
> has Client-owned accounting, Invoice, Transfer, delivered report, or other
> immutable history. After that boundary, reassignment is blocked and requires a
> separately reviewed administrative migration/business workflow.

> Duplicate Client identities may be merged even when their Projects have
> history, but only through an owner-authorized `MergeClients` command that picks
> one survivor, aliases the loser, moves current Project ownership atomically,
> preserves all frozen display/audit snapshots, changes no money, and records a
> complete dependency/result receipt. Merge never retroactively creates or
> rewrites Transfers.

## Confirmed Constraints

- Client ID, not name, defines ownership and same-Client Transfer eligibility.
- Project/Client identity is Account-scoped and cannot move across Accounts.
- Renaming a Client changes current display while frozen Invoice/report/history
  snapshots remain.
- Current Firebase Project delete can orphan children; that is a source defect,
  not target behavior.
- Financial/placement/Invoice/Transfer/media history must remain explainable
  after Project/Client lifecycle changes.
- App and MCP use typed trusted operations, not raw Project `clientId` patch.

## Options

### Option A — Dependency-based physical delete and ordinary Client reassignment

Reject. Later emptiness cannot prove that synchronized history, external
artifacts, offline operations, or retained references never existed, and a raw
Client change can alter Transfer/report/accounting ownership silently.

### Option B — Never permit correction or duplicate merge

Reject as too rigid. It preserves history but leaves genuine pre-history setup
mistakes and duplicate real-world Client identities permanently fragmented.

### Option C — Archive after synchronization, typed pre-history correction, and
audited Client merge (recommended)

Allow physical discard only for a proven clean never-synchronized local draft;
archive accepted Projects; permit exact dependency-safe Project Client
correction before immutable history; and merge true duplicate Clients through a
survivor/alias operation that changes no money or frozen snapshots.

## Project Lifecycle

### Archive

`ArchiveProject`:

- validates capability, exact Project revision and pending operations;
- records archived actor/time/reason and revision;
- preserves Client, Items, Spaces, Transactions, Invoicing sources, Invoices,
  budgets, attachments, reports, operation results and history;
- removes the Project from new-work/default active pickers and rejects new
  ordinary financial/placement writes unless a typed archive exception exists;
- retains authorized read/report/export and migration resolution; and
- writes one idempotent result/event.

Archiving does not archive the Client automatically, clear Item placement, cancel
Invoices, settle credits, delete media or change accounting. The UI must explain
blocking active work (for example pending collection/operations) and route it to
the owning command rather than cascading silently.

`RestoreProject` may reactivate under expected revision when Client remains
active/authorized and no identity/name/config conflict blocks it.

### Physical discard

`DiscardProjectDraft` is local-only and permitted solely before server acceptance
when a trusted local transaction proves no child Item/Space/note/category/
attachment, pending upload/operation, external artifact or migration correlation.
After one accepted Project ID, later emptiness does not make it deletable.

Account deletion/privacy retention is a separate higher-authority policy.

## Project Client Correction

`CorrectProjectClient` is allowed only when all are true:

- same Account and active destination Client;
- exact Project/source/destination revisions and explicit reason/confirmation;
- no Purchase/Return/Transfer, Item accounting occurrence, Expense/Fee/
  adjustment/credit, Invoice, collected allocation, paid history, delivered
  client artifact, or Client-specific immutable operation;
- no conflicting pending write/media/report/migration review; and
- every current nonfinancial child can be reassigned without contradicting its
  own ownership/history rules.

The command atomically changes Project client ownership, current denormalized
display, safe nonfinancial current children and report/search projections, then
appends before/after/reason evidence. It never rewrites historical snapshots.

If any immutable history exists, ordinary reassignment rejects with an exact
dependency plan. The recommended user path is to correct the Client identity via
merge if both IDs truly represent the same Client, or create/use the correct
Project and perform real current-state movement/accounting actions. A bespoke
administrative correction after history requires explicit product/accounting
review and is not exposed as generic CRUD.

## Duplicate Client Merge

`MergeClients` is an identity correction, not a Transfer or financial event.

- Owner chooses survivor and duplicate within the same Account.
- Command previews all Projects, memberships/contacts if later added, Transfers,
  Invoices, reports, open operations and name/display conflicts.
- It locks both Clients and Projects in stable ID order, revalidates every
  dependency, assigns current Project `client_id` to survivor, archives/aliases
  loser and appends merge evidence atomically.
- Frozen Invoice/report/Transaction/Transfer display snapshots and source
  correlations retain their historical values/IDs plus resolver to survivor.
- Existing Project money/budgets do not change; Client aggregate projections
  rebuild under survivor. Projects newly become eligible for future same-Client
  Transfer only after accepted merge.
- No historical movement between formerly separate Client IDs is relabeled as a
  Transfer or made legal retroactively.

Conflicting evidence that Clients represent different real people/entities
blocks merge. A merge cannot be undone by restoring the loser; reversal is a
separately reviewed identity correction that must preserve all post-merge work.

## Client Archive

A Client may be archived for new Project selection while existing Projects and
history remain resolvable. Recommended default: active Projects block archive
until they are archived or explicitly reassigned under the safe pre-history
rule. Client physical delete is unavailable after synchronization.

## Conceptual Target Shape

| Family | Responsibility |
|---|---|
| `clients` | Stable Account identity, current display, active/archived revision |
| `projects` | Stable Account/Client relationship, current lifecycle and revision |
| Client aliases/merge events | Loser-to-survivor resolution and immutable dependency/result evidence |
| Project Client correction events | Typed before/after/reason/confirmation for allowed pre-history correction |
| archived resolver projections | Visibility-safe local resolution for historical/current references |
| operation/results | Idempotency, dependency-plan/payload hash, expected revisions and outcomes |

Use stable client-generated IDs, immutable Account foreign keys, explicit archive
state and indexed Client/Project/alias relationships. Index every FK/RLS key,
active/archived lists and merge/correction lookups. Enforce same-Account Client FK
through schema/handler constraints and prevent direct `client_id` updates.

## Atomicity, Authorization, and Offline

- Archive/correction/merge lock operation, Clients/Projects in stable order,
  dependency headers and projection/result rows; revalidate plan/authorization
  inside one short transaction.
- Owner/Admin/default capability matrix names archive/restore; Client merge and
  post-history administrative correction require narrower owner-level authority
  and exact confirmation. Payload role/account never grants scope.
- RLS prevents cross-Account ownership changes and hides protected Client/
  Project/financial dependencies/counts from unauthorized members.
- Direct delete/client-FK/alias/event writes are revoked. App/MCP use identical
  handlers and safe result projections.
- Offline archive/correction/merge submissions are durable but not
  optimistically authoritative where Client identity changes authorization.
  Pending state is visible; server conflict restores authoritative identity.
- Sync Streams include active/archived minimal resolvers required by current
  Items/history without leaking hidden financial child existence.

## Migration and Reconciliation

- Preserve every Firebase Project/clientName, child relationship, deletion/
  archive evidence, Invoice/report name snapshot and source timestamp/hash.
- Generate Client candidates from normalized names only as review suggestions.
  Reviewer chooses/create Client; homonyms/households/entities remain distinct.
- Existing missing/orphan Project documents/children receive explicit migration
  disposition; do not delete children or synthesize ownership from nearest name.
- Map prior duplicate Client decisions/aliases deterministically. Merging target
  Clients records every source name/Project correlation and changes no cents.
- Source hard-deleted Projects with retained children/history import as archived
  resolver/review evidence, not active invisible Projects or dropped children.

Reconcile every Project/Client/alias, child ownership, archive state, frozen
display snapshot, Transfer eligibility, Client aggregate, source orphan/delete
and quarantine reason. Repeat/interrupted import/merge remains idempotent.

## Required Acceptance Tests

- archive/restore empty and child-bearing Projects without deleting/reassigning
  children or changing accounting;
- synchronized Project direct delete fails; dependency-free never-synced local
  draft discard succeeds only before acceptance;
- pre-history same-Account Client correction commits atomically; every listed
  history/dependency/cross-Account case rejects with no partial reassignment;
- duplicate Client merge moves current Projects, retains frozen snapshots/
  aliases, changes no Project/client-wide cents and enables only future Transfer;
- conflicting identity evidence blocks merge; direct client-FK/alias patch fails;
- concurrent create-history/correction, Transfer/merge, archive/child write and
  merge/merge serialize or conflict safely;
- restricted/cross-account users cannot infer dependency counts or mutate;
- offline submit/restart/reconnect exposes pending/result without temporary
  authorization widening; and
- deleted/orphan/duplicate-name migration fixtures preserve all source evidence
  and reconcile deterministically.

## Approval Consequences

If approved:

1. update canonical Project/Client/Transfer/report/migration specs and record
   confirmed decisions;
2. promote archive/correction/merge contracts into architecture 02/03/04/05/06/
   07/08;
3. remap the seven affected surfaces while retaining production-profile/A-015/
   other independent blockers;
4. specify reviewed constraints/indexes, RLS/Sync profiles, dependency plans and
   migration fixtures; and
5. include identity-authorization concurrency and offline cases in the target
   spike.

## Approval Checklist

- [ ] Every server-accepted Project is archive-only; only clean local draft may
  be physically discarded.
- [ ] Ordinary edits never change Client.
- [ ] Project Client correction is limited to same-Account pre-immutable-history
  state with exact dependency proof.
- [ ] Duplicate Clients merge through owner-authorized survivor/alias operation
  without changing money or frozen snapshots.
- [ ] Merge affects only future Transfer eligibility and never rewrites history.
