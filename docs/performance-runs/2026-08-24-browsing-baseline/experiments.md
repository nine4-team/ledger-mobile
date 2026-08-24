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

## Next Experiment

First, repeat E08 on the same macOS item, filter, and image using the remediated
build. Separately, run the Halrow browsing and bulk-menu scenarios on a physical
iPhone with a stable connection and `-LedgerPerformanceDiagnostics YES`.
Capture an Instruments trace plus the diagnostic event stream. Classify any
termination as exception, watchdog, memory pressure/jetsam, or unknown before
selecting the next remediation.
