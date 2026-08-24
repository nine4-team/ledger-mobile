# Browsing Freeze, Crash, and Latency Diagnostics Plan

## Status

Instrumentation and offline investigation completed; stable-network physical
device capture remains pending.

This plan covers the measurement phase for Ledger's browsing freezes, crashes,
and navigation latency on iOS and macOS. It deliberately separates diagnosis
from remediation so listener ownership, data freshness, and UI behavior are not
changed based on an unmeasured theory.

## Priority

The priority order for this work is:

1. Prevent crashes during ordinary browsing.
2. Prevent UI freezes and multi-second main-thread stalls.
3. Reduce item-detail and back-navigation latency.
4. Preserve live-data freshness and existing UI behavior.
5. Optimize bulk-operation completion only after the browsing path is stable.

## Problem Statement

Observed behavior includes:

- frequent freezing and occasional crashing on iOS;
- macOS back navigation taking more than 10 seconds;
- severe latency when browsing a large project such as Halrow;
- bulk menu and bulk action latency, although crashes may also occur without a
  bulk operation;
- approximately 668 project items in the strongest known reproduction case.

The recent lazy item-list and project bulk-menu isolation changes improved the
project item list. They do not prove which remaining subsystem causes browsing
crashes or navigation stalls.

## Questions This Investigation Must Answer

1. Is the app blocked on the main actor during a visible freeze?
2. If so, is the block dominated by Firestore snapshot decoding, context
   publication, financial-access filtering, SwiftUI list derivation, per-card
   lookup work, image decoding, or another call tree?
3. Do account-wide and project-scoped listeners publish overlapping data during
   the same user operation?
4. Do listener, task, image-request, or view counts grow after repeated
   detail/back navigation?
5. Does resident memory reach a stable plateau, or grow until iOS terminates the
   process?
6. Are crashes ordinary exceptions with stack traces, watchdog terminations,
   memory-pressure terminations, or jetsam events without an app crash stack?
7. Does a slow back operation wait for network work, or is local UI work enough
   to explain it?
8. Which single remediation has the highest measured probability of preventing
   the reported freezes and crashes?

## Non-Goals

The diagnostic implementation must not:

- change listener ownership or listener scope;
- change Firestore queries, document structures, or write behavior;
- debounce, delay, or suppress live updates;
- change filtering, sorting, grouping, selection, or menu behavior;
- change image cache policy or request concurrency;
- add a user-visible diagnostics screen;
- add Crashlytics or another third-party telemetry dependency in the first pass;
- mix in bulk-write batching, lookup dictionaries, or speculative performance
  refactors before a baseline trace exists.

## Behavioral and Privacy Invariants

1. Diagnostics are disabled by default.
2. Enabling diagnostics must require an explicit launch argument or environment
   variable on a development/profile run.
3. No account IDs, project IDs, item IDs, names, image URLs, notes, prices, or
   other customer data may be written to logs or signposts.
4. Allowed metadata is limited to logical operation names, entity types,
   collection types, counts, durations, byte counts, image dimensions, cache
   results, active-operation counts, and coarse device/runtime state.
5. No diagnostic data leaves the device automatically.
6. Signposts and counters must not alter actor ownership or introduce waits in
   application code.
7. The instrumentation must be removable through a small number of clearly
   named files and call sites.

## Current Code Baseline

The first implementation pass should begin from these verified facts:

- `AccountContext` maintains account-wide listeners for items, proto-items,
  transactions, spaces, budget categories, projects, and invoices.
- Each `ProjectDetailContainer` creates an independent `ProjectContext` with
  project-scoped listeners for project detail, projects, transactions, items,
  proto-items, spaces, budget data, preferences, and notes.
- `AccountContext` and `ProjectContext` therefore intentionally have overlapping
  coverage while a project is open. The cost and invalidation impact have not
  been measured.
- `FirestoreRepository` decodes every document in each delivered query snapshot
  before invoking the context callback. It currently logs decoding failures but
  not snapshot timing, callback queue delay, or document-change size.
- Context callbacks enqueue `Task { @MainActor ... }`. Main-actor delivery delay
  is not currently measured.
- `SharedItemsList` recomputes filtered items, groups, visible IDs, and selection
  totals through computed properties. Invocation count and duration are not
  measured.
- `ItemCard` performs account-wide invoice and space searches during card
  evaluation. Aggregate lookup cost is not measured.
