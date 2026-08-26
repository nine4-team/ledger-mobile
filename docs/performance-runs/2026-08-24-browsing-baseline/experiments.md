# Browsing Performance Experiment Ledger

Date opened: 2026-08-24

This file is the canonical experiment record for the browsing freeze, crash,
and latency investigation. The run summary describes the current diagnosis;
this ledger preserves how each conclusion was reached.

## Experiment Standard

Every performance experiment must record:

1. hypothesis and user-visible symptom it could explain;
2. code path and data scale under test;
3. environment, build configuration, and network classification;
4. exact measurement method and output;
5. result, limitations, and confidence;
6. behavior, freshness, and UI implications of any proposed change;
7. decision and the evidence required to revisit it.

Synthetic benchmarks are evidence about local computational complexity. They
are not substitutes for a physical-device trace, memory-pressure report, hang
report, or crash classification.

## Measurement Validity

The connection was degraded and both registered physical iPhones were offline.
Network-dependent timings from this run are invalid. CPU-only simulator tests,
source audits, lifecycle tests, and local memory calculations remain useful.

The performance suite originally allowed Swift Testing to run benchmarks in
parallel. Results recorded before the suite was marked `.serialized` can be
used as historical directional evidence, but not for precise cross-benchmark
comparison. The canonical controlled run is:

- simulator: iPhone 17 Pro, iOS 26.0, arm64;
- build: Debug test configuration;
- suite: `PerformanceDiagnosticsTests`, serialized;
- result bundle: `Test-LedgeriOS-2026.08.24_13-44-35--0700.xcresult`;
- result: 18 tests passed, 0 failed.

## E01: Project Listener Teardown

**Hypothesis:** project contexts survive navigation and leave Firestore
listeners active, producing progressively worse browsing pressure and possible
memory growth.

**Method:** activate a test `ProjectContext`, release it, and count calls to
`ListenerRegistration.remove()` for all registrations owned by the context.

**Result:** before the fix, 0 of 9 registrations were removed. After adding the
listener ownership bag, 9 of 9 were removed.

**Decision:** confirmed defect; fixed and protected by a lifecycle regression
test. No live-data or UI behavior changes while a context remains alive.

## E02: Per-Card Metadata Lookup Complexity

**Hypothesis:** linear space, category, and invoice searches performed for every
card can consume frame budgets when a large list is invalidated.

**Method:** model 668 items, 80 spaces, 40 categories, and 80 invoices. Compare
the original linear lookup pass with ID-keyed dictionaries.

**Controlled result:**

- linear card lookup pass: 41.315 ms;
- indexed card lookup pass: 0.272 ms;
- improvement: 152.0x.

**Decision:** confirmed frame-budget defect; fixed. Indexes rebuild
synchronously whenever source arrays change, so there is no stale-data window.

## E03: Financial Publication Complexity

**Hypothesis:** account-wide transaction and invoice filtering blocks the main
actor during listener publication.

**Method:** model 2,000 transactions, 100 categories, and 200 legacy invoices.
Profile access-policy publication before and after replacing repeated searches
and per-invoice dictionary rebuilds with one-pass indexes.

**Historical pre-fix result:** 17.538 ms for transaction filtering and 509.954
ms for invoice filtering.

**Controlled post-fix result:** 1.444 ms for transaction filtering and 4.117 ms
for invoice filtering.

**Decision:** confirmed architectural hotspot; fixed. The exact speedup is
directional because the historical pre-fix suite was not serialized. Financial
visibility policy and tests are unchanged.

## E04: Image Decode and Cache Accounting

**Hypothesis:** platform-image construction on the main actor and cache charges
based on compressed bytes can cause browsing stalls and memory-pressure exits.

**Method:** audit the image request actor path and compare compressed payload
size with decoded pixel memory. Verify display-ready image creation off the
caller actor and deterministic cache-cost calculation.

**Result:** a 4,000 by 3,000 RGBA image requires roughly 48 MB decoded even when
its downloaded payload is much smaller. Image preparation previously ran on the
main actor and the cache charged only compressed bytes.

