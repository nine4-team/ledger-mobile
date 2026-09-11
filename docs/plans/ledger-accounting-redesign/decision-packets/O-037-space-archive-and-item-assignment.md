# Decision Packet — O-037 Space Archive and Item Assignment

Status: proposed recommendation; product decision not yet approved
Last reviewed: 2026-08-31
Owners: Spaces, Item Placement, Offline Queries, Search/Reports, Migration
Unlocks: 9 residual surfaces
Residual register: [generated M2 queue](../conversion/residual-decision-register.generated.md)

## Decision Requested

Approve or reject this policy:

> Every synchronized Space is archive-only. Archiving a Space retains existing
> Item assignments and makes the archived Space resolvable anywhere those Items
> appear, while removing it from new-assignment pickers and ordinary active Space
> lists. Archive never silently clears or moves Items. Users may explicitly move
> or clear affected assignments through a separate revision-safe Item-placement
> command before or after archive. Only a never-synchronized local Space draft
> with no dependent operation/media may be discarded physically.

This packet is a product/architecture proposal. It is not DDL, implementation,
production migration or provider approval.

## Confirmed Constraints

- Space is optional and independent from Item accounting state.
- Current physical Item placement and historical accounting provenance are
  separate facts.
- An Item may remain Unaccounted For while assigned to a Space.
- Silent assignment clearing loses location history; a hidden unresolved Space
  ID makes offline Item state misleading.
- Space photos, checklists, review notes and Item-linked marks carry stable
  history/attachment retention requirements.
- App and MCP must share typed operations and visibility/readiness behavior.

## Options

### Option A — Block archive while Items are assigned

Recommendation: reject as the only behavior. It forces unnecessary bulk work
and makes archival brittle for completed Projects with intentional historical
placement.

### Option B — Archive and clear assignments automatically

Recommendation: reject. It mutates Item placement without user intent and loses
the answer to where retained Items were grouped.

### Option C — Archive, retain resolvable assignments (recommended)

Existing references remain valid/readable. New assignments reject. Explicit
move/clear is a separate operation.

## Archive Semantics

`ArchiveSpace`:

- verifies Account/Project ownership, capability, expected Space revision and
  pending operations;
- sets archived actor/time/reason and increments revision;
- preserves name, description, checklist/review/media and all current Item
  assignments;
- does not change Item accounting, placement scope, occurrence, Invoice, budget,
  Transaction or Transfer evidence;
- removes the Space from new-assignment choices and active work queues; and
- writes one durable idempotent result/event.

The operation may return the authorized count of currently assigned Items and
available follow-up actions. That count is advisory, not a stale precondition or
authorization token.

`RestoreSpace` may unarchive under expected revision if the Project remains
active/authorized and no active-name/system conflict exists. Existing Item
assignments become ordinary active assignments again.

## Item Assignment Semantics

- An Item already assigned to an archived Space retains `space_id` and renders
  the Space name with an **Archived** badge.
- `AssignItemsToSpace` rejects archived destination Spaces.
- `MoveOrClearSpaceAssignments` is an explicit all-or-nothing command over exact
  Item IDs/revisions and either a validated active destination Space or `none`.
- Bulk follow-up may be launched from archive result, but archive and move/clear
  are not one implicit command. If the user requests both, a reviewed compound
  operation may perform them atomically while preserving the same story/event
  distinction.
- Moving an Item between Spaces never changes Project, Client, accounting Link,
  category, billing occurrence or paid history.
- Item movement out of the Project/Transfer may clear or replace current Space
  only through that story's placement contract; the archived Space remains in
  historical placement evidence where applicable.

## Query and Presentation Contract

Ordinary active Space queries omit archived rows, but every Item/placement query
that can return an archived `space_id` includes or can locally resolve a minimal
authorized archived Space reference:

- stable ID, Project, name and archived state/time;
- display-safe location context; and
- readiness/version.

Selected Project Sync Streams therefore include:

- active Spaces and their working detail as authorized;
- minimal archived Space resolvers for current Item assignments;
- full archived Space detail only when explicitly requested/authorized;
- Item placement revisions and pending operation results; and
- readiness proving whether assignment resolution is complete.

Item detail, search, reports and exports never render an archived assignment as
“No Space,” a broken ID, or an active selectable Space. Space lists can offer an
explicit archived filter. Counts are computed from authorized current placement
rows and cannot leak hidden Items.

## Checklist, Review, and Attachment Behavior

- Archive freezes no accounting, but existing checklist/review history remains
  queryable according to its own mutability/audit rules.
- New ordinary checklist/review work on an archived Space is disabled unless a
  typed historical correction/annotation command explicitly permits it.
- Attachments/review-note visual references remain stable and follow O-023
  detach/hold/quarantine rules. Archive never deletes bytes.
- Applying a Space template or creating a new Space cannot select an archived
  Space as a destination/parent.

## Physical Deletion

There is no app/MCP `DeleteSpace` for a synchronized Space, even when currently
empty. Archive is the terminal ordinary lifecycle and preserves stable history.

A local `DiscardSpaceDraft` may physically remove a Space only if it has never
been accepted/synchronized and a trusted local transaction proves:

- no Item assignment, checklist/review/history/attachment reference;
- no pending create/update/upload/operation;
- no report/export/template/migration correlation; and
- explicit confirmation of the exact draft.

