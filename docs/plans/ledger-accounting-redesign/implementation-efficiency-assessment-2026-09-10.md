# Item workflow implementation efficiency assessment

Date: 2026-09-10. Original assessment only; the separately requested process repair is recorded in the addendum below.

## Conclusion

### September 11 Purchase-read process trial (in progress)

Bounded work: finish the pre-existing canonical Item-linked Purchase backend read;
no UI, payment writes, complete Transaction destination or migration delivery.
New work tightened malformed currency/origin handling and exact-money edge cases,
documented full-Purchase versus per-Item amounts, and tested the existing reader.
Unrelated gallery test edits remain outside the batch.

Local evidence: 25 reader tests / 6.964s, 7 core tests / 0.004s (test execution,
not compilation); 47 SQL assertions passed; 117 actual stream SQL captures passed;
5 stream-parser tests / 0.378s; environment validation and diff whitespace passed.
The initial 24-reader baseline also passed. No local UI or full native suite run.
Clean-environment CI remains required; local checks are not whole-feature readiness.

Observed overhead, not hidden from this trial:
- Historical token logs were stale; two bounded lookups found no current request
  boundary. Live goal counters are available, but no cached/uncached/output split.
- System Node20 failed parsing the service dependency before tests ran. Retrying
  with CI's Node24.14.0 passed; existing command guidance now records that runtime.
- Docker was unresponsive; the user approved restart. Its local schema was ahead
  of its migration ledger, so db push failed on an already-existing column. Only
  the new read migration was then applied transactionally to the verified local
  container, and affected SQL tests passed. CI must verify fresh migration replay.
- New execution-record setup initially failed schema validation; corrected. One
  remaining local scope-check error attributes the preserved gallery test dirt to
  this batch. Do not add UI work or weaken the checker to claim a pass. The clean
  committed batch must exclude that unrelated patch.

Live goal counter checkpoints (reported tokens, not subscription consumption):

| Boundary | Cumulative reported goal tokens | Interval tokens |
|---|---:|---:|
| Goal creation (1789159907) | 0 | — |
| Initial inspection / baseline native test | 17,652 | 17,652 |
| Implementation, local hardening and environment troubleshooting | 131,132 | 113,480 |
| Local verification review, before CI preparation | 144,832 | 13,700 |

These mixed activity intervals are not precise per-task attribution. Initial work
before goal creation and future CI/reporting are not in the latest count; final
closure must report the later counter and this limitation. Cached input, uncached
input and output are **unavailable**, not zero. No subscription percentage,
whole-project completion percentage or controlled savings estimate follows from
these readings. The test execution itself was fast; setup, environment recovery,
record updates and review consumed the observed surrounding effort.

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

Setup baseline located: goal continuation04:31:21.299, preceding counter at
04:31:20.837 = (1001941162,990067584,2349255,1004290417). Thus setup through
implementation start reports817246 total (814925input,787456cached,2321output);
writing/initial build reports607608 total (600038input,586240cached,7570output);
debugging/integrated-local interval reports1207793 total
(1202320input,1186048cached,5473output). These are mixed activity intervals,
not billed usage or task-specific avoidable-cost estimates.

Checkpoint505dc2bb658076b0536e705038dd29b020747baf was pushed with automatic
CI34563203081 as the sole integrated gate. The local full-suite total included
pre-existing dirty Purchase tests; CI subsequently verified the committed batch
without those changes. Native CI and final findings were pending at this checkpoint;
the completed results follow below.

## Final findings: implementation observation completed

