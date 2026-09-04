# EVID-SOURCE-QUERY-RECONCILIATION-001 — Source Query Reconciliation Control

- Timestamp: 2026-09-04
- Class: draft technical-control design
- Draft baseline: `76b2ff45ba4fffe68097919c32ec7b4fec48047c` on
  `codex/supabase-powersync-implementation`
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and shipped app remain unchanged
- Claimed target surfaces: `CONFIG-A8BD153106B8`,
  `CONFIG-40F01696B8A6`
- Slice dossier:
  `conversion/implementation-slices/source-query-reconciliation-control.json`
- Production reads or mutations: none
- Verification state: immutable DRAFT checkpoint `570f54a50405376ee4b642f1abc11ea04eb0a4bb`
  passed GitHub Actions run `33861320397`, evidence-sync commit
  `b4d948e41f9ca6d5ea50da0ba9d8db6504ea06ae` passed run `33861762639`, and
  first scaled-population checkpoint `3504b473e16fc40b260652c001fdd6b903b81e40`
  passed run `33862965822`; all 386 QUERY IDs are human-reviewed and assigned
  exactly once; all 386 rows now carry 584 explicit outcomes. The 375-row
  population plus retirement hardening passed bounded independent review. A
  second reviewer re-derived all 386 occurrence/owner hashes and validated all
  584 outcome bindings; its one O-041 scope/cursor finding is corrected. A
  separate adversarial review found control-model gaps; the corrected lifecycle,
  retention, retirement-authority, evidence-binding, compatibility-scope and
  conflict-schema model passed bounded corrected-model re-review with no P0-P3
  finding

## Draft Outcome

The repository now contains a draft topology for reconciling every occurrence
in the frozen current-source query catalog. One aggregate registry binds the
full source-query artifact, its source digest and the full verified target
logical-authority artifact. Conversion-manifest references are bound per row
through stable selected projections rather than a volatile full-manifest hash.
Ten capability-sized batches contain a human-reviewed, disjoint and exhaustive
assignment of all 386 QUERY IDs. Row population is now complete at 386 rows and
584 canonical outcomes. The first 375 rows and retirement hardening received
root plus bounded independent review; findings corrected overbroad blockers,
invalid target query mappings, and retirement authority that could otherwise
bypass an unresolved source-owner blocker. Independent completion review then
re-derived every occurrence/owner hash and checked all 584 canonical outcomes.
The final 11 rows make six production-read evidence dependencies and eight
product-authority dependencies explicit, with five rows correctly carrying
both. Adversarial control review subsequently identified model-level weaknesses
ordinary row validation did not expose. Those are corrected in DRAFT, and two
bounded corrected-model reviews independently returned GO with no P0-P3
finding. The generator and test files remain comment-only; immutable complete-
DRAFT evidence and the exact READY freeze remain required before READY.

The original DRAFT checkpoint established semantic batch ownership without
choosing query outcomes. The current pilot adds reviewed outcomes but does not
prove reconciliation completeness, authorize implementation or create generated
reconciliation output. I inspected each frozen occurrence's
path, symbol, operation and complete expression and assigned the occurrence to
the capability that must review its meaning. Mixed files, notably the Firebase
function entry point, were split occurrence by occurrence rather than assigned
as a file. No subsystem/path/symbol/expression rule produced the partition.

## Reviewed Row-Population Status

The bounded subagent-author/root-review/independent-review process was first
proved on Spaces/review and media, then scaled across the remaining capability
batches. Current reviewed counts are:

| Batch | Rows | Outcomes | Remaining QUERY IDs |
|---|---:|---:|---|
| Identity/lifecycle | 29/29 | 50 | none |
| Projects/Clients/reference | 10/10 | 16 | none |
| Inventory/Transactions/provenance | 123/123 | 126 | none |
| Invoicing/collection/budget | 35/35 | 40 | none |
| Item creation/accounting Link | 18/18 | 19 | none |
| Media lifecycle | 3/3 | 6 | none |
| Spaces/review | 8/8 | 12 | none |
| Reporting/search/export | 13/13 | 18 | none |
| Source migration/audit/repair/profile | 129/129 | 258 | none |
| Platform/backend/control | 18/18 | 39 | none |

The final 11 rows do not manufacture resolution. Six use `evidence_blocked`
against E-001/E-002 and the exact selected owner's matching blocker; eight use
`authority_blocked` against O-023/O-038/O-040/O-041, with five rows carrying
both independent blocker types. The two BatchWriting reads remain `source_only`
for `current_source_compatibility` through verified cutover reconciliation, then
retire only their Firebase mechanism after that reconciliation under A-017. No
row claims a production read, resolved product decision or physical target
implementation.

