# EVID-ACCOUNT-DISCOVERY-PROVIDER-001 — Account Discovery PowerSync Provider

- Status: READY candidate; comment-only implementation leaves
- Date: 2026-09-04
- Environment: isolated target worktree and synthetic/disposable local fixtures only
- Production/Firebase impact: none
- Slice: `account-discovery-powersync-provider`
- Surfaces: `SWIFT-A8B0B06147C3`, `SWIFT-8AA6BB698C64`, `TEST-D960EA615333`, `SWIFT-3BFEA9F12A91`

## Outcome

This package freezes the smallest provider-backed Account-discovery outcome:
observe the Principal's locally available visibility-safe Account projection with
honest bootstrap readiness, define those states in a build-only isolated staging
component, and create one explicit local selection intent from the exact current
snapshot through the canonical policy.

The four implementation leaves contain comments only. No runtime, query, UI,
hosted resource or production behavior is executable until this synchronized
READY checkpoint passes review and immutable CI.

## Authority and Boundary

The canonical Account discovery spec already settles stable Account identity,
safe display metadata, duplicate-name handling, complete/partial/stale/empty
truth, deterministic ordering, explicit selection and non-enumerating failure.
The offline and adapter architecture assigns the implementation to a small
Principal bootstrap stream plus `AccountQuerying`.

This slice stops before workspace activation. It does not decide Auth provider
A-007, offline lease A-016, refresh current server authorization, open protected
Account data, switch streams, dispose pending work, remember a selection,
create Accounts/memberships, or implement MCP session state.

## Provider Boundary

The local implementation uses only disposable/injected rows matching the local
PowerSync Principal, Account and membership table shape. It makes no Postgres
schema, Data API grant or RLS claim. Those server-side obligations belong to a
later hosted identity-bootstrap slice. It uses an injected typed query-specific
readiness observation carrying both completeness and freshness. The current Sync YAML is
illustrative, intentionally untouched, and explicitly not reused or accepted as
safe hosted proof: it selects broad Principal data and auto-subscribes Account
data beyond this local slice. A separate A-004/A-007-gated hosted bootstrap
slice must narrow columns, prove grant/removal and unauthorized local-row
absence, and correct subscription lifecycle before connection.

The local adapter requires the exact Principal row as a bootstrap sentinel and
counts active same-Principal membership evidence before joining Account rows.
A delayed or malformed Principal/Account row therefore produces partial
evidence rather than a false authoritative-empty list. Exact bootstrap
completion and freshness are separate reactive inputs; ready-to-stale-to-ready
must emit without row changes, and a reopened cache starts partial or stale
until current-process evidence arrives. Historical connection-wide sync status
cannot certify this query.

## Planned Verification

- exact environment/Principal binding and cross-scope refusal;
- zero/one/many/equal-name lists and no automatic choice;
- inactive and other-Principal membership exclusion;
- membership-before-Account and malformed-row false-empty prevention;
- independently reactive completeness/freshness, row-independent
  ready-to-stale-to-ready transitions, stale/partial restart initialization and
  content-bound local versions;
- bounded read/readiness failure before cache and exact cached-snapshot
  retention after cache, with no raw error or false authoritative empty;
- poison/access-counting proof that rejected scope rebinding performs no query;
- explicit current-snapshot selection and changed-snapshot refusal;
- encrypted close/reopen and cancellation;
- build-only isolated staging component and both target builds; existing
  staging-root runtime wiring is explicitly not claimed;
- no server-schema, Data API grant or RLS claim in this local-only slice; and
- no hosted Sync claim; authenticated bootstrap/revocation proof belongs to the
  separate gated hosted identity-bootstrap slice.

## Isolation Statement

No hosted Supabase or PowerSync resource is provisioned or contacted. No
Firebase application code, Firebase worktree, source data, migration,
deployment, release or cutover authority is touched. A-003/A-004 remain
proposed.

The later implementation allowlist includes the four owned leaves, synchronized
control artifacts, and the deterministically generated target Xcode project.
The existing staging root is excluded; the staging component compiles but is not
wired into the app at runtime in this slice. No SQL, grant, RLS, Sync
configuration, migration or Data API file is in this slice's implementation
allowlist.

## Independent READY Review

The first independent review returned NO-GO and identified five substantive
gaps: unclaimed pgTAP work, an unclaimed staging-root edit, readiness that did
not react to freshness-only changes, missing before/after-cache failure cases,
and no proof that rejected scope rebinding avoids database access. The corrected
package removes every server/RLS/pgTAP claim, narrows the staging component to
build-only, freezes typed completeness-plus-freshness and restart behavior, and
requires explicit bounded-failure and zero-database-access tests. A second
review caught three stale wording inconsistencies; after correction and
regeneration, final corrected-diff review returned GO with no P0-P3 finding.

## Local READY Gate

- conversion synchronization, check, report and M0 control pass with zero
  errors and only the three established retired-path warnings;
- target environment and generated app/MCP contract checks pass;
- all 11 target MCP tests pass;
- all 358 Swift tests in 69 suites pass;
- deterministic target-project generation and both macOS and generic iOS
  Simulator staging builds pass; and
- `git diff --check` passes.

Initial exact READY commit `a34a51e94e58b1b0b9106204e2b74b09217a31f9`
was correctly rejected by immutable Actions run `33921833216`: the conversion
job found only that the generated M2 residual report was stale, so dependent
target and local-Supabase jobs did not run. No executable behavior existed at
that checkpoint. The residual report is regenerated at 443 mapped / 184
residual / 47 blocker rows, and the complete workflow command set—not the
earlier shorthand subset—must pass locally and on the corrected exact READY
commit before executable work.

Follow-up commit `900fcd673d783c2a5c99d162bcd379dead83ab6a`
contained the corrected residual report but accidentally omitted other
regenerated conversion/audit outputs that remained dirty locally. Its workflow
run `33921970523` was administratively cancelled as soon as that omission was
observed and is not acceptance evidence. The next checkpoint must include the
entire synchronized generated-artifact set and prove a clean checkout.
