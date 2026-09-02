# Supabase Conversion Execution State

Last updated: 2026-09-02
State version: 165

## Objective

Create a complete, evidence-backed inventory and Supabase/PowerSync target
mapping for the entire Ledger application, then implement and rehearse it without
modifying the running Firebase application before hard cutover.

## Current Checkpoint

- Phase: M1 evidence-gated source closure and bounded M2 mapping continue;
  decision-independent Phase 1 target foundations are now in progress
- Checkpoint: PROJECT-CORE-DETAILS-ISOLATED-WORKER
- Branch: `codex/supabase-powersync-implementation`
- Source commit: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6`
- Worktree: dedicated conversion branch/worktree. The current Firebase release
  baseline is committed and shared by `firebase` and `main`; conversion planning,
  architecture, control, and evidence remain isolated on this branch.
- Production export: profilers and artifact format are ready; execution is
  blocked on an acceptable external project-matching service-account key or a
  separately proven canonical immutable production export. Existing local
  `firebase-export*` directories do not have sufficient recorded provenance to
  promote silently.
- Production mutations authorized: no.
- Supabase/PowerSync implementation authorized: decision-independent target
  environment contracts, isolated build/test infrastructure, and unprovisioned
  staging shell only; hosted resources, provider adapters, product/schema
  decisions, migration, and production authority remain gated.

## Completed at This Checkpoint

- Separated the supplied 197-path dirty snapshot into an independently verified
  16-path current Firebase implementation commit, a 64-path product-authority
  package with four supporting non-item audit/evidence paths, and the remaining
  conversion architecture/control/generated-evidence package. `firebase` and `main`
  now share exact source baseline `fe018501`; no conversion file was placed on
  either shared branch. See `EVID-GIT-BASELINE-001`.
- Established a machine-readable conversion manifest and objective milestone
  definitions.
- Added automatic discovery for Swift application/test files, Firestore rule
  surfaces, Firebase Functions, MCP modules/tools/resources, Firebase-related
  scripts, migration tooling, configuration, and existing tests.
- Added manual cross-cutting surfaces that static discovery cannot prove:
  production data profiling, Auth, Storage, dynamic/server-only data, indexes,
  hosting/deep links, offline behavior, local lifecycle, reports, release
  isolation, cutover, and observability.
- Added validation, milestone gating, and generated coverage reporting.
- Synchronized 674 repository-discovered and 12 manual cross-cutting surfaces.
- Verified the control tool with deterministic positive checks and intentional
  negative milestone-gate checks; see `EVID-CONTROL-001`.
- Characterized every production Firestore rule match, all 18 exported Cloud
  Functions, all five Function modules, the core Firebase Auth/account/invite
  boundary, MCP OAuth/Admin access, Storage/media behavior, and server-only
  dynamic collections.
- Classified all 686 surfaces: 680 characterized, four verified control/tool
  surfaces, and two intentionally blocked evidence surfaces. Zero surfaces are
  unclassified or lack behavior, evidence, or one classification batch.
- Published `current-backend-contract.md` and `EVID-SOURCE-BACKEND-001`,
  including current privilege defects, production/test rule drift, derived
  side effects, media durability, and explicit static-review limitations.
- Added a deterministic query extractor and generated a catalog from 169
  Firestore-candidate files: 74 contain 386 recognized reads, filters, ordering,
  pagination, listeners, collection groups, projections, and aggregates.
- Published `current-query-contract.md` and `EVID-QUERY-001`; static query and
  declared-index characterization is complete. Deployed index/runtime evidence
  remains open.
- Added separate fail-closed Firestore/Auth and Storage/reference profilers,
  a shared exact-target/redaction/hashed-artifact runtime, a mutation-API source
  guard, and gitignored production-derived output location.
- Resolved the exact target to project `ledger-nine4`, account
  `1dd4fd75-8eea-4f7a-98e7-bf45b987ae94`, and bucket
  `ledger-nine4.firebasestorage.app`. No production call was made because this
  host does not currently expose an acceptable service-account credential.
- Adopted the Capability Evolution Method: source mechanics and possibly stale
  specs are evidence, not automatic parity requirements. Every target slice now
  requires preserve/correct/improve/redesign/retire decisions and tests.
- Assigned all 41 Swift service/Auth and 47 MCP source modules to 11 initial
  user/operational capabilities in a deterministic generated catalog. The
  capability register records the dossier queue without inventing target tables.
- Completed the first static capability dossier for identity, account session,
  invites, MCP account binding, pending-work logout and the shared operation
  lifecycle. It links services, models, UI callers, Functions, tests and specs;
  separates preserved outcomes from defects/mechanics; and defines observable
  contracts/tests without selecting Auth or target tables.
- Updated the stale authentication/offline-access spec to reflect the confirmed
  offline-first target and current Firebase behavior while retaining A-007,
  A-016, unlock/recovery and logout product questions as explicit blockers.
- Completed the media, attachments, and offline-byte-durability static dossier.
  It links the iOS upload/queue/cache/model/presentation paths, every granular
  MCP media tool, parent callers/shapes, tests, fixtures and legacy migration
  utilities without treating Firebase URL/path mechanics as parity.
- Confirmed that durable offline media is not universal in the current app:
  several create/import flows enqueue bytes, while Transaction/account/detail
  paths upload directly; queue local-display APIs have no callers; enqueue can
  report an ID after local persistence failure; and placeholder records can
  outlive retained bytes.
- Defined a backend-neutral stable-attachment/durable-receipt contract,
  private/local-first display, idempotent/resumable verification, derivative
  state, shared-reference retention, MCP ingress security, migration
  reconciliation and offline/fault/security tests.
- Reconciled `offline-first.md` with the target attachment lifecycle, corrected
  the legacy proto media field in `data-model.md` to `photos`, and recorded
  O-023 for reference removal versus permanent byte deletion/retention.
- Characterized 44 additional local/media/UI/MCP/test/fixture/migration surfaces;
  old Supabase-to-Firebase and one-off repair tools are explicitly source-only,
  not target implementation.
- Completed the Projects/Clients/settings/reference-data static dossier. It
  identified free-text Client identity, partial Project setup, orphaning hard
  delete, cross-user preference access, reorder/array races and incomplete
  Space-template callers; recorded O-024–O-026; and characterized 54 surfaces.
- Completed the unified Item creation/accounting Link/legacy-capture static
  dossier. It defines one real-Item writer, stable offline identity,
  quantity-on-one-record semantics, relationship-derived Project sections,
  story-specific Link commands and source-only proto import; it characterized
  52 additional surfaces.
- Corrected stale target dual-read guidance: the running Firebase app remains
  unchanged before hard cutover, immutable exports are imported into isolated
  target staging, the final freeze/import resolves every proto, and the target
  contains no Firebase runtime Item/proto reader or writer.
- Recorded O-027 for the exact unified name/photo/note minimum-evidence rule
  rather than copying either contradictory current form.
- Completed the Inventory/provenance/Transaction/receipt/correction static
  dossier. It separates real scope-owner money, physical placement, open
  demand/credit, Transfer and correction; defines deterministic offline history
  readiness; and characterizes 81 additional Swift/MCP/test/migration surfaces.
- Corrected the older Vendor Credit proposal: D-001/D-007 prohibit its fourth
  target Transaction type. Actual vendor money received is a scope-relative
  Return; O-028 records the still-open non-cash cancellation/account-credit
  representation.
- Recorded O-029–O-032 for Transaction void/delete, receipt one-cent behavior,
  Item tax-basis inheritance and canonical posted-versus-draft minimum evidence.
- Completed the Invoicing/collection/budget static dossier. It traces live
  Invoice sources, Expense/Fee/manual paths, collection/correction, vendor
  document intake, budget projections, access filtering, app/MCP divergence,
  rules/Functions/tests and legacy repair/migration evidence; it characterizes
  62 additional surfaces.
- Defined one target-neutral whole-Invoice collection contract: authoritative
  source-set/revision validation, one actual positive Client payment, one
  Project Purchase, immutable frozen allocations, durable idempotent result,
  and no Invoice-link or collection-Purchase budget double count.
- Defined stable budget-contribution identity and one `ProjectBudgetSnapshot`
  read contract for paid/unpaid/recognized/category values, replacing current
  Transaction-only and cached-summary authority.
- Recorded O-033 for actual collection-payment variance and O-034 for
  sent-Invoice membership revision/resend/render/delivery audit.
- Completed the reporting/search/cross-domain static dossier and classified 42
  surfaces. Defined version/readiness-aware search, report and export snapshots,
  one canonical visibility-safe projection authority, stable cursors and
  private receipt delivery; recorded O-035/O-036.
- Completed the Spaces/review/work-queue static dossier and classified 33
  surfaces. Defined typed Space/checklist/assignment/archive/review operations,
  explicit review reasons and offline readiness; recorded O-037.
- Completed the platform/transport/release/migration-control static dossier and
  classified 101 surfaces. Defined the fail-closed environment manifest, small
  target composition root, Principal-bound/versioned MCP, release manifest,
  migration runner and observability controls; explicitly rejected Firebase
  adapters and reuse of the reverse Supabase-to-Firebase migration package.
- Completed the app-shell/shared-presentation/test-support static dossier and
  classified the final 115 surfaces. Preserved reusable UI/platform outcomes,
  redesigned typed snapshot/intent/readiness boundaries, retired placeholders
  and raw Item mutation coordinators, and separated target tests from source-era
  Firestore/Sale/payment mechanics.
- Ran the deterministic whole-manifest audit across 18 batches. M0 passes with
  686 recorded surfaces, zero unclassified/missing behavior/missing evidence/
  missing batch/source-drift/validation gaps. G0.5 capability synthesis is done;
  see `EVID-M0-COVERAGE-001`.
- Exactly mapped 39 target-relevant app-shell/presentation/test surfaces and
  eight identity/membership/session/MCP-account surfaces, including all required
  owner, target surface, security, Sync, migration, reconciliation, test and
  acceptance fields; see `EVID-M2-APP-SHELL-001` and `EVID-M2-IDENTITY-001`.
- Exactly mapped 15 of 19 target-relevant media surfaces to stable attachment
  identity, protected durable local bytes, private resolution, parent-specific
  operations, revision-safe order/primary changes, secure MCP ingress and
  migration/reconciliation tests. The four detach/delete tools remain honestly
  characterized because O-023 and the canonical reference/object profile can
  still change whether those target commands exist; see `EVID-M2-MEDIA-001`.
- Exactly mapped 38 of 41 target-relevant platform/control surfaces to fail-
  closed environment/composition, Principal-bound MCP, generated contracts,
  stable errors/capabilities, protected exports, observability, hosting and
  reproducible release authority. The concrete SDK lock graph, cross-cutting
  offline contract and price/tax helper retain exact A-003/A-004,
  A-015/A-016/physical-verification and O-008/O-031 holds; see
  `EVID-M2-PLATFORM-001`.
- Exactly mapped 36 of 52 target-relevant Client/Project/reference surfaces to
  stable Client relationships, durable Project setup, readiness-aware local
  queries, revisioned notes, own-Principal preferences, normalized reference
  reads, typed ports, MCP parity and semantic tests. Sixteen writer/deletion/
  correction surfaces retain exact O-024–O-026 holds; see
  `EVID-M2-PROJECT-REFERENCE-001`.
- Exactly mapped 14 of 31 target-relevant Item creation/Link surfaces to typed
  Item query/detail/accounting-section ports, one stable physical identity,
  bounded MCP queries, revisioned safe bulk operations and target semantic
  tests. Seventeen decision-sensitive writer/schema/import/retention surfaces
  remain honestly held; O-021 is explicitly UI-only; see
  `EVID-M2-ITEM-CREATION-001`.
- Exactly mapped 23 of 66 target-relevant Inventory/Transaction surfaces to
  typed Transaction boundaries, versioned local/MCP read models, offline-ready
  provenance history, typed corrections, exact-cent audit and semantic target
  tests. Forty-three decision-sensitive writer/schema/lifecycle/planning
  surfaces remain honestly held; O-038 now owns Inventory destination-planning
  retention, granularity and lifecycle; see
  `EVID-M2-INVENTORY-TRANSACTION-001`.
- Exactly mapped 21 of 44 target-relevant Invoicing/budget surfaces to stable
  contribution identity, Invoice/billing read models, download-time financial
  authorization, durable vendor-document intake, typed ports and semantic
  collection/contribution tests. Twenty-three decision-sensitive writer/
  lifecycle/display surfaces remain honestly held; see
  `EVID-M2-INVOICING-BUDGET-001`.
- Exactly mapped 16 of 27 target-relevant Space/review surfaces to stable
  Space/checklist/review identity, readiness-aware local queries, typed create/
  update/checklist/assignment operations and semantic target tests. Eleven
  archive/review-media/work-queue surfaces remain honestly held; see
  `EVID-M2-SPACES-REVIEW-001`.
- Exactly mapped 19 of 37 target-relevant reporting/search surfaces to named
  visibility-safe projections, stable search/lookup contracts, immutable report/
  export snapshots, protected artifact lifecycle and semantic tests. Eighteen
  report-semantic/delivery/posting surfaces remain honestly held; see
  `EVID-M2-REPORTING-SEARCH-001`.
- Exactly mapped 31 of 62 target-relevant backend/Auth/Functions/rules/Storage/
  query-control surfaces to capability-specific identity/handlers/RLS/Sync,
  private attachment Storage, query/index control and source-to-target
  migration contracts. Thirty-one decision/evidence-sensitive backend surfaces
  remain honestly held; see `EVID-M2-BACKEND-CONTROL-001`.
- Audited all 427 target-relevant source/control surfaces: 260 are exactly
  mapped, 167 retain
  explicit mapping-changing blockers, zero mapped entries lack any required
  field and zero residual entries have an empty blocker list; see
  `EVID-M2-WHOLE-MANIFEST-001`.
- Added a deterministic M2 residual generator/check and generated JSON/Markdown
  queue: 167 residual surfaces grouped under 44 validated product, architecture,
  spike, or production-evidence blockers. Unknown blockers and stale artifacts
  fail `npm run conversion:residuals:check`.
- Drafted seventeen senior-level product decision packets covering all 36 product
  blockers and all 160 product-dependent residual surfaces: O-007/O-015
  explicit Item facts/provenance; O-029/O-032 Transaction post/lifecycle;
  O-023 attachment
  retention; O-026 reference-data capabilities; O-031 Item tax/basis; O-009/
  O-034 typed adjustments/sent revisions; O-003/O-004/O-005/O-010 credit,
  zero-Invoice and signed-budget behavior; and O-008/O-030 exact receipt-line
  treatment/one-cent variance; and O-006/O-033 Expense field locks/exact
  collection payment; O-035/O-036 Client Summary/shared evidence; and O-037
  Space archive/assignment; O-002/O-011–O-014 Transfer edges; and O-016/O-017/
  O-027 Item capture/acquisition readiness; O-018/O-019/O-020/O-022 proto
  migration/authority cutoff; O-024/O-025 Project/Client lifecycle; O-028
  non-cash vendor adjustment/conserved balance; and O-038 Inventory destination
  planning retention/granularity/lifecycle. O-021 is explicitly UI-only and
  deferred to UX testing. These are proposals, not approvals;
  see `EVID-M2-DECISION-PACKETS-001`.
- Applied Supabase Postgres design guidance to the proposals: explicit relational
  authority, integer cents/`timestamptz`, indexed foreign keys and RLS predicates,
  partial/composite indexes for bounded query shapes, keyset pagination, short
  deterministic-lock-order transactions, least privilege and no premature
  partitioning. No DDL or target implementation was created.
- Converted the broad A-003/A-004/A-007/A-015/A-016 and physical-device spike
  criteria into an executable S0–S9 protocol with a disposable synthetic slice,
  7,000-Item reported-scale and 20,000-Item headroom fixtures, sixteen mandatory
  hard-failure tests, Auth/optimism comparisons, seven-day offline and media/
  revocation/evolution/restore cases, precommitted thresholds, cost review,
  machine-readable evidence layout, repetition and strict no-go semantics; see
  `EVID-M2-SPIKE-PROTOCOL-001`. Execution and provider approval remain blocked.
- Added a reviewed product-authority crosswalk and generated JSON/Markdown
  audit. All 686 surfaces now resolve through 18 classification batches to an
  explicit authority set: 573 product-governed and 113 technical/control.
  All five target specs registered at that checkpoint were explicitly
  distinguished from current
  product and historical evidence; see `EVID-PRODUCT-AUTHORITY-001`.
- Made authority coverage part of `conversion:check`: missing batch mappings,
  missing authority files, product batches without a canonical target spec,
  unused canonical target specs, unresolved surfaces and stale generated audit
  artifacts fail closed. The check now also compares live discovered hashes
  with the synchronized manifest instead of detecting source drift only after
  a sync.
- Added explicit canonical-target reconciliation to the Invoicing,
  Inventory/Transaction, Project/Client, reporting, identity, Spaces, app-shell,
  and platform dossiers. Current/historical Firebase-era specs remain behavior
  or migration evidence and cannot define the redesigned target.
- Added the required Vertical Slice Implementation Method, ignored dossier
  template, and generated slice JSON/Markdown audit. Slice requirements must
  name exact existing authority headings and trace reciprocally to executable
  verification obligations across domain, Postgres, handlers, Data API grants,
  RLS, Sync, offline, media, app/MCP, migration/reconciliation, operations and
  rollback.
- Conversion checking now enforces slice readiness, derived test kinds,
  implementation/passing/rehearsal evidence and bidirectional status agreement.
  An implemented-or-later target surface without exactly one correspondingly
  advanced slice fails. A valid temporary ready-slice control passed; invalid
  ready-slice and implemented-without-slice controls failed; see
  `EVID-SLICE-METHOD-001`.
- Adopted the long-running goal operating model: the goal owns the coherent
  outcome while repository instructions, execution state, slice dossiers,
  generated audits and evidence own durable truth. Fresh, resumed, handed-off
  and compacted agents must reconstruct state rather than trust conversation
  memory.
- Tightened `AGENTS.md` and the conversion README so target implementation reads
  the full method and active dossier, reconciles the working diff, reruns the
  conversion check and continues autonomously through routine checkpoints while
  respecting explicit decision/credential/spend/production/cutover boundaries.
- Added a narrow repository-local Codex `SessionStart` hook for `source=compact`.
  Its deterministic contract reads state version/checkpoint/next action, runs
  the conversion check and supplies bounded context to the immediate
  continuation. It does not mutate state or grant authority; one-time Codex hook
  trust and a live compaction observation remain before full evidence. See
  `EVID-CONTINUITY-001`.
- Added a pull-request conversion-control workflow using Node.js 22. It runs the
  conversion, capability, query, residual and M0 controls and rejects generated
  rewrites. The first workflow run and repository branch-protection requirement
  remain external verification/administration steps; no merge-enforcement claim
  is made yet.
- Started the first machine-enforced technical slice,
  `target-environment-isolation`, with exact architecture/conversion
  requirements, complete contract applicability, reciprocal verification, and
  explicit non-authority limits.
- Added the public, dependency-free `LedgerTargetCore` package. Its closed
  target environment manifest, exact contract/resource allowlists, safe
  diagnostics, deterministic per-Principal/Account local namespaces, persisted
  environment binding, PowerSync descriptor, and pre-dependency/local-state
  bootstrap gates import no provider SDK.
- Added 12 deterministic package tests. They pass for manifest validation,
  Firebase-kind refusal, mixed/production resource refusal, contract mismatch,
  safe diagnostics, pre-bootstrap refusal, restart-stable namespace isolation,
  required identity inputs, stale persisted-binding byte preservation, and
  matching-binding reopen.
- Added a separate reproducible `LedgerTarget.xcodeproj`, generated from
  `LedgerTargetProject.yml`; the source Firebase `LedgeriOS.xcodeproj`
  remains unchanged. The target project builds a fixed
  `apps.nine4.ledger.staging` / `Ledger STAGING` shell for macOS and iOS
  Simulator, links only the local target core, shows permanent staging/no-hosted-
  services banner code, and contains only unprovisioned synthetic identifiers.
- Added a fail-closed graph/import/source-contamination check and root commands
  for target checks, tests, generation, and both platform builds. Repeated
  XcodeGen output is byte-stable on this host.
- Extended the pull-request workflow with a separate macOS target job for the
  boundary check, 12 tests, both builds, and clean-diff verification. Its first
  external run remains pending; the slice therefore stays `in_progress` and
  `TARGET-ENV-TEST-005` remains planned.
- Recorded partial implementation evidence in
  `EVID-TARGET-ENVIRONMENT-001`. No hosted resource, credential, network
  backend, source Firebase implementation, production read/mutation, deployment,
  migration, release, or cutover was used.
- Opened draft pull request `#1` only as the review/CI surface for the isolated
  Supabase branch. GitHub Actions run `33555553117` passed both conversion
  traceability and isolated-target jobs at commit `2da54304`, including the
  target boundary check, 12 package tests, macOS build, generic iOS Simulator
  build and clean-diff verification. The Firebase worktree/branch remained
  unchanged; the draft was not merged and grants no deployment or cutover
  authority.
- Completed and verified the decision-independent
  `operation-lifecycle-and-readiness` technical slice. The dependency-free
  target core now owns typed Operation/Account/Principal IDs, a typed command
  envelope and closed preconditions, canonical epoch-millisecond codec and
  SHA-256 fingerprint, queued receipt versus authoritative snapshot/outcome,
  the closed lifecycle transition graph, stable error/retry/rejection values,
  an Account-scoped restartable reference journal, provider-free operation and
  health ports, and explicit subscription/pending/write-block readiness.
- Added eleven deterministic operation/restart/readiness tests. The first run
  exposed and then corrected a mismatched date decode strategy; the final 11
  operation tests and all 23 target-package tests pass. Exact replay,
  same-ID/different-payload refusal, transient requeue, permanent rejection
  without queue starvation, lost-response replay, illegal transition refusal,
  restart restoration, Account isolation, online/readiness separation,
  explicit required-update/contract blocks, retained original result/rejection
  evidence through supersession/resolution, and safe diagnostics are proven in
  `EVID-OPERATION-CORE-001`.
- Advanced the two target-only operation code/test surfaces to `verified`,
  extended the reviewed platform authority set to the operation/domain/port
  architecture files, and regenerated coverage/authority/slice audits. The
  initial checkpoint also overclaimed three broader current MCP/app/test-helper
  replacements; the later Phase 1 audit corrected those surfaces and removed
  them from the slice because concrete app/MCP/test-harness integration was
  explicitly not applicable. No Postgres schema, RLS, Data API grant, PowerSync
  Stream, provider adapter, hosted resource, Firebase implementation,
  migration, deployment or production operation was introduced.
- Implemented the decision-independent `versioned-contract-catalog` technical
  slice with one canonical registry and deterministic Swift, TypeScript and
  bounded MCP-resource projections. All projections embed catalog SHA-256
  `1a42004b…`, and the target TypeScript package pins compiler 5.9.3 with no
  runtime dependencies.
