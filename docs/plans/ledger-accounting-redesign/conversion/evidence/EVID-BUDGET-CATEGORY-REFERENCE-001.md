# EVID-BUDGET-CATEGORY-REFERENCE-001 — Budget Category Reference Read Contracts

- Timestamp: 2026-09-02
- Class: implementation planning / provider-free budget-category reference read
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and shipped app remain unchanged
- Claimed target surfaces: `SWIFT-8351FACDBE06`, `TEST-61925915E20E`
- Slice dossier:
  `conversion/implementation-slices/budget-category-reference-read-contracts.json`
- Verification state: ready; behavioral implementation has not started
- Ready scaffold hashes:
  - `BudgetCategoryReferenceData.swift`:
    `1a92b7ba856a4f6a204a2d671996f913b4f671025512a80ecc65066d3243e053`
  - `BudgetCategoryReferenceDataTests.swift`:
    `ca36532c54ee7627aef3a93cf519a846a571f9d21d6a6c2f139a4211ad050f89`

## Selection and Scope

After verifying Project archive, the Phase 1 dependency audit selected the
budget-category reference read boundary. Project setup, Project category
configuration, Transaction/Item routing and fee-aware presentation all need
stable category identity and canonical type before their later operations can
be implemented safely.

The reviewed capability contract separates reference reads from shared
reference-data administration. O-026 blocks Create/Update/Archive/Reorder
category mutations but does not block an already-authorized local snapshot.
Exactly two target-only comment scaffolds are claimed in the provider-free core
and test roots. Existing app/MCP behavior, schema, Auth, RLS, Sync, migration and
production remain unadvanced.

## Why Open Decisions Do Not Block This Slice

- O-026 governs who may administer shared reference data. This slice has no
  mutation, capability grant or administration UI.
- Financial-access policy is not implemented locally. The snapshot represents
  only rows already authorized for the requesting principal and does not expose
  hidden fee-category rows or counts.
- Project allocation configuration remains a separate later conflict-aware
  operation; this slice cannot enable, disable or allocate a category.
- A-007/A-016 govern Auth correlation and offline authorization duration. This
  contract carries one Account scope but performs no authorization or physical
  offline access.
- A-003/A-004/A-015 and physical verification govern provider schema, Sync and
  durable implementation, all excluded here.

## Ready-Gate Contract

The dossier freezes seven exact product/conversion/architecture requirements
and requires:

- stable Account/category identity, bounded display name, canonical general/
  itemized/fee kind, active/archived lifecycle, system flag, explicit overall-
  budget exclusion, unique presentation order and revision;
- derived Project-configuration eligibility only for active non-system visible
  rows, with itemized eligibility additionally requiring the itemized kind;
- one Account-scoped snapshot over the shared local-list readiness contract,
  where empty, partial and stale evidence remain distinct;
- exact refusal for invalid names/types/revisions, cross-Account rows, duplicate
  identities, case-insensitive names and presentation orders;
- one narrow provider-free read port plus deterministic reference/failure port
  tests;
- canonical decode-through-validation and byte-identical restart; and
- permanent separation between snapshot validity and later trusted membership,
  financial-visibility and download authorization.

Postgres, handlers, Data API grants, RLS, Sync Streams, physical local
persistence, reference mutations, Project allocations, app/MCP, migration,
observability and feature activation are explicit nonapplicabilities.

## Ready-Gate Verification

The two comment-only surfaces are acknowledged through the reviewed Project/
Client/reference batch and are `target_mapped`. The dossier has no blocker;
every requirement is reciprocally covered by domain, offline-restart, offline-
rejection, exact-port and exact-commit operational obligations.

The ready checkpoint ran from the dedicated Supabase worktree on 2026-09-02:

- conversion sync/check and capability/query/residual controls — pass at 753
  recorded / 738 discovered surfaces and 327 mapped / 164 residual / 43
  blockers, with only the three documented retired-path warnings;
- M0 — pass; M1/M2 — expected blocks at the unchanged 2/164 prerequisites;
- `swift test --package-path LedgeriOS` — pass, the existing 104 tests in 23
  suites; the two scaffolds intentionally add no executable category-reference
  test;
- target environment and generated-contract checks — pass;
- macOS and generic iOS Simulator staging builds — pass; and
- `git diff --check` — pass.

Passing this ready gate authorizes only the bounded provider-free implementation
named in the dossier.

## Permanent Limits

This ready plan cannot:

- authorize, download or reveal a budget category or hidden fee-category count;
- create, update, archive, reorder or delete a category;
- configure a Project category or allocation, calculate budget values or choose
  a default category;
- create or modify a local/server category row, visibility rule or audit field;
- define a Postgres table, handler, grant, RLS policy, Sync Stream or optimistic
  projection;
- wire a current/target app form, MCP tool/resource, transport or catalog entry;
- transform, default, deduplicate or reconcile source category data; or
- authorize hosted resources, deployment, production migration, release or
  cutover.

No production read or mutation, shipped-app implementation, provider
connection, hosted resource, migration, deployment or cutover occurred.