**Delivered:** Project Item accounting filtering, using the existing atomic read
and shared facet semantics. Four ITEM-ACCOUNTING-FILTER acceptance checks passed
on [505dc2bb / automatic CI34563203081](https://github.com/nine4-team/ledger-mobile/actions/runs/34563203081).
All five jobs passed:1086 native tests/156suites,25MacUI and30iPhoneUI.
The new interaction passed Mac68.952s and iPhone131.451s. Exact job logs:
`/tmp/ledger-accounting-filter-ci-mac.log` and
`/tmp/ledger-accounting-filter-ci-ios.log`. Root reviewed the actual assertions,
shared classification, scope rejection and selection wiring—not just green badges.

The production change added34 lines and removed5 across existing Core, AppModel
and View files; the fixture and tests are separate. This describes the change,
not its token value. No new provider, schema, permission, writer or UI rebuild
was required. No broad Item or migration completion is claimed. Existing Purchase
work remains untouched by the committed batch. The observation stops here.

### Reconciled task measurements

Reported cumulative-counter differences, UTC September11; cached input is a
**subset** of input. These are processing counters, not billing or account-quota
measurements. Reasoning is already included in output. Task labels are coarse:
implementation includes test writing/first compile; later intervals include
mixed review and coordination. They do not assign every token to a precise cause.

| Task and interval | Input | Cached input subset | Output | Total |
|---|---:|---:|---:|---:|
| Discovery and boundary / coordination (04:31:20.837–04:32:58.870) | 814,925 | 787,456 | 2,321 | 817,246 |
| Implementation and new tests / mixed first build (04:32:58.870–04:37:04.382) | 600,038 | 586,240 | 7,570 | 607,608 |
| Debugging, local verification and staging (04:37:04.382–04:40:33.023) | 1,202,320 | 1,186,048 | 5,473 | 1,207,793 |
| Checkpoint, review and early CI coordination (04:40:33.023–04:44:43.628) | 1,165,532 | 1,153,280 | 6,452 | 1,171,984 |
| CI waiting, evidence review and monitoring (04:44:43.628–05:26:02.338) | 11,743,612 | 11,614,592 | 25,668 | 11,769,280 |
| Measured aggregate | 15,526,427 | 15,327,616 | 47,484 | 15,573,911 |

Endpoint05:26:02.338 cumulative tuple:
(1017467589,1005395200,2396739,1019864328). The additional boundary04:44:43.628
is (1005723977,993780608,2371071,1008095048), just before starting the single
background CI watcher. The task rows sum exactly to the aggregate. Input not
reported cached totals198811; output totals47484. Neither is a dollar/quota proxy.

**Unassigned/unmeasured:** goal creation before the implementation observation,
the final report/record edits and completion response after the endpoint, and
fine-grained causes inside mixed intervals. No new agents ran. No counter decrease
or compaction marker occurred within this implementation window; duplicated
cumulative notifications are not counted twice. The earlier gallery observation's
compaction ambiguity remains separate and prevents pretending these tables are a
complete account-level usage statement.

CI's iPhone UI execution took1724.158s; its job and build involved additional
time. This elapsed time is not tokens. Model activity while waiting is in the
last measured interval; that interval must not all be labeled waste.

### What the evidence supports, ranked for action

1. **Reduce unnecessary model interaction during external waits.** The largest
   measured interval was CI coordination/review, not writing the feature.
   Initially each55-second wait used an early-yield exec plus a separate resume.
   Changing the exec yield window to cover the bounded wait eliminated that
   second model resumption without changing CI polling or verification.
   Two later waits successfully used one call each. Keep the existing background
   watcher, single-call bounded waits, and short change-driven evidence retrieval;
   do not re-review completed code just because CI is running.

   The measured comparison is deliberately limited: a paired wait at
   05:15:37/05:15:42 reported354452 total processing tokens,352512 cached input
   and632 output. A single-call wait at05:21:29 reported184037 total,
   182016 cached and602 output. Calls and largely cached processing decreased;
   input-not-cached plus output was1940 versus2021, so this pair does **not**
   demonstrate quota/cost savings. Context/cache conditions were not controlled.

2. **Keep working context small; do not assume cache reuse makes extra calls free.**
   A watch-log status read at05:15:14.909 reported176281 input tokens, only105600
   cached, and235 output. Its70681 input tokens not reported cached represent
   approximately35.6% of that category across this entire measured window.
   Nearby calls reused much more of their input. The cache-reuse drop is observed;
   its underlying cause and preventability are unknown. Long retained context
   makes such a drop consequential. Avoid oversized mixed-file dumps, retrieve
   current facts before histories, and use the existing compact resume record.
   Setup still had oversized/truncated reads: this practice improved unevenly,
   not enough to declare the process fixed or guarantee a savings percentage.

3. **Keep meaningful verification; remove retries that answer no new question.**
   The new tests caught a real authoring error (missing `try`); correcting it
   and rerunning focused tests was justified. The local Mac startup failed before
   tests, so it was not treated as an app defect or retried unchanged. The normal
   CI gate then verified both platforms on the first submitted implementation.
   Retain scoped/unknown-accounting, selection and native tests. Repair local
   automation readiness separately if needed; do not weaken CI to hide it.

4. **Use observed file structure and cheap validation for edits.** One selective
   staging attempt failed because its generated patch lacked a final newline.
   The correction succeeded and kept Purchase changes excluded. Together with
   the earlier indentation retries, this is concrete avoidable editing overhead,
   not evidence that the app architecture needs redesign. Inspect formatting
   first and check generation/patch exit status before proceeding.

5. **Retain the bounded workflow and reuse existing implementations.** The four
   declared checks, outcome and exclusions stayed aligned through closure. No
   unrelated feature or new tracking structure was added. The repaired checker
   passed32negative/10positive regression cases;15CI guard tests also passed.
   This is one successful application of the process—not proof of universal
   completeness, broad throughput gains, or future accounting/media efficiency.

Necessary work included establishing the correct accounting meaning, rejecting
foreign/incomplete evidence, keeping displayed and selectable rows aligned,
reviewing assertions and obtaining native proof. Demonstrably avoidable work
included excess wait resumptions, some oversized reads and patch retries.
The avoidable share of each mixed task, cache behavior, recurring native flakiness
and whole-app savings remain uncertain. No affordability or completion forecast
is inferred. Future real work should retain these corrections, not start another
audit solely to chase a desired savings number.

## Quiet CI trial — September 11

Outcome: ending the AI turn eliminated repeated monitoring calls. There were no
token-count increments between the final setup reply at 15:25:47.681Z and the
scheduled wake-up at 16:24:29.830Z (58m42s). No compaction/counter reset appeared
in this measured interval. This proves quiet waiting, not zero-cost setup/review.
The hourly heartbeat `ledger-quiet-ci-trial` was paused after its first wake-up.

Unchanged [CI34563203081 attempt 2](https://github.com/nine4-team/ledger-mobile/actions/runs/34563203081/attempts/2)
ran at505dc2bb from15:24:25Z to16:11:29Z. Three jobs passed; iOS failed, and the
final aggregate gate correctly failed. Native core1086/156suites and MacUI25/25
passed. iPhoneUI28/30 passed. The accounting filter passed on both platforms.
Failed iPhone assertions: `testDownloadedItemImageGallery` at line1178 (pinned
image counter after pinning) and `testDownloadedItemImageSwipeNavigationAndDismissal`
at line1321 (zoom reset to1.0x). Both passed the prior identical-commit run;
intermittency is observed but its app/test/environment cause is not diagnosed.
Job IDs: Mac103318899915, iOS103318900044. No rerun-to-green or code repair.

Tradeoff: wake-up was13m01s after overall completion, and33m41s after the first
failing assertion (15:50:48.769Z). An hourly check is not an instant failure alert.
Desktop availability remains a dependency. Future event-driven notification
could reduce delay, but that mechanism was not implemented or tested here.

Measurement: same cumulative session source as the plan. Input includes cached;
output includes reasoning. Setup includes documentation lookup, initial invalid
automation call/correction, launch, checkpoints and Benjamin's two follow-ups.
The account meter showed8% at early setup,9% at launch,9% at result review, with
the same weekly reset. Rounded account-wide values cannot isolate this task or
establish exact subscription savings; unchanged9% does not mean free.

Initial review cutoff16:25:28.003Z (before final report writes):

| Activity | Input | Cached subset | Output |
|---|---:|---:|---:|
| Setup and explanatory replies |894,190|865,920|5,541|
| Idle interval |0|0|0|
| Scheduled wake-up and result review |256,407|232,448|1,057|
| Measured total to this cutoff |1,150,597|1,098,368|6,598|

Using the previously checked [published Astra rates](https://learn.chatgpt.com/docs/pricing)
as a proxy (input:cached:output weights1:0.1:5), review so far is96.3% cheaper
than the historical mixed monitoring/review interval, or86.3% cheaper including
this trial's setup. These are NOT subscription savings or a whole-batch estimate.
Final reporting adds cost, reconciled below; do not present the provisional
percentages as the completed experiment total.

Comparison limitations: already-reviewed unchanged code requires less review
than new implementation; context is smaller now; cache reuse and CI outcomes
differ. The old interval mixed waiting with review. Do not attribute the entire
difference to scheduling, nor extrapolate35% or another whole-app saving.
Recommendation: keep quiet waiting and required tests; explicitly accept delayed
failure detection. Keep the two iPhone failures visible for subsequent authorized
implementation work, not another efficiency audit.

Reporting reconciliation cutoff16:26:08.064Z: an additional89,534input
(87,680cached) and1,155output tokens were measured after the initial review
cutoff. Total from the pre-request counter is1,240,131input
(1,186,048cached),7,753output,1,247,884total processed tokens. At that explicit
cutoff, the weighted proxy is85.1% below the historical monitoring/review cost,
including setup and measured reporting. Cumulative end: input1,020,679,455;
cached1,008,310,144; output2,419,456; total1,023,098,911.
The final reconciliation write and final user handoff fall after this cutoff and
are excluded/unassigned, not zero. This avoids a recursive measure/write loop.
No exact subscription-savings percentage was established.

## Gallery repair batch — September 11 (in progress)

Authorized workflow: reliable Item photo viewing, restricted to the existing
ITEM-IMAGE-VIEWER-CONTROLS and ITEM-IMAGE-NATIVE-GESTURES checks. Start505dc2bb;
preserve unrelated dirty Purchase code. The two checks are reopened, preserving
historical passes. No full Item-read or new feature-completion claim.
Counter before user request19:45:16.092Z: input1,021,967,393;
cached1,009,575,552; output2,424,955; total1,024,392,348. Session source is the
same as the diagnostic plan. Account-wide weekly meter9% during discovery.
Measure discovery/repair, verification, quiet waiting, and review/reporting at
natural boundaries, including this documentation overhead; report the full
sample without assuming the earlier85% monitoring proxy applies overall.

Evidence: attempt2 screenshots in /tmp/ledger-gallery-repair.9fniS2/screenshots
show the gallery with controls hidden after Reset, and a pinned1-of-2 image
where2-of-2 was expected. CI event timing shows AX lookups/event delivery can
consume the real2.2-second controls interval. Working diagnosis: transient UI
interaction/assertion races, not demonstrated provider or image-storage failure.
Proposed correction is test-only: assert native persistent zoom, resolve target
coordinates before renewing control visibility, and assert the selected image
before pinning. No auto-hide extension, disabled animation, or action retries.
Unmodified local baseline started at /tmp/ledger-gallery-repair.9fniS2/baseline.xcresult;
post-change verification remains pending. Do not report the diagnosis as proven
or the batch complete before reviewing native results.

Local unmodified baseline passed2/2 on iPhone17Pro/iOS26.5, ending19:51:48Z;
the CI failure was not reproduced in that run. Corrected test-only run performs
two fixed iterations of the same tests, with corrected.xcresult in the same
directory (session30159). No app code change. conversion:check passed with the
three pre-existing source-removal warnings. Heartbeat ledger-gallery-verification
returns every20min for this local verification, then should switch to hourly for
the normal full CI run. No frequent model polling while waiting.
Discovery/repair checkpoint19:51:26.512Z: cumulative input1,024,199,957;
cached1,011,758,464; output2,434,105; total1,026,634,062. This boundary includes
overlapping baseline-test execution, not all subsequent scheduling/closure costs.
