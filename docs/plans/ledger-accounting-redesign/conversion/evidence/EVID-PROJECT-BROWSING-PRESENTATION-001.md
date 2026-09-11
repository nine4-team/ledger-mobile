# EVID-PROJECT-BROWSING-PRESENTATION-001 — Project Browsing Presentation

- Timestamp: 2026-09-02
- Class: implementation / provider-free Project directory-selection and detail-header presentation
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on `firebase`; the source worktree and released Firebase app remain unchanged
- Claimed target surfaces: `SWIFT-6075C2D24BAD`, `SWIFT-FC9E3C33FECA`, `TEST-02013D984E64`, `TEST-8CB70D14D5BC`
- Slice dossier: `conversion/implementation-slices/project-browsing-presentation-contracts.json`
- Verification state: verified at exact integration checkpoint `717a0eb89099676bd4c09d6b0665dd83ab9739d8` and immutable Actions run `33723154735`

## Selection and Scope

The delegation-economics audit replaced repeated micro-slices with coherent,
independently testable outcomes. This four-path slice covers one user flow:
locally available Project directory core rows, evidence-bound selection, exact
`ProjectCoreDetailsRequest` derivation and the matching local detail header.

It composes the verified `ClientProjectDirectory`, `ProjectCoreDetailsData` and
shared local-read truth. It does not create a second query port, route registry,
authorization model, Project workspace or provider contract.

## Preflight Corrections

The first scout recommendation—`CreateSpaceFromTemplate`—was invalid because
it missed an explicit earlier rejection. No authority has since resolved
O-026, Space naming, fresh nested identity allocation, atomicity, template
provenance, scope/staleness or customization timing. That candidate was
withdrawn without implementation.

Independent adversarial review then rejected three parts of the Project
browsing proposal before freeze:

1. target case-insensitive sorting and its Unicode/locale comparator were not
   canonical target authority, so this slice preserves exact upstream order;
2. fixed tabs were current-system mechanics outside the target requirements and
   were removed; and
3. no canonical Project route-kind or Principal/workspace activation evidence
   exists in the Account-only directory read, so selection derives only the
   verified detail request and never constructs `ScopedRoute`.

The review also required strict Project-lifecycle filtering, visibility for an
active Project whose Client is archived, source-exhaustive empty proof, narrow
`CoreRow`/`DetailHeader` naming, content-bound evidence and explicit detail
failure/readiness behavior. Actual-diff review then caught and corrected an
unrelated D-023 citation, required exact Client-lifecycle authority and froze
request derivation behind validation against the current presentation snapshot.

## Frozen Boundary

- `ProjectDirectorySegment`: active or archived only.
- `ProjectDirectoryCoreRow`: exact Project/Client identity, current names and
  both lifecycle values; never hero/budget/action/route data.
- `ProjectDirectoryPresentationProjector`: validated snapshot projection,
  Project-lifecycle filtering, upstream-order preservation, explicit quality,
  source completeness/exhaustiveness and canonical evidence fingerprint.
- `ProjectBrowsingSelection`: exact represented-row and evidence binding; its
  only request-producing call validates the current presentation snapshot
  before deriving `ProjectCoreDetailsRequest`.
- `ProjectDetailHeaderPresentationProjector`: request-validated waiting, found,
  authoritative-absence and stable failure projection over the verified detail
  update contract.

Canonical restart and adversarial tests bind every source and projected field.
Ready-complete-exhaustive evidence alone can establish an empty segment or
missing detail. Partial/stale represented evidence stays visible without
becoming authorization.

## Open Decisions and Exclusions

O-023/O-024/O-025 and A-003/A-004/A-007/A-015/A-016 remain outside. The slice
contains no full Project Card, hero media, budget preview/pins, sorting/search,
tabs/workspace children, navigation/route, create/edit/archive action,
authorization, physical persistence, app SwiftUI wiring, MCP, Postgres, Data
API, RLS, Sync Stream, provider, migration, hosted resource, production access,
release or cutover behavior.

## Ready Verification

The four target paths contain comments only. Their frozen SHA-256 hashes are:

