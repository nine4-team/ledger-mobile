# EVID-PROJECT-EXISTING-CLIENT-SELECTION-001 — Project Existing-Client Selection Projection

- Timestamp: 2026-09-02
- Class: verification / provider-free Project existing-Client selection projection
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and released Firebase app remain unchanged
- Claimed target surfaces: `SWIFT-0C8433A6C6F4`, `TEST-8B902DC97729`
- Slice dossier:
  `conversion/implementation-slices/project-existing-client-selection-read-contracts.json`
- Verification state: verified after corrected primary and independent review;
  exact integration checkpoint `9ff6540760548377fd5c4f528974045777619aad`
  passed immutable Actions run `33707305340`
- Ready scaffold hashes:
  - `ProjectExistingClientSelectionData.swift`:
    `184acab06203e860c4f68323a8cd580c23163c0618bfc8a0fddeb9caf9c35f3f`
  - `ProjectExistingClientSelectionDataTests.swift`:
    `8994a2c92f54a54e7881083a1c0f7531e11f8fafe948bd46c8352b9cc7f24273`
- Reviewed implementation hashes:
  - `ProjectExistingClientSelectionData.swift`:
    `fcc321e02472e209791970dbe4c918455dd6d60c7ec5c0ae0dea4f4f30603ca0`
  - `ProjectExistingClientSelectionDataTests.swift`:
    `5c2f4c5325b0a793487615354ae610281a8479c1d33a3e36172f8a7f9f8b4bd9`

## Selection and Scope

After verifying the Client directory, Project setup command and single-Client
core read, a read-only scout proposed the smallest remaining Project-creation
selection boundary: take validated Account-scoped Client directory evidence,
exclude archived Clients, and turn one explicit active ClientID into the
already-verified existing-Client Project setup input.

D-006 and the canonical Client/Project specifications settle stable Client
identity, archived-Client exclusion from new-Project selection and the
existing-versus-new Client setup branches. They do not settle a final picker
layout or automatic preselection policy. This slice therefore contains no UI,
selected/default value, mutation, authorization or provider behavior.

Exactly two target-only comment scaffolds are claimed in the provider-free core
and test roots. No executable behavior or test exists at this checkpoint.

## Independent Adversarial Preflight

Before freeze, the independent reviewer returned NO-GO on two proposed details:

1. A new Account-only Client query port would duplicate the verified
   `ClientProjectDirectoryQuerying.watchClients(accountId:)` source of truth.
   The corrected slice is a pure application projection over
   `ClientListSnapshot`; a production protocol, adapter or second query is
   forbidden.
2. “Zero/one/many never auto-select” would invent final UI behavior not present
   in canonical authority. The corrected structural contract merely contains
   no selected/default Client and requires an explicit caller-supplied active
   ClientID to return `ProjectClientSelectionInput.existing(ClientID)`.

The reviewer then required a further integrity correction: query identity alone
cannot protect a projected active-row payload that omits archived rows. A
distinct canonical evidence fingerprint must bind contract version, AccountID,
the ordered active `ClientSummary` values, source-directory fingerprint,
`sourceDirectoryRowCount`, `visibleRowCountBeforeFiltering`, completeness,
quality, LocalDataVersion and as-of time. Candidate removal, insertion,
reordering, count change or rebinding
therefore cannot decode as unchanged evidence. This is corruption/rebind
detection, not authentication or authorization; a separately constructed
legitimate later snapshot derives new evidence and remains valid.

With those corrections the reviewer returned GO without requiring a product
decision. Root review agrees: the boundary composes existing authority instead
of creating a competing backend abstraction or UI rule.

The reviewer then inspected the actual ready-gate diff and found one additional
P2 integrity-spec gap: the explicit evidence-fingerprint basis omitted
`visibleRowCountBeforeFiltering`, even though that preserved source count cannot
be reconstructed after archived rows are filtered. The dossier now binds that
count explicitly and requires both changed-but-still-structurally-valid count
rejection under the old fingerprint and negative/below-candidate structural
rejection. After regeneration, independent re-review reports no remaining
P0-P3 finding and confirms the diff contains only the two scaffolds, slice
control/evidence entries and expected generated effects.

Independent review of worker candidate `41a2033c` then found a P1
authoritative-empty defect in both implementation and the frozen plan. The
shared list contract permits `visibleRowCountBeforeFiltering` to exceed the
represented source-row count. After filtering archived rows away, an empty
active array plus ready/complete evidence therefore could not prove that an
omitted row was not active. That false `noActiveClient` result could steer a
user toward creating a duplicate Client and incorrect Project relationship.

The candidate is rejected pending correction. The frozen contract now carries
and fingerprint-binds exact `sourceDirectoryRowCount`. `noActiveClient` is
permitted only when ready, complete and source-exhaustive
(`sourceDirectoryRowCount == visibleRowCountBeforeFiltering`); otherwise an
empty active projection remains `directoryIncomplete`. Visible active rows may
still form explicit local selection intent without becoming authorization.

## Ready-Gate Contract

The dossier freezes eight requirements and seven future test obligations:

- filter only active Clients from one validated `ClientListSnapshot`, retaining
  exact relative source order and byte-exact valid display values;
- allow duplicate display names while preserving stable ClientID distinction;
- distinguish available, ready-complete source-exhaustive no-active and
  incomplete/non-exhaustive local states;
