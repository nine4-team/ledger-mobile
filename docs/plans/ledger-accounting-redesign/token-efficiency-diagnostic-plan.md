# Token-efficiency diagnostic plan

## September 11 follow-up: quiet CI monitoring experiment

Status: completed September 11. Quiet waiting succeeded; the unchanged rerun
failed two iPhone gallery checks. Results and usage are recorded in the existing
efficiency assessment under "Quiet CI trial — September 11". The heartbeat is
paused; no repairs or further reruns are authorized by this experiment.
This was a monitoring-only
experiment, not a new implementation batch or additional feature-completion claim.
It is the single authorized diagnostic exception to the normal no-duplicate-CI rule.

- Run the unchanged Supabase conversion suite at
  `505dc2bb658076b0536e705038dd29b020747baf` once, by rerunning CI34563203081.
  Preserve all tests, existing timeouts, and local dirty Purchase work. No code,
  workflow configuration, production, or Firebase checkout changes.
- Intervention: end the active AI turn while GitHub executes. Use one thread
  heartbeat after roughly an hour to inspect the result. No minute-by-minute
  model polling, wait/resume loop, repeated log review, or unchanged commentary.
  This is scheduled monitoring, NOT an instant completion/failure callback.
  Account for delayed failure detection and desktop availability as tradeoffs.
- At wake-up, read job status once. If complete, inspect compact per-job results
  and exact native test summaries; fetch detailed logs only for failures or
  missing evidence. If still running, leave quietly until the next scheduled
  check. Stop after completion or a concrete access/measurement failure; pause
  the heartbeat. Do not repair unrelated app code or rerun the suite again.
- Record setup, idle interval, result review, and reporting costs separately in
  the existing efficiency assessment. Use cumulative session-counter differences;
  cached input is part of input, reasoning is part of output. Include automated
  follow-up invocation costs. Check for session changes and counter resets.
- Subscription baseline: the account-wide weekly meter reported 8% used during
  setup on September 11; reset timestamp 1789516099. Read it at launch and closure.
  Its displayed precision and other tasks prevent direct causal attribution;
  do not call a rounded zero change zero cost. Do not consume reset credits.
- Historical comparison: prior CI waiting/review interval had 11,743,612 input,
  including 11,614,592 cached input, and 25,668 output tokens. Its cost-weighted
  estimate is a PROXY, not measured subscription consumption. Keep comparison
  limited to monitoring/review: this rerun reuses already-reviewed code, has no
  implementation effort, and is not a controlled whole-batch experiment.
- Primary success: unchanged tests finish, evidence is reviewed, and no AI calls
  are spent checking unchanged CI during the planned idle interval. Report actual
  token change, account meter movement, detection delay, and limitations. Do not
  force the tentative 35% whole-batch savings target into the result.

Session source (counter fields only, never dump raw conversation logs):
`/Users/benjaminmackenzie/.codex/sessions/2026/09/03/rollout-2026-09-03T10-23-44-01a0597e-a903-72f1-83da-ad0e7d114ac0_01a0684c-483f-7cc1-8810-354d376933d4.jsonl`.
Current model observed: gpt-6-astra. Pre-launch sample at 15:22:36.147Z:
input 1,019,690,322; cached 1,007,360,640; output 2,413,296;
total 1,022,103,618. This is not the setup-start counter. Resolve the user-request
boundary from the session when reporting setup; mark unavailable if unrecoverable.
Launch: CI34563203081 attempt 2, started 2026-09-11T15:24:25Z; confirmed in_progress
at the required exact commit. URL:
https://github.com/nine4-team/ledger-mobile/actions/runs/34563203081/attempts/2.
Heartbeat `ledger-quiet-ci-trial` returned at 16:24:29.830Z and was PAUSED after
review. No further scheduled runs remain active for this experiment.
Do not mistake the successful attempt 1 for this experiment's result.

Recovered setup-start boundary: user request at 15:21:27.710Z, preceding counter
at 15:20:58.877Z: input 1,019,439,324; cached 1,007,124,096;
output 2,411,703; total 1,021,851,027. Launch account meter: 9% weekly used,
same reset timestamp as the 8% setup reading. This is an observed account movement,
not proof this task consumed one exact percentage point.
Pre-yield sample 15:24:28.072Z: input 1,020,005,972; cached 1,007,665,536;
output 2,415,871; total 1,022,421,843. Setup includes one rejected automation
creation (missing destination=thread) followed by successful corrected creation.
Include remaining checkpoint/final-message and wake-up/review calls in closure
totals; this pre-yield sample does not include those. Use the actual end of this
setup turn and beginning of scheduled resumption for the idle interval.

