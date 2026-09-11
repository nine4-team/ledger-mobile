# EVID-CAPABILITY-SPACES-REVIEW-001 — Spaces, Review, and Work Queues

- Timestamp: 2026-08-31
- Class: static source/spec characterization and capability synthesis
- Repository baseline: `d83c64724fe4e92be27c62f425979bd30fcfc9bb`
  on `dev`; shared worktree was already dirty
- Production reads or mutations: none
- Target implementation/schema/RLS/Sync Stream changes: none
- Operator: Codex
- Primary artifact: `capability-dossiers/spaces-review-and-work-queues.md`

## Sources Reviewed

- Space/checklist and SpaceReviewNote/visual-marker models;
- Swift Space service/protocol, review-note service, Project/Inventory lists,
  create/edit/picker/card/detail/checklist/review UI and pure calculations;
- app Transaction Review queue and legacy `needsReview` removal history;
- MCP Space module, scope-assignment helper and list/get/create/update tools;
- Space/review/assignment integration and calculation tests; and
- Space, data-model, Item, media, offline, reference-data, accounting, and
  financial-access specs plus adjacent capability dossiers.

## Method and Result

The review traced Space identity/scope, checklist/review-note/media state,
single/bulk Item assignment, archive/delete, template, list/detail/search/report
use, and work-queue behavior through app, MCP, tests, rules/query assumptions and
migration shapes. Source mechanics were separated from the organizational and
physical-review outcomes worth retaining.

The dossier defines a local `SpaceWorkspaceSnapshot`; typed Space, checklist,
assignment, review-note and template commands; stable attachment identity; and
explicit posting/import/operation review queue reasons. O-037 now records the
unresolved assigned-Item behavior at Space archive, with resolvable archived
placement as the provisional safe direction.

## Material Findings

- Current service hard-deletes despite the archive spec and does not recheck
  assigned Items, notes, attachments, or concurrent writes.
- Bulk assignment is independent generic writes and can partially apply or
  cross a changed Project/Inventory scope.
- Embedded checklist arrays have no revision/merge contract; missing nested IDs
  can become random on decode, while Space coding omits timestamps.
- Review-note actor/time is client-authored and its visual reference uses copied
  URL-shaped attachment metadata; pending offline photos are excluded.
- Space detail builds extra Firebase listener/context graphs and directly owns
  unrelated Item movement, relation, media, status and delete mechanics.
- Current template UI is incomplete and can report success without persistence.
- Current Review infers work from legacy incomplete Transactions and partial
  account arrays rather than explicit target draft/import/integrity states.

## Limitations

Production archived/deleted Spaces, assigned orphan IDs, duplicate/missing
checklist IDs, review-note authors/timestamps, URL variants, pending media,
template usage, concurrent edits and `needsReview` distributions remain
unconfirmed until read-only profiling and staging fixtures. Final mapping still
depends on O-023/O-026/O-032/O-037, A-015/A-016 and target schema/index tests.

This evidence supports target-independent command, query, security, offline,
migration, and test design only. It does not authorize Postgres DDL, Supabase
RLS/RPCs, PowerSync Streams, Firebase refactoring/adapters, production reads/
mutations, migration, or cutover.
