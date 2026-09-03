# Parallel Subagent Implementation Workflow

Status: required for every write-capable conversion subagent

## Purpose

Subagents may shorten Ledger's implementation calendar only when they preserve
the conversion control plane's single product and evidence authority. Parallel
work is organized around complete frozen vertical slices, never around
competing technical layers or shared control files.

The integration agent remains the sole writer of the canonical conversion
branch's product authority, manifest, generated artifacts, evidence status and
execution state. A worker produces an untrusted candidate commit in an isolated
branch and worktree. Integration, verification and status promotion remain
serial.

## Eligibility Gate

A write-capable assignment may begin only when all of the following are true:

1. the slice dossier is `ready`, has no blocker and passes conversion checking;
2. the exact ready commit has passed both pull-request CI jobs;
3. the assignment is recorded in `parallel-work-registry.json` with its exact
   base commit, branch/worktree, owned paths, forbidden paths and tests;
4. owned paths do not overlap another active assignment or a shared foundation;
5. the work can implement the complete frozen slice without choosing an open
   product or architecture decision; and
6. no production, credential, spend, hosted-resource, migration-execution,
   release or cutover authority is required.

For a product slice, the integration agent and an independent read-only
reviewer must also confirm that every promised user-visible outcome appears in
a canonical target spec or confirmed D decision. Batch-level association with
broad target specs, current shipped behavior, an architecture interface, a
capability dossier, or an existing `target_mapped` status is not sufficient.
Authority must be feature-specific and must not be created during ready-gate
preparation merely to justify the proposed slice. If the audit discovers a new
product choice, add an O blocker/decision packet and select another slice.

Read-only exploration, test design and adversarial review may run earlier when
their scope is bounded and they do not mutate a checkout or external system.

## Delegation Economics and Worktree Threshold

A worktree is an isolation mechanism for a delegated writer, not the unit by
which implementation should be divided. Every concurrent write-capable worker
uses one even when its frozen ownership happens to contain only two files: that
is what keeps its exact base, index, untracked files and candidate lineage from
colliding with the integration branch or another worker. The number of files
alone does not measure the size or risk of the change.

Do not create a write-capable assignment merely because two leaf files can be
isolated. The default delegation unit is one coherent, independently testable
outcome expected to change roughly 600–1,200 lines across two to six leaf
implementation/test paths. This is a planning range, not a status shortcut:
scope cohesion and authority boundaries take precedence over line count.

The integration agent normally implements work expected to take less than
about 20 minutes or 300 changed lines itself. It may still isolate a smaller
change when concurrent writes are already active or the boundary is unusually
risky. Conversely, a larger candidate must be split when it crosses product
authority, shared foundations or independently promotable outcomes. Never pad
a slice with unrelated work to meet a size target.

The preferred topology is one write-capable worker for the frozen outcome, one
read-only scout or adversarial reviewer, and the integration agent retaining
all control-plane and promotion work. This preserves useful parallelism while
avoiding worktree, control-commit and CI overhead for micro-slices.

## Ownership

The integration agent exclusively owns:

- canonical specs and the decision log;
- architecture and shared domain primitives;
- classification batches and the product-authority crosswalk;
- the conversion manifest, generated coverage/audits and residual register;
- slice dossiers, the evidence index and `execution-state.md`;
- package/project graphs, contract generators and migration ordering;
- commits and pushes to `codex/supabase-powersync-implementation`; and
- final local gates, exact-integration-commit CI and lifecycle promotion.

A worker owns only the allowlisted leaf implementation/test paths recorded for
its assignment. It must not run conversion synchronization or generators,
modify either application project, edit Firebase, access credentials or hosted
resources, push the integration branch, or advance evidence/status.

## Worker Handoff

The worker returns one candidate commit plus:

- exact base and candidate commit IDs;
- all changed paths;
- focused test commands and results;
- a requirement-by-requirement account of the implementation;
- assumptions, compromises and remaining risks; and
- confirmation that forbidden files/actions were untouched.

A changed path outside the allowlist, a material base/authority change, an
implicit A-/O- decision or incomplete handoff invalidates the candidate until
the integration agent explicitly re-scopes it.

## Integration and Verification

The integration agent reviews and integrates one candidate at a time:

1. compare the candidate's exact base and changed paths with the registry;
2. inspect every changed line against the frozen dossier and canonical
   authorities;
