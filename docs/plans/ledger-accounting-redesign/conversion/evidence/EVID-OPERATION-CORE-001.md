# EVID-OPERATION-CORE-001 — Shared Operation Lifecycle and Readiness Contracts

- Timestamp: 2026-09-01
- Class: implementation / offline contract / operational readiness
- Repository baseline: `2da54304ec8261ed67c88f5510002c8d8a3626fc`
  on `codex/supabase-powersync-implementation`; checkpoint implementation was
  verified in the working diff before commit
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6`
  on `firebase`; source worktree and application target were not modified
- Target environment: dependency-free local target package; synthetic IDs and
  deterministic clocks only
- Production reads or mutations: none
- Hosted Supabase/PowerSync resources created or contacted: none
- Operator: Codex

## Surfaces

Verified target-only surfaces:

- `SWIFT-A3B756DA1382` — shared operation envelope, lifecycle, journal, error,
  query and readiness contracts
- `TEST-7D6F49F784FB` — deterministic operation/restart/readiness suite

Broader mapped surfaces that use this contract as evidence but are not verified
by this provider-free slice:

- `MCPMOD-DAB760104CEE` — target MCP error-envelope projection and app/MCP
  parity still require an entry-point slice;
- `SWIFT-F26052171FEB` — application lifecycle wiring and physical/provider
  readiness evidence still require an integration slice; and
- `FILE-F29942C1A7F4` — the target MCP/app/local/staging contract harness still
  requires dedicated test-support implementation and self-tests.

## Implemented Contract

`LedgerTargetCore` now provides:

- validated typed Operation, Account, Principal, entity and contract IDs;
- a typed `OperationEnvelope` and closed precondition values containing no
  provider SDK or persistence-path types;
- an explicit canonical codec using sorted JSON keys and epoch-millisecond
  dates, plus a SHA-256 fingerprint for same-ID payload consistency;
- queued local `OperationReceipt` values distinct from later authoritative
  `OperationSnapshot` outcomes;
- the exact draft → queued → applying → applied/rejected and explicit
  superseded/resolved transition graph;
- transient failure requeue separate from permanent domain/authorization
  rejection;
- stable application error category/code/retry values that contain no raw
  provider message or business payload;
- a Codable reference operation journal with exact replay, lost-response
  replay, Account-scoped unresolved queries and restart restoration;
- provider-free `OperationQuerying` and `SyncHealthProviding` ports; and
- an explicit health snapshot separating connectivity, Auth freshness,
  subscription readiness/version, checkpoint, pending operations/media,
  rejection, transient failure and write-block state.

The first test run intentionally failed two restart/fingerprint assertions
because the fixture encoded epoch milliseconds but decoded with Swift's default
reference-date strategy. The implementation added one public canonical codec
and the restart/fingerprint fixtures now use it in both directions. The final
suite passes and preserves the exact timestamps and fingerprints.

An audit after the later operational-health slice found that the initial
checkpoint had incorrectly advanced the three broader source surfaces above to
`verified` even though the dossier explicitly makes app/MCP integration not
applicable. Their statuses and slice ownership were corrected back to
`target_mapped`; the code, two target-only verified surfaces and test evidence
remain unchanged.

## Reproduction

```bash
swift test --package-path LedgeriOS
node scripts/supabase-conversion-ledger.mjs sync
node scripts/supabase-conversion-ledger.mjs report
node scripts/supabase-conversion-ledger.mjs check
```

Final results on 2026-09-01:

- target package build: pass;
- 11 operation lifecycle/readiness tests: pass;
- 12 target environment tests: pass;
- 23 total tests across two suites: pass;
- exact replay produces one record and the same receipt/result: pass;
- same Operation ID with a different payload fingerprint fails: pass;
- transient failure requeues and increments the next attempt: pass;
- permanent rejection does not prevent a later operation from applying: pass;
- illegal transitions preserve the prior record: pass;
- supersession retains both the original authoritative result and the later
  correction reference across serialization: pass;
- rejection resolution retains both the original rejection and its later
  resolution evidence: pass;
- journal encode/decode restart preserves Account-scoped unresolved state:
  pass;
- online and synchronized states vary independently: pass;
- contract mismatch and required-update blocks remain explicit: pass;
- contradictory pending counts/timestamps fail closed: pass;
- safe diagnostic serialization contains stable codes and no vendor message,
  token or payload: pass; and
- conversion ledger after discovery/classification: 701 recorded, 686
  currently discovered, zero errors and three explained retired-path warnings.

## Proven Verification Obligations

- `OPERATION-CORE-TEST-001`: canonical envelope/fingerprint, exact replay,
  payload mismatch and closed lifecycle transitions pass.
- `OPERATION-CORE-TEST-002`: serialized restart preserves local acceptance and
  unresolved evidence without inventing authoritative application; Account
  queries remain isolated.
- `OPERATION-CORE-TEST-003`: transient retry, permanent rejection, queue
  continuation and lost-response result replay pass.
- `OPERATION-CORE-TEST-004`: explicit readiness/write blocks, health
  validation and safe diagnostic bounds pass.

## Explicit Limits

This evidence verifies the backend-neutral shared contract and reference
behavior only. It does not select or prove:

- A-003/A-004 Supabase/PowerSync provider architecture;
- A-015 optimistic projection storage or queue ownership;
- A-016 offline authorization duration/unlock policy;
- Postgres operation/result tables, handlers, Data API grants or RLS;
- PowerSync Sync Streams or physical-device durability;
- generated TypeScript/MCP contract parity or concrete app presentation;
- Firebase pending-write migration; or
- deployment, production migration, release or cutover authority.
