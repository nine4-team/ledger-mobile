# EVID-ACCOUNT-DISCOVERY-SELECTION-001 — Account Discovery and Explicit Selection Contracts

- Timestamp: 2026-09-02
- Class: implementation / provider-free Account discovery and selection intent
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and shipped app remain unchanged
- Claimed target surfaces: `SWIFT-C1B994920894`, `TEST-11AC450D596A`
- Slice dossier:
  `conversion/implementation-slices/account-discovery-and-selection-contracts.json`
- Verification state: verified at exact implementation commit
  `e2972b9c81055fdf936db81afc4bd7e5cd13d0fb`
- Ready scaffold hashes:
  - `AccountDiscoveryAndSelection.swift`:
    `f84b92866a982f2acad887883e27e8e509b0c9923feddbd4d144988fa053d96e`
  - `AccountDiscoveryAndSelectionTests.swift`:
    `75591273d8606cb6055e5011f036a8e063aff71ef48dde64a9ed1d16a37a863d`

## Selection and Scope

The next-slice audit selected Account discovery and explicit workspace-choice
intent because the reviewed identity dossier marks it ready for target-
independent mapping and the canonical product boundary can be stated without
choosing an Auth provider or offline-access lease.

The current Firebase implementation sequentially resolves membership and
Account documents, turns discovery failure into an empty list, writes an
arbitrary selected ID to unencrypted global defaults, and couples selection to
broad provider listeners. Current MCP may choose the first membership or use a
fallback and stores active state in root `mcpUserState`. Those mechanics are
source evidence, not behavior to reproduce.

The bounded target slice owns only visibility-safe, readiness-labeled Account
list values and an explicit local selection intent bound to the exact list the
caller saw. It cannot authenticate, prove current server membership, activate
or clear a workspace, choose an offline lease, persist remembered state, start
or stop streams, touch a queue, access a provider, or wire the app/MCP.

## Product and Source Cross-Reference

The audit cross-referenced:

- `docs/specs/account-discovery-and-workspace-selection.md` as canonical target
  authority for scoped discovery, explicit choice, remembered convenience,
  non-enumerating refusal and the selection-versus-authorization boundary;
- `docs/specs/authentication-offline-access.md` and A-007/A-016 for the still-
  open provider, local-unlock, authority-freshness and revocation policies;
- the reviewed identity/session dossier for zero/one/many discovery, current
  failure collapse, arbitrary selection, listener coupling, MCP first/fallback
  selection and the provider-neutral target contract;
- `03-data-sync-and-offline.md` for identity-bootstrap local rows, readiness and
  the rule that local state is not current server authority;
- `04-backend-ports-and-adapters.md` for `AccountQuerying` and selection as an
  application-shell transition rather than a server active-Account record;
- `08-verification-observability-and-operations.md` for authorized bootstrap,
  switch isolation and revocation test obligations; and
- current `AccountContext`, `AccountDiscoveryTests`, `Account`, MCP account
  tools, auth/context and `mcpUserState` for shipped outcomes and defects.

The canonical spec records only decisions already settled by those sources:
stable Account identity, visibility-safe display, explicit selection,
deterministic remembered ordering, distinct empty/readiness/failure states,
exact scope binding and no selection-as-authorization.

## Why Open Decisions Do Not Block This Slice

- A-007 chooses provider and issuer/subject correlation. This contract begins
  with an already-established stable Principal and carries no provider value.
- A-016 chooses when protected data may be opened offline. A selection intent
  only records choice and cannot activate or unlock data.
- O-023 controls attachment retention. Account summaries omit logo attachment
  identity and bytes completely.
- Membership roles, financial access, invites and Account creation are separate
  read/write capabilities. This snapshot intentionally exposes none of them.
- Physical workspace switch ordering, pending-work disposition, local database
  lifecycle, RLS and Sync authorization remain later spike/provider work.

## Ready-Gate Contract

The dossier freezes eight product/conversion/architecture requirements and five
verification obligations. It requires:

- exact target-environment and stable-Principal scope;
- unique stable Account IDs and nonblank visibility-safe names while allowing
  duplicate names;
- explicit completeness, ready/partial/stale quality, local version, finite
  time and canonical fingerprint evidence;
- deterministic name/ID order with a currently visible remembered ID optionally
  first and no automatic selection even for one Account;
- one explicit selection intent bound to the exact visible snapshot;
- atomic stable refusal for invalid, duplicate, unlisted, rebound, changed or
  tampered evidence without Account enumeration;
- canonical structured restart; and
- one narrow provider-free discovery stream that yields no false snapshot on
  wrong scope or failure.

Postgres, handlers, grants, RLS, Sync Streams, Auth, physical persistence,
workspace activation/switching, Account/member/invite mutations, logo/media,
app/MCP, migration, observability and feature activation are explicit
nonapplicabilities.

## Dependency Evidence

The session-ending verification-document checkpoint is immutable at commit
`41d96d7dd4d935bf6f320e55dcfe277b28ff3c9b`. GitHub Actions run
`33664894237` passed conversion traceability in 10 seconds and the isolated
target environment in 2 minutes 23 seconds, including all 168 then-existing
target tests, graph/generated-contract checks, both staging builds and clean
tracked artifacts.

