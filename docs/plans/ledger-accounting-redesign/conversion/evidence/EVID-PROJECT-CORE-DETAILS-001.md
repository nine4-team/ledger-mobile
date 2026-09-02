# EVID-PROJECT-CORE-DETAILS-001 — Project Core-Details Read Contracts

- Timestamp: 2026-09-02
- Class: ready gate / provider-free single-Project core-record read
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and shipped app remain unchanged
- Claimed target surfaces: `SWIFT-4C4690368BEC`, `TEST-5F24EA7C310A`
- Slice dossier:
  `conversion/implementation-slices/project-core-details-read-contracts.json`
- Verification state: ready contract; complete local ready gate passed and
  implementation remains withheld until immutable CI passes on the exact ready
  commit
- Ready scaffold hashes:
  - `ProjectCoreDetailsData.swift`:
    `cc13b8b394e52067dc66fd08e0700ab200645811b6c3249bf89ec2dcf504f68e`
  - `ProjectCoreDetailsDataTests.swift`:
    `f0947a1bca6060d39a05255fa442830f707851d944c08945d6d71f11d3ed7c62`

## Independent Scope Preflight

The primary agent, a read-only scout and an independent adversarial reviewer
separately read the canonical Projects and Client-identity specifications,
D-006, the redesign architecture and the verified Project directory/details-
update/archive dependencies. All approved only a single Project's core record,
not a complete workspace.

The independent review tightened the boundary before implementation:

- D-006 establishes stable Account/Project/Client identity but does not itself
  authorize revision semantics;
- revision is included only as the exact locally observed
  `ExpectedProjectRevision` required by already-verified conflict-aware Project
  commands, remains distinct from `LocalDataVersion`, and cannot be promoted to
  current server authority by incomplete, partial or stale evidence;
- reused `ProjectSummary` must be wrapped with explicit
  `ProjectDescriptionReplacement` canonicality validation because the summary
  itself accepts raw optional strings;
- an archived Project remains found, and an active Project with an archived
  Client relationship remains valid historical/current relationship evidence;
- authoritative absence requires ready, complete, zero-row evidence; and
- the slice cannot claim any current Firebase/app/MCP surface converted or call
  itself the complete `ProjectWorkspaceSnapshot`.

## Frozen Contract and Exclusions

The dossier freezes exact Account/Project request identity, verified
ProjectSummary identity/Client relationship/current display/lifecycle,
canonical optional description, exact locally observed Project revision,
at-most-one local cardinality, explicit readiness/completeness/absence/failure,
structured restart, bounded refusal and one narrow query port.

It expressly excludes Project children, Item/Transaction/Space/note/category/
preference/Invoice/budget/history/report evidence, media, action capabilities,
rename/archive/delete/reassignment or other mutation, physical persistence,
current authorization, Postgres/handlers/grants/RLS, PowerSync, Auth/provider,
SwiftUI/MCP, source migration, hosted resources, production access, release and
cutover. O-023/O-024/O-025 and A-003/A-004/A-007/A-015/A-016 remain untouched.

## Ready-Gate Obligations

Six obligations require:

- active and archived rows with exact Account/Project/Client relationship,
  nil/canonical description, exact revision and an active Project/archived
  Client fixture;
- independent AccountID and ProjectID fingerprint binding;
- ready found/authoritative absence and incomplete/partial/stale found/empty
  truth with byte-identical canonical restart and no revision-authority upgrade;
- bounded rejection of request/row/relationship/description/revision/
  cardinality/count/time/completeness/fingerprint tampering with exact unique
  stable diagnostics;
- non-enumerating unavailable and distinct retryable/required-update states;
  and
- port-side exact-request validation visible to a raw consumer, upstream
  failure, cancellation and encoded exclusion proof.

The two implementation paths contain comments only. The complete local ready
gate passes:

- conversion sync/check/report, capability/query/residual freshness and M0,
  with 799 recorded / 784 discovered surfaces, 370 mapped-or-later, 167
  residuals, 44 blockers and only the three documented retired-path warnings;
- target isolation and generated app/MCP contracts;
- all 199 existing target tests in 46 suites;
- repeatable XcodeGen output with project hash
  `0657194a678ebbeb7d55e322303e2c5d63198f342e090d2f7072525b20ff9f53`
  and scheme hash
  `388303af0f4bd6641d70c669ff3754445ab4f59c1a5310cdfe69336827990ed8`;
- macOS and generic iOS Simulator staging builds; and
- clean formatting and no source application-project change.

Immutable CI on the exact ready checkpoint remains the final prerequisite
before an isolated worker may replace the scaffolds.

## Permanent Limits

Ready status proves only that the authority, boundary and tests are internally
traceable. It proves no executable read behavior, physical offline durability,
authorization, synchronization, database policy, migration reconciliation,
app/MCP behavior, hosted resource, production behavior, release or cutover.
