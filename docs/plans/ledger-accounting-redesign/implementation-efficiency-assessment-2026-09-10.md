# Item workflow implementation efficiency assessment

Date: 2026-09-10. Original assessment only; the separately requested process repair is recorded in the addendum below.

## Conclusion

The sampled work followed the backend-neutral architecture and added meaningful
local functionality. It also incurred demonstrated avoidable test repair and
tracking overhead. The strongest correction is to enforce a stable feature
boundary and a focused native feedback loop, not to restart architecture or
remove security/offline testing. Widespread unnecessary UI reconstruction and
specific token savings are **not established**.

## Scope and evidence

Reviewed September 8–9 commits through `f66e2927`, concentrating on Item
browsing/detail, gallery, and their verification. Compared requirements at
`2a44682f` (September 7, before the sampled work) with HEAD. Inspected actual
diffs, old/new UI dependencies, adapter/runtime code, test code, committed
checkpoints, and retained CI logs. No new test suites, production access, or
hosted checks were run. The in-progress Purchase projection remains untouched
and does not receive completion credit.

For context, all 78 commits in the two-day period touched both progress files;
67 touched `WorkspaceChecklistUITests.swift`, and 22 touched the CI workflow.
Sixteen touched only verification/tracking files. Those counts cover more than
the Item workflow and measure changes, not effort. No historical per-activity
token attribution was measured in this assessment.

## Findings and actions

### 1. Requirements existed; a new comprehensive mapping audit is unwarranted

At `2a44682f`, the checklist already specified Item detail links/sections,
list search/sort/facets/grouping/selection, gallery navigation, zoom, pinning,
save/share, and meaningful failure states. The four sampled journeys are
identical at HEAD: `UIBASE-ITEM-DETAIL-001`,
`UIBASE-ITEM-LIST-CARDS-FILTERS-AND-PICKER-001`,
`UIBASE-MEDIA-IMAGE-GALLERY-001`, and
`UIBASE-MEDIA-ZOOMABLE-ANNOTATED-IMAGE-001`. The Item and image-pinning specs and
ports document also did not change between those commits.

The pre-existing method already required coherent workflows, existing code
reuse, focused development tests, and full verification at an integrated
boundary. Thus many later additions were known requirements delivered
incrementally, not newly discovered requirements. Their order alone does not
prove requirements were overlooked. The initial gallery checkpoint explicitly
deferred zoom/pinning and other features.

**Action:** use the existing checklist and contracts to select the next bounded
result; fill only consequential missing design details. Do not create another
whole-app mapping exercise or require final design for all features upfront.

### 2. The recorded workflow boundary stopped matching the actual work

The `active-workspace-to-space-checklist` execution record grew from four
acceptance checks to 31. At HEAD, 22 are still `planned`, including Item/media
checks with implementation discussed elsewhere. Its review summary grew from
549 to 17,868 characters. Its exclusions still say Items/media and other tabs
are separate workflows, while its checks now include them and note migration.
This demonstrates an internal tracking inconsistency, not that all planned
checks have actually passed.

**Action:** before resuming implementation, give the existing record an accurate
scope and explicit finish boundary. Keep compact current status and evidence
references in their designated fields. Move historical narration out of the
resume path by relying on Git history. Do not add a new tracker or mark checks
passed merely because a narrative mentions them. Related field additions should
share a batch where dependencies permit; small commits remain acceptable.

### 3. Native verification found real bugs and also generated avoidable repairs

| Case | Evidence | Assessment |
|---|---|---|
| Photos save crash | `426baa0c` changes the PhotoKit callback to `@Sendable`, avoiding inherited MainActor isolation; checkpoint records crash diagnosis and subsequent saved/denied tests | Necessary application fix; compilation alone did not establish runtime correctness |
| Gallery close clipped after unpinning | `998329bd` changes macOS image layout priority/minimum height; prior checkpoint identifies screenshot evidence | Necessary application/layout fix |
| New window-bounds assertion then fails | `998329bd` uses `app.frame`; `f66e2927` corrects it to the containing macOS window | Avoidable test defect, not another backend requirement |
| Several tests fail at the same reveal helper | Retained `ledger-ebf-macos-ci.log` records four Item tests failing at line 1707; `c660d832` checkpoint identifies scroll direction relative to the viewport | Shared test-interaction issue; investigate once before repeated broad runs |

Retained logs confirm full native UI runs of 781 seconds (21 Mac tests,
`ebf11e65`), 843 seconds (24 Mac tests, `e3f4ba9a`), and 1,499 seconds (27 iPhone
tests, `426baa0c`). These are runner durations, not model token usage.