- `ItemDetailView` owns focused item and transaction listeners plus an async
  lineage load task. It removes/cancels them on disappear, but repeated lifecycle
  counts and cancellation completion are not measured.
- `ImageCache` declares a 50 MB cost limit but currently charges compressed image
  byte count, not decoded pixel memory. The relationship between cache cost and
  actual resident memory is unknown.
- `NavLifecycleLog` records a few debug lifecycle events, but it does not record
  intervals, memory, active counts, or correlations with a user-visible stall.
- The repository does not currently integrate MetricKit diagnostics or Firebase
  Crashlytics.

## Diagnostic Architecture

### Runtime Gate

Add a single runtime gate such as:

```text
-LedgerPerformanceDiagnostics YES
```

or:

```text
LEDGER_PERFORMANCE_DIAGNOSTICS=1
```

The diagnostic facade should return immediately when the gate is absent. The
gate allows an optimized local profile build to include diagnostics without
turning them on for ordinary users.

### Diagnostic Facade

Create a small `PerformanceDiagnostics` facade backed by `OSSignposter`,
`Logger`, and `ContinuousClock`.

It should support:

- synchronous intervals;
- asynchronous intervals with explicit begin/end tokens;
- point events;
- integer metadata such as item count or active listener count;
- a process-wide scenario/run identifier that contains no customer identifier;
- aggregate counters for high-frequency row work;
- a bounded in-memory ring buffer for the latest diagnostic events so the final
  seconds before a crash can be printed or persisted locally during a profile
  run.

Event and interval names must be static, low-cardinality values. Dynamic values
belong in numeric metadata, never in signpost names.

### Main-Thread Stall Monitor

Add a diagnostic-only heartbeat that schedules work onto the main actor from a
background monitor and measures delivery delay.

Classification:

- `notice`: at least 250 ms;
- `severe`: at least 1 second;
- `critical`: at least 5 seconds.

The monitor must pause while the app is inactive or backgrounded so suspension
is not reported as a freeze. It must report the current diagnostic scenario and
coarse memory footprint with each severe/critical stall.

### Memory Sampler

While a diagnostic scenario is active, sample process physical footprint at a
low fixed frequency, initially once per second. Also record:

- process physical footprint;
- app memory-warning notifications;
- `ProcessInfo.thermalState`;
- active image download count;
- approximate decoded image bytes created during the scenario;
- image-cache hit, miss, insert, and eviction-related counters available from
  the cache wrapper;
- active focused-listener and lineage-task counts.

Sampling stops when the scenario stops. It must not run continuously during
ordinary app use.

## Phase 0: Collect Existing Crash Evidence

Before changing application code, inspect evidence already available for the
affected builds:

1. Check Xcode Organizer/App Store Connect for iOS crash, hang, and energy
   reports for builds 46 and 47.
2. Classify every relevant report as one of:
   - app exception;
   - watchdog/hang termination;
   - memory-pressure or jetsam termination;
   - CPU exception;
   - disk-write exception;
   - unknown or unsymbolicated.
3. Confirm that dSYMs exist for each relevant build before treating a report as
   unusable.
4. Retrieve physical-device analytics logs for a known crash if Organizer has no
   report.
5. Record only build number, platform, OS version, device class, termination
   class, top symbolized frames, and occurrence count in the run summary.

Exit criteria:

- Existing crash evidence is either classified or explicitly recorded as
  unavailable.
- Lack of a crash report is not interpreted as evidence against an out-of-memory
  or jetsam termination.

## Phase 1: Build the Diagnostic Foundation

### Proposed Files

Create:

- `LedgeriOS/LedgeriOS/Diagnostics/PerformanceDiagnostics.swift`
- `LedgeriOS/LedgeriOS/Diagnostics/MainThreadStallMonitor.swift`
- `LedgeriOS/LedgeriOS/Diagnostics/ProcessMemorySampler.swift`
- `LedgeriOS/LedgeriOSTests/PerformanceDiagnosticsTests.swift`

Modify:

- `LedgeriOS/LedgeriOS/LedgerApp.swift`
- the Xcode project file to include the new sources;
- `NavLifecycleLog.swift` only if it can delegate to the new facade without
  changing existing debug behavior.

### Foundation Tests

Use pure/testable components for:

1. runtime-gate parsing;
2. stall-threshold classification;
3. bounded ring-buffer behavior;
4. counter increment/decrement behavior;
5. scenario start/stop reset behavior;
6. redaction rules that reject forbidden metadata keys;
7. disabled diagnostics producing no retained events.

