# EVID-DOMAIN-PRIMITIVES-001 — Exact Money and Domain Identity

- Timestamp: 2026-09-01
- Class: implementation planning / provider-free domain primitives
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and released application remain unchanged
- Claimed target surfaces: `SWIFT-3AC58A64B789`, `TEST-15ECC49577C0`
- Slice dossier:
  `conversion/implementation-slices/exact-money-and-domain-identity.json`
- Ready-gate state: ready; behavior and executable self-tests are not yet
  implemented

## Selection and Scope

The remaining Phase 1 audit found that every later Client, Project, Item,
Transaction, Invoice, media, report and migration slice needs stable entity
identity and exact money representation, while none should invent those
mechanics independently. This boundary is decision-independent because it does
not choose any product amount sign, bound, allocation, tax, rounding, posting,
currency-default or lifecycle policy.

Exactly two target-only comment scaffolds are claimed inside the already
provider-free core/test package. No current Firebase model, formatter,
calculation, app, MCP, provider, schema or migration surface is advanced by the
scaffold.

## Ready-Gate Contract

The dossier freezes six exact architecture requirements and requires:

- distinct stable opaque target IDs for the established entity families,
  retaining the existing bounded `LedgerIdentifier` validation;
- a `CurrencyCode` that accepts exactly three uppercase ASCII letters and makes
  no ISO-registry, locale, exchange or default-currency claim;
- a signed Int64-minor-unit `Money` value with explicit currency and checked
  same-currency comparison/add/subtract/negate behavior;
- decode-through-validation, deterministic sorted-key restart fixtures and no
  floating-point representation;
- stable refusal for malformed IDs/currency, cross-currency operations and all
  Int64 overflow boundaries; and
- no provider import, database/Sync/file/network access, product semantic,
  migration transform or production authority.

Postgres, handlers, Data API, RLS, PowerSync, media behavior, app/MCP wiring,
migration and operations are explicit non-applicabilities. Later slices remain
responsible for mapping stable IDs to text and Money to bigint minor units plus
currency and for proving their own accounting semantics.

## Ready-Gate Verification

The two comment-only hashes are acknowledged through the reviewed platform
batch and both surfaces are `target_mapped`. The dossier has no blocker; every
requirement is reciprocally covered by domain, offline-restart,
offline-rejection and exact-commit operational obligations. Conversion checking
must pass before behavioral implementation begins.

## Permanent Limits

This ready gate and later primitive implementation cannot:

- approve an Account currency, ISO list, locale formatter, exchange rate,
  rounding, tax or receipt allocation policy;
- decide positive/negative/zero validity for any Transaction, Invoice, Expense,
  Fee, credit or payment story;
- create a table, migration, RLS policy, Sync Stream, handler, app/MCP contract
  or provider adapter;
- claim migrated source amounts/IDs are correct without explicit transform and
  reconciliation evidence; or
- authorize deployment, migration, release or cutover.

No production read or mutation, Firebase implementation, provider connection,
hosted resource, migration, deployment or cutover occurred.
