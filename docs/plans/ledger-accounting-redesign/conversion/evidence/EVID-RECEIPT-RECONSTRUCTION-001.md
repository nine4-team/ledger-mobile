# EVID-RECEIPT-RECONSTRUCTION-001 — Non-Item Receipt Reconstruction Contracts

- Timestamp: 2026-09-01
- Class: implementation / provider-free receipt evidence domain
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and released Firebase app remain unchanged
- Claimed target surfaces: `SWIFT-B687382A0772`, `TEST-4CDC064BC93C`
- Slice dossier:
  `conversion/implementation-slices/non-item-receipt-line-reconstruction-contracts.json`
- Implementation state: implemented locally; exact-commit hosted CI remains
  pending before verification
- Implementation hashes:
  - `ReceiptLineReconstruction.swift`:
    `2d5ce505a18fbb9cfeeb4b556e36784203469da6ca545192d2b1c77a6204d23e`
  - `ReceiptLineReconstructionTests.swift`:
    `5a910b897f18a423643fc7481f95e4337299dede1e1c7c0e310d11bbed39b70a`

## Selection and Scope

The Phase 1 dependency audit selected the smallest next accounting value
boundary after exact Money and Purchase/Return classification. D-016 and the
accepted non-item receipt-line design fully settle embedded line identity,
ordered source evidence, increase/decrease magnitude semantics and the exact
mathematical reconstruction/variance equation.

Exactly two target-only implementation surfaces are claimed in the provider-
free core/test targets. Existing Transaction models, forms, audit panels, MCP
tools, backend code and Firebase remain unadvanced. This boundary deliberately
stops before a Transaction writer or completion verdict, physical Item-history
authority, client billing, tax allocation, schema/provider behavior, source
decoding or migration.

## Why Open Decisions Do Not Block This Slice

- O-008 decides whether/how a receipt line affects client billing. This slice
  contains no billability, Invoice, Expense, credit or budget field/effect.
- O-030 decides how a one-cent source discrepancy is accepted or represented.
  This slice retains exact variance and exposes no complete/incomplete verdict.
- O-031 decides Item tax/acquisition-basis treatment. Quantity and description
  are source evidence only; tax is never inferred or allocated to Items.
- O-032 decides canonical Transaction draft/posting evidence. This slice cannot
  create, post, edit or authorize a Transaction.

## Ready-Gate Contract

The dossier freezes six exact canonical/architecture requirements and requires:

- distinct stable receipt-line identity, source-preserving nonblank wording,
  strictly positive Money magnitude, exact increase/decrease effect and optional
  non-arithmetic quantity evidence;
- one ordered duplicate-free embedded line collection bound to a synthetic
  Account/Transaction and validated standalone Purchase/Return classification;
- exact integer-Money increase, decrease, net, reconstructed and variance
  evidence using a supplied authoritative physical Item total;
- no subtotal, tax-rate, percentage-tolerance, Item fabrication or billability
  semantics;
- canonical restart plus classification/Account/currency/overflow/tamper
  refusal; and
- stable bounded failure codes with no provider or production material.

Postgres, handlers, Data API, RLS, Sync Streams, local persistence, media,
concrete app/MCP wiring, migration, observability and feature activation are
explicit nonapplicabilities. Exact mathematical evidence never substitutes for
Transaction authorization or an approved completeness policy.

## Ready-Gate Verification

The two comment-only hashes are acknowledged through the reviewed Inventory/
Transaction batch and both surfaces are `target_mapped`. The dossier has no
blocker; every requirement is reciprocally covered by domain, offline-restart,
offline-rejection and exact-commit operational obligations.

All ready-gate commands ran from the dedicated Supabase worktree on 2026-09-01:

- `node scripts/supabase-conversion-ledger.mjs check` — pass at 741 recorded /
  726 discovered surfaces with only the three documented retired-path warnings;
- capability, query and residual generated checks — pass at 315 mapped / 164
  residual / 43 blockers;
- M0 — pass; M1/M2 — expected blocks at the unchanged 2/164 prerequisites;
- `swift test --package-path LedgeriOS` — pass, the existing 80 tests in 17
  suites; the scaffold intentionally adds no executable receipt test yet;
- target environment and generated-contract checks — pass;
- macOS and generic iOS Simulator staging builds — pass; and
- `git diff --check` — pass.

That ready gate authorized only the bounded implementation recorded below.

## Implemented Contract

`ReceiptLineReconstruction.swift` now provides:

- a distinct `NonItemReceiptLineID`, validated source-preserving nonblank
  description, exact positive `Money` magnitude, increase/decrease effect and
  optional quantity retained only as source evidence;
- an Account/Transaction-bound standalone Purchase/Return reconstruction that
  preserves duplicate-free line order and derives checked increase, decrease,
  signed net, physical-Item-plus-line total and exact recorded-total variance;
- a deterministic SHA-256 evidence fingerprint over the contract version,
  identity/classification, exact inputs, ordered lines and every derived total;
  this detects corruption/order changes but is not authorization or proof of an
  authentic external receipt;
- construction and decoding through the same classification, Account, line,
  currency, checked-arithmetic, aggregate and fingerprint validators; and
- a closed set of stable, bounded diagnostic codes.

The boundary deliberately accepts signed recorded-final and physical-Item
`Money` evidence and arbitrary optional `Int64` quantity evidence. It does not
invent the Transaction posting/sign/minimum-evidence policy still owned by
O-032, and quantity never participates in arithmetic.

## Local Implementation Verification

The implementation checkpoint ran from the dedicated Supabase worktree on
2026-09-01:

- `swift test --package-path LedgeriOS --filter ReceiptLineReconstructionTests`
  — pass, 4 focused tests;
- `swift test --package-path LedgeriOS` — pass, all 84 tests in 18 suites;
- `npm run target:environment:check` — pass;
- `npm run target:contracts:check` — pass;
- `npm run target:staging:build:macos` — pass;
- `npm run target:staging:build:ios` — pass; and
- `git diff --check` — pass.

`RECEIPT-TEST-001` through `RECEIPT-TEST-004` therefore pass with this evidence.
`RECEIPT-TEST-005` remains planned until the exact implementation commit passes
both required pull-request jobs; the slice and its two surfaces remain
`implemented`, not `verified`, until then.

## Permanent Limits

This ready gate and later provider-free implementation cannot:

- create, edit, post, correct, delete or authorize a Transaction;
- decide exact-match versus one-cent completion or introduce a rounding line;
- derive physical Item history or allocate receipt tax/cost across Items;
- create billable demand, Invoice membership, Expense, credit or budget value;
- define Postgres/RLS/Sync/Storage/provider or physical offline behavior;
- decode Firebase discount/subtotal/tax evidence or migrate source records;
- wire current app/MCP entry points; or
- authorize hosted resources, deployment, production migration, release or
  cutover.

No production read or mutation, Firebase implementation, provider connection,
hosted resource, migration, deployment or cutover occurred.