### Foundation Acceptance Criteria

- iOS and macOS builds succeed with diagnostics disabled.
- Existing tests pass.
- A controlled 100 ms diagnostic interval appears in an Instruments Points of
  Interest trace with the expected name and approximate duration.
- The stall classifier has deterministic unit coverage without deliberately
  freezing the test runner.
- Idle overhead while enabled is measured and recorded; target is under 1% CPU
  and under 5 MB additional resident memory.
- Disabled overhead is below practical measurement noise.

## Phase 2: Instrument the Data Pipeline

### Firestore Repository

Instrument all three subscription shapes in
`Services/FirestoreRepository.swift`:

- collection listener registration;
- query listener registration;
- document listener registration;
- snapshot callback start;
- document count;
- `documentChanges.count` where available;
- cache-origin and pending-write metadata;
- full decode interval;
- decode-drop count;
- callback invocation interval;
- listener removal where ownership can be observed safely.

Use only the logical entity type, such as `items`, `transactions`, or `spaces`.
Do not log the account-scoped collection path.

### Context Delivery and Publication

Instrument `State/AccountContext.swift` and `State/ProjectContext.swift`:

- activation, early return, stop, and deactivation;
- listener count after activation;
- snapshot receipt time before enqueuing onto the main actor;
- main-actor queue delay before publication;
- assignment/publication interval and entity count;
- `applyFinancialAccess` interval and input/output counts;
- `recomputeBudgetProgress` interval;
- callback count by entity type;
- duplicate account/project publication timing for items, transactions, spaces,
  projects, and budget categories.

The instrumentation must observe duplicate coverage; it must not remove it in
this phase.

### Data-Pipeline Acceptance Criteria

- A single project activation produces a countable, named set of account and
  project listeners.
- A single snapshot shows separate decode time, main-actor queue delay, and
  publication time.
- Re-entering the same project confirms the existing activation early return
  without listener-count growth.
- Opening and closing an item detail returns focused listener/task counts to
  baseline.

## Phase 3: Instrument Browsing and Rendering

### Shared Item List

Instrument `Components/SharedItemsList.swift` at aggregate boundaries:

- `setupData` start/end and source mode;
- source item count changes;
- filter/sort/search computation duration;
- grouping duration and resulting group count;
- visible-ID and selected-total computation duration;
- inline and standalone list appearance/disappearance;
- group expansion count;
- selected-ID count changes;
- bulk action trigger to action sheet first appearance.

Do not emit a signpost for every row. High-frequency card work should use an
aggregate counter flushed at most once per second, because per-row logging could
create the latency being measured.

### Item Card Lookups

Instrument aggregate work in `Components/ItemCard.swift` and the relevant
`SharedItemsList` helper methods:

- invoice-status lookup count and total duration;
- space-name lookup count and total duration;
- category-name lookup count and total duration;
- grouped-space lookup count and total duration;
- menu-item construction count and total duration.

Instruments Time Profiler remains the source of truth for call stacks. These
counters answer how often the known linear searches occur in one interaction.

### Navigation and Focused Work

Instrument:

- `Views/Projects/ProjectDetailContainer.swift`;
- `Views/Projects/ProjectDetailView.swift`;
- `Views/Projects/ItemsTabView.swift`;
- `Views/Projects/ItemDetailView.swift`;
- focused transaction and space detail lifecycle where the reproduction enters
  those screens.

Measure:

- project route activation to first project-detail appearance;
- item tap to item-detail appearance;
- item-detail appearance to focused item listener's first value;
- transaction listener start/first value/stop;
- lineage task start, edge query, number of transaction fallbacks, completion,
  cancellation request, and post-cancellation completion;
- item-detail disappearance to parent item-list reappearance;
- repeated navigation cycle number;
- active focused listener/task counts before and after each cycle.

### Images and Memory

Instrument `Components/FirebaseImage.swift` and `Services/ImageCache.swift`:

- request start and completion;
- active request count;
- cache hit/miss;
- Storage URL resolution interval;
- network download interval and compressed byte count;
- image decode interval;
- decoded pixel dimensions and estimated decoded bytes (`width * height * 4`);
- cancellation and failure stage;
- fallback attempt count;
- cache insertion using both declared cache cost and estimated decoded cost.

