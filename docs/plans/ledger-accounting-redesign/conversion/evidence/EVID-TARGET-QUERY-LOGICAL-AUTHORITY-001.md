# EVID-TARGET-QUERY-LOGICAL-AUTHORITY-001 — Target Query Logical-Authority Crosswalk

- Timestamp: 2026-09-03
- Class: READY gate / target query logical-authority conversion control
- Target baseline: `ee06e2a8b86a2b5e7db80c3b8628deeb34f993f6` on
  `codex/supabase-powersync-implementation`
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and shipped app remain unchanged
- Claimed target surfaces: `CONFIG-5422E6C6A047`, `CONFIG-ED6818A70D4E`
- Slice dossier:
  `conversion/implementation-slices/target-query-logical-authority-crosswalk-control.json`
- Verification state: READY; executable validator, generated JSON and package/CI
  integration do not exist yet

## Selection and Scope

The verified target query-port inventory proves exactly 16 verified owners, 16
public exact-suffix `Querying` protocols and 18 direct observation methods. It
does not say what those methods may read, how absence/readiness is interpreted,
which ordering is authoritative, or which uncertainty prevents physical work.
This technical-control slice closes that logical-authority gap before schema,
adapter or index implementation begins.

The reviewed source is one JSON registry with exactly one row per TQUERY. It
binds the current inventory digest and each method's signature hash, then records
only authority references, logical scope/result/order/pagination/readiness/
authorization axes, proposed architecture data-domain dependencies and explicit
unresolved axes. Owner path, protocol, selector and category remain generated
inventory facts and are not copied into the registry.

This is deliberately not the formerly proposed per-query physical index plan.
Postgres and local physical planes are each globally `deferred` under proposed
A-003 and A-004. There are no TINDEX identities, physical keys, table/index
names, SQL, query plans, RLS policies, Sync queries or implementation claims.

## Review Corrections Applied Before READY

Independent review required seven changes before this package was written:

1. remove per-query index identities/classes and retain only global A-003/A-004
   physical-plane deferral;
2. keep Operation queries Account-scoped and multi-domain without inventing a
   Principal predicate, and apply A-015 only to optional optimistic projection;
3. remove O-007/O-015 from budget segments and retain them only for Item
   occurrence/provenance persistence;
4. mark Project preference decision-blocked by O-040 with no authorized data-
   domain assignment;
5. label every stream/data-domain reference `proposed_architecture_dependency`,
   never implemented or authorized;
6. use O-026 only for unresolved reference-data visibility/download/capability
   policy, leaving verified logical read shapes intact; and
7. start Account discovery from an already-established stable Principal while
   preserving unresolved issuer/subject correlation under A-007/A-010.

The bounded READY addendum also corrects `discoverTooling()` so both logical-
authority generator/test paths are excluded from generic Firebase audit/repair
discovery, matching the already-declared CONFIG-only ownership. The comment-only
test scaffold contains contiguous `firestoreQuery` and `firestoreIndex`
sentinels; normal synchronization therefore proves the path exclusion works and
does not merely evade content discovery.

The same sentinels make the current-source query extractor recognize the
comment-only test file as a candidate even though they create no occurrence.
The addendum therefore exact-path-excludes only
`scripts/tests/generate-target-query-logical-authority-crosswalk.test.mjs` from
candidate inspection. `FILE-49BE7A26CE03` is deliberately re-acknowledged at
its exact hash without status or ownership change; both generated QUERY
artifacts, their source/candidate totals, and all 386 occurrences remain byte-
unchanged.

The validator contract was also narrowed to JSON-only structural checking. It
may confirm exact keys/types/enums, set equality, digests, signatures, literal
authority references, exact allowlisted IDs, stable generated identities and
deterministic bytes. It does not scan free-text values for semantic keywords or
parse Markdown decision status/meaning. It therefore cannot infer whether a
sentence or a blocker placement is semantically correct; human row-by-row review
remains mandatory evidence. Every row now cites its exact owning implemented
query-contract evidence in addition to any canonical/architecture authority so
detailed axes remain auditable without pretending canonical specs say more than
they do.

## Reviewed 18-Row Logical Crosswalk