- Added strict shape/version/cross-reference/test-owner/size/leakage validation,
  reciprocal deprecation checks, generated-file freshness enforcement and
  nineteen intentional malformed-catalog controls. Six catalog tests and all
  29 target-package tests pass; strict TypeScript compilation, isolated target
  checks, macOS build, generic iOS Simulator build, clean source-project diff
  and diff formatting also pass locally. See `EVID-CONTRACT-CATALOG-001`.
- Advanced only the ten new target implementation surfaces to `implemented`.
  The ten broader current-MCP replacement surfaces deliberately remain
  `target_mapped` because product command/query DTOs, transport execution,
  container/deployment controls and full app/MCP parity are not implemented by
  this platform-only catalog. Exact-commit external CI remains the final
  `CONTRACT-CATALOG-TEST-003` obligation before verification.
- Parent-commit GitHub Actions run `33557226244` passed the isolated target job
  but failed conversion traceability because the query catalog had not been
  regenerated after new Swift/script candidates and the residual generator
  recognized only the literal `target_mapped` status. This checkpoint excludes
  target-only scripts from Firebase query-source candidates, treats every later
  lifecycle status as mapped-or-later, regenerates both artifacts, and passes
  the complete local workflow command set. The failed run is not accepted as
  verification; a new exact-commit run is required.
- Exact implementation commit `c79484a8` passed immutable GitHub Actions run
  `33559241558`: both conversion traceability and isolated-target jobs passed,
  including generated contract validation, the then-configured 12 environment
  tests, macOS and generic iOS Simulator builds, and clean-diff checks. All 29
  then-current package tests also passed locally; corrected cumulative run
  `33567370249` later passed the complete 47-test suite with the implementation
  unchanged. All three catalog obligations and exactly its ten target-only
  surfaces are now `verified`.
- Created and passed the ready gate for `shared-list-query-presentation`, then
  implemented target-only named query/sort/filter/action profiles, normalized
  search, stable-ID tie ordering, query-bound opaque cursors, local version/as-
  of snapshots, explicit readiness/empty/failure states, typed presentation
  intents, and a pure cached-first reducer. Raw not-found/authorization/
  authentication causes collapse internally before the public update boundary.
- Added three deterministic domain/restart/rejection tests; all 32 target tests,
  the target boundary guard, macOS build, generic iOS Simulator build and clean
  source-project diff pass locally. Only the two new target code/test surfaces
  are `implemented`; four broader current list-control replacements remain
  `target_mapped` pending concrete UI/accessibility and feature profiles. See
  `EVID-SHARED-LIST-001`.
- Exact implementation commit `587ce11e` passed immutable GitHub Actions run
  `33560578730`: both conversion traceability and isolated-target jobs passed,
  including the then-configured environment tests, generated contracts, target
  boundary checks, macOS and generic iOS Simulator builds, and clean tracked
  artifacts. Corrected cumulative run `33567370249` later passed all 47 target
  tests with the implementation unchanged. All four shared-list obligations and
  exactly its two target-only surfaces are now `verified`; the four concrete
  source UI replacements remain `target_mapped`.
- Created and passed the ready gate for
  `scoped-route-resolution-and-restoration`, then implemented target-only
  registered stable routes, bounded subject/parent scope, environment/
  Principal/Account restoration, opaque deterministic keys, activation-bound
  resolution, explicit not-synced/retry states, structural non-enumeration, and
  late-workspace-result refusal. Live resolution requests are intentionally not
  decodable without registry validation.
- Added three deterministic domain/restart/rejection tests; all 35 target tests,
  the target boundary and contract checks, macOS build, generic iOS Simulator
  build, clean source-project diff, and diff formatting pass locally. Only the
  two new target code/test surfaces are `implemented`; concrete current routes,
  views, workspace/Auth lifecycle, and accessibility remain unadvanced. See
  `EVID-SCOPED-ROUTE-001`.
- Exact implementation commit `bb978212` passed immutable GitHub Actions run
  `33562117852`: both conversion traceability and isolated-target jobs passed,
  including the then-configured environment tests, generated contracts, target
  boundary checks, macOS and generic iOS Simulator builds, and clean tracked
  artifacts. Corrected cumulative run `33567370249` later passed all 47 target
  tests with the implementation unchanged. All four scoped-route obligations
  and exactly its two target-only surfaces are now `verified`; current Firebase-
  era route/view surfaces remain unadvanced.
- Created and passed the ready gate for `typed-edit-draft-and-submission`, then
  implemented target-only unchanged/set/clear field values, typed Account/
  actor/contract/entity/revision-bound drafts, stable validation results,
  exact operation-envelope binding, and provider-free receipt/result
  presentation. Binding cannot be directly constructed or decoded; restart
  recreates it by revalidating the typed draft and queued envelope.
- Added four deterministic domain/restart/rejection/presentation tests; all 39
  target tests, target boundary and contract checks, macOS build, generic iOS
  Simulator build, clean source-project diff, and diff formatting pass locally.
  Only the two new target code/test surfaces are `implemented`; current editors,
  product field rules, commands/handlers, concrete UI, and MCP remain
  unadvanced. See `EVID-TYPED-EDIT-001`.
- Exact implementation commit `10a7db79` passed immutable GitHub Actions run
  `33563347569`: both conversion traceability and isolated-target jobs passed,
  including the then-configured environment tests, generated contracts, target
  boundary checks, macOS and generic iOS Simulator builds, and clean tracked
  artifacts. Corrected cumulative run `33567370249` later passed all 47 target
  tests with the implementation unchanged. All five typed-edit obligations and
  exactly its two target-only surfaces are now `verified`; current editors and
  feature commands remain unadvanced.
- Created and passed the ready gate for
  `privacy-safe-telemetry-and-correlation`. Exactly two comment-only target
  scaffolds are mapped to stable signal IDs, validated environment/build scope,
  domain-separated opaque correlation, exact allowlisted bounded values,
  canonical offline representation, and deterministic redaction/refusal.
  Current app/MCP logging remains unadvanced; no sink, emission, provider,
  hosted resource, credential, product event, migration or production action
  exists. See `EVID-TELEMETRY-001`.
- Implemented the ready telemetry slice with closed target signal and dimension
  IDs, generated telemetry-class validation, validated environment/build/
  contract scope, typed domain-separated HMAC-SHA256 correlation, exact
  dimension/correlation/unit/range allowlists, deterministic canonical bytes,
  a 1,536-byte envelope ceiling, and stable redaction/refusal by data class.
  Four focused tests and all 43 target tests pass, as do target boundary and
  generated-contract checks, macOS/iOS Simulator target builds, clean source-
  project isolation and diff formatting. Exactly the two target-only telemetry
  surfaces are `implemented`; current logging/telemetry surfaces remain
  `target_mapped`. Exact-commit CI is still required before verification.
- Exact implementation commit `4277afc5` passed immutable GitHub Actions run
  `33565583450`: both conversion traceability and isolated-target jobs passed,
  including the then-configured environment tests, generated contracts, target
  boundary checks, macOS and generic iOS Simulator builds, and clean tracked
  artifacts. Corrected cumulative run `33567370249` later passed all 47 target
  tests with the implementation unchanged. All four telemetry obligations and
  exactly its two target-only surfaces are now `verified`; current app/MCP/
  performance logging remains unadvanced.
- Created and passed the ready gate for
  `reproducible-release-manifest-and-artifact-integrity`. Exactly two comment-
  only target scaffolds are mapped to validated release build/channel/contract
  identity, immutable artifact and dependency-lock hashes, canonical manifest
  evidence, compatibility refusal, and an evidence-only non-authority boundary.
  Current release scripts remain unadvanced; no signer, upload, provider,
  hosted resource, deployment, migration execution, production release or
  cutover action exists. See `EVID-RELEASE-MANIFEST-001`.
- Implemented the ready release-manifest slice with closed release values,
  environment-derived build identity, exact generated-catalog and schema/query/
  operation/Sync binding, immutable artifact/dependency-lock byte evidence,
  deterministic canonical restart bytes/content digest, exact compatibility and
  tamper failures, fixed count/size ceilings, and a single evidence-only
  disposition. Four focused tests and all 47 target tests pass, as do target
  boundary and generated-contract checks, macOS/iOS Simulator target builds,
  clean source-project isolation and diff formatting. Exactly the two target-
  only release-manifest surfaces are `implemented`; current release scripts
  remain `target_mapped`. Exact-commit CI is still required before verification.
- Exact implementation commit `81726e3b` passed immutable GitHub Actions run
  `33567370249`: both conversion traceability and isolated-target jobs passed,
  including the corrected complete 47-test target package suite, generated
  contracts, target boundary checks, macOS and generic iOS Simulator builds,
  and clean tracked artifacts. All four release-manifest obligations and exactly
  its two target-only surfaces are now `verified`; current release scripts
  remain `target_mapped`.
- The same checkpoint corrected an inherited CI evidence gap: earlier isolated-
  target runs executed only the 12 environment tests despite evidence prose
  saying “all target tests.” The workflow now runs the complete package, prior
  evidence names the exact split instead of overstating the old runs, and
  immutable run `33567370249` supplies cumulative hosted proof for all 47
  unchanged target tests.
- Created and passed the ready gate for
  `protected-artifact-export-lifecycle`. Exactly two comment-only target
  scaffolds are mapped to an already-authorized immutable snapshot reference,
  policy-bounded short-lived lease lifecycle, deterministic restart evidence,
  typed destination/cleanup receipt and stable fail-closed results. The dossier
  explicitly cannot choose report contents, widen visibility, authorize client
  delivery, prove filesystem protection/deletion or settle O-023/O-036. No
  bytes, files, renderer, destination adapter, provider, migration or production
  action exists; see `EVID-PROTECTED-ARTIFACT-001`.
- Implemented the ready protected-artifact slice with fixed opaque export/
  snapshot IDs and visibility-scope digest, exact immutable snapshot/profile/
  authority binding, policy and request fingerprints, a path-free short-lived
  lease, replay-validated lifecycle, canonical restart evidence and evidence-
  only terminal receipts. Four focused tests and all 51 target tests pass, as do
  target boundary and generated-contract checks, macOS/iOS Simulator target
  builds, clean source-project isolation and diff formatting. Exactly the two
  target-only surfaces are `implemented`; current report/export/PDF/share/
  platform destination surfaces remain `target_mapped`. Exact-commit CI is
  still required before verification.
- Exact implementation commit `10d94f1f` passed immutable GitHub Actions run
  `33569882379`: both conversion traceability and isolated-target jobs passed,
  including all 51 target tests, generated contracts, target boundary checks,
  macOS and generic iOS Simulator builds, and clean tracked artifacts. All four
  protected-artifact obligations and exactly its two target-only surfaces are
  now `verified`; current report/export/PDF/share/platform destination surfaces
  remain `target_mapped`.
- Selected and passed the ready gate for
  `migration-run-plan-and-journal-integrity` only after confirming the boundary
  is explicitly owned by the migration/release architecture and reviewed
  platform dossier. Exactly two comment-only surfaces live under a separate
  target migration-control module; neither is linked into the target app.
- The ready dossier binds immutable source/target/Account/artifact/version
  evidence, deterministic journal/replay/resume semantics, exact per-entity
  outcomes, named reconciliation and permanent evidence-only non-authority to
  six planned domain/restart/rejection/migration/reconciliation/operational
  obligations. It cannot read an export, connect to a target, persist a journal,
  sign or approve a plan, execute/roll back a migration or authorize cutover.
- Extended automatic conversion discovery to the separate migration-core/test
  directories and re-acknowledged only the exact reviewed control-script hash.
  Sync/check/report pass at 725 recorded / 710 discovered surfaces with zero
  errors and the same three documented retired-path warnings. The existing
  reverse Supabase-to-Firebase package remains source-only and untouched.
- Implemented `LedgerTargetMigrationCore` as a second provider-free Swift
  package product that depends only on `LedgerTargetCore` and is linked by
  neither application project. The graph guard now validates the separate
  tooling/test edges, provider-import coverage and app/source-project exclusion.
- Added immutable source/target/Account/artifact/entity plan identity,
  canonical evidence-only plan bytes, monotonic replay-safe journal events,
  interruption/resume fingerprints, overflow-safe exact counts, terminal
  manifest/reconciliation closure and canonical restart/tamper refusal. No
  exporter, transform, loader, database/file/provider adapter, journal store,
  signer, operator authorization or executor exists.
- Bound every public journal boundary to the same exact plan policy and added a
  negative direct-decoding bypass fixture, so a structurally decodable but
  changed plan cannot start, append, encode or restore journal evidence.
- Four focused migration-integrity tests and all 55 target package tests pass
  locally, as do target boundary/contract checks, reproducible project
  generation and macOS/generic-iOS-Simulator staging builds. Five of six slice
  obligations pass locally; the exact-commit operational CI obligation remains
  planned, so exactly its two target-only surfaces are `implemented` rather
  than `verified`.
- Exact implementation commit `34d52dba` passed immutable GitHub Actions run
  `33573298495`: both conversion traceability and isolated-target jobs passed,
  including all 55 target tests, generated contracts, dependency/application-
  graph guards, macOS and generic iOS Simulator builds and clean tracked
  artifacts. All six migration-run obligations and exactly its two target-only
  surfaces are now `verified`.
- Selected `operational-health-and-objective-registry` only after auditing the
  architecture and reviewed `MAN-OBS-001`, `SWIFT-7B159D426B1D`,
  `SWIFT-2703ADAB66C5` and `TEST-ECE08B24ADCE` mappings. Those broader source
  outcomes remain `target_mapped`: a registry without actual emitters,
  lifecycle wiring, adapters, approved thresholds and physical evidence is not
  their replacement.
- Created exactly two comment-only target scaffolds and a ready dossier for
  provider-free health derivation, complete measurement/objective/alert/runbook
  topology, evidence-gated objective evaluation, spike-pending numeric budgets,
  canonical restart evidence and permanent candidate-only/non-authority.
  Conversion sync/check and residual controls pass at 727 recorded / 712
  discovered surfaces, 301 mapped, 164 residual and 43 blockers, with only the
  three documented retired-path warnings. No behavioral code, metric emission,
  hosted alert, provider, production threshold or operational action exists.
- Implemented the ready operational-health slice with one validated health
  snapshot over the shared SyncHealthSnapshot, explicit nonnegative ages and
  separate connectivity/Auth/subscription/checkpoint/queue/attachment/rejection/
  write/transient components. Online and synchronized remain independent,
  including offline-ready and online-unsynchronized states.
- Added the complete closed client/server/replication/cross-cutting measurement
  registry, seven exact-zero evidence-gated service objectives, twelve grouped/
  rate-limited alert candidates, twelve structurally complete runbook topics
  and twelve performance-budget measurements that remain pending the vertical
  spike with no numeric production threshold.
- Added bounded canonical health/registry evidence and stable refusal for
  invalid time/count, duplicate/missing/reference/policy/evidence, digest,
  canonical and size failures. Every policy remains candidate-only and every
  registry remains evidence-only; no type can emit/acknowledge/resolve an alert,
  execute a runbook or approve a threshold.
- Four focused operational-health tests and all 59 target package tests pass
  locally. Three of four slice obligations pass; exact-commit operational CI
  remains planned, so exactly the two target-only surfaces are `implemented`
  and the broader current observability/performance surfaces remain
  `target_mapped`.
- Exact implementation commit `4fdb363f` passed immutable GitHub Actions run
  `33576448917`: both conversion traceability and isolated-target jobs passed,
  including all 59 target tests, graph/generated-contract checks, macOS and
  generic iOS Simulator builds and clean tracked artifacts. All four
  operational-health obligations and exactly its two target-only surfaces are
  now `verified`; the broader current observability/performance/navigation/test
  surfaces remain `target_mapped`.
- Audited the remaining Phase 1 composition-root and deterministic test-support
  mappings and found one historical scope inconsistency: operation-lifecycle
  had verified `MCPMOD-DAB760104CEE`, `SWIFT-F26052171FEB`, and
  `FILE-F29942C1A7F4` even though its dossier explicitly omitted concrete
  app/MCP integration and a shared target harness. Corrected those three to
  `target_mapped`, removed them from the operation slice, retained only the two
  actual target files as verified, and updated evidence/tracker counts. No code
  or already-passing operation behavior changed.
- Extended conversion discovery to separate target test-support and self-test
  roots, acknowledged only the exact reviewed control-script hash, created two
  comment-only target scaffolds, and passed their deterministic-target-test-
  support ready mapping. The dossier binds validated synthetic environment/
  Principal/Account context, fixed clock/IDs/revisions, immutable scripted
  operation/readiness/failure adapters, canonical restart evidence and stable
  production/provider/tamper refusal to domain, offline and operational tests.
  Current Swift helper `TEST-6A6B0926E2EE` and MCP helper
  `FILE-F29942C1A7F4` remain `target_mapped`; no behavior, package target,
  application link, database, provider, hosted resource, product fixture,
  migration or production operation exists at this ready checkpoint.
- Implemented `LedgerTargetTestSupport` as a separate provider-free Swift
  package product depending only on `LedgerTargetCore`, plus a self-test target
  depending only on those two modules. Neither application project links the
  support module; the graph guard now enforces those edges, scans both support
  roots for provider imports and rejects application/source-project
  contamination.
- Added validated synthetic non-production context, finite domain-separated
  clock/Operation-ID/Entity-ID/revision schedules, immutable Account-scoped
  operation/unresolved/readiness/durability scripts, safe terminal failures,
  lifecycle/order/cross-reference validation and bounded canonical restart
  evidence with digest/tamper/noncanonical/size refusal. Decode reconstructs
  through the environment, schedule, operation-script and Sync-health
  validators rather than trusting Codable structure.
- Four focused test-support tests and all 63 target package tests pass locally,
  as do target graph/contract checks and macOS/generic-iOS-Simulator staging
  builds. Three of four slice obligations pass; exact-commit hosted CI remains
  planned, so exactly its two target-only surfaces are `implemented`. Current
  Swift/MCP helper surfaces remain `target_mapped`; no domain-specific product
  fixture, app/MCP wiring, local database, provider, hosted resource, Firebase
  change, migration or production operation was introduced.
- Exact implementation commit
  `986d633eec2884d1138e0613f9fc35d68ae913c3` passed immutable GitHub Actions
  run `33579458286`: conversion traceability and the isolated-target job both
  passed, including graph/generated-contract checks, all 63 target tests,
  macOS and generic iOS Simulator builds and clean tracked artifacts. All four
  test-support obligations and exactly its two target-only surfaces are now
  `verified`; current Swift/MCP helper surfaces remain `target_mapped`.
- Audited the remaining Phase 1 dependency order and selected
  `validated-target-composition` as the next smallest decision-independent
  technical slice. Exactly two comment-only target scaffolds define the future
  explicit environment/version-bound composition contract and self-tests;
  current Firebase root `SWIFT-88C69E26FBA0`, target app/MCP wiring, provider
  adapters and target-environment package/project surfaces remain unadvanced.
- The ready dossier binds exact Phase 1, composition-root, feature-activation,
  dependency-rule and port-contract requirements to typed dependency/capability
  closure, reference-versus-runtime separation, canonical structural receipt,
  stable refusal and operational graph/source-isolation tests. No behavior,
  package target, application link, SDK, database, hosted service, product
  command, migration or production operation exists at this checkpoint.
- Implemented `LedgerTargetComposition` as a separate provider-free package
  product depending only on `LedgerTargetCore`; its self-test target may also
  depend on `LedgerTargetTestSupport`. Neither application project links the
  module, and the graph guard now enforces exact package edges, scans both new
  roots for provider imports, and rejects premature composition/source-project
  contamination.
- Added exact environment/use/version-bound dependency plans for the generated
  contract catalog, operation queries and Sync health; exact stable
  implementation/capability ownership; explicit reference-versus-runtime
  classes; typed port assembly; stable fail-closed dependency/catalog/
  capability results; and a bounded structural-only canonical receipt that
  restores through the same validators without reconstructing adapters.
- Three focused composition tests and all 66 target package tests pass locally,
  as do the target graph/generated-contract checks and macOS/generic-iOS-
  Simulator staging builds. Three of four slice obligations pass; exact-commit
  hosted CI remains planned, so exactly the two target-only composition
  surfaces are `implemented`. Current Firebase root, app/MCP integration,
  provider adapters and target application project surfaces remain unadvanced.
- Exact implementation commit
  `be88c5b9e42eef90018f84012f5a3e60f9631009` passed immutable GitHub Actions
  run `33581326840`: conversion traceability and isolated-target jobs both
  passed, including graph/generated-contract checks, all 66 target tests,
  macOS and generic iOS Simulator builds and clean tracked artifacts. All four
  composition obligations and exactly its two target-only surfaces are now
  `verified`; current Firebase root, app/MCP/provider integration and target
  application project surfaces remain unadvanced.
- Audited the remaining Phase 1 foundations after composition and selected
  `exact-money-and-domain-identity` as the next smallest decision-independent
  technical slice. Exact signed integer-minor-unit representation, explicit
  currency identity and stable entity ID types are shared prerequisites for
  later product/database/migration slices and do not settle product signs,
  bounds, allocation, tax, rounding, posting or currency policy.
- Created exactly two comment-only target scaffolds in the existing provider-
  free core/test roots and a complete ready dossier covering stable IDs, Money/
  currency, checked arithmetic, restart decoding and malformed/cross-currency/
  overflow refusal. No behavior, product command/read model, app/MCP link,
  database, provider, hosted resource, source transform, migration or
  production operation exists at this checkpoint.
- Implemented the ready exact-money/domain-identity slice with distinct typed
  Client/Project/Item/Invoice/Transaction/Expense/Fee/Space/Attachment IDs,
  exactly-three-uppercase-ASCII-letter CurrencyCode, signed Int64-minor-unit
  Money, checked same-currency amount equality/order/add/subtract/negate, decode-
  through-validation and stable bounded failures.
- Three focused primitive tests and all 69 target package tests pass locally,
  as do the target graph/generated-contract checks and macOS/generic-iOS-
  Simulator staging builds. Canonical restart evidence emits exact integer
  boundaries; fractional numeric input, malformed identity/currency, cross-
  currency operations and every arithmetic overflow edge fail atomically.
- The evidence deliberately does not claim lexical rejection of every exactly
  integral decimal-form JSON token because Swift's standard Int64 decoder may
  accept a spelling such as `1.0`; canonical target encoding remains integer-
  only and the domain never stores or calculates floating-point money.
- Three of four slice obligations pass. Exact-commit hosted CI remains planned,
  so exactly the two target-only primitive surfaces are `implemented`, not
  `verified`. No product sign/bound/currency/rounding/tax policy, app/MCP link,
  database, provider, migration, hosted resource or production operation was
  introduced.
