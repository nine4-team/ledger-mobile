# EVID-PROJECT-ARCHIVE-001 — Project Archive Operation Contracts

- Timestamp: 2026-09-01
- Class: implementation planning / provider-free Project archive command
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and shipped app remain unchanged
- Claimed target surfaces: `SWIFT-10A07B52B82D`, `TEST-756CB57BD6CA`
- Slice dossier:
  `conversion/implementation-slices/project-archive-operation-contracts.json`
- Verification state: ready; behavioral implementation has not started
- Ready scaffold hashes:
  - `ProjectArchiveOperation.swift`:
    `ccb34eadc48d27d994388d893b1b8b8489111a0ab3907f572548a3d42e7c6b78`
  - `ProjectArchiveOperationTests.swift`:
    `7dbcee77d28a2f8e9e508c0977b315e87c3b59f3054d3e0a72c121287b326fdf`

## Selection and Scope

After verifying Project setup, the Phase 1 dependency audit selected Project
archive as the next smallest user-meaningful operation. The reviewed capability
contract defines archive as a distinct, always-safe history-preserving command;
the target mapping already names `ArchiveProjectCommand`, exact expected Project
revision and the shared operation receipt.

This improves the shipped direct `isArchived` toggle by making stale intent and
idempotent retry explicit. It does not copy generic update fields, trust a
caller timestamp or permit a lifecycle boolean to become delete/reassignment.
Exactly two target-only comment scaffolds are claimed in the provider-free core
and test roots. Existing app/MCP behavior, schema, Auth, RLS, Sync, migration
and production remain unadvanced.

## Why Open Decisions Do Not Block This Slice

- O-024 governs whether any persisted Project may be physically deleted. This
  command can only archive and has no delete/discard/tombstone input.
- O-025 governs Project Client correction and Client merge. Archive carries no
  Client ID or relationship mutation and preserves the existing relationship.
- O-026 governs shared reference-data mutation and is unrelated to Project
  lifecycle.
- Restore/unarchive remains a separate later command rather than a generic
  caller-controlled lifecycle toggle; this slice does not invent its contract.
- A-007/A-016 govern Auth correlation and offline authorization duration. This
  contract carries one typed actor/Account but performs no authorization or
  physical offline access.
- A-003/A-004/A-015 and physical verification govern provider schema, Sync and
  optimistic/durable implementation, all excluded here.

## Ready-Gate Contract

The dossier freezes seven exact canonical/conversion/architecture requirements
and requires:

- one stable Project ID, exact Account, actor, operation contract, Operation ID
  and finite client time;
- one typed expected Project revision that derives exactly one same-subject
  `expectedRevision` precondition;
- a typed `ArchiveProject` business command with no arbitrary fields, lifecycle
  toggle, Client/name/details/category/media/child/delete/restore input or
  backend type;
- reuse of the shared operation envelope, fingerprint, receipt and exact replay
  semantics rather than a Project-specific queue/result lifecycle;
- canonical decode-through-validation and atomic changed-scope/payload/
  precondition/subject/fingerprint/receipt refusal;
- one narrow provider-free operation port plus deterministic reference/failure
  adapter tests; and
- permanent separation between local command validity and later trusted
  membership/Project/revision authorization and history-preserving apply.

Postgres, handlers, Data API grants, RLS, Sync Streams, physical local
persistence, app/MCP, migration, observability and feature activation are
explicit nonapplicabilities.

## Ready-Gate Verification

The two comment-only surfaces are acknowledged through the reviewed Project/
Client/reference batch and are `target_mapped`. The dossier has no blocker;
every requirement is reciprocally covered by domain, offline-restart, offline-
rejection, operation-idempotency and exact-commit operational obligations.

The ready checkpoint ran from the dedicated Supabase worktree on 2026-09-01:

- conversion sync/check and capability/query/residual controls — pass at 751
  recorded / 736 discovered surfaces and 325 mapped / 164 residual / 43
  blockers, with only the three documented retired-path warnings;
- M0 — pass; M1/M2 — expected blocks at the unchanged 2/164 prerequisites;
- `swift test --package-path LedgeriOS` — pass, the existing 100 tests in 22
  suites; the two scaffolds intentionally add no executable Project-archive
  test;
- target environment and generated-contract checks — pass;
- macOS and generic iOS Simulator staging builds — pass; and
- `git diff --check` — pass.

Passing this ready gate authorizes only the bounded provider-free implementation
named in the dossier.

## Permanent Limits

This ready plan cannot:

- visibly or authoritatively archive, restore or delete a Project;
- create or modify a local/server Project row, lifecycle state or audit field;
- prove that children/accounting/history remain stored after authoritative
  archive;
- authorize Account membership, Project existence/revision or archive rights;
- rename/edit/reassign a Project or change Client/category/media/accounting
  state;
- define a Postgres table, handler, grant, RLS policy, Sync Stream or optimistic
  projection;
- wire a current/target app action, MCP tool, transport or catalog entry;
- transform or reconcile source Project archive state; or
- authorize hosted resources, deployment, production migration, release or
  cutover.

No production read or mutation, shipped-app implementation, provider
connection, hosted resource, migration, deployment or cutover occurred.