**Decision:** confirmed risk; fixed by preparing images off the main actor and
charging estimated decoded memory. Physical-device memory plateau and eviction
behavior remain unmeasured because the device was unavailable.

## E05: Firestore Decode Placement and Incrementality

**Hypothesis:** decoding every document for every collection/query snapshot on
Firebase's default main callback queue contributes to stalls and callback
storms.

**Method:** model 668 Firestore-encoded items. Measure a full decode, a
one-document incremental change, and a 20-document incremental change. Verify
add, modify, remove, reorder, decode-failure, cancellation, and callback-order
semantics.

**Controlled result:**

- full decode: 10.537 ms;
- one-document change: 0.289 ms, about 36.5x faster;
- 20-document change: 0.596 ms, about 17.7x faster.

**Decision:** confirmed bounded hotspot; fixed. Initial snapshots still decode
fully. Later snapshots decode added/modified documents only, process removals,
reconstruct current query order, and publish on main in arrival order. Listener
scope, cache/server behavior, and freshness are unchanged.

## E06: Duplicate Subscription Audit

**Hypothesis:** identical listeners create redundant decode, publication, and
view invalidation work.

**Method:** trace listener ownership and all readers for project metadata,
budget categories, and the projects list.

**Result:** `ProjectContext.projects` had no readers; its listener was removed.
The duplicate project budget-category query was replaced with the same live raw
snapshot already owned by `AccountContext`. `ProjectsListView` also duplicated
the exact account-wide projects query and now reads `AccountContext.allProjects`.

**Decision:** remove only exact duplicates with established ownership. Do not
replace project/inventory scoped item listeners with account-wide arrays without
a separate freshness, memory, and lifecycle decision.

## E07: Full-Array Publication and SwiftUI Invalidation

**Hypotheses:**

- H1: assigning a 668-item array to an `@Observable` context is itself a major
  source of latency;
- H2: data-identical full-array publications unnecessarily invalidate views;
- H3: real item changes may cause broad downstream recomputation even when the
  direct setter is inexpensive.

**Method:** alternate independent 668-item arrays through plain and
`@Observable` properties. Measure scalar observation overhead, equal-array
publication, a worst-case changed array whose final element differs, filter/sort,
and grouping. Use `withObservationTracking` to verify notification behavior.

**Controlled result:**

- plain array assignment: below 0.001 ms;
- observable scalar assignment: below 0.001 ms;
- equal observable array publication: 0.311 ms;
- changed-last observable array publication: 0.327 ms;
- filter/sort after publication: 0.360 ms;
- grouping after publication: 0.935 ms;
- equal-array observer notifications: 0;
- changed-array observer notifications: 1.

**Interpretation:** Observation performs an equality check for the `Equatable`
item array. That scan is measurable but cannot explain seconds or minutes.
Data-identical arrays do not invalidate observers. A real item change correctly
invalidates consumers; the remaining unknown is how much SwiftUI body, layout,
card, image, and navigation work follows that notification on a physical device.

**Instrumentation added:** `FirestoreSnapshotReceived` records total documents
and changed documents. `ViewBodyEvaluated` records project-items and shared-list
body evaluations. Existing events record repository callbacks, main-actor
delivery, context publication, list derivation, card lookup, stalls, and memory.
No customer identifiers or field values are logged.

**Decision:** reject H1 and H2 as primary causes. Do not introduce granular
per-item observable stores, suppress live changes, or alter listener scope yet.
Test H3 on Halrow by correlating each Firestore snapshot and context publication
with body-evaluation counts, aggregate list/card work, main-thread heartbeat,
and memory.

**Revisit threshold:** consider view-boundary or granular-state architecture
only if a physical trace shows one item publication causing repeated list-body
evaluation or more than one frame of downstream main-thread work. Consider
listener-scope changes only if overlapping account/project publications are
measured and their ownership/freshness requirements are documented first.

## E08: macOS Full-Resolution Image Beachball

