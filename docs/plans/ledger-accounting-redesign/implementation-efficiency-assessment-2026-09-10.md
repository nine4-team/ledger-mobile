# Item workflow implementation efficiency assessment

Date: 2026-09-10. Original assessment only; the separately requested process repair is recorded in the addendum below.

## September 11 — original-gallery reuse integration (locally completed)

Reported-goal counter created1789167117, starting0. Updates can lag; cached/uncached split unavailable. Not subscription usage. Mixed intervals remain mixed. Verification includes model reasoning, result review and diagnosis—not tokens consumed by dormant tests. No subagents or GitHub CI ran for this trial.

| Activity | Counter range | Tokens | Result |
|---|---|---:|---|
| Context recovery and bounded implementation setup | 0 → 5256 | 5256 | Loaded prior decisions/current state, selected four existing gallery checks and inspected overlapping dirty test patch; pre-goal user reply/initial read excluded. |
| Mixed implementation and context/checkpoint work | 5256 → 48856 | 43600 | Extracted original native zoom loading adapter and pure gallery math; added target source membership. Includes rejected patch-generation attempts; no UI reconstruction. Earlier context/checkpoint work was not separately measured; this is not pure implementation cost. |
| Verification | 48856 → 51381 | 2525 | macOS isolated Swift6 typecheck failed: native annotation coordinates also require original PinnedImageCalculations. No tests/CI launched. |
| Implementation / dependency repair | 51381 → 63428 | 12047 | Extracted original pinned-coordinate helpers required by the native view; added build membership. Includes failed output-truncated patch attempt. No feature scope expansion. |
| Verification | 63428 → 66422 | 2994 | Shared native macOS Swift6 typecheck passed. iOS typecheck found duplicate existing teardown method after extraction; runtime integration not tested. |
| Rework | 66422 → 68668 | 2246 | Removed duplicate UIKit teardown; retained cancellation, load-identity invalidation and pixel clearing. |
| Verification | 68668 → 68668 | 0 | Retried only affected iOS shared-view Swift6 typecheck after removing duplicate teardown. |
| Implementation | 68668 → 79075 | 10407 | Moved original full-gallery controls/pager into shared presentation with injected content/identity/actions; original URL wrapper delegates. Target wiring and pinned chrome still pending. Includes one overbroad source-guard retry. |
| Verification | 79075 → 80049 | 974 | Shared gallery typecheck found Typography's existing BrandColors dependency on both platforms. |
| Implementation | 80049 → 85478 | 5429 | Added original theme dependency and explicit original-project source membership for extracted files. Shared native and gallery source now separated; target adapter/pinned chrome not yet switched. |
| Implementation (including reporting checkpoint) | 85478 → 106833 | 21355 | Extracted original pinned chrome and wired target catalog/protected pixels/export callbacks to shared gallery/native views. Superseded target zoom source excluded from YAML. Includes checkpoint/reporting and patch-output retries; mixed interval, no claimed pure implementation attribution. |
| Verification | 106833 → 112608 | 5775 | Typechecked shared original gallery/pinned/native presentation with all theme/math dependencies on both platforms; result logs retained. Target app build/runtime still pending. |
| Implementation | 112608 → 118949 | 6341 | Finished target gallery/pinned callback wiring, accessibility controls and original pinned paging adaptation; regenerated target Xcode project. Old target zoom code excluded, not deleted. Runtime verification pending. |
| Verification | 118949 → 121678 | 2729 | Actual target macOS app build passed (log /tmp/ledger-gallery-reuse-target-macos-build.log). Reviewed existing gallery/Photos test entry points and disposable-simulator guard. |
| Environment/setup + verification selection (mixed) | 121678 → 132161 | 10483 | Created owned disposable iPhone simulator81EE3ADB-136B-4DFA-BC80-4EAA2962F18C for isolated gallery/Photos tests; selected existing test suites and guards. Includes two unsuccessful filename/search attempts. |
| Verification / environment diagnosis / build bookkeeping (mixed) | 132161 → 150021 | 17860 | 43 tests/5 suites passed1.650s; Mac UI failed before assertions (automation initialization timeout, developer mode disabled); permission requested. Added extracted pinned file to original project. iOS four selected tests running on owned simulator, session90051. |
| Measurement/reporting + verification (mixed) | 150021 → 156841 | 6820 | Flushed resume/usage checkpoint, then observed iOS session90051 terminal65:4tests2failed,91.575s. Photos success/denial passed; gallery/gesture failures need exact diagnosis. No automatic rerun. |
| Verification | 156841 → 157840 | 999 | Diagnosed iOS failures: gallery case failed in pre-gallery Project navigation; gesture case reached successful Share cancellation then failed paging counter assertion. Source review found hidden controls were not revealed on page/zoom and synchronous pixels can arrive before initial layout. |
| Rework | 157840 → 176848 | 19008 | Adapted original controls to reveal after page/zoom; fit supplied pixels on viewport layout with stale-callback protection, rather than relying on network delay. Preserved Primary image caption and denied-scope close controls. No model/storage changes. |
| Verification | 176848 → 297984 | 121136 | Original app simulator build passed without launching Firebase. Narrow iOS rerun reached gallery in both cases but failed same helper's hidden-control existence assertion; original opacity-based controls can remain instantiated. No new storage/Photos failure. |
| Rework | 297984 → 304466 | 6482 | Changed only shared reveal helper's visibility check from element existence to hit-testing for original faded overlay, preserving actual hide/reveal gestures and failure diagnostics. |
| Mixed verification, context recovery and test repair | 304466 → 355387 | 50921 | Single-gallery run19015 failed: gallery reports hidden but XCTest reports faded button hittable. Test now observes existing viewer visibility state; focused rerun8230 active. |
| Mixed verification, test repair and documentation | 355387 → 390105 | 34718 | Visibility helper passed; corrected remaining same-assumption checks. Single-gallery6880 active. Added shared source ownership and architecture note. conversion:check continuity passed but passive source hashes/new extraction files require reconciliation; no full pass. |
| Mixed focused verification and source-omission diagnosis | 390105 → 399504 | 9399 | Gallery6880 passed143.797s. Gesture-only test launched. Identified11changed/new original-source surfaces from approved extraction; historical catalogs not synchronized. |
| Mixed source bookkeeping, macOS verification and repair | 399504 → 438758 | 39254 | Reconciled approved extracted source inventory/checklist (including correcting misplaced generated patch); conversion gate passed before latest Mac fix. Gesture test passed70.203s. Mac build passed, CUA fixture launch exposed NSInvalidArgumentException minMagnification360 > max5; corrected macOS-only range setter order. Rebuild60931 active. No security-setting change. |
| Mixed macOS interaction verification and zoom feedback repair | 438758 → 471380 | 32622 | Mac CUA verified zoom/pan/page/wrap/pin/resize/unpin/share cancellation. Found programmatic zoom feedback left Reset slightly enlarged; guarded animation KVO and routed double-click reset through binding. Rebuilt single fixture proves2.5→1.0 exact fit with disabled zoom-out, both reset paths; close removes pixels. Owned duplicate fixtures terminated; no security setting changed. Original Mac wrapper build now running. |
| Final review, compatibility and reporting | 471380 → 487090 | 15710 | Original Mac app build passed without launch. Reviewed shared/target diff, target-only protected pixels and unchanged export, scope ownership and actual log evidence; recorded four local passes without broad Item/CI promotion. conversion:check and diff whitespace check passed. Source snapshot recorded; owned Mac fixtures terminated, owned iPhone simulator already shut down. |

