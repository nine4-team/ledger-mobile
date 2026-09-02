# EVID-PROJECT-BUDGET-SEGMENT-001 — Project Budget Segment Read Contracts

- Timestamp: 2026-09-02
- Class: implementation gate / provider-free Project budget segment read contract
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and shipped app remain unchanged
- Claimed target surfaces: `SWIFT-42C7BDDCD714`, `TEST-A0B2D5B97695`
- Slice dossier:
  `conversion/implementation-slices/project-budget-segment-read-contracts.json`
- Verification state: verified after enhanced second-pilot review, complete
  local gates and immutable exact-integration-checkpoint CI
- Ready scaffold hashes:
  - `ProjectBudgetSegmentData.swift`:
    `74231d9920e803381789c0b342ce09273de40216cf9d673c65e78c4637251dd2`
  - `ProjectBudgetSegmentDataTests.swift`:
    `1cb753600e1fafbca077f410059b7dc522b9c48ac53e7f53eeb1dd504395f1ba`
- Implemented source hashes:
  - `ProjectBudgetSegmentData.swift`:
    `321e57d77b2ee49c1c8cc4d4c16ed1fb2d4c1e4e55770611ccd49f566ef8dcd1`
  - `ProjectBudgetSegmentDataTests.swift`:
    `e0fcf2c6489ec2f1421e6a7138bc0331ea644b19f219a70eb4af2dd25680eb40`

## Selection and Authority Audit

The stricter next-slice rescout considered only features whose exact behavior
already exists in a pre-existing canonical target spec or confirmed decision.
It rejected media primary/order and Project-note search because their detailed
semantics are not settled. It also followed the separate rejection of Inventory
destination planning, where independent review caught that shipped behavior had
been mistaken for target authority before a worker was launched.

The selected boundary is narrower and explicit. `Budget Progress` in
`docs/specs/invoice-centered-project-accounting.md` and confirmed D-012 define
two signed semantic segments per Project category, their derived sum, and the
invariant that collection moves equal value unpaid-to-paid without increasing
recognized progress. The same section explicitly leaves visual treatment to
presentation. This slice implements no presentation.

The reviewed Invoicing/budget dossier supplies source defects and technical
context only: current Transaction-only arithmetic, cached `budgetSummary`,
Invoice-status fallbacks and MCP-only signs are not preserved as target
authority. Architecture supplies exact scoped request, local-readiness and
narrow-port constraints without adding product behavior.

## Frozen Safe Boundary

The ready dossier permits only:

- one exact Account/Project/currency request and deterministic fingerprint;
- stable budget-category definition identity/order;
- signed `clientPaid` and `invoicingUnpaid` `Money`;
- overflow-safe `recognized = clientPaid + invoicingUnpaid`, derived rather
  than caller-authored and verified when decoded;
- a synthetic before/after collection fixture that exchanges an equal amount
  between segments without changing recognized value;
- explicit ready, authoritative-empty, partial, stale and failure truth;
- distinct `LocalDataVersion` and accounting-authority/projection revision
  evidence, so local freshness is not mistaken for financial authority;
- canonical structured restart and bounded refusal; and
- one narrow provider-free query port for exact request-matching snapshots.

It expressly excludes contribution-source eligibility/taxonomy, occurrence or
Invoice persistence, actual collection, budget limits, remaining/over values,
source counts, Project cards, pins, reports/exports, negative-credit visual
treatment, category mutation, Postgres, RLS, PowerSync, Auth, adapters,
app/MCP wiring, migration, hosted resources and production.

O-003 through O-005 and O-010 remain open because signed values are semantic
data, not a choice of settlement behavior, label, bar direction, color,
clamping or percentage. O-007/O-015 do not control this leaf because it carries
no contribution source or occurrence shape. O-026 remains open because the
slice reads an already verified immutable category definition snapshot and
cannot mutate shared reference data. O-033 through O-036 remain outside because
the slice neither accepts collection variance nor defines reports or summary
labels.

