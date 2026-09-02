# EVID-RECEIPT-RECONSTRUCTION-001 — Non-Item Receipt Reconstruction Contracts

- Timestamp: 2026-09-01
- Class: implementation planning / provider-free receipt evidence domain
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and released Firebase app remain unchanged
- Claimed target surfaces: `SWIFT-B687382A0772`, `TEST-4CDC064BC93C`
- Slice dossier:
  `conversion/implementation-slices/non-item-receipt-line-reconstruction-contracts.json`
- Ready-gate state: ready; behavior and executable self-tests are not yet
  implemented

## Selection and Scope

The Phase 1 dependency audit selected the smallest next accounting value
boundary after exact Money and Purchase/Return classification. D-016 and the
accepted non-item receipt-line design fully settle embedded line identity,
ordered source evidence, increase/decrease magnitude semantics and the exact
mathematical reconstruction/variance equation.

Exactly two target-only comment scaffolds are claimed in the provider-free core/
test targets. Existing Transaction models, forms, audit panels, MCP tools,
backend code and Firebase remain unadvanced. This boundary deliberately stops
before a Transaction writer or completion verdict, physical Item-history
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

Behavioral implementation may now begin only within the exact ready dossier.

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
