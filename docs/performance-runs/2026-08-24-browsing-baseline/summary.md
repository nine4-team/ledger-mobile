# Browsing Performance Baseline: Network-Limited Run

Date: 2026-08-24

## Run Classification

This run is **network-limited**. The active internet connection was degraded,
and both physical iPhones registered with Xcode were offline. Cold Firestore,
Firebase Storage URL resolution, and image-download durations from this run are
not valid evidence for ranking architectural remediations.

## Evidence Available

- No Ledger crash or hang reports were present in the local macOS Diagnostic
  Reports directory.
- The diagnostics foundation and focused instrumentation compile in the iOS
  and macOS application targets.
- The focused diagnostics and lifecycle suites passed after the final changes:
  24 tests in 2 suites, with 0 failures.
- Main-thread heartbeat delay, process-memory trends, listener and task counts,
  context publication time, list derivation time, card lookup time, image
  decoding, and warm-cache navigation remain valid measurements under degraded
  internet.

## Offline Findings and Changes

### 1. Project listener lifecycle leak

Each `ProjectContext` test configuration starts 9 Firestore listeners. The
production project-detail configuration can start up to 11 because it also
enables proto-item and user-preference subscriptions. Locally owned contexts in
project detail and scoped transaction detail had no destruction cleanup.

The Firebase SDK source bundled in DerivedData states that destroying a
`ListenerRegistration` does not automatically stop listening. A regression
test confirmed the application bug: after releasing an active
`ProjectContext`, 0 of 9 listener registrations received `remove()`.

A listener-ownership bag now removes every registration when the context is
destroyed. The same regression test passes with 9 of 9 removals. This changes
no visible navigation or live-data behavior while the owning context is alive;
it only stops obsolete listeners after that context has been released.

### 2. Repeated card metadata scans

A deterministic Debug simulator benchmark modeled 668 items, 80 spaces, 40
categories, and 80 invoices. The latest representative run measured:

- filter/sort pipeline: 0.449 ms per evaluation;
- grouping: 1.068 ms per evaluation;
- 20-item selection total: 0.265 ms per evaluation;
- linear space/category/invoice card lookups: 40.270 ms per 668-card pass;
- indexed lookups: 0.258 ms per 668-card pass;
- measured lookup improvement: 156.2x.

The optimized simulator run measured 0.184 ms for filter/sort, 0.724 ms for
grouping, 0.091 ms for selection, 6.341 ms for linear card lookups, and 0.126
ms for indexed card lookups. The indexed path remained 50.2x faster after
compiler optimization.

The raw list, grouping, and selection calculations are therefore not credible
explanations for a multi-second or multi-minute stall by themselves. Repeated
linear card lookups can miss frame budgets and amplify broad SwiftUI
invalidation, but also do not explain minutes in isolation.

Account-level space names, category names, and per-item invoice status now use
indexes rebuilt synchronously whenever their source arrays are replaced. Tests
verify invoice-status priority and that replacing or clearing source arrays
immediately replaces or clears the indexes, preventing stale derived data.

### 3. Duplicate project listeners

Every project context also opened an account-wide projects listener whose
`ProjectContext.projects` value had no reader anywhere in the application.
That listener was removed; AccountContext remains the sole live projects-list
owner used by navigation.

ProjectContext also opened its own account-wide budget-category listener even
though AccountContext already owns the same live query. Project contexts now
receive AccountContext's raw category snapshot during activation and on every
category or membership change. Passing the raw snapshot is important because
financial-access classification cannot safely use the already-filtered public
category array. Tests verify that no duplicate category listener starts and
that employee/owner access changes immediately refresh visible categories.

These changes reduce the test ProjectContext from 9 listeners originally to 7.
The production configuration drops from up to 11 to up to 9, depending on
optional proto-item and user-preference subscriptions.

### 4. Financial publication complexity

The account listener callback applies financial-access filtering on the main
actor. A synthetic Debug benchmark with 2,000 transactions, 100 categories,
and 200 legacy invoices measured the original implementation at:

- transaction filtering: 17.538 ms;
- invoice filtering: 509.954 ms.

The transaction path searched the category array repeatedly. The invoice path
rebuilt the full transaction dictionary once for every invoice. Both now build
category and transaction indexes once per publication. The identical benchmark
after the change measured:

- transaction filtering: 1.233 ms, about 14x faster;
- invoice filtering: 3.357 ms, about 152x faster.

All financial-access policy tests pass, including limited fee-category and
invoice visibility behavior.

### 5. Image memory and main-actor decode pressure

`FirebaseImage` originally constructed `UIImage`/`NSImage` from downloaded data
inside a SwiftUI task running on the main actor. It also charged the 50 MB
`NSCache` with compressed download bytes even though a 4,000 by 3,000 RGBA image
occupies roughly 48 MB after decoding. Highly compressed thumbnails and
full-image fallbacks could therefore retain far more decoded memory than the
declared cache limit while image preparation blocked UI work.