Status: completed September 10. The initial observation closed already-built
gallery verification. The separately authorized goal then delivered the missing
Project Item accounting facet; all four checks passed exact-commit CI34563203081
at505dc2bb. Final task metrics, findings and limitations are in the existing
efficiency assessment. Neither observation establishes broad savings percentages.

Observed boundary: `ITEM-IMAGE-VIEWER-CONTROLS` and
`ITEM-IMAGE-NATIVE-GESTURES` in `downloaded-item-browsing-and-detail`, starting
from `f66e2927f7ea816a15d50e81f2f7ae08e9960631`. Finish when exact-commit CI and
assertion/source review establish those behaviors, or identify a concrete gap.
Exclude other Item checks, Purchase work, media writes and migration. Both
selected checks passed review against automatic CI34396683481; unchanged native
code needed neither repair nor rerun. Observations and counters are in the
September 10 efficiency assessment, not a second progress ledger.

## Objective

Implementation observation boundary: implement the genuinely missing Project Item accounting
facet in the existing read workflow. Exact checks: ITEM-ACCOUNTING-FILTER-VALUES,
ITEM-ACCOUNTING-FILTER-COMPOSITION, ITEM-ACCOUNTING-FILTER-LIFECYCLE, and
ITEM-ACCOUNTING-FILTER-NATIVE. Start at f66e2927 with existing dirty Purchase and
process work preserved; neither is new trial implementation. Finish with shared
filter logic, the native control, focused tests and exact-commit integrated CI.
Authority: items.md Target Everyday Workspace (accounting-association facets,
AND/OR composition, selection pruning and unknown evidence). Do not call this
a payment-status or source mutable-Transaction filter. No new data/grants/Sync,
writers, prices, Purchase destinations, migration or media changes in this batch.
Existing atomic Project Item reader supplies the required canonical resolution.

Identify avoidable token use, explain its causes, and test specific corrections
without weakening implementation quality. Affordability, remaining project cost,
and whole-app completion estimates are outside this exercise. No predetermined
savings percentage is required.

## 1. Define one bounded batch

Use existing Item browsing/detail work. Before implementation, select exact
acceptance-check IDs from the existing checklist, identify starting code and
already-completed work, and state the finish condition and exclusions. Inspect
outstanding verification results before repeating work. Use the existing checklist
and current-state record; do not create another progress-tracking system.

The recently repaired batch-baseline checker is a starting condition, not an
intervention with a measured historical comparison. Keep the batch base separate
from the last verified checkpoint. Starting a batch grants no completion credit
to earlier work.

## 2. Establish trustworthy measurement

Verify what the available counter measures before promising precision: per-request
versus cumulative usage, cached input, reasoning, context compaction, and delegated
work. Do not double-count reasoning included in output. Do not equate token counts
with account-limit consumption or dollar cost.

Prefer existing telemetry. Otherwise read a cumulative counter at the sample
start, each activity switch, before yielding, immediately on resume, and closure.
Use one boundary reading to close the outgoing interval and open the incoming
one; do not log every tool call. Record the source/identifier, timestamp, units and
starting value once. A goal counter must belong to the active measured goal, not
a completed previous goal. It measures reported goal usage, not subscription cost.
For a goal-based sample, use `get_goal` on that active goal and retain its goal
identity/creation timestamp. If no live counter is available, label measurement
unavailable before proceeding; do not promise a measured activity distribution.

Never subtract counters across a reset, goal/session change or incompatible
source. Start a new segment and retain any gap as unattributed. Record separate
cached-input, uncached-input and output deltas only if the source supplies them;
missing fields are unavailable, not zero. Do not double-count delegated usage
already included in a parent total, or reasoning already included in output.

An interruption can straddle activities before a boundary is captured. Mark that
interval mixed/unattributed unless finer existing telemetry can separate it.
Do not assign it entirely to implementation or CI by its ending activity, or guess
proportions from elapsed time, commits or tool counts. The September 11 Purchase
intervals remain mixed; this protocol cannot repair missing boundaries retroactively.

## 3. Record concrete tasks cheaply

Maintain one small append-only interval table in the existing efficiency assessment,
not a second progress catalog. Its heading identifies the sample and counter source:

| Activity / concrete task | Start → end counter | Delta | Result / revisit reason |
|---|---|---:|---|
| One activity, not several phases combined | Readings from the same source/segment | End minus start | Short result, including failure or discarded work |

Use these non-overlapping categories for measured work:

- **Implementation:** design, product code and its new/updated tests, including
  normal red/green development. Close this interval before running/reviewing tests.
- **Verification:** test selection, execution-related agent work and result/code
  review; not repairs or the time an external test runs unattended.