**User reproduction:** on an updated macOS build, a user opened the large
Halrow project's item section with the "no space assigned" filter active, opened
an item to inspect its image, and encountered a macOS beachball lasting more
than two minutes.

**Hypothesis:** opening the zoomable full-resolution image performs image
construction and pixel preparation on the main actor. The gallery may amplify
the work by constructing zoom views for every attachment when only one image is
visible.

**Source evidence:** both platform implementations of `ZoomableScrollView`
downloaded full image data and called `UIImage(data:)` or `NSImage(data:)` from
an inheriting task. The macOS `loadImage` method was explicitly `@MainActor`.
This path bypassed the detached `PlatformImageDecoder` already used by
`FirebaseImage` thumbnails. The macOS `ImageGallery` also built a `TabView`
containing a zoomable full-image view for every attachment.

**Remediation:**

- route iOS and macOS zoomable-image construction through the detached,
  display-preparing `PlatformImageDecoder`;
- reject canceled or superseded loads before publishing an image;
- reuse the decoded-memory-bounded `ImageCache` for repeat opens;
- track active zoomable requests and full-image decode duration;
- instantiate only the currently visible full-resolution image on macOS.

**Behavior implications:** image URLs, resolution, zoom limits, previous/next
controls, save, share, and pin behavior are unchanged. macOS no longer
pre-constructs every gallery image. A newly selected next/previous image may
show its existing loading spinner until that image loads, rather than being
incidentally prefetched. This trades speculative bandwidth and memory for a
responsive main run loop.

**Filter assessment:** the no-space filter is important reproduction context,
but no filter-specific work occurs in the full-image decode path. It remains a
possible contributor to navigation invalidation, not the direct source-level
cause identified here.

**Verification:** a 2,048 by 1,536 image regression exercises the zoomable
viewer through the detached decoder. The focused performance and media-gallery
run passed 84 tests, and the macOS Debug app build passed.

**Confidence and decision:** high-confidence causal match, but not a captured
stack trace. Ship the remediation and ask the reporter to repeat the same item,
filter, and image. If the beachball persists, capture a macOS sample while it is
hung and correlate item-detail startup, gallery presentation, and image decode
events.

## E09: Bulk Item Metadata Task and Read Amplification

**Hypothesis:** status and space bulk actions complete slowly because every
selected item starts an independent task through the generic single-item update
path, producing redundant reads, writes, and independently arriving listener
callbacks.

**Source evidence:** Project Items, Inventory Items, Transaction Detail, Space
Detail, and Universal Search all looped over selected items and created one
`Task` plus `ItemsService.updateItem` call per item. That service rereads the
item and, when linked, its transaction before issuing the write.

**Remediation:** add a shared `ItemsService.updateItems` operation that uses the
selected live item snapshots, validates all inputs before writing, deduplicates
IDs, and issues Firestore batch updates in chunks of at most 500 operations.
Each write contains only the requested status or space field, preventing stale
selected snapshots from overwriting unrelated price or association data.
Migrate every item bulk-menu surface to one task and one service call per user
action.

**Behavior implications:** the API is intentionally restricted to `status` and
`spaceId`. Transaction/category association and project movement remain on
their dedicated multi-document operations. Menu structure, picker behavior,
freshness, and immediate selection clearing are unchanged. An ordinary bulk
selection commits atomically; selections above 500 items require sequential
Firestore batches and can therefore partially complete if a later chunk fails.

**Verification:** focused service tests cover one-batch status updates without
transaction reads or unrelated field writes, null space assignment, duplicate
IDs, unsupported fields, missing IDs, legacy category state, 501-item chunking,
commit-error propagation, and empty input.

On 2026-08-25, the production-backed iOS simulator was also verified against an
authenticated playground account. A two-item Business Inventory selection was
changed from Purchased to To Purchase through the bulk menu. Both listener-backed
cards reflected the new status together in 1.655 seconds, including the UI
automation stabilization delay. The same two items were restored to Purchased
in 1.588 seconds and the final list confirmed both original values. No account
or item identifiers were retained in the experiment artifacts.