**Action:** reproduce a failed native interaction with the affected test and
inspect its hierarchy/screenshot before another broad run. Fix a shared helper
when several failures share that cause. Keep real device-framework interaction
coverage; put data permutation coverage in domain/model/provider tests when
it does not require the native UI. Do not weaken assertions to make CI green.

### 4. CI was an expensive integration feedback loop under a real local constraint

The PR workflow runs conversion, local provider, and both native-platform jobs
on PR updates. Checkpoints for `6355430e`, `7e0383c4`, `c660d832`, and
`998329bd` document new pushes while earlier native runs were still pending.
Some runs were later canceled as superseded. They also explicitly reuse prior
local database/native results and prohibit duplicate dispatch: repeated local
full-suite execution is not established as a universal practice.

The same checkpoints report disk constraints (about 300 MiB by `998329bd`) and
reliance on typechecks rather than full local Xcode runs. That constraint helps
explain reliance on remote runtime proof; simply telling agents to test locally
would not resolve it.

**Action:** establish a usable focused native-test environment before further
UI-heavy work, or provide a focused CI path using the existing workflow. Keep
full CI for integrated batches. Coordinate pushes and consume one authoritative
result per batch instead of maintaining several obsolete runs. No CI change or
disk cleanup is performed by this assessment.

### 5. Adapter direction is sound; reuse findings are narrower than previously claimed

`DownloadedItemsModel` consumes Core protocols; `LedgerOfflineClientRuntime`
implements them with PowerSync-backed readers. Local physical/accounting reads
are combined atomically. Image work reused the protected attachment cache and
transport rather than introducing a separate storage system (`6355430e`).
This is substantive implementation of the agreed architecture.

The original `ImageGallery`/`ZoomableScrollView` own Storage URL resolution,
URLSession fetching, image caching, decoding, and platform behavior. Original
Item detail imports Firebase and depends on existing contexts/listeners. The new
zoom component accepts decoded pixels; the baseline also documents a legacy
zoom-limit defect and changed media-access requirements. Therefore reuse was
not a drop-in alternative. Extraction might have been cheaper, but that
counterfactual and widespread unnecessary replacement are unproved.

The runtime repeats watch startup/cancellation/cleanup code. However, the
placement-watch comment explains why an untracked AsyncStream producer would
not satisfy shutdown guarantees. The existing generic helper is not an automatic
safe substitute.

**Action:** retain working components and the adapter boundary. For the next
component requiring change, compare reuse, extraction, and replacement using
its actual dependencies. Consolidate lifecycle duplication only when the shared
implementation preserves owned-task/subscription cleanup. Do not undertake a
blanket UI rewrite reversal or general framework project.

### 6. Verification safeguards are substantive; feature closure is still partial

Image reader tests distinguish missing download evidence from an empty gallery,
reject cross-account objects/revoked membership, and exercise encrypted restart
and reactive updates. These are distinct risks that a UI test or fake adapter
alone cannot prove. Preserve those tests and accounting/RLS/Sync checks.

The sampled implementation adds downloaded Item lists, search/order/facets,
grouping/selection/ID copying, descriptive detail and physical history, current
category/accounting display, Space navigation, and protected image viewing/
thumbnails/save/share. These are meaningful increments. The evidence contains
passing local checks and individual UI results, alongside failing/pending full
runs; this report does not certify latest-commit release readiness.

Remaining gaps include full financial card/detail/history content and linked
Purchase/Invoice destinations, editing/bulk/media mutations, remaining
facets/picker behavior, and live authenticated hosted verification. The broad
Item outcome remains blocked by recorded financial/Sold-policy questions;
those do not make all read implementation unauthorized. Other command-role
decisions affect writes. Do not silently settle them for throughput.

**Action:** report the bounded read result separately from the complete Item
workflow, keeping specific unimplemented/decision-blocked behavior visible.

## Cost, completion, and stopping decision

This assessment supports specific corrections to batch closure, native test
feedback, and tracking hygiene. It does not establish a 20%, 50%, or 3× token
improvement, nor whether the overall project is affordable. It also does not
validate or revise the earlier whole-app 15–20% completion guess: one sampled
workflow and test/commit counts cannot establish a remaining-effort denominator.

No further audit is needed to make the recommendations above. A representative
implementation trial would test their economic value, but is outside this goal.
No product requirements, security guarantees, implementation, tracking system,
or CI configuration were changed. Existing uncommitted Purchase work was
preserved. The assessment is complete at the evidence available, without
expanding into a whole-app audit or promising unmeasured savings.

