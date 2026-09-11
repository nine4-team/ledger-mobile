# EVID-PROJECT-CATEGORY-CONFIGURATION-REVISION-001 — Dedicated Project Category-Configuration Revision Implementation

- Date: 2026-09-06
- Class: isolated local implementation / independently reviewed and exact-CI-backed prerequisite
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on `firebase`; the Firebase checkout and released app were not changed
- Target branch: `codex/supabase-powersync-implementation`
- Frozen READY baseline: `dec9a5703fc9d723d02f60ff6b1037f2db8e9dd2`
- Slice dossier: `conversion/implementation-slices/project-category-configuration-revision-foundation.json`
- Claimed leaves: `CONFIG-3F4DAB40CF04`, `CONFIG-6EE152848D09`

## Implemented Outcome

Every synthetic target Project now owns one independent `category_configuration_revision`. PostgreSQL stores an exact positive integral value through the full inclusive `UInt64` range, defaults and backfills it to `1`, and documents that it is neither the Project entity revision nor an allocation-row-derived value.

Both existing Project Sync projections explicitly cast that value to canonical decimal text. The authoritative and pending PowerSync Project tables store text, and offline Project acceptance writes projected text `1` in the same transaction as the local operation, optional Client, Project, complete allocation set and queued command.

No category configuration command, provider, application model, view or MCP behavior was activated. The six discovered downstream scaffolds remain comment-only and O-026-blocked.

## Exact Database and Access Proof

The 33-assertion pgTAP suite inspects the actual migrated Project column's numeric type, non-null/default contract, named range constraint and comment. A separate scratch relation inserts a row before executing the same additive column definition and proves PostgreSQL backfills it to `1` without replacing the real migrated column under test.

The real `spike_create_project` RPC is exercised with empty and nonempty allocation sets; both Projects begin at revision `1`. Invalid zero, fractional, null and above-`UInt64` values are rejected. Project archive increments only the Project entity revision and leaves configuration and allocation revisions unchanged.

Active membership reads the new value. Anonymous has no SELECT or INSERT/UPDATE/DELETE privilege; removed, nonmember and foreign-Account principals read no Project; authenticated callers have no INSERT/UPDATE/DELETE privilege, and a removed member's direct update is denied.

## Offline and Sync Proof

Encrypted close/reopen preserves revision text `1` and the complete three-allocation optimistic aggregate. A fault trigger aborting the first pending-allocation insertion proves the surrounding acceptance transaction leaves no local operation, pending Client, pending Project, allocation or command. A changed replay preserves every original aggregate component and queued command. Remote rejection removes the complete aggregate.

A simulated authoritative local projection preserves decimal text through `18446744073709551615`. Authoritative Project-core readback at revision text `1` removes only the Project/Client core overlays and deliberately retains pending allocations until a future configuration-aware provider has complete aggregate evidence.

The target checker exact-compares the ordered normalized text of all three `spike_projects` queries and both `project_note_history` queries. Extra projections, joins, filters, OR branches, query additions/removals, reordered queries, authorization changes, category-visibility changes or a new stream fail closed. This is static configuration proof, not a claim that a hosted PowerSync session has run.

## Independent Review

Two independent reviewers initially returned NO-GO because the first candidate did not truly exercise Project-command initialization or backfill, omitted anonymous/removed access cases, used substring-level Sync checks and lacked a mid-transaction local failure. Their second pass found further incomplete rebound coverage, copied-DDL test contamination, sibling-query authorization ambiguity and incomplete DML privilege assertions.

All findings were corrected. Both reviewers then returned GO with no P0–P3 findings after independently rerunning the focused database, Swift, target-environment and lint checks.

## Local Verification

- actual migration plus clean local database suite: 373/373 pgTAP assertions in 10 files
- focused category-revision pgTAP: 33/33
- focused Project PowerSync suite: 10/10
- complete Swift package: 566/566 tests in 90 suites
- database lint at warning level with fail-on-warning: zero findings
- target environment/isolation checker and JavaScript syntax check: passed
- target MCP tests: 26/26; contract generation, TypeScript and catalog checks: passed
- deterministic target project generation and both macOS/iOS target staging builds: passed with no generated-project drift
- immutable exact-implementation commit CI: all three jobs passed at
  `ac9fdcd4bb43c979526503862d715de61a9ee4e6` / run `34011514963`, attempt 2

READY commit `dec9a5703fc9d723d02f60ff6b1037f2db8e9dd2` entered Actions run `34006713872`; its conversion job stopped only because generated residual artifacts had not been refreshed. Those artifacts were regenerated before implementation. No executable READY boundary or product decision was changed to make that check pass.

Exact implementation commit
`ac9fdcd4bb43c979526503862d715de61a9ee4e6` passed every immutable job in
Actions run `34011514963`, attempt 2. Conversion state and traceability passed,
the disposable local Supabase job passed schema, RLS, RPC, replay, lint and all
373 pgTAP assertions, and the isolated target job passed all 566 Swift tests,
MCP/contracts, environment guards and both staging builds. Attempt 1 had already
passed the conversion and Supabase jobs but timed out during target-test process
shutdown. The unchanged exact-commit rerun passed, but later directory-only
correction run `34013428800` again timed out after the Client archive suite.
That result proved the initial diagnosis incomplete. The expanded directory and
core-details provider-lifecycle correction is separately reviewed and evidenced
by `EVID-CLIENT-PROJECT-DIRECTORY-PROVIDER-001` without changing this slice's
schema, Sync projection or Project-store implementation.

## Remaining Gates and Safety Boundary

The slice remains `implemented`, not `verified`, because real authenticated hosted PowerSync authorization/readback remains deliberately unclaimed; A-003/A-004/A-015 remain proposed and O-026 remains open.

No Firebase file or worktree, hosted resource, source export/import, production data, migration run, deployment, release or cutover was touched or authorized.
