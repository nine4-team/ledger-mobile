# EVID-SCOPED-ROUTE-001 — Scoped Route Resolution and Restoration

- Timestamp: 2026-09-01
- Class: implementation / offline restoration / workspace isolation
- Repository implementation commit:
  `bb9782126900f5d3099186f0571e1b5503445db7` on
  `codex/supabase-powersync-implementation`
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and current application project were not
  modified
- Target environment: dependency-free local target package with synthetic
  target route definitions, identifiers, workspaces, activations, snapshots,
  clocks, and failures
- Production reads or mutations: none
- Hosted Supabase/PowerSync resources created or contacted: none
- Operator: Codex

## Surfaces

- `SWIFT-D0BC2109537E` — target-only scoped route, registry, restoration,
  resolution state, and reducer contracts
- `TEST-E106594B9EF3` — deterministic registry, restart, scope-isolation,
  non-enumeration, retry, not-synced, and late-result tests

No current Firebase-era route, view, or navigation surface is advanced by this
technical-control slice. Concrete iOS/macOS navigation, feature route profiles,
visual/accessibility behavior, workspace activation, Auth, and Sync remain in
their owning later slices.

## Implemented Contract

`LedgerTargetCore` now provides:

- stable route kind, route contract, activation, and resolution-request IDs;
- one `WorkspaceRouteScope` containing the target environment, Principal, and
  Account;
- a closed `RouteRegistry` whose definitions validate required/forbidden
  subjects and required/optional/forbidden bounded parent entity kinds;
- `ScopedRoute` values containing only a registered kind and stable entity
  references—never a document path, SQL/table name, URL, provider object, or
  arbitrary payload dictionary;
- a versioned `RouteRestorationRecord` that must be revalidated against the
  active scope, supported contract version, and current registry after decode;
- deterministic SHA-256 restoration keys over the exact record without placing
  raw Principal or Account IDs in the key;
- live `RouteResolutionRequest` values that cannot be decoded without registry
  validation, and that bind route work to scope, workspace activation, and
  request identity;
- explicit loading, ready, not-synced, stale, unavailable, and blocked
  readiness plus retryable/required-update failures;
- internal not-found, authorization, authentication, and revocation causes
  that collapse to the same public unavailable state and clear cached entity
  bytes/version evidence;
- explicit not-synced state that may retain a supplied safe cached snapshot,
  without turning incomplete synchronization into absence;
- retryable infrastructure failure that retains only an explicitly supplied
  safe cached snapshot and emits a typed retry intent; and
- a reducer that validates scope, activation, request ID, and route before
  mutation, rejecting late results from another Account, a prior re-entry into
  the same Account, an older request, or a different route.

Review removed `Codable` from live resolution requests/updates after the first
passing test run. Otherwise untrusted persisted bytes could construct a request
without the route registry used by the validated initializer. Only restoration
records are serializable, and accepting them always requires registry, scope,
and version validation.

## Reproduction

```bash
swift test --package-path LedgeriOS --filter ScopedRouteResolutionTests
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

- three scoped-route domain/restart/rejection tests: pass;
- 35 total tests across five target-package suites: pass;
- empty/duplicate/unknown registries and invalid subject/parent shapes: reject;
- valid restoration survives encode/decode with the same deterministic key;
- environment, Principal, Account, contract-version, and registry mismatch:
  reject;
- missing, unauthorized, unauthenticated, and revoked causes: identical public
  unavailable state with no cached destination/version evidence;
- not-synced and retryable cached states remain distinct and typed;
- wrong Account, prior activation, old request, and wrong route updates: reject
  without changing the active state;
- target environment/source-contamination guard: pass;
- generated target catalog and TypeScript check: pass;
- target staging macOS and generic iOS Simulator builds: pass;
- source `LedgeriOS.xcodeproj` diff: empty; and
- tracked diff formatting check: pass.

Immutable GitHub Actions run
[`33562117852`](https://github.com/nine4-team/ledger-mobile/actions/runs/33562117852)
passed on the exact implementation commit. Its `Conversion state and
traceability` and `Isolated target environment` jobs both passed, including
conversion coverage, generated-artifact cleanliness, target dependency and
environment boundaries, generated app/MCP contracts, all target tests, the
macOS build, and the generic iOS Simulator build.

## Verification Status

- `SCOPED-ROUTE-TEST-001`: passed locally. The route registry and restoration
  key are bounded, deterministic, provider-free, and structurally validated.
- `SCOPED-ROUTE-TEST-002`: passed locally. Offline encode/decode restoration is
  deterministic and every scope/version/registry mismatch fails closed.
- `SCOPED-ROUTE-TEST-003`: passed locally. Inaccessible causes are publicly
  indistinguishable; not-synced/retry are explicit; stale workspace work cannot
  mutate active route state.
- `SCOPED-ROUTE-TEST-004`: passed in immutable GitHub Actions run `33562117852`
  on exact implementation commit
  `bb9782126900f5d3099186f0571e1b5503445db7`.

All four obligations pass, so the slice and its two target-only surfaces are
`verified`. Current Firebase-era route/view surfaces remain at their prior
honest statuses.

## Explicit Limits

This evidence does not implement or prove:

- actual workspace activation, authenticated Principal selection, logout or
  account-switch pending-work policy;
- a local database, query port, Supabase adapter, PowerSync Stream, Postgres
  relation, Data API grant, RLS policy, or server handler;
- concrete Project/Item/Invoice/etc. route definitions or destination views;
- iOS/macOS navigation stacks, deep links, keyboard behavior, accessibility,
  Dynamic Type, VoiceOver, screenshots, or visual state;
- signed/physical-device navigation or revocation behavior; or
- hosted staging, migration, release, cutover, or production authority.
