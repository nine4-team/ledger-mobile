# EVID-PROJECT-BROWSING-PRESENTATION-001 — Project Browsing Presentation

- Timestamp: 2026-09-02
- Class: ready gate / provider-free Project directory-selection and detail-header presentation
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on `firebase`; the source worktree and released Firebase app remain unchanged
- Claimed target surfaces: `SWIFT-6075C2D24BAD`, `SWIFT-FC9E3C33FECA`, `TEST-02013D984E64`, `TEST-8CB70D14D5BC`
- Slice dossier: `conversion/implementation-slices/project-browsing-presentation-contracts.json`
- Verification state: ready only; executable implementation and tests are absent

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
overclaim. Immutable CI on the exact ready commit remains mandatory before a
worker begins.

## Permanent Limits

Ready status proves no executable presentation, physical offline durability,
authorization, database policy, synchronization, migration reconciliation,
app/MCP behavior, hosted resource, production behavior, release or cutover.
