# EVID-CAPABILITY-MEDIA-001 — Media, Attachments, and Offline Byte Durability

- Timestamp: 2026-08-31
- Class: static source/spec characterization and capability synthesis
- Repository baseline: `d83c64724fe4e92be27c62f425979bd30fcfc9bb`
  on `dev`; shared worktree was already dirty
- Production reads or mutations: none
- Target implementation/schema/Storage changes: none
- Operator: Codex
- Primary artifact:
  `capability-dossiers/media-attachments-and-offline-byte-durability.md`

## Sources Reviewed

- iOS attachment/upload values, Firebase media service, persistent upload queue,
  URL resolver, thumbnail generator, memory/URL caching and application wiring;
- gallery, thumbnail, PDF, pinning, annotation, save/share/print components and
  their pure calculation tests;
- Account, Project, Item, legacy proto, Space/review-note and Transaction media
  shapes plus create/detail/import caller paths;
- MCP Storage, derivative, primary/order, Item ownership/copy helpers and Item,
  Space, Transaction and quick-draft tool call sites/tests;
- production Storage rules and existing static backend characterization;
- Firebase fixtures, old Supabase-to-Firebase media migration/repair scripts and
  the narrow receipt-attachment exporter;
- `offline-first.md`, `items.md`, `proto-item-capture.md`, `data-model.md`,
  `spaces.md`, `ui/image-pinning.md`; and
- architecture A-003/A-004/A-006/A-011/A-016, attachment/local lifecycle,
  Storage security, target ports, migration and cutover guardrails.

## Method and Result

Static source and call-site searches were reconciled with models, existing
tests, specs, architecture decisions, prior backend evidence and conversion
surface IDs. The dossier separates current behavior from intended outcomes,
classifies preserve/correct/improve/redesign/retire/open behavior, defines a
backend-neutral observable contract and names migration/security/offline tests.

`offline-first.md` was corrected where authority is clear: all attachment
capture paths must durably accept and display local bytes, stable attachment
identity replaces URL identity, private uploads reconcile separately from
structured sync, and removal of a reference is not automatically physical byte
deletion. The legacy proto field in `data-model.md` was corrected from `images`
to implemented `photos`. O-023 records the unresolved product/retention choice
instead of silently choosing destructive behavior.

## Material Findings

- Durable media handling is not universal. New Project/Item, quick-draft and
  invoice-import paths enqueue bytes; new Transaction, Account logo and several
  detail paths upload directly.
- Queue enqueue can fail to write bytes/metadata but still returns a success-
  shaped ID. The queue's local-display APIs have no observed callers, so the
  documented immediate local display is not implemented uniformly.
- Item/Space direct uploads can leave empty-URL placeholders without retained
  bytes; missing queue bytes are silently removed during processing.
- URL serves as identity across ordering, removal, reuse and note snapshots;
  existing data can contain Firebase token URLs, `gs://`, `offline://` and other
  historical forms.
- Current Storage rules are globally open. Pending bytes/caches are not
  principal/environment partitioned, and signout/account switch do not own
  their disposition.
- iOS commonly deletes only the original after reference removal, leaving
  derivatives, while MCP paths differ between non-destructive Item detach and
  immediate Space/Transaction deletion. Shared references and financial/history
  retention are not authoritatively checked.
- MCP remote URL ingestion checks size only after download and lacks one shared
  scheme/redirect/private-network/streaming/timeout/MIME/path validation policy.
- The useful product behavior is richer than upload: offline capture intent,
  galleries, primary/order, derivatives, PDFs, pin/save/share/print, Item-photo
  marks, Space review snapshots and source evidence must survive the redesign.
- Existing media migration tools run in the old Supabase-to-Firebase direction
  or are one-off repairs. They are source evidence, not the target migrator.

## Limitations

Production object counts, sizes/types, URL/path variants, shared references,
missing/dangling objects and Auth/financial visibility inheritance remain
unconfirmed until the fail-closed read-only Storage/reference profile runs.
This dossier permits target-independent attachment contract/test mapping and a
bounded synthetic private/resumable/offline spike. It does not authorize a
Supabase bucket/table/RLS policy, PowerSync Stream, object layout, Firebase
adapter, production read/mutation, or migration.
