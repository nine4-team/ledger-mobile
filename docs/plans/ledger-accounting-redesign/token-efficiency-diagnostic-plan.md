# Token-efficiency diagnostic plan

Status: authorized September 10; first observation completed. After inspecting
CI, the selected work required verification closure, not new implementation.
Implementation efficiency remains unmeasured; do not enlarge this sample to
manufacture implementation work.

Observed boundary: `ITEM-IMAGE-VIEWER-CONTROLS` and
`ITEM-IMAGE-NATIVE-GESTURES` in `downloaded-item-browsing-and-detail`, starting
from `f66e2927f7ea816a15d50e81f2f7ae08e9960631`. Finish when exact-commit CI and
assertion/source review establish those behaviors, or identify a concrete gap.
Exclude other Item checks, Purchase work, media writes and migration. Both
selected checks passed review against automatic CI34396683481; unchanged native
code needed neither repair nor rerun. Observations and counters are in the
September 10 efficiency assessment, not a second progress ledger.

## Objective

Active goal follow-on: implement the genuinely missing Project Item accounting
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

Prefer existing telemetry. Otherwise use counter differences at natural task
boundaries. Record mixed work, interruptions, and unavailable attribution explicitly.
Reconcile task totals with the measured batch total, showing unassigned usage.
If precise attribution is unavailable, retain aggregate measurements and qualitative
observations; do not build a telemetry platform or substitute elapsed time, code
volume, or tool counts for tokens.

## 3. Record concrete tasks cheaply

Maintain one small measurement table alongside the existing efficiency assessment:

| Task | Result or reason for failure | Activity | Tokens and measurement basis | Why revisited? |
|---|---|---|---|---|
| Concrete work unit | What it accomplished or ruled out | Implementation/design, testing/debugging, or coordination | Measured value or explicit uncertainty | Prior task and trigger, if applicable |

Use natural work units, such as implementing a query or diagnosing a gallery
failure, rather than logging every tool call. Include failed attempts, discarded
work, context recovery, and monitoring/reporting overhead. Keep test-waiting time
separate from token use. Preserve the measurement pointer in the normal resume
record if context compacts. Use short evidence references only where they explain
a finding.

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