- Exact implementation commit
  `7133aef5a17f946f0f01c084015145592d7bc4ce` passed immutable GitHub Actions
  run `33582602647`: conversion traceability and isolated-target jobs both
  passed, including graph/generated-contract checks, all 69 target tests,
  macOS and generic iOS Simulator builds and clean tracked artifacts. All four
  primitive obligations and exactly its two target-only surfaces are now
  `verified`; all product accounting, current app/MCP, database/provider,
  migration and production surfaces remain unadvanced.
- Audited the remaining Phase 1 boundary after exact primitives and selected
  `client-project-directory-read-contracts` as the first decision-independent
  product-domain foundation. D-006 and the canonical Client spec settle stable
  Account-scoped Client identity and required same-Account Project relationship;
  O-024/O-025 can remain fully open because mutation, reassignment, merge and
  deletion are excluded.
- Created exactly two comment-only target scaffolds in the existing provider-
  free core/test roots and a complete ready dossier for Client/Project summaries,
  exact ID/Account relationship validation, validated duplicate-free local list
  snapshots and the architecture-named `ClientProjectDirectoryQuerying` port.
  Postgres, handlers, Data API, RLS, Sync Streams, media, concrete app/MCP,
  migration, observability and rollout are explicit non-applicabilities.
- Extended only the reviewed Project/Client authority set with the architecture
  files needed by target implementation and mapped the two new target surfaces.
  Sync/check/report pass at 735 recorded / 720 discovered, 309 target-mapped or
  later / 473 target-relevant, 164 residual and 43 blockers, with only the three
  documented retired-path warnings. No behavioral code, source app/MCP surface,
  provider, database, hosted resource, migration or production operation exists
  at this ready checkpoint.
- Implemented the ready Client/Project directory slice with exact nonblank
  display values, finite ordered Client audit time, Account-scoped Client
  summaries, same-Account/exact-Client Project summaries, duplicate-free local
  Client/Project snapshots and the backend-neutral
  `ClientProjectDirectoryQuerying` watch port. Display names remain display-only:
  two equal names never collapse identity or repair a relationship.
- Added three focused domain/restart/refusal tests. They prove ready, partial and
  authoritative-empty local evidence, byte-identical canonical restart,
  construction/decode revalidation, same-name distinct Clients and atomic stable
  refusal for blank names, invalid time, Account/relationship mismatch,
  duplicate identity, incomplete authority and wrong-Account port use.
- All three focused tests and all 72 target tests pass locally, as do the target
  graph/generated-contract checks and macOS/generic-iOS-Simulator staging
  builds. Three of four slice obligations pass; exact-commit hosted CI remains
  planned, so exactly the two target-only directory surfaces are `implemented`.
  Current Project/app/MCP, schema/RLS/Sync/provider and migration surfaces remain
  unadvanced; no Firebase change, hosted resource or production operation was
  introduced.
- Exact implementation commit
  `3c0b58b66e61ab8351d823bf0e0bdcaca7d1c9ff` passed immutable GitHub Actions
  run `33584456794`: conversion traceability and isolated-target jobs both
  passed, including graph/generated-contract checks, all 72 target tests,
  macOS and generic iOS Simulator builds and clean tracked artifacts. All four
  directory obligations and exactly its two target-only surfaces are now
  `verified`; current Project/app/MCP, schema/RLS/Sync/provider and migration
  surfaces remain unadvanced.
- Audited the remaining Phase 1/domain dependency order after Client/Project
  verification and selected `transaction-taxonomy-and-transfer-identity` as the
  smallest next decision-independent accounting foundation. D-001/D-002/D-007
  settle the exact scope-relative Purchase/Return meanings; D-003–D-006 settle
  project-only non-cash Transfer, exact same-Client routing and structural pair
  identity without choosing any open amount, Item, Invoice, Space, lifecycle or
  correction behavior.
- Created exactly two comment-only target scaffolds in the provider-free core/
  test roots and a complete ready dossier for the closed three-type taxonomy,
  explicit Inventory/Project owner scope, compatible record roles, exact-ID
  active-destination route, Operation-bound distinct Transfer pair, canonical
  restart and stable invalid-combination refusal.
- Extended only the reviewed Inventory/Transaction authority set with the
  architecture files needed by target implementation. Postgres, handlers, Data
  API, RLS, Sync Streams, media, concrete app/MCP, legacy enum migration,
  observability and activation are explicit non-applicabilities. D-017 and
  O-002/O-011–O-015/O-028–O-032 remain fully open for excluded effects.
- Sync/check/report pass at 737 recorded / 722 discovered, 311 target-mapped or
  later / 475 target-relevant, 164 residual and 43 blockers, with only the three
  documented retired-path warnings. M0 passes; M1 and M2 remain honestly
  blocked by the unchanged two and 164 prerequisites. No behavioral code,
  source app/MCP surface, provider, database, hosted resource, migration or
  production operation exists at this ready checkpoint.
- Implemented the ready Transaction taxonomy slice with the exact closed
  Purchase/Return/Transfer type, validated Inventory/Project owner scope,
  derived economic meaning, compatible standalone/source/destination roles,
  exact-ID same-Account/same-Client/distinct-Project active-destination route,
  Operation-bound distinct Transfer pair identity, decode revalidation and
  stable bounded failures. Display names carry no route authority.
- Added four focused domain/restart/refusal tests. They prove all valid scope-
  relative meanings, byte-identical canonical restart, equal-name/different-
  Client refusal, Inventory/cross-Account/cross-Client/same-Project/archived-
  destination refusal, duplicate pair refusal, malformed aggregate decoding
  and every stable diagnostic code.
- All four focused tests and all 76 target package tests pass locally, as do
  target graph/generated-contract checks and macOS/generic-iOS-Simulator
  staging builds. Four of five slice obligations pass; exact-commit hosted CI
  remains planned, so exactly the two target-only taxonomy surfaces are
  `implemented`. No writer, money rule, Item/Invoice/Space effect, correction/
  lifecycle behavior, schema/RLS/Sync/provider, app/MCP wiring, legacy import,
  Firebase change, hosted resource, migration or production operation was
  introduced.
- Exact implementation commit
  `031a240a703232216a4efff9686c1516a35a82f4` passed immutable GitHub Actions
  run `33585853504`: conversion traceability and isolated-target jobs both
  passed, including graph/generated-contract checks, all 76 target tests,
  macOS and generic iOS Simulator builds and clean tracked artifacts. All five
  taxonomy obligations and exactly its two target-only surfaces are now
  `verified`; every excluded writer/accounting/provider/migration surface
  remains unadvanced.
- Audited the next Phase 1/domain dependency after exact Client/Project and
  Transfer-route verification and selected
  `transfer-destination-selection-contracts` as the smallest user-meaningful,
  decision-independent read boundary. D-003/D-005/D-006 and the canonical
  picker story settle exact same-Account/same-Client/distinct active-Project
  eligibility without choosing Items, amount, Invoice, Space, tag, correction,
  credit, persistence or provider behavior.
- Created exactly two comment-only target scaffolds in the provider-free core/
  test roots and a complete ready dossier for exact-ID filtering, validated
  candidate routes, source-bound directory/query fingerprints, deterministic
  order, available versus authoritative-empty versus incomplete local evidence,
  canonical restart and stable tamper/refusal behavior.
- Postgres, handlers, Data API, RLS, Sync Streams, local persistence, media,
  concrete app/MCP, source migration, observability and activation are explicit
  nonapplicabilities. Locally valid eligibility is not authorization. No
  behavioral code, current picker/app/MCP surface, Firebase change, provider,
  hosted resource, migration or production operation exists at this ready
  checkpoint.
- Implemented the ready Transfer destination-selection slice with exact
  same-Account/same-Client active-Project filtering, source and Business
  Inventory exclusion, validated direct routes, source-directory/query
  fingerprints, deterministic order, distinct available/authoritative-empty/
  incomplete states, decode revalidation and stable bounded failures. Partial
  or stale evidence may expose an already validated candidate while retaining
  its non-ready quality; an empty partial/stale directory never becomes an
  authoritative empty result.
- Added four focused domain/restart/refusal tests. They prove equal-name/
  different-Client exclusion, directory-order preservation, source/directory
  rebinding, ready/partial/stale evidence, byte-identical restart through the
  local read port, cross-Account/route/duplicate/completeness/fingerprint/
  malformed refusal and every public diagnostic code.
- All four focused tests and all 80 target package tests pass locally, as do
  target graph/generated-contract checks, macOS and generic-iOS-Simulator
  staging builds and diff formatting. Four of five obligations pass; exact-
  commit hosted CI remains planned, so exactly its two target-only surfaces are
  `implemented`. No Item selection, Transfer writer, server authorization,
  schema/RLS/Sync/provider, app/MCP wiring, Firebase change, migration, hosted
  resource or production operation was introduced.
- Exact implementation commit
  `6dc7d0c21ccd8c966b43b02240d14ad9fe79ea92` passed immutable GitHub Actions
  run `33587234037`: conversion traceability and isolated-target jobs both
  passed, including graph/generated-contract checks, all 80 target tests,
  macOS and generic iOS Simulator builds and clean tracked artifacts. All five
  destination-selection obligations and exactly its two target-only surfaces
  are now `verified`; current picker/app/MCP, command, authorization, schema/
  RLS/Sync/provider and migration surfaces remain unadvanced.
- Audited the remaining Phase 1 dependency graph after exact Money,
  Purchase/Return taxonomy and Transfer destination verification and selected
  `non-item-receipt-line-reconstruction-contracts` as the smallest next
  decision-independent accounting value boundary. D-016 settles stable ordered
  embedded line identity/shape and exact reconstruction math without choosing
  billing, rounding, Item tax/basis or Transaction posting behavior.
- Created exactly two comment-only target scaffolds in the provider-free core/
  test roots and a complete ready dossier for stable ID/source wording,
  positive Money magnitude, increase/decrease effect, optional non-arithmetic
  quantity evidence, duplicate-free order, standalone Purchase/Return scope,
  exact increase/decrease/net/reconstructed/variance totals, canonical restart
  and stable classification/Account/currency/overflow/tamper refusal.
- O-008/O-030/O-031/O-032 remain fully open and outside the slice. Postgres,
  handlers, Data API, RLS, Sync Streams, local persistence, media, current app/
  MCP, source decoding/migration, observability and activation are explicit
  nonapplicabilities. No behavioral code, Firebase change, provider, hosted
  resource, migration or production operation exists at this ready checkpoint.
- Sync/check/report pass at 741 recorded / 726 discovered surfaces, 315 target-
  mapped or later / 479 target-relevant, 164 residual and 43 blockers, with only
  the three documented retired-path warnings. M0 passes; M1 and M2 remain
  honestly blocked by the unchanged two and 164 prerequisites.
- The existing 80 target tests, target graph/generated-contract checks, macOS
  and generic-iOS-Simulator staging builds and diff formatting all pass with the
  two comment-only receipt scaffolds. The receipt obligations remain planned;
  no executable receipt test or behavioral implementation is claimed at ready.
- Implemented only the ready provider-free receipt boundary: distinct line ID,
  source-preserving nonblank wording, positive exact-Money magnitude, increase/
  decrease effect, optional non-arithmetic quantity, duplicate-free source
  order, standalone Purchase/Return classification, exact increase/decrease/
  net/reconstructed/variance evidence, and a canonical SHA-256 fingerprint
  binding identity, classification, inputs, order and derived totals.
- Added four deterministic receipt tests. BLVD-like Purchase evidence exactly
  reconstructs 504,772 minor units; Wayfair-like Return evidence retains an
  exact negative-one-minor-unit variance without declaring completion. Tests
  also prove every reachable aggregation/reconstruction/variance overflow,
  mixed-currency refusal, byte-identical restart, stable diagnostics and atomic
  malformed/duplicate/reordered/derived-total/fingerprint tamper refusal.
- All four focused receipt tests and all 84 target package tests pass locally,
  as do target graph/generated-contract checks, macOS and generic-iOS-Simulator
  staging builds and diff formatting. `RECEIPT-TEST-001` through `-004` pass;
  exact-commit hosted `RECEIPT-TEST-005` remains planned, so exactly the two
  receipt surfaces are `implemented`, not `verified`.
- The receipt fingerprint is deterministic corruption/order evidence rather
  than authorization or proof of external authenticity. No completion verdict,
  Transaction writer/posting/sign policy, Item basis/tax allocation, billing,
  schema/RLS/Sync/provider, app/MCP, migration, Firebase change, hosted resource
  or production operation was introduced; O-008/O-030/O-031/O-032 remain open.
- Exact implementation commit
  `594aec1e68747fefe9fffd6a80d550c55d0c555d` passed immutable GitHub Actions
  run `33588870600`: conversion traceability passed in 11 seconds and the
  isolated-target job passed in 1 minute 31 seconds with all 84 target tests,
  graph/generated-contract checks, macOS and generic-iOS-Simulator builds and
  clean tracked artifacts. All five receipt obligations and exactly its two
  target-only surfaces are now `verified`; every excluded writer, current app/
  MCP, provider, migration and production surface remains unadvanced.
- Audited the remaining mapped Phase 1 product boundaries and selected
  `project-item-accounting-section-contracts` as the smallest next user-visible,
  decision-independent Item slice. D-019/D-022/D-023 and the canonical Item
  spec settle relationship-derived Unaccounted For / Accounted For state, one
  physical Item identity and Space/detail independence without choosing Item
  creation/Link, occurrence persistence, credit settlement or provider design.
- Created exactly two comment-only target scaffolds in the provider-free core/
  test roots and a complete ready dossier for exact Account/Project/Item-bound
  client-paid Purchase and billable charge/credit occurrence evidence,
  relationship-derived state, Unaccounted For first / Accounted For second,
  deterministic order, authoritative-empty versus incomplete/partial/stale
  local evidence, explicit unresolved rows when relationship absence is not
  authoritative, canonical restart and stable cross-scope/duplicate/tamper
  refusal.
- Extended only the reviewed Item-creation authority set with the Phase 1
  domain/read-model architecture files required by these two target surfaces.
  O-003/O-007/O-015/O-016/O-021/O-023/O-027 remain fully open and outside the
  slice. Postgres, handlers, Data API, RLS, Sync Streams, local persistence,
  media, current app/MCP, source migration, observability and activation are
  explicit nonapplicabilities.
- Sync/report pass at 743 recorded / 728 discovered surfaces, 317 target-mapped
  or later / 481 target-relevant, 164 residual and 43 blockers, with only the
  three documented retired-path warnings. No behavioral code, Firebase change,
  provider, hosted resource, migration or production operation exists at this
  ready checkpoint.
- Implemented only the ready provider-free Project Item accounting-section
  boundary: distinct Purchase-relationship/occurrence IDs, exact Account/
  Project/Client/Item-bound relationship evidence, charge/credit occurrences
  across available/live/frozen phases, relationship-derived product state, two
  deterministic ordered sections, explicit unresolved incomplete-local rows,
  local readiness/version/time and a canonical evidence fingerprint.
- A present qualifying relationship may prove Accounted For from partial/stale
  evidence. Missing relationship evidence proves Unaccounted For only when the
  relationship working set is authoritative; otherwise the Item stays outside
  both product sections as `relationshipEvidenceIncomplete`. Space never changes
  the resolution. Frozen occurrence evidence carries no amount or collection-
  transaction settlement semantics and therefore does not choose O-003.
- Added four deterministic accounting-section tests. They prove standalone
  current-Project Purchase classification, charge/credit and available/live/
  frozen qualification, one Item identity, source-order sectioning, Space
  independence, authoritative-empty versus incomplete/partial/stale truth,
  byte-identical restart through the scoped query port, every stable diagnostic,
  and atomic scope/Item/duplicate/phase/derived/fingerprint/malformed refusal.
- All four focused tests and all 88 target package tests pass locally, as do
  target graph/generated-contract checks, macOS and generic-iOS-Simulator
  staging builds and diff formatting. `ITEMACCOUNT-TEST-001` through `-004`
  pass; exact-commit hosted `ITEMACCOUNT-TEST-005` remains planned, so exactly
  the two Item-accounting surfaces are `implemented`, not `verified`.
- No Item writer/Link, occurrence persistence or transition, amount/category/
  budget effect, credit settlement, schema/RLS/Sync/provider, current app/MCP,
  source migration, Firebase change, hosted resource or production operation
  was introduced; O-003/O-007/O-015/O-016/O-021/O-023/O-027 remain open.
- Exact implementation commit
  `92e0b565d02f9a2ad3f96f195327bc2b12ae0e56` passed immutable GitHub Actions
  run `33591275648`: conversion traceability passed in 11 seconds and the
  isolated-target job passed in 1 minute 26 seconds with all 88 target tests,
  graph/generated-contract checks, macOS and generic-iOS-Simulator builds and
  clean tracked artifacts. All five Item-accounting obligations and exactly its
  two target-only surfaces are now `verified`; every excluded writer, current
  app/MCP, provider, migration and production surface remains unadvanced.
- Audited the attachment/offline boundary against the reviewed media dossier,
  offline contract, adapter ports and Phase 1 architecture and selected
  `attachment-capture-and-local-durability-receipt` as the smallest honest next
  technical slice. Stable ID/scope/byte-evidence/receipt semantics are settled;
  actual encrypted filesystem persistence and provider behavior are not.
- Created exactly two comment-only target scaffolds and a complete ready dossier
  for non-Codable raw capture input, exact environment/Principal/Account/parent
  binding, opaque local-object identity, positive byte count, SHA-256 evidence,
  canonical path-free receipt, a narrow capture-store port and stable refusal.
- O-023 remains open because the slice exposes no detach/delete/retention
  operation. A-003/A-004/A-016, O-022, SPIKE-MED-001, content/size/derivative
  policy, physical local durability, upload/display/provider, app/MCP,
  migration and production behavior remain explicitly outside the boundary.
- Implemented only the ready provider-free attachment receipt boundary:
  non-Codable raw capture bytes, stable Attachment and opaque local-object IDs,
  exact environment/Principal/Account/parent scope, integer timestamp, positive
  byte count/SHA-256 matching, canonical path-free fingerprinted receipt, a
  narrow capture-store port and closed bounded failures.
- Added four deterministic tests for matching scope/byte evidence, Attachment
  identity independent of opaque local-object identity, raw-byte/path/URL
  exclusion, byte-identical structured restart, every scope/identity/byte/
  malformed/tamper rejection and no false-success receipt from a failing test
  adapter. Four focused/all 92 target tests, graph/contracts and both staging
  builds pass locally.
- `ATTACHCAP-TEST-001` through `-004` pass locally. Deterministic receipt tests
  are not physical encrypted-filesystem or process/device-restart evidence.
- Exact implementation commit
  `1792a86292d1553a11d78ff977736f63f12cbbe4` passed immutable GitHub Actions
  run `33593116980`: conversion traceability passed in 8 seconds and the
  isolated-target job passed in 1 minute 33 seconds with all 92 target tests,
  graph/generated-contract checks, macOS and generic iOS Simulator builds and
  clean tracked artifacts. All five attachment obligations and exactly its two
  target-only surfaces are now `verified`; every excluded filesystem/provider,
  current app/MCP, migration and production surface remains unadvanced.
- Audited the next Phase 1 dependency graph and selected
  `client-creation-operation-contracts` as the smallest user-meaningful command
  needed before Project setup. D-006 and the canonical Client spec settle one
  stable Account-scoped Client ID and display-name non-authority; O-025 remains
  open because rename/archive/merge/reassignment are excluded.
- Created exactly two comment-only target scaffolds and a complete ready dossier
  for exact Account/actor/contract/Operation/Client/name binding, the shared
  operation fingerprint/receipt/replay lifecycle, canonical restart, a narrow
  Client creation operation port and stable mismatch/tamper/local-failure
  refusal. No behavioral code or executable Client test exists at ready.
- Postgres, handlers, Data API grants, RLS, Sync Streams, physical local
  durability, membership authorization, Auth/provider choice, current/target
  app/MCP, source migration, hosted resources and production remain explicit
  nonapplicabilities.
- Ready-gate sync/check and capability/query/residual controls pass at 747
  recorded / 732 discovered surfaces, 321 mapped / 164 residual / 43 blockers;
  M0 passes, M1/M2 retain the expected 2/164 blocks, and the existing 92 target
  tests, graph/contracts, both staging builds and diff formatting pass with no
  executable Client-creation behavior claimed.
- Implemented only the ready provider-free Client creation boundary: an exact
  Account/actor/contract/Client/name/time draft, minimal typed payload,
  precondition-free shared operation envelope, derived Client subject and
  fingerprint, receipt validator, narrow operation port and closed failures.
- Added four deterministic tests for same-name/different-ID identity, exact
  command scope, byte-identical structured restart, provider/path/credential
  exclusion, every binding/precondition/subject/fingerprint/receipt/malformed
  refusal and shared OperationJournal replay/same-ID-changed-payload behavior.
- Four focused/all 96 target tests, graph/contracts and both staging builds pass
  locally. `CLIENTCREATE-TEST-001` through `-004` pass; exact-commit hosted
  `CLIENTCREATE-TEST-005` remains planned, so exactly the two Client-creation
  surfaces are `implemented`, not `verified`.
- No Client row, authoritative apply, physical local durability, membership
  authorization, Client lifecycle/correction, Project setup/reassignment,
  schema/RLS/Sync/Auth/provider, current/target app/MCP, migration, hosted
  resource or production operation was introduced; O-025 remains open.
- Exact implementation commit
  `3b837af34bbbde9e7c4b6707f6366dc88d236957` passed immutable GitHub Actions
  run `33595993615`: conversion traceability passed in 10 seconds and the
  isolated-target job passed in 1 minute 50 seconds with all 96 target tests,
  graph/generated-contract checks, macOS and generic iOS Simulator builds and
  clean tracked artifacts. All five Client-create obligations and exactly its
  two target-only surfaces are now `verified`; every excluded server,
  authorization, provider, migration and production surface remains unadvanced.
- Audited the next Phase 1 dependency graph and selected
  `project-setup-operation-contracts` as the next smallest user-meaningful
  operation. D-006 settles stable Account-scoped Client identity; the reviewed
  capability contract and target architecture settle one Project setup intent
  with existing/new Client selection and the complete selected-category state.
- Created exactly two comment-only target scaffolds and a complete ready dossier
  for stable Project/Client identity, validated Project name/exact optional
  description, canonical duplicate-free category selection, absent/null/zero
  allocation, shared operation fingerprint/receipt/replay and stable refusal.
  No behavioral Project-setup code or executable test exists at ready.
- Corrected the target allocation guidance to retain exact non-negative
  integer-currency Money without inheriting the source UI's arbitrary 32-bit
  maximum. Empty category selection remains representable; category order is
  canonical rather than a business identity.
- Kept hero media entirely outside CreateProject under the separately verified
  attachment-capture receipt lifecycle. Media failure cannot invalidate a
  valid Project, and this slice makes no attachment-reference/upload claim.
- O-023/O-024/O-025/O-026 remain open: the slice neither changes attachment
  retention, deletes/edits/reassigns a Project, merges a Client nor mutates a
  shared category definition. Local command validation is not authorization.
