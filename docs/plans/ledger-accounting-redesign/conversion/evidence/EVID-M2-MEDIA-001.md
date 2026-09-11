# EVID-M2-MEDIA-001 — Attachment and Offline-Byte Target Mapping

- Timestamp: 2026-08-31
- Class: target mapping design evidence
- Repository baseline: `d83c64724fe4e92be27c62f425979bd30fcfc9bb`
  on `dev`; shared worktree was already dirty
- Production reads or mutations: none
- Target implementation/schema/RLS/Storage/Sync Stream changes: none
- Operator: Codex
- Mapping batch: `M0-MEDIA-LIFECYCLE-001`
- Method: `target-mapping-method.md`

## Scope and Result

The media batch contains 19 `replace`, `redesign`, or `migrate` surfaces. Fifteen
have complete target maps. Four destructive/reference-removal MCP surfaces
remain deliberately `characterized` because O-023 and the unproven production
reference/object graph can still change whether the target exposes detach,
quarantine, retention, or permanent-delete commands at all.

The completed map covers the local pending-media boundary, attachment identity
and capture receipts, local-first display, galleries and protected PDF display,
export/share behavior, Item/Space/Transaction attach operations, Item ordering
and primary selection, MCP ingress parity, and target contract/migration tests.

## Mapping Decisions

- One stable `AttachmentID` replaces URLs, Firebase paths, and upload
  placeholders as identity. `attachments` and `attachment_references` own
  durable metadata, ordered parent relationships, primary state and canonical
  private-object locators.
- Every accepted capture first creates protected account/principal/environment-
  scoped local bytes plus a durable `AttachmentReceipt`. Structured Sync carries
  metadata and operation state, never pending bytes or bearer download URLs.
- `AttachmentResolving` returns local bytes first and only then short-lived,
  currently authorized remote delivery. Gallery, PDF, save/share/print and MCP
  callers do not resolve Firebase URLs themselves.
- Item, Space and Transaction attachment changes use parent-specific typed
  commands behind `AttachmentOperations`. Ordering and primary changes use
  stable reference IDs plus parent revision checks; one non-empty applicable
  collection has exactly one primary.
- MCP attachment ingress applies the same Account/membership authorization and
  lifecycle as the app, with bounded streaming, redirect/network-target checks,
  content sniffing, allowed type/size validation and audited service identity.
- Migration constructs and reconciles a source-reference/source-object graph,
  preserves missing/quarantined outcomes explicitly and treats derivatives as
  rebuildable. Existing local Firebase caches are not target authority.

The target architecture now includes the attachment operations and conceptual
reference/object families needed by these mappings. The exact delete/retention
operation is intentionally absent until O-023 is resolved; backend-neutral does
not mean inventing a destructive operation prematurely.

## Withheld Surfaces

The following remain `characterized`, not `target_mapped`:

- `MCPTOOL-35D04B60563F` — Item reference detach;
- `MCPTOOL-608B84DDBEA5` — Item destructive delete;
- `MCPTOOL-EAA4B71CE0F5` — Space detach plus immediate deletion; and
- `MCPTOOL-9C8591F5294C` — Transaction detach plus immediate deletion.

Their blockers are exactly O-023 and the canonical production reference/object
profile. This is an honest mapping hold, not authorization to preserve current
best-effort deletion behavior.

## Verification

The batch must contain 19 target-relevant surfaces, 15 `target_mapped` entries
and the four named holds. Every mapped entry must have non-empty owner, target
surfaces, security, Sync, migration rule, reconciliation, tests and acceptance
fields. Conversion/capability/query checks and M0 remain required. M1 remains
blocked only by the canonical production profile and O-022 cutover evidence.

This evidence proves reviewed target mapping only. It does not resolve O-023,
approve Supabase/PowerSync, create buckets/tables/policies, access production,
migrate bytes, implement app or MCP behavior, release, or cut over.