3. run an independent read-only adversarial review for correctness, security,
   offline semantics and missing tests;
4. resolve every material finding before integration;
5. cherry-pick or reproduce the accepted patch on the canonical branch;
6. regenerate and reconcile all control-plane artifacts centrally;
7. run focused tests and the complete local conversion/target/build gate;
8. commit and push the integrated result; and
9. require both CI jobs at the exact integrated commit before verification.

Worker-branch tests or CI are preliminary evidence only. They never prove a
cherry-picked, rebased, conflict-resolved or regenerated integration commit.

## Delegation Calibration Quality Gate

Every candidate receives integration-agent line review. Independent adversarial
review is additionally mandatory until five consecutive delegated candidates
complete without an accepted P0-P2 defect, an out-of-allowlist edit or a
material product-authority correction:

- every changed line is reviewed by the integration agent;
- a separate read-only reviewer independently checks every dossier requirement,
  public API, stable failure, restart path, negative case and scope exclusion;
- the integration agent reruns both focused tests and the complete gate rather
  than accepting worker output;
- the registry records findings by severity and their exact disposition; and
- any P0-P2 finding, out-of-scope edit or material authority correction resets
  the five-candidate calibration count; and
- any critical finding, repeated major finding or evidence overclaim suspends
  further write-capable delegation until this workflow is corrected and
  revalidated.

Candidate selection itself is part of the pilot: a proposed slice rejected
before worker launch is recorded as a preflight finding, not counted as a
completed write pilot. The 2026-09-02 Inventory destination-planning candidate
demonstrates this guard: independent review found no canonical target decision,
a D-013 category conflict, and unresolved granularity/lifecycle, so the
scaffolds were discarded and O-038 was opened before any implementation.

After five consecutive qualifying candidates, line review, full local
verification and exact-commit CI remain mandatory. The extra independent
review may become risk-based, but accounting, authentication/security, RLS,
Sync/offline durability, provider, migration/reconciliation, release and
cutover slices always require it. A candidate that required P3-only correction
may still qualify for the counter, but its finding remains recorded and the
integration agent may extend enhanced review when the pattern indicates weak
tests or evidence.

### Pilot outcome — 2026-09-02

The first two enhanced write-capable pilots completed without an accepted P0-P2 defect.
The controls nevertheless changed the outcome materially:

- pilot 1's independent review found and corrected one P3 documentation
  ambiguity before verification;
- candidate selection review rejected Inventory destination planning before a
  writer launched because canonical target authority was missing and O-038 was
  unresolved; and
- pilot 2's integration review rejected an approximately 1,076-line first
  draft on maintainability grounds and required a reduced 768-line candidate
  before commit; independent adversarial review then found no P0-P3 defect.

This was enough evidence to continue bounded delegation, not evidence that
worker output may be trusted without inspection. A later Project existing-
Client selection candidate exposed a P1 false-authoritative-empty defect during
independent review, so the calibration counter was reset. Every worker
candidate still requires exact ancestry/path verification, integration-agent line review,
focused and complete local gates, central regeneration and exact integrated-SHA
CI. Independent adversarial review remains mandatory for novel shared
semantics, accounting, security, authorization/RLS, Sync/offline durability,
migration/reconciliation, provider, release and cutover work, and whenever the
integration review identifies complexity, ambiguity, unusual size or weak test
evidence. It is optional only for low-risk leaf work whose behavior is already
fully fixed and whose complete diff is straightforward for the integration
agent to validate.

## Concurrency Limits

- At most two write-capable workers may run concurrently.
- Each worker uses a unique `codex/` branch and Git worktree pinned to an exact
  ready commit.
- Two workers may not share a classification batch, shared primitive, package
  graph, schema migration sequence or owned path unless the registry serializes
  them explicitly.
- One worker owns a complete vertical slice; a slice is not divided into Swift,
  SQL, RLS, Sync, app or MCP agents that can redefine its semantics separately.
- Product decisions, shared schema foundations, Auth/offline authority design,
  vertical-spike stage progression, production profiling, migration sign-off,
  release and cutover remain serial.

## Continuity

`parallel-work-registry.json` is the durable source for active assignments. On
resume or compaction, reconcile it with `git worktree list`, the recorded branch
heads and the canonical working tree before steering, integrating or creating a
worker. Conversation summaries cannot prove ownership or completion.