- Postgres, handlers, Data API grants, RLS, Sync Streams, physical local
  durability, Auth/provider choice, current/target app/MCP, source migration,
  hosted resources and production remain explicit nonapplicabilities.
- Ready-gate sync/check and capability/query/residual controls pass at 749
  recorded / 734 discovered surfaces, 323 mapped / 164 residual / 43 blockers;
  M0 passes, M1/M2 retain the expected 2/164 blocks, and the existing 96 target
  tests, graph/contracts, both staging builds and diff formatting pass with no
  executable Project-setup behavior claimed.
- Implemented only the ready provider-free Project setup boundary: stable
  existing/new Client selection, distinct BudgetCategoryID, exact non-negative
  nullable Money, canonical duplicate-free category state, Account/actor/
  contract/Project/name/description/time draft, precondition-free shared
  operation envelope, derived Project subject/fingerprint, receipt validator,
  narrow operation port and closed stable failures.
- Added four deterministic tests for stable existing/new Client and Project
  identity, empty/absent/null/zero category state, order-independent canonical
  encoding, byte-identical structured restart, provider/media/path/credential
  exclusion, every invalid/binding/precondition/subject/fingerprint/receipt/
  malformed refusal and shared OperationJournal replay/mismatch behavior.
- Four focused/all 100 target tests, graph/contracts and both staging builds pass
  locally. `PROJECTSETUP-TEST-001` through `-004` pass; exact-commit hosted
  `PROJECTSETUP-TEST-005` remains planned, so exactly the two Project-setup
  surfaces are `implemented`, not `verified`.
- No Project/Client/category row, authoritative apply, physical local
  durability, membership/category authorization, shared reference mutation,
  Project edit/reassignment/archive/delete, hero media, schema/RLS/Sync/Auth/
  provider, current/target app/MCP, migration, hosted resource or production
  operation was introduced; O-023/O-024/O-025/O-026 remain open.
- Exact implementation commit
  `8d8cd30f3b2ff8f582b8117f4799f732cca854a5` passed immutable GitHub Actions
  run `33599214652`: conversion traceability passed in 8 seconds and the
  isolated-target job passed in 2 minutes 53 seconds with all 100 target tests,
  graph/generated-contract checks, macOS and generic iOS Simulator builds and
  clean tracked artifacts. All five Project-setup obligations and exactly its
  two target-only surfaces are now `verified`; every excluded server,
  authorization, media, provider, migration and production surface remains
  unadvanced.
- Audited the next Phase 1 dependency graph and selected
  `project-archive-operation-contracts` as the next smallest user-meaningful
  operation. The reviewed capability contract defines ArchiveProject as a
  distinct always-safe history-preserving intent, and the exact target mapping
  already names its expected Project revision and shared operation receipt.
- Created exactly two comment-only target scaffolds and a complete ready dossier
  for stable Project identity, finite Account/actor/contract/time binding, one
  exact same-subject expected-revision precondition, shared operation
  fingerprint/receipt/replay and stable mismatch/tamper/local-failure refusal.
  No behavioral Project-archive code or executable test exists at ready.
- Explicitly excluded a generic lifecycle toggle, restore/unarchive and physical
  delete. O-024 remains open because no delete/discard/tombstone behavior is
  chosen; O-025 remains open because no Client relation/correction is carried.
- Postgres, authoritative history preservation, handlers, Data API grants, RLS,
  Sync Streams, physical local durability, authorization, Auth/provider choice,
  current/target app/MCP, source migration, hosted resources and production
  remain explicit nonapplicabilities.
- Ready-gate sync/check and capability/query/residual controls pass at 751
  recorded / 736 discovered surfaces, 325 mapped / 164 residual / 43 blockers;
  M0 passes, M1/M2 retain the expected 2/164 blocks, and the existing 100 target
  tests, graph/contracts, both staging builds and diff formatting pass with no
  executable Project-archive behavior claimed.
- Implemented only the ready provider-free Project archive boundary: typed
  expected revision, exact Account/actor/contract/Project/time draft, one-field
  archive payload, exactly one same-Project expected-revision precondition,
  shared operation envelope/fingerprint/receipt, narrow operation port and
  closed stable failures.
- Added four deterministic tests for exact archive-only scope, stable Project
  identity, canonical byte-identical restart, changed Account/actor/contract/
  payload/revision-subject/revision-value/precondition-count/command-subject/
  fingerprint/receipt/malformed refusal and shared OperationJournal replay/
  changed-Project-or-revision mismatch behavior.
- Four focused/all 104 target tests, graph/contracts and both staging builds pass
  locally. `PROJECTARCHIVE-TEST-001` through `-004` pass; exact-commit hosted
  `PROJECTARCHIVE-TEST-005` remains planned, so exactly the two Project-archive
  surfaces are `implemented`, not `verified`.
- No lifecycle row, authoritative archive or history-preservation result,
  physical local durability, membership/Project authorization, restore/delete/
  edit/reassignment, Client/category/media/accounting mutation, schema/RLS/
  Sync/Auth/provider, current/target app/MCP, migration, hosted resource or
  production operation was introduced; O-024/O-025 remain open.
- Exact implementation commit
  `7b30bd25a60f2a2a751c219b7745e0ec524f31b8` passed immutable GitHub Actions
  run `33601516220`: conversion traceability passed in 9 seconds and the
  isolated-target job passed in 2 minutes 16 seconds with all 104 target tests,
  graph/generated-contract checks, macOS and generic iOS Simulator builds and
  clean tracked artifacts. All five Project-archive obligations and exactly its
  two target-only surfaces are now `verified`; every excluded lifecycle-row,
  server, authorization, history-preservation, provider, migration and
  production surface remains unadvanced.
- Audited the next Phase 1 dependency graph and selected
  `budget-category-reference-read-contracts` because Project setup, Project
  category configuration and Item/Transaction routing depend on stable category
  identity/type/lifecycle/order before their later operations can be safe.
- Created exactly two comment-only target scaffolds and a complete ready dossier
  for stable Account/category identity, bounded display name, canonical general/
  itemized/fee kind, active/archived and system state, overall-budget exclusion,
  unique presentation order/revision, active/non-system/itemized eligibility and
  shared local-list readiness/restart/refusal.
- Kept financial visibility as an already-authorized visible subset: the local
  contract neither authorizes rows nor exposes hidden fee-category counts.
  O-026 remains open because no category Create/Update/Archive/Reorder command or
  administration capability exists; Project allocation configuration is also
  excluded.
- Ready-gate sync/check and capability/query/residual controls pass at 753
  recorded / 738 discovered surfaces, 327 mapped / 164 residual / 43 blockers;
  M0 passes, M1/M2 retain the expected 2/164 blocks, and the existing 104 target
  tests, graph/contracts, both staging builds and diff formatting pass with no
  executable budget-category reference behavior claimed.
- Implemented only the ready provider-free budget-category reference boundary:
  bounded normalized display name, exact general/itemized/fee kind, stable
  Account/category identity, lifecycle/system/overall-budget-exclusion/order/
  revision evidence, active/non-system/itemized eligibility, Account-exact
  local-list snapshots, visible-count privacy, canonical restart, one narrow
  query port and closed stable failures.
- A visible count is valid only when it equals the already-authorized rows
  actually present. The local contract cannot reveal hidden fee rows or counts,
  authorize a download or infer complete Account data beyond its explicit
  readiness evidence.
- Added four deterministic tests for exact visible category semantics, ready/
  partial/stale/authoritative-empty restart, invalid name/type/revision/time,
  scope/identity/name/order/count/malformed refusal and exact-Account port
  failure safety. Four focused/all 108 target tests in 24 suites pass locally,
  as do conversion/capability/query/residual controls, M0, graph/contracts,
  macOS and generic iOS Simulator staging builds and diff formatting.
- `CATEGORYREFERENCE-TEST-001` through `-004` pass locally. Exact-commit hosted
  `CATEGORYREFERENCE-TEST-005` remains planned, so exactly the two category-
  reference surfaces are `implemented`, not `verified`.
- No hidden fee visibility, category administration, Project allocation or
  budget calculation, physical local persistence, server/download
  authorization, schema/RLS/Sync/Auth/provider, current/target app/MCP, source
  migration, hosted resource or production operation was introduced. O-026
  remains open and unchanged.
- Exact implementation commit
  `713dcf579bc8634b6a429da2fa1e2a431b722b57` passed immutable GitHub Actions
  run `33606006684`: conversion traceability passed in 13 seconds and the
  isolated-target job passed in 1 minute 59 seconds with all 108 target tests,
  graph/generated-contract checks, macOS and generic iOS Simulator builds and
  clean tracked artifacts. All five category-reference obligations and exactly
  its two target-only surfaces are now `verified`; every excluded mutation,
  server/authorization, provider, migration and production surface remains
  unadvanced.
- Audited the remaining Phase 1 Project/reference dependency graph and selected
  `project-category-configuration-read-contracts` as the next smallest complete
  user outcome. The verified Project setup contract already preserves the
  complete selected-category set, and the verified budget-category reference
  contract supplies stable visible category identity/type/lifecycle/order.
- Created exactly two comment-only target scaffolds and a complete ready dossier
  for exact Account/Project/category scope, one configuration revision,
  no-relationship versus enabled-without-allocation versus enabled-with-explicit-
  zero/positive Money, explicit incomplete relationship evidence, authorized
  visible-count privacy, shared local readiness/restart and one narrow read port.
- The slice cannot calculate paid/unpaid/recognized budget values or import
  current cached/Transaction-only spend as authority. It exposes no shared
  category or Project configuration writer; O-026 remains fully open and
  unchanged.
- Postgres, handlers, Data API grants, RLS, Sync Streams, physical local
  durability, financial authorization, Auth/provider choice, current/target
  app/MCP, source migration, hosted resources and production remain explicit
  nonapplicabilities. No behavioral code or executable Project configuration
  test exists at ready.
- The ready gate passes at 755 recorded / 740 discovered surfaces, 329 mapped /
  164 residual / 43 blockers. Conversion, capability, query, residual, M0,
  target-environment and generated-contract controls pass; M1/M2 retain their
  expected 2/164 blockers. All existing 108 target tests in 24 suites, macOS and
  generic iOS Simulator staging builds, and diff formatting pass while the two
  scaffolds remain comment-only.
- Exact ready commit `0a34682693d13a0432d0fde54c9254d98641b0a4`
  passed immutable Actions run `33608479448`: traceability passed in 7 seconds,
  and the isolated target job passed in 2 minutes 54 seconds with all 108 then-
  existing tests, graph/contracts, both staging builds and clean artifacts.
- Implemented only the frozen provider-free Project category configuration read
  boundary: exact Account/Project/configuration revision, closed no-relationship/
  enabled-null/enabled-zero-or-positive/incomplete states, verified category
  evidence, visible-count privacy, canonical local restart, completeness-aware
  refusal, stable failures and one narrow read port.
- Added four deterministic tests covering exact relationship/allocation truth,
  ready/partial/stale/authoritative-empty restart, malformed/negative/scope/
  duplicate/count/completeness refusal and exact Account/Project port failure
  safety. Four focused/all 112 target tests in 25 suites pass locally, as do
  graph/contracts, target environment, macOS and generic iOS Simulator staging
  builds and diff formatting.
- `PROJECTCATEGORY-TEST-001` through `-004` pass locally. Exact-implementation-
  commit hosted `PROJECTCATEGORY-TEST-005` remains planned, so exactly the two
  Project category configuration surfaces are `implemented`, not `verified`.
- No budget/spend calculation, hidden row/count, category or Project
  configuration writer, physical persistence, server/download authorization,
  schema/RLS/Sync/Auth/provider, current/target app/MCP, source migration,
  hosted resource or production operation was introduced. O-026 remains open
  and unchanged.
- Exact implementation commit
  `40d20efb9fce0873008b29fec783f2bc28ba30c0` passed immutable GitHub Actions
  run `33610276267`: conversion traceability passed in 10 seconds and the
  isolated-target job passed in 1 minute 54 seconds with all 112 target tests,
  graph/generated-contract checks, macOS and generic iOS Simulator builds and
  clean tracked artifacts. All five Project category configuration obligations
  and exactly its two target-only surfaces are now `verified`; every excluded
  budget, mutation, authorization, provider, migration and production surface
  remains unadvanced.
- Audited the remaining Phase 1 Project/Client/reference dependency graph and
  selected `client-rename-operation-contracts` as the next smallest complete
  user outcome. Stable Client identity, creation and directory reads are already
  verified, and the canonical Client spec settles mutable current display text
  without making name an identity key.
- Deliberately did not select Client archive: whether active Projects block that
  operation remains part of the unapproved O-024/O-025 lifecycle packet. Client
  merge and Project reassignment also remain excluded. A rename carries no
  archive/delete/merge/reassignment or dependency-policy input.
- Created exactly two comment-only target scaffolds and a complete ready dossier
  for exact Account/actor/contract/Operation/Client/new-name/time binding, one
  same-subject expected Client revision, derived subject/fingerprint, canonical
  restart, atomic rebound refusal and one narrow rename port.
- The ready gate passes at 757 recorded / 742 discovered surfaces, 331 mapped /
  164 residual / 43 blockers. Conversion, capability, query, residual, M0,
  target-environment and generated-contract controls pass; M1/M2 retain their
  expected 2/164 blockers. All existing 112 target tests in 25 suites, macOS and
  generic iOS Simulator staging builds, and diff formatting pass while the two
  scaffolds remain comment-only.
- No executable Client rename, Client row/current-Project projection, frozen-
  history rewrite, physical persistence, server authorization/revision apply,
  schema/RLS/Sync/Auth/provider, current/target app/MCP, source migration,
  hosted resource or production operation exists at ready. O-024/O-025 remain
  open and unchanged.
- Implemented only the frozen provider-free Client rename boundary: validated
  stable Client/new-display-name intent, one exact Client revision, shared
  Account/actor/contract/Operation/time/subject/precondition/fingerprint/
  receipt lifecycle, decode-through-validation and one narrow operation port.
- Added four deterministic tests covering exact payload/command shape,
  byte-identical restart, malformed/rebound/tampered refusal, shared journal
  replay/mismatch behavior and no false receipt from a failing port. Four
  focused/all 116 target tests in 26 suites pass locally, as do target
  environment/generated-contract controls, macOS and generic iOS Simulator
  staging builds, conversion/capability/query/residual controls, M0 and diff
  formatting. M1/M2 retain exactly their expected 2/164 blockers.
- `CLIENTRENAME-TEST-001` through `-004` pass locally. Exact-implementation-
  commit hosted `CLIENTRENAME-TEST-005` remains planned, so exactly the two
  Client rename surfaces are `implemented`, not `verified`.
- No Client row/current-Project projection, frozen-history rewrite, archive/
  delete/merge/reassignment, physical persistence, authoritative authorization
  or revision apply, schema/RLS/Sync/Auth/provider, app/MCP, source migration,
  hosted resource or production operation was introduced. O-024/O-025 remain
  open and unchanged.
- Exact implementation commit
  `3282f8e38784e96d46e34f94fb045997f3f19bd3` passed immutable GitHub Actions
  run `33612902860`: conversion traceability passed in 9 seconds and the
  isolated-target job passed in 2 minutes 20 seconds with all 116 target tests,
  graph/generated-contract checks, macOS and generic iOS Simulator builds and
  clean tracked artifacts. All five Client rename obligations and exactly its
  two target-only surfaces are now `verified`; every excluded lifecycle,
  history, provider, migration and production surface remains unadvanced.
- Audited the remaining Phase 1 Project/Client/reference dependency graph and
  selected `project-rename-operation-contracts` as the next smallest complete
  user outcome. Stable Project/Client identity, Project setup/archive and
  directory reads are already verified; the canonical relationship and reviewed
  capability contract settle name-as-display semantics without making name an
  identity, relationship or authorization key.
- Deliberately did not combine Project rename with description/category/media
  edits or Client reassignment. Those are distinct operations; O-024/O-025
  remain open for physical delete and Client correction/merge/reassignment.
- Created exactly two comment-only target scaffolds and a complete ready dossier
  for exact Account/actor/contract/Operation/Project/new-name/time binding, one
  same-subject expected Project revision, derived subject/fingerprint, canonical
  restart, atomic rebound refusal and one narrow rename port.
- The ready gate passes at 759 recorded / 744 discovered surfaces, 333 mapped /
  164 residual / 43 blockers. Conversion, capability, query, residual, M0,
  target-environment and generated-contract controls pass; M1/M2 retain their
  expected 2/164 blockers. All existing 116 target tests in 26 suites, macOS and
  generic iOS Simulator staging builds, and diff formatting pass while the two
  scaffolds remain comment-only.
- No executable Project rename, Project row/downstream projection, Client/
  description/category/media/history/lifecycle change, physical persistence,
  server authorization/revision apply, schema/RLS/Sync/Auth/provider,
  current/target app/MCP, source migration, hosted resource or production
  operation exists at ready. O-024/O-025 remain open and unchanged.
- Exact ready commit `18ab228379e9d81db1dc35c16bf6eecc867b64cc`
  passed immutable GitHub Actions run `33614187250`: conversion traceability
  passed in 9 seconds and the isolated-target job passed in 3 minutes 1 second
  with all 116 then-existing target tests, graph/generated-contract checks,
  macOS and generic iOS Simulator builds and clean tracked artifacts.
- Implemented only the frozen provider-free Project rename boundary: validated
  stable Project/new-display-name intent, one exact Project revision, shared
  Account/actor/contract/Operation/time/subject/precondition/fingerprint/
  receipt lifecycle, decode-through-validation and one narrow operation port.
- Added four deterministic tests covering exact payload/command shape,
  byte-identical restart, malformed/rebound/tampered refusal, shared journal
  replay/mismatch behavior and no false receipt from a failing port. Four
  focused/all 120 target tests in 27 suites pass locally, as do target
  environment/generated-contract controls, macOS and generic iOS Simulator
  staging builds, conversion/capability/query/residual controls, M0 and diff
  formatting. M1/M2 retain exactly their expected 2/164 blockers.
- `PROJECTRENAME-TEST-001` through `-004` pass locally. Exact-implementation-
  commit hosted `PROJECTRENAME-TEST-005` remains planned, so exactly the two
  Project rename surfaces are `implemented`, not `verified`.
- No Project row/downstream projection, Client/description/category/media/
  history/lifecycle change, physical persistence, authoritative authorization
  or revision apply, schema/RLS/Sync/Auth/provider, app/MCP, source migration,
  hosted resource or production operation was introduced. O-024/O-025 remain
  open and unchanged.
- Exact implementation commit `7f395bbe99bdd4a564eef1fdbee664cb03519595`
  passed immutable GitHub Actions run `33615145061`: conversion traceability
  passed in 8 seconds and the isolated-target job passed in 2 minutes 11 seconds
  with all 120 target tests, graph/generated-contract checks, macOS and generic
  iOS Simulator builds and clean tracked artifacts. All five Project rename
  obligations and exactly its two target-only surfaces are now `verified`;
  every excluded relationship, details, lifecycle, provider, migration and
  production surface remains unadvanced.
- Audited the next Phase 1 Project/Client/reference dependency and selected
  `project-note-read-contracts` as the smallest complete decision-independent
  outcome. The reviewed target contract already settles stable note identity,
  creator/creation/source and revision/edit/tombstone evidence, deterministic
  bounded order and explicit incomplete local-history truth.
- Deliberately excluded Add/Edit/Remove commands, edit/delete role policy,
  physical persistence, RLS/Sync, indexed search, app/MCP wiring and Firebase
  note migration. The read values consume only already-authorized local rows and
  cannot make any of those decisions implicitly.
- Created exactly two comment-only target scaffolds plus one reciprocal seven-
  requirement/five-verification dossier. The planned implementation binds exact
  Account/Project/note scope, active-versus-tombstone content, immutable creator/
  creation/source evidence, revision and paired edit audit, newest-first
  `(createdAt,id)` order, structured continuation, local query identity and
  complete/incomplete Project-history readiness.
- The ready checkpoint records 761 surfaces, including 746 currently
  discovered, with 335 of 499 target-relevant surfaces mapped or later and 164
  residual surfaces under 43 explicit blockers. No executable Project-note
  behavior, provider connection, hosted resource, production read/mutation,
  app change, migration, deployment or cutover exists.
- Conversion, capability, query, residual, M0, target-environment and generated-
  contract checks pass. M1/M2 retain their expected 2/164 blockers. All 120
  existing target tests in 27 suites, macOS and generic iOS Simulator staging
  builds, generated target-project stability and diff formatting pass while
  both Project-note scaffolds remain comment-only.
- Exact ready commit `58319f2a89a81dd39dd8d624dba481b7d5b17abe`
  passed immutable GitHub Actions run `33616981355`: conversion traceability
  passed in 7 seconds and the isolated-target job passed in 2 minutes 22 seconds
  with all 120 then-existing tests, graph/generated-contract checks, macOS and
  generic iOS Simulator builds and clean tracked artifacts.
- Implemented only the frozen provider-free Project-note read boundary: stable
  Account/Project/note identity, validated text/source, immutable creator/
  creation evidence, revision and paired edit audit, non-content-bearing
  tombstones, bounded typed requests, derived query fingerprints, structured
  `(createdAt,id)` cursors, newest-first page validation, explicit complete/
  incomplete Project-history truth and one narrow read port.
- Added four deterministic tests covering active/edited/tombstoned values,
  same-time ID tie-breaks, bounded continuation, complete/partial/stale/empty
  restart, malformed/scope/audit/order/fingerprint/readiness refusal, exact
  request matching and no false page from a failing port.
- `PROJECTNOTE-TEST-001` through `-004` pass locally. Exact-implementation-
  commit hosted `PROJECTNOTE-TEST-005` remains planned, so exactly the two
  Project-note target surfaces are `implemented`, not `verified`.
- No note authorization/mutation, physical local persistence, schema/RLS/Sync/
  Auth/provider behavior, app/MCP/search wiring, source note migration, hosted
  resource or production operation was introduced.
- Exact implementation commit
  `b421f41948a23fa0918b5e33c0a4d436e5b87080` passed immutable GitHub Actions
  run `33618364544`: conversion traceability passed in 12 seconds and the
  isolated-target job passed in 2 minutes 21 seconds with all 124 target tests,
  graph/generated-contract checks, macOS and generic iOS Simulator builds and
  clean tracked artifacts. All five Project-note obligations and exactly its
  two target-only surfaces are now `verified`; every excluded mutation,
  provider, migration and production surface remains unadvanced.
- Exact verification-document commit `0b811864504a90294beefcf6e34b6e9adc73dfda`
  passed immutable GitHub Actions run `33618750372`; both conversion
  traceability and the isolated target environment completed successfully.
- Audited the next Phase 1 dependency and selected
  `project-note-creation-operation-contracts` as the smallest complete
  decision-independent operation. It owns only AddProjectNote intent; edit,
  remove and their role/revision policy remain separate and unimplemented.
