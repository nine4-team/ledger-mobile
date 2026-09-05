# EVID-SPACE-ASSIGNMENT-DESTINATION-PICKER-PROVIDER-001 — Local Space Destination Picker

- Status: implemented and independently reviewed locally; immutable CI pending
- Date: 2026-09-05
- Environment: isolated target worktree and synthetic local fixtures only
- Production/Firebase impact: none
- Slice: `space-assignment-destination-powersync-picker`

## Implemented Outcome

The target staging application can open an offline-first Space destination
picker for one exact Project or for Business Inventory. The implementation
reads active same-Account/same-scope Space rows through a typed Core contract,
orders them canonically, presents waiting/partial/stale/ready/authoritative-empty
and bounded-failure states, and permits selection only by a Space ID represented
in the current local snapshot.

This slice adds no Item selection, assignment, clearing, Space mutation, MCP
surface, hosted environment, source-data migration, Firebase behavior, release,
or cutover authority.

## Physical Target Surfaces

- `CONFIG-048B775BE4E4` — additive `spike_spaces` schema, constraints, indexes,
  SELECT-only grant, and active-membership RLS;
- `CONFIG-DC77B9F609A7` — runnable 34-assertion pgTAP schema/security leaf;
- `CONFIG-5F4C2A8274C3` — localhost-only Data API read/denial runner;
- `SWIFT-0A528DE84879` / `TEST-33BFA84BCBB2` — encrypted local PowerSync query,
  exact on-demand stream ownership, freshness, cancellation, and reciprocal
  tests;
- `SWIFT-62E2D7E9B40E` / `TEST-0126A06E52D0` — Core-only presenter/AppModel and
  state/selection tests; and
- `SWIFT-698CCC538675` / `SWIFT-A1156933E12E` — thin runtime adapter and isolated
  staging view.

Shared schema, runtime, facade, Sync Stream, staging-composition, generated-
project, conversion-discovery, package/workflow, and environment-check surfaces
were changed only within the exact READY touchpoint permissions. Primary
ownership remains with their existing slices.

## Freshness and Offline Correctness

PowerSync 1.16.1 retains `ps_stream_subscriptions.last_synced_at` across a
subscription UPSERT, while its `waitForFirstSync()` accepts any already-present
exact-stream sync epoch. The production adapter therefore loads both public
status and the exact retained local subscription epoch before subscribing,
decodes local parameters semantically, validates microsecond timestamps, and
uses their maximum as the strict freshness baseline. The waiter is used only
when neither source contains an earlier epoch.

Row-watch payloads are invalidation signals, not authority. Every invalidation
is fail-closed validated and followed by a serialized fresh production query;
an accepted exact-stream epoch is likewise paired with a fresh read. Cached or
delayed rows cannot overwrite causal ready evidence. Membership loss clears
completeness immediately, and regained membership remains incomplete until a
later qualifying exact-stream epoch and fresh read.

Provider shutdown directly awaits status observation, cancels and joins both
owned tasks, and releases the sole PowerSync subscription owner before the
structured workspace database closes.

## Database and Sync Security

The Postgres relation enforces exact Project-or-Business-Inventory scope shape,
same-Account Project ownership, active/archived lifecycle, positive revision,
and query-aligned indexes. Authenticated users receive SELECT only. RLS and both
on-demand Sync Streams derive visibility from the signed user through active
Account membership, return only active rows, and do not auto-subscribe.

The Swift local query independently binds the validated Principal and Account,
preserves malformed lifecycle/name/revision evidence for atomic refusal, and
cannot use local membership or typed input as server authorization.

## Review Corrections

Independent database review removed three future-hostile or seed-sensitive
assertions while preserving the 34 required invariants. Independent Swift
review repeatedly returned NO-GO until the implementation corrected:

- persisted first-sync status falsely establishing current-process readiness;
- presenter acceptance of ready-but-incomplete snapshots;
- silently trimmed display-name bytes;
- unstructured subscription observation and undrained subscription lifetime;
- delayed cached rows overwriting a fresh synchronized read;
- absent-public-baseline liveness and retained-epoch false readiness; and
- missing production-shaped SQL, scope, lifecycle, membership, and shutdown
  regressions.

Final database and Swift re-reviews returned GO with no remaining P0-P3
finding.

## Local Verification

- 14 focused PowerSync provider tests pass, including an encrypted retained-
  epoch regression using the production source;
- 512 Swift tests across 84 suites pass nonparallel;
- all six local pgTAP files pass, 210 assertions total, including 34 Space
  destination assertions;
- the localhost Data API read/denial matrix passes;
- database lint reports zero errors;
- target-environment/source-boundary checks and `git diff --check` pass;
- source-query reconciliation accepts the exact new verification integration:
  canonical package SHA-256
  `dc869d9038d65dfa4a6ec51ecd7552e20331564b3324d825f35d8e4659c4f35c`,
  workflow byte SHA-256
  `908fa8281ff9a688c7bdf0d0a387062c160f3e768ab609f464155c57bceb241b`,
  and post-update generator SHA-256
  `5dcc19a95ecccd1b72a9be18e7e9d5353e3eaeadb98a204876d9aca1ae2b77a3`;
  all 23 reconciliation tests pass and the 386-query/584-outcome artifact
  remains byte-exact;
- deterministic Xcode project generation adds only the two authorized staging
  source memberships; and
- macOS and generic iOS Simulator staging builds pass.

`SPACEDESTPICKER-TEST-001` through `-011` and `-013` pass locally.
`SPACEDESTPICKER-TEST-012`, the real isolated authenticated PowerSync session,
remains planned. A-003 and A-004 remain proposed. Immutable exact-head CI is
still required before this evidence can be promoted to verified.
