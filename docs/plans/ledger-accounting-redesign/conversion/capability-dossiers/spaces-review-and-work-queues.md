# Capability Dossier — Spaces, Review, and Work Queues

Status: reviewed static characterization; 16 of 27 target-relevant surfaces are
exactly target-mapped. Eleven archive/review-media/work-queue/optimistic-
operation surfaces remain honestly withheld on their named blockers;
implementation remains unauthorized

## Outcome

An authorized user can organize Project and Business Inventory Items into
Spaces, capture Space photos/notes/checklists, review the physical Space against
Ledger, and resolve work needing attention while offline. Space placement is
scope-valid, durable, and explainable; it never changes accounting. Archiving a
Space cannot orphan, hide, or silently erase Item placement. Review queues name
the approved evidence problem and launch the owning typed correction/completion
flow rather than mutating arbitrary fields.

## Source Surfaces

- `Space`, `SpacesService`/protocol, Project and Inventory Space lists, New/Edit/
  picker/card/detail views, form/list/detail calculations, and Space integration
  tests;
- `SpaceReviewNote`, visual reference/marker UI,
  `SpaceReviewNotesService`, checklist editing and review-note tests;
- app `ReviewView`/`ReviewCalculations`, the legacy `needsReview` removal script,
  and the reporting dossier's MCP triage dependency;
- MCP Space module, scope assignment helper, list/get/create/update tools; and
- Space, data-model, attachment, offline, Item-placement, financial-access and
  reference-data specs.

## Current Behavior and Defects

1. `Space` is a Firestore DTO. Checklist/checklist-item IDs default to random
   UUIDs when absent, and custom coding keys omit stored timestamps.
2. The service exposes generic field dictionaries and hard delete even though
   the product spec calls ordinary removal archive.
3. No trusted delete/archive handler rechecks assigned Items, review notes,
   attachments, template origin, or concurrent assignments.
4. Archived Space behavior is inconsistent: lists may hide the Space while
   assigned Items retain an unresolved `spaceId`; movement paths may clear it.
5. Bulk Item-to-Space assignment is composed as independent writes and can
   partially apply or cross a changed scope.
6. Checklists are embedded arrays updated as a whole. Concurrent edits/reorders/
   checks have no revision or merge contract.
7. Review-note actor names/IDs and timestamps are client-authored; update/delete
   is generic repository CRUD with no explicit author/admin policy or audit.
8. A review visual reference is identified by `spaceId|image.url`, copies an
   attachment snapshot, and rejects local/offline attachment schemes. URL
   rotation or migration changes identity and offline capture can disappear.
9. Space detail creates additional Firebase-backed Project contexts and direct
   listeners based on route state, producing partial refreshes and duplicate
   backend composition.
10. Space detail also owns Item media matching, status, movement, Transaction
    association, delete and copy workflows. Those outcomes belong to existing
    Item/media/movement commands, not Space persistence.
11. New Space/template behavior is incomplete in the current app; template
    selection is stubbed and Save as Template can report success without write.
12. Current Review is an in-memory queue of legacy incomplete Transactions,
    bucketed by nullable Project and sorted with current Transaction helpers. It
    cannot distinguish local capture draft, migration review, canonical posted
    evidence, or incomplete synchronization.
13. MCP Space reads/writes use Firebase DTOs and generic updates; service-role
    execution does not establish target RLS/Sync authorization or local offline
    readiness.

## Product and Spec Reconciliation

| Authority | Assessment |
|---|---|
| `spaces.md` | Governs Space organization, checklists, templates and review outcomes; Firestore mechanics, hard deletion and stale `needsReview` behavior are not target requirements |
| `items.md` | Preserves stable Item identity, optional Space placement and relevant list/detail outcomes without making Space an accounting relationship |
| `inventory-item-invoicing-lifecycle.md` | Canonical target Item movement and correction stories must retain explainable Space placement or explicit clearing without rewriting accounting history |
| `proto-item-capture.md` | Canonical target one-Item writer may assign an optional Space; Space is independent from Accounted For state and Link routing |
| O-023/O-026/O-032/O-037 | Attachment retention, template administration, posting/review readiness and archive effects remain explicit blockers where they change commands or storage |

## Behavior Decisions

