# EVID-CLIENT-CREATION-001 — Client Creation Operation Contracts

- Timestamp: 2026-09-01
- Class: implementation planning / provider-free Client creation command
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and released Firebase app remain unchanged
- Claimed target surfaces: `SWIFT-3B3E02643603`, `TEST-E42E9E6D7B28`
- Slice dossier:
  `conversion/implementation-slices/client-creation-operation-contracts.json`
- Verification state: verified at exact implementation commit
  `3b837af34bbbde9e7c4b6707f6366dc88d236957`
- Implementation hashes:
  - `ClientCreationOperation.swift`:
    `bcda18195d249e5c852ef7125c0151a83eaf294c5f324d4b656bbb48cbb1b78f`
  - `ClientCreationOperationTests.swift`:
    `11866971537ccb6d043ab034acc8f1a95222fc642ed4d9dc7c6f9dbdcb91df28`

## Selection and Scope

After verifying the attachment-capture receipt boundary, the Phase 1 dependency
audit selected Client creation as the smallest next user-meaningful operation.
D-006 and the canonical Client spec already settle stable Account-scoped Client
identity, the minimal current display name and the rule that text never owns a
relationship or authorization. A typed CreateClient command is required before
Project setup can select or create a Client without restoring free-text
`project.clientName` as authority.

Exactly two target-only comment scaffolds are claimed in the provider-free core
and test roots. Existing Firebase Project/Client mechanics, current app/MCP
tools, Project creation, schema, Auth, RLS, Sync, migration and production remain
unadvanced.

## Why Open Decisions Do Not Block This Slice

- O-025 governs Client correction/merge and Project reassignment. This slice
  creates one new stable Client only and exposes none of those operations.
- O-024 governs persisted Project deletion; Client creation creates no Project.
- O-026 governs shared reference-data mutation and does not control a Client
  identity command.
- A-007/A-016 govern Auth correlation and offline authorization duration. This
  contract carries one typed actor/Account but performs no authorization or
  physical offline access.
- A-003/A-004/A-015 and physical verification govern provider schema, Sync and
  optimistic/durable implementation, all excluded here.

## Ready-Gate Contract

The dossier freezes six exact canonical/architecture requirements and requires:

- one preallocated stable Client ID, exact Account, actor, operation contract,
  Operation ID, finite client time and validated display name;
- equal display names to remain distinct when Client IDs differ;
- a typed `CreateClient` business command with no generic fields, copied Project
  Client text, lifecycle correction or backend type;
- reuse of the shared operation envelope, fingerprint, receipt and exact replay
  semantics rather than a Client-specific queue/result lifecycle;
- canonical decode-through-validation and atomic changed-scope/payload/subject/
  precondition/fingerprint/receipt refusal;
- one narrow provider-free operation port plus deterministic reference/failure
  adapter tests; and
- permanent separation between local command validity and later trusted
  membership/capability authorization.

Postgres, handlers, Data API grants, RLS, Sync Streams, physical local
persistence, media, app/MCP, migration, observability and feature activation are
explicit nonapplicabilities.

## Ready-Gate Verification

The two comment-only surfaces are acknowledged through the reviewed Project/
Client/reference batch and are `target_mapped`. The dossier has no blocker;
every requirement is reciprocally covered by domain, offline-restart, offline-
rejection, operation-idempotency and exact-commit operational obligations.

The ready checkpoint ran from the dedicated Supabase worktree on 2026-09-01:

- conversion sync/check and capability/query/residual controls — pass at 747
  recorded / 732 discovered surfaces and 321 mapped / 164 residual / 43
  blockers, with only the three documented retired-path warnings;
- M0 — pass; M1/M2 — expected blocks at the unchanged 2/164 prerequisites;
- `swift test --package-path LedgeriOS` — pass, the existing 92 tests in 20
  suites; the two scaffolds intentionally add no executable Client test;
- target environment and generated-contract checks — pass;
- macOS and generic iOS Simulator staging builds — pass; and
- `git diff --check` — pass.

Passing this ready gate authorizes only the bounded provider-free implementation
named in the dossier.

## Implemented Contract

`ClientCreationOperation.swift` now provides:

- `ClientCreationDraft`, which binds one preallocated Client ID and validated
  display name to exact Account, actor, operation-contract and finite capture
  time evidence;
- `CreateClientPayload`, which contains only the stable Client identity and
  display name and gives text no relationship or authorization meaning;
- `CreateClientCommand`, whose public construction creates a precondition-free
  shared `OperationEnvelope`, derives the exact Client subject and operation
  fingerprint, and whose decoder revalidates every duplicated binding instead
  of trusting serialized derived evidence;
- exact `OperationReceipt` validation for the command's Operation ID;
- the narrow `ClientCreationOperating` provider-free port; and
- a closed stable failure taxonomy for invalid time, scope/actor/contract/
  payload/precondition/subject/fingerprint/receipt mismatches, malformed command
  evidence and local acceptance failure.

The implementation reuses `OperationJournal` only through a deterministic test
adapter. It does not claim physical durable storage, server authorization,
authoritative Client creation or synchronized visibility.

## Local Implementation Verification

The implementation checkpoint ran from the dedicated Supabase worktree on
2026-09-01:

- `swift test --package-path LedgeriOS --filter ClientCreationOperationTests`
  — pass, four focused tests;
- `swift test --package-path LedgeriOS` — pass, all 96 tests in 21 suites;
- target environment and generated-contract checks — pass;
- macOS and generic iOS Simulator staging builds — pass;
- conversion sync/check/report, capability/query/residual controls and M0 —
  pass at 747 recorded / 732 discovered surfaces and 321 mapped / 164 residual /
  43 blockers, with only the three documented retired-path warnings; and
- M1/M2 — expected blocks at the unchanged 2/164 prerequisites.

`CLIENTCREATE-TEST-001` through `-004` therefore pass with this evidence.

## Immutable Exact-Commit Verification

GitHub Actions run
[`33595993615`](https://github.com/nine4-team/ledger-mobile/actions/runs/33595993615)
verified exact implementation commit
`3b837af34bbbde9e7c4b6707f6366dc88d236957` on 2026-09-01:

- `Conversion state and traceability` — pass in 10 seconds;
- `Isolated target environment` — pass in 1 minute 50 seconds;
- target dependency/provider/source-project isolation and generated app/MCP
  contracts — pass;
- all 96 target tests in 21 suites — pass;
- macOS and generic iOS Simulator staging builds — pass; and
- tracked-artifact cleanliness — pass.

`CLIENTCREATE-TEST-005` therefore passes. All five obligations and exactly the
two claimed target-only surfaces are verified. The hosted evidence adds no
server, physical persistence, authorization, provider, migration or production
claim.

## Permanent Limits

This provider-free implementation cannot:

- create a server/local-database Client row or make a Client visible in a query;
- authorize Account membership or choose an authentication provider;
- rename, archive, merge, delete or otherwise correct a Client;
- create, edit, reassign, archive or delete a Project;
- define a Client/Postgres table, handler, grant, RLS policy, Sync Stream or
  optimistic projection;
- wire a current/target app form, picker, MCP tool, transport or catalog entry;
- cluster or import Firebase `clientName` values or claim migration coverage;
  or
- authorize hosted resources, deployment, production migration, release or
  cutover.

No production read or mutation, Firebase implementation, provider connection,
hosted resource, migration, deployment or cutover occurred.