Coordinate this instrumentation with the separate Space thumbnail repair. Do
not overwrite or revert that work.

### Browsing-Instrumentation Acceptance Criteria

- Every visible scenario boundary can be correlated to a signpost interval.
- A severe main-thread stall can be aligned with a Time Profiler call tree.
- Repeated item-detail navigation exposes whether listener, task, request, and
  memory counts return to baseline.
- Image diagnostics distinguish URL resolution, download, decode, and cache
  behavior without recording a URL.

## Phase 4: Controlled Reproduction Matrix

### Run Metadata

Record for every run:

- date and time;
- Git commit SHA and dirty-file list;
- Ledger build/configuration;
- platform, device model/class, and OS version;
- physical device, simulator, or Mac;
- project item count and group count;
- cold in-memory cache or warm in-memory cache;
- network type and whether Low Power Mode is active;
- scenario IDs completed;
- whether the app froze, crashed, was killed, or completed.

Do not record project, account, item, client, vendor, or space names in committed
run artifacts. The known project can be referred to as `large-project-A`.

### Platform Order

1. macOS local build with production-like data.
2. Physical iPhone development/profile build.
3. iOS Simulator only for deterministic lifecycle verification; do not use it
   as proof of physical-device memory safety.
4. TestFlight/field evidence only if local and tethered runs do not reproduce.

### Scenario A: Large List Entry

1. Force quit and relaunch Ledger.
2. Open `large-project-A`.
3. Open Items and wait for the first usable frame.
4. Scroll through at least five screens at a normal pace.
5. Return to the top.
6. Repeat once without force quitting.

Capture:

- activation and snapshot intervals;
- initial item-list derivation;
- first card/image work;
- main-thread stalls;
- peak and settled memory;
- cold versus warm difference.

### Scenario B: Detail and Back Loop

1. Begin on the stable project item list.
2. Open an item with an image.
3. Wait for the detail screen to settle.
4. Navigate back.
5. Repeat ten times, alternating between at least two items.

Capture:

- tap-to-detail and back-to-list durations;
- focused listener and task counts;
- lineage fallback fetches;
- parent-list recomputation;
- memory after each cycle;
- image request/cache behavior.

### Scenario C: Read-Only List Interaction

1. Search for an item and clear search.
2. Apply and remove one filter.
3. Change sort and restore it.
4. Expand three small groups and keep them expanded.
5. Select 20 items.
6. Open and dismiss Actions without executing an action.

Capture:

- each derivation count and duration;
- card lookup aggregate totals;
- menu trigger-to-appearance duration;
- main-thread stalls and memory.

### Scenario D: Cross-Surface Browsing

1. Open Items, then Spaces, then Transactions within the same project.
2. Open and close one detail screen from each surface.
3. Return to Items after each detail.
4. Repeat the sequence three times.

Capture:

- listener counts and callbacks by surface;
- project-context stability;
- image request concurrency;
- memory plateau or growth;
- navigation latency by destination type.

### Scenario E: One Controlled Live Mutation

Run only after the read-only scenarios.

1. Change one reversible metadata field on one test item.
2. Observe all account-wide, project-scoped, and focused callbacks.
3. Restore the original value.
4. Confirm freshness on list and detail surfaces.

Capture:

- number and size of snapshots caused by one document mutation;
- full-snapshot decode time despite `documentChanges.count == 1`;
- context publication count;
- list recomputation count;
- main-thread stall duration.

### Repetition

- Run each read-only scenario three times on macOS.
- Run Scenarios A through C at least twice on a physical iPhone.
- Preserve one cold-cache and one warm-cache trace per platform.
- Do not average away a freeze. Report maximum latency and every severe stall in
  addition to median values.

## Instruments Capture Procedure

For each platform, collect separate traces where necessary to limit profiler
distortion:

1. **Time Profiler + Points of Interest** for CPU stacks and signpost alignment.
2. **Hangs** for main-thread unresponsiveness.
3. **Allocations/Leaks** for repeated detail/back cycles and retained growth.
4. **Network** only when image or Firestore waiting remains a candidate after
   CPU analysis.

Do not attach every heavy instrument to the same run and treat the resulting
latency as representative.

Raw `.trace` files can be large and may contain system/process details. Store
them outside Git under `tmp/performance-runs/`. Commit only a redacted Markdown
summary and small aggregate data files.

## Performance and Stability Gates