| Classification | Decision |
|---|---|
| Preserve | Project and Inventory Spaces; duplicate names; optional notes/photos/checklists; checklist progress; create/edit/list/detail/picker UX; Item counts; review notes with at most one same-Space photo and normalized red marker; offline review; work queues and search/sort productivity |
| Correct | Hard delete; hidden unresolved archived IDs; independent bulk assignment; random decoded IDs; omitted timestamps; generic field updates; client-authored actor/time; URL-keyed media identity; offline-photo exclusion; duplicate listener graphs; template false success; legacy `needsReview` authority |
| Improve | Stable IDs/revisions, deterministic ordering, typed conflict results, explicit readiness/integrity, locally durable review-note media, assignment availability/capabilities, complete template flows, actionable typed review reasons |
| Redesign | `SpaceWorkspaceSnapshot`; typed create/update/archive/checklist/review-note/assign commands; stable attachment reference; target posting/import-review projection; RLS/Sync-filtered local data |
| Retire | Target Space hard delete except any separately approved verified empty draft; generic Space field dictionaries; fire-and-forget bulk assignment; URL identity; target `needsReview` boolean and Firebase repository/listener composition |
| Source only | Current Firebase Space/review documents and scripts after migration/source freeze |
| Open | O-026 Space-template administration, O-032 posting/review states, O-037 archive assignment, O-023 attachment retention, A-015/A-016 |

## Target Contracts

`SpaceWorkspaceSnapshot` contains the Space, authoritative scope, archive state,
revision, ordered checklists, attachment IDs/states, review notes, assigned Item
summaries, readiness/integrity and allowed action capabilities. Project/
Inventory lists and detail query the local database; route context cannot grant
scope or create a second backend authority.

Typed operations include:

- `CreateSpace` and `UpdateSpaceDetails`;
- `ReviseSpaceChecklists` with expected revision and stable nested IDs;
- `AssignItemsToSpace` / `ClearItemsFromSpace` with one scope-validating atomic
  handler and durable result;
- `ArchiveSpace`, gated by O-037 for assigned Items and any physical deletion;
- `CreateSpaceReviewNote`, `ReviseSpaceReviewNote`, and
  `RemoveSpaceReviewNote` with server actor/time and revision/audit; and
- `CreateSpaceFromTemplate` / `SaveSpaceAsTemplate`, using the reference-data
  authorization from O-026 and resetting every copied checklist item unchecked.

A Space operation never writes Transaction, occurrence, Invoice, budget, payer,
or accounting state. Item movement commands may validate/clear destination-
incompatible Space IDs as part of their own atomic scope change.

Review visual references store stable `attachment_id` plus marker coordinates
and optional immutable display metadata. They reuse the parent Space attachment;
they do not duplicate bytes. A locally durable pending attachment is eligible
offline. Detach/delete follows O-023 and the attachment dossier.

The target work queue consumes explicit states such as local capture draft,
import review, rejected operation, migration quarantine, or canonical evidence
integrity issue. Each row carries a stable reason code, source IDs, readiness,
allowed resolution command and deterministic cursor. It does not infer target
posting readiness from the legacy `isComplete`/`needsReview` pair.

## Security, Offline, and Migration

- Account/Project/Inventory scope and active membership are enforced before
  Sync download and again by RLS/handlers. Financially restricted Item details
  and work-queue counts never leak through Space summaries.
- Space/review/checklist edits are locally durable; complex assignment/archive
  operations expose queued/applied/rejected receipts across restart.
- Migration preserves Space/checklist/review-note IDs when stable, generates
  deterministic mappings when absent, restores timestamps from raw evidence
  where possible, maps URL snapshots to attachment IDs, and quarantines cross-
  Space visual references, cross-scope assignments, hard-deleted parents,
  duplicate nested IDs, and undecodable arrays.
- Archived/assigned Space rows remain resolvable in target fixtures pending
  O-037; migration never silently clears Item placement.
- Legacy `needsReview` values are source evidence mapped to explicit target
  draft/import/integrity states only when the rest of the record proves it.

## Verification Contract

- create/edit/archive/list/detail across Project and Inventory scopes;
- duplicate names, stable IDs/order, concurrent checklist check/edit/reorder;
- single/bulk assign/clear, cross-scope rejection, concurrent Item movement,
  idempotent retry and offline restart;
- assigned-Space archive/search/report behavior after O-037;
- review-note actor/time/revision, same-Space photo validation, pending offline
  attachment, URL rotation, detach/delete and marker bounds;
- template create/apply/save/reset plus O-026 authorization;
- no accounting mutation from Space operations;
- work-queue readiness/reason/action/cursor, O-032 draft/post behavior and no
  hidden count/amount leak; and
- migration orphan/cross-scope/duplicate/timestamp/attachment reconciliation.

This dossier does not authorize target DDL, Supabase/PowerSync implementation,
production reads/mutations, migration, or cutover. It creates no Firebase
adapter and requires no new Firebase Space implementation.
