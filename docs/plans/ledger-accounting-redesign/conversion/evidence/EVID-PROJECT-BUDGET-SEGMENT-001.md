# EVID-PROJECT-BUDGET-SEGMENT-001 — Project Budget Segment Read Contracts

- Timestamp: 2026-09-02
- Class: implementation gate / provider-free Project budget segment read contract
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and shipped app remain unchanged
- Claimed target surfaces: `SWIFT-42C7BDDCD714`, `TEST-A0B2D5B97695`
- Slice dossier:
  `conversion/implementation-slices/project-budget-segment-read-contracts.json`
- Verification state: exact ready commit
  `43189f1abe6e023f4d29b00f190b40464ce7a3e5` passed immutable Actions run
  `33687191592`; enhanced second-pilot implementation review remains open
- Ready scaffold hashes:
  - `ProjectBudgetSegmentData.swift`:
    `74231d9920e803381789c0b342ce09273de40216cf9d673c65e78c4637251dd2`
  - `ProjectBudgetSegmentDataTests.swift`:
    `1cb753600e1fafbca077f410059b7dc522b9c48ac53e7f53eeb1dd504395f1ba`

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

## Permanent Ready-State Limits

This evidence does not prove any calculation from real source facts, financial
authorization, physical local durability, authenticated synchronization,
database schema/policy, app or MCP behavior, migration reconciliation, hosted
resource, production access, release or cutover. The Firebase application and
worktree remain untouched.
