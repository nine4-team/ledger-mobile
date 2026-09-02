# EVID-PROJECT-SETUP-001 — Project Setup Operation Contracts

- Timestamp: 2026-09-01
- Class: implementation planning / provider-free Project setup command
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and shipped app remain unchanged
- Claimed target surfaces: `SWIFT-C1C5DFC81448`, `TEST-99B322EB971A`
- Slice dossier:
  `conversion/implementation-slices/project-setup-operation-contracts.json`
- Verification state: ready; behavioral implementation has not started
- Ready scaffold hashes:
  - `ProjectSetupOperation.swift`:
    `21cbed117d3b60dfaad58c8959b63fec532adad7a5adb8d1917634c9c3e40eb1`
  - `ProjectSetupOperationTests.swift`:
    `67a4b1320bb3fb409c01ab4362005035f15fefd086308b03f35948830749c647`

## Selection and Scope

After verifying Client creation, the Phase 1 dependency audit selected Project
setup as the next smallest user-meaningful operation. D-006 and the canonical
Client spec settle one stable Account-scoped Client relationship. The reviewed
Project/reference-data capability contract settles one observable Project setup
payload containing stable Project identity, existing/new Client selection,
Project name/description and the complete exact category-selection state.

This deliberately improves the shipped partial-write flow: Project and category
intent is one operation instead of a Project write followed by independent
category writes, and an omitted allocation stays null rather than silently
becoming zero. Category identity is stable, selection order is not business
meaning, empty selection remains representable, and supplied allocation Money
is exact and non-negative. The target does not inherit the source UI's arbitrary
32-bit maximum.

Exactly two target-only comment scaffolds are claimed in the provider-free core
and test roots. Existing app/MCP Project mechanics, schema, Auth, RLS, Sync,
migration and production remain unadvanced.

## Why Open Decisions Do Not Block This Slice

- O-025 governs correcting an existing Project's Client and merging Clients.
  This slice only creates a new Project with one selected/preallocated Client.
- O-024 governs physical Project deletion; the command creates but never
  deletes, archives or edits a Project.
- O-026 governs who may mutate shared category definitions and other reference
  data. This command only records selected stable category IDs. Later trusted
  server authorization remains mandatory; no category definition is mutated.
- O-023 governs attachment reference/byte retention. Hero media is absent from
  CreateProject and remains an independently durable attachment lifecycle.
- A-007/A-016 govern Auth correlation and offline authorization duration. This
  contract carries one typed actor/Account but performs no authorization or
  physical offline access.
- A-003/A-004/A-015 and physical verification govern provider schema, Sync and
  optimistic/durable implementation, all excluded here.

## Ready-Gate Contract

The dossier freezes eight exact canonical/conversion/architecture requirements
and requires:

- one preallocated Project ID and exact Account, actor, operation contract,
  Operation ID and finite client time;
- an explicit existing Client ID or preallocated new Client ID plus validated
  display name, with text never used to select an existing identity;
- one validated Project display name, exact optional description and a complete
  canonical duplicate-free category selection set;
- exact separation among category absence, selected null allocation and
  selected explicit zero Money, with non-negative supplied amounts;
- a typed `CreateProject` business command with no arbitrary fields, copied
  Client text, category-definition mutation, media, Project lifecycle/
  correction or backend type;
- reuse of the shared operation envelope, fingerprint, receipt and exact replay
  semantics rather than a Project-specific queue/result lifecycle;
- canonical decode-through-validation and atomic changed-scope/payload/subject/
  precondition/fingerprint/receipt refusal; and
- one narrow provider-free operation port plus deterministic reference/failure
  adapter tests.

Postgres, handlers, Data API grants, RLS, Sync Streams, physical local
persistence, hero media, app/MCP, migration, observability and feature
activation are explicit nonapplicabilities.

## Ready-Gate Verification

The two comment-only surfaces are acknowledged through the reviewed Project/
Client/reference batch and are `target_mapped`. The dossier has no blocker;
every requirement is reciprocally covered by domain, offline-restart, offline-
rejection, operation-idempotency and exact-commit operational obligations.

The ready checkpoint ran from the dedicated Supabase worktree on 2026-09-01:

- conversion sync/check and capability/query/residual controls — pass at 749
  recorded / 734 discovered surfaces and 323 mapped / 164 residual / 43
  blockers, with only the three documented retired-path warnings;
- M0 — pass; M1/M2 — expected blocks at the unchanged 2/164 prerequisites;
- `swift test --package-path LedgeriOS` — pass, the existing 96 tests in 21
  suites; the two scaffolds intentionally add no executable Project-setup test;
- target environment and generated-contract checks — pass;
- macOS and generic iOS Simulator staging builds — pass; and
- `git diff --check` — pass.

Passing this ready gate authorizes only the bounded provider-free implementation
named in the dossier.

## Permanent Limits

This ready plan cannot:

- create a local/server Project, Client, category or allocation row;
- authorize Account membership, an existing/new Client, or selected categories;
- create, edit, archive, reorder or otherwise mutate category definitions;
- edit, reassign, archive or physically delete a Project or merge a Client;
- attach, upload, resolve, order, detach or delete hero media;
- define a Postgres table, handler, grant, RLS policy, Sync Stream or optimistic
  projection;
- wire a current/target app form, MCP tool, transport or catalog entry;
- transform or reconcile source Projects, free-text Client names, categories or
  media; or
- authorize hosted resources, deployment, production migration, release or
  cutover.

No production read or mutation, shipped-app implementation, provider
connection, hosted resource, migration, deployment or cutover occurred.