Independent reviews already caused substantive corrections: the O-038 planning
filters were removed from `ListTransactionsQuery`; O-026, O-035 and O-040 were
prevented from authorizing unrelated semantics; O-041 now uses heterogeneous
event cursors and distinguishes Inventory/1584 ownership from Project context;
and behavior retirements now use only four independently extracted,
content-hashed authority projections. Manifest disposition can no longer
authorize its own retirement.

The current draft hashes are:

- generator scaffold:
  `8a87ea132249c0008efea0793d592c6c0ff51c59465a7f808f13f1ba49ce182c`;
- test scaffold:
  `2093c906b75cc1dd507d62eda0e752a1df8ffae9bafbcff07682e2d7329f1a60`;
- aggregate registry:
  `550e4e023ef314f99787b56d070b5d192b5d6bad3e9955c61106b6a305ccf48b`;
- draft dossier:
  `51b3b244e53cdcbd0e3c61effbff80fec1ebc87070aea568da4dbab59103a210`;
- product-authority crosswalk:
  `92dbdf08b4aa4fa875817c974475eb92af95066b0594a022d9d44d29cf29a7d4`;
- conversion discoverer:
  `8b1cc1ea52cfd864bebbdf7f77888c108147b205a6814838e9a7f639a9702cdd`;
  and
- current-query extractor:
  `2eb8feed057ecdae250f51714dd38c4fee197726c36e30322d43d26853446efd`.

## Corrected Source Artifact Evidence

The source-query artifact has contained 170 inspected candidate files, 74 files
with recognized occurrences and 386 occurrences since its original committed
checkpoint `3e1d435b`. `EVID-QUERY-001` and two historical summaries in
`execution-state.md` incorrectly said 169 candidates. The generated artifacts
were not changed; their committed and current hashes are:

- JSON: `2a43de6e59844d081237c8d9731846662e0862190823ea854c2238256b0a6a14`;
- Markdown: `970b84d56837b78958d78003122ec86398e0ccd1928160b14c746fd6eb27ea41`;
- source digest:
  `87a3c1deb568f3e5a5bd35dc316dff38eccaf4fb83e8ecc02c61c77887150da4`.

This is an evidence-text correction, not query extraction or source drift.

## Frozen Draft Row and Outcome Model

Every eventual batch row owns exactly one `QUERY-*` ID and contains only:

- `queryId`;
- `expectedOccurrenceHash`, defined as lowercase SHA-256 over UTF-8
  `source-query-occurrence-v1\0` followed by recursively canonicalized minified
  JSON of the complete generated occurrence object;
- `sourceOwnerSurfaceId`, which must identify exactly one conversion-manifest
  surface selected by a human reviewer;
- `sourceRef`, copied exactly from that surface's `sourceRefs` and required to
  have a path equal to the occurrence `sourcePath`;
- `expectedSourceOwnerHash`, lowercase SHA-256 over UTF-8
  `source-query-owner-projection-v1\0` plus canonical minified JSON of
  `{surfaceId,disposition,sourceRef}`; and
- `outcomes`, a nonempty duplicate-free canonical set.

The source artifact's QUERY identity is re-derived, not trusted: `QUERY-` plus
the uppercase first 12 hexadecimal characters of SHA-256 over UTF-8
`${sourcePath}:${line}:${operation}`. Any mismatch fails closed.

The machine binds the selected source owner/reference; it never infers owner
from path or source mechanics. Registry, ten batches and slice have one exact
closed lifecycle. Each batch also has exact `assignedQueryIds`; their pairwise-
disjoint union must equal all 386 frozen IDs. Only synchronized DRAFT authoring
permits `rows` to be a subset of assignments. READY, implemented and verified
require exact equality. Both ID arrays sort by ascending bytes.

Outcome objects sort by their recursively canonicalized minified JSON bytes.
They may be one-to-many because one source read can support more than one
independently authorized target or lifecycle outcome. The only categories are:

1. `verified_target_query_port` — exact `tqueryId`, `taccessId` and
   `expectedMappingHash` from a non-decision-blocked row in the bound verified
   target logical-authority artifact;
2. `approved_future_target_query` — exact manifest target surface, exact
   `target.surfaces` member and exact canonical target mapping hash, with status
   restricted to `target_mapped`, `implemented`, `verified`, `rehearsed` or
   `cutover_ready`;
3. `approved_target_nonquery_surface` — the same exact manifest binding for an
   approved command, handler, migration or other nonquery owner;
4. `source_only` — the row's same exact `sourceOwnerSurfaceId` and `sourceRef`,
   a manifest `source_only` disposition, bounded purpose/retention gate and
   exact authority;
5. `retired` — explicit behavior/mechanism scope, timing gate and exact
   retirement authority;