Closure/reporting interval: 487090 → 492669 (5579 reported tokens). Final completed-goal total: 492669 reported tokens over3894seconds (about65minutes). All intervals are contiguous and sum to that total. This final accounting write and user handoff occur after the counter closes and are excluded. This is not evidence of subscription savings; no comparable baseline was measured, and mixed intervals limit attribution. Patch-generation repairs, platform-specific defects, UI automation assumptions, context recovery and bookkeeping all contributed—not just test execution.

Result: target uses original shared gallery/pinned/zoom components, with legacy URL/cache loading excluded.43native tests passed1.650s; iOS gallery143.797s, gestures70.203s and Photos denied/saved23.422s/17.823s passed. Original iOS and Mac wrappers and target Mac build passed without Firebase launch. Mac XCTest could not initialize; direct CUA on an in-memory fixture verified gallery interactions, native share cancellation and exact reset/close after fixing the reproduced AppKit range crash and animation feedback. No security setting changed. Both previous failures and subsequent passes remain in the four existing Item-image acceptance entries. No whole Item, CI, hosted or release completion claimed.

Uncommitted implementation at base ca68d793f193463fd191d272891d02cf85b7c5c4, source snapshot 9433e986cd3c68e4413e394b1b9192e3eabf977801ae1d8b1b7d6cf8d475269d. Snapshot is SHA256(JSON of sorted [path,SHA256(file)] pairs for the15changed/new LedgeriOS source/project/test files). No commit/push, production or hosted access. The superseded zoom file remains on disk but is excluded from the target build. conversion:check passed; unrelated historical missing-source warnings remain warnings. Owned Mac fixtures stopped; disposable iPhone simulator is shut down and retained with its test data. Concrete logs and detailed scoped results are in the unified checklist; current state is only the resume pointer.

