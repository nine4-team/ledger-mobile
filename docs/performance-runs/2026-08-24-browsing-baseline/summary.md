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
  28 tests in 2 suites, with 0 failures.
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

A deterministic serialized Debug simulator benchmark modeled 668 items, 80
spaces, 40 categories, and 80 invoices. The controlled run measured:

- filter/sort pipeline: 0.369 ms per evaluation;
- grouping: 0.930 ms per evaluation;
- 20-item selection total: 0.267 ms per evaluation;
- linear space/category/invoice card lookups: 41.315 ms per 668-card pass;
- indexed lookups: 0.272 ms per 668-card pass;
- measured lookup improvement: 152.0x.

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

- transaction filtering: 1.444 ms;
- invoice filtering: 4.117 ms.

The pre-fix and post-fix values establish an order-of-magnitude improvement, but
the exact multiplier is directional because the historical pre-fix suite was
not serialized.

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
668-item Firestore Codable pass at 10.537 ms in Debug.

That isolated cost cannot explain a multi-minute stall. It is nevertheless
confirmed main-thread work that can compound when account-wide and
project-scoped listeners deliver overlapping snapshots or trigger broad view
invalidation. Collection and query snapshot decoding now runs on a private
serial queue per repository. The first snapshot still decodes every document.
Later snapshots apply Firestore's document changes: added and modified documents
are decoded, removed documents are deleted from the decoded state, and the full
result is emitted in the current snapshot's query order. The serial queue
preserves snapshot arrival order, and completed arrays are still delivered on
the main queue exactly as before.

The integrated 668-item benchmark measured 0.289 ms for a one-document change
and 0.596 ms for a 20-document change, approximately 36.5x and 17.7x faster than
re-decoding all 668 documents. Equivalence tests cover additions, modifications,
removals, query reordering, malformed modified documents, and snapshots with no
document changes.

Listener scope, cache/server behavior, and update freshness are unchanged. A
publication is delayed only by the same decode work that previously blocked the
main queue, plus the next main-queue turn. Firebase's global callback queue was
not changed because several direct subscribers outside the repository mutate UI
state under the existing main-queue assumption.

Each active collection/query subscription now retains an ID-keyed decoded-value
dictionary in addition to the full array published by its context. This is a
modest memory tradeoff that should be checked on a physical device. Every
snapshot still rebuilds and publishes a full array, so broad SwiftUI invalidation
remains a separate architectural issue; this change only removes redundant
Codable decoding.

### 7. Duplicate projects-list subscription

`ProjectsListView` opened a second account-wide projects listener even though
`AccountContext.allProjects` is already the live source used for project
navigation and route resolution. The list now renders from that existing live
array. Its per-user project-preferences listener remains local because
AccountContext does not own that data.

This removes one listener and one duplicate decode/publication path while the
Projects screen is visible. Project card freshness, sorting, archive filtering,
navigation, and preferences behavior are unchanged.

### 8. Full-array publication and view invalidation

A controlled Debug benchmark assigned independent 668-item arrays through an
`@Observable` property. Equal-array publication measured 0.311 ms; a worst-case
change in the final item measured 0.327 ms. The corresponding filter/sort and
grouping passes measured 0.360 ms and 0.935 ms.

An Observation regression test verified that an equal full-array publication
causes zero observer notifications, while the changed array causes one. Direct
publication is therefore not a credible explanation for multi-second or
multi-minute stalls, and data-identical snapshots do not create the hypothesized
SwiftUI invalidation storm.

Real changes still correctly invalidate consumers. Diagnostic-only events now
record each Firestore snapshot's total/change counts and top-level project-items
and shared-list body evaluations. A physical Halrow trace is required before
splitting contexts into granular stores or changing view-state ownership.

### 9. macOS zoomable full-image main-actor work

After the publication experiment, a user on an updated macOS build reported a
new narrow reproduction: in Halrow project items with the no-space filter
active, opening an item/image caused a beachball lasting more than two minutes.

The zoomable full-image viewer bypassed the earlier `FirebaseImage` fix. Its
macOS loader was `@MainActor` and called `NSImage(data:)` after downloading the
full-resolution image. The iOS equivalent also constructed `UIImage` in its
inheriting task. In addition, the macOS gallery constructed a zoomable image
view for every attachment through `TabView`, creating a possible concurrent
full-image decode and memory multiplier.

Both platforms now use the detached display-preparing decoder, cancel stale
loads, and reuse the decoded-memory-bounded image cache. macOS instantiates only
the currently visible full-resolution image. This preserves image quality and
gallery commands; the next or previous image may show its spinner when selected
instead of being speculatively loaded.

### 10. Unbatched bulk item metadata writes

Project Items, Inventory Items, Transaction Detail, Space Detail, and Universal
Search each launched one independent task per selected item for status and space
changes. Every task called the generic single-item update path, which reread the
item and, for linked items, its transaction before writing. A 20-item action
could therefore produce roughly 20 item reads, up to 20 transaction reads, 20
writes, and 20 independently completing listener callbacks.

All five surfaces now call one `ItemsService.updateItems` operation with the
already-live selected item snapshots. The service validates every requested
field and item ID before writing, deduplicates item IDs, and commits one
Firestore batch for ordinary selections. It writes only the requested status
or space field, so a
bulk metadata action cannot overwrite a newer price or association value.
Selections above Firestore's 500-operation limit are committed in sequential
chunks. The API accepts only
status and space metadata; transaction association, category, project movement,
sales, returns, and deletion retain their dedicated multi-document operations.
Preexisting association/category data is neither rewritten nor used to block an
unrelated metadata change.

Visible menu contents and immediate selection clearing are unchanged. The
service propagates batch failure to its single caller task instead of creating
independent partial task failures. Production timing remains to be captured,
but the per-item read and task amplification is removed by construction.

