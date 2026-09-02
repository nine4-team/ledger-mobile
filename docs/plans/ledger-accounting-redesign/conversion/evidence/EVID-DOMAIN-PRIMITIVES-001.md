# EVID-DOMAIN-PRIMITIVES-001 — Exact Money and Domain Identity

- Timestamp: 2026-09-01
- Class: implementation / provider-free domain primitives
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and released application remain unchanged
- Claimed target surfaces: `SWIFT-3AC58A64B789`, `TEST-15ECC49577C0`
- Slice dossier:
  `conversion/implementation-slices/exact-money-and-domain-identity.json`
- Slice state: implemented; local obligations pass and exact-commit hosted CI
  remains pending before verification

## Selection and Scope

The remaining Phase 1 audit found that every later Client, Project, Item,
Transaction, Invoice, media, report and migration slice needs stable entity
identity and exact money representation, while none should invent those
mechanics independently. This boundary is decision-independent because it does
not choose any product amount sign, bound, allocation, tax, rounding, posting,
currency-default or lifecycle policy.

Exactly two target-only implementation surfaces are claimed inside the already
provider-free core/test package. No current Firebase model, formatter,
calculation, app, MCP, provider, schema or migration surface is advanced by
this representation boundary.

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

## Implemented Contract

`LedgerTargetCore/DomainPrimitives.swift` now provides:

- distinct `ClientID`, `ProjectID`, `ItemID`, `InvoiceID`, `TransactionID`,
  `ExpenseID`, `FeeID`, `SpaceID` and `AttachmentID` types over the existing
  bounded provider-free identifier validation;
- `CurrencyCode` validation for exactly three uppercase ASCII letters, including
  decode-through-validation and stable direct/encoded failure categories;
- signed Int64-minor-unit `Money` with explicit currency, zero/sign inspection,
  checked same-currency amount equality and ordering, and overflow-checked add,
  subtract and negate operations;
- deterministic Codable boundaries whose canonical evidence emits integer minor
  units and revalidates identifiers and currency after restart; and
- stable bounded `DomainPrimitiveFailure` values for malformed identifiers,
  currency and encoded money, currency mismatch and operation-specific overflow.

The types contain no clock, UUID generator, locale, decimal/floating-point
calculation, database, network, provider SDK or global state. They establish
representation only; they do not define product signs, bounds, currency policy,
formatting, exchange, allocation, tax, rounding or posting.

## Local Verification

Local results on 2026-09-01:

- `swift test --package-path LedgeriOS --filter DomainPrimitivesTests`: pass,
  three focused tests;
- `swift test --package-path LedgeriOS`: pass, 69 tests across fourteen suites;
- `npm run target:environment:check`: pass; package edges, provider-import scan
  and application/source-project exclusion remain valid;
- `npm run target:contracts:check`: pass; generated Swift/TypeScript/MCP
  projections remain current;
- `npm run target:staging:build:macos`: pass; and
- `npm run target:staging:build:ios`: pass for generic iOS Simulator.

The focused tests cover every new entity-ID type, CurrencyCode boundaries,
positive/negative/zero Money, exact same-currency amount comparison and checked
arithmetic, deterministic Int64-min/max restart bytes, malformed decoded values,
cross-currency refusal and all addition/subtraction/negation overflow edges.
Canonical encoding contains integer minor-unit tokens; fractional numeric input
is rejected. Swift's standard JSON integer decoder may accept an exactly integral
JSON spelling such as `1.0`, so this evidence deliberately does not claim lexical
rejection of every decimal-form token.

`PRIMITIVE-TEST-001`, `PRIMITIVE-TEST-002` and `PRIMITIVE-TEST-003` pass locally.
`PRIMITIVE-TEST-004` remains planned until an immutable hosted run passes on the
exact implementation commit, so the slice and exactly its two target-only
surfaces remain `implemented`, not `verified`.

## Ready-Gate Verification

The original comment-only hashes were acknowledged through the reviewed
platform batch before implementation. The dossier has no blocker; every
requirement remains reciprocally covered by domain, offline-restart,
offline-rejection and exact-commit operational obligations. The implementation
hashes are acknowledged only after code review and local verification.

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
