# EVID-OPERATIONAL-HEALTH-001 — Operational Health and Objective Registry

- Timestamp: 2026-09-01
- Class: implementation / health, objective, alert, and runbook control
- Exact implementation commit: pending this bounded checkpoint on
  `codex/supabase-powersync-implementation`; immutable hosted CI is still
  required before verification
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and current diagnostics remain unchanged
- Claimed target surfaces: `SWIFT-D9A560340CA9`, `TEST-D534C0EDD709`
- Slice dossier:
  `conversion/implementation-slices/operational-health-and-objective-registry.json`

## Surface Selection

The reviewed platform mapping identifies `MAN-OBS-001`,
`SWIFT-7B159D426B1D`, `SWIFT-2703ADAB66C5`, and `TEST-ECE08B24ADCE` as the
broader observability/performance/navigation outcomes that the target must
eventually replace. This foundation does not claim those source surfaces: a
provider-free registry without actual target emitters, application lifecycle
wiring, adapters, approved thresholds, or physical evidence is not their full
replacement.

Exactly two target-only files are claimed. They create the shared vocabulary,
validation and pure-test boundary required before those later integrations can
be implemented without inventing health semantics per screen or per provider.

## Ready-Gate Scope

The ready dossier traces exact architecture headings into a provider-free
contract for:

- one derived health snapshot that preserves online, synchronized, Auth,
  subscription, queue, attachment, rejection, transient-error, and write-block
  truth separately;
- the complete required measurement identity set without claiming that an
  adapter has collected it;
- all seven normative initial service objectives, with missing evidence unable
  to pass;
- all alert candidates with grouping/rate-limit policy and one runbook, but no
  delivery or activation;
- every required runbook topic with complete bounded structural references;
- explicit spike-pending numeric latency, volume, cost, and physical-device
  thresholds; and
- deterministic canonical restart evidence plus stable rejection for unsafe,
  incomplete, noncanonical, tampered, or authority-bearing input.

## Implemented Contract

`LedgerTargetCore/OperationalHealth.swift` now provides:

- a validated `OperationalHealthSnapshot` derived from the existing
  `SyncHealthSnapshot` at one explicit observation time, with nonnegative
  checkpoint/operation/attachment ages and separate connectivity, Auth,
  subscription, checkpoint, operation queue, attachment queue, rejection,
  write-authority and transient-transport components;
- independent online and synchronized facts, including honest offline-ready,
  online-unsynchronized, degraded and blocked aggregate states;
- closed measurement identities with units, client/server/replication/cross-
  cutting scope, stable owner and explicit `derivedLocally` versus `planned`
  collection state;
- all seven exact-zero normative service objectives, initially unevaluated and
  satisfiable only from a complete unique typed evidence set with a digest;
- all twelve architecture alert candidates with severity, condition,
  measurement/objective references, one runbook, grouping window, rate limit
  and permanently `candidateOnly` authority;
- all twelve required runbook topics with distinct bounded references for
  detection, impact, first safe action, evidence preservation, rollback,
  escalation and recovery verification;
- all twelve architecture performance measurements with only
  `pendingVerticalSpike` status and no numeric production-threshold field; and
- canonical sorted JSON with integer epoch-millisecond time normalization,
  SHA-256 content evidence, fixed byte ceilings and decode-through-validation
  refusal for malformed, incomplete, duplicate, noncanonical, tampered or
  oversized health/registry evidence.

The registry has only `evidenceOnly` disposition. It contains no emitter, sink,
file/database/network persistence, hosted policy, incident state, executable
runbook action, provider SDK or production authority.

## Ready-Gate Verification

The two files began as comment-only scaffolds. Their stable surface IDs are
classified under the reviewed platform authority set and claimed by exactly
one implementation slice. The dossier covers domain, local/offline,
observability/runbook, rollout and operational verification obligations and
records explicit non-applicability for Postgres, handlers, Data API, RLS, Sync
Streams, Storage/media, app/MCP, and migration.

## Local Verification

Local results on 2026-09-01:

- `swift test --package-path LedgeriOS --filter OperationalHealthTests`: pass,
  four tests;
- `swift test --package-path LedgeriOS`: pass, 59 tests across eleven suites;
- health fixtures prove offline-ready is not online, online is not necessarily
  synchronized and each derived age/component/action remains explicit;
- registry fixtures prove exact closed topology, canonical reorder/restart,
  complete evidence-gated objective assessment and runbook structure;
- negative fixtures refuse invalid counts/times, duplicate subscriptions,
  missing/duplicate registry definitions, invalid alert/runbook policies,
  incomplete/unexpected/duplicate objective evidence, zero sample counts,
  digest tamper, noncanonical bytes and oversized inputs; and
- closed authority/threshold types prove the registry cannot represent an
  active policy, emitted/acknowledged/resolved alert, executable operator action
  or approved numeric performance budget.

`OPHEALTH-TEST-001`, `OPHEALTH-TEST-002`, and `OPHEALTH-TEST-003` pass locally.
`OPHEALTH-TEST-004` remains planned until an immutable GitHub Actions run passes
on the exact implementation commit with conversion/contract/graph checks, the
complete 59-test package, both target builds and clean tracked artifacts. The
slice and exactly its two target-only surfaces are therefore `implemented`, not
`verified`.

No metric was emitted, no threshold was approved, no alert was activated, and
no runbook action, provider, hosted resource, production access, deployment,
release, migration, or cutover occurred.

## Explicit Limits

This evidence is not operational readiness, a service-level claim, a dashboard,
an alert configuration, a production runbook approval, or proof that any
objective is satisfied. It cannot settle the vertical-spike thresholds or
authorize provider, staging, production, release, or cutover work.