- Froze seven exact requirements over stable Account/Project/note identity,
  nonblank text, requested source, the shared operation envelope/fingerprint/
  receipt/replay lifecycle, one derived parent Project reference and explicit
  exclusion of caller-authored authoritative creator/time/source evidence.
- The later trusted handler, not this provider-free command, must derive and
  verify the actor, assign final creation time/source and preflight Project
  existence/visibility without distinguishing missing from denied. No server
  handler, authorization, note row/projection, provider or app/MCP writer was
  introduced.
- Exactly two comment-only target surfaces are `target_mapped` under the ready
  dossier: `SWIFT-9CDB2BCAC71B` and `TEST-DB2559406D3D`. The ledger now records
  763 surfaces, including 748 currently discovered, and 337 of 501 target-
  relevant surfaces are mapped or later; the existing 164 residual surfaces
  remain under 43 explicit blockers.
- Conversion, capability, query, residual, M0, target-environment and generated-
  contract checks pass. M1/M2 retain their expected 2/164 blockers. All 124
  existing target tests in 28 suites, macOS and generic iOS Simulator staging
  builds, XcodeGen/source-project stability and diff formatting pass while both
  new scaffolds remain comment-only. Exact ready commit
  `d84dc10998981b54c847b112cf1e063bd1e74c29` passed immutable Actions run
  `33620363089`: conversion traceability passed in 11 seconds and the isolated
  target environment passed in 3 minutes 33 seconds.
- No physical local persistence, parent authorization, server audit assignment,
  schema/RLS/Sync/Auth/provider behavior, shipped-app/MCP change, source note
  migration, hosted resource, production read/mutation, deployment, release or
  cutover occurred.
- Implemented only the frozen provider-free AddProjectNote boundary:
  `ProjectNoteCreationDraft`, exact payload, precondition-free shared envelope,
  derived parent Project reference, canonical fingerprint/receipt validation,
  narrow create port and stable bounded failures.
- The command includes stable note identity, nonblank text and
  `requestedSource` intent, but excludes creator display, authoritative
  creation time, revision, edit audit, deletion evidence and authorization
  claims. Client actor/time/source intent cannot become authoritative without
  later trusted verification and assignment.
- Added four deterministic tests for exact command/payload/parent shape,
  byte-identical restart, blank/malformed/rebound/tampered refusal, shared
  OperationJournal replay/mismatch semantics and no false receipt.
- `PROJECTNOTECREATE-TEST-001` through `-004` pass locally. All 128 target
  tests in 29 suites, target graph/generated contracts, both staging builds,
  conversion/capability/query/residual controls, M0 and clean artifacts pass.
  M1/M2 retain exactly their expected 2/164 blockers.
- Exact implementation commit
  `15566c8dd766762656cb180a65caf0b4600841d5` passed immutable GitHub Actions
  run `33622056438`: conversion traceability passed in 8 seconds and the
  isolated target environment passed in 2 minutes 37 seconds with all 128
  target tests, dependency/environment and generated-contract checks, macOS
  and generic iOS Simulator staging builds and clean tracked artifacts.
- All five Project-note-creation obligations and exactly its two claimed target
  surfaces are now `verified`. Parent authorization, authoritative audit/source
  assignment, note persistence/projection, edit/remove role policy, schema/RLS/
  Sync/Auth/provider behavior, app/MCP, migration, hosted resources and
  production remain unadvanced.
- Exact Project-note-creation verification-document commit
  `b6e8e6cc179df8f670db689679a89dbf9b5f0cea` passed immutable GitHub Actions
  run `33622774880`: conversion traceability passed in 8 seconds and the full
  isolated target environment passed in 1 minute 58 seconds.
- Audited the next Phase 1 Project/Client/reference dependency and excluded
  Project-note edit/removal because their role policy remains deliberately
  unsettled. Selected `project-preference-read-contracts` as the next smallest
  complete dependency: current-Principal ordered pins, revision and local
  absence/readiness truth only.
- Froze seven exact requirements over stable Account/Principal/Project scope,
  ordered unique category identities, preference revision, derived query
  fingerprint, already-authorized visible count and stored/not-stored/not-
  available lookup. Pins remain presentation evidence and cannot supply or
  change canonical budget amounts or arithmetic.
- Exactly two comment-only target surfaces are `target_mapped` under the ready
  dossier: `SWIFT-C6AE96622805` and `TEST-96AAFA22224B`. Preference writes,
  first-use defaults, category visibility resolution, authentication, physical
  persistence, schema/RLS/Sync/provider behavior, app/MCP, source migration,
  hosted resources and production remain unadvanced.
- The ledger now records 765 surfaces, including 750 currently discovered, and
  339 of 503 target-relevant surfaces are mapped or later. The same 164
  residual surfaces remain under 43 explicit blockers; no product or provider
  gate was silently cleared.
- The complete local ready gate passes: all 128 existing target tests in 29
  suites while both scaffolds remain comment-only, target isolation/generated
  contracts, macOS and generic iOS Simulator staging builds, XcodeGen/source-
  project stability, conversion/capability/query/residual controls, M0 and clean
  diff formatting. M1/M2 retain exactly their expected 2/164 blockers.
- Exact ready commit `dfcc1419f59b058c1a4a467662cba8ff95dd5909`
  passed immutable GitHub Actions run `33623843538`: conversion traceability
  passed in 7 seconds and the isolated target environment passed in 1 minute
  50 seconds with all 128 then-existing tests, graph/generated-contract checks,
  both staging builds and clean tracked artifacts.
- Implemented only the frozen provider-free Project preference read boundary:
  exact Account/Principal/Project rows with ordered unique category pins and
  revision, a derived-fingerprint directory request, canonical local directory,
  stored/not-stored/not-available lookup, one narrow read port and stable
  bounded failures.
- Added four deterministic tests for exact personal scope/pin order, ready/
  partial/stale/authoritative-empty restart, authoritative absence versus local
  unavailability, cross-scope/duplicate/fingerprint/count/request/time/malformed
  refusal and exact/no-false-result port behavior.
- `PROJECTPREFERENCE-TEST-001` through `-004` pass locally. All 132 target tests
  in 30 suites, target graph/generated contracts, both staging builds,
  conversion/capability/query/residual controls, M0 and clean artifacts pass.
  Exact-implementation-commit hosted
  `PROJECTPREFERENCE-TEST-005` remains planned, so exactly the two claimed
  target surfaces are `implemented`, not `verified`.
- Exact implementation commit
  `59526ccc33c5317768dc0e986f6c91bf24b2a441` passed immutable GitHub Actions
  run `33624655214`: conversion traceability passed in 11 seconds and the
  isolated target environment passed in 2 minutes 2 seconds with all 132 target
  tests, dependency/environment and generated-contract checks, both staging
  builds and clean tracked artifacts.
- All five Project-preference obligations and exactly its two claimed target
  surfaces are now `verified`. Authentication/authorization implementation,
  physical persistence, preference writes, defaults/category resolution,
  budget calculation, schema/RLS/Sync/provider behavior, app/MCP, migration,
  hosted resources and production remain unadvanced.
- Exact Project-preference-read verification-document commit
  `f19492b800961a4db517eb7a91a1249841b5be5f` passed immutable GitHub Actions
  run `33625052445`: conversion traceability passed in 14 seconds and the full
  isolated target environment passed in 1 minute 46 seconds.
- Audited the next Phase 1 Project/Client/reference dependency and selected
  `project-preference-update-operation-contracts` as the next smallest complete
  mutation. Personal preference ownership is independent of O-026 shared-
  reference administration; the command cannot mutate a category, template or
  vendor suggestion.
- Froze seven exact requirements over one current-Principal Account/Project,
  complete ordered duplicate-free stable category pins, stored-empty support,
  explicit not-stored versus exact-revision concurrency, the shared operation
  lifecycle, canonical restart/refusal and one narrow provider-free port.
- Exactly two comment-only target surfaces are `target_mapped` under the ready
  dossier: `SWIFT-8668DE2251DE` and `TEST-AC9956AE9D5C`. Authentication,
  category mutation/resolution, first-use defaults, budget effects, physical
  persistence, schema/RLS/Sync/provider behavior, app/MCP, source migration,
  hosted resources and production remain unadvanced.
- The ledger now records 767 surfaces, including 752 currently discovered, and
  341 of 505 target-relevant surfaces are mapped or later. The same 164
  residual surfaces remain under 43 explicit blockers; no product or provider
  gate was silently cleared.
- The complete local ready gate passes: all 132 existing target tests in 30
  suites while both scaffolds remain comment-only, target isolation/generated
  contracts, macOS and generic iOS Simulator staging builds, repeatable
  XcodeGen/source-project stability, conversion/capability/query/residual
  controls, M0 and clean diff formatting. M1/M2 retain exactly their expected
  2/164 blockers.
- Exact ready commit `30a131e8305b838f32854601db44ae5aeacbfe7b`
  passed immutable GitHub Actions run `33626533989`: conversion traceability
  passed in 10 seconds and the isolated target environment passed in 2 minutes
  25 seconds with all 132 then-existing tests, graph/generated-contract checks,
  both staging builds and clean tracked artifacts.
- Implemented only the frozen provider-free Project preference update boundary:
  one exact Account/actor/Project, complete ordered duplicate-free pin
  replacement, explicit not-stored or exact-revision precondition, derived
  reference-data subject, shared operation lifecycle, canonical restart,
  stable bounded failures and one narrow update port.
- Added four deterministic tests for exact current-Principal payload/scope,
  absent/revision/stored-empty/reordered restart, duplicate/rebound/tampered
  refusal, shared OperationJournal replay/mismatch behavior and no false
  receipt.
- `PROJECTPREFERENCEUPDATE-TEST-001` through `-004` pass locally. All 136 target
  tests in 31 suites, target graph/generated contracts, both staging builds,
  conversion/capability/query/residual controls, M0 and clean artifacts pass.
  Exact-implementation-commit hosted `PROJECTPREFERENCEUPDATE-TEST-005`
  remains planned, so exactly the two claimed target surfaces are
  `implemented`, not `verified`.
- Exact implementation commit `0e652548d3d4009c392ddacb298d0ef66db61aa2`
  passed immutable GitHub Actions run `33628801064`: conversion traceability
  passed in 10 seconds and the isolated target environment passed in 2 minutes
  29 seconds with all 136 tests in 31 suites, graph/generated-contract checks,
  both staging builds and clean tracked artifacts. All five dossier obligations
  now pass and `SWIFT-8668DE2251DE` plus `TEST-AC9956AE9D5C` are verified.
- Exact Project-preference-update verification-document commit
  `da5cfa4a5ad8941656475644202b510c1ee593ad` passed immutable GitHub Actions
  run `33629389877`: conversion traceability passed in 8 seconds and the full
  isolated target environment passed in 2 minutes 32 seconds.
- Audited the next Project/Client/reference dependency and selected the
  vendor-suggestion reference read as the smallest complete decision-independent
  slice. O-026 governs mutation authority, not an already-authorized Account-
  scoped read; suggestion selection remains free-text source evidence rather
  than Vendor or accounting identity.
- Froze seven exact requirements and five verification obligations over stable
  suggestion identity, preserved bounded spelling, normalized comparison,
  lifecycle/revision/order, explicit local readiness/restart, atomic refusal and
  one narrow Account-exact query port.
- Exactly two comment-only target surfaces are `target_mapped` under the ready
  dossier: `SWIFT-111A94B464D5` and `TEST-A73A49564E8C`. Suggestion mutation,
  O-026 roles/capabilities, default seeding, canonical Vendor identity, physical
  persistence, schema/RLS/Sync/provider behavior, app/MCP, migration, hosted
  resources and production remain unadvanced.
- The ready ledger records 769 surfaces / 754 discovered, with 343 mapped, 164
  residual and 43 blockers. Thirty-two slices claim 85 target surfaces and 68
  are implemented or later. All 136 existing target tests in 31 suites,
  target isolation/generated contracts, both staging builds, repeatable
  XcodeGen/source-project stability, conversion/capability/query/residual
  controls, M0 and clean diff formatting pass; M1/M2 retain exactly their
  expected 2/164 blockers.
- Exact ready commit `3abee18e8011943e74185e43d1630aeb9fa2bff7`
  passed immutable GitHub Actions run `33631062466`: conversion traceability
  passed in 20 seconds and the isolated target environment passed in 2 minutes
  51 seconds with all 136 then-existing tests, graph/generated-contract checks,
  both staging builds and clean tracked artifacts.
- Implemented only the frozen provider-free vendor-suggestion read boundary:
  stable typed suggestion identity, exact Account scope, preserved control-free
  display spelling bounded to 200 UTF-8 bytes, normalized comparison, active/
  archive lifecycle, revision/order, local readiness/restart, atomic refusal and
  one narrow query port. Selection exposes only the preserved source string.
- Added four deterministic tests for exact values/source-text semantics,
  ready/partial/stale/authoritative-empty restart, invalid/cross-Account/
  duplicate/count/time/malformed refusal and exact/no-false-snapshot port
  behavior.
- `VENDORSUGGESTION-TEST-001` through `-004` pass locally. All 140 target tests
  in 32 suites, target graph/generated contracts, both staging builds,
  conversion/capability/query/residual controls, M0 and clean artifacts pass.
  Exact-implementation-commit hosted `VENDORSUGGESTION-TEST-005` also passes, so
  exactly the two claimed surfaces are `verified`.
- Exact implementation commit `519b4338c7cbe8cc63a01820116bef5283a8625a`
  passed immutable GitHub Actions run `33632364285`: conversion traceability
  passed in 10 seconds and the isolated target environment passed in 2 minutes
  38 seconds with all 140 tests in 32 suites, graph/generated-contract checks,
  both staging builds and clean tracked artifacts. All five dossier obligations
  now pass and `SWIFT-111A94B464D5` plus `TEST-A73A49564E8C` are verified.
- Exact vendor verification-document commit
  `08cc0472598a5f8171059d91f19f08024a3704f4` passed immutable Actions run
  `33632848448`: conversion traceability passed in 7 seconds and the isolated
  target environment passed in 2 minutes 58 seconds.
- Audited the next decision-independent Project/reference dependency and
  selected Space-template reads. Corrected `spaces.md` from `current_product` to
  registered canonical target authority for both affected batches because its
  existing target-state notice—not the Firebase checked-state-copy/no-op
  behavior—owns the redesigned contract.
- Added exactly two comment-only target scaffolds and the complete ready dossier
  for `SWIFT-77F812A8F463` and `TEST-CB30140F137B`. The frozen boundary covers
  stable Account/template/checklist/item identity, text, lifecycle/revision/
  explicit order, checklist structure with no checked state, local readiness/
  restart/refusal and one narrow Account query port.
- The synchronized ledger records 771 surfaces / 756 discovered, 345 mapped-or-
  later target-relevant surfaces, 164 residual surfaces and 43 validated
  blockers. Thirty-three slices claim 87 target surfaces. M0 passes; M1/M2
  retain exactly their expected 2/164 blockers.
- The complete local ready gate passes with all 140 existing target tests in 32
  suites, target graph/generated contracts, both staging builds, repeatable
  XcodeGen/source-project hashes, conversion/capability/query/residual controls,
  M0 and clean diff formatting.
- Exact comment-only ready commit
  `acc48f637d0f8702a83142f2ba94facd462b48ff` passed immutable Actions run
  `33634828042`: conversion traceability passed in 11 seconds and the isolated
  target environment passed in 2 minutes 7 seconds with all 140 then-existing
  tests, graph/generated-contract checks, both staging builds and clean tracked
  artifacts.
- Implemented only the frozen provider-free Space-template read boundary:
  distinct stable template/checklist/item identity, preserved required text,
  optional notes, lifecycle/revision/explicit deterministic order, local
  readiness/restart/refusal and one narrow Account query port. The target
  structure has no checked-state field and discards unknown stale source
  `isChecked` input on decode/re-encode.
- Added four deterministic tests for exact nested structure and active/archive
  selection, no checked-state carriage, ready/partial/stale/authoritative-empty
  restart, blank/cross-Account/nested-duplicate/count/time/malformed refusal and
  exact/no-false-snapshot query-port behavior.
- `SPACETEMPLATE-TEST-001` through `-004` pass locally. All 144 target tests in
  33 suites, target graph/generated contracts, both staging builds,
  conversion/capability/query/residual controls, M0 and clean artifacts pass.
  Exact-implementation-commit hosted `SPACETEMPLATE-TEST-005` also passes, so
  exactly the two claimed surfaces are `verified`.
- Exact implementation commit `f23afce3a95dbf9bb96d1716b73f65f79bbc2714`
  passed immutable GitHub Actions run `33636359059`: conversion traceability
  passed in 8 seconds and the isolated target environment passed in 2 minutes
  33 seconds with all 144 tests in 33 suites, graph/generated-contract checks,
  both staging builds and clean tracked artifacts. All five dossier obligations
  now pass; 72 target surfaces are implemented or later.
- Exact Space-template verification-document commit
  `58a7c406a0f35d510b57cbb3604623a9aea8c1bd` passed immutable Actions run
  `33636886779`: conversion traceability passed in 8 seconds and the isolated
  target environment passed in 2 minutes 25 seconds.
- Audited the next Project/Client/reference dependency against canonical target
  authority and selected Client archive. The spec defines archive as hiding one
  stable Client from new-project selection without deleting history; O-025
  continues to block merge and Project reassignment, not this exact intent.
- Added exactly two target-only comment scaffolds and a ready dossier for one
  expected-revision-aware `ArchiveClient` command. The frozen boundary cannot
  cascade to Projects, restore/delete/merge/rename a Client, rewrite frozen
  history or reassign a Project, and introduces no executable behavior before
  immutable ready-commit CI.
- The synchronized ledger now records 773 surfaces / 758 discovered, 347 mapped-
  or-later target-relevant surfaces, 164 residual surfaces and 43 validated
  blockers. Thirty-four slices claim 89 target surfaces; 72 target surfaces are
  implemented or later. M0 passes; M1/M2 retain exactly their expected 2/164
  blockers.
- The complete local Client-archive ready gate passes with all 144 existing
  target tests in 33 suites while both new files remain comment-only, target
  environment/generated contracts, both staging builds, conversion/capability/
  query/residual controls, M0 and clean diff formatting. Immutable exact-ready-
  commit CI remains the only prerequisite to bounded implementation.
- Exact comment-only ready commit
  `9f3a03dd257b350362d48ef8b5742dcd01131747` passed immutable Actions run
  `33638235220`: conversion traceability passed in 7 seconds and the isolated
  target environment passed in 2 minutes 20 seconds with all 144 then-existing
  tests, graph/generated-contract checks, both staging builds and clean tracked
  artifacts.
- Implemented only the frozen provider-free Client archive boundary: one stable
  Client ID, reused typed expected revision, exact same-subject precondition,
  shared envelope/fingerprint/receipt/replay lifecycle, canonical restart and
  stable refusal. There is no lifecycle boolean, Project list, cascade, hard
  delete, merge, rename, restore, history rewrite or reassignment input.
- Added four deterministic tests for exact scope/precondition, byte-identical
  restart, invalid/rebound/tampered evidence refusal, shared replay/mismatch
  semantics and no false receipt from a failing port. Four focused/all 148
  target tests in 34 suites, graph/generated contracts, both staging builds,
  conversion/capability/query/residual controls, M0 and clean artifacts pass
  locally. Exactly two surfaces are `implemented`; exact-commit CI remains.
- Exact implementation commit
  `e10be9ec731ee68ed14ff6e2b6d004b6d00d5baf` passed immutable GitHub Actions
  run `33639210706`: conversion traceability passed in 13 seconds and the
  isolated target environment passed in 2 minutes 58 seconds with all 148 tests
  in 34 suites, graph/generated-contract checks, both staging builds and clean
  tracked artifacts. All five obligations pass and exactly the two Client-
  archive surfaces are now `verified`; 74 target surfaces are implemented or
  later.
- Exact Client-archive verification-document commit
  `1926a16e87e353853d3e439d62fbc88495ee1c0d` passed immutable Actions run
  `33639869188`: conversion traceability passed in 8 seconds and the isolated
  target environment passed in 2 minutes 35 seconds.
- Audited Project details as the next smallest complete dependency. The target
  taxonomy already separates `UpdateProjectDetails`; the preserved optional
  Project description is the only field it owns after Project rename, Client
  relationship, category configuration, media and lifecycle are excluded.
- Corrected `projects.md` from `current_product` to the seventh canonical target
  spec because it already separates Target Redesign Requirements from Firebase
  mechanics retained as migration evidence. Made the reviewed optional-
  description preserve/correct rule explicit without adding a new feature:
  trim outer whitespace, whitespace-only clears, and no other Project concern
  may change.
- Added exactly two target-only comment scaffolds and a ready dossier for one
  expected-revision-aware `UpdateProjectDetails` description replacement. No
  executable behavior exists before exact-ready-commit CI.
- The synchronized ledger now records 775 surfaces / 760 discovered, 349 mapped-
  or-later target-relevant surfaces, 164 residual surfaces and 43 validated
  blockers. Thirty-five slices claim 91 target surfaces; 74 are implemented or
  later. M0 passes; M1/M2 retain exactly their expected 2/164 blockers.
- The complete local Project-details ready gate passes with all 148 existing
  target tests in 34 suites while both new files remain comment-only, target
  environment/generated contracts, both staging builds, conversion/capability/
  query/residual controls, M0 and clean diff formatting. Immutable exact-ready-
  commit CI remains the only prerequisite to bounded implementation.
- Exact comment-only ready commit
  `119e04559fbf756e2481287963d0367d80d39846` passed immutable Actions run
  `33641244740`: conversion traceability passed in 8 seconds and the isolated
  target environment passed in 2 minutes 25 seconds with all 148 then-existing
  tests, graph/generated-contract checks, both staging builds and clean tracked
  artifacts.
- Implemented only the frozen provider-free Project-details boundary: one
  canonical optional-description replacement/clear, stable Project ID, reused
  typed expected revision, exact same-subject precondition, shared envelope/
  fingerprint/receipt/replay lifecycle, canonical restart and stable refusal.
  There is no name, Client, category, media, lifecycle, child, accounting,
  history or generic-field mutation input.
- Added four deterministic tests for normalized set/clear scope, byte-identical
  restart, noncanonical/malformed/rebound/tampered evidence refusal, shared
  replay/mismatch semantics and no false receipt from a failing port. Four
  focused/all 152 target tests in 35 suites, graph/generated contracts, both
  staging builds, conversion/capability/query/residual controls, M0 and clean
  artifacts pass locally. Exactly two surfaces are `implemented`; 76 target
  surfaces are implementation-advanced and exact-commit CI remains.