**Decision:** implement independent of the browsing diagnosis. It directly
removes write-completion and callback amplification but is not evidence about
latency before a bulk action starts.

## E10: macOS Item Detail Navigation AttributeGraph Loop

**User reproduction:** a release 52 macOS user opened an item from a large
project and encountered an infinite spinner/beachball that required a force
quit. The reported action was opening Item Detail, not selecting an item or
opening its image.

**Exact reproduction:** the signed release 52 app and the current Debug app
both reproduced against the same 546-item production project. Clicking a card
body left the process at 99-100% CPU with growing memory. A five-second process
sample placed the main thread in repeated SwiftUI `AttributeGraph` updates.

**Isolation results:** replacing the destination with static text opened in
1.272 seconds and remained responsive. The real `ItemDetailView` still looped
after independently removing or bypassing the nested item-list lazy stack, the
source list while detail was active, pinned list headers, the Item Detail
toolbar, broad item-array route resolution, full detail content, inactive sheet
and nested-destination hosts, find registration, focused listeners, and lineage
startup. Even a static one-line body looped while it remained inside the
original state-heavy `ItemDetailView` type. This rules out item payload size,
network waiting, image decode, the source list, and any one visible detail
section as the immediate trigger.

**Remediation:** make the navigation destination a lightweight
`ItemDetailView` wrapper. It first mounts a background-colored frame, yields
one scheduler turn, and then mounts the unchanged stateful
`ItemDetailContentView`. This prevents SwiftUI from adding the detail view's
large dynamic-property graph during the same transaction that pushes away the
546-item parent hierarchy.

**Behavior and freshness implications:** Item Detail layout, media, notes,
details, toolbar, sheets, nested navigation, focused Firestore listeners, and
lineage behavior are unchanged. The only presentation difference is a possible
single background-colored frame during the push. The focused item listener
starts one scheduler turn later; no update is debounced, cached in place of a
listener, or suppressed.

**Production-backed verification:** the full detail screen opened in 1.387
seconds on the first remediated run. Three additional opens completed in
1.362-1.530 seconds; all expected detail sections and toolbar controls were
present. Back completed in 1.241-1.272 seconds each time and returned to the
546-item list. After settling, the app measured 0.0% CPU instead of the
reproduced 99-100% loop. The macOS build also compiled the iOS application and
test targets successfully.

**Decision:** confirmed navigation-transaction defect; fixed with the deferred
detail mount. Keep the diagnostics because other browsing crashes may have
independent causes.

## E11: macOS Search Item to Transaction Detail AttributeGraph Loop

**User reproduction:** a release 53 macOS user searched for an item, opened it,
then clicked its linked transaction and encountered an indefinite beachball.

**Exact reproduction:** the signed release 53 app reproduced on the 1584 Design
production account. Universal Search opened an item in Witzenman's project, but
opening its linked Wayfair transaction timed out after 18 seconds. The process
remained at 97% CPU. A five-second sample showed the main thread continuously
performing `NSHostingView` layout and SwiftUI `AttributeGraph` updates, including
repeated `TransactionDetailView.body` and selection derivation evaluations. No
Firestore wait, image decode, or blocked network stack appeared on the hot path.

**Remediation:** make `TransactionDetailContainer` a lightweight navigation
wrapper. It mounts the background, yields one scheduler turn, and then mounts a
private stateful container that preserves the existing project-scope resolution,
scoped `ProjectContext`, live listeners, asynchronous lineage loads, sections,
and nested destinations.

**Behavior and freshness implications:** transaction content, expanded-section
defaults, controls, listener scope, and freshness are unchanged. The only
possible visual difference is one background-colored frame during navigation.
Scoped context activation and focused transaction listeners begin on the next
scheduler turn; no snapshots are cached, debounced, or suppressed.

