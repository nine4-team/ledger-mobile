# Supabase Conversion Execution State

Last updated: 2026-09-01
State version: 64

## Objective

Create a complete, evidence-backed inventory and Supabase/PowerSync target
mapping for the entire Ledger application, then implement and rehearse it without
modifying the running Firebase application before hard cutover.

## Current Checkpoint

- Phase: M1 evidence-gated source closure and bounded M2 mapping continue;
  decision-independent Phase 1 target foundations are now in progress
- Checkpoint: CLIENT-PROJECT-DIRECTORY-VERIFIED-NEXT-SLICE-AUDIT
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
- Exactly mapped 25 of 66 target-relevant Inventory/Transaction surfaces to
  typed Transaction boundaries, versioned local/MCP read models, offline-ready
  provenance history, nonfinancial Inventory planning, typed corrections,
  exact-cent audit and semantic target tests. Forty-one decision-sensitive
  writer/schema/lifecycle surfaces remain honestly held; see
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
- Exactly mapped 32 of 62 target-relevant backend/Auth/Functions/rules/Storage/
  query-control surfaces to capability-specific identity/handlers/RLS/Sync,
  private attachment Storage, query/index control and source-to-target
  migration contracts. Thirty decision/evidence-sensitive backend surfaces
  remain honestly held; see `EVID-M2-BACKEND-CONTROL-001`.
- Audited all 427 target-relevant surfaces: 263 are exactly mapped, 164 retain
  explicit mapping-changing blockers, zero mapped entries lack any required
  field and zero residual entries have an empty blocker list; see
  `EVID-M2-WHOLE-MANIFEST-001`.
- Added a deterministic M2 residual generator/check and generated JSON/Markdown
  queue: 164 residual surfaces grouped under 43 validated product, architecture,
  spike, or production-evidence blockers. Unknown blockers and stale artifacts
  fail `npm run conversion:residuals:check`.
- Drafted sixteen senior-level product decision packets covering all 35 product
  blockers and all 157 product-dependent residual surfaces: O-007/O-015
  explicit Item facts/provenance; O-029/O-032 Transaction post/lifecycle;
  O-023 attachment
  retention; O-026 reference-data capabilities; O-031 Item tax/basis; O-009/
  O-034 typed adjustments/sent revisions; O-003/O-004/O-005/O-010 credit,
  zero-Invoice and signed-budget behavior; and O-008/O-030 exact receipt-line
  treatment/one-cent variance; and O-006/O-033 Expense field locks/exact
  collection payment; O-035/O-036 Client Summary/shared evidence; and O-037
  Space archive/assignment; O-002/O-011–O-014 Transfer edges; and O-016/O-017/
  O-027 Item capture/acquisition readiness; O-018/O-019/O-020/O-022 proto
  migration/authority cutoff; O-024/O-025 Project/Client lifecycle; and O-028
  non-cash vendor adjustment/conserved balance. O-021 is explicitly UI-only and
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
  All five canonical target specs are explicitly distinguished from current
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

## Next Action

Continue without waiting on the two M1 evidence blockers:

1. Treat `operation-lifecycle-and-readiness` and
   `EVID-OPERATION-CORE-001` as the shared semantic dependency for every later
   operation slice. Do not recreate queued/applied/rejected, idempotency,
   readiness or error behavior independently in app, MCP, SQL or adapters.
2. Audit the remaining mapped Phase 1 foundations and select the smallest next
   decision-independent vertical slice. Freeze its exact product/architecture
   authority, claim only target-only surfaces, define every applicable and
   explicitly non-applicable contract layer, and pass the dossier `ready` gate
   before behavior begins. Do not choose an O-/A-gated mutation/schema/provider
   policy merely to keep implementation moving.
3. Do not enter hosted/provider-specific Phase 2, identity/Auth, encrypted
   local persistence, media retention, or product-command work while its named
   A-/O-/credential/spend gates remain open.
4. Keep `target-environment-isolation` in progress with successful external CI
   recorded. Complete only the later signed/visual/physical staging and actual
   hosted-resource projection portions when their credentials/resources and
   authorization exist; do not wait on those gates before continuing other
   decision-independent target foundations and do not reattach target files to
   `LedgeriOS.xcodeproj`.
5. Keep the target projection explicitly `unprovisioned` until isolated hosted
   resource IDs, staging-only credentials, maximum spend/run-rate, cleanup
   owner, and the applicable spike authorization are explicit. Do not replace
   synthetic IDs with guesses or production identifiers.
6. Preserve the decision-packet queue as proposals until product approval. Every
   generated product blocker now has a packet; O-021 remains an explicit UI-only
   UX experiment rather than a schema gate.
7. Do not execute the prepared vertical-spike protocol until isolated hosted
   resources, staging-only credentials, maximum spend/run-rate, cleanup owner,
   device matrix, and pre-measurement hard caps are explicitly authorized. When
   authorized, begin at S0 and stop fail-closed on any unknown/production ID.
8. When the user approves a product decision, update its canonical spec and
   decision log first, then traceability, architecture, affected batch mappings/
   evidence and this state. Keep one target operation/query authority across app
   and MCP and do not create a Firebase application adapter.
9. Keep A-003/A-004 proposed until the isolated vertical spike passes. The spike
   may use synthetic staging only and must prove encrypted local durability,
   scoped Sync Streams, idempotent operations/rejection, media restart, RLS, and
   offline provenance before provider-specific architecture is approved.
10. When an external chmod-600 service-account JSON whose `project_id` is exactly
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
- all five canonical target specs are represented and explicitly separated from
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
