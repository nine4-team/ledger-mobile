# EVID-SPACE-CORE-DETAILS-001 — Space Core-Details Read Contracts

- Timestamp: 2026-09-02
- Class: ready gate / provider-free single-Space core-details read
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and shipped app remain unchanged
- Claimed target surfaces: `SWIFT-02BF0EA3C433`, `TEST-377B0FDAF4D4`
- Slice dossier:
  `conversion/implementation-slices/space-core-details-read-contracts.json`
- Verification state: verified after enhanced review, complete local gates and
  immutable CI on the exact integration checkpoint
- Ready scaffold hashes:
  - `SpaceCoreDetailsData.swift`:
    `d9e4335368aa7d9d7b9a0616f0dbf851f39a58f0ecf9ccef5ef66c0b1fe742b5`
  - `SpaceCoreDetailsDataTests.swift`:
    `e336e5cd42808d3dd5784bacc4ace3e54f3567145538af02ab7b088e240302eb`
- Implemented source hashes:
  - `SpaceCoreDetailsData.swift`:
    `2d02cbd351cce52a163fda48381f6e10eeea953d17af637e24860ce0ca6b7669`
  - `SpaceCoreDetailsDataTests.swift`:
    `92522cb15998005b3729d0c2cf7cf16bd33ef2bcc05fd478debf47ced94c8100`

## Independent Scope Preflight

The primary agent and an independent adversarial reviewer separately read the
canonical Spaces and offline-first specifications, D-023, the reviewed Spaces
capability dossier and the verified Space/shared-list primitives. Both approved
only one provider-free read of an exact Space's core operational details.

The independent review tightened the boundary before delegation:

- `createdAt` and `updatedAt` are exact Space fields, but this slice cannot call
  them server-authored audit provenance, bind an actor, infer immutability or
  impose an unapproved ordering between the timestamps;
- derived completed/total counts from incomplete local checklist evidence must
  remain explicitly non-authoritative;
- archived detail is readable evidence and must not collapse into absence, but
  the slice cannot decide O-037 archive effects on assigned Items;
- checklist-item identity is unique within one checklist, not globally across
  all checklists;
- zero checklists and zero-item checklists are valid and yield exact 0/0 counts,
  while no zero-denominator percentage convention is invented; and
- the public/encoded boundary must omit media, Item/assignment, review,
  template, legacy `Space.isComplete`, accounting, provider and app/MCP fields.

## Frozen Contract and Exclusions

The dossier freezes exact Account/Space request identity, immutable Project-or-
Business-Inventory scope, normalized name/notes, active-or-archived lifecycle,
exact revision and finite timestamps, canonical stable checklist hierarchy,
derived counts, explicit local completeness/readiness/failure, structured
restart, bounded refusal and one narrow query port.

It expressly excludes archive/restore/delete behavior, assigned Items and Space
eligibility, attachments/images/PDFs/markers, review notes, templates, legacy
completion state, Transactions/Invoices/Purchases/occurrences/budget/accounting,
physical persistence, current authorization, Postgres/handlers/grants/RLS,
PowerSync, Auth/provider, SwiftUI/MCP, source migration, hosted resources,
production access, release and cutover. O-023/O-026/O-037 and A-003/A-004/A-007/
A-015/A-016 remain untouched.

## Ready-Gate Obligations

Six obligations require:

- Project and Business Inventory found rows with active and archived lifecycle;
- stable canonical nested identities/order/check state, valid same item ID in
  different checklists, empty hierarchy and exact derived counts;
- ready found, authoritative absence, incomplete, partial, stale, unavailable,
  retryable and required-update truth without enumeration or false absence;
- byte-identical canonical restart;
- bounded rejection of request/row/scope/cardinality/count/time/content/order/
  identity/fingerprint tampering; and
- exact-request port streaming, upstream failure and cancellation behavior.

The two implementation paths contain comments only. The complete local ready
gate passes:

- conversion synchronization/check/report, capability/query/residual freshness
  and M0, with 797 recorded / 782 discovered surfaces, 368 mapped-or-later,
  167 residuals, 44 blockers and only the three documented retired-path
  warnings;