- Exact implementation commit
  `a532ac9dee5bedca6ade576657fc4fd971841854` passed immutable GitHub Actions
  run `33642777864`: conversion traceability passed in 10 seconds and the
  isolated target environment passed in 2 minutes 51 seconds with all 152 tests
  in 35 suites, graph/generated-contract checks, both staging builds and clean
  tracked artifacts. All five obligations pass and exactly the two Project-
  details surfaces are now `verified`; 76 target surfaces are implemented or
  later.
- Exact Project-details verification-document commit
  `27b2123474957a448097078c7facbf6ed3d8c418` passed immutable GitHub Actions
  run `33643300146`: conversion traceability passed in 11 seconds and the
  isolated target environment passed in 3 minutes 4 seconds.
- Audited `ConfigureProjectCategories` and did not create a writer: verified
  requirement `PROJECTCATEGORY-REQ-004` keeps category mutation out while O-026
  shared-reference administration authority remains open.
- Selected direct `CreateSpace` as the next smallest complete decision-
  independent dependency. Clarified the existing canonical `spaces.md` target
  requirements for stable identity, exact Project-or-Business-Inventory scope,
  normalized required name and optional notes, separate child concerns, shared
  operation lifecycle and no accounting effects. O-023/O-026/O-037 are not
  resolved or bypassed.
- Added exactly two target-only comment scaffolds and a ready dossier for the
  provider-free direct Space-create operation. No executable behavior exists
  before exact-ready-commit CI.
- The synchronized ledger now records 777 surfaces / 762 discovered, 351
  mapped-or-later target-relevant surfaces, 164 residual surfaces and 43
  validated blockers. Thirty-six slices claim 93 target surfaces; 76 are
  implemented or later. M0 passes; M1/M2 retain exactly their expected 2/164
  blockers.
- The complete local Space-create ready gate passes with all 152 existing
  target tests in 35 suites while both new files remain comment-only, target
  environment/generated contracts, both staging builds, conversion/capability/
  query/residual controls, M0 and clean diff formatting. Immutable exact-ready-
  commit CI is the only prerequisite to bounded implementation.
- Exact comment-only Space-create ready commit
  `fd81c8aed1a88a3cbd8be742a784dd3d1ab72e93` passed immutable GitHub Actions
  run `33645504076`: conversion traceability passed in 20 seconds and the
  isolated target environment passed in 2 minutes 32 seconds with all 152 then-
  existing tests, graph/generated-contract checks, both staging builds and
  clean tracked artifacts.
- Implemented only the frozen provider-free direct Space-create boundary:
  stable Space identity; exact Project-or-Business-Inventory scope; canonical
  required name and optional notes; zero expected-revision preconditions;
  shared envelope/fingerprint/receipt/replay; canonical restart/refusal; stable
  diagnostics; and one narrow port. It contains no child, template, media,
  assignment, review, lifecycle, accounting, provider or authoritative-apply
  concern.
- Four focused and all 156 target tests in 36 suites pass locally, along with
  target isolation/generated contracts, both staging builds and clean diff
  formatting. The implementation acknowledges exact source hashes; 78 target
  surfaces are now implementation-advanced. Exact implementation-commit CI
  remains before verification.
- Exact Space-create implementation commit
  `03b545dffcaaf8ea37fc9f30f0e3f12b761610a4` passed immutable GitHub Actions
  run `33647113450`: conversion traceability passed in 7 seconds and the
  isolated target environment passed in 2 minutes 45 seconds with all 156 tests
  in 36 suites, graph/generated-contract checks, both staging builds and clean
  tracked artifacts. All five obligations pass and exactly the two Space-create
  surfaces are now `verified`; 78 target surfaces are implemented or later.
- Exact Space-create verification-document commit
  `74d411f162633a9fcd03f7976e4b1f312a78473e` passed immutable GitHub Actions
  run `33650026503`: conversion traceability passed in 10 seconds and the
  isolated target environment passed in 2 minutes 28 seconds.
- Audited `UpdateSpaceDetails` as the next smallest complete decision-
  independent dependency. The canonical Space spec and reviewed capability
  dossier preserve name/optional-notes editing while replacing generic partial
  dictionaries and last-write-wins with one complete same-Space revisioned
  replacement. Scope, child state, media, assignment, review, lifecycle and
  accounting remain separate.
- Clarified that existing target rule in `spaces.md`, registered the reviewed
  Spaces capability dossier as conversion-control evidence, and added exactly
  two target-only comment scaffolds plus a ready dossier. No executable details-
  update behavior exists before exact-ready-commit CI.
- The synchronized ledger now records 779 surfaces / 764 discovered, 353
  mapped-or-later target-relevant surfaces, 164 residual surfaces and 43
  validated blockers. Thirty-seven slices claim 95 target surfaces; 78 are
  implemented or later. M0 passes; M1/M2 retain exactly their expected 2/164
  blockers.
- The complete local Space-details ready gate passes with all 156 existing
  target tests in 36 suites while both new files remain comment-only, target
  environment/generated contracts, both staging builds, conversion/capability/
  query/residual controls, M0 and clean diff formatting. Immutable exact-ready-
  commit CI is the only prerequisite to bounded implementation.
- Exact comment-only Space-details ready commit
  `938a30abdf816be63055f30a2d17c602f92e0611` passed immutable GitHub Actions
  run `33652799157`: conversion traceability passed in 10 seconds and the
  isolated target environment passed in 2 minutes 57 seconds with all 156 then-
  existing tests, graph/generated-contract checks, both staging builds and
  clean tracked artifacts.
- Implemented only the frozen provider-free Space-details boundary: reused
  canonical Space name/notes values; stable Space identity; typed expected
  revision; exactly one same-Space precondition; shared envelope/fingerprint/
  receipt/replay; canonical restart/refusal; stable diagnostics; and one narrow
  port. It contains no scope, child, template, media, assignment, review,
  lifecycle, accounting, provider or authoritative-apply concern.
- At the local implementation checkpoint, four focused and all 160 target tests
  in 37 suites passed, along with
  target isolation/generated contracts, both staging builds and clean diff
  formatting. The implementation acknowledged exact source hashes; 80 target
  surfaces were implementation-advanced and exact implementation-commit CI
  remained before verification.
- Exact Space-details implementation commit
  `1c8c12b4c593a43b3743fec41331dd852edbc10b` passed immutable GitHub Actions
  run `33654631876`: conversion traceability passed in 8 seconds and the
  isolated target environment passed in 2 minutes 31 seconds with all four
  focused/all 160 target tests in 37 suites, graph/generated-contract checks,
  both staging builds and clean tracked artifacts. All five obligations pass;
  exactly the two Space-details surfaces are now `verified`, and 80 target
  surfaces remain implemented or later.
- Exact Space-details verification-document commit
  `01d3638b2b7850f39a7a16e1b899b37ce441e189` passed immutable GitHub Actions
  run `33655871244`: conversion traceability passed in 8 seconds and the
  isolated target environment passed in 2 minutes 36 seconds.
- Audited `ReviseSpaceChecklists` as the next smallest complete decision-
  independent dependency. Canonical Space authority and the reviewed capability
  dossier preserve add/remove/rename/reorder/check/progress outcomes while
  replacing random decoded IDs and last-write-wins embedded-array updates with
  one complete revisioned hierarchy. Template administration, media, Item
  assignment, review, Space reconciliation, lifecycle and accounting remain
  separate and O-023/O-026/O-032/O-037 remain open.
- Clarified that target rule in `spaces.md`, added exactly two target-only
  comment scaffolds and froze the ready dossier. The synchronized ledger now
  records 781 surfaces / 766 discovered, 355 mapped-or-later target-relevant
  surfaces, 164 residual surfaces and 43 validated blockers. Thirty-eight
  slices claim 97 target surfaces; 80 are implemented or later. M0 passes;
  M1/M2 retain exactly their expected 2/164 blockers.
- The complete local Space-checklist ready gate passes with all 160 existing
  target tests in 37 suites while both new files remain comment-only, target
  environment/generated contracts, both staging builds, conversion/capability/
  query/residual controls, M0 and clean diff formatting. M1/M2 retain exactly
  their expected 2/164 prerequisite blockers. Immutable exact-ready-commit CI
  remains required before bounded implementation.
- Exact comment-only Space-checklist ready commit
  `68d2b4d071fdf96911d5cc0c1b6e71cd1b3c53b2` passed immutable GitHub Actions
  run `33658088408`: conversion traceability passed in 18 seconds and the
  isolated target environment passed in 2 minutes 6 seconds with all 160 then-
  existing target tests, graph/generated-contract checks, both staging builds
  and clean tracked artifacts.
- Implemented only the frozen provider-free checklist boundary: distinct stable
  checklist/item identities; canonical nonblank names/text; complete
  deterministic nested order; checked-state progress; valid empty clear and
  zero-item checklists; exact same-Space revision; shared envelope/fingerprint/
  receipt/replay; canonical restart/refusal; stable diagnostics; and one narrow
  port. It contains no scope/details/template/media/assignment/review/Space-
  completion/lifecycle/accounting/provider or authoritative-apply concern.
- Four focused and all 164 target tests in 38 suites pass locally, along with
  target isolation/generated contracts, conversion/capability/query/residual
  controls, M0, both staging builds and clean diff formatting. The
  implementation acknowledges exact source hashes; 82 target surfaces are
  implementation-advanced. Exact implementation-commit CI remains before
  verification.
- Exact Space-checklist implementation commit
  `8131e8570cda2d9ffa5a4e445bd6dfd50b8aefed` passed immutable GitHub Actions
  run `33659853864`: conversion traceability passed in 10 seconds and the
  isolated target environment passed in 2 minutes 36 seconds with all four
  focused/all 164 target tests in 38 suites, graph/generated-contract checks,
  both staging builds and clean tracked artifacts. All five obligations pass;
  exactly the two Space-checklist surfaces are now `verified`, and 82 target
  surfaces are implemented or later.
- The Space-checklist verification-document commit
  `3cfbcb5a70c0d3620aedf04a57bf46690cd6263a` passed both jobs in immutable
  Actions run `33660769158`, including all 164 then-existing target tests, both
  staging builds and clean tracked artifacts.
- Audited Item-to-Space assignment and withheld it because O-037 still owns
  archived destination/retained-assignment semantics; no proposed archive
  policy was promoted into code.
- Selected the decision-independent session-ending pending-work safety
  boundary. Canonical Auth/offline requirements now state the already-required
  exact environment/Principal/Account summary, four distinct pending-work
  counts, clean-zero rule, sync-first completion rule, exact-confirmed
  destructive exception, cancellation no-call and fail-closed interruption
  behavior while leaving Auth, offline lease, UI copy and physical cleanup open.
- Added exactly two comment-only target surfaces, the reviewed identity batch
  mapping, `session-ending-pending-work-contracts`, and
  `EVID-SESSION-ENDING-POLICY-001`. The ready dossier freezes eight requirements
  and five deterministic obligations; executable behavior remains absent until
  the exact ready checkpoint passes immutable CI.
- The complete local ready gate passes with all 164 existing target tests in 38
  suites, both staging builds, target isolation/generated contracts,
  conversion/capability/query/residual controls, M0 and clean formatting. The
  ledger records 783 surfaces / 768 discovered, 357 mapped / 164 residual / 43
  blockers; M1/M2 retain the expected 2/164 blockers with zero structural
  errors.
- Exact comment-only session-ending ready commit
  `caa9a9003c13782780d6107df805b95f2f9240ba` passed immutable GitHub Actions
  run `33662071456`: conversion traceability passed in 10 seconds and the
  isolated target environment passed in 2 minutes 23 seconds with all 164 then-
  existing tests, graph/generated-contract checks, both staging builds and
  clean tracked artifacts.
- Implemented only the frozen provider-free session-ending safety boundary:
  exact scoped four-class pending-work summaries; canonical summary/request
  fingerprints; clean/sync-first/exact-confirmed-destructive dispositions;
  cancellation no-request; fresh-summary, stale/regression and scope checks;
  stable diagnostics; and one narrow port. It contains no Auth, physical
  synchronization/cleanup, provider, media-retention, schema/RLS/Sync, app/MCP,
  migration or production behavior.
- Four focused and all 168 target tests in 39 suites pass locally, along with
  target isolation/generated contracts, both staging builds and clean diff
  formatting. Exact source hashes are acknowledged.
- Exact session-ending implementation commit
  `bf9a00ca45c8054018ab6f021aab13386ba24872` passed immutable GitHub Actions
  run `33663785835`: conversion traceability passed in 15 seconds and the
  isolated target environment passed in 2 minutes 32 seconds with all four
  focused/all 168 target tests in 39 suites, graph/generated-contract checks,
  both staging builds and clean tracked artifacts. All five obligations pass;
  exactly the two session-ending surfaces are now `verified`, and 84 target
  surfaces are implemented or later.
- The session-ending verification-document commit
  `41d96d7dd4d935bf6f320e55dcfe277b28ff3c9b` passed immutable Actions run
  `33664894237`: conversion traceability passed in 10 seconds and the isolated
  target environment passed in 2 minutes 23 seconds with all 168 then-existing
  tests, both staging builds and clean tracked artifacts.
- Audited Account discovery/selection against the canonicalized product spec,
  reviewed identity dossier, architecture and current app/MCP sources. The
  bounded target contract corrects discovery-error-as-empty, arbitrary/first/
  fallback selection and selection-as-listener-state without deciding Auth,
  offline lease, current membership or physical workspace activation.
- Added exactly two comment-only target surfaces,
  `account-discovery-and-selection-contracts`, and
  `EVID-ACCOUNT-DISCOVERY-SELECTION-001`. The ready dossier freezes eight
  requirements and five deterministic obligations. The ledger records 785
  surfaces / 770 discovered, 359 mapped / 164 residual / 43 blockers; 40
  slices claim 101 of 523 target-relevant surfaces while 84 are implementation-
  advanced.
- The complete local ready gate passes with all 168 existing target tests in 39
  suites, both staging builds, unchanged repeatable target graph, target
  isolation/generated contracts, conversion/capability/query/residual controls,
  M0 and clean formatting. M1/M2 retain the expected 2/164 blockers with zero
  structural errors.
- Exact Account-discovery ready commit
  `ae16ed4e62ee2abe7ab60f71a26a92824e70fa01` passed immutable Actions run
  `33666363647`: conversion traceability passed in 7 seconds and the isolated
  target environment passed in 3 minutes 34 seconds with all 168 then-existing
  target tests, graph/generated-contract checks, both staging builds and clean
  tracked artifacts.
- Implemented only the frozen provider-free Account-discovery/selection
  boundary: bounded visibility-safe Account summaries; exact environment/
  Principal/readiness/version/time/fingerprint snapshots; distinct waiting,
  snapshot and failed-with-cache states; deterministic remembered ordering with
  no automatic selection; exact-snapshot-bound non-authorizing selection
  intent; stable rejection diagnostics; and one narrow `AccountQuerying` port.
  Auth, membership proof, authorization, offline lease, persistence, physical
  activation/switching, schema/RLS/Sync, app/MCP, migration and production remain
  absent.
- Four focused and all 172 target tests in 40 suites pass locally, along with
  target isolation/generated contracts, both staging builds, repeatable target
  project generation, conversion/capability/query/residual controls, M0 and
  clean diff formatting. M1/M2 retain exactly 2/164 blockers with zero
  structural errors.
- Exact Account-discovery implementation commit
  `e2972b9c81055fdf936db81afc4bd7e5cd13d0fb` passed immutable Actions run
  `33668715587`: conversion traceability passed in 8 seconds and the isolated
  target environment passed in 3 minutes 8 seconds with all 172 target tests in
  40 suites, graph/generated-contract checks, both staging builds and clean
  tracked artifacts. All five obligations pass; exactly the two Account-
  discovery/selection surfaces are now `verified`.
- Exact Account-discovery verification-document commit
  `4102365871ba3bde9b42e6132f98a02a1bbd3d69` passed immutable Actions run
  `33669255726`: conversion traceability passed in 9 seconds and the isolated
  target environment passed in 2 minutes 51 seconds with all 172 then-existing
  target tests, graph/generated-contract checks, both staging builds and clean
  tracked artifacts.
- Audited Item-to-Space assignment against canonical `spaces.md`, the one-Item
  identity/accounting boundary, the reviewed Spaces dossier, architecture and
  current Firebase assignment callers. The target keeps stable physical Item
  identity and same-scope placement while replacing independent writes and
  generic field updates with one atomic typed operation; it does not preserve
  Firebase mechanics.
- Selected `AssignItemsToSpace` as the next smallest complete decision-
  independent slice. O-037 remains open because archive/delete is absent;
  O-007/O-015 do not block a command that cannot change occurrence, provenance
  or accounting state. Clear assignment, scope movement, media and review are
  separate operations.
- Added exactly two comment-only target surfaces,
  `item-space-assignment-operation-contracts`, and
  `EVID-ITEM-SPACE-ASSIGNMENT-001`. The ready dossier freezes eight requirements
  and five deterministic obligations. The ledger records 787 surfaces / 772
  discovered, 361 mapped / 164 residual / 43 blockers; 41 slices claim 103 of
  525 target-relevant surfaces while 86 are implementation-advanced.
- The complete local ready gate passes with all 172 existing target tests in 40
  suites, both staging builds, unchanged repeatable target graph, target
  isolation/generated contracts, conversion/capability/query/residual controls,
  M0 and clean formatting. M1/M2 retain the expected 2/164 blockers with zero
  structural errors.
- Exact ready commit `30f4ab88cd526b89b09dc22f1f26cd66884b0b33`
  passed immutable Actions run `33670383410`: conversion traceability passed in
  14 seconds and the isolated target environment passed in 2 minutes 8 seconds
  with all 172 then-existing target tests, graph/generated-contract checks, both
  staging builds and clean tracked artifacts.
- Replaced exactly those two comment-only scaffolds with the bounded provider-
  free implementation. `ItemPlacementScope`, exact Space/Item revision inputs,
  canonical nonempty duplicate-free candidate sets, typed active/revision/scope
  preconditions, command/fingerprint/receipt reconstruction, 16 stable failure
  codes and the narrow `ItemSpaceAssigning` port now exist.
- Four focused/all 176 target tests in 41 suites pass locally, along with both
  staging builds, target isolation/generated contracts, conversion/capability/
  query/residual controls, M0, clean formatting and repeatable project/scheme
  hashes. M1/M2 retain exactly 2/164 blockers with zero structural errors. The
  source application project is unchanged.
- Exact implementation commit
  `c5fdf5c73763b5a629ff0416bebba92696af6581` passed immutable Actions run
  `33672006836`: conversion traceability passed in 9 seconds and the isolated
  target environment passed in 2 minutes 31 seconds with all 176 target tests
  in 41 suites, graph/generated-contract checks, both staging builds and clean
  tracked artifacts. All five obligations pass; exactly the two Item-to-Space
  assignment surfaces are now `verified`.
- The Item-to-Space verification-document commit
  `6ff51992726a7a2d88739bf9e8a689bffe4b6de4` passed immutable Actions run
  `33672821325`: conversion traceability passed in 8 seconds and the isolated
  target environment passed in 3 minutes 5 seconds with all 176 then-existing
  target tests, both staging builds and clean tracked artifacts.
- Audited explicit Item Space clearing against canonical Space/Item authority,
  D-019/D-023, reviewed Spaces/media dossiers, architecture and current Item/
  Inventory/Project/Space/Search callers. The target replaces generic
  `spaceId: NSNull()` dictionaries, silent duplicate removal and independently
  chunked writes with one atomic typed operation while preserving authoritative
  closure of old green Item-linked Space-photo checkmark relationships without
  accepting marker data or deleting media bytes.
- Selected `ClearItemSpaceAssignments` as the next smallest complete decision-
  independent slice. O-037 remains open because archive/delete is absent and
  clear is explicit; O-023 remains open because no attachment reference or byte
  is removed; O-007/O-015 do not block non-accounting placement clear.
- Added exactly two comment-only target surfaces,
  `item-space-clearing-operation-contracts`, and
  `EVID-ITEM-SPACE-CLEARING-001`. The ready dossier freezes eight requirements
  and five deterministic obligations. The synchronized ledger records 789
  surfaces / 774 discovered, 363 mapped / 164 residual / 43 blockers; 42 slices
  claim 105 of 527 target-relevant surfaces while 88 are implementation-
  advanced.
- The complete local Item Space-clearing ready gate passes with all 176 existing
  target tests in 41 suites, both staging builds, unchanged repeatable target
  graph, target isolation/generated contracts, conversion/capability/query/
  residual controls, M0 and clean formatting. M1/M2 retain the expected 2/164
  blockers with zero structural errors.
- Exact ready commit `2a201de4109891323e51bbd273ed33723d970508`
  passed immutable Actions run `33675190031`: conversion traceability passed in
  11 seconds and the isolated target environment passed in 2 minutes with all
  176 then-existing target tests, graph/generated-contract checks, both staging
  builds and clean tracked artifacts.
- Replaced exactly those two comment-only scaffolds with the bounded provider-
  free implementation. Exact Project-or-Business-Inventory scope, canonical
  nonempty duplicate-free Item/revision/current-Space candidates including
  mixed source Spaces, deterministic scope/current-placement preconditions,
  command/fingerprint/receipt reconstruction, 15 stable failure codes and the
  narrow `ItemSpaceAssignmentClearing` port now exist. Marker closure remains a
  later trusted-handler effect and no media-deletion instruction is accepted.
- Four focused/all 180 target tests in 42 suites pass locally, along with both
  staging builds, target isolation/generated contracts, conversion/capability/
  query/residual controls, M0, clean formatting and repeatable project/scheme
  hashes. M1/M2 retain exactly 2/164 blockers with zero structural errors. The
  source application project is unchanged; exact implementation-commit CI
  was required before promotion.
- Exact implementation commit
  `f5a7ac7598f77859239b66666bc703ee4639c233` passed immutable Actions run
  `33677087616`: conversion traceability passed in 8 seconds and the isolated
  target environment passed in 2 minutes 25 seconds with all 180 target tests
  in 42 suites, graph/generated-contract checks, both staging builds and clean
  tracked artifacts. All five obligations pass; exactly the two Item Space-
  clearing surfaces are now `verified`.
- The Item Space-clearing verification-document commit
  `2fd9ccaa183d7a840aa578192c7da3bf2b40c0db` passed immutable Actions run
  `33677528131`: conversion traceability passed in 9 seconds and the isolated
  target environment passed in 3 minutes 21 seconds with all 180 then-existing
  target tests, both staging builds and clean tracked artifacts.
- Audited the Space assignment destination picker against canonical Space/Item
  authority, the reviewed Spaces dossier, local-first architecture, the
  verified assignment operation and current Firebase callers. Some current
  callers supply exact Project/Inventory-filtered arrays while shared search
  flows may supply Account-wide Spaces; the target replaces caller-owned
  filtering with one exact operation-specific local directory.
- Selected `space-assignment-destination-read-contracts` as the next smallest
  complete decision-independent slice. O-037 does not block a directory that
  exposes only active destinations and cannot archive; O-023/O-032 do not block
  rows that carry no media or review state.
