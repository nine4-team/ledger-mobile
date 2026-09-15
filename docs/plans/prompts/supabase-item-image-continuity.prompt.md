# Supabase Item Image Continuity Implementation Prompt

Implement the confirmed Item-image continuity behavior in the Supabase/PowerSync
target without changing the Firebase app or any production environment.

## Start Here

- Work in `/Users/benjaminmackenzie/Dev/ledger_mobile_supabase`.
- Read and follow the repository `AGENTS.md`, the Supabase skill, the conversion
  method, the active product checklist and the current execution-state pointer.
- The category-management workflow may contain unrelated in-progress changes.
  Do not mix this work into that batch or overwrite its files. Establish an
  isolated workflow/checkpoint for Item creation and media continuity when the
  conversion method permits it.
- Do not update frozen source inventory, source behavior IDs, source hashes,
  historical catalogs or baseline counts merely because this is a newly
  confirmed post-baseline behavior.

## Product Authority

- D-031 in `docs/plans/ledger-accounting-redesign/decision-log.md`.
- `docs/specs/items.md`, especially **Target Physical Copies**, **Physical
  Copies and Quantity Expansion**, and **Image Management**.
- `docs/specs/proto-item-capture.md`, especially **Unified Item-Creation
  Wizard**, **Legacy Proto-Item Source Migration**, and **Required Tests**.
- `docs/specs/offline-first.md`, especially **Target Attachment Lifecycle** and
  **User-Initiated Image Transfer**.
- `docs/plans/ledger-accounting-redesign/conversion/product-behavior-checklist.json`
  is the only active conversion checklist.

This decision settles creation-time quantity image propagation, explicit image
copy/paste, and platform Save to Device. It does not settle later **Make Copies**
inheritance under O-066 or attachment deletion/retention under O-023.

## Verified Starting Point

The target already has useful foundations. Reuse them rather than building a
second media system:

- authorized downloaded Item-image reads;
- byte-level export preparation/revalidation and overlapping-export blocking in
  `LedgeriOS/LedgerTargetAppModel/DownloadedItemImagesModel.swift`;
- the shared full gallery and pinned presentation;
- Share and iOS Photos Save to Device in
  `LedgeriOS/LedgerTargetApp/DownloadedItemImagesView.swift`;
- durable attachment capture receipt contracts in
  `LedgeriOS/LedgerTargetCore/AttachmentCaptureReceipt.swift` and their tests.

The audited gaps are:

- no connected target unified Item writer that expands creation quantity;
- no connected target media add/upload mutation flow for Item, lightweight
  capture, Space and Transaction parents;
- no target Copy Image or Paste Image action;
- no macOS Save to Device file-destination flow;
- legacy proto quantity/media migration remains specification/checklist work.

## Required Behavior

1. Creation quantity N creates N distinct physical Items. Every Item receives
   the complete selected image set, even when bytes are locally queued, offline,
   retrying, replayed or restored after process restart. Missing required local
   bytes must prevent a success-shaped partial result. Repeated submission and
   replay must not duplicate Items, attachments or canonical objects.
2. Copy Image copies the currently selected authorized image bytes—not its URL,
   token, attachment ID or local path—to the platform clipboard after a fresh
   authorization/reference check.
3. Paste Image is an explicit platform-authorized action in supported Item,
   lightweight capture, Space and Transaction media-add flows. It creates a new
   destination attachment relationship and succeeds only after the protected
   bytes and durable local capture receipt are stored. Prefer native explicit
   paste controls such as `PasteButton`; do not probe the clipboard just to
   decide whether the UI should show the action.
4. Save to Device preserves the existing iOS Photos add-only behavior and adds
   a macOS user-selected file destination. Cancellation is not an error. Denial,
   stale authorization, unavailable bytes and write failure are visible and
   retryable. Share remains separate.

## Architecture and Security Boundaries

- Stable attachment IDs and parent relationships are canonical; URLs are not.
- Use the existing durable capture receipt and attachment lifecycle. Do not add
  a parallel queue, repository, upload tracker or gallery.
- Revalidate exact Account, parent, attachment reference, allowed media kind,
  capacity and in-flight operation before handoff or mutation. Learned
  revocation must fail closed.
- Preserve private object storage and exact-scope RLS. Never put a service-role
  credential in a client.
- Respect the unresolved O-023 retention boundary and O-051 rejected-work
  recovery boundary. Do not invent permanent deletion behavior.
- Do not add a Firebase adapter, target proto writer, dual read or dual write.
- Do not access production, provision hosted resources, run migrations or
  perform cutover without separate explicit user authorization.

## Checklist Integration

Create or resume the future owning Item-creation/media workflow only after the
active category workflow is safely checkpointed according to the conversion
method. Map D-031 to the existing outcomes for:

- `item-create-unified-wizard`;
- `attachment-capture-delivery-verification`;
- `legacy-proto-item-migration`; and
- the existing Item image viewer/export acceptance coverage where applicable.

Do not claim the blocked unified creation or legacy migration outcomes are
complete until their other open decisions are resolved. Do not fold Copy/Paste
write acceptance into the read-only downloaded Item browsing workflow simply
because the gallery already exists.

## Verification

Add focused unit/integration/native coverage for at least:

- quantity N multiplied by the full selected image set;
- offline acceptance, restart, retry and idempotent replay;
- missing pending bytes producing a recoverable failure with no partial success;
- Copy Image delivering exact authorized bytes and rejecting stale/revoked
  references;
- Paste Image enforcing destination scope, media kind, capacity, durable receipt
  and duplicate prevention across every supported parent flow;
- iOS Photos save success, denial, cancellation and operation re-enable;
- macOS explicit file selection, successful byte write, cancellation, failure
  and operation re-enable; and
- native visibility and usability of Copy, Paste, Save and Share controls on
  both supported platforms.

Use the repository's normal conversion and native verification gates. Report
exact commands, results, unresolved blockers and which claims remain unproved.

## Deliverable

Return a compact implementation report covering changed authority/checklist
records, code paths, tests, security review, migration impact and any remaining
decision blocker. Clearly distinguish already-existing behavior from newly
implemented behavior and do not claim production deployment or cutover.