| TQUERY | Reviewed logical authority | Proposed architecture dependency | Explicit uncertainty |
|---|---|---|---|
| `TQUERY-C7BD4AEAAB98` | Exact Account/Project Item accounting sections derive from client-paid Purchase relationships and billable occurrences; Unaccounted For precedes Accounted For and each section preserves upstream Item order; authoritative absence requires complete ready evidence from the provider-free currently supplied working set | Project workspace | O-007/O-015 occurrence/provenance persistence; deterministic physical storage order not defined |
| `TQUERY-CD97754157F6` | Exact Space core zero-or-one read with immutable Project/Inventory scope and ordered checklist hierarchy | Project workspace or Inventory by immutable scope | none in this logical boundary |
| `TQUERY-BD89A02A23F2` | Account-scoped vendor/source suggestions ordered by presentation order and ID; suggestions are convenience values, not Vendor identity | Account catalog | O-026 exact visibility/download capability |
| `TQUERY-A95F4BE0B9D8` | Exact Project-or-Inventory active Space destinations ordered by folded name, exact name and ID | Project workspace or Inventory by immutable scope | none in this logical boundary |
| `TQUERY-2D53E545A090` | Same-Account/same-Client other active Project routes, derived in upstream directory order | Derived from Project directory | no separate canonical data authority |
| `TQUERY-2ACE415664D8` | Exact Account Client directory with stable identity/lifecycle/readiness | Account catalog | canonical directory order not defined |
| `TQUERY-C84BC7558133` | Exact Account Project directory with exact same-Account Client relationship | Account catalog | canonical directory comparator/order not defined |
| `TQUERY-961BF10129CC` | Exact Account/Project/currency signed client-paid and invoicing-unpaid category segments with derived recognized total; consumes only an already-authorized visible snapshot and does not define financial authorization/download policy | Account catalog and Project workspace | contribution-source eligibility and taxonomy are not defined by the current contract; O-007/O-015 are absent |
| `TQUERY-E8233F3CB7D5` | Exact Project core zero-or-one read with current Client relationship and locally observed revision | Project workspace | none in this logical boundary |
| `TQUERY-975125F40458` | Account Space-template structures ordered by explicit presentation order and identity with no copied completion state | Account catalog | O-026 exact visibility/download capability |
| `TQUERY-EDEC33C918C3` | Account-visible category definitions ordered by presentation order and ID | Account catalog | O-026 exact visibility/download capability |
| `TQUERY-7B6C178A522D` | Exact Operation-ID lifecycle read; snapshot itself carries Account, not Principal | Multi-domain local journal and authoritative outcomes | authorization, merge and domain routing not defined |
| `TQUERY-BAFDEB7B1FDF` | Exact Account unresolved operations ordered by accepted time and Operation ID; only queued/applying/rejected are included, draft/applied/superseded/resolved are excluded, and transient failure requeues | Multi-domain identity/Project/Inventory plus local journal | authorization/merge/routing undefined; A-015 only if optimistic projection is required |
| `TQUERY-2932CD350E5E` | Exact Account/Project note pages, bounded 1...200, keyset-ordered by created time and ID descending, with separate page/history completeness | Project workspace | none in this logical boundary |
| `TQUERY-4C3A96B8C83F` | Environment/established-Principal authorized Account summaries with deterministic name/ID and remembered-first presentation | Identity bootstrap | A-007/A-010 identity correlation and A-016 offline unlock/revocation |
| `TQUERY-87E07EB9A4B3` | Candidate representation preserves Account/Principal scope, Project-ID order and stored/notStored/notAvailable distinction | none authorized | O-040 blocks feature retention, data domain, authorization and migration; Project workspace is only conditional if retained |
| `TQUERY-136644A3C02A` | Exact Client core zero-or-one read with lifecycle/audit fields and locally observed revision | Account catalog | none in this logical boundary |
| `TQUERY-9FA1EEF3437A` | Exact Account/Project visible categories composed with absent/enabled/zero/positive/incomplete relationship states in category order | Account catalog and Project workspace | O-026 exact visibility/download capability |

## Frozen JSON-Only Implementation Contract

Implementation may replace only the two comment scaffolds and add one generated
JSON artifact. The dependency-free control must:

- consume the reviewed registry, generated TQUERY inventory and required
  conversion JSON metadata only;
- require exact 18/18 TQUERY set equality, inventory digest and signature hash;
- enforce a closed schema and discriminated logical axes: only `reviewed` has
  `value`; `not_defined_by_current_contract` has `authorityRefs`; and
  `decision_blocked` has `blockerIds`;
- accept only review classes `mapped`, `mapped_with_unresolved_axes`, or
  `decision_blocked`; authority roles `canonical_target`,
  `architecture_authority`, `conversion_control`, or `verification_evidence`;
  logical-axis states `reviewed`, `not_defined_by_current_contract`, or
  `decision_blocked`; and proposed-domain state
  `proposed_architecture_dependency`;
- accept only the exact data-domain, unresolved-axis and decision/blocker token
  allowlists frozen in the dossier. For decisions, membership plus referenced
  path/exact-heading existence is the entire machine check; no decision-status
  or prose parser is allowed;
- join owner/path/protocol/selector/category from the generated inventory;
- derive `TACCESS-` plus the first twelve uppercase hexadecimal characters of
  SHA-256 over `target-query-logical-authority-v1\0<TQUERY-ID>`, collision-check
  it, and derive `mappingHash` as lowercase full SHA-256 over UTF-8
  `target-query-logical-authority-mapping-v1\0` followed by canonical minified
  JSON of the registry row, recursively sorting object keys lexicographically
  while preserving array order;
