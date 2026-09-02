# EVID-PROJECT-CATEGORY-CONFIGURATION-001 — Project Category Configuration Read Contracts

- Timestamp: 2026-09-02
- Class: implementation planning / provider-free Project category configuration read
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and shipped app remain unchanged
- Claimed target surfaces: `SWIFT-E084EBB4EBFF`, `TEST-DB57E9433EB6`
- Slice dossier:
  `conversion/implementation-slices/project-category-configuration-read-contracts.json`
- Verification state: ready; behavioral implementation has not started
- Ready scaffold hashes:
  - `ProjectCategoryConfigurationData.swift`:
    `625c7b4209814892595793bb57ede2c57c9f5b6bee925feaadfcd952f2cc2cf4`
  - `ProjectCategoryConfigurationDataTests.swift`:
    `7717c1c54f2011989105a08e80e98d9d587df06277d35530957a5ffb987b35b8`

## Selection and Scope

After verifying the budget-category reference read boundary, the Phase 1
dependency audit selected the Project category configuration read boundary.
Project setup already preserves the complete selected category set, and the
verified category reference contract supplies stable category identity/type/
lifecycle/order. The next safe read outcome combines those facts without
calculating the redesigned budget or creating a configuration writer.

The source query/model mappings already name `ProjectCategoryConfigurationSnapshot`
and `ProjectCategoryAllocationSnapshot`. Exactly two new target-only comment
scaffolds are claimed in the provider-free core/test roots. The broader current
MCP query and source model remain `target_mapped`; they are not treated as
replaced until concrete schema/authorization/Sync/app/MCP/migration behavior is
implemented and verified.

## Why Open Decisions Do Not Block This Slice

- O-026 governs shared reference-data mutation authority. This slice has no
  category or Project-configuration command, capability grant or administration
  UI.
- Financial-access policy is not implemented locally. The snapshot contains
  only category/allocation values already authorized for the requesting
  Principal and exposes no hidden rows or counts.
- The redesigned contribution sources, collection transfers, Fees and budget
  totals are outside this slice; it cannot calculate a spent/progress value or
  import the current cached/Transaction-only summary as authority.
- A-007/A-016 govern Auth correlation and offline authorization duration. This
  contract carries exact Account/Project scope but performs no authorization or
  physical offline access.
- A-003/A-004/A-015 and physical verification govern provider schema, Sync and
  durable implementation, all excluded here.

## Ready-Gate Contract

The dossier freezes seven exact product/conversion/architecture requirements
and requires:

- exact Account, Project and visible category identity plus one monotonic
  configuration revision;
- separate no-relationship, enabled-without-allocation, explicit-zero and
  positive exact-Money states;
- explicit relationship-evidence-incomplete state rather than converting an
  incomplete local working set into a disabled category;
- preserved category name/type/lifecycle/system/exclusion/order/revision from
  the verified category-reference contract without granting selection or write
  authority;
- one Project-scoped snapshot over the shared local-list readiness contract,
  where authorized empty, partial and stale evidence remain distinct;
- exact refusal for negative/malformed allocation, cross-Account categories,
  duplicate identities/names/orders, hidden-count mismatch and contradictory
  completeness state; and
- one narrow provider-free Account/Project read port with canonical
  decode-through-validation and byte-identical restart.

Postgres, handlers, Data API grants, RLS, Sync Streams, physical local
persistence, budget arithmetic, category/Project configuration mutation,
app/MCP, migration, observability and feature activation are explicit
nonapplicabilities.

## Ready-Gate Verification

The two comment-only surfaces are acknowledged through the reviewed Project/
Client/reference batch and are `target_mapped`. The dossier has no blocker;
every requirement is reciprocally covered by domain, offline-restart, offline-
rejection, exact-port and exact-commit operational obligations.

The ready checkpoint passed from the dedicated Supabase worktree:

- conversion sync/check and capability/query/residual controls;
- M0, with M1/M2 retaining their expected prerequisite blockers;
- the existing complete target package suite (108 tests in 24 suites), while
  the two scaffolds add no executable configuration test;
- target environment and generated-contract checks;
- macOS and generic iOS Simulator staging builds; and
- `git diff --check`.

The synchronized ledger records 755 surfaces, including 740 discovered and 15
manual surfaces. It reports 329 mapped target-relevant surfaces, 164 residual
surfaces and 43 validated blockers. M0 passes; M1 and M2 retain exactly their
expected 2 and 164 blockers. Conversion, capability, query, residual, target-
environment and generated-contract controls pass. The complete package suite,
macOS staging build and generic iOS Simulator staging build pass without adding
executable behavior to either comment-only scaffold.

Passing this ready gate authorizes only the bounded provider-free implementation
named in the dossier.

## Permanent Limits

This ready plan cannot:

- authorize, download or reveal a category, allocation or hidden row/count;
- create, update, archive, reorder or delete a category;
- configure a Project category/allocation or calculate paid/unpaid/recognized
  budget values;
- create or modify a local/server Project-category row or visibility rule;
- define a Postgres table, handler, grant, RLS policy, Sync Stream or optimistic
  projection;
- wire a current/target app form, MCP tool/resource, transport or catalog entry;
- transform, default, deduplicate or reconcile source category/allocation data;
  or
- authorize hosted resources, deployment, production migration, release or
  cutover.

No production read or mutation, shipped-app implementation, provider
connection, hosted resource, migration, deployment or cutover occurred.