The cache now charges the larger of compressed bytes and estimated decoded
pixel bytes. Image construction and display preparation run in a cancellable
detached task, then only the prepared platform image is published back to the
view. The original resolution and URLs are unchanged. The user-visible tradeoff
is limited to earlier RAM eviction under pressure; an evicted image can be
reloaded from the existing URL disk cache.

### 6. Firestore snapshot decoding on the main queue

The bundled Firebase SDK documents that Firestore completion and event handlers
use the main queue by default. `FirestoreRepository` then decoded every document
in collection and query snapshots synchronously inside that callback before a
context could publish the result. A representative local benchmark measured a
668-item Firestore Codable pass at 10.326 ms in Debug.

That isolated cost cannot explain a multi-minute stall. It is nevertheless
confirmed main-thread work that can compound when account-wide and
project-scoped listeners deliver overlapping snapshots or trigger broad view
invalidation. Collection and query snapshot decoding now runs on a private
serial queue per repository. The serial queue preserves snapshot arrival order,
and completed arrays are still delivered on the main queue exactly as before.

Listener scope, cache/server behavior, and update freshness are unchanged. A
publication is delayed only by the same decode work that previously blocked the
main queue, plus the next main-queue turn. Firebase's global callback queue was
not changed because several direct subscribers outside the repository mutate UI
state under the existing main-queue assumption.

## Ranked Readout

1. **Leaked project listeners:** confirmed architectural defect and plausible
   source of progressively worsening browsing pressure. Fixed and regression
   tested.
2. **Per-card linear metadata lookup churn:** measured frame-budget problem.
   Fixed on the shared item-card/list path with synchronous freshness tests.
3. **Main-actor financial publication:** a confirmed half-second synthetic
   callback path for limited-access accounts, reduced to approximately 3 ms.
4. **Main-queue Firestore snapshot decoding:** confirmed architecture risk.
   A 668-item decode measured 10.326 ms in isolation and now runs on a serial
   background queue while preserving ordered main-queue publication.
5. **Remaining account/project listener overlap:** item, transaction,
   proto-item, and space listeners still overlap by scope. A stable trace is
   needed before choosing between account-listener suspension and deriving
   project subsets from account data.
6. **Image decode and memory pressure:** confirmed architectural risk. Decoded
   memory is now bounded correctly and display preparation no longer runs on
   the main actor. Cold image-download timing remains unranked because the
   network measurements are invalid in this run.
7. **List filtering, grouping, and selection totals:** measured too small to be
   a primary cause at 668 items, unless SwiftUI causes an unexpectedly large
   number of reevaluations.
8. **Unbatched bulk writes:** remains a write-completion and callback-storm
   issue, but does not explain slow browsing before a bulk operation begins.

## Evidence Unavailable

- A classified iOS crash, watchdog termination, or jetsam report.
- A physical-device Halrow reproduction trace.
- Reliable cold-network Firestore, Storage, or image latency.
- A network-sensitive remediation ranking for Firestore first-snapshot and
  image-loading work.

## Behavior Safeguards

The diagnostics are disabled by default and do not change UI presentation,
listener scope or freshness, Firestore writes, or image-request concurrency.

The listener cleanup and lookup indexes also preserve visible behavior and
freshness. Cleanup occurs only after a project context is destroyed; lookup
indexes are rebuilt synchronously from each published source-array value.
Image cache eviction now reflects decoded memory rather than compressed payload
size, and image preparation moved off the main actor without resizing images.
Firestore collection/query decoding now occurs on a private serial queue, with
the same live snapshots published on the main queue in arrival order.

## Verification

- Performance diagnostics and loading lifecycle suites: 17 tests passed.
- Optimized diagnostics benchmark suite: 8 tests passed.
- Combined financial-policy, lifecycle, and performance suites after the
  publication optimization: 25 tests passed.
- Latest focused performance suite, including image cache/decode coverage: 11
  tests passed on the iOS simulator.
- Latest combined performance and lifecycle run, including Firestore queue,
  cancellation, and 668-item decode coverage: 24 tests passed on the iOS
  simulator.
- Listener regression before fix: 0 of 9 registrations removed; test failed.
- Listener regression after fix: 9 of 9 registrations removed; test passed.
- macOS Debug scheme build: passed.
- Full iOS target: 925 tests executed. The run was not green because 42
  emulator integration tests could not authenticate and 3 unrelated
  price-policy expectation tests fail independently. The focused changed-path
  suites are green.

## Next Valid Capture

When a physical iPhone and a stable connection are available, enable
`-LedgerPerformanceDiagnostics YES` and capture the same scenarios:

1. Open Halrow and wait for its item list to settle.
2. Select 20 items and open the bulk action menu.
3. Open an item and navigate back ten times.
4. Repeat the navigation once with warm caches.
5. Record main-thread stalls, memory, active listeners and tasks, context
   publications, list derivations, card lookups, image work, and Firestore
   callback timing.
6. Correlate any crash time with device analytics before choosing a fix.
