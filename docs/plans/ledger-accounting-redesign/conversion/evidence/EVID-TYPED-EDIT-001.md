# EVID-TYPED-EDIT-001 — Typed Edit Draft and Submission Presentation

- Timestamp: 2026-09-01
- Class: implementation / typed edit intent / offline operation presentation
- Repository implementation commit:
  `10a7db798712512be61cff0354083c9d5e2ce25d` on
  `codex/supabase-powersync-implementation`
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and current application project were not
  modified
- Target environment: dependency-free local target package with synthetic
  target draft fields, Accounts, Principals, entities, revisions, payloads,
  operations, clocks, validation issues, receipts, results, and rejections
- Production reads or mutations: none
- Hosted Supabase/PowerSync resources created or contacted: none
- Operator: Codex

## Surfaces

- `SWIFT-3E0BAFEF6955` — target-only typed field, draft, validation,
  submission-binding, and operation-presentation contracts
- `TEST-F9037F34FAF9` — deterministic field, restart, binding, mismatch,
  monotonicity, and lifecycle-presentation suite

No current editor, modal, controller, Firebase service, or MCP tool is advanced
by this technical-control slice. Product field mutability and validation,
feature command handlers, concrete forms, app/MCP parity, visual/accessibility
behavior, and provider integration remain in their owning later slices.

## Implemented Contract

`LedgerTargetCore` now provides:

- generic `EditFieldValue<Value>` with distinct `unchanged`, `set(Value)`, and
  `clear` cases; setting empty string or integer zero is not clearing;
- a feature-owned `TypedEditPayload` protocol with explicit change detection;
- `TypedEditDraft<Payload>` binding stable draft, Account, actor Principal,
  operation-contract, subject, expected revision, local version, captured time,
  and typed payload values without a field dictionary or null sentinel;
- stable, optionally field-scoped validation issue codes with deterministic
  ordering and duplicate refusal;
- `unchanged`, `invalid`, and `valid` validation results, where
  `ValidatedEditDraft` cannot be constructed or decoded publicly;
- `EditSubmissionBinding.bind` that accepts only a validated draft and the same
  typed `OperationEnvelope` payload, exact Account, actor, contract, and exactly
  one matching subject-revision precondition, then records the canonical
  operation fingerprint;
- a non-public, non-decodable binding initializer. Restart persists the typed
  draft plus queued envelope and recreates the binding only by running all
  validation again;
- exact receipt and snapshot checks for operation ID, Account, contract, and
  fingerprint before presentation mutation;
- closed edit-submission phases for local acceptance, queued, applying,
  applied, rejection, conflict, retry, unavailable, reauthentication, required
  update, superseded, and resolved outcomes;
- stable failure-category mapping with no vendor error, raw patch, or
  inaccessible entity detail; and
- monotonic presentation checks: late receipts, older snapshots, conflicting
  equal-time snapshots, and illegal later phase regressions fail without
  replacing the current state.

The first compilation exposed a throwing fallback expression in duplicate
validation handling; it was rewritten explicitly. Review then removed direct/
decoded binding construction and added timestamp plus lifecycle-transition
guards so persistence or late observation cannot bypass the same invariants.

## Reproduction

```bash
swift test --package-path LedgeriOS --filter TypedEditDraftTests
swift test --package-path LedgeriOS
npm run target:environment:check
npm run target:contracts:check
npm run target:project:generate
npm run target:staging:build:macos
npm run target:staging:build:ios
git diff -- LedgeriOS/LedgeriOS.xcodeproj/project.pbxproj
git diff --check
```

Local results on 2026-09-01:

- four typed-edit domain/restart/rejection/presentation tests: pass;
- 39 total tests across six target-package suites: pass;
- unchanged, set-empty, set-zero, set-value, and clear encode distinctly and
  apply deterministically: pass;
- unchanged/invalid/valid draft outcomes, stable issue ordering, issue
  round-trip, and duplicate refusal: pass;
- draft plus queued envelope survive restart and recreate the identical binding
  only through validation: pass;
- wrong Account, actor, contract, payload, subject, missing/duplicate/wrong
  revision, operation ID, snapshot Account/contract/fingerprint: reject;
- local receipt remains locally accepted rather than server-applied: pass;
- queued/retry/applying/applied/rejection/conflict/authentication/update/
  superseded/resolved states map to closed provider-free phases: pass;
- late receipt, older snapshot, equal-time conflicting snapshot, and later
  terminal regression: reject without mutation;
- target environment/source-contamination guard: pass;
- generated target catalog and TypeScript check: pass;
- target staging macOS and generic iOS Simulator builds: pass;
- source `LedgeriOS.xcodeproj` diff: empty; and
- tracked diff formatting check: pass.

Immutable GitHub Actions run
[`33563347569`](https://github.com/nine4-team/ledger-mobile/actions/runs/33563347569)
passed on the exact implementation commit. Its `Conversion state and
traceability` and `Isolated target environment` jobs both passed, including
conversion coverage, generated-artifact cleanliness, target dependency and
environment boundaries, generated app/MCP contracts, the then-configured 12
environment tests, the macOS build, and the generic iOS Simulator build. The
complete 47-test package suite, including the unchanged typed-edit tests, later
passed with the corrected workflow in immutable run
[`33567370249`](https://github.com/nine4-team/ledger-mobile/actions/runs/33567370249).

## Verification Status

- `TYPED-EDIT-TEST-001`: passed locally. Typed field intent and validation are
  deterministic, explicit, and free of raw patch mechanics.
- `TYPED-EDIT-TEST-002`: passed locally. Draft/envelope restart reconstructs
  the exact validated binding without confusing local acceptance with apply.
- `TYPED-EDIT-TEST-003`: passed locally. Scope/revision/fingerprint/stale and
  nonmonotonic mismatches fail without mutating the current presentation.
- `TYPED-EDIT-TEST-004`: passed locally. Every shared operation state maps to a
  stable provider-free edit presentation category.
- `TYPED-EDIT-TEST-005`: exact implementation run `33563347569` passed the
  conversion/boundary/contracts/build/clean-diff gates; corrected cumulative
  run `33567370249` passed the complete 47-test target suite with this
  implementation unchanged.

All five obligations pass, so the slice and its two target-only surfaces are
`verified`. Current editor, feature-command, and Firebase surfaces remain at
their prior honest statuses.

## Explicit Limits

This evidence does not implement or prove:

- which Project, Client, Item, Transaction, Invoice, Expense, Space, reference,
  or identity fields exist or may be edited in any lifecycle state;
- money parsing, rounding, tax/basis, accounting, relationship, paid-lock, or
  destructive-action policy;
- a product command, handler, Postgres relation/function, Data API grant, RLS
  policy, Sync Stream, local database, or provider adapter;
- concrete iOS/macOS forms, focus/keyboard behavior, accessibility, Dynamic
  Type, VoiceOver, screenshots, or visual states;
- MCP command payload/handler integration or end-to-end app/MCP parity;
- signed/physical-device offline behavior; or
- hosted staging, migration, release, cutover, or production authority.