6. `authority_blocked` — one frozen `blockedScope`, nonempty unique named
   blocker IDs, and exact typed `{id,kind,path,section}` entries present in both
   the batch allowlist and registry authority table. Product O IDs point to
   `decision-log.md` section `Open Product Decisions`; architecture A IDs point
   to their exact `architecture-decisions.md` headings. O-021 and A-003/A-004
   are forbidden; and
7. `evidence_blocked` — one evidence scope plus nonempty E IDs, exact registry
   evidence entries and explicit selected bindings over the complete
   QUERY-owner/ref/hash/blocker tuple. Each binding has a domain-separated
   hash, appears in the batch allowlist and matches the selected manifest
   owner's exact blocker. This records required evidence without claiming that
   it exists or authorizing a production read.

Authority-blocked cannot launder a blocker from unrelated authority. A
`target_query_contract` outcome additionally binds the exact TQUERY/TACCESS/
mappingHash row, and every blocker must occur in the byte-sorted unique union
of `blockerIds` found only under `logicalAxes` entries and `unresolvedAxes`
entries whose state is exactly `decision_blocked`. Missing or malformed nested
arrays fail closed; prose is never scanned. A `target_nonquery_contract`
outcome additionally binds the exact target manifest surface/member/mapping
hash and every blocker must occur in that same surface's `blockers`. For
`source_disposition` and `retirement`, every blocker must occur in the exact
row-selected source-owner manifest surface's `blockers`.

For future/nonquery outcomes, `expectedTargetMappingHash` is lowercase SHA-256
over UTF-8 `source-query-target-mapping-v1\0` plus recursively canonicalized
minified JSON of `{surfaceId,disposition,target}` from the conversion manifest.
The selected `targetSurface` must equal one exact member of `target.surfaces`.
Status is validated separately and is deliberately absent from this stable
mapping hash. `blocked` and `retired` status and `retire`/`source_only` target
dispositions are rejected for future/nonquery target outcomes.

Outcome category order is exactly verified target query, future target query,
target nonquery, source-only, retired, authority-blocked, then evidence-blocked.
Within a category, recursively canonicalized minified JSON bytes determine
order. The dossier freezes identity fields and rejects duplicate identities.

Source-only purpose is exactly one of `migration`, `audit`, `repair`,
`profiling`, or `current_source_compatibility`; retention is one of
`through_migration_rehearsal`,
`through_verified_cutover_reconciliation`, or
`through_post_cutover_audit_signoff`. `current_source_compatibility` is valid
only for the two exact BatchWriting QUERY/owner/ref/hash bindings frozen in both
the registry and dossier. Every source-only outcome carries the exact
content-hashed A-017 lifecycle-authority binding rather than a bare path/heading.

Retirement scope is exactly `source_query_mechanism_only` or
`source_behavior`. One ordered milestone model requires mechanism retirement
strictly after every same-row source-only retain-through obligation. Thus 60
reconciliation-retained rows use `after_verified_cutover_reconciliation`, 42
post-audit rows use `after_post_cutover_audit_signoff`, and only the 35 rows
whose source obligation ends at migration rehearsal may retain
`after_verified_target_cutover`. Source-only is a retention obligation and
never counts as target replacement or present retirement. Every mechanism-
retirement outcome carries the same independently re-derived content-hashed
A-017 authority.

Behavior retirement uses `at_verified_target_cutover` and an exact
`retirementAuthorityId` plus domain-separated projection hash. The four
allowlisted authorities are two unique canonical target headings, confirmed
D-025's unique table row, and architecture decision A-017's unique heading.
Their bounded content is independently re-extracted and hashed; arbitrary or
stale headings/decisions and owner-manifest self-authorization reject.

An exhaustive symmetric matrix normalizes every outcome category, evaluates
every unordered pair through exact allow/deny/conditional values, and defines
named gate/identity predicates plus cardinalities. In particular, behavior
retirement conflicts with target/source preservation and any unresolved
evidence; any retirement conflicts with an unresolved retirement outcome;
source retention conflicts with an unresolved source disposition; and a target
block conflicts only with the exact target identity it blocks.

The registry freezes typed authority for A-007 target authentication, A-010
provider-independent principals, A-015 complex-command optimistic projection
and A-016 offline-access lease, plus O-002 through O-041 except UI-only O-021.
Each batch carries only the byte-sorted subset semantically relevant to its
assigned capability. An authority-blocked row may use only the intersection of
that batch allowlist and registry table.

No outcome is inferred from subsystem, source path, symbol, operation,
expression or naming. The aggregate checker will validate structure and exact
bindings only. Human capability-owner review decides meaning.

## Global Physical Boundary

