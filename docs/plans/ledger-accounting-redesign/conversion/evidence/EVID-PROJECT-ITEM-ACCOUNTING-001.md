# EVID-PROJECT-ITEM-ACCOUNTING-001 — Project Item Accounting Section Contracts

- Timestamp: 2026-09-01
- Class: implementation planning / provider-free Project Item read domain
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and released Firebase app remain unchanged
- Claimed target surfaces: `SWIFT-008B49A474D1`, `TEST-0E4B478B0C55`
- Slice dossier:
  `conversion/implementation-slices/project-item-accounting-section-contracts.json`
- Ready-gate state: ready; behavior and executable self-tests are not yet
  implemented

## Selection and Scope

The Phase 1 dependency audit selected the smallest next user-visible Item read
boundary after stable Item/Project identity and Transaction/receipt values.
D-019, D-022 and D-023 plus the canonical Item-capture spec fully settle that
Project Items derives Unaccounted For and Accounted For from authoritative
relationships, preserves one physical Item identity, and treats Space and
ordinary presentation/detail state as non-authoritative.

Exactly two target-only comment scaffolds are claimed in the provider-free core/
test targets. Existing Item models, Project Items views/cards, Link flows, MCP
tools, backend code and Firebase remain unadvanced. This boundary deliberately
stops before Item creation/Link, final occurrence schema, amount/category/budget
effects, credit settlement, persistence/provider behavior, source decoding or
migration.

## Why Open Decisions Do Not Block This Slice

- O-003 decides paid-credit settlement, not whether an existing authoritative
  charge/credit occurrence makes an Item Accounted For.
- O-007/O-015 decide occurrence/provenance persistence. This slice consumes
  typed opaque relationship evidence and creates no table or writer.
- O-016 decides missing Business-paid acquisition evidence. Acquisition
  readiness is not part of this accounting-section projection.
- O-021 is the Item-wizard layout question and has no effect on the read model.
- O-023 decides media reference/byte retention; no attachment behavior exists.
- O-027 decides minimum creation evidence; this slice creates no Item and accepts
  stable Item identity only.

## Ready-Gate Contract

The dossier freezes six exact canonical/architecture requirements and requires:

- exact Account/Project/Item-bound client-paid Purchase and billable occurrence
  relationship evidence with stable identities;
- relationship-derived accounting state with no writable/cached authority;
- Unaccounted For first and Accounted For second, preserving deterministic order
  inside each section and refusing duplicate/cross-scope evidence;
- available, live-Invoice and frozen-paid charge/credit occurrences as qualifying
  without choosing settlement, amount, budget or Invoice-lifecycle behavior;
- authoritative-empty versus incomplete/partial/stale local evidence, canonical
  restart, derived-state/section fingerprint validation and stable refusal;
  relationship-free Items stay explicitly unresolved and outside both product
  sections until relationship absence is authoritative, while present qualifying
  evidence may still prove Accounted For; and
- one Account/Project-scoped local query port with no provider or production
  material.

Postgres, handlers, Data API, RLS, Sync Streams, local persistence, media,
concrete app/MCP wiring, migration, observability and feature activation are
explicit nonapplicabilities. Locally valid relationship evidence never
substitutes for server authorization or final occurrence schema.

## Ready-Gate Verification

The two comment-only hashes are acknowledged through the reviewed Item-
creation/Link batch and both surfaces are `target_mapped`. The dossier has no
blocker; every requirement is reciprocally covered by domain, offline-restart,
offline-rejection and exact-commit operational obligations.

All ready-gate commands ran from the dedicated Supabase worktree on 2026-09-01:

- `node scripts/supabase-conversion-ledger.mjs check` — pass at 743 recorded /
  728 discovered surfaces with only the three documented retired-path warnings;
- capability, query and residual generated checks — pass at 317 mapped / 164
  residual / 43 blockers;
- M0 — pass; M1/M2 — expected blocks at the unchanged 2/164 prerequisites;
- `swift test --package-path LedgeriOS` — pass, the existing 84 tests in 18
  suites; the scaffold intentionally adds no executable Item-accounting test;
- target environment and generated-contract checks — pass;
- macOS and generic iOS Simulator staging builds — pass; and
- `git diff --check` — pass.

Behavioral implementation may now begin only within the exact ready dossier.

## Permanent Limits

This ready gate and later provider-free implementation cannot:

- create, edit, Link, move, copy, merge or delete an Item;
- create or settle a charge/credit, Purchase, Invoice or budget contribution;
- choose final occurrence/provenance tables or O-003/O-007/O-015/O-016 behavior;
- choose Item-wizard layout/minimum evidence or media retention;
- define Postgres/RLS/Sync/Storage/provider or physical offline behavior;
- decode Firebase Item/proto/Transaction/Invoice/lineage evidence or migrate it;
- wire current app/MCP entry points; or
- authorize hosted resources, deployment, production migration, release or
  cutover.

No production read or mutation, Firebase implementation, provider connection,
hosted resource, migration, deployment or cutover occurred.