- require the exact global `physicalPlanes` value: Postgres deferred/A-003 and
  local deferred/A-004; require the exact proposed-domain state; and reject
  blocked axes with a value or unregistered references;
- reject every unknown key. Explicit rejected per-row examples include copied
  inventory fields (`ownerSurfaceId`, `ownerPath`, `protocol`, `selector`,
  `category`) and physical/provider fields (`tindexId`, `indexId`, `indexName`,
  `primaryKeyCandidate`, `secondaryRequired`, `physicalAccess`, `sql`, `rls`,
  `syncStream`, `provider`); rejection is by closed schema or exact enum, never
  by scanning free-text values for those words;
- emit deterministic timestamp-free JSON and make check mode byte-compare
  without writing; and
- report machine structural success separately from required human semantic
  review.

No Swift parser, free-text keyword scanner or Markdown semantic/status parser is
permitted. Exact authority paths and literal headings may be existence-checked,
but prose meaning and decision status are not machine-inferred.

## Lifecycle Allowlists

READY is limited to:

- the reviewed registry;
- the two comment-only executable scaffolds;
- this dossier/evidence pair;
- adding only those two scaffold paths to `discoverConfiguration()` and to the
  bounded `discoverTooling()` Firebase audit/repair exclusion set;
- adding the exact logical-authority test path to the current-query extractor's
  target-control exclusion and deliberately re-acknowledging
  `FILE-49BE7A26CE03` without changing its status or ownership;
- classifying only their two CONFIG surfaces `target_mapped`; and
- synchronized manifest, generated conversion audits/counts, evidence index,
  tracker and execution-state updates.

Implementation may additionally replace the two scaffolds, add only
`target-query-logical-authority-crosswalk.generated.json`, add exact root
generate/check/test commands and the Ubuntu conversion-control hook, and update
the same synchronized control metadata. Promotion is documentation/control only
after immutable implementation CI and separate human review.

All 16 query-owner surfaces, `FILE-063B0E6EC659`, `MAN-INDEX-001`, existing
package/workflow surfaces and the verified TQUERY inventory control preserve
their status and ownership. This slice does not alter Swift, schema, RLS, Sync,
provider, runtime, Firebase, hosted or production behavior.

## Separate Source-Query Reconciliation

The generated current-source inventory still contains 386 `QUERY-*`
occurrences. A later slice must map each occurrence to retained target authority,
a future approved target query, source-only migration/audit use, deliberate
retirement or an explicit decision hold. That work must not transliterate
Firestore syntax or indexes and is not part of this READY package.

## READY Verification

The exact reviewed READY content hashes are:

- discoverer `scripts/supabase-conversion-ledger.mjs`:
  `d09791ac48388b937401e24424caf20164d3bf65ae79f35dabaaaaf0b7c796dd`;
- current-query extractor `scripts/extract-firestore-query-contract.mjs`:
  `326a97771630e5426a9628e4f2926470867604fc43e4f6212880b617fc131a2a`;
- generator scaffold:
  `713dd34cc2304b2603724f6e3d7f92ca4281a3d42d2d8112ed3ff8ef63eb73cf`;
- test scaffold:
  `84090b5d61ce7953561cab02959e1686ae0b26280a4335396b575770bac4eb53`;
- reviewed registry:
  `b67abf7dbdb78c9b89f1eb9e58852e319426f2497a9a9b376f25bc1c9a0416cb`;
  and
- READY dossier:
  `23891fb174cfa2a70229458f545f9ae2a00b3db1c8b33e41896027c1dbc90f97`.

Local syntax and JSON parsing pass. `conversion:sync`, `conversion:report` and
`conversion:check` pass at 839 recorded / 824 currently discovered surfaces,
zero errors and only the three established retired-path warnings. Capability,
current-query, residual and M0 checks pass; the residual register is current at
395 mapped / 184 residual / 46 blockers. All 20 verified target query-port
inventory tests, its 16/16/18 generated-artifact check, target-environment
isolation and target contract/TypeScript checks pass. The READY diff contains no
Swift, package, workflow, generated logical-authority artifact, schema, RLS,
Sync, provider, or Firebase application/backend/runtime change. Its executable
changes are limited to the two exact-path discovery/extraction exclusions; the
logical-authority test scaffold remains comment-only. Swift tests and staging
builds were not rerun because the addendum changes only those repository-local
control exclusions, documentation/control JSON, and the comment-only scaffold;
those gates remain required for implementation.

The literal `firestoreQuery`/`firestoreIndex` sentinel check passes while the
logical-authority generator/test remain exactly their two CONFIG surfaces and
the current-query artifacts remain byte-unchanged/current at 170 inspected
candidates, 74 files with occurrences and exactly 386 occurrences. The bounded
READY addendum changes exactly 16 paths, including synchronized generated
conversion audits; it creates no extra FILE surface.

No hosted service or production system was contacted, and no implementation or
cutover authority is created by this evidence.