**Production-backed verification:** the previously hanging 37-item transaction
rendered completely in the remediated Debug app, including three receipts,
notes, details, item drafts, and item controls. The first automated transition
stabilized in 8.756 seconds and a warm repeat in 4.090 seconds; these include UI
automation stabilization and are not direct first-paint measurements. Back
returned to the item in 2.359 seconds. The process settled at 0.0% CPU after
each successful open instead of remaining at 97%. After applying the same
change to the full working tree and rebuilding both app targets, the exact
Search-item-to-transaction path completed in 1.943 seconds; the preceding item
open completed in 1.807 seconds and CPU again settled at 0.0%.

**Decision:** confirmed second navigation-transaction defect; apply the same
deferred-mount boundary to transaction detail and retain the current live data
architecture.

## E12: Navigation Destination Audit and Cross-Project Space Scope

**Motivation:** two independently reproduced 97-100% CPU navigation loops in
Item Detail and Transaction Detail indicate an architectural trigger rather
than two unrelated screens. Audit every navigation destination before waiting
for another user report.

**Static audit:** all app `navigationDestination` call sites were classified by
parent hierarchy size, destination dynamic-property graph, synchronous work,
and data-scope ownership. The three largest entity detail surfaces are Item,
Transaction, and Space. Item and Transaction already have deferred mount
boundaries from E10 and E11. Space still mounted 18 local state slots, five
environment dependencies, an item list, bulk-action hosts, and a focused space
listener in the navigation push transaction.

**Production finding:** Universal Search listed a project space with 157 items,
but opening it displayed zero items. The transition completed in 2.052 seconds,
so the absent project data hid the destination's real graph. Search had no
activated `ProjectContext`, while `SpaceDetailView` read project items,
transactions, and spaces exclusively from that ambient context.

**Remediation:** make `SpaceDetailView` a lightweight deferred wrapper. After
one scheduler yield, a private container reuses the ambient `ProjectContext`
when it already owns the route's project, uses `InventoryContext` for inventory
spaces, and creates an isolated live `ProjectContext` only for cross-project
entry points such as Search or an item opened outside its project.

**Behavior and freshness implications:** the visible space screen, expansion
defaults, media, notes, checklists, item actions, bulk actions, and focused space
listener are unchanged. In-project routes do not add another project context.
Cross-project routes now receive the same live project-scoped subscriptions as
Project Detail; no update is cached, debounced, or suppressed. As with Item and
Transaction Detail, the only possible presentation difference is one
background-colored frame during the push.

**Production-backed verification:** the same Search result now opened in 1.951
seconds and displayed all 157 items. The full space controls and initial item
rows were present, and the process settled at 0.0% CPU. The macOS Debug scheme
build also compiled and signed both macOS and iOS app/test products. An
in-project route reused its active context and displayed all 21 expected items.
UI automation stabilized in 10.218 seconds because multiple thumbnail views
remained busy; the process settled at 0.0% CPU, distinguishing that known
image/network path from an AttributeGraph navigation loop.

**Remaining destination checks:** Search to Item Quick Draft completed in 1.470
seconds and settled at 0.0% CPU. Opening a 554-item project completed in 2.022
seconds. Its 207-row Invoice report completed in 1.479 seconds and settled at
0.0% CPU. These routes do not currently justify speculative deferred wrappers.
Invoice Detail and Inventory remain lower-risk watch points because their
destination graphs are materially smaller and their parent routes do not
combine the confirmed high-risk factors.

**Decision:** fix Space Detail's deferred mount and scope ownership. Retain the
explicit wrappers for the three large entity details rather than applying a
global navigation delay to every destination.

## Next Experiment

Repeat E10 and E11 on release hardware after distribution, including an item
opened from an active filter and a transaction opened directly from Search.
Separately, repeat E08 on the same macOS item, filter, and image using the
remediated build. Run the Halrow browsing and bulk-menu scenarios on a physical
iPhone with a stable connection and
`-LedgerPerformanceDiagnostics YES`. Classify any termination as exception,
watchdog, memory pressure/jetsam, or unknown before selecting another
remediation.
