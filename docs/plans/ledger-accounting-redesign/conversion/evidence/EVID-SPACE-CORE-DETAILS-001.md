# EVID-SPACE-CORE-DETAILS-001 — Space Core-Details Read Contracts

- Timestamp: 2026-09-02
- Class: ready gate / provider-free single-Space core-details read
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and shipped app remain unchanged
- Claimed target surfaces: `SWIFT-02BF0EA3C433`, `TEST-377B0FDAF4D4`
- Slice dossier:
  `conversion/implementation-slices/space-core-details-read-contracts.json`
- Verification state: ready contract; implementation withheld until exact-ready-
  commit immutable CI passes
- Ready scaffold hashes:
  - `SpaceCoreDetailsData.swift`:
    `d9e4335368aa7d9d7b9a0616f0dbf851f39a58f0ecf9ccef5ef66c0b1fe742b5`
  - `SpaceCoreDetailsDataTests.swift`:
    `e336e5cd42808d3dd5784bacc4ace3e54f3567145538af02ab7b088e240302eb`

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

## Permanent Limits

Ready status proves only that the authority, boundary and tests are internally
traceable. It proves no executable read behavior, physical offline durability,
authorization, synchronization, database policy, migration reconciliation,
app/MCP behavior, hosted resource, production behavior, release or cutover.