## Follow-up: concrete process repair (separately requested September 10)

Inspection of `check-conversion-current-state.mjs` found a specific pressure
toward scope expansion: it attributed every target file changed since
`verifiedCheckpoint.commit` to the active workflow, then required that workflow
to declare all corresponding layers and risks. When the last fully green run
was old, an unrelated new batch inherited the prior batches' ownership burden.
This explains a mechanism encouraging the observed catch-all; it is not proof
of every agent's intent or the sole cause.

The checker now uses `activeWorkflow.baseCommit` for batch ownership and retains
`verifiedCheckpoint` separately for verification. The base must be an exact
ancestor commit and remain fixed while the batch is active. The active outcome
must equal its checklist record's outcome. Regression checks cover mismatched
outcomes, missing bases, undeclared files, exclusion of prior-batch changes, and
retention of current untracked implementation and Sync files.

Item acceptance checks moved to `downloaded-item-browsing-and-detail`; six
note-import/parity checks moved to the existing reconciliation record. All 31
original checks were conserved exactly once, unchanged, including statuses.
The navigation record's outcome and exclusions now reflect its retained scope.
Its lengthy prior review narrative remains retrievable at `f66e2927`. Product
requirements and outcome completion statuses were unchanged; no new product or
CI success was asserted. Existing uncommitted Purchase implementation remains.

The existing review step now explicitly compares changed outcomes, checks, and
exclusions when checks are added and at closure. Machine checks cannot decide
whether free-text scope is truthful; no semantic guarantee or savings estimate
is claimed. This repair removes a contradictory mechanical incentive and two
unchecked structural disagreements, without another tracker. Full app/native
verification is not rerun for these process-only changes.

## Authorized diagnostic observation: September 10, 2026

Boundary: only ITEM-IMAGE-VIEWER-CONTROLS and ITEM-IMAGE-NATIVE-GESTURES.
CI34396683481 for f66e2927 was already successful when inspected. Root compared
the existing acceptance expectations with the native assertions and relevant
source, and verified those app/test files match the tested commit. Gallery
controls passed on Mac (131.280s) and iPhone (148.809s); the iPhone gesture test
passed (97.467s). Both checklist checks are now passed. Other Item checks and the
broader workflow remain incomplete. No application code changed in this trial;
existing dirty Purchase work was preserved. This is a verification-closure
sample, not evidence of implementation throughput.

### Measurement and attribution limits

Source: this task's local rollout metadata, session continuation
01a0684c-483f-7cc1-8810-354d376933d4, token_count.info.total_token_usage.
User authorization is timestamped 2026-09-11T00:30:09.311Z. Starting counter:
the last preceding event, 00:08:51.035Z (input1000074354, cached988368128,
output2334289, total1002408643). Ending snapshot: 2026-09-11T00:38:53.383Z
(input1001521073, cached989743360,
output2345224, total1003866297).

Counters were fresh and monotonic in the inspected interval; reported total
equals input plus output, with cached input a subset of input and reasoning a
subset of output. Do not sum cumulative snapshots or add reasoning again.
These are reported processing-token deltas, NOT account quota or dollar cost.
Cached tokens dominate them. No subagents were started in this observation.

Important limitation: at 00:32:42 the compaction event's last_token_usage reports
36382 total tokens with zero component counts, while the cumulative counter
does not advance. Compaction therefore cannot be reliably reconciled from these
fields. Do not silently count that as zero cost or add it to the total below
without knowing whether another field/event accounts for it.

The following coarse intervals reconcile exactly to the reported cumulative
delta. Activity labels indicate the predominant task, not precise attribution
of every token. Setup mixed CI discovery and coordination; review interpretation
also continued into closure. Instrumentation/reporting is included in those
intervals, not free. The final table-writing and response after the ending
snapshot are unmeasured here; no claim of a complete billed turn total.

