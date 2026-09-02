# EVID-CLIENT-ARCHIVE-001 — Client Archive Operation Contracts

- Timestamp: 2026-09-02
- Class: implementation plan / provider-free Client archive command
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and shipped app remain unchanged
- Claimed target surfaces: `SWIFT-82AD18E41C5C`, `TEST-DAD87DF6C1DB`
- Slice dossier:
  `conversion/implementation-slices/client-archive-operation-contracts.json`
- Verification state: ready locally; executable behavior remains absent until
  the exact comment-only ready commit passes immutable pull-request CI
- Ready scaffold hashes:
  - `ClientArchiveOperation.swift`:
    `9df1f684216df501b959cd2cb31e5116fd50181ddcc16627599bdbf9ac0698e1`
  - `ClientArchiveOperationTests.swift`:
    `4eb6a5c22de6e721c0eba77e626bce6f183e5d698f48065e46f07b002119db93`

## Selection and Scope

After verifying Space-template reference reads, the next Phase 1 dependency
audit selected Client archive as the smallest complete decision-independent
operation. Canonical target authority explicitly says an archived Client is
hidden from new-project selection without deleting history, and that a Client
with Projects or accounting history is archived rather than hard-deleted.

This improves the future target boundary over a generic lifecycle boolean by
binding one stable Client identity and one expected revision to the shared
operation lifecycle. It cannot cascade to Projects, delete or merge a Client,
change any Project's Client, rename current display text or rewrite frozen
documents and accounting evidence. Exactly two target-only comment scaffolds
are claimed in the provider-free core and test roots. The Firebase worktree and
shipped application remain unchanged.

## Why Open Decisions Do Not Block This Slice

- O-025 governs Client merge and Project Client reassignment. This command has
  no replacement Client, Project list, reassignment or merge input.
- Restore/unarchive remains a separate later intent rather than a generic
  caller-controlled lifecycle toggle; this slice invents no restore contract.
- O-024 governs physical Project deletion and is unrelated to this Client-only
  history-preserving archive intent.
- O-026 governs shared reference-data mutation and does not govern Client
  lifecycle.
- A-007/A-016 govern Auth correlation and offline authorization duration. This
  contract carries typed Account/actor evidence but performs no authorization
  or physical offline access.
- A-003/A-004/A-015 and physical verification govern provider schema, Sync and
  durable/optimistic implementation, all excluded here.

## Ready-Gate Contract

The dossier freezes seven exact canonical/conversion/architecture requirements
and requires:

- one stable Client ID, exact Account, actor, operation contract, Operation ID
  and finite client time;
- reuse of the existing typed expected Client revision to derive exactly one
  same-subject `expectedRevision` precondition;
- a typed `ArchiveClient` business command with no arbitrary fields, lifecycle
  boolean, Project/history/name/accounting/delete/merge/restore/reassignment
  input or backend type;
- reuse of the shared operation envelope, fingerprint, receipt and exact replay
  semantics rather than a Client-specific queue/result lifecycle;
- canonical decode-through-validation and atomic changed-scope/payload/
  precondition/subject/fingerprint/receipt refusal;
- one narrow provider-free operation port plus deterministic reference/failure
  adapter tests; and
- permanent separation between local command validity and later trusted
  membership/Client/revision authorization and history-preserving apply.

Postgres, handlers, Data API grants, RLS, Sync Streams, physical local
persistence, app/MCP, migration, observability and feature activation are
explicit nonapplicabilities.

## Dependency Evidence

The preceding Space-template verification-document checkpoint is immutable:
exact commit `58a7c406a0f35d510b57cbb3604623a9aea8c1bd` passed Actions run
`33636886779`, with conversion traceability in 8 seconds and the isolated target
environment in 2 minutes 25 seconds.

The source/caller/authority mapping is already reviewed in
`EVID-CAPABILITY-PROJECT-REFERENCE-001` and
`EVID-M2-PROJECT-REFERENCE-001`. It separates Client identity/lifecycle from
Project relationship correction and records O-025 rather than treating a copied
name, generic update or cascade as target authority.

## Ready-Gate Verification

The two comment-only surfaces are acknowledged through the reviewed Project/
Client/reference batch and are `target_mapped`. The dossier has no blocker;
every requirement is reciprocally covered by domain, offline-restart, offline-
rejection, operation-idempotency and exact-commit operational obligations.

The synchronized ledger records 773 surfaces, including 758 currently
discovered surfaces, 347 mapped-or-later target-relevant surfaces, 164 residual
surfaces and 43 validated blockers. Thirty-four slices claim 89 target surfaces
and 72 are implementation-advanced. M0 passes. M1 and M2 retain exactly their
expected 2 and 164 prerequisite blockers, with zero structural errors and only
the same three explained retired-path warnings.

The complete local ready gate passes:

- conversion sync/check/report and capability/query/residual controls;
- M0, with M1/M2 retaining the expected 2/164 prerequisite blockers;
- all 144 existing target tests in 33 suites while both scaffolds remain
  comment-only;
- target environment and generated app/MCP contract checks;
- macOS and generic iOS Simulator staging builds; and
- clean diff formatting.

Passing immutable exact-ready-commit CI may authorize only the bounded
provider-free implementation named here.

## Permanent Limits

This ready plan cannot:

- visibly or authoritatively archive, restore, merge or delete a Client;
- create or modify a local/server Client row, lifecycle state or audit field;
- archive/reassign a Project or rewrite a current/frozen Client-name display;
- prove that Projects, Transfers, documents or accounting history remain stored
  after authoritative archive;
- authorize Account membership, Client existence/revision or archive rights;
- define a Postgres table, handler, grant, RLS policy, Sync Stream or optimistic
  projection;
- wire a current/target app action, project picker, MCP tool, transport or
  catalog entry;
- transform or reconcile source Client identity/archive state; or
- authorize hosted resources, deployment, production migration, release or
  cutover.

No production read or mutation, shipped-app implementation, provider
connection, hosted resource, migration, deployment or cutover occurred.
