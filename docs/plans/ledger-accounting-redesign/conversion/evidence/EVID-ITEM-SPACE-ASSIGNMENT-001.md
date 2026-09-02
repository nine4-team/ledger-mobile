# EVID-ITEM-SPACE-ASSIGNMENT-001 — Item-to-Space Assignment Operation Contracts

- Timestamp: 2026-09-02
- Class: ready gate / provider-free Item-to-Space assignment intent
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and shipped app remain unchanged
- Claimed target surfaces: `SWIFT-4B007A00C393`, `TEST-51D893DD949E`
- Slice dossier:
  `conversion/implementation-slices/item-space-assignment-operation-contracts.json`
- Verification state: ready locally; exact ready-commit CI is required before
  executable behavior may be added
- Ready scaffold hashes:
  - `ItemSpaceAssignmentOperation.swift`:
    `beb965fd5d36a8d73fedbd390d0ff26a6e2ae8ae9af459ceb592f7537db09f5b`
  - `ItemSpaceAssignmentOperationTests.swift`:
    `01a7478e70c6f0c0581791a3842e0b0a51262e26e31417d6995ad50a12af95c5`

## Selection and Scope

The next-slice audit selected direct `AssignItemsToSpace` because canonical
Space authority explicitly requires one durable typed same-scope bulk operation,
and current Firebase behavior issues independent Item writes that may partially
apply. The operation is organizational placement only, so it can be frozen
without choosing occurrence persistence, accounting, Storage, Auth, Postgres or
PowerSync implementation.

The bounded slice owns only one nonempty canonical Item/revision set, one stable
destination Space and exact expected revision, one immutable Project-or-
Business-Inventory scope, deterministic conflict preconditions, the shared
operation lifecycle and one narrow port. It cannot clear placement, change Item
scope, archive a Space, create or update accounting evidence, persist rows, or
wire an application/provider.

## Product and Source Cross-Reference

The audit cross-referenced:

- `docs/specs/spaces.md` as canonical target authority for stable Space identity,
  same-scope single/bulk assignment, atomic/idempotent application, separate
  scope-changing Item commands and no Space-driven accounting effect;
- `docs/specs/items.md` and the invoice-centered Item lifecycle specifications
  for stable physical Item identity and the rule that Space is independent from
  accounting state;
- the reviewed Spaces capability dossier for independent-write partial failure,
  generic update, stale-scope and duplicate-listener defects plus the typed
  `AssignItemsToSpace` target boundary;
- `02-domain-and-application-architecture.md`, `03-data-sync-and-offline.md` and
  `04-backend-ports-and-adapters.md` for story-specific commands, exact
  preconditions, restart-safe operation evidence and narrow ports; and
- current Space detail/item-assignment callers, `ItemService`, Firebase model/
  repository behavior and existing Space tests as source behavior evidence.

The current app's fire-and-forget field writes, route strings, display names,
nullable scope pairs and SDK acknowledgements are not target contract authority.

## Why Open Decisions Do Not Block This Slice

- O-037 controls what happens to assigned Items when a Space is archived. This
  command cannot archive or delete a Space and therefore does not resolve or
  bypass that policy.
- O-007/O-015 govern hidden occurrence/accounting provenance. Space placement
  is explicitly non-accounting and the payload contains no occurrence, Invoice,
  Transaction, category, amount, price, payer or acquisition value.
- O-023 governs attachment retention; this command carries no attachment.
- O-032 governs posting/review readiness; this command creates no review state.
- A-003/A-004/A-007/A-016 and hosted staging remain proposed/gated. Typed local
  scope and revision evidence are conflict inputs, never provider authorization.

## Ready-Gate Contract

The dossier freezes eight requirements and five verification obligations. It
requires exact Account/actor/contract/Operation identity; one stable destination
Space and immutable Project-or-Business-Inventory scope; exact Space and Item
revisions; a canonical nonempty duplicate-free Item set; deterministic active/
revision/scope preconditions; atomic stable refusal; byte-identical structured
restart; the shared queued/applied/rejected receipt; and one narrow provider-free
`ItemSpaceAssigning` port.

Postgres, handlers, grants, RLS, Sync Streams, Auth, physical local persistence,
optimistic row mutation, app/MCP, media, accounting, migration, observability,
hosted resources and feature activation are explicit nonapplicabilities.

## Dependency Evidence

The Account-discovery verification-document checkpoint is immutable at commit
`4102365871ba3bde9b42e6132f98a02a1bbd3d69`. GitHub Actions run
`33669255726` passed conversion traceability in 9 seconds and the isolated
target environment in 2 minutes 51 seconds, including all 172 then-existing
target tests, graph/generated-contract checks, both staging builds and clean
tracked artifacts.

The verified exact-money/domain-identity, operation-lifecycle, Space creation/
details/checklist and Project Item accounting-section slices supply stable Item,
Space, Project, Account, Principal, revision, scope and receipt primitives. This
slice neither redefines those meanings nor claims their physical adapters.

## Ready-Gate Verification

The two comment-only surfaces are acknowledged through the reviewed Spaces
batch and are `target_mapped`. The dossier has no blocker; every requirement is
reciprocally covered by domain, offline-restart, offline-rejection,
deterministic port-flow and exact-commit operational obligations.

The complete local ready gate passes with all 172 existing target tests in
40 suites while the two scaffolds remain comment-only, plus target isolation/
generated contracts, both staging builds, repeatable project generation,
conversion/capability/query/residual controls, M0 and clean formatting. M1/M2
retain exactly their expected 2/164 coverage blockers with zero structural
errors. The synchronized ledger records 787 surfaces / 772 discovered, 361
mapped-or-later target-relevant surfaces, 164 residual surfaces and 43 validated
blockers. Forty-one slices claim 103 of 525 target-relevant surfaces; 86 are
implemented or later. No implementation may begin before this ready evidence is
committed, pushed and both immutable CI jobs pass.

## Permanent Limits

This ready evidence cannot verify or authorize Item/Space row mutation, physical
offline durability, optimistic presentation, current membership/authorization,
clear assignment, Item scope movement, Space archive/delete, occurrence or
accounting changes, Postgres/RLS/PowerSync, app/MCP integration, Firebase
migration, hosted resources, production access, release or cutover. The source
Firebase application remains unchanged.