- **Rework:** repairing missed dependencies, regressions, wrong assumptions or
  unintended rebuilding. Name the triggering defect, not merely "debugging."
- **Environment/setup:** Docker, runtimes, dependencies or credential prerequisites.
- **Process/tooling:** CI-policy changes, guard scripts and working instructions.
- **Discussion/coordination:** user explanations, decisions and agent coordination.
- **Monitoring:** model work to launch/watch/check external jobs; dormant wall time
  is not itself tokens. Do not label all activity while CI runs as monitoring.
- **Context recovery:** inspection/re-reading needed to recover prior state.
- **Measurement/reporting:** counter capture, progress records and result reporting.
- **Mixed/unattributed:** missing boundaries, gaps or intervals that cannot be split.

At a switch, read the counter before substantive work in the next category. Keep
the source, open activity and last reading as one compact pointer in the normal
resume record. After compaction resume that measurement, not a new history audit.
Keep boundary rows compact in working memory and flush them at normal checkpoints
or before yielding; do not rewrite the report after every test or tool call.
Explicitly label startup, boundary-reading and final-handoff overhead that cannot
be cleanly assigned. Test wall time may be reported separately.

After the first two switches, check contiguous boundaries, source/units and that
no "implementation + CI + discussion" interval masquerades as one activity.
Correct missing instrumentation immediately, not at the end of the feature.
Do not start a telemetry implementation to obtain precision.

At closure, read the counter after preparing the result and reconcile:
**sum of recorded deltas + unattributed remainder = measured total**. Report
tokens and share of that same total by activity, including mixed/unattributed.
Include failed attempts, process interventions and reporting overhead; do not
hide measurement overhead by subtracting it. A nonzero gap remains visible. A
large mixed bucket makes activity attribution insufficient even if arithmetic
reconciles. Do not claim the diagnostic succeeded merely because the feature did.
A completed goal's final returned counter can supply the small closing remainder,
without another history scan or monitoring loop.

Do not introduce parallel agents solely for this observation. If separately
authorized parallel work occurs, account for attributable delegated usage and mark
overlapping intervals without double-counting them.

## 4. Investigate expensive activities and repeated work

Inspect the largest observed costs and tasks that were revisited. Look for:

- Rediscovering information already available, including repeated oversized reads.
- Rework caused by missed existing requirements, incorrect assumptions, incompatible
  contracts, or demonstrated unnecessary duplication.
- Repeated verification or investigation that answers no new risk question.
- Fragile test interactions that cause recurring repairs or repeated diagnosis of
  one shared defect.
- Scope expansion, duplicated reviews, excessive tracking, and costly recovery from
  missing or misleading checkpoints.

For each finding, identify the triggering event, evidence, causal explanation,
observed cost or attribution limitation, and a cheaper alternative preserving the
same required behavior and risk coverage. Classify it as necessary, avoidable,
or uncertain. Expensive work and unsuccessful experiments are not automatically
wasteful. Do not classify a whole task's tokens as waste when only a portion was
avoidable; quantify that portion only where the measurement supports it.

## 5. Correct demonstrated problems during the batch

Inspect observations at the first completed acceptance unit, when a failure or
investigation repeats, and at batch closure. These are decision points, not
occasions for recurring status essays.

Apply small, supported corrections within authorized scope instead of continuing
a known wasteful loop. Examples include fixing a shared test helper, narrowing
log retrieval, or correcting a misleading resume pointer. Record when each change
occurred and compare the next similar task where possible. Preserve the agreed
acceptance boundary. Substantial architectural changes become recommendations
rather than silently expanding the batch.

Preserve product fidelity, authorization, accounting correctness, offline/restart/
replay guarantees, media durability, and required verification. Compare equivalent
outcomes and risks when judging alternatives. Keep observations before and after
an intervention distinguishable; one uncontrolled batch cannot prove broad
percentage savings.

## 6. Stop and report

Stop when the batch reaches its defined finish condition, or when a blocker makes
further observation unproductive. Do not automatically expand the sample to obtain
a desired finding. Report:

1. The behavior delivered or blocked and the starting conditions.
2. Tokens by task and activity, including monitoring overhead, unassigned usage,
   and measurement limitations.
3. Specific unnecessary work, its causes, and supporting evidence; also identify
   expensive work that was necessary and suspicions the evidence did not support.
4. Corrections tested and their observed effects. Mark benefits unmeasured where
   no comparable subsequent occurrence exists.
5. Recommendations ranked by observed recurring cost, confidence, and correction
   effort, distinguishing what to retain, change, or investigate next.

No new tracking system, whole-app audit, production access, hosted provisioning,
migration, or cutover is part of this plan. Work remains confined to the separate
Supabase worktree, preserving existing uncommitted implementation.