`EVID-CAPABILITY-IDENTITY-001` and `EVID-M2-IDENTITY-001` provide the reviewed
source/caller/defect map. Verified target-environment, shared list/readiness,
scoped route, operation lifecycle and session-ending contracts supply reusable
technical primitives without authorizing provider behavior by implication.

## Ready-Gate Verification

The two comment-only surfaces are acknowledged through the reviewed identity/
lifecycle batch and are `target_mapped`. The dossier has no blocker; every
requirement is reciprocally covered by domain, offline-restart, offline-
rejection, deterministic port-flow and exact-commit operational obligations.

The complete local ready gate passes:

- conversion sync/check/report and capability/query/residual controls;
- M0, with M1/M2 retaining their expected 2/164 prerequisite blockers and zero
  structural errors;
- all 168 existing target tests in 39 suites while both scaffolds remain
  comment-only;
- target environment and generated app/MCP contract checks;
- macOS and generic iOS Simulator staging builds;
- repeatable XcodeGen output with unchanged
  `0657194a678ebbeb7d55e322303e2c5d63198f342e090d2f7072525b20ff9f53`
  graph hash and no source-project diff; and
- clean diff formatting.

The synchronized ledger records 785 surfaces / 770 discovered, 359 mapped-or-
later target-relevant surfaces, 164 residual surfaces and 43 validated blockers.
Forty slices claim 101 of 523 target-relevant surfaces; 84 are implemented or
later. The bounded provider-free implementation remained prohibited until the
exact ready checkpoint passed immutable CI.

The exact ready commit
`ae16ed4e62ee2abe7ab60f71a26a92824e70fa01` passed immutable GitHub Actions
run `33666363647`: conversion traceability passed in 7 seconds and the isolated
target environment passed in 3 minutes 34 seconds with all 168 then-existing
target tests, graph/generated-contract checks, both staging builds and clean
tracked artifacts. That immutable pass authorized only the frozen provider-free
implementation below.

## Implemented Contract

The bounded implementation now defines:

- `AccountDisplayName` and `AccountSummary`, exposing only a stable Account ID
  and a validated, bounded, visibility-safe display name;
- `AuthorizedAccountListSnapshot`, which binds one deterministic unique Account
  list to an exact target environment, Principal, completeness, readiness,
  local-data version, finite observation time and canonical SHA-256 fingerprint;
- explicit waiting, snapshot and failed-with-cache discovery states without
  collapsing an incomplete or failed read into authoritative emptiness;
- deterministic normalized-name/stable-ID ordering, with a remembered visible
  Account optionally presented first but never selected automatically;
- `WorkspaceSelectionIntent`, bound to the exact snapshot, environment,
  Principal, Account, version and request time the caller selected;
- `AccountSelectionPolicy`, which rejects unlisted, rebound, changed or tampered
  selection evidence through stable non-enumerating diagnostics; and
- one narrow provider-free `AccountQuerying` stream port that cannot authorize
  or activate an Account.

The exact implementation source hashes are:

- `AccountDiscoveryAndSelection.swift`:
  `4fc4c2e008995fd1e317508323d55e72c42a6126b79200be825267f8d51d042f`
- `AccountDiscoveryAndSelectionTests.swift`:
  `ef93c06a416b24ae4a3116cddcfa880ac1273cf18d3c0072ea400410e8229166`

## Local Implementation Verification

All four focused discovery/selection tests and all 172 target tests in 40
suites pass locally. They cover zero/one/many/equal-name Account discovery,
remembered ordering without implicit choice, readiness/empty/failure
distinction, byte-identical restart, malformed/duplicate/scope/version/time/
fingerprint/rebinding refusal, every stable diagnostic code and the exact
provider-free query-port request/stream behavior.

The complete local implementation gate also passes both staging builds, target
isolation/generated contracts, conversion sync/check/report, capability/query/
residual controls, M0, clean diff formatting and repeatable XcodeGen output.
The target project and staging scheme remain exactly
`0657194a678ebbeb7d55e322303e2c5d63198f342e090d2f7072525b20ff9f53`
and `388303af0f4bd6641d70c669ff3754445ab4f59c1a5310cdfe69336827990ed8`;
the source application project is unchanged. M1/M2 retain exactly their
expected 2/164 coverage blockers with zero structural errors.

## Immutable Implementation Verification

Exact implementation commit
`e2972b9c81055fdf936db81afc4bd7e5cd13d0fb` passed immutable GitHub Actions
run `33668715587`. Conversion traceability passed in 8 seconds. The isolated
target environment passed in 3 minutes 8 seconds, including target dependency/
environment validation, generated app/MCP contracts, all 172 target tests in 40
suites, the macOS staging build, the generic iOS Simulator staging build and
clean tracked artifacts. All five dossier obligations therefore pass and both
claimed surfaces are `verified`.

## Permanent Limits

This ready evidence cannot verify or authorize Auth, membership, financial
access, invite or Account creation; current server authorization; offline lease
or unlock; local database/key/remembered-state persistence; physical workspace
switching or queue isolation; logo attachments; Postgres/RLS/PowerSync; app/MCP
integration; Firebase migration; hosted resources; production access; release;
or cutover. The source Firebase application remains unchanged.