- target isolation and generated app/MCP contracts;
- all 193 existing target tests in 45 suites;
- repeatable XcodeGen output with project hash
  `0657194a678ebbeb7d55e322303e2c5d63198f342e090d2f7072525b20ff9f53`
  and scheme hash
  `388303af0f4bd6641d70c669ff3754445ab4f59c1a5310cdfe69336827990ed8`;
- macOS and generic iOS Simulator staging builds; and
- clean formatting and no source application-project change.

Immutable CI on the exact ready commit was the final prerequisite before a
worker could replace the scaffolds.

Exact ready commit
`8849344dc66d71d9dd9b9ba589a76deb007f3172` passed immutable Actions run
`33693232878`: conversion traceability passed in 12 seconds and the isolated
target environment passed in 2 minutes 32 seconds with all 193 existing tests,
generated contracts, both staging builds and clean tracked artifacts. The
ready gate therefore authorizes only the frozen two-path candidate
implementation in the isolated worker worktree.

## Enhanced Worker Review and Implementation

The worker started from exact green ready commit `8849344d` in the isolated
`codex/supabase-slice-space-core-details` branch/worktree and changed exactly
the two allowlisted Swift paths. It made no documentation, control, generated,
project/package, MCP, Firebase, provider, hosted-resource, production or
integration-branch change.

The candidate was not accepted from its own report. Primary every-line review
found three concrete test-quality gaps: missing direct normalization-refusal
cases for Space notes, checklist names and checklist-item text; no independent
proof that both AccountID and SpaceID alter the request fingerprint; and a
fixture port that did not itself reject a mismatched request. Candidate
`19794b4107ef8f0a0ac8a773bc6d767a508a935b` corrected all three. An independent
read-only adversarial review then found one P3 gap: the diagnostic test did not
pin every public failure case to an exact unique stable code. Test-only commit
`1920389d28a71fff3b3233bef2971fe9525bc6e3` corrected it. Primary and independent
rechecks confirmed that all four findings are resolved and that no P0-P3
finding remains.

The bounded implementation defines a fingerprinted exact Account/Space
request, validated Project-or-Business-Inventory core snapshot, canonical
ordered checklist hierarchy with derived counts, explicit local
readiness/completeness/absence evidence, bounded update/failure states and one
narrow request-exact watch port. Tests cover active and archived rows, empty
and populated checklists, valid repeated item IDs across different checklists,
ready/incomplete/partial/stale found and empty states, authoritative absence,
canonical restart, scope/cardinality/count/time/content/order/fingerprint
tampering, non-enumerating failures, port-side request rejection, upstream
failure, cancellation, exact stable diagnostics and forbidden encoded fields.

The worker and both reviewers passed all six focused tests. The worker, primary
agent and independent reviewer passed all 199 target tests in 46 suites as
applicable. The three candidate commits were integrated as `72b24afa`,
`503b3839` and `05509124`. The complete integration gate then passed conversion
sync/check/report, capability/query/residual freshness and M0; target isolation
and generated app/MCP contracts; all 199 tests; repeatable XcodeGen output with
project hash
`0657194a678ebbeb7d55e322303e2c5d63198f342e090d2f7072525b20ff9f53`
and scheme hash
`388303af0f4bd6641d70c669ff3754445ab4f59c1a5310cdfe69336827990ed8`;
macOS and generic iOS Simulator staging builds; and clean formatting/artifacts.
Exact integration checkpoint
`d5afa699ce09c105a82b187f9953e06a09ac2b10` then passed immutable Actions run
`33695588031`: conversion traceability passed in 10 seconds and the isolated
target environment passed in 3 minutes 16 seconds with all 199 tests, generated
contracts, both staging builds and clean tracked artifacts. The slice and its
two surfaces are therefore verified. The clean worker worktree may now be
removed while its branch and candidate commits remain recoverable.

## Permanent Limits

Implemented status proves only the provider-free executable contract and
synthetic evidence described above. It proves no physical offline durability,
authorization, synchronization, database policy, migration reconciliation,
app/MCP behavior, hosted resource, production behavior, release or cutover.
