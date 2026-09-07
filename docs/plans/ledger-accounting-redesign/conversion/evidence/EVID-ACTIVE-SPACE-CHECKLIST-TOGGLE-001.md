# EVID-ACTIVE-SPACE-CHECKLIST-TOGGLE-001 — Active Space Checklist Item Toggle

- Date: 2026-09-06
- Class: isolated local implementation / independently reviewed product workflow
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on `firebase`; the Firebase checkout and released app were not changed
- Target branch: `codex/supabase-powersync-implementation`
- Workflow record: `conversion/workflow-records/active-space-checklist-item-toggle.json`
- Directly owned surfaces: `SWIFT-84575506886A`, `SWIFT-FF03A6E032AA`, `SWIFT-8FE0D1AD0744`, `TEST-37FF8615DAB5`, `TEST-6C3784A08B93`

## Implemented Outcome

One exact active Project or Business Inventory Space now supports toggling one existing checklist item through the isolated target app. The AppModel derives one complete ordered replacement command from represented Space detail, accepts it durably before projecting the new checked state and progress, prevents duplicate submission, retries uncertain acceptance byte-identically, observes the exact operation, and reconciles only against later authoritative Space evidence.

Waiting, incomplete, unavailable, absent and archived details remain non-writable. Empty checklists, collapsed/expanded presentation, pending state, rejection and retry are explicit. The workflow does not add checklist creation, deletion, reordering or text editing; Space completion; Item/media/template behavior; accounting; MCP registration; or any Firebase behavior.

## Database and Authorization Boundary

- The local Supabase migration adds the checklist-revision command/result relations and one trusted transactional RPC. The handler validates the full hierarchy, exact Account/Space/actor/operation/fingerprint/revision binding and active membership, replaces the hierarchy atomically, increments the Space revision once and returns an immutable terminal result.
- Forced RLS and explicit grants deny anonymous, inactive, cross-Account, wrong-parent and direct-table writes. The client adapter accepts only injected publishable-key and scoped-user-token authority and refuses service-role credentials or malformed result evidence.
- pgTAP proves exact replay, changed-payload rejection, stale revision, concurrent revision races, hierarchy constraints, immutable scope and unrelated-row preservation without partial mutation.

## Offline, Restart and Readback Proof

PowerSync stores the operation, insert-only command and optimistic checklist overlay atomically in the encrypted Account workspace. Exact replay and reopen reconstruct the same command and displayed hierarchy. Actor, Account, Space, contract, fingerprint, revision and collection provenance are retained with the local projection, so a newly created AppModel can restore the operation and reattach its watch without accepting a duplicate toggle.

Applied optimism remains visible until a current-process completed exact stream produces a fresh authoritative snapshot. Reconciliation atomically records the exact projected readback revision and deletes only the identity-matched overlay. Replay and operation observation require either the exact retained overlay or that durable marker plus an authoritative revision at or beyond it; missing, mismatched or corrupted proof fails closed. Rejection waits for later complete detail evidence before removing optimism, and server-ahead terminal timestamps remain valid.

## Independent Review and Corrections

Independent review initially returned NO-GO. It found that restart could display an overlay without restoring the operation; rejection/detail event order could settle against old evidence; device receipt time could precede a server terminal timestamp; archived wording falsely implied missing evidence; and cleanup removed the only exact proof needed for later replay/watch.

Root corrected all five areas with backend-neutral projection provenance, restart watch reattachment, evidence-sequenced settlement, monotonic terminal timestamps, honest archived copy, a durable exact readback marker and corruption coverage. The final independent re-review returned GO with no remaining P0/P1 finding. A complete regression then exposed and corrected one strict-decoding bug where absent optional projection metadata was mistakenly rejected.

## Local Verification

- checklist-toggle AppModel/UI contracts: 10/10 passed
- encrypted PowerSync/RPC vertical slice: 6/6 passed
- complete Swift package: 690/690 tests in 100 suites passed serially
- disposable local Supabase: zero lint findings and 426/426 pgTAP assertions in 12 files passed
- local scoped read/RPC probes: passed
- target contract generation/check and MCP typecheck/tests: passed, including 27/27 MCP tests
- conversion state, query-port, query-authority, source-reconciliation, capability, query, residual and M0 gates: passed with only the three established retired-surface warnings
- isolated target environment checker: passed
- macOS and generic iOS Simulator staging builds: passed
- exact-commit automatic CI: pending

## Remaining Gates

A-003 and A-004 remain proposed. A real isolated authenticated Supabase/PowerSync session must still prove authorized upload, Sync receipt, membership revocation and eviction before this workflow can claim hosted rehearsal or cutover readiness.

This implementation creates no hosted or paid resource, accesses no production data, changes no Firebase code or checkout, performs no migration, and authorizes no deployment, release or cutover. Product specs and the decision log remain product authority.