### 11. macOS Item Detail navigation transaction loop

Release 52 and the current Debug app both reproduced an infinite Item Detail
navigation hang against a 546-item production project. The process remained at
99-100% CPU, and samples showed repeated SwiftUI `AttributeGraph` updates rather
than a thread blocked on Firestore or image download. A static destination
opened normally, but the original `ItemDetailView` type still looped even after
its body was reduced to one static label and its content, presentations,
toolbar, find registration, and listener lifecycle were independently removed.

The navigation destination is now a lightweight wrapper that yields one
scheduler turn before mounting the unchanged state-heavy detail implementation.
This keeps its large dynamic-property graph out of the parent list's navigation
push transaction. The first full production-backed detail opened in 1.387
seconds; three repeats opened in 1.362-1.530 seconds, Back returned in
1.241-1.272 seconds, and settled CPU was 0.0%. All detail sections and toolbar
controls remained present. The only possible visible difference is one
background-colored frame during the push; live listeners start on the following
scheduler turn and retain their original freshness behavior.

## Ranked Readout

1. **Item Detail navigation transaction loop:** exact release 52 infinite-hang
   reproduction confirmed at 99-100% CPU and fixed by deferring the state-heavy
   detail mount one scheduler turn. Four production-backed opens and Back
   operations completed responsively with the full UI intact.
2. **Zoomable full-image main-actor work:** strongest current
   interaction-specific causal candidate after a user reproduced a two-minute
   macOS beachball while opening an item image. Remediated; same-item retest is
   pending.
3. **Leaked project listeners:** confirmed architectural defect and plausible
   source of progressively worsening browsing pressure. Fixed and regression
   tested.
4. **Per-card linear metadata lookup churn:** measured frame-budget problem.
   Fixed on the shared item-card/list path with synchronous freshness tests.
5. **Main-actor financial publication:** a confirmed half-second synthetic
   callback path for limited-access accounts, reduced to approximately 3 ms.
6. **Repeated Firestore snapshot decoding:** confirmed architecture risk. A
   668-item full decode measured 10.537 ms. Subsequent one- and 20-document
   changes now measure 0.289 ms and 0.596 ms while preserving ordered,
   main-queue publication and live freshness.
7. **Remaining account/project listener overlap:** item, transaction,
   proto-item, and space listeners still overlap by scope. A stable trace is
   needed before choosing between account-listener suspension and deriving
   project subsets from account data.
8. **Duplicate projects-list subscription:** confirmed redundant listener.
   Removed by rendering the list from AccountContext's existing live projects.
9. **Full-array observable publication:** 0.311-0.327 ms at 668 items, and
   equal arrays do not notify observers. Not a primary cause; downstream SwiftUI
   fan-out from real changes remains pending physical measurement.
10. **List filtering, grouping, and selection totals:** measured too small to be
   a primary cause at 668 items, unless SwiftUI causes an unexpectedly large
   number of reevaluations.
11. **Unbatched bulk item metadata writes:** confirmed implementation defect.
   Status and space changes now use one validated batch operation across all five
   item bulk surfaces. This improves action completion and callback pressure but
   does not explain slow browsing before a bulk operation begins.

## Evidence Unavailable

- A classified iOS crash, watchdog termination, or jetsam report.
- A physical-device Halrow reproduction trace.
- Reliable cold-network Firestore, Storage, or image latency.
- A network-sensitive remediation ranking for Firestore first-snapshot and
  image-loading work.

## Behavior Safeguards

The diagnostics are disabled by default and do not change UI presentation,
listener scope or freshness, Firestore writes, or image-request concurrency.
The new snapshot/body correlation events are also diagnostics-gated and record
only collection kinds and counts, never customer IDs or field values.

The listener cleanup and lookup indexes also preserve visible behavior and
freshness. Cleanup occurs only after a project context is destroyed; lookup
indexes are rebuilt synchronously from each published source-array value.
Image cache eviction now reflects decoded memory rather than compressed payload
size, and image preparation moved off the main actor without resizing images.
Firestore collection/query decoding now occurs on a private serial queue, with
the same live snapshots published on the main queue in arrival order. Initial
snapshots are fully decoded; later snapshots incrementally update an ID-keyed
decoded state and reconstruct the result in the current query order. No updates
are debounced or suppressed.

## Verification

- Performance diagnostics and loading lifecycle suites: 17 tests passed.
- Optimized diagnostics benchmark suite: 8 tests passed.
- Combined financial-policy, lifecycle, and performance suites after the
  publication optimization: 25 tests passed.
- Latest focused performance suite, including image cache/decode coverage: 11
  tests passed on the iOS simulator.
- Latest combined performance and lifecycle run, including Firestore queue,
  cancellation, incremental equivalence, observable publication behavior, and
  668-item coverage: 28 tests passed on the iOS simulator.
- Canonical serialized performance suite: 18 tests passed. Earlier synthetic
  benchmark numbers are directional because Swift Testing ran them in parallel;
  the experiment ledger identifies the controlled result bundle.
- Zoomable full-image and media-gallery focused run: 84 tests passed on the iOS
  simulator; macOS Debug app build passed.
- Production-backed iOS simulator bulk-write check: two inventory items updated
  together through one status action in 1.655 seconds, then both were restored
  to their original status in 1.588 seconds.
- Production-backed macOS Item Detail check: four opens from a 546-item project
  completed in 1.362-1.530 seconds, with Back completing in 1.241-1.272 seconds
  and settled CPU at 0.0%.
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
5. Correlate Firestore snapshot total/change counts with repository callbacks,
   context publications, project-items/shared-list body evaluations, list
   derivations, card lookups, image work, main-thread stalls, and memory.
6. Correlate any crash time with device analytics before choosing a fix.