- preserve source query fingerprint, source-row count, visible count,
  completeness, quality,
  LocalDataVersion and finite as-of evidence;
- derive distinct query identity and content-bound canonical evidence identity,
  including both source-row and visible-row counts that cannot be reconstructed
  after archived rows are filtered;
- carry no selected/default Client and require one explicit projected active
  ClientID to create exactly the existing-Client setup input;
- refuse Account/fingerprint/row/order/count/completeness/time/encoding rebinds,
  duplicate Client IDs and unknown/archived/cross-snapshot selection; and
- consume no new port and claim no current server authorization from local
  evidence.

Future tests must directly cover exhaustive true-empty and archived-only
ready-complete evidence; non-exhaustive empty/archived-only ready-complete
evidence; ready-incomplete, partial and stale empty evidence; zero/one/many
candidate shapes without a selected/default field; active explicit selection;
same-name identities; padded display text; identical and conflicting duplicate
IDs; inserted, removed and reordered rows; changed but still structurally valid
source-row or visible counts under the old evidence fingerprint plus negative,
below-active and source-above-visible counts;
every fingerprint and scope rebind; canonical restart; a test-only consumer over
the existing directory port; upstream error and cancellation; literal bounded
unique diagnostics; and exact encoded-key allowlists.

## Open Decisions and Exclusions

- O-025 remains open because the slice cannot rename, archive, restore, merge,
  delete or correct a Client or reassign any existing Project.
- The final Project form/picker layout and any convenience preselection remain
  outside this structural boundary.
- Local candidate validity is not authorization. A later authoritative
  CreateProject handler must recheck current membership, Client Account and
  lifecycle.
- A-003/A-004 keep provider choices proposed pending their spike; A-007/A-016
  keep Auth/offline authorization open; A-015 keeps optimistic physical
  projection open.
- There is no Project or Client mutation, physical persistence, schema, handler,
  Data API grant, RLS policy, Sync Stream, app/MCP wiring, source transform,
  hosted resource, production access, release or cutover authorization.

## Ready Verification

The two target paths contain comments only. The complete local ready gate passes:

- conversion sync/check/report — 803 recorded / 788 currently discovered,
  zero errors and only the three established retired-path warnings;
- capability and query controls — current;
- residual register — current at 374 mapped / 167 residual / 44 blockers;
- M0 — pass; M1/M2 — expected evidence/decision blocks at 2/167 with zero
  structural errors;
- `swift test --package-path LedgeriOS` — all existing 211 tests in 48 suites
  pass; neither scaffold adds an executable test;
- target environment and generated app/MCP contract checks — pass;
- XcodeGen output is repeatable at project hash
  `0657194a678ebbeb7d55e322303e2c5d63198f342e090d2f7072525b20ff9f53`
  and staging-scheme hash
  `388303af0f4bd6641d70c669ff3754445ab4f59c1a5310cdfe69336827990ed8`;
- macOS and generic iOS Simulator staging builds — pass;
- `git diff --check` — pass; and
- the Firebase source checkout remains clean on `firebase`.

Exact ready commit `e6d805630c2ba1f366a6ecf1715a8cf0e60a90ee`
passed immutable Actions run `33704608811`: conversion traceability passed and
the isolated target job passed all 211 existing tests, generated contracts and
both staging builds with clean tracked artifacts. `SUBAGENT-WORK-006` is now
registered from that exact base in isolated branch/worktree
`codex/supabase-slice-project-existing-client-selection` /
`/Users/benjaminmackenzie/Dev/ledger_mobile_supabase_project_existing_client_selection`.
The worker owns only the two target paths listed above and cannot edit or
promote canonical conversion controls. Primary every-line review, independent
adversarial review, the complete integration gate and immutable CI on the exact
integration commit remain mandatory.

Passing these ready gates proves only that the frozen authority, coverage and
isolation were coherent before the isolated worker began. It does not prove the
planned projection behavior.

## Implementation Review

`SUBAGENT-WORK-006` produced candidates `de476aed`, `41a2033c`, `c2492452`
and final `d206f542` from the exact ready base. Every candidate changed only the
two registered paths. Root every-line review required direct partial/stale
selection, distinct insertion, both invalid completeness combinations and
non-exhaustive no-active restart coverage.

Independent review rejected `41a2033c` for the P1 authoritative-empty defect
described above. The corrected implementation stores
`sourceDirectoryRowCount`, validates
`activeClients.count <= sourceDirectoryRowCount <= visibleRowCountBeforeFiltering`,
binds both counts into evidence, and requires exact source exhaustiveness before
returning `noActiveClient`. Final root and independent re-review of `d206f542`
found no remaining P0-P3 issue. Root, worker and reviewer focused runs pass all
seven tests; root and worker full package runs pass all 218 tests in 49 suites.
The central integration gate also passes conversion sync/check/report,
capability/query/residual/M0 controls, target environment and generated-contract
checks, repeatable project generation, macOS and generic iOS Simulator staging
builds, clean formatting and an untouched Firebase checkout. Immutable exact-
integration-commit CI passed in immutable run `33707305340`: traceability passed
in 12 seconds and isolated target verification passed in 2 minutes 44 seconds,
including all 218 tests, generated contracts, both staging builds and clean
tracked artifacts.

## Permanent Limits

Verified status proves no physical offline durability, authorization,
synchronization, database policy, migration reconciliation, app/MCP behavior,
hosted resource, production behavior, release or cutover.
