# EVID-PROJECT-ITEM-LINK-PRESENTATION-001 — Project Item Link Presentation

- Timestamp: 2026-09-02
- Class: ready gate / provider-free product presentation
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and shipped app remain unchanged
- Claimed target surfaces: `SWIFT-A2FCAF3E6103`, `TEST-F63806A8047A`
- Slice dossier:
  `conversion/implementation-slices/project-item-link-presentation-contracts.json`
- Verification state: ready; implementation and exact-commit verification are
  intentionally withheld
- Ready scaffold hashes:
  - `ProjectItemLinkPresentation.swift`:
    `f83b017c6902a682f931aee3df6c0441a321103d904da8b62f5dde11e002e971`
  - `ProjectItemLinkPresentationTests.swift`:
    `b0c93bfa0c3e6f177ec74c68e5e78648a067c6701c26c692790b0e9d644b77d4`

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
ready commit remains required before implementation.

## Permanent Limits

Ready status proves only that the bounded target contract is sufficiently
specified to implement with synthetic provider-free evidence. It proves no
physical persistence, authorization, synchronization, database policy, Link
behavior, app/MCP behavior, migration reconciliation, hosted resource,
production behavior, release or cutover.