Once the server accepts the Space ID, later emptiness does not make it deletable.
Administrative privacy/account deletion follows its separate retention policy.

## Conceptual Target Shape

| Family | Responsibility |
|---|---|
| `spaces` | Stable Account/Project identity, presentation, active/archived lifecycle and revision |
| Space checklist/review rows | Stable child identity/state/history and archive-aware mutation rules |
| Item placement/current assignment | Exact current optional Space relationship and revision |
| Space events | Append-only create/revise/archive/restore and assignment-operation evidence |
| minimal archived resolver projection | Visibility-safe local resolution for assigned Items |
| operation/results | Idempotency, payload hash, expected revisions and durable outcomes |

Use stable client-generated IDs, immutable Account/Project ownership, foreign
keys, `timestamptz`, revision checks and explicit archived state. Index every
foreign key/RLS key, active/archived Space lists, current Item assignments and
resolver lookup. Use a partial unique index for active normalized names if names
must be unique; archived names do not silently block a new active Space unless
the approved naming policy says otherwise.

## Atomicity and Concurrency

- `ArchiveSpace` locks operation, Project/Space and relevant pending dependency
  rows. It does not need to lock/rewrite every assigned Item because assignments
  remain valid.
- `MoveOrClearSpaceAssignments` locks Items/current placements in stable ID order,
  source/destination Spaces and result rows, revalidating exact revisions and
  active destination inside one short transaction.
- Concurrent archive/assign: either assignment commits before archive and is
  retained, or archive commits first and assignment rejects archived destination.
- Concurrent restore/new assignment, Project archive, Item Transfer/movement and
  bulk assignment serialize or return typed conflict with no partial assignments.
- No media upload or external call occurs while locks are held.

## Authorization, RLS, Sync, and Offline

- Active membership and Project/Space capability authorize archive/restore and
  assignment. Payload Account/Project/role never grants scope.
- Direct ownership/archive/assignment table patches are revoked where they could
  bypass revision/state checks. App and MCP use the same handlers.
- Restricted Project members cannot infer hidden Space/Item counts or resolver
  details. Existing/current row and resulting-row checks prevent cross-Account/
  Project reassignment.
- Offline archive and assignment operations are durable, ordered and visibly
  pending. Optimistic UI may mark the Space pending archive but must retain Item
  resolvers until authoritative result.
- Reconnect conflict never silently clears assignments. Local readiness
  distinguishes complete, partial, restricted and pending resolver state.

## Migration and Reconciliation

- Export every Space, archive/status/deletion evidence, Item `spaceId`, checklist,
  review note/visual reference, attachment, template correlation and timestamps
  from immutable Firebase source.
- Existing Space documents map to stable target Spaces. Source deleted/missing
  Spaces referenced by Items are not invented as normal active Spaces: preserve
  the raw ID/evidence and map to an archived migration resolver or quarantine
  with explicit reason.
- Do not clear Item `spaceId` merely because the source Space is archived,
  missing from an active query, or outside a stale cache.
- Source hard-deleted empty Spaces retain deletion evidence; referenced deletes
  require orphan review. Unknown child/reference relationships quarantine.

Reconcile Space IDs/states/revisions, Item assignments, unresolved references,
active/archived list membership, checklist/review/media children, report/search
resolution and every source deletion/quarantine disposition. Repeat/interrupted
import must be idempotent.

## Required Acceptance Tests

- archive empty/assigned Spaces and prove assigned Item IDs/revisions/accounting
  remain unchanged;
- active list/picker excludes archived Space while Item detail/search/report
  resolves its name/state offline;
- assignment to archived Space rejects; explicit move/clear commits all or none;
- archive/assign and restore/assign races produce one serial explainable result;
- Project/Item movement and Transfer preserve the correct current/historical
  Space evidence without changing money;
- archived checklist/review mutation follows typed restrictions and attachments
  remain held;
- synchronized Space physical delete/direct-table attempt fails; clean local
  unsynchronized draft discard passes only exact dependency checks;
- cross-account/restricted-role/hidden-count attempts fail without leakage;
- offline archive/restart/reconnect preserves resolver/readiness and pending
  result; and
- missing/deleted/referenced source Space fixtures map to archived resolver or
  quarantine without silent assignment loss.

## Approval Consequences

If approved:

1. update canonical Space/Item placement/search/report/offline specs and record
   the confirmed decision;
2. promote archive/resolver/assignment contracts into architecture 02/03/04/05/
   06/07;
3. remap the nine O-037 surfaces while retaining O-023/O-026/O-032/A-015 and
   other independent blockers;
4. specify reviewed constraints/indexes, RLS/Sync profiles, operation locks and
   migration orphan fixtures; and
5. include assigned archive/offline resolver/concurrency cases in the target
   spike.

## Approval Checklist

- [ ] Every synchronized Space is archive-only.
- [ ] Archive retains Item assignments and never silently moves/clears them.
- [ ] Archived Spaces are not selectable for new assignments.
- [ ] Items can resolve archived Space identity/state offline.
- [ ] Move/clear is a separate explicit revision-safe command.
- [ ] Only a dependency-free never-synchronized local Space draft may be
  physically discarded.
- [ ] Missing/deleted legacy Space references remain explicit migration evidence.