These are initial investigation gates, not a claim that every device will have
identical timing:

### Stability

- zero crashes, watchdog terminations, and memory warnings in the repeated local
  matrix;
- active focused listeners/tasks return to baseline after every detail closes;
- resident memory reaches a plateau rather than growing monotonically across ten
  detail/back cycles;
- post-warmup physical footprint should not grow more than 15% across the final
  five cycles without an explained cache plateau.

### Responsiveness

- no critical main-thread stalls of 5 seconds or more;
- no unexplained severe main-thread stalls of 1 second or more;
- action-menu appearance target: under 500 ms at the 95th percentile;
- back-to-usable-list target: under 500 ms at the 95th percentile;
- detail first usable frame target: under 750 ms at the 95th percentile, while
  network content may continue loading non-blockingly.

### Freshness

- a controlled mutation appears on all currently visible relevant surfaces;
- no diagnostic or later optimization step may substitute stale persisted
  indexes for current listener data;
- listener containment is not approved until the measured replacement retains
  the same visible freshness behavior.

## Phase 5: Analysis and Decision Gates

Produce a run summary containing:

- scenario timing table;
- maximum main-thread stall and associated call stack;
- peak and settled memory by scenario;
- listener registrations, callback counts, and peak concurrent listeners;
- snapshot document count versus `documentChanges.count`;
- top CPU stacks during each freeze;
- list derivation and lookup aggregate costs;
- image request/decode/cache totals;
- crash/termination classification;
- confidence level for each conclusion.

Use the following gates to choose the next remediation:

### Gate A: Firestore Decode or Main-Actor Publication Dominates

Evidence:

- stalls align with full-snapshot decode, main-actor delivery delay, context
  publication, or financial-access recomputation;
- account-wide and project-scoped listeners process the same mutation.

Next work:

- design listener containment or shared snapshot ownership;
- evaluate incremental `documentChanges` application;
- move safe decoding/derivation work away from the main actor;
- preserve live freshness with explicit ownership and equivalence tests.

### Gate B: Per-Card Lookup or List Derivation Dominates

Evidence:

- Time Profiler and aggregate counters show repeated linear invoice, space, or
  category scans, or repeated filter/group/sort work.

Next work:

- build snapshot-derived lookup dictionaries;
- isolate/memoize derived list state using explicit current inputs;
- add freshness tests proving indexes rebuild synchronously on snapshot changes.

### Gate C: Listener or Task Counts Grow

Evidence:

- focused listeners, lineage tasks, or project contexts do not return to
  baseline after navigation.

Next work:

- repair lifecycle ownership and cancellation;
- add listener/task-count regression tests;
- repeat Scenario B until counts and memory plateau.

### Gate D: Image Memory or Request Work Dominates

Evidence:

- resident memory tracks decoded image bytes;
- cache declared cost materially understates decoded cost;
- duplicate requests or excessive concurrent decodes align with freezes/crashes.

Next work:

- charge cache by decoded memory;
- bound request/decode concurrency;
- deduplicate in-flight requests;
- downsample before full bitmap decode where possible;
- repeat physical-device memory scenarios.

### Gate E: Lineage or Detail Network Work Dominates

Evidence:

- detail/back latency aligns with sequential lineage transaction fetches or work
  that continues after cancellation.

Next work:

- use already-live transaction indexes first;
- batch/parallelize only missing fetches;
- make cancellation observable and effective;
- keep detail first paint independent of lineage completion.

### Gate F: No Local Reproduction but Field Crashes Continue

Next work:

- add a separately reviewed MetricKit subscriber for Apple-provided crash/hang,
  CPU, and disk-write diagnostics;
- decide whether Crashlytics is warranted after reviewing privacy, dependency,
  and operational implications;
- do not add third-party crash reporting silently as part of this instrumentation
  patch.

## Phase 6: Verification After Each Remediation

Every remediation selected by a decision gate must follow the same loop:

1. preserve the original failing trace and baseline summary;
2. make one architectural change class at a time;
3. run focused unit tests and both platform builds;
4. repeat the exact scenario on the same device and data set;
5. compare timings, memory, and counts against baseline;
6. verify freshness and UI behavior explicitly;
7. keep, revise, or revert based on measured results;
8. update the ranked cleanup list from evidence.

Do not combine listener containment, lookup indexes, image-cache changes, and
bulk batching in a single measurement comparison.

## Test and Build Matrix

### Automated