## September 11 — bounded process correction

### Follow-on sample: PDF row/list reuse (withdrawn by user)

Counter: live goal created `1789174075`, `reported_goal_tokens`; not subscription
consumption and no cache/input/output split available. Initial pre-goal setup is
outside this counter. Boundary: shared original PDF row/list controls with target
bindings, exact edits/inclusion, cancellation and source evidence; no accounting
import, parser rewrite, schema or inherited gallery work.

| Activity / concrete task | Start → end | Tokens | Result |
|---|---:|---:|---|
| Context recovery / select unfinished planned integration | 0 → 33,216 | 33,216 | Existing tracker had no single next task; candidate reads included oversized historical evidence. Avoidable discovery overhead, not implementation. |
| Mixed: implementation + initial scope/measurement records | 33,216 → 75,202 | 41,986 | Shared row/list extraction and adapters/tests; one rejected patch corrected directly. Cannot reliably split documentation from coding. |
| Verification: model tests, builds, UI launch, diff/continuity review | 75,202 → 87,824 | 12,622 | 9 model tests pass; native checks running. Continuity requires accounting risk for InvoiceImport paths. |
| Measurement/reporting | 87,824 → 88,905 | 1,081 | Scope evidence and initial measurement table. |
| Verification | 88,905 → 95,562 | 6,657 | Both original builds, target builds and continuity pass; first iOS runner crashes before assertions. |
| Environment/setup | 95,562 → 102,381 | 6,819 | Crash inspection: Apple bundle/defaults initialization; created owned iOS26.5 simulator matching Xcode. |
| Verification | 102,381 → 112,365 | 9,984 | Retry same iOS scenarios; Mac direct QA reached Project but CUA pipe failed at PDF open. Started existing focused Mac XCTest as alternative. |
| Environment/setup | 112,365 → 114,365 | 2,000 | One CUA session reset failed to restore native connection; stopped CUA attempts. |
| Verification | 114,365 → 122,665 | 8,300 | New iOS runner works; error/empty scenario passes. Reviewed unchanged identity/evidence policy. |
| Measurement/reporting | 122,665 → 123,694 | 1,029 | Saved test sessions and activity rows. |
| Verification | 123,694 → 125,748 | 2,054 | Both iOS scenarios pass (47.194s and54.452s); user then withdrew the importer scope. |
| Mixed: user discussion, rollback and scope correction | 125,748 → 149,280 | 23,532 | Stopped Mac run, undid only this batch's app changes, recorded D-029 retirement. No feature-completion claim. |
| Mixed: withdrawal reporting and documentation validation | 149,280 → 162,176 | 12,896 | Retirement/checkpoint records, source-hash updates for changed product authority, rollback verification and conversion checks. |