## Ready-Gate Verification

The two implementation paths contain comments only. Both are classified
through the reviewed Invoicing/budget batch and remain `target_mapped`; the
slice is `ready`, not implemented or verified. Five pending obligations require
domain arithmetic/no-double-count evidence, byte-identical readiness restart,
negative scope/currency/duplicate/overflow/tamper cases, exact-request port
isolation, upstream-failure/cancellation behavior, and exact-implementation-
commit operational CI.

The complete local ready gate passed all 184 then-existing target tests in 43
suites, target isolation and generated app/MCP contracts, repeatable project
generation, both staging builds, conversion/capability/query/residual checks,
M0, clean formatting, and the expected M1/M2 holds of exactly 2/167 surfaces.
Exact ready commit `43189f1abe6e023f4d29b00f190b40464ce7a3e5`
then passed immutable Actions run `33687191592`: conversion traceability passed
in 11 seconds and the isolated target environment passed in 2 minutes 3 seconds
with the same 184 tests, both staging builds, and clean tracked artifacts.

The second write-capable pilot cannot be accepted from its own report. It must
start from the exact green ready commit in an isolated branch/worktree, change
only the two allowlisted Swift paths, receive integration-agent review of every
changed line plus a separate adversarial review, pass focused and full local
gates, and pass immutable CI on the final integrated SHA before verification.

## Enhanced Second-Pilot Review and Implementation

The worker started from exact green ready commit `43189f1a` in the isolated
`codex/supabase-slice-project-budget-segment` branch/worktree. Candidate
`dc9f2601b2610746c68f4efbd1be4f09540d0943` changed exactly the two allowlisted
Swift paths. It made no documentation, control, generated, project/package,
MCP, Firebase, provider, hosted-resource, production or integration-branch
change. A precommit size review required simplification from approximately
1,076 to 768 added lines while retaining every frozen obligation.

The integration agent reviewed every changed source and test line and reran all
five focused tests. The independent read-only adversarial reviewer verified the
exact parent and path scope, reread product/architecture authority and every
changed line, ran five focused and all 189 target tests in 44 suites plus target
isolation, and found no P0-P3 defect. Its environment lacked a worktree-local
`tsc`, so it could not repeat the MCP TypeScript subcheck there; the ready-
commit CI already passed that check and the integration full gate repeated it
successfully before operational verification.

The bounded implementation defines the exact fingerprinted request, signed
category segments with overflow-safe internally derived and decode-verified
recognized value, validated canonical local snapshot with distinct local and
accounting-projection versions, stable failures and a narrow watch port. Tests
cover positive/zero/negative arithmetic, positive collection exchange, scope/
currency/duplicate/order/count/time/revision/overflow/fingerprint/encoding
refusal, ready/authoritative-empty/incomplete-empty/partial/stale byte-identical
restart, exact-request streaming, upstream failure, cancellation and forbidden
encoded shape. The candidate was integrated as `ddbe7d7b`. The complete
integration gate passes conversion/capability/query/residual/M0 controls,
target isolation and generated app/MCP contracts, five focused and all 189
tests in 44 suites, repeatable project generation, both staging builds and
clean formatting. Exact integration checkpoint
`8fce53b75029133b39fe182031df25ef011fc35e` then passed immutable Actions
run `33689446640`: conversion traceability passed in 11 seconds, and the
isolated target environment passed in 2 minutes 30 seconds with all 189 tests
in 44 suites, generated contracts, both staging builds and clean artifacts.
The second enhanced write-capable pilot is therefore accepted and verified.
Its clean isolated worktree was removed after verification; the branch and
candidate commit remain recoverable.

## Permanent Limits

This evidence does not prove any calculation from real source facts, financial
authorization, physical local durability, authenticated synchronization,
database schema/policy, app or MCP behavior, migration reconciliation, hosted
resource, production access, release or cutover. The Firebase application and
worktree remain untouched.
