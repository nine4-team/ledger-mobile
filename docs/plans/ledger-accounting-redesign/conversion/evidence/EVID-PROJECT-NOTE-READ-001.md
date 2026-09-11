# EVID-PROJECT-NOTE-READ-001 — Project Note Read Contracts

- Timestamp: 2026-09-02
- Class: implementation planning / provider-free Project-note read domain
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and shipped app remain unchanged
- Claimed target surfaces: `SWIFT-B3DBE3375ACE`, `TEST-E8DC4AE52ED7`
- Slice dossier:
  `conversion/implementation-slices/project-note-read-contracts.json`
- Verification state: verified; all five obligations pass at exact
  implementation commit `b421f41948a23fa0918b5e33c0a4d436e5b87080`
  and immutable Actions run `33618364544`
- Implementation hashes:
  - `ProjectNoteData.swift`:
    `f9ac710c8c031f23178b8a4ab064a3243ed2c2d6ff694de95044fdd8a14c1f18`
  - `ProjectNoteDataTests.swift`:
    `572fc8cb8ace9e690fea913754f96a33427f7cc0fc3257ade4680d75df11db31`

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

Exact ready commit `58319f2a89a81dd39dd8d624dba481b7d5b17abe`
passed immutable GitHub Actions run `33616981355`: conversion traceability
passed in 7 seconds and the isolated-target job passed in 2 minutes 22 seconds
with all 120 then-existing tests, graph/generated-contract checks, macOS and
generic iOS Simulator builds and clean tracked artifacts.

## Implemented Contract

- `ProjectNoteID`, `ProjectNoteText`, `ProjectNoteCreatorDisplayName` and
  `ProjectNoteSource` provide provider-free stable identity and validated
  visible values.
- `ProjectNoteSnapshot` binds exact Account/Project/note scope to visible text
  or non-content-bearing tombstone state, immutable creator/creation/source
  evidence, an explicit revision and optional paired last-editor/time evidence.
  Finite creation, edit and deletion times must be causally ordered.
- `ProjectNotePageRequest` enforces a 1...200 bound, exact Account/Project scope,
  an optional structured `(createdAt,id)` continuation boundary and a derived
  canonical query fingerprint with no provider token.
- `ProjectNotePage` reuses `ListLocalSnapshot`, refuses fingerprint/scope/
  duplicate/order/limit/count/cursor/readiness contradictions and exposes
  complete Project-history truth independently from bounded-page completeness.
- `ProjectNoteQuerying` is the narrow typed local read port. Stable failures
  reveal no hidden note, actor, membership, provider or production detail.

## Local Implementation Verification

Four focused deterministic tests pass. They prove active, edited and tombstoned
note shape; newest-first same-time ID ordering; structured continuation;
complete, partial, stale and authoritative-empty canonical restart; stable
refusal of malformed text/source/audit/scope/identity/order/limit/fingerprint/
cursor/readiness evidence; exact request matching; and no false page from a
failing read port.

The complete local gate passes with all 124 target tests in 28 suites, target
environment isolation, generated app/MCP contracts, macOS and generic iOS
Simulator staging builds, conversion/capability/query/residual controls, M0 and
clean diff formatting. M1/M2 retain exactly their expected 2/164 blockers.

Exact implementation commit `b421f41948a23fa0918b5e33c0a4d436e5b87080`
passed immutable GitHub Actions run `33618364544`: conversion state and
traceability passed in 12 seconds; the isolated target environment passed in 2
minutes 21 seconds with all 124 tests, target graph/generated-contract controls,
macOS and generic iOS Simulator staging builds, and clean tracked artifacts. All
five obligations and exactly the two Project-note target surfaces are therefore
verified.

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