- `ProjectDirectoryPresentation.swift` — `29603f79b563532d6f038b38f80eb4b8b62e1fdff385c556533721ff288a6c02`;
- `ProjectDetailHeaderPresentation.swift` — `29603f79b563532d6f038b38f80eb4b8b62e1fdff385c556533721ff288a6c02`;
- `ProjectDirectoryPresentationTests.swift` — `d27c45ab432f1c7d7bddf1dc8cfe17000879217b16267777f51a7d9064d10caa`; and
- `ProjectDetailHeaderPresentationTests.swift` — `d27c45ab432f1c7d7bddf1dc8cfe17000879217b16267777f51a7d9064d10caa`.

The complete local ready gate passed with 809 recorded / 794 discovered
surfaces, zero errors, the three established retired-path warnings, 380 mapped
/ 167 residual / 44 blockers, M0, all 224 existing tests in 50 suites,
generated contracts, two identical XcodeGen outputs, macOS and generic iOS
Simulator staging builds and clean diff formatting. The stable generated
project/scheme hashes remain
`0657194a678ebbeb7d55e322303e2c5d63198f342e090d2f7072525b20ff9f53`
and `388303af0f4bd6641d70c669ff3754445ab4f59c1a5310cdfe69336827990ed8`.
Independent correction re-review returned GO with no remaining P0-P3 issue or
overclaim. Exact ready commit
`459a58123ac7241984ddee6d559e33f4bca931d4` passed immutable Actions run
`33720134399`: conversion traceability and the complete isolated-target job both
passed. `SUBAGENT-WORK-008` is restricted to the four frozen leaf paths in the
isolated `codex/supabase-slice-project-browsing` worktree.

## Implementation and Review

Worker candidate `964dbabcfc5efe3946744c41020a652f03cf0165`
changed only the four registered paths and passed all tests, but primary and
independent review rejected it:

- P1: an encoded selection could replace Project B with the complete valid row
  for sibling Project A in the same directory and still derive A's request,
  because only directory evidence—not the chosen row—was fingerprinted; and
- P2: the public output was named `ProjectDirectoryPresentation`, diverging
  from the frozen `ProjectDirectoryPresentationSnapshot` manifest surface.

Corrected candidate `73f94525e3fef8c46a6243ff12c0fd6d02f89e6c`
adds a canonical selection fingerprint over contract version, Account, segment,
the exact six-field row and directory evidence. Decode recomputes it, a direct
sibling-row substitution test fails before any request exists, and
`detailRequest(validating:)` still requires exact current snapshot evidence.
The public type now matches the manifest. Final primary every-line and
independent adversarial review found no remaining P0-P3 issue.

The implemented SHA-256 hashes are:

- `ProjectDirectoryPresentation.swift` — `bc6545189e12322b35c98180b0f35b0fea275c2b7dc4ab616679569340b7083e`;
- `ProjectDetailHeaderPresentation.swift` — `23df5419080383f476b1f0a4990316f7ea904e6d858bdd26a0e2d1a4c861e936`;
- `ProjectDirectoryPresentationTests.swift` — `4b8b327e899e192d0a3313fc47c978d4961c2d2cc4eda93cc15621ebbee7ec6e`; and
- `ProjectDetailHeaderPresentationTests.swift` — `f3ecfae520965a05a9996871450a170162405046deba4c84ca9bb27cba70db8c`.

The worker, primary agent and final reviewer passed four directory plus three
detail-header focused tests. Worker and primary full suites pass all 231 tests
in 52 suites. The central local gate also passes conversion sync/check/report,
capability/query/residual controls, M0, target isolation/generated contracts,
two identical XcodeGen outputs, both staging builds and clean formatting. The
Firebase checkout remains clean at `fe018501`.

Exact integration checkpoint
`717a0eb89099676bd4c09d6b0665dd83ab9739d8` passed immutable Actions run
`33723154735`: both Conversion state and traceability and Isolated target
environment completed successfully on the reviewed, synchronized
implementation SHA. `PBROWSE-TEST-007` therefore passes and the four claimed
surfaces are verified.

## Permanent Limits

Implementation proves only deterministic provider-free presentation and
structured restart/refusal over already-validated local evidence. It does not
prove physical offline durability,
authorization, database policy, synchronization, migration reconciliation,
app/MCP behavior, hosted resources, production behavior, release or cutover.