- `PerformanceDiagnosticsTests`;
- existing navigation route resolution tests;
- existing list filter/sort/group tests;
- existing selection calculation tests;
- context activation/lifecycle tests with mock listener counts;
- iOS simulator build;
- macOS build.

### Manual

- macOS optimized diagnostics run;
- physical iPhone diagnostics run;
- cold and warm cache runs;
- repeated detail/back lifecycle run;
- one controlled mutation freshness run;
- Cmd+F smoke test on the lazy item list, recorded separately from the freeze
  measurements.

## Deliverables

1. Diagnostic foundation and focused instrumentation patch.
2. Redacted baseline run summary under:
   `docs/performance-runs/<date>-browsing-baseline/summary.md`.
3. A small aggregate JSON file with counts/timings if useful; no raw customer
   identifiers or values.
4. Raw Instruments traces stored outside Git under `tmp/performance-runs/`.
5. Ranked findings with evidence and confidence.
6. One approved remediation plan selected through the decision gates.
7. Before/after run summary after that remediation.

## Required User Participation

Most of the work can be completed by the engineering agent. User participation
is limited to:

- reproducing an iPhone-only freeze on the physical device if it cannot be
  reproduced through a tethered development run;
- identifying the approximate time of a physical-device crash;
- providing or exporting the device analytics report if it is not available in
  Organizer/App Store Connect;
- confirming that the post-fix UI and live-data behavior still feel correct.

The user does not need to configure Instruments, interpret traces, or choose an
architectural fix before the evidence is collected.

## Execution Order

1. Collect existing crash evidence.
2. Implement and test the diagnostic foundation.
3. Instrument Firestore decode and context publication.
4. Instrument navigation, list derivation, card lookups, images, and memory.
5. Build both platforms.
6. Capture macOS baseline scenarios.
7. Capture physical-iPhone baseline scenarios.
8. Write the baseline summary.
9. Select exactly one remediation through the decision gates.
10. Implement and rerun the same scenarios.

## Execution Notes (2026-08-24)

- No Ledger crash or hang reports were present in the local DiagnosticReports
  directory. Existing archives do not provide a classified failure for the
  reported browsing crashes.
- The physical iPhones registered with Xcode were offline, so a device jetsam,
  watchdog, or memory-pressure capture was not available in this run.
- The active internet connection was reported degraded. Cold Firestore loads,
  image downloads, Storage URL resolution, and lineage fetch durations from
  this connection must not be used to rank remediations.
- Deterministic diagnostics tests, both application builds, warm-cache UI work,
  main-thread heartbeat delay, listener/task counters, context publication,
  image decoding, and memory-footprint trends remain valid measurements.
- The instrumentation preserves listener scope, data freshness, UI behavior,
  Firestore writes, image request concurrency, and the existing image-cache
  eviction cost. Diagnostics are disabled unless explicitly enabled.
- A synthetic 668-item benchmark ruled out filter/sort, grouping, and selection
  totals as primary multi-second causes. Optimized per-pass measurements were
  0.184 ms, 0.724 ms, and 0.091 ms respectively.
- A lifecycle regression test proved that releasing an active `ProjectContext`
  removed 0 of its 9 test listeners. Firebase explicitly does not unlisten when
  a registration object is merely destroyed. Automatic listener ownership
  cleanup now removes all 9, and the regression test passes.
- Per-card linear space/category/invoice lookups measured 6.341 ms per
  optimized 668-card pass versus 0.126 ms with synchronous indexes, a 50.2x
  improvement. Replacement/clearing tests verify the indexes cannot retain
  stale source values.
- The focused diagnostics and lifecycle suites passed 17 tests, the optimized
  diagnostics suite passed 8 tests, and the macOS scheme builds successfully.
- The full iOS test target ran 925 tests but is not green: 42 emulator tests
  could not authenticate under the current network/auth conditions and 3
  unrelated price-policy expectations fail independently.

## Completion Criteria

The diagnostic task is complete only when:

- the strongest available freeze/crash reproduction has a trace or classified
  field diagnostic;
- the longest visible stalls can be mapped to concrete call stacks or waiting
  states;
- listener/task/image counts and memory behavior are known across repeated
  browsing;
- the next remediation is ranked from measured evidence rather than likelihood
  alone;
- the plan records any evidence that remains unavailable;
- no instrumentation has changed UI behavior, data semantics, listener
  freshness, or Firestore writes.
