# EVID-SHARED-LIST-001 — Shared List Query Presentation Contracts

- Timestamp: 2026-09-01
- Class: implementation / offline presentation / query contract
- Repository baseline: `fcfffdd0` on
  `codex/supabase-powersync-implementation`; implementation was verified in the
  working diff before commit
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and current application project were not
  modified
- Target environment: dependency-free local target package with synthetic
  query profiles, IDs, cursors, rows, versions, clocks, and failures
- Production reads or mutations: none
- Hosted Supabase/PowerSync resources created or contacted: none
- Operator: Codex

## Surfaces

- `SWIFT-38DC8C755068` — named query/sort/filter/cursor/readiness/intent values
  and pure presentation reducer
- `TEST-7E87ABB4166B` — deterministic domain, restart, incomplete-data,
  safe-failure, retry, and late-snapshot suite

The four mapped current UI surfaces that motivated the foundation—
`SWIFT-7FD35B52D248`, `SWIFT-AA317435FD6E`, `SWIFT-CDADEAA08764`, and
`SWIFT-D49180285F84`—remain `target_mapped`. They are not advanced by this
contract slice because concrete iOS/macOS controls, visual/accessibility proof,
and feature-specific profiles have not yet been implemented.

## Implemented Contract

`LedgerTargetCore` now provides:

- validated named query, sort, filter, and action identifiers rather than raw
  fields, collection paths, SQL, dynamic dictionaries, or provider values;
- a reviewed query profile with unique registries, supported directions,
  bounded page size, optional search capability, and exactly one default sort;
- normalized bounded search terms;
- a stable sort descriptor whose only tie-breaker is stable entity identity;
- deterministic SHA-256 query fingerprints over profile/sort/filter/search/page
  state and opaque cursors bound to that fingerprint;
- cursor, retry, sort, filter, search, add, and selection intent validation
  against the active profile;
- closed readiness, empty, and failure states separating waiting, ready,
  partial, stale, blocked, authoritative empty, no local matches, unavailable,
  retryable, and required-update outcomes;
- locally versioned/as-of snapshots and a pure reducer that rejects late
  snapshots from another query;
- cached-row preservation through retryable failure with visibly stale state
  and a typed retry intent; and
- structural non-enumeration: not-found, authorization, and authentication
  causes collapse internally, while the public presentation update carries
  only `unavailable` and clears cached rows/version evidence.

The first compilation found one test-only generic inference ambiguity for a
failure with no cached rows. The fixture was explicitly typed; no production
contract changed to satisfy the compiler. Review then moved raw failure-cause
distinctions behind the module boundary and added intent/profile validation so
non-enumeration and named-action safety are structural.

## Reproduction

```bash
swift test --package-path LedgeriOS
npm run target:environment:check
npm run target:project:generate
npm run target:staging:build:macos
npm run target:staging:build:ios
node scripts/supabase-conversion-ledger.mjs sync
node scripts/supabase-conversion-ledger.mjs report
node scripts/supabase-conversion-ledger.mjs check
git diff -- LedgeriOS/LedgeriOS.xcodeproj/project.pbxproj
git diff --check
```

Local results on 2026-09-01:

- three shared-list domain/restart/rejection tests: pass;
- 32 total tests across four target-package suites: pass;
- profile uniqueness, default-sort, direction, page-size, search, filter,
  action, retry, cursor, and late-snapshot negative cases: pass;
- restart reconstruction preserves identical partial cached state: pass;
- incomplete empty never becomes authoritative empty: pass;
- ready/complete zero rows distinguish authoritative empty from no matches:
  pass;
- not-found and not-authorized produce identical public unavailable state and
  clear cached rows/version metadata: pass;
- transient failure retains safe cached rows as stale and emits typed retry:
  pass;
- target environment/source-contamination guard: pass;
- target staging macOS and generic iOS Simulator builds: pass;
- source `LedgeriOS.xcodeproj` diff: empty; and
- tracked diff formatting check: pass.

## Verification Status

- `SHARED-LIST-TEST-001`: passed locally. Named query state is bounded,
  deterministic, cursor-safe, profile-validated, and provider-free.
- `SHARED-LIST-TEST-002`: passed locally. Restart reconstruction preserves the
  same local partial truth, and incomplete empty is never authoritative empty.
- `SHARED-LIST-TEST-003`: passed locally. Failures are non-enumerating, safe
  cached rows survive retryable faults, and mismatched snapshots fail closed.
- `SHARED-LIST-TEST-004`: exact-commit pull-request CI is pending, so the slice
  remains `implemented`, not `verified`.

## Explicit Limits

This evidence does not implement or prove:

- concrete iOS/macOS list controls, keyboard behavior, accessibility, Dynamic
  Type, VoiceOver, screenshots, or visual state;
- feature-specific Item, Project, Invoice, Transaction, Space, report, or
  search profiles and row projections;
- a query port, local database, adapter, PowerSync Stream, Postgres query,
  index, Data API grant, RLS policy, or server handler;
- Auth, workspace activation, attachments, product writes, or accounting
  semantics; or
- hosted staging, migration, release, cutover, or production authority.
