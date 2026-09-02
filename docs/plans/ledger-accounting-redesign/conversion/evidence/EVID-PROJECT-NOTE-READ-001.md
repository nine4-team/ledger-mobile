# EVID-PROJECT-NOTE-READ-001 — Project Note Read Contracts

- Timestamp: 2026-09-02
- Class: implementation planning / provider-free Project-note read domain
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and shipped app remain unchanged
- Claimed target surfaces: `SWIFT-B3DBE3375ACE`, `TEST-E8DC4AE52ED7`
- Slice dossier:
  `conversion/implementation-slices/project-note-read-contracts.json`
- Verification state: ready; implementation is intentionally absent
- Ready scaffold hashes:
  - `ProjectNoteData.swift`:
    `6b3cf7b3430b34455a2286516484c0a5cbd7a46da4e2d596704ed3a9819b8d5f`
  - `ProjectNoteDataTests.swift`:
    `f37383a496fc9c5a3b2ae6491c9441f2d4ff1e1489df28b7e91efedd198adbc0`

## Selection and Scope

After verifying Project rename, the remaining Phase 1 Project/Client/reference
dependency audit selected bounded Project-note reading as the next smallest
complete user outcome. The current app preserves useful note text, source,
creator display and creation time, while the target contract already requires
stable identity, revision/audit evidence, deterministic ordering and explicit
offline-history readiness.

This slice is intentionally read-only. Add, edit and remove are separate
story-specific operations with authorization, revision, audit and idempotency
requirements. Indexed historical search, source migration and physical local
storage also remain separate slices. Exactly two target-only comment scaffolds
are claimed; no current app, MCP or Firebase surface is treated as replaced.

## Why Open Decisions Do Not Block This Slice

- D-006 settles stable Account/Project identity; names cannot scope notes.
- O-024/O-025 govern Project deletion and Client correction, neither of which
  this read value can express.
- O-026 governs shared reference-data administration, not Project notes.
- The read model can represent already-authorized tombstone evidence without
  choosing which role may add, edit or remove a note.
- A-007/A-016 govern Auth correlation and offline authorization duration. This
  slice performs no authorization or physical offline access.
- A-003/A-004/A-015 and physical verification govern provider schema, Sync and
  durable implementation, all excluded here.

## Ready-Gate Contract

The dossier freezes seven exact product/conversion/architecture requirements
and requires:

- one stable Account/Project/note identity with validated visible text and
  stable source;
- immutable creator/creation evidence, explicit revision, paired edit audit and
  non-content-bearing tombstone evidence with finite ordered times;
- bounded newest-first `(createdAt, id)` pages with structured continuation;
- exact query identity, already-authorized visible counts and explicit complete
  versus incomplete Project-history truth;
- canonical decode-through-validation and atomic scope/order/audit/cursor/
  readiness refusal; and
- one narrow provider-free `ProjectNoteQuerying` port.

Postgres, handlers, Data API grants, RLS, Sync Streams, physical local
persistence, note mutations, app/MCP, indexed search, migration, observability
and feature activation are explicit nonapplicabilities.

## Ready-Gate Verification

The two comment-only surfaces are acknowledged through the reviewed Project/
Client/reference batch and are `target_mapped`. The dossier has no blocker;
every requirement is reciprocally covered by domain, offline-restart, offline-
rejection, reference-port and exact-commit operational obligations.

The ready checkpoint passed from the dedicated Supabase worktree:

- conversion sync/check and capability/query/residual controls;
- M0, with M1/M2 retaining their expected prerequisite blockers;
- all 120 existing target tests in 27 suites while the two scaffolds contain no
  executable Project-note behavior;
- target environment and generated-contract checks;
- macOS and generic iOS Simulator staging builds; and
- `git diff --check`.

The synchronized ledger records 761 surfaces, including 746 currently
discovered. It reports 335 of 499 target-relevant surfaces mapped or later, 164
residual surfaces and 43 validated blockers. M0 passes; M1 and M2 retain exactly
their expected 2 and 164 blockers. Conversion, capability, query, residual,
target-environment and generated-contract controls pass. The complete package
suite, macOS staging build and generic iOS Simulator staging build pass without
adding executable behavior to either comment-only scaffold.

Passing this ready gate authorizes only the bounded provider-free implementation
named in the dossier.

## Permanent Limits

This ready plan cannot:

- authorize, add, edit, remove, search or physically persist a note;
- decide mutation roles, server-owned audit assignment or tombstone retention;
- define a Postgres table/index, handler, grant, RLS policy, Sync Stream or
  optimistic projection;
- wire the Notes tab, Project context/service, MCP tools, transport or catalog;
- decode, merge, deduplicate, quarantine or reconcile Firebase embedded/nested
  notes; or
- authorize hosted resources, deployment, production migration, release or
  cutover.

No production read or mutation, shipped-app implementation, provider
connection, hosted resource, migration, deployment or cutover occurred.