The sample ended because the user explicitly does not want invoice importers in
the redesigned app. Inspection found a source modal definition and helper code
but no call site opening it; the earlier plan/spec had treated source presence as
shipped behavior without established reachability. This finding is limited to the
inspected tree, not a verified audit of the latest released binary or all features.
Both target outcomes are retired. Pre-existing importer code/tests remain historical;
removing their old target wiring is separate from undoing this turn's changes.
No push, GitHub CI or production access. The measurements do not establish
whole-batch savings; startup discovery and invalid scope selection were material
waste. A precise coding-only share is unavailable because its interval included
bookkeeping. Intervals reconcile to162,176reported goal tokens at this checkpoint;
the final handoff is outside that total. No subscription-consumption percentage
or savings claim is supported. Conversion and diff checks passed after retirement.

First two intervals checked: same monotonic live counter, contiguous readings.
The implementation/recording interval is explicitly mixed, not a precise coding
cost. Remaining intervals will separate reporting from verification/rework.

Kept the existing diagnose-before-retry rule, removed its broken duplicate, and
added related-use review only after a helper/assumption is demonstrably wrong.
AGENTS.md now requires direct patches or existing mechanical tools, not custom
patch generators. No new tracking system or app implementation change.

The source checker and checklist audit views now read the inventory/source tree
at exact local Git snapshot ca68d793, descended from product baseline fe018501.
This preserves the reviewed original-app coverage without making target reuse
update original source hashes, IDs or counts. The gallery-only catalog additions
were removed; target reuse choices, implementation files and test evidence remain.
No Firebase checkout/backend, fetch, original-app maintenance, push or CI run is
needed. The new focused snapshot tests are included in the existing CI check step
for the next normal push, not dispatched now. Savings remain unmeasured.

Local verification passed: `node --test scripts/tests/source-baseline.test.mjs`
(5 tests), `npm run conversion:ci:test` (18 configuration tests),
`npm run conversion:check`, and `git diff --check`. The conversion check retains
three pre-existing missing-source warnings in the saved inventory. No app/UI
tests were run for this correction. This bounded process correction is complete.

## September 11 — completed implemented-work reuse review