A-003 (`architecture-decisions.md`, `A-003 — Supabase Postgres as Target
Authority`) and A-004 (`A-004 — PowerSync as Target Local Data Plane`) remain
global proposed architecture decisions. They are not valid per-row outcomes or
blockers. The registry, batches and future generated
artifact contain no physical table, key, index, SQL, query plan, RLS, Sync
Stream, SQLite, provider or hosted implementation field. Closed schemas must
reject such additions.

## Batch Topology

The ten draft batches are identity/lifecycle (29 assigned IDs);
Projects/Clients/reference data (10);
Inventory/Transactions/provenance; Invoicing/collection/budget; Item creation
and accounting Link; media lifecycle; Spaces/review; reporting/search/export;
source migration/audit/repair/profile; and platform/backend/control. Their exact
assignment counts are respectively 29, 10, 123, 35, 18, 3, 8, 13, 129 and 18.

| Batch | Assigned | Human-reviewed ownership boundary |
|---|---:|---|
| Identity/lifecycle | 29 | Account membership, invite, OAuth/user-state, quota and account-discovery reads |
| Projects/Clients/reference | 10 | Project directory/preferences/notes and vendor/default-reference reads |
| Inventory/Transactions/provenance | 123 | Item, Transaction, inventory movement, purchase-intent, lineage, correction and deletion-dependency reads |
| Invoicing/collection/budget | 35 | Invoice/settlement, project financial summary, fee, budget-category and budget-contribution reads |
| Item creation/accounting Link | 18 | Proto/quick-draft capture and Link prerequisite reads |
| Media lifecycle | 3 | Runtime upload-queue evidence and storage-emulator seed reads |
| Spaces/review | 8 | Space detail/list and Space-scoped Item reads |
| Reporting/search/export | 13 | MCP resource enumeration, analytics and composite-search reads |
| Source migration/audit/repair/profile | 129 | Explicit source conversion, repair, audit, export and profiling reads retained for migration review |
| Platform/backend/control | 18 | Generic repository/batch/query utilities, backend health and Firebase test-surface reads |

The exact registry-order counts are 29, 10, 123, 35, 18, 3, 8, 13, 129 and 18.
Batch assignment is itself reviewed semantic ownership. A file, subsystem or
symbol may contribute rows to different capability batches. Registry
path/batch-ID/owner objects exactly equal the dossier's ten frozen metadata
entries. Exact directory contents are those ten ordered batch filenames plus
`_template.json`; only that exact template filename is excluded by the future
validator. No other underscore, file, directory or symlink receives implicit
exclusion. All nested objects are closed-schema and every input is a repository-
contained regular non-symlink file.

## Lifecycle Boundary

DRAFT completion changes only the exact 40-path allowlist recorded in the
dossier relative to `3504b473e16fc40b260652c001fdd6b903b81e40`, including
the product-authority crosswalk addition that grants this technical-control
batch the architecture-decisions authority directly. The two
stable CONFIG owners are `target_mapped` with empty blockers while the slice
remains DRAFT. Corrected-model independent review is complete. READY still
requires synchronized registry/batch/slice lifecycle, all 386 rows and
synchronized immutable hashes. READY is
classification completeness only: it may report unresolved authority/evidence
outcomes and grants no implementation, migration, source-retirement,
production, or cutover authority. The generated artifact must expose exact
unresolved counts and downstream promotion/cutover consumers must reject
applicable nonzero counts. Implementation may then replace only the two
comment scaffolds, add one generated JSON artifact, add exact package commands
and an Ubuntu conversion-control gate before target Swift work, and synchronize
the same control metadata. Promotion records immutable CI and human review.

The current source and target generated query artifacts, target registry, all
Swift query owners, package/workflow, schema, RLS, Sync, provider, hosted and
production systems remain unchanged by this draft.

Canonical production-read evidence remains a precise row-level requirement for
the six outcomes whose source use or reference safety cannot be established
from repository authority. E-001/E-002 bind the exact required artifact and
complete selected owner/ref/hash/blocker tuple through a re-derived binding
hash; they are not evidence that a production read occurred. Neither is a
blocker on the two CONFIG control surfaces.

## Immutable DRAFT Verification

Exact DRAFT commit `570f54a50405376ee4b642f1abc11ea04eb0a4bb`
passed GitHub Actions run `33861320397`. Both `Conversion state and
traceability` and `Isolated target environment` completed successfully,
including target contract tests plus macOS and generic iOS Simulator builds.
This verifies the committed draft boundary only; it does not populate or
approve any reconciliation outcome and does not advance the slice to READY.

Follow-up evidence-sync commit
`b4d948e41f9ca6d5ea50da0ba9d8db6504ea06ae` passed GitHub Actions run
`33861762639`. Both jobs completed successfully again, including all target
contract tests and the isolated macOS and generic iOS Simulator builds. The only
annotations were the runner's Node.js action-runtime deprecation warnings.