- Added exactly two comment-only target surfaces and the complete ready dossier.
  It freezes eight requirements and five domain/restart/rejection/port/
  operational obligations over exact Account/scope, active Space identity/name/
  revision, valid duplicate names, deterministic ordering and explicit local
  readiness without treating cached rows as authorization.
- Conversion synchronization and generated residuals pass at 791 recorded / 776
  discovered surfaces, 365 mapped / 164 residual / 43 blockers. Forty-three
  slices claim 107 of 529 target-relevant surfaces and 90 are implementation-
  advanced. The only warnings are the same three evidenced retired paths.
- The complete local ready gate passes all 180 existing target tests in 42
  suites, both staging builds, target isolation/generated contracts, conversion/
  capability/query/residual controls, M0, clean formatting and repeatable target
  project/scheme hashes. The source application project is unchanged. M1/M2
  retain exactly 2/164 coverage blockers with zero structural errors.
- Exact ready commit `5f4867af1cba9b860efe9de2a914782bb8010278`
  passed immutable Actions run `33679542831`: conversion traceability passed in
  8 seconds and the isolated target environment passed in 3 minutes 39 seconds
  with all 180 then-existing tests, generated contracts, graph checks, both
  staging builds and clean tracked artifacts.
- Adopted the controlled subagent model after an explicit risk/reward review.
  `parallel-subagent-workflow.md` keeps one canonical integration/control-plane
  owner and permits at most two write-capable workers, each owning one frozen
  slice in an exact-base isolated worktree. Worker results are untrusted
  candidate commits and cannot advance evidence or status.
- The first two implementation pilots require primary-agent review of every
  changed line, a separate read-only adversarial requirements/security/offline/
  test review, primary-agent focused and complete-gate reruns, and fresh exact-
  integration-commit CI. A critical/repeated-major finding, out-of-scope edit or
  evidence overclaim suspends further write delegation until the process is
  corrected.
- Recorded `SUBAGENT-PILOT-001` in `parallel-work-registry.json`, pinned to the
  exact ready commit and run above. Its dedicated branch/worktree may modify only
  the two Space assignment-destination implementation/test scaffolds; Firebase,
  docs/control/generated files, package/project graphs, MCP and hosted systems
  are forbidden.
- Completed the first isolated implementation candidate at
  `dd48f23557ed204244a68c4cf6896a58133276f4`. Its clean branch is descended
  from the exact ready commit and changes exactly the two allowlisted files.
- Applied the enhanced first-pilot quality gate: the integration agent reviewed
  every changed line and independently reran four focused and all 184 target
  tests in 43 suites; a separate read-only adversarial reviewer repeated the
  authority, negative, restart, scope and exclusion audit and found no P0-P2
  defect.
- Resolved the reviewer's nonblocking P3 documentation finding by clarifying
  that legitimate later revision/readiness snapshots remain valid while
  malformed, rebound or internally inconsistent evidence fails closed; no
  content-integrity or authorization proof is claimed.
- Integrated the candidate into the canonical branch at
  `0cca411d78d41281f3fb1f1d5c08c6518e2003b7`. The dossier and exactly its two
  surfaces are `implemented`, not `verified`.
- The complete local integration gate passes conversion sync/check/report,
  capability/query/residual controls, M0, target isolation/generated contracts,
  four focused/all 184 tests in 43 suites, repeatable project generation, both
  staging builds and clean formatting. Project/scheme hashes remain unchanged;
  M1/M2 retain exactly 2/164 coverage blockers and zero structural errors.
- Exact integration checkpoint
  `b0ffef836cc82f6011b802a5cb5f6a6ade05680a` passed immutable Actions run
  `33682239349`: traceability passed in 10 seconds and the isolated target job
  passed in 3 minutes 2 seconds with all 184 tests in 43 suites, target graph/
  contracts, both staging builds and clean artifacts.
- Promoted exactly the Space assignment-destination dossier and its two
  surfaces to `verified`; `SUBAGENT-PILOT-001` is complete with its worker,
  integration-agent and independent-review evidence preserved. One of two
  enhanced write pilots has now passed.
- Rejected the proposed Inventory purchase-planning second pilot before a ready
  dossier or worker launch. Root and independent authority review found that
  the shipped spec is current/migration evidence only, D-013 conflicts with
  legacy intended-category authority, and retention/granularity/lifecycle are
  unresolved. Removed the speculative scaffolds, demoted the two MCP planning
  tools and legacy category helper, added O-038 to all five affected surfaces,
  removed premature planning ports, and created a non-authoritative decision
  packet. Current deterministic state is 791 recorded / 776 discovered, 362
  mapped-or-later / 167 residual / 44 blockers with only the three documented
  retired-path warnings. No worker implementation was accepted.
- Re-ran the next-slice search under the strengthened feature-specific
  authority rule. Media primary/order and Project-note search were rejected as
  insufficiently specified. A strict scout and independent read-only
  adversarial preflight approved only a narrow provider-free Project budget
  segment DTO/query foundation from the pre-existing Budget Progress spec and
  D-012. The preflight required exact Account/Project/currency identity, signed
  client-paid and invoicing/unpaid Money, internally derived recognized value,
  positive collection-segment exchange with no recognized change, stable
  category order, distinct LocalDataVersion and accounting-authority/projection
  revision, explicit incomplete/empty truth, restart/refusal and exact-request
  port behavior. It prohibited calling the result the complete
  ProjectBudgetSnapshot or adding source resolution, settlement, reports,
  visual policy, providers or migration.
- Prepared `project-budget-segment-read-contracts` as `ready` with exactly two
  comment-only target surfaces, seven requirements and five planned
  verification obligations. The accompanying architecture clarification records
  technical request/port scope only; it is not product authority and did not
  exist at the reviewed base. Current deterministic state is 793 recorded / 778
  discovered, 364 mapped-or-later / 167 residual / 44 blockers, 44 slices
  claiming 109 of 531 target-relevant surfaces, and only the three documented
  retired-path warnings. No worker, provider, Firebase or production action has
  occurred.
- `SUBAGENT-PILOT-002` produced candidate `dc9f2601` from the exact green ready
  base and changed only the two allowlisted Swift paths. A precommit size check
  required simplification from approximately 1,076 to 768 added lines without
  dropping frozen coverage. The integration agent reviewed every changed line
  and reran five focused tests. An independent read-only adversarial reviewer
  verified exact ancestry/path scope, product authority, arithmetic, tamper,
  restart, exact-port/upstream-failure/cancellation and isolation behavior,
  passed five focused and all 189 target tests in 44 suites plus isolation, and
  found no P0-P3 defect. The candidate is integrated as `ddbe7d7b`; the slice
  is `implemented`, not verified. The complete local integration gate passes
  conversion/capability/query/residual/M0 controls, target isolation/generated
  app-MCP contracts, five focused/all 189 tests in 44 suites, repeatable project
  generation, both staging builds and clean formatting. Immutable exact-
  checkpoint CI remains required. No provider, Firebase or production action
  occurred.
- The complete local ready gate passed all 184 target tests in 43 suites,
  target isolation/contracts, repeatable project generation, both staging
  builds, conversion/capability/query/residual/M0 controls and the exact
  expected M1/M2 holds. Exact ready commit `43189f1a` passed immutable Actions
  run `33687191592`: conversion traceability in 11 seconds and the isolated
  target environment in 2 minutes 3 seconds. `SUBAGENT-PILOT-002` is now
  recorded from that exact base in its own branch/worktree with only the two
  scaffold Swift paths writable. No provider, Firebase or production action
  occurred.
- Exact integration checkpoint
  `8fce53b75029133b39fe182031df25ef011fc35e` passed immutable Actions run
  `33689446640`: conversion traceability passed in 11 seconds and the isolated
  target environment passed in 2 minutes 30 seconds with all 189 tests in 44
  suites, generated contracts, both staging builds and clean tracked artifacts.
  Promoted exactly the Project budget segment dossier and its two surfaces to
  `verified`. `SUBAGENT-PILOT-002` is complete, and both required enhanced
  write-capable pilots now preserve worker, every-line integration and
  independent adversarial review evidence. No provider, Firebase or production
  action occurred.
- Completed the first-two-pilot quality audit and retained its controls as
  permanent policy. Both accepted workers changed only their allowlisted paths
  and had no accepted P0-P2 defect, but review materially improved the work:
  pilot 1 received a P3 documentation correction, Inventory planning was
  rejected before delegation for missing authority/O-038, and pilot 2 was
  reduced from approximately 1,076 to 768 added lines before commit. Worker
  output remains untrusted until exact ancestry/path and line review, complete
  local gates, central regeneration and exact integrated-SHA CI pass;
  independent adversarial review remains mandatory for novel shared semantics
  and accounting/security/Sync/migration/provider/release risk.
- A fresh primary and independent read-only preflight approved
  `project-item-link-presentation-contracts` only as a narrow stateless leaf.
  Two comment-only target paths, six requirements and five planned obligations
  now cover exact Unaccounted/Accounted labels and order, authoritative
  Unaccounted-only Link availability, exact prompt/two-choice membership without
  imposing choice order, fail-closed Accounted/incomplete rows, side-effect-free
  dismissal, restart re-projection and provider isolation. The broader Link
  flow is NO-GO: no command/route, Purchase selection/eligibility, acquisition
  handling, transient persistence, Accounted-item behavior, app/MCP, schema/
  RLS/Sync/provider, migration or production authority exists. Deterministic
  state is 795 recorded / 780 discovered, 366 mapped-or-later / 167 residual /
  44 blockers with only the three documented retired-path warnings. No worker,
  provider, Firebase or production action occurred.
- The complete Project Item Link presentation ready gate passes conversion,
  capability, query, regenerated residual and M0 controls, target isolation,
  generated app/MCP contracts, all 189 existing target tests in 44 suites,
  two identical project generations, macOS and iOS staging builds and clean
  formatting. The slice remains comment-only and cannot enter implementation
  until immutable CI passes on the exact ready commit.
- Exact ready commit `47f8fe0d148de617154e40da22bf02d2b47aefc2`
  passed immutable Actions run `33690917866`: conversion traceability passed in
  9 seconds and the isolated target environment passed in 2 minutes 14 seconds
  with all 189 existing tests, generated contracts, both staging builds and
  clean artifacts. Implemented only the two frozen presentation paths. The
  primary agent reviewed every changed line; an independent adversarial review
  found no P0-P2 defect and one P3 self-referential payer-membership assertion.
  That assertion now independently proves exhaustive enum membership and the
  literal unordered two-choice descriptor set; the reviewer confirmed the fix.
  Four focused/all 193 target tests in 45 suites, isolation, generated app/MCP
  contracts, repeatable project generation and both staging builds pass
  locally. The slice is `implemented`, not verified, until final synchronized
  controls and immutable exact-implementation-checkpoint CI pass. No provider,
  Firebase or production action occurred.
- Exact implementation commit
  `d7f4286be2a2fe7f4a8c8e7d59a59547114e47e4` passed immutable Actions run
  `33691932385`: conversion traceability passed in 10 seconds and the isolated
  target environment passed in 2 minutes 19 seconds with all 193 target tests
  in 45 suites, generated contracts, both staging builds and clean tracked
  artifacts. Promoted exactly the Project Item Link presentation dossier and
  its two surfaces to `verified`. The broader Link flow remains unimplemented
  and blocked from this leaf. No provider, Firebase or production action
  occurred.
- Prepared `space-core-details-read-contracts` as a bounded provider-free read
  with exactly two comment-only target paths, eight requirements and six
  planned obligations. Primary and independent adversarial preflight approved
  the slice only after clarifying that exact timestamps are not audit
  provenance, incomplete checklist counts are not authoritative, archived
  detail is not absence, nested Item IDs are unique within a checklist rather
  than globally, and zero-item progress has counts but no invented percentage.
  Deterministic state is 797 recorded / 782 discovered, 368 mapped-or-later /
  167 residual / 44 blockers, and 46 slices claim 113 of 535 target-relevant
  surfaces. The complete local ready gate passes conversion/target/generated-
  contract controls, all 193 existing tests in 45 suites, repeatable XcodeGen
  output and both staging builds. At that local checkpoint no worker
  implementation, provider, Firebase or production action had occurred;
  exact-ready-SHA immutable CI was the remaining prerequisite.
- Exact ready commit
  `8849344dc66d71d9dd9b9ba589a76deb007f3172` passed immutable Actions run
  `33693232878`: conversion traceability passed in 12 seconds and isolated
  target verification passed in 2 minutes 32 seconds with all 193 existing
  tests, generated contracts, both builds and clean tracked artifacts.
  `SUBAGENT-WORK-003` is recorded from that exact base in isolated branch/
  worktree `codex/supabase-slice-space-core-details` /
  `/Users/benjaminmackenzie/Dev/ledger_mobile_supabase_space_core_details`, with
  only the two Space core-details scaffold paths writable. Every-line primary
  review, independent adversarial review, complete local gates and exact
  integrated-SHA CI remain mandatory. No provider, Firebase or production
  action occurred.
- Space core-details candidate `1920389d28a71fff3b3233bef2971fe9525bc6e3`
  was integrated as `72b24afa`/`503b3839`/`05509124` after the primary agent
  reviewed every source/test line and an independent adversarial reviewer
  checked the exact frozen-base diff. The review process caught four concrete
  test-quality gaps: direct normalization refusal for notes/checklist names/item
  text, independent AccountID/SpaceID fingerprint binding, port-side request
  validation, and exact unique diagnostic-code stability. Each was corrected,
  re-reviewed and retested. Six focused and all 199 target tests in 46 suites,
  target isolation/generated-contract checks, repeatable project generation,
  both staging builds and clean diff checks pass with no remaining P0-P3
  finding. Exact integration checkpoint
  `d5afa699ce09c105a82b187f9953e06a09ac2b10` then passed immutable Actions
  run `33695588031`: conversion traceability passed in 10 seconds and isolated
  target verification passed in 3 minutes 16 seconds with all 199 tests,
  generated contracts, both builds and clean tracked artifacts. The slice and
  its two surfaces are `verified`. No provider, Firebase or production action
  occurred.
- Rescouted the next boundary after Space core details. A read-only scout and an
  independent adversarial reviewer approved only
  `project-core-details-read-contracts`: exact Account/Project/Client core
  identity, verified ProjectSummary fields, canonical optional description,
  exact locally observed Project revision and explicit local readiness/
  absence/failure truth. The review requires revision to remain local conflict-
  precondition evidence distinct from LocalDataVersion, accepts an active
  Project with an archived Client, and rejects any complete-workspace, current
  Firebase/app/MCP, child, media, accounting, mutation, authorization,
  provider/schema/RLS/Sync, migration or production claim. Two new target-only
  paths contain comments only. The complete local ready gate passes: all 199
  existing target tests in 46 suites, repeatable XcodeGen output, both staging
  builds, target isolation/generated contracts and clean-artifact checks pass.
  Exact ready commit `4fd81f477f87de9528c25559d0950dbdd0136717`
  passed immutable Actions run `33697079580`: traceability passed in 13 seconds
  and isolated target verification passed in 2 minutes 51 seconds. Registered
  `SUBAGENT-WORK-004` on branch
  `codex/supabase-slice-project-core-details` in isolated worktree
  `/Users/benjaminmackenzie/Dev/ledger_mobile_supabase_project_core_details`,
  with only the two scaffold paths writable. Every-line primary review,
  independent adversarial review, complete integration gates and exact
  integration-commit CI remain mandatory. No provider, Firebase or production
  action occurred.

## Next Action

Continue without waiting on the two M1 evidence blockers:

1. Treat `operation-lifecycle-and-readiness` and
   `EVID-OPERATION-CORE-001` as the shared semantic dependency for every later
   operation slice. Do not recreate queued/applied/rejected, idempotency,
   readiness or error behavior independently in app, MCP, SQL or adapters.
2. Treat `transaction-taxonomy-and-transfer-identity` and
   `EVID-TRANSACTION-TAXONOMY-001` as the sole shared semantic source for later
   Transaction classification, scope, route and pair identity. Do not recreate
   or extend that meaning independently in app, MCP, SQL or adapters.
3. Treat `non-item-receipt-line-reconstruction-contracts` and
   `EVID-RECEIPT-RECONSTRUCTION-001` as the sole shared semantic source for
   embedded receipt lines and exact reconstruction evidence. Do not recreate
   or extend that meaning independently in app, MCP, SQL or adapters. Treat the
   verified `project-item-accounting-section-contracts` and
   `EVID-PROJECT-ITEM-ACCOUNTING-001` as the sole shared read semantics for
   relationship-derived Project Item sections. Treat the verified
   `attachment-capture-and-local-durability-receipt` dossier and
   `EVID-ATTACHMENT-CAPTURE-001` as the sole shared semantic source for stable
   capture identity, exact local-byte evidence and success-shaped receipts.
   Treat the verified `client-creation-operation-contracts` dossier and
   `EVID-CLIENT-CREATION-001` as the sole Client-create semantic authority.
   Treat the verified `project-setup-operation-contracts` dossier and
   `EVID-PROJECT-SETUP-001` as the sole CreateProject semantic authority for
   existing/new Client selection and complete absent/null/zero category intent.
   Treat the verified `project-archive-operation-contracts` dossier and
   `EVID-PROJECT-ARCHIVE-001` as the sole ArchiveProject semantic authority.
   Treat the verified `budget-category-reference-read-contracts` dossier and
   `EVID-BUDGET-CATEGORY-REFERENCE-001` as the sole shared read semantics for
   category identity/kind/lifecycle/system/exclusion/order/revision,
   eligibility, visible-count privacy and local readiness. Treat the verified
   `project-category-configuration-read-contracts` dossier and
   `EVID-PROJECT-CATEGORY-CONFIGURATION-001` as the sole shared read semantics
   for exact Account/Project/category configuration state, absent/null/zero/
   positive allocation, incomplete relationship evidence and configuration
   revision. Treat the verified `client-rename-operation-contracts` dossier and
   `EVID-CLIENT-RENAME-001` as the sole RenameClient semantic authority.
   Treat the verified `project-rename-operation-contracts` dossier and
   `EVID-PROJECT-RENAME-001` as the sole RenameProject semantic authority.
   Treat the verified `project-note-read-contracts` dossier and
   `EVID-PROJECT-NOTE-READ-001` as the sole shared read semantics for stable
   Project-note identity, audit/tombstone evidence, deterministic bounded order
   and explicit offline-history completeness. Treat the verified
   `project-note-creation-operation-contracts` dossier and
   `EVID-PROJECT-NOTE-CREATION-001` as the sole AddProjectNote semantic
   authority. Treat the verified `project-preference-read-contracts` dossier
   and `EVID-PROJECT-PREFERENCE-READ-001` as the sole current-Principal Project
   preference read semantics. Treat the verified
   `project-preference-update-operation-contracts` dossier and
   `EVID-PROJECT-PREFERENCE-UPDATE-001` as the sole UpdateProjectPreferences
   semantics. Treat the verified `vendor-suggestion-reference-read-contracts`
   dossier and `EVID-VENDOR-SUGGESTION-REFERENCE-001` as the sole vendor-
   suggestion read semantics. Treat the verified
   `space-template-reference-read-contracts` dossier and
   `EVID-SPACE-TEMPLATE-REFERENCE-001` as the sole Space-template read semantics.
   Treat the verified `client-archive-operation-contracts` dossier and
   `EVID-CLIENT-ARCHIVE-001` as the sole ArchiveClient semantic authority.
   Treat the verified `project-details-update-operation-contracts` dossier and
   `EVID-PROJECT-DETAILS-UPDATE-001` as the sole UpdateProjectDetails semantic
   authority. Treat `space-creation-operation-contracts` and
   `EVID-SPACE-CREATION-001` as the sole direct provider-free CreateSpace
   semantic authority. Treat `space-details-update-operation-contracts` and
   `EVID-SPACE-DETAILS-UPDATE-001` as the sole provider-free
   UpdateSpaceDetails semantic authority. The exact implementation commit and
   both CI jobs are verified. Treat
   `space-checklist-revision-operation-contracts` and
   `EVID-SPACE-CHECKLIST-REVISION-001` as the sole provider-free
   ReviseSpaceChecklists semantic authority. Its exact implementation commit and
   both CI jobs are verified. Treat the verified
   `session-ending-pending-work-contracts` dossier and
   `EVID-SESSION-ENDING-POLICY-001` as the sole provider-free safety authority
   for exact pending-work summaries and clean/sync-first/destructive session
   dispositions. Its exact implementation commit and both CI jobs are
   verified. Treat the verified `account-discovery-and-selection-contracts`
   dossier and `EVID-ACCOUNT-DISCOVERY-SELECTION-001` as the sole authority for
   the bounded provider-free discovery/selection-intent boundary. Its exact
   implementation commit and both CI jobs are verified. Treat the verified
   `item-space-assignment-operation-contracts` dossier and
   `EVID-ITEM-SPACE-ASSIGNMENT-001` as the sole authority for the bounded
   provider-free AssignItemsToSpace boundary. Its exact implementation commit
   and both CI jobs are verified. Treat the verified
   `item-space-clearing-operation-contracts` dossier and
   `EVID-ITEM-SPACE-CLEARING-001` as the sole authority for explicit
   Item-placement clearing. Its exact implementation commit and both CI jobs
   are verified. Treat the verified `space-assignment-destination-read-contracts`
   dossier and
   `EVID-SPACE-ASSIGNMENT-DESTINATION-001` as the sole verified provider-free
   assignment-destination read semantics. Treat the verified
   `project-budget-segment-read-contracts` dossier and
   `EVID-PROJECT-BUDGET-SEGMENT-001` as the sole provider-free source for exact
   Project category client-paid/invoicing-unpaid segments and their internally
   derived recognized value. Preserve both completed enhanced-pilot review
   records. Do not implement Inventory destination planning until O-038 is
   explicitly approved in canonical product authority. Both enhanced pilots
   passed; retain the conductor, isolated-worktree, frozen-slice, path-allowlist,
   independent review and exact-integration-SHA CI controls, and apply review
   depth according to novelty and accounting/security risk without allowing a
   worker to promote its own status or edit canonical integration controls.
   Treat the verified `project-item-accounting-section-contracts` resolution as
   the sole input authority for the ready
   verified `project-item-link-presentation-contracts` leaf as the sole target
   presentation authority for exact section/action/question/payer vocabulary,
   authoritative Unaccounted-only Link availability and no-action dismissal.
   Keep
   actual Link routes/commands, Purchase choice/eligibility, acquisition
   handling, correction/relink behavior, transient UI state, Accounted-item
   actions, app/MCP and provider/migration behavior outside this slice.
   Treat verified `space-core-details-read-contracts` and
   `EVID-SPACE-CORE-DETAILS-001` as the sole provider-free single-Space core
   detail read authority. Preserve the completed every-line and independent
   adversarial reviews, their four corrected findings and exact integration
   run `33695588031`. Do not let later slices recreate or extend timestamp provenance,
   authoritative partial counts, percentage policy, archive effects,
   Item/media/review/template/accounting, provider/schema/RLS/Sync, app/MCP,
   migration or production behavior.
   Treat ready `project-core-details-read-contracts` and
   `EVID-PROJECT-CORE-DETAILS-001` as the next frozen implementation boundary.
   Exact comment-only ready commit `4fd81f47` passed complete local gates and
   immutable Actions run `33697079580`. Continue only through registered
   `SUBAGENT-WORK-004`, limited to its two paths, and retain primary every-line
   plus independent adversarial review because
   the slice composes shared Project/Client, canonical-description, revision and
   offline-readiness semantics. Do not let it become a Project workspace or
   acquire children, media, accounting, mutation, authorization, provider,
   schema/RLS/Sync, app/MCP, migration or production behavior.
   Keep
   first-use defaults,
   category visibility resolution, authentication, physical persistence,
   authoritative parent preflight/audit assignment, note edit/remove/role
   policy, schema/RLS/Sync/Auth/provider behavior, app/MCP/search, migration,
   hosted resources and production access excluded unless their named gates
   are resolved.