The one-time review resolves the remaining reuse choices and updates 11 existing
workflow records plus shared checklist guidance. No behavior, acceptance, status,
product blocker or historical verification evidence was removed. All 43 target-app
files remain accounted for; non-UI responsibilities are classified by family, not
certified line by line. Seven generic infrastructure files have only test consumers
found; freeze expansion rather than adopting or deleting them automatically.
See [reuse decisions](implemented-work-reuse-audit-2026-09-11.md#completed-review-and-implementation-decisions).
No app implementation/deletion, tests, CI, push or production/hosted access occurred.
Next proposed batch: original gallery presentation with protected target image inputs.

Measurement source: same active goal created at Unix 1789165663, starting at zero;
units are **reported goal tokens**, not subscription consumption. Cached input,
uncached input and output breakdowns are unavailable. No subagents. The first two
intervals were checked for contiguous counters/source identity; the interval that
crossed compaction is explicitly mixed, not retrospectively assigned to CI or code.

| Activity / concrete work | Counter range | Tokens | Result |
|---|---|---:|---|
| Context recovery / prior assessment and scope | 0 → 1,759 | 1,759 | Loaded existing assessment and latest isolated worktree state; no CI inspection. |
| Verification / implemented-work review plus compaction recovery (mixed) | 1,759 → 15,629 | 13,870 | Reviewed existing assessment, plan and original/target Item/checklist dependencies; boundary crossed context compaction. |
| Verification | 15,629 → 91,767 | 76,138 | Resolved remaining UI/provider boundaries and generic-helper consumers against code and existing decisions. No test/CI execution. |
| Process/tooling | 91,767 → 117,749 | 25,982 | Wrote finite review decisions and reuse plans for 11 existing records plus shared guidance/method link; includes one rejected documentation patch, then successful correction. |
| Verification | 117,749 → 125,497 | 7,748 | JSON/source-link and historical-content comparison: all 43 target-app files covered; 11 reuse plans; all prior behavior/acceptance/evidence unchanged. One read-only comparison retried with sufficient output buffer. No tests or CI. |

| Measurement/reporting | 125,497 → 130,891 | 5,394 | Resume/checkpoint, reporting and final document checks. |

**Closed:** 130,891 reported goal tokens; 842 seconds (about 14 minutes).
The closing interval includes final preparation, not final post-closure
bookkeeping. Same source and denominator throughout:

| Activity | Tokens | Share |
|---|---:|---:|
| Context recovery | 1,759 | 1.34% |
| Mixed review/context recovery | 13,870 | 10.60% |
| Verification / code and document review | 83,886 | 64.09% |
| Process/tooling / plan correction | 25,982 | 19.85% |
| Measurement/reporting | 5,394 | 4.12% |
| **Total** | **130,891** | **100.00%** |

The intervals sum exactly to 130,891; no arithmetic gap. The 13,870-token mixed
interval cannot be split between review and compaction recovery. No implementation,
test execution, environment setup or CI monitoring interval occurred. This is
not a subscription-usage distribution or evidence of implementation savings.
This review is not an implementation-efficiency sample or evidence of savings.
Avoidable overhead observed here included overly broad/truncated read output and
one output-buffer retry. No ongoing test or CI waiting contributed to this task.

## Conclusion

### September 11 Purchase-read process trial — finished

**Result:** the bounded backend read is implemented and verified at
`6f9efa2ed58ef4d92410ef22354f8d38a39ad774`. Run34649367344 attempt1 passed clean
database/security, contracts/MCP, 1,090 native tests in156suites (139.402s), and
both platform builds. The macOS job also passed. The remaining unrelated iOS UI
run was cancelled after the user clarified that it must not block this task.
The full run's conclusion is **cancelled**, not success. Backend acceptance is
explicitly scoped; it cannot stand in for cumulative app/merge/release verification.
Evidence: /tmp/ledger-purchase-ci-final-evidence.json and
/tmp/ledger-purchase-native-ci-final.log, plus the exact GitHub run/attempt above.
Watcher stopped and heartbeat paused. No further trial work or UI repair remains.

**Recommendation:** run cheap affected-consumer checks before pushing a coherent
batch; keep CI in the background and select UI automation by actual impact.
This trial has not demonstrated a subscription savings percentage.

The prior successful full-UI run34563203081 attempt1 took15m10s on macOS
and34m12s on iOS (GitHub step timestamps). Those durations are UI execution,
not the sub-second SQL suite or an agent's polling timer. The old-policy
run included that broad work; the local policy correction has not been
pushed or used to launch another GitHub run.

Scope: existing current-Item Purchase facts, exact money, authorized sync and
encrypted local readback. No UI reconstruction, payment writes, complete
Transaction destination, hosted replication or migration/cutover delivery.
Full-Purchase amounts are not per-Item allocations. Missing/malformed payment
evidence cannot erase physical history. Broader reuse investigation remains incomplete.

Evidence already obtained (execution times exclude compilation/setup):

| Verification | Result |
|---|---|
| Current Item reader, including NULL metadata, exact cents, revocation and reopen | 25 tests passed / 6.910s; /tmp/ledger-purchase-null-fixed.log |
| Core value/scope checks | 7 tests passed / 0.004s; /tmp/ledger-purchase-core.log |
| Full local SQL | 948 assertions, 33 files / about 1s; /tmp/ledger-purchase-db-full.log |
| Actual stream SQL | 117 captures, 13 projections passed; /tmp/ledger-purchase-stream-sql.log |
| PowerSync parser | 5 tests passed / 0.378s; /tmp/ledger-purchase-stream-parser-node24.log |
| Existing MCP/HTTP and native shared-data parity | passed; /tmp/ledger-purchase-report-mcp-direct.log; /tmp/ledger-purchase-native-parity.log |
| CI selection correction | 18 local tests passed / 0.319s; /tmp/ledger-purchase-ci-policy-tests.log; not yet deployed |

What cost avoidable effort:
- Initial selection missed a legacy SQL assertion and the report fixture's query
  count. CI34647677526 and34648180814 failed on those compatibility checks.
  The full SQL and existing shared consumers should have run locally first.
- Final review reproduced a real NULL-field reader bug and fixed it. Earlier
  CI34648906045 was cancelled because it cannot verify this subsequent change.
- Docker hung and needed the user-approved restart. Its local migration ledger
  lagged already-applied schema; only the new migration was applied directly.
  Fresh CI migration replay supplies the clean-environment proof.
- Node20 could not parse the pinned service dependency; Node24 worked. An outer
  npx invocation interfered with nested npx; direct cached Node24 resolved it.
- Written guidance changed, but automatic CI still launched both entire UI suites.
  User-authorized process correction now changes the workflow, its checker and
  existing guidance together. It retains native/backend/security/build checks.
- Goal continuations woke the model during waiting. This was **not zero-model
  waiting**. Status reviews, process changes, discussion and record maintenance
  are overhead, not the tests executing.
- Preserved unrelated gallery edits cause the raw local scope check to fail.
  They are excluded from committed Purchase work; clean CI traceability passes.

CI selection uses the existing fixed batch base. An initial full-UI-baseline
design was corrected during review because it pulled older UI work into unrelated
backend batches. No extra baseline tracker is retained. Unclassified/UI-impact
changes within a batch remain conservative; full integration/release checks remain
explicit. Historical run34563203081 attempt1 passed but attempt2 failed iOS UI.
That failure remains recorded; backend success cannot resolve it or prove release
readiness. No unrelated UI repair is authorized.

Live goal counter checkpoints (**reported tokens, not subscription usage**):

| Boundary | Cumulative | Interval |
|---|---:|---:|
| Goal creation (1789159907) | 0 | — |
| Initial inspection / baseline test | 17,652 | 17,652 |
| Implementation, hardening and environment recovery | 131,132 | 113,480 |
| Local review before CI preparation | 144,832 | 13,700 |
| Commit, CI launch and wait setup | 159,106 | 14,274 |
| Compatibility repairs, consumer checks and third CI launch | 212,744 | 53,638 |
| Later hardening, discussion, CI-policy repair and evidence review | 310,028 | 97,284 |
| Process correction, unnecessary waiting, discussion and closure evidence | 445,203 | 135,175 |
| Final scope/evidence checks and result recording | 457,000 | 11,797 |
| Goal completion receipt / closing remainder | 460,863 | 3,863 |

Cached input, uncached input and output counts are **unavailable**, not zero.
Two bounded historical-log lookups found no current request baseline; do not
rescan them. Mixed intervals cannot provide exact per-task attribution. Initial
pre-goal setup and post-goal conversation are excluded. The closing receipt totals
460,863 reported tokens over4,580seconds (about76minutes). No controlled comparison, subscription percentage or
whole-project completion estimate follows from these counters.

Measurement assessment: the counter intervals reconcile, but the activity
distribution is insufficient. The largest mixed interval group (232,459 tokens,
50.4% of the total) combines process changes, discussion, waiting, review and late
code fixes. It cannot be called all CI, all waste or all implementation. Sections
2-3 of `token-efficiency-diagnostic-plan.md` now require activity-switch readings,
an early two-interval check and a final reconciled activity distribution. That is
a forward correction, not retroactive attribution or proof of future savings.

The process trial exposed a failure to follow the intended policy: even after
recognizing that UI was outside scope, the agent continued waiting on it. That
waiting and repeated goal wake-ups were unnecessary. The corrected policy is
saved in commits cba2652d and3e9a8a86, tested locally, and deliberately not pushed
just to launch another CI batch. It still needs normal use on a future authorized
batch; this trial does not demonstrate its end-to-end token savings.

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
