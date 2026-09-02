# EVID-CLIENT-RENAME-001 — Client Rename Operation Contracts

- Timestamp: 2026-09-02
- Class: implementation planning / provider-free Client rename command
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and shipped app remain unchanged
- Claimed target surfaces: `SWIFT-9CB51D74D41C`, `TEST-D1C8EFBDFDDE`
- Slice dossier:
  `conversion/implementation-slices/client-rename-operation-contracts.json`
- Verification state: ready; behavioral implementation has not started
- Ready scaffold hashes:
  - `ClientRenameOperation.swift`:
    `f39db0f014a16f919717f2ff2b5e9039d6860fde300df8594270e19aa3eae4c4`
  - `ClientRenameOperationTests.swift`:
    `b2e411c67e491db94b79bfe04c6327ac91823b1d893b170960092bb26ef0e512`

## Selection and Scope

After verifying Project category configuration reads, the remaining Phase 1
Project/Client/reference dependency audit selected Client rename. Stable Client
identity, Client creation and Account-scoped Client/Project directory reads are
already verified. The canonical target spec explicitly separates mutable Client
display text from identity and requires frozen paid/report/history snapshots to
remain unchanged.

Client archive was not selected: its behavior when active Projects exist remains
part of the proposed O-024/O-025 lifecycle packet. Client merge and Project
reassignment also remain gated by O-025. This slice can therefore express only
one expected-revision Client display-name intent without deciding any of them.

Exactly two target-only comment scaffolds are claimed in the provider-free core
and test roots. No current app/MCP surface is treated as replaced until concrete
schema, authorization, Sync, UI/MCP and migration behavior is implemented and
verified.

## Why Open Decisions Do Not Block This Slice

- D-006 settles stable Account-scoped Client identity; the canonical Client spec
  says names are mutable display values and current Project display resolves
  through Client identity.
- O-024/O-025 govern deletion/archive dependency policy, Client merge and
  Project reassignment. The rename payload cannot express any of them.
- Frozen Invoice, report, paid-history and audit snapshots are excluded from the
  payload. The command cannot enumerate or rewrite them.
- A-007/A-016 govern Auth correlation and offline authorization duration. This
  command carries an actor/Account binding but performs no authorization or
  physical offline access.
- A-003/A-004/A-015 and physical verification govern provider schema, Sync and
  durable implementation, all excluded here.

## Ready-Gate Contract

The dossier freezes six exact product/conversion/architecture requirements and
requires:

- one stable ClientID inside one immutable Account plus one validated new
  display value;
- exact separation from Project client text, Client create/archive/merge,
  Project reassignment and every frozen historical display snapshot;
- one typed expected Client revision on the exact Client subject;
- the shared Account/actor/contract/Operation/time/fingerprint/receipt lifecycle
  with canonical decode-through-validation and byte-identical restart;
- atomic refusal for invalid text/time and rebound Account/actor/contract/Client/
  name/revision/payload/subject/precondition/fingerprint/receipt evidence; and
- one narrow provider-free rename port with exact replay and no false receipt.

Postgres, handlers, Data API grants, RLS, Sync Streams, physical local
persistence, authoritative current-Project projection, app/MCP, migration,
observability and feature activation are explicit nonapplicabilities.

## Ready-Gate Verification

The two comment-only surfaces are acknowledged through the reviewed Project/
Client/reference batch and are `target_mapped`. The dossier has no blocker;
every requirement is reciprocally covered by domain, offline-restart, offline-
rejection, reference-port and exact-commit operational obligations.

The ready checkpoint passed from the dedicated Supabase worktree:

- conversion sync/check and capability/query/residual controls;
- M0, with M1/M2 retaining their expected prerequisite blockers;
- the existing complete target package suite (112 tests in 25 suites), while
  the two scaffolds add no executable rename test;
- target environment and generated-contract checks;
- macOS and generic iOS Simulator staging builds; and
- `git diff --check`.

The synchronized ledger records 757 surfaces, including 742 discovered and 15
manual surfaces. It reports 331 mapped target-relevant surfaces, 164 residual
surfaces and 43 validated blockers. M0 passes; M1 and M2 retain exactly their
expected 2 and 164 blockers. Conversion, capability, query, residual, target-
environment and generated-contract controls pass. The complete package suite,
macOS staging build and generic iOS Simulator staging build pass without adding
executable behavior to either comment-only scaffold.

Passing this ready gate authorizes only the bounded provider-free implementation
named in the dossier.

## Permanent Limits

This ready plan cannot:

- rename a visible/local or authoritative Client row;
- authorize the actor, resolve membership/capability, lock/enforce a revision or
  update current Project projections;
- rewrite an Invoice, report, paid-history, audit or migration display snapshot;
- archive/delete/merge a Client, reassign a Project or decide O-024/O-025;
- define a Postgres table, handler, grant, RLS policy, Sync Stream or optimistic
  projection;
- wire a current/target app form, MCP tool/resource, transport or catalog entry;
- transform, cluster, backfill or reconcile source `project.clientName`; or
- authorize hosted resources, deployment, production migration, release or
  cutover.

No production read or mutation, shipped-app implementation, provider
connection, hosted resource, migration, deployment or cutover occurred.
