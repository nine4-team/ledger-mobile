# EVID-PROJECT-ITEM-LINK-PRESENTATION-001 — Project Item Link Presentation

- Timestamp: 2026-09-02
- Class: ready gate / provider-free product presentation
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and shipped app remain unchanged
- Claimed target surfaces: `SWIFT-A2FCAF3E6103`, `TEST-F63806A8047A`
- Slice dossier:
  `conversion/implementation-slices/project-item-link-presentation-contracts.json`
- Verification state: verified after every-line primary review, independent
  adversarial review, complete local gates and exact implementation-SHA CI
- Ready scaffold hashes:
  - `ProjectItemLinkPresentation.swift`:
    `f83b017c6902a682f931aee3df6c0441a321103d904da8b62f5dde11e002e971`
  - `ProjectItemLinkPresentationTests.swift`:
    `b0c93bfa0c3e6f177ec74c68e5e78648a067c6701c26c692790b0e9d644b77d4`
- Implemented source hashes:
  - `ProjectItemLinkPresentation.swift`:
    `87c045cde2aefd81c78e456a9474c272283f14bd8e8c53bfd9f78436b081665f`
  - `ProjectItemLinkPresentationTests.swift`:
    `b93321983708579c99bbdfe31c58dcaf35bdbb4cfa1d73ba39303e1e4e566048`

## Independent Scope Preflight

The primary agent and a fresh independent read-only preflight re-read Product
Vocabulary, Accounting-State Rule and Link Flow in the canonical Item creation
spec, the user-facing Inventory model and D-014/D-019/D-020/D-023/D-024. They
approved only a stateless presentation contract. The broader Link flow is
NO-GO because actual routes, Purchase selection/eligibility, acquisition
handling, review effects, correction/relink behavior and persistence intersect
open product decisions.

The preflight further narrowed the safe boundary:

- consume the already verified `ProjectItemAccountingRow` resolution rather
  than re-deriving accounting state;
- project exact `Unaccounted For Items`, `Accounted For Items`, `Link`,
  `Who paid for this Item?`, `Client paid` and `Business paid` text;
- expose exactly the two payer-choice meanings without claiming their display
  order;
- allow Link presentation only for authoritative Unaccounted For rows;
- fail closed for Accounted For and relationship-evidence-incomplete rows;
- treat dismissal as no route, command, mutation or persisted selection; and
- re-derive presentation after canonical accounting-snapshot restart rather
  than serializing transient modal state.

## Frozen Exclusions

The slice cannot define or imply a Client-paid/Business-paid command payload,
Purchase picker or eligibility, review-screen behavior, missing acquisition
evidence, payer hint, Item-creation validation, category/price/Invoice effect,
Accounted-item action, correction/relink, app UI, MCP schema/handler, Postgres,
RLS, PowerSync, Auth/provider, source migration, hosted resource, release,
production access or cutover. O-007/O-015/O-016/O-017/O-021/O-023/O-027/
O-029/O-032/O-034 remain open or owned by later slices.

## Ready Gate

The two claimed implementation paths contain comments only. Five planned
obligations require exact labels and semantic choice membership, fail-closed
accounted/incomplete evidence and forbidden-vocabulary absence, stateless
dismissal plus restart re-projection, and exact-implementation-SHA operational
CI. The ready gate must pass conversion/capability/query/residual/M0 controls,
target isolation/generated contracts, the complete target suite, repeatable
project generation, both staging builds and clean tracked artifacts before any
implementation begins. That complete local ready gate passed: conversion,
capability, query, residual and M0 controls are current; target isolation and
generated app/MCP contracts pass; all 189 existing target tests in 44 suites
pass; two project generations produce the identical project hash; both staging
builds succeed; and tracked artifacts are clean. Immutable CI on the exact
ready commit remains required before implementation. Exact ready commit
`47f8fe0d148de617154e40da22bf02d2b47aefc2` then passed immutable Actions run
`33690917866`: conversion traceability passed in 9 seconds and the isolated
target environment passed in 2 minutes 14 seconds with all 189 existing tests,
generated contracts, both staging builds and clean tracked artifacts.

## Implementation and Review

The implementation changes only the two frozen Swift paths. It projects exact
section labels in the verified snapshot's existing order, returns a Link
descriptor only for a verified `.unaccountedFor` row, exposes the exact action,
question and two payer meanings as an unordered `Set`, and represents dismissal
only as `.noAction`. Accounted and relationship-evidence-incomplete rows fail
through two bounded stable diagnostics. No presentation value is `Codable`, no
new port exists, and no route, command, Purchase identity or mutation can be
constructed from the API.

The primary agent reviewed every implementation/test line. A separate read-only
adversarial reviewer found no P0-P2 defect and one P3 test-hardening issue: the
initial payer-membership assertion compared the descriptor with the same
production constant used to build it. The implementation now derives canonical
membership from `Set(allCases)`, explicitly states that declaration order is not
UI order, and the test independently asserts all cases and descriptor membership
against the literal two-case set. The reviewer reran the focused suite and
confirmed the finding resolved with no remaining issue.

Four focused tests and all 193 target tests in 45 suites pass. Target isolation,
generated app/MCP contracts, repeatable project generation and both staging
builds also pass locally. Conversion synchronization, capability/query/
residual controls and M0 were rerun after status/hash reconciliation. The
exact implementation commit
`d7f4286be2a2fe7f4a8c8e7d59a59547114e47e4` passed immutable Actions run
`33691932385`: conversion traceability passed in 10 seconds and the isolated
target environment passed in 2 minutes 19 seconds with all 193 tests in 45
suites, generated contracts, both staging builds and clean tracked artifacts.
The slice is therefore verified.

## Permanent Limits

Verified status proves only the bounded provider-free contract with synthetic
evidence and the recorded local/CI gates. It proves no
physical persistence, authorization, synchronization, database policy, Link
behavior, app/MCP behavior, migration reconciliation, hosted resource,
production behavior, release or cutover.