| Task interval (UTC, Sept 11) | Predominant activity | Input | Cached subset | Output | Reported total | Result / revisit |
|---|---|---:|---:|---:|---:|---|
| Start–00:34:46.250 | Coordination/setup, mixed initial evidence discovery | 928,915 | 881,536 | 3,738 | 932,653 | Counter discovery and context recovery; CI confirmed green; oversized reads and a wrong checklist-key lookup added overhead. |
| 00:34:46.250–00:35:36.029 | Testing/review, with boundary setup | 131,390 | 118,400 | 1,298 | 132,688 | Retrieved existing passing native results and inspected assertions/source; no test rerun. |
| 00:35:36.029–ending snapshot | Coordination/closure, mixed final review | 386,414 | 375,296 | 5,899 | 392,313 | Final interpretation, measurements and record edits; two failed patch-generation attempts caused by wrong indentation; corrected, conversion check passed. |
| Reported aggregate | All measured intervals | 1,446,719 | 1,375,232 | 10,935 | 1,457,654 | No new feature implementation; no new native-test waiting. |
| New feature implementation | Implementation/design | 0 | 0 | 0 | 0 | None required by the selected checks; not an implementation-efficiency sample. |

Input outside the cached subset: 71,487.
It is not a billing proxy either. The entire setup or closure interval must not
be classified as waste: each mixes required work with identified avoidable work.

### Findings, corrections, and stopping decision

1. **Avoidable evidence loading; observed, high confidence.** A whole active
   workflow dump returned approximately9633 tool-output tokens, including long
   historical command narratives, and was truncated. A raw rollout tail also
   produced oversized output; a compaction followed, though this does not prove
   the tail caused it. Correction: parse only usage metadata; first read
   acceptance ID/expected/status, then selected evidence; filter CI output to
   relevant results. The two closed checks now carry concise current proof and
   a reference to their preserved history at f66e2927. No measured savings
   percentage: repeated prompts include cached context and individual reads'
   avoidable cost is not separately metered.

2. **Potential duplicate verification avoided, not historical savings proved.**
   The resume pointer still said native CI was pending. It now records the
   actual green commit independently of the dirty tree. Exact existing results
   answered this trial's verification question; no native build/CI rerun was
   started. The assertion/source review was necessary: green CI alone would
   not establish coverage of the selected requirements.

3. **Avoidable patch retry; observed, high confidence.** Generated checklist
   patches assumed six-space indentation where the file uses ten. Two
   attempts failed without changing that file. Inspection corrected the
   assumption; exit status was then checked before applying the generated
   patch. Use observed formatting and validate generated patches before
   submission. Its exact token share is unknown within closure overhead.

4. **Measurement effort and limitations must stay visible.** This sample's
   largest reported interval was setup, not implementation. That supports
   reducing oversized reads and reusing the established metadata location;
   it does not prove the main implementation is inefficient by the same ratio.
   Do not build more instrumentation to chase missing compaction attribution.
   Retain coarse task intervals plus explicit unknowns for future real work.

Stop condition reached: both selected checks have reviewed exact-commit passing
evidence. Conversion/checklist validation and git diff whitespace checks passed;
the three already-recorded source-removal warnings remain unchanged. There was
no comparable subsequent implementation task, so implementation savings and
the behavioral effectiveness of the scope repair remain unmeasured. Do not
broaden this observation into a new audit or relabel it a completed implementation
trial. The next real implementation batch can reuse these cheap measurements.

## Implementation observation: Project Item accounting facet

Active goal follow-on, fixed four ITEM-ACCOUNTING-FILTER-* checks in the existing
checklist. Actual implementation extends the existing filter value, shared scoped
projection, selection eligibility and native menu; no new backend, grants, Sync
or writer. Pre-existing Purchase changes remain unstaged and outside the batch.
Previous process repairs/documentation are being checkpointed with the batch,
not counted as new feature implementation.

Initial local result: 19 focused tests passed after fixing one missing `try` in
a new test. Full native package passed1087 tests/156suites in82.151s. Existing
process guard tests passed32negative/10positive and15CI cases. Local Mac app and
XCTest compiled, but runner startup timed out enabling automation (no test
executed); no unchanged rerun. Automatic exact-commit CI remains the native gate.
One selective Git staging attempt lacked a final patch newline and failed; adding
it staged only the two new Core hunks without incorporating Purchase work.

Meter checkpoints from the same rollout as above (UTC September11), kept as
raw cumulative tuples (input,cached,output,total) for eventual interval deltas:

- Implementation start04:32:58.870: (1002756087,990855040,2351576,1005107663).
- First focused-build result04:37:04.382: (1003356125,991441280,2359146,1005715271).
- Integrated local result04:40:33.023: (1004558445,992627328,2364619,1006923064).

The first implementation interval includes writing tests and the failed compile;
the next mixes debugging, successful focused tests, native startup diagnosis,
review, staging and monitoring. Final task attribution must retain those mixtures,
not call the entire interval avoidable. Setup still contained oversized reads;
the old measurement limitations still apply. No new savings claim yet.