4. Do not enter hosted/provider-specific Phase 2, identity/Auth, encrypted
   local persistence, media retention, or product-command work while its named
   A-/O-/credential/spend gates remain open.
5. Keep `target-environment-isolation` in progress with successful external CI
   recorded. Complete only the later signed/visual/physical staging and actual
   hosted-resource projection portions when their credentials/resources and
   authorization exist; do not wait on those gates before continuing other
   decision-independent target foundations and do not reattach target files to
   `LedgeriOS.xcodeproj`.
6. Keep the target projection explicitly `unprovisioned` until isolated hosted
   resource IDs, staging-only credentials, maximum spend/run-rate, cleanup
   owner, and the applicable spike authorization are explicit. Do not replace
   synthetic IDs with guesses or production identifiers.
7. Preserve the decision-packet queue as proposals until product approval. Every
   generated product blocker now has a packet; O-021 remains an explicit UI-only
   UX experiment rather than a schema gate.
8. Do not execute the prepared vertical-spike protocol until isolated hosted
   resources, staging-only credentials, maximum spend/run-rate, cleanup owner,
   device matrix, and pre-measurement hard caps are explicitly authorized. When
   authorized, begin at S0 and stop fail-closed on any unknown/production ID.
9. When the user approves a product decision, update its canonical spec and
   decision log first, then traceability, architecture, affected batch mappings/
   evidence and this state. Keep one target operation/query authority across app
   and MCP and do not create a Firebase application adapter.
10. Keep A-003/A-004 proposed until the isolated vertical spike passes. The spike
   may use synthetic staging only and must prove encrypted local durability,
   scoped Sync Streams, idempotent operations/rejection, media restart, RLS, and
   offline provenance before provider-specific architecture is approved.
11. When an external chmod-600 service-account JSON whose `project_id` is exactly
   `ledger-nine4`, or a separately proven canonical immutable production export,
   becomes available, run the fail-closed read-only profiling/reconciliation
   flow. Do not copy credentials into the repository, substitute authorized-user
   ADC, or treat emulator exports as production evidence without provenance.

M1 correctly remains blocked by `MAN-DATA-001` and `MAN-CUTOVER-001`. This does
not authorize target implementation and does not prevent honest bounded M2
mapping for ready capabilities.

## Active Blockers and Gates

- O-002 through O-037 remain product blockers where referenced by the decision
  traceability table.
- A-003 and A-004 remain proposed until the vertical spike passes.
- A-007 target authentication choice is open.
- A-015 optimistic complex-operation projection is blocked on the spike.
- A-016 offline authorization lease needs product/security approval.
- O-022 source freeze and rejected-write recovery is unresolved.
- Production data/Auth/Storage shape is statically cataloged but not confirmed
  by a canonical read-only profile/export.
- `MAN-INDEX-001` is statically characterized; deployed index/runtime evidence
  is still open.
- Production profiling is blocked on an external chmod-600 service-account JSON
  for `ledger-nine4`; the configured authorized-user ADC is deliberately not
  accepted by the profiler.
- Identity provider/correlation remains blocked on A-007; offline authorization
  lease/unlock remains blocked on A-016 and product/security approval.
- Attachment reference removal versus permanent byte deletion, shared-reference
  retention and financial/history evidence handling remain blocked on O-023.
- Project deletion, Client reassignment/merge and reference-data mutation
  authority remain blocked on O-024–O-026.
- Unified Item minimum identifying evidence remains blocked on O-027.
- Non-cash vendor credit, Transaction void/delete, receipt rounding/Item tax
  basis and canonical Transaction draft/posting remain blocked on O-028–O-032.
- Actual collection-payment variance and sent-Invoice membership/revision/
  delivery audit remain blocked on O-033/O-034. The safe provisional target
  rejects amount mismatches and does not expose sent-membership mutation.
- Client Summary financial meaning and client-shared receipt delivery remain
  blocked on O-035/O-036; report code cannot choose a metric or expose raw/
  expiring private-object URLs.
- Space archive effects on assigned Items remain blocked on O-037; the safe
  provisional behavior retains a resolvable archived placement and requires an
  explicit move/clear.

## Resume Commands

```bash
node scripts/supabase-conversion-ledger.mjs check
git status --short
node scripts/supabase-conversion-ledger.mjs report
npm run conversion:gate:m0
npm run conversion:gate:m1
npm run target:environment:check
npm run target:environment:test
npm run target:staging:build:macos
npm run target:staging:build:ios
```

If `check` reports new or missing surfaces, resolve discovery drift before
continuing implementation. If the user supplies a newer product decision, update
the decision log first, then traceability, manifest entries, and execution state.

## Last Verification

Verified 2026-08-31 at source baseline
`d83c64724fe4e92be27c62f425979bd30fcfc9bb` in the pre-existing dirty shared
worktree:

- `node --check scripts/supabase-conversion-ledger.mjs` — pass;
- `npm run conversion:sync` — 679 recorded / 667 automatic / 12 manual, zero
  errors and zero warnings;
- `npm run conversion:check` — pass;
- `npm run conversion:report` — pass;
- check invoked from `/tmp` by absolute script path — pass;
- M0 gate — correctly blocked by 677 unclassified surfaces; and
- cumulative M2 gate — correctly blocked by 678 prerequisite/target surfaces.

Backend characterization checkpoint verified later on 2026-08-31:

- four classification batches synchronized — 79 surfaces;
- 679 recorded / 667 automatic / 12 manual surfaces;
- 598 unclassified surfaces remain;
- 77 surfaces are characterized, three are blocked, and the control surface is
  verified;
- zero missing sources, structural errors, or warnings;
- M0 correctly blocked by 598 surfaces; and
- M1 correctly blocked by 601 prerequisite surfaces.

The static backend checkpoint is complete. M0 is not complete, and no
app/backend implementation or production operation has been performed.

Query/profiler checkpoint verified later on 2026-08-31:

- 684 recorded / 672 automatic / 12 manual surfaces;
- 595 unclassified surfaces remain;
- 84 surfaces are characterized, two are blocked, and three control/tool
  surfaces are verified;
- deterministic query generation/check passed with 169 candidates, 74 files
  containing recognized operations, and 386 occurrences;
- profiler syntax, help, mutation guard, and intentional missing-credential
  refusal passed;
- conversion sync/check/report passed with zero errors and warnings; and
- M0 correctly remains blocked by 595 unclassified surfaces.

No Firebase production read or mutation and no Supabase implementation occurred
at this checkpoint.

Capability guidance/catalog checkpoint verified later on 2026-08-31:

- 685 recorded / 673 automatic / 12 manual surfaces;
- 595 unclassified surfaces remain;
- 84 surfaces are characterized, two are blocked, and four control/tool
  surfaces are verified;
- capability evolution is now a required G0.5 gate before target schema;
- all 88 Swift service/Auth and MCP files are assigned to 11 capability groups;
- capability generation/check passed with zero unassigned files;
- exact reviewed `acknowledgeSourceHash` is required for deliberate changes to
  previously characterized automatic surfaces; and
- intentional wrong-hash acknowledgment failed as required;
- conversion sync/check/report passed with zero errors and warnings; and
- production evidence and capability dossier decisions remain explicitly open.

Identity/lifecycle dossier checkpoint verified later on 2026-08-31:

- 685 recorded / 673 automatic / 12 manual surfaces;
- 584 unclassified surfaces remain;
- 95 surfaces are characterized, two are blocked, and four control/tool
  surfaces are verified;
- 11 additional identity/session/model/UI/MCP/test surfaces were characterized;
- stale auth/offline spec assumptions were corrected without choosing a target
  provider or lease policy;
- conversion sync/check/report passed with zero errors and warnings; and
- M0 correctly remains blocked by 584 unclassified surfaces.

Media/attachment dossier checkpoint verified later on 2026-08-31:

- 685 recorded / 673 automatic / 12 manual surfaces;
- 540 unclassified surfaces remain;
- 139 surfaces are characterized, two are blocked, and four control/tool
  surfaces are verified;
- 44 additional media/local/UI/MCP/test/fixture/migration surfaces were
  characterized by `M0-MEDIA-LIFECYCLE-001`;
- static source/spec review found no uniform current local-display or durable
  enqueue contract and did not treat those defects as target parity;
- O-023 and the target attachment lifecycle are traced through product,
  architecture, tracker, dossier and tests;
- classification JSON, conversion sync/check/report passed with zero errors and
  warnings; and
- M0 correctly remains blocked by 540 unclassified surfaces.

No Firebase production read or mutation and no Supabase/PowerSync application,
schema, Storage policy, or migration implementation occurred at this checkpoint.

Projects/Clients/reference-data dossier checkpoint verified later on 2026-08-31:

- 685 recorded / 673 automatic / 12 manual surfaces;
- 486 unclassified surfaces remained;
- 193 surfaces were characterized, two blocked and four verified;
- 54 Project/Client/note/category/preference/vendor/template/UI/MCP/test
  surfaces were characterized by `M0-PROJECT-CLIENT-REFERENCE-001`;
- O-024–O-026 and the target-neutral Client/Project/reference contracts were
  traced through product, architecture, tracker, dossier and tests; and
- conversion sync/check/report passed with zero errors and warnings.

Unified Item creation/Link dossier checkpoint verified later on 2026-08-31:

- 685 recorded / 673 automatic / 12 manual surfaces;
- 434 unclassified surfaces remain;
- 245 surfaces are characterized, two blocked and four verified;
- 52 Item/proto/service/model/UI/MCP/test surfaces were characterized by
  `M0-ITEM-CREATION-LINK-001`;
- stale runtime Firebase dual-read guidance was removed, and O-027 was added to
  the decision log and architecture traceability;
- classification JSON and conversion sync/check/report passed with zero errors
  and warnings; and
- M0 correctly remains blocked by 434 unclassified surfaces.

Inventory/provenance/Transaction dossier checkpoint verified later on
2026-08-31:

- 685 recorded / 673 automatic / 12 manual surfaces;
- 353 unclassified surfaces remain;
- 326 surfaces are characterized, two blocked and four verified;
- 81 Inventory/Transaction/lineage/service/model/UI/MCP/test/migration surfaces
  were characterized by `M0-INVENTORY-TRANSACTION-001`;
- Vendor Credit target conflict and O-028–O-032 were traced through product,
  architecture, tracker, dossier and tests;
- classification JSON and conversion sync/check/report passed with zero errors
  and warnings; and
- M0 correctly remains blocked by 353 unclassified surfaces.

Invoicing/collection/budget dossier checkpoint verified later on 2026-08-31:

- 685 recorded / 673 automatic / 12 manual surfaces;
- 291 unclassified surfaces remain;
- 388 surfaces are characterized, two blocked and four verified;
- 62 Invoice/Fee/budget/vendor-import/service/model/UI/MCP/test/migration
  surfaces were characterized by `M0-INVOICING-BUDGET-001`;
- O-033/O-034 and the target-neutral source, whole-collection, immutable-paid,
  and stable budget-contribution contracts were traced through product,
  architecture, tracker, dossier, evidence and tests;
- classification JSON, conversion sync/check/report, capability/query generated
  checks, and `git diff --check` passed with zero errors and warnings; and
- M0 correctly remains blocked by 291 unclassified surfaces.

No Firebase production read or mutation and no Supabase/PowerSync application,
schema, RLS, Sync Stream, migration or production operation occurred at this
checkpoint.

Reporting/search dossier checkpoint verified later on 2026-08-31:

- 42 report/search/export/calculation/MCP/test/manual surfaces were classified
  by `M0-REPORTING-SEARCH-001`;
- O-035/O-036 and the typed readiness/version/visibility-safe projection
  contracts were traced through product, architecture, tracker and evidence;
- conversion sync/check/report, capability/query checks and diff validation
  passed.

Spaces/review dossier checkpoint verified later on 2026-08-31:

- 33 Space/checklist/assignment/review/work-queue/MCP/test/migration surfaces
  were classified by `M0-SPACES-REVIEW-001`;
- O-037 and typed Space/review/archive/readiness contracts were traced through
  product, architecture, tracker and evidence; and
- conversion sync/check/report, capability/query checks and diff validation
  passed.

Platform/control dossier checkpoint verified later on 2026-08-31:

- 101 app-composition/environment/MCP/release/hosting/source-tool/reverse-
  migration surfaces were classified by `M0-PLATFORM-CONTROL-001`;
- target generic Firestore repositories, fallback production identities,
  unauthenticated MCP Account context, stale manual schema authority and reverse
  migration reuse were explicitly rejected; and
- conversion sync/check/report, capability/query checks and diff validation
  passed.

Whole-manifest M0 checkpoint verified later on 2026-08-31:

- 115 final app-shell/presentation/navigation/platform-capture/test surfaces
  were classified by `M0-APP-SHELL-PRESENTATION-001`;
- 685 total surfaces across 17 batches have 679 characterized, four verified
  and two explicitly blocked states;
- dispositions are 134 preserve, 186 redesign, 239 replace, 37 retire, 87
  source-only and two migrate;
- zero unclassified, missing behavior, missing evidence, missing batch,
  source-drift, structural-error or warning gaps remain;
- conversion sync/check/report, deterministic capability/query checks,
  classification JSON validation and `git diff --check` passed;
- `M0 PASS: Inventory classified`; and
- M1 correctly remains blocked by exactly `MAN-DATA-001` and
  `MAN-CUTOVER-001`.

No production Firebase read or mutation, Firebase application implementation,
Supabase/PowerSync schema/application implementation, migration, release, or
cutover occurred at this checkpoint.

M2 foundation checkpoint verified later on 2026-08-31:

- 62 target-relevant surfaces are exactly `target_mapped`: 39 app-shell, eight
  identity/session and 15 media/local-durability surfaces;
- the media batch has exactly four intentional mapping holds, all tied to O-023
  and the canonical production reference/object profile;
- mapped-field completeness checks found zero missing owner, target surface,
  security, Sync, migration, reconciliation, test or acceptance fields; and
- no production read/mutation or target implementation occurred.

M2 platform-control checkpoint verified later on 2026-08-31:

- 100 target-relevant surfaces are exactly `target_mapped`: the prior 62 plus
  38 platform/environment/MCP/release/control surfaces;
- the platform batch has exactly three intentional mapping holds tied to
  A-003/A-004, A-015/A-016/physical verification and O-008/O-031;
- exact-field completeness found zero missing owner, target surface, security,
  Sync, migration, reconciliation, test or acceptance fields; and
- A-003/A-004 remain proposed; no target implementation, production operation,
  deployment, release or cutover occurred.

M2 Client/Project/reference checkpoint verified later on 2026-08-31:

- 136 target-relevant surfaces are exactly `target_mapped`: the prior 100 plus
  36 Client/Project/reference surfaces;
- the batch has exactly 16 intentional holds tied only to O-024, O-025 or
  O-026, where the decision can change the command/retention/security boundary;
- exact-field completeness found zero missing owner, target surface, security,
  Sync, migration, reconciliation, test or acceptance fields; and
- no production operation or Supabase/PowerSync implementation occurred.

M2 stable Item checkpoint verified later on 2026-08-31:

- 150 target-relevant surfaces are exactly `target_mapped`: the prior 136 plus
  14 Item query/port/bulk/test surfaces;
- the Item batch has exactly 17 intentional holds tied to A-015 or
  O-007/O-015–O-019/O-023/O-027; O-021 is recorded as UI-only, not an
  architecture blocker;
- exact-field completeness found zero missing owner, target surface, security,
  Sync, migration, reconciliation, test or acceptance fields; and
- no production operation or target implementation occurred.

M2 stable reporting/search checkpoint verified later on 2026-08-31:

- 231 target-relevant surfaces are exactly `target_mapped`: the prior 212 plus
  19 reporting/search/export surfaces;
- the batch has exactly 18 intentional holds tied to A-015 or underlying
  accounting/report/delivery decisions, including O-035/O-036;
- exact-field completeness found zero missing owner, target surface, security,
  Sync, migration, reconciliation, test or acceptance fields; and
- no production operation or target implementation occurred.

M2 whole-manifest stable-mapping audit verified later on 2026-08-31:

- all 427 target-relevant surfaces were audited across 17 batches;
- 263 are exactly `target_mapped` and 164 remain explicitly held;
- zero mapped entries are missing owner, target surface, security, Sync,
  migration, reconciliation, test or acceptance fields;
- zero held target-relevant entries have an empty blocker list;
- M0 passes, M1 remains blocked by exactly `MAN-DATA-001` and
  `MAN-CUTOVER-001`, and M2 correctly remains blocked by 164 surfaces; and
- no production operation, target implementation, deployment, release,
  migration or cutover occurred.

M2 stable Spaces/review checkpoint verified later on 2026-08-31:

- 212 target-relevant surfaces are exactly `target_mapped`: the prior 196 plus
  16 Space/review surfaces;
- the batch has exactly 11 intentional holds tied to O-023/O-026/O-032/O-037
  or A-015;
- exact-field completeness found zero missing owner, target surface, security,
  Sync, migration, reconciliation, test or acceptance fields; and
- no production operation or target implementation occurred.

M2 stable Invoicing/budget checkpoint verified later on 2026-08-31:

- 196 target-relevant surfaces are exactly `target_mapped`: the prior 175 plus
  21 Invoicing/budget surfaces;
- the batch has exactly 23 intentional holds tied to mapping-changing A/O
  decisions, including explicit O-009/O-010 and O-033/O-034 coverage;
- exact-field completeness found zero missing owner, target surface, security,
  Sync, migration, reconciliation, test or acceptance fields; and
- no production operation or target implementation occurred.

M2 stable Inventory/Transaction checkpoint verified later on 2026-08-31:

- 175 target-relevant surfaces are exactly `target_mapped`: the prior 150 plus
  25 Inventory/Transaction/provenance surfaces;
- the batch has exactly 41 intentional holds, each tied to a mapping-changing
  A/O decision rather than a generic implementation placeholder;
- exact-field completeness found zero missing owner, target surface, security,
  Sync, migration, reconciliation, test or acceptance fields; and
- no production operation or target implementation occurred.

Complete product-packet/spike-protocol checkpoint verified later on 2026-08-31:

- 16 packet files cover all 35 generated product blockers and all 157 residual
  surfaces with any product blocker; O-021 is explicitly UI-only;
- the seven other residual surfaces depend only on architecture/spike, physical-
  target verification, or canonical-production-evidence blockers;
- the S0–S9 vertical-spike protocol and prepared evidence record cover A-003/
  A-004/A-007/A-015/A-016 and physical verification without approving them;
- all 63 required D-001–D-027/O-002–O-037 traceability rows exist exactly once;
- all relative Markdown links across 87 redesign architecture/program files
  resolve and all 16 packet index targets exist;
- all 16 packets pass the required decision/constraints/options/target/security/
  migration/tests/consequences/checklist structure audit;
- residual and query artifacts were regenerated; conversion sync/check/report,
  capability/query/residual checks and `git diff --check` pass;
- M0 passes at 686 total / 674 discovered surfaces, M1 correctly remains blocked
  by two surfaces, and M2 correctly remains blocked by 164 surfaces; and
- no production read/mutation, Firebase adapter/v2 implementation, target DDL/
  implementation/deployment, migration, release or cutover occurred.

Product-authority cross-reference checkpoint verified on 2026-09-01:

- all 686 surfaces resolve through 18 batches to reviewed authority sets: 573
  product-governed and 113 technical/control;
- all five target specs then registered were represented and explicitly separated from
  current-product, historical-evidence, architecture and conversion-control
  roles;
- the generated JSON records every stable surface ID and the generated Markdown
  publishes batch/spec counts; both are freshness-checked;
- explicit canonical-target reconciliation is present across the affected
  capability dossiers and the specs index now foregrounds the new redesign
  specs;
- conversion sync/check/report and M0 passed with 686 recorded / 674 discovered
  surfaces, zero errors and zero warnings; and
- no production read/mutation, Firebase application implementation, target DDL/
  implementation/deployment, migration, release or cutover occurred.

Vertical-slice implementation-method checkpoint verified on 2026-09-01:

- one required method now governs exact authority-to-requirement-to-contract-to-
  verification-to-evidence traceability for every future target slice;
- the template covers domain, Postgres, handlers, Data API grants, RLS, Sync,
  offline/local, media, app/MCP, migration/reconciliation, operations and
  rollout/rollback obligations;
- conversion checking accepts a fully traced ready dossier, rejects an
  incomplete ready dossier, and rejects an implemented target surface without
  a correspondingly advanced slice;
- the clean generated audit correctly reports zero slices, zero claimed target
  surfaces and zero implementation-advanced target surfaces because target
  implementation has not begun;
- conversion sync/check/report, capability/query/residual checks and M0 pass at
  686 recorded / 674 discovered surfaces with zero errors and warnings; and
- no production read/mutation, Firebase application implementation, target DDL/
  implementation/deployment, migration, release or cutover occurred.

Target-environment isolation checkpoint verified later on 2026-09-01:

- `target-environment-isolation` is the first active implementation dossier;
  four of five verification obligations pass and the external-CI/complete
  operational obligation remains planned;
- the provider-free `LedgerTargetCore` graph check passes and all 12 package
  tests pass;
- repeated XcodeGen generation produced stable target project/scheme hashes;
- the separate `LedgerTargetStaging` application builds for macOS and generic
  iOS Simulator with bundle `apps.nine4.ledger.staging`, product/display name
  `Ledger STAGING`, and no signing;
- the source Firebase `LedgeriOS.xcodeproj` has no checkpoint diff and the
  target graph contains no Firebase, Google Sign-In, Supabase, or PowerSync SDK;
- conversion sync/check pass at 699 recorded / 684 discovered surfaces with
  zero errors and three explained retired-path warnings;
- the target CI job is defined but has no external run evidence yet; and
- no hosted resource, credential, network backend, production read/mutation,
  deployment, migration, release, branch/ref operation, or cutover occurred.
