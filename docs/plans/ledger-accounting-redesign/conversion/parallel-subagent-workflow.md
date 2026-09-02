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

Read-only exploration, test design and adversarial review may run earlier when
their scope is bounded and they do not mutate a checkout or external system.

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

## First-Two-Pilot Quality Gate

The first two write-capable assignments receive enhanced review:

- every changed line is reviewed by the integration agent;
- a separate read-only reviewer independently checks every dossier requirement,
  public API, stable failure, restart path, negative case and scope exclusion;
- the integration agent reruns both focused tests and the complete gate rather
  than accepting worker output;
- the registry records findings by severity and their exact disposition; and
- any critical finding, repeated major finding, out-of-scope edit or evidence
  overclaim suspends further write-capable delegation until this workflow is
  corrected and revalidated.

After two clean pilots, line review, full local verification and exact-commit CI
remain mandatory. The extra independent review may be risk-based, but security,
RLS, Sync, accounting, migration and cutover slices always require it.

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
