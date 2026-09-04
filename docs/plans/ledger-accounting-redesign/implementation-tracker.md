# Ledger Accounting Redesign — Implementation Tracker

Status: decision-independent target foundations in progress; provider-specific implementation and production migration remain gated
Last updated: 2026-09-04
Program index: [README.md](README.md)
Decision log: [decision-log.md](decision-log.md)
Conversion coverage and resume state: [conversion/README.md](conversion/README.md)

## Status Key

- `not started` — no target implementation exists;
- `design` — product/schema decisions are still being resolved;
- `ready` — scope and acceptance tests are sufficiently defined to implement;
- `in progress` — implementation has begun;
- `blocked` — a named prerequisite prevents safe progress;
- `verify` — implementation exists and awaits required validation;
- `existing` — already-shipped source behavior that remains unchanged; and
- `done` — implemented, migrated where required, and verified.

## Program Gates

| Gate | Status | Exit condition |
|---|---|---|
| G0 — Product boundary | design | Open decisions that change schemas/writers are resolved |
| G0.5 — Capability synthesis | done | All 686 source-baseline surfaces have one reviewed disposition, behavior, evidence owner and dossier/control contract; new target implementation surfaces enter the same manifest and deterministic M0 audit |
| G0.75 — Target mapping | design | 437 of 621 target-relevant surfaces are target-mapped or later; all 184 residual surfaces have explicit decision/spike/production-evidence blockers across 47 validated blocker keys; `EVID-M2-WHOLE-MANIFEST-001` plus bounded slice evidence |
| G1 — Target schema | not started | Postgres entities, relationships, IDs, locks, invariants, RLS, and Sync Streams approved |
| G2 — Source migration/cutover | not started | Firebase export coverage, final-write freeze, pending-write disposition, and rejected-write recovery designed without refactoring the old app |
| G3 — Implementation | in progress | Provider-free foundations are extensive, but executable migration progress is still early. Two provider-backed product slices—Client create/read and Project setup/read—have working local identity/offline/RLS/replay/readback mechanics across spike-prefixed Postgres, encrypted PowerSync SQLite, the isolated target app and gated target MCP. Their ordinary-name fixtures pass exact-commit CI, but O-043 now correctly gates final Client-name submission parity for Client creation and the new-Client Project branch; real isolated PowerSync/Auth proof also remains open. Independent review rejected the first Client rename READY package, so its nine machine-tracked scaffolds are honestly DRAFT on O-042/O-043 and contain no executable rename. A supporting slice verifies protected offline attachment-byte acceptance locally at exact commit `ecfcdc3b` / run `33902466636`; it is not yet an upload/display product path. The 123 previously verified `LedgerTargetCore` production/test leaves are prerequisites and must not be counted as 123 migrated features. Completion still requires every product slice to pass the [Vertical Slice Implementation Method](conversion/vertical-slice-implementation-method.md); no Firebase application adapter exists |
| G4 — Migration rehearsal | not started | Read-only audit, backups, dry run, reconciliation, and rollback pass |
| G5 — Authority cutover | not started | Supabase/PowerSync writers enabled; Firebase source frozen; stale writers rejected; monitoring active |
| G6 — Release completion | not started | Production target, macOS/iOS distribution, MCP, and post-release reconciliation complete |

## Backend Responsibility Rule

The redesign has one target implementation, not parallel Firebase and Postgres
v2 systems:

| Surface | Permitted responsibility |
|---|---|
| Backend-neutral app/domain | Typed use cases, local query ports, operation receipts/results, product invariants, and UI |
| Existing Firebase production system | Continue running unchanged until cutover; no port conformance or redesign implementation |
| Firebase operational boundary | Read-only audit/export, verified backup, source-to-target mapping, final pending-write disposition, maintenance/write freeze, rejected-write recovery, and retained rollback evidence |
| Supabase Postgres target | Canonical redesigned tables, constraints, transactions, command handlers, RLS, projections, indexes, migration journals, and audit evidence |
| PowerSync target | Encrypted local SQLite, authorized Sync Streams, local query updates, durable upload coordination, and sync readiness |
| Target MCP | Invoke the same typed target commands and authorized queries as the app; no independent accounting semantics |

Do not build a Firebase application adapter. Do not add v2 Client, occurrence,
Transfer, Invoice, credit, correction, budget, or provenance authority to
Firestore rules, indexes, or Cloud Functions. The only new Firebase-side work is
the minimum operational freeze/rejection control required for the hard cutover.

## Workstream 0 — Product and Spec Control

| Task | Status | Evidence / dependency |
|---|---|---|
| Establish central program directory | done | This directory |
| Adopt capability evolution method | done | [Capability Evolution Method](conversion/capability-evolution-method.md) |
| Build complete current capability/surface catalog | done | 686 surfaces: 674 repository-discovered plus 12 manual cross-cutting; zero unclassified/missing-source/drift/validation gaps; `EVID-M0-COVERAGE-001` |
| Create reviewed capability dossiers | done | Identity/session, media, Projects/Clients/reference, unified Item/Link, Inventory/Transactions/provenance, Invoicing/budget, reporting/search, Spaces/review, platform/control, and app-shell/presentation/test-support dossiers complete |
| Map stable target responsibilities | done | 397 target mappings or later across 581 target-relevant source and target implementation surfaces; zero incomplete mapped records; 184 unresolved surfaces remain tied to 47 explicit blockers rather than guessed |
| Generate exact residual decision queue | done | 184 residual surfaces grouped under 47 validated blockers; `npm run conversion:residuals:check` |
| Draft product decision packets | done | Twenty proposed packets cover all 39 product blockers, including O-039 Project-note text validation, O-040 Project budget pinning and O-041 vendor-spend report semantics; O-021 is UI-only; none is approved by documentation alone |
| Register canonical target specs | done | [Program index](README.md#canonical-target-state-specs) |
| Establish enforceable vertical-slice implementation protocol | done | [Required method](conversion/vertical-slice-implementation-method.md), ignored template, generated slice audit and conversion-check status/evidence gates; `EVID-SLICE-METHOD-001` |
| Enforce complete target query-port method inventory | done | Verified dependency-free lexical scanner, 20-test adversarial suite, deterministic JSON/Markdown, exact package commands and Linux-before-macOS CI dependency fail closed on stale, malformed, ambiguous or unsupported target query-port declarations. Review caught and corrected nested string/regex declaration leakage including comment-separated regex context, split multiline-return truncation, incomplete declaration/header/generic/parameter/tail validation including nested component endpoints, and Unicode/backticked-name omission. Reviewed baseline remains 16 verified owners / 16 protocols / 18 methods, all current `watch*` observations, with stable TQUERY identity and separate signature drift. `TQUERYCONTROL-TEST-001` through `-008` pass; exact implementation `a359c8622069c2dc8b75ca09a8fd89b95713f1bb` passed immutable Actions run `33842465485`, and independent final review returned GO. Later slices own every-TQUERY logical access/index review and reconciliation to all 386 source `QUERY-*` occurrences. No product/query semantics, physical index, provider, hosted or production behavior advances; `EVID-TARGET-QUERY-PORT-INVENTORY-001` |
| Freeze complete target-query logical-authority crosswalk | done | Verified all 18 generated TQUERY methods in one closed JSON registry bound to the inventory digest and exact signature hashes. A dependency-free generator/checker and 23-test adversarial suite fully re-derive upstream inventory schemas/relations/totals/identities, enforce review-class consistency, canonicalize nested output, reject root/symlink escapes, use exclusive no-follow atomic generation, validate exact CLI arity, derive collision-checked TACCESS identities and separate mapping hashes, and emit/check one deterministic JSON artifact. Root generate/check/test commands and the Ubuntu conversion-control gate run before the dependent target job. The amended READY exclusions let the tests retain contiguous `firestoreQuery`/`firestoreIndex` negative cases while both conversion surface discovery and the 386-occurrence current-query inventory remain unchanged. Human review confirms all 18 generated rows and explicit uncertainty; machine validation performs no free-text or Markdown semantic/status inference. Exact implementation commit `66d56bf1ee8302e63b5622c879e62dbbe4b7e95e` passed immutable Actions run `33853355777`, and independent final adversarial review returned GO with no P0-P3 finding. Postgres and local physical planes remain globally deferred under proposed A-003/A-004 with no TINDEX IDs, SQL, RLS, Sync assignment or provider/runtime claim. Only the two control/test surfaces advance to `verified`; discoverer/query-extractor/package/workflow retain their existing status and ownership, and all query owners remain unadvanced. Reconciliation of all 386 source `QUERY-*` occurrences is a separate later slice; `EVID-TARGET-QUERY-LOGICAL-AUTHORITY-001` |
| Reconcile every frozen source QUERY occurrence | implemented | The dependency-free generator/checker validates the unchanged 170/74/386 source artifact, exact verified target-authority bytes, every selected owner/target/blocker/evidence/retirement binding, synchronized lifecycle, the exact historical implementation checkpoint and READY semantics, closed schemas, canonical conflict/cardinality rules, safe atomic output and byte-exact read-only checking. One deterministic artifact expands all 386 rows / 584 outcomes; 23 adversarial tests and independent review pass. Exact implementation `aefa7acd` passed immutable Actions run `33880331322`; administrative VERIFIED promotion remains. The artifact intentionally reports 115 authority-blocked and six evidence-blocked outcomes and grants no target-domain implementation, production read, physical access, migration, retirement or cutover authority; `EVID-SOURCE-QUERY-RECONCILIATION-001` |
| Confirm global Purchase/Return/Transfer taxonomy | done | D-001/D-002 |
| Confirm Client identity and same-Client destination rule | done | D-003 through D-006 |
| Resolve Transfer budget behavior | done | D-017 |
| Incorporate Item intake source task and raw requirements | done | [Item Intake Handoff](item-intake-handoff.md) |
| Confirm unified Item wizard, Unaccounted For/Accounted For, and two-route Link UX | done | D-018 through D-025 |
| Resolve optional Business Inventory acquisition evidence | blocked | O-016; [proposed unresolved-evidence Item capture packet](decision-packets/O-016-O-017-O-027-item-capture-and-acquisition-readiness.md) awaits approval |
| Resolve capture-time payer hint | blocked | O-017; proposed Item capture packet omits persisted hints; approval required |
| Resolve legacy proto import, source cutoff, and matching | blocked | O-018/O-019/O-020/O-022; [proposed deterministic migration/freeze/activation packet](decision-packets/O-018-O-020-O-022-proto-migration-and-authority-cutover.md) awaits approval and pending-work proof |
| Resolve wizard screen/step layout | blocked | O-021; does not block domain schema |
| Resolve attachment reference removal versus byte deletion | blocked | O-023; [proposed detach/hold/30-day-quarantine packet](decision-packets/O-023-attachment-reference-and-retention.md) awaits approval and production reference/object evidence |
| Resolve persisted Project deletion policy | blocked | O-024; [proposed archive-only Project lifecycle packet](decision-packets/O-024-O-025-project-and-client-lifecycle.md) awaits approval |
| Resolve Client reassignment and merge/correction | blocked | O-025; proposed Project/Client packet limits Project reassignment to pre-history correction and uses an audited duplicate-Client merge; approval required |
| Resolve shared reference-data administration | blocked | O-026; [proposed capability-matrix packet](decision-packets/O-026-shared-reference-data-authorization.md) awaits approval |
| Resolve unified Item minimum identifying evidence | blocked | O-027; proposed Item capture packet uses any one durable name/photo/note; approval required |
| Resolve non-cash vendor cancellation/account credit | blocked | O-028; [proposed non-Transaction adjustment/conserved-balance packet](decision-packets/O-028-vendor-adjustment-and-credit-balance.md) awaits approval; Return remains actual cash only |
| Resolve Transaction posted/draft, void and deletion lifecycle | blocked | O-029/O-032; [proposed atomic-post/append-only-lifecycle packet](decision-packets/O-029-O-032-transaction-posting-and-lifecycle.md) awaits approval |
| Resolve receipt rounding and per-Item tax basis | blocked | O-030 remains open; O-031 has a [proposed exact-allocation/basis packet](decision-packets/O-031-item-tax-and-acquisition-basis.md) awaiting approval |
| Resolve paid-credit/refund closure | blocked | O-003/O-004/O-005/O-010; [proposed balance/settlement/signed-budget packet](decision-packets/O-003-O-004-O-005-O-010-client-credit-and-zero-invoice.md) awaits approval |
| Resolve Expense edit-lock matrix | blocked | O-006/O-033; [proposed field-state/exact-payment packet](decision-packets/O-006-O-033-expense-locks-and-collection-payment.md) awaits approval |
| Resolve hidden occurrence authority | blocked | O-007/O-015; [proposed explicit-facts/derived-history packet](decision-packets/O-007-O-015-item-accounting-and-provenance.md) awaits approval |
| Resolve receipt-line billability | blocked | O-008/O-030; [proposed exact-treatment/explicit-variance packet](decision-packets/O-008-O-030-receipt-line-treatment-and-rounding.md) awaits approval |
| Resolve manual Invoice adjustment and sent revision behavior | blocked | O-009/O-034; [proposed typed-adjustment/revise-and-resend packet](decision-packets/O-009-O-034-invoice-adjustments-and-sent-revisions.md) awaits approval |
| Resolve actual collection-payment variance | blocked | O-033; proposed field-state/exact-payment packet retains strict equality and noncanonical mismatch review; approval required |
| Resolve zero-dollar Invoice behavior | blocked | O-010; covered by the proposed credit/zero-Invoice packet, product approval still required |
| Resolve Client Summary financial meaning | blocked | O-035/O-036; [proposed paid/open/recognized and sanitized-evidence packet](decision-packets/O-035-O-036-client-summary-and-shared-evidence.md) awaits approval |
| Resolve client-shared receipt evidence policy | blocked | O-036; proposed report packet defaults to omission and explicit standalone sanitized packages; approval required |
| Resolve Space archive behavior for assigned Items | blocked | O-037; [proposed archive-only/resolvable-assignment packet](decision-packets/O-037-space-archive-and-item-assignment.md) awaits approval |
| Resolve Project-note text validation | blocked | O-039; [proposed shared app/MCP normalization-and-minimum packet](decision-packets/O-039-project-note-text-validation.md) awaits approval |
| Resolve Project budget pinning | blocked | O-040; [proposed Project budget-pinning packet](decision-packets/O-040-project-budget-pinning.md) leaves pin existence, survival, no-pin/default/detail/card fallback and implicit-write policy explicitly unresolved pending approval |
| Resolve vendor-spend report semantics | blocked | O-041; [proposed Business Vendor Cash Movement packet](decision-packets/O-041-vendor-spend-report-semantics.md) leaves payer/recipient perspective, included events/signs, scope, date, credit, currency and exact label-snapshot grouping explicitly unresolved pending approval |
| Resolve Transfer edge cases | blocked | O-002/O-011–O-014; [proposed sent/tag/Space/reversal/credit packet](decision-packets/O-002-O-011-O-014-transfer-edge-policy.md) awaits approval |

## Workstream 1 — Additive Data Foundations

| Task | Status | Required output |
|---|---|---|
| Design and implement Client identity | in progress | Local provider-backed create/read proves stable Account-scoped identity, name, revision, authorization, optimistic readiness, replay and isolation. Rename/archive, hosted Sync/Auth proof, Project FK adoption, migration correlation and O-025 reassignment/merge remain open |
| Add authoritative `project.clientId` | not started | Domain/MCP contract plus target Postgres FK, RLS, indexes, and Sync Streams |
| Design Expense entity | design | Category, amount, receipt, Invoice/paid links, locks |
| Design Item charge/credit occurrence | blocked | O-007/O-015 |
| Design paired Transfer shape | blocked | O-015 |
| Split Item acquisition/current placement/open billing/paid history | blocked | O-015 |
| Add collected Invoice attachment shape | design | Exact source IDs and frozen line allocation |
| Add NonItemReceiptLine | blocked | [Accepted design](../non-item-receipt-lines/design.md); O-008/O-030/O-031 must close billability, rounding and Item tax-basis behavior |
| Add accounting authority/version marker | not started | One active budget/writer model per project |
| Design stale-Firebase-writer rejection/recovery | blocked | O-022; target read isolation does not stop an old client writing the source after final export |
| Adopt categorized No-Transaction Item shape for Unaccounted For state | design | Implement in the target app/MCP/Postgres only; source behavior informs migration tests but is not refactored |
| Define accounting-state projection | design | Project Purchase or open/Invoice/paid Item occurrence; never Space-derived |
| Define unresolved acquisition association | blocked | O-016 |

## Workstream 1A — Isolated Test Infrastructure

| Task | Status | Required output |
|---|---|---|
| Define executable vertical-spike protocol | done | [Named phases, synthetic scale, mandatory tests, evidence layout and go/no-go](vertical-spike-protocol.md); execution remains unauthorized |
| Isolate target build and environment graph | in progress | Dependency-free target package, separate staging project/scheme, fixed unprovisioned identity, source-project contamination guard, 12 tests and external CI pass; signed/physical/hosted projection remains open; `EVID-TARGET-ENVIRONMENT-001` |
| Define shared operation lifecycle/readiness | done | Typed envelope/receipt/result/rejection, exact replay, Account-isolated restart journal, stable errors and readiness; 11 focused tests; `EVID-OPERATION-CORE-001` |
| Define session-ending pending-work safety boundary | done | Exactly two target surfaces implement environment/Principal/Account-scoped queued/applying/unresolved-rejected/unverified-attachment counts, canonical summary/request fingerprints, clean/sync-first/exact-confirmed destructive dispositions, cancellation no-call, stale/regressed-summary refusal, stable diagnostics and one narrow `AccountSessionEnding` port. Exact implementation commit `bf9a00ca` passed four focused/all 168 target tests in 39 suites, graph/contracts, both staging builds and clean artifacts in immutable run `33663785835`. Auth provider/offline lease/UI copy, physical synchronization/cleanup, O-023 retention, schema/RLS/Sync, app/MCP, migration and production remain excluded; `EVID-SESSION-ENDING-POLICY-001` |
| Define Account discovery and explicit selection intent | done | Exactly two target surfaces implement environment/Principal-scoped visibility-safe Account summaries; complete/partial/stale/authoritative-empty/failure distinction; deterministic remembered-first ordering without auto-selection; exact-snapshot-bound non-authorizing selection intent; canonical restart/refusal; stable diagnostics; and one narrow `AccountQuerying` port. Exact implementation commit `e2972b9c` / immutable run `33668715587` pass four focused/all 172 target tests in 40 suites, graph/contracts, both staging builds and clean artifacts. A-007/A-016/O-023, current authorization, physical workspace activation/switching, membership/Account writers, schema/RLS/Sync, app/MCP, migration and production remain excluded; `EVID-ACCOUNT-DISCOVERY-SELECTION-001` |
| Generate versioned app/MCP contract catalog | done | Canonical JSON to Swift/TypeScript/MCP resource, strict registration/leakage/deprecation controls, 6 tests, 19 negative mutations, both target builds and exact-commit Actions run `33559241558` pass; `EVID-CONTRACT-CATALOG-001` |
| Define shared list/query presentation truth | done | Named profiles/sorts/filters/actions, stable cursors/ties, cached-first readiness/empty/failure reducer and structural non-enumeration; 3 focused/32 then-current tests passed locally, exact run `33560578730` passed conversion/build gates, and corrected cumulative run `33567370249` passed all 47 target tests; `EVID-SHARED-LIST-001` |
| Define scoped route resolution/restoration | done | Registered stable routes, environment/Principal/Account restoration, opaque keys, activation-bound resolution, non-enumerating failures, explicit not-synced/retry states and late-result refusal; 3 focused/35 then-current tests passed locally, exact run `33562117852` passed conversion/build gates, and corrected cumulative run `33567370249` passed all 47 target tests; `EVID-SCOPED-ROUTE-001` |
| Define typed edit draft/submission truth | done | Typed unchanged/set/clear fields, Account/actor/contract/subject/revision-bound drafts, validated non-decodable operation binding, stable lifecycle presentation and stale/nonmonotonic refusal; 4 focused/39 then-current tests passed locally, exact run `33563347569` passed conversion/build gates, and corrected cumulative run `33567370249` passed all 47 target tests; `EVID-TYPED-EDIT-001` |
| Define privacy-safe telemetry/correlation truth | done | Closed registered signals/classes, validated environment/build scope, opaque domain-separated correlations, allowlisted bounded values, canonical offline bytes and deterministic redaction/refusal; 4 focused/43 then-current tests passed locally, exact run `33565583450` passed conversion/build gates, and corrected cumulative run `33567370249` passed all 47 target tests; `EVID-TELEMETRY-001` |
| Define reproducible release manifest/artifact truth | done | Validated environment/profile/channel/build/contracts, immutable artifact and dependency-lock byte evidence, deterministic offline canonical manifest/digest, exact compatibility/tamper refusal and evidence-only non-authority; 4 focused/47 total target tests and both target builds pass locally and in exact-commit Actions run `33567370249`; `EVID-RELEASE-MANIFEST-001` |
| Define protected artifact export lifecycle truth | done | Authorized immutable snapshot binding, policy-bounded path-free lease, replay-validated lifecycle, canonical restart evidence and evidence-only terminal receipt; 4 focused/51 total target tests and both target builds pass locally and in exact-commit Actions run `33569882379`; `EVID-PROTECTED-ARTIFACT-001` |
| Define migration plan/journal/manifest integrity truth | done | Exact source/target/Account/artifact plan identity, policy-bound replay-safe journal, deterministic resume, terminal entity/reconciliation evidence and permanent non-authority in a separate non-app module; 4 focused/55 total target tests and both target builds pass locally and in exact-commit Actions run `33573298495`; `EVID-MIGRATION-RUN-INTEGRITY-001` |
| Define operational health/objective/alert/runbook registry truth | done | Provider-free health derivation, unit-safe measurement registry, seven evidence-gated objectives, grouped/rate-limited alert candidates, complete runbook structure, spike-pending budgets, canonical restart/tamper refusal and permanent candidate-only authority pass 4 focused/59 total tests and exact-commit Actions run `33576448917`; current emitters/lifecycle surfaces remain unadvanced; `EVID-OPERATIONAL-HEALTH-001` |
| Define deterministic target reference test support | done | Separate provider-free package target implements validated synthetic environment/Principal/Account context, finite clock/ID/revision schedules, immutable scripted operation/readiness/failure adapters, canonical restart evidence and production/credential/cross-Account/tamper refusal. Exact implementation commit `986d633e` passed immutable Actions run `33579458286`, including four focused/63 total tests, graph/contracts, clean artifacts and both builds. Current Swift/MCP helper surfaces stay target-mapped; `EVID-DETERMINISTIC-TEST-SUPPORT-001` |
| Define validated target composition boundary | done | A separate provider-free package module implements one explicit environment/version-bound composition, typed ownership of currently available catalog/operation/readiness ports, reference-versus-runtime separation, canonical structural receipt and fail-closed completeness tests. Exact implementation commit `be88c5b9` passed immutable Actions run `33581326840`: conversion traceability, graph/contracts, all 66 target tests, both staging builds and clean artifacts passed. Current Firebase root, target app/MCP wiring and provider adapters remain unadvanced; `EVID-TARGET-COMPOSITION-001` |
| Define exact Money and stable domain identity | done | Two target-only core/test surfaces implement signed Int64 minor-unit Money plus explicit validated currency, distinct stable entity IDs, checked same-currency amount comparison/arithmetic, deterministic restart encoding and malformed/fractional/cross-currency/overflow refusal. Exact implementation commit `7133aef5` passed immutable Actions run `33582602647`, including all 69 target tests, graph/contracts, both builds and clean artifacts. Product signs/bounds, currency policy, formatting, tax/rounding, schema, providers, app/MCP and migration remain unadvanced; `EVID-DOMAIN-PRIMITIVES-001` |
| Define attachment capture/local-durability receipt boundary | done | Two target-only core/test surfaces implement stable Attachment ID and exact environment/Principal/Account/parent scope, non-Codable raw capture bytes, adapter-reported size/SHA-256/opaque-local-object evidence, canonical path-free receipt, narrow capture-store port and fail-closed tests. Exact implementation commit `1792a862` passed immutable Actions run `33593116980`, including four focused/all 92 target tests, graph/contracts, both staging builds and clean artifacts. Physical encrypted persistence, upload/display/Storage, O-023 retention, providers, app/MCP and migration remain unimplemented; `EVID-ATTACHMENT-CAPTURE-001` |
| Implement protected local attachment-byte durability provider | done | Three isolated target surfaces implement a validated environment/Principal/Account-bound SQLCipher localOnly queue and AES-GCM byte vault with atomic descriptor-relative promotion, restart/pending/corruption evidence, exact replay refusal, bounded reads and no delete/upload/success API. Independent review corrections pass; exact implementation commit `ecfcdc3b` and immutable Actions run `33902466636` passed conversion controls, all 342 Swift tests, both staging builds, isolated local Supabase provider checks and clean artifacts. This is a verified local prerequisite, not completion of hosted/physical `SPIKE-MED-001`, app composition, O-023 retention, migration or cutover; `EVID-ATTACHMENT-DURABILITY-PROVIDER-001` |
| Provision dedicated target staging | blocked | Supabase project, PowerSync instance, Storage, identities, and no production IAM |
| Approve spike budget, lifecycle and hard caps | blocked | Product owner records maximum hosted run-rate/spend, cleanup owner/time, supported devices and pre-measurement performance/cost caps |
| S0 isolation/reset proof | not started | `SPIKE-ISO-001`; fail before Auth/network I/O on unknown/production resources; deterministic reset and cleanup |
| S1 Postgres authority/RLS/restore | not started | `SPIKE-DB-001`, `SPIKE-RLS-001`, `SPIKE-RST-001`; exact invariants, plans, concurrency, backup/restore |
| S2 Auth strategy comparison | not started | `SPIKE-AUTH-001`; Supabase Auth default candidate versus isolated identity-only Firebase contingency |
| S3 encrypted local lifecycle/offline lease | not started | `SPIKE-ENC-001`, `SPIKE-OFF-001`; physical devices, logout dispositions and seven-day soak |
| S4 Sync authorization/readiness/history | not started | `SPIKE-SYNC-001`, `SPIKE-REV-001`, `SPIKE-HIS-001`; zero local leakage and locally explainable cycles |
| S5 durable operation/optimism comparison | not started | `SPIKE-QUE-001`; overlay/tagged/hybrid, retry, rejection, concurrency and cross-screen truth |
| S6 attachment durability | not started | `SPIKE-MED-001`; the deterministic local acceptance provider is verified at exact commit `ecfcdc3b` / run `33902466636`, but physical-device interruption/resume, low-storage/protection/soak and hosted private resolution have not started |
| S7 schema/client evolution | not started | `SPIKE-EVO-001`; mixed versions, rebuild, contract rejection and pending-work preservation |
| S8 performance/capacity/cost | not started | `SPIKE-PERF-001`, `SPIKE-COST-001`; baseline/headroom, physical targets, hosted/self-hosted run-rate |
| S9 repeated decision review/cleanup | not started | Three clean repetitions plus randomized faults, gate recommendations, `SPIKE-PHY-001`, cleanup proof |
| Build versioned Firebase export fixtures | not started | Sanitized snapshots exercise source decoding/transform; no Firebase app adapter |
| Add isolated Ledger target staging configuration | in progress | Separate target project/scheme, bundle/state, visible banner and runtime production refusal exist with synthetic unprovisioned IDs; signed/physical and hosted-service configuration remain open |
| Parameterize MCP/backend/Storage targets | in progress | Fail-closed environment manifest and target contract exist; real staging-only credentials/config remain blocked on approved isolated resources and spend/lifecycle bounds |
| Add fail-closed migration environment guard | not started | Explicit source/target/account/mode/credential match; dry-run default |
| Build staging reset/import workflow | not started | Curated fixtures plus restricted production-like snapshot |
| Add staging Auth/member bootstrap | not started | Test identities only; chosen launch Auth strategy isolated from production |
| Add staging deploy wrapper | not started | Explicit target for schema/RLS/functions/Sync Streams/Storage; production refusal |
| Define migration manifest/reconciliation format | done | Provider-free exact commit/snapshot/target/plan/journal/entity/reconciliation evidence is verified by `EVID-MIGRATION-RUN-INTEGRITY-001`; exporter, transform, loader, persistence and operator/apply authority remain separate work |
| Rehearse interruption/idempotency/rollback | not started | Repeatable evidence before production cutover |
| Design accounting maintenance mode | not started | Affected writes paused during final delta migration |

## Workstream 2 — Client Identity

| Task | Status | Current surfaces |
|---|---|---|
| Swift Client domain/read models, query port, and context | done | Two target-only core/test surfaces implement Account-scoped Client/Project summaries, exact `clientId` relationship validation, duplicate-free readiness/versioned local list snapshots, deterministic restart, stable refusal and `ClientProjectDirectoryQuerying`. Exact commit `3c0b58b6` and immutable Actions run `33584456794` passed three focused/all 72 target tests, graph/contracts, both staging builds and clean artifacts. O-024/O-025 mutations, schema/RLS/Sync/provider, app/MCP and migration remain excluded; `EVID-CLIENT-PROJECT-DIRECTORY-001` |
| Define provider-free Client creation operation | done | Two target-only core/test surfaces verify stable Account/actor/Operation/Client identity and command-envelope/replay structure. Their current ClientDisplayName dependency is provisional under O-043 and does not prove raw cross-runtime submission parity. Exact commit `3b837af3` and immutable Actions run `33595993615` passed four focused/all 96 target tests, graph/contracts, both staging builds and clean artifacts. No server row, membership authorization, Client correction/lifecycle, schema/RLS/Sync/Auth/provider, app/MCP or migration behavior exists; `EVID-CLIENT-CREATION-001` |
| Define provider-free Client rename operation | done | Exactly two target-only core/test surfaces implement one stable Account/Client/name/expected-revision intent, shared operation envelope/fingerprint/receipt/replay lifecycle, canonical restart, atomic rebound refusal and one narrow port. Exact commit `3282f8e3` and immutable Actions run `33612902860` passed four focused/all 116 target tests, graph/contracts, both staging builds and clean artifacts. No Client row/current-Project projection, frozen-history rewrite, archive/delete/merge/reassignment, physical persistence, schema/RLS/Sync/provider, app/MCP or migration behavior exists; O-024/O-025 remain open; `EVID-CLIENT-RENAME-001` |
| Define typed Client rename intent-to-application use case | done | Exactly two target leaves implement a public non-Codable Account/Client/revision/`ClientDisplayName` intent and a generic application boundary over the verified Client rename operation. The use case constructs before one `ClientRenaming.rename` call, validates the receipt afterward, preserves all 12 typed failures and cancellation, and bounds unknown errors. Exact READY `9cc34f4c` / run `33819792298` and exact implementation `0f000b8e` / immutable run `33821354656` pass. Eight focused/all 302 tests in 63 suites, local and CI controls, repeatable generation and both builds pass; both independent implementation reviewers returned GO after one caught and the implementation corrected missing explicit UTF-8 byte-equality evidence for the large Unicode payload. It accepts no raw String and adds no normalization, read/readiness/lifecycle/no-op/UI, archive/delete/merge, Project reassignment/projection, frozen-history rewrite, persistence, authorization, provider/schema/RLS/Sync, app/MCP, migration, hosted or production behavior; `EVID-CLIENT-RENAME-USE-CASE-001` |
| Define provider-free Project rename operation | done | Exactly two target-only core/test surfaces implement one stable Account/Project/name/expected-revision intent, shared operation envelope/fingerprint/receipt/replay lifecycle, canonical restart, atomic rebound refusal and one narrow port. Exact commit `7f395bbe` and immutable Actions run `33615145061` passed four focused/all 120 target tests, graph/contracts, both staging builds and clean artifacts. No Project row/downstream projection, Client/description/category/media/history/lifecycle change, physical persistence, schema/RLS/Sync/provider, app/MCP or migration behavior exists; O-024/O-025 remain open; `EVID-PROJECT-RENAME-001` |
| Define typed Project rename intent-to-application use case | done | Exactly two target leaves implement a public non-Codable Account/Project/revision/`ProjectDisplayName` intent and a generic application boundary over the verified Project rename operation. The use case constructs before one `ProjectRenaming.rename` call, validates the receipt afterward, preserves all 12 typed failures and cancellation, and bounds unknown errors. Exact READY `dc7c9779` / run `33808493496` and exact implementation `9c8e27cf` / immutable run `33816585123` pass. Eight focused/all 294 tests in 62 suites, local and CI controls, repeatable generation and both builds pass; both independent implementation reviewers returned GO. It accepts no raw String and adds no normalization, read/readiness/lifecycle/no-op/UI, broader mutation, persistence, authorization, provider/schema/RLS/Sync, app/MCP, migration, hosted or production behavior. ProjectDetailView, ProjectDetailContainer and the other named source surfaces remain unadvanced; `EVID-PROJECT-RENAME-USE-CASE-001` |
| Define provider-free Project-note reads | done | Exactly two target core/test surfaces implement stable Account/Project/note identity, visible-content versus tombstone evidence, immutable creation/source plus revision/edit audit, bounded newest-first `(createdAt,id)` order, structured continuation, explicit complete/incomplete local history, atomic refusal and one narrow read port. Exact commit `b421f419` and immutable Actions run `33618364544` passed four focused/all 124 target tests, graph/contracts, both staging builds and clean artifacts. No mutation authorization, physical persistence, schema/RLS/Sync/provider, app/MCP/search, migration or production behavior exists; `EVID-PROJECT-NOTE-READ-001` |
| Define provider-free Project-note creation operation | done | Exactly two target core/test surfaces implement one stable Account/Project/note/text/requested-source intent, shared operation envelope/fingerprint/receipt/replay, exact parent reference, excluded caller-authored authoritative creator/time/source evidence and later non-enumerating parent-preflight responsibility. Exact commit `15566c8d` and immutable Actions run `33622056438` passed four focused/all 128 target tests, graph/contracts, both staging builds and clean artifacts. No note row/projection, authorization, physical persistence, schema/RLS/Sync/provider, app/MCP, migration or production behavior exists; `EVID-PROJECT-NOTE-CREATION-001` |
| Define provider-free Project preference-shaped reads | done | Exactly two target core/test surfaces verify a current-Principal Account/Project preference-shaped representational primitive: ordered unique stable identities, revision, derived query identity, canonical readiness/restart and authoritative not-stored versus incomplete not-available lookup. Exact commit `59526ccc` and immutable Actions run `33624655214` passed four focused/all 132 target tests, graph/contracts, both staging builds and clean artifacts. This is not canonical product approval: O-040 owns whether target pins exist and every no-pin/default/detail/card fallback and lifecycle outcome. No authentication/authorization implementation, preference write, category visibility resolution, budget calculation, physical persistence, schema/RLS/Sync/provider, app/MCP, migration or production behavior exists; `EVID-PROJECT-PREFERENCE-READ-001` |
| Define provider-free Project preference-shaped replacement primitive | done | Exactly two target core/test surfaces verify one current-Principal complete ordered identity replacement, explicit not-stored versus exact-revision concurrency, an Account/Principal/Project-derived subject, shared operation lifecycle, canonical restart/refusal and one narrow port. Exact commit `0e652548` and immutable Actions run `33628801064` passed four focused/all 136 target tests, graph/contracts, both staging builds and clean artifacts. This is a provider-free technical primitive, not approval to ship pinning; O-040 owns target pin existence/default/fallback/lifecycle policy. No authentication, category mutation/resolution, budget effects, physical persistence, schema/RLS/Sync/provider, app/MCP, migration or production behavior exists; O-026 remains open; `EVID-PROJECT-PREFERENCE-UPDATE-001` |
| Define provider-free vendor-suggestion reference reads | done | Exactly two target core/test surfaces implement stable Account-scoped suggestion identity, preserved control-free display spelling bounded to 200 UTF-8 bytes, normalized duplicate detection, active/archive lifecycle, revision, unique order, explicit ready/partial/stale/authoritative-empty local evidence, source-text-only selection and one narrow query port. Exact commit `519b4338` and immutable Actions run `33632364285` passed four focused/all 140 target tests, graph/contracts, both staging builds and clean artifacts. No O-026 mutation authority, default seeding, canonical Vendor identity, physical persistence, schema/RLS/Sync/provider, app/MCP, migration or production behavior exists; `EVID-VENDOR-SUGGESTION-REFERENCE-001` |
| Define provider-free Space-template reference reads | done | Exactly two target core/test surfaces implement stable Account/template/checklist/item identity, preserved required text, optional notes, lifecycle/revision/explicit order, structure with no checked state, explicit ready/partial/stale/authoritative-empty local evidence and one narrow query port. Exact implementation commit `f23afce3` and immutable Actions run `33636359059` passed four focused/all 144 target tests, graph/contracts, both staging builds and clean artifacts. No O-026 mutation authority, apply/save, Space creation, physical persistence, schema/RLS/Sync/provider, app/MCP, migration or production behavior exists; `EVID-SPACE-TEMPLATE-REFERENCE-001` |
| Define provider-free Client archive operation | done | Exactly two target core/test surfaces implement one stable Client archive intent, reuse the typed expected Client revision, bind the exact same-subject precondition to the shared operation lifecycle and forbid Project cascade, hard delete, merge, rename, restore, history rewrite or reassignment. Exact implementation commit `e10be9ec` and immutable Actions run `33639210706` passed four focused/all 148 target tests, graph/contracts, both staging builds and clean artifacts. No physical persistence, authoritative apply, schema/RLS/Sync/Auth/provider, app/MCP, migration or production behavior exists; O-025 remains open; `EVID-CLIENT-ARCHIVE-001` |
| Define selected-Client archive application use case | done | Exactly two target leaves implement a transient exact Account/Client/expected-revision intent and application orchestration over the verified Client archive operation: caller operation metadata, construction before one port call, receipt validation, structured cancellation, normalized failure preservation and bounded raw errors. Exact READY commit `a4bc1daa` / run `33765054735` and exact implementation commit `a5ba0ae3` / immutable run `33767120461` passed. One bounded writer changed only the two leaves; authority review caught and corrected one missing conformance-proof test; two final reviews returned GO. Root line review, six focused/all 267 tests, complete controls, repeatable generation and both staging builds passed. Client reads/UI, lifecycle eligibility/projection, physical persistence, authorization, schema/RLS/Sync/provider, app/MCP, migration, hosted resources, production and cutover remain excluded; `EVID-CLIENT-ARCHIVE-USE-CASE-001` |
| Define provider-free Project details update operation | done | Exactly two target core/test surfaces implement one normalized optional-description replacement/clear, stable Project identity, exact expected revision, shared operation lifecycle and explicit separation from name, Client, category, media, lifecycle, child, accounting and history mutation. Exact implementation commit `a532ac9d` and immutable Actions run `33642777864` passed four focused/all 152 target tests, graph/contracts, both staging builds and clean artifacts. No physical persistence, authoritative apply, schema/RLS/Sync/Auth/provider, app/MCP, migration or production behavior exists; O-023/O-024/O-025 remain open; `EVID-PROJECT-DETAILS-UPDATE-001` |
| Define Project description form-to-application use case | done | Exactly two target leaves implement a transient exact Account/Project/revision/raw-description input with a public four-argument initializer, reuse canonical `ProjectDescriptionReplacement` plus the verified draft/command, construct before one `ProjectDetailsUpdating.updateDetails` call, validate the receipt, preserve every typed failure/cancellation and bound unknown errors. Exact READY `22c6cc01` / run `33797480692` and exact implementation `55baae9d` / immutable run `33799751617` pass. Seven focused/all 286 tests in 61 suites, local and CI controls, repeatable generation and both builds pass; independent review caught and corrected zero-revision dispatch proof, and both final reviewers returned GO. EditProjectModal, ProjectService/Protocol, Project model and update_project MCP tool retain prior statuses; all read/readiness/lifecycle/no-op/UI, broader mutation, persistence, authorization, provider/schema/RLS/Sync, app/MCP, migration, hosted and production behavior remains excluded; `EVID-PROJECT-DETAILS-UPDATE-USE-CASE-001` |
| Define provider-free Project setup operation | done | Two target-only core/test surfaces verify existing/new Client selection, stable Project identity/name/description, complete category/allocation state and command-envelope/replay structure. The new-Client ClientDisplayName dependency is provisional under O-043; existing-Client selection is unaffected. Exact commit `8d8cd30f` and immutable Actions run `33599214652` passed four focused/all 100 target tests, graph/contracts, both staging builds and clean artifacts. No rows, authorization, category-definition mutation, Project edit/lifecycle, media, schema/RLS/Sync/provider, app/MCP or migration behavior exists; `EVID-PROJECT-SETUP-001` |
| Define Project setup selection-to-application use case | done | Exactly two target leaves verify Project-setup dispatch, receipt/local-state validation, failures and cancellation. The new-Client name value remains provisional under O-043; existing-Client dispatch is unaffected. Exact READY `863f6fce` / run `33791245215` and exact implementation `d624c2e0` / immutable run `33793469069` pass after review corrections. UI/default/category mutation/media, physical persistence, authorization, provider/schema/RLS/Sync, app/MCP, migration and production remain excluded; `EVID-PROJECT-SETUP-USE-CASE-001` |
| Define provider-free Project archive operation | done | Two target-only core/test surfaces implement one stable Project archive intent, typed expected revision, exact same-subject precondition, shared operation fingerprint/receipt/replay and explicit no-delete/no-reassignment boundary. Exact commit `7b30bd25` and immutable Actions run `33601516220` passed four focused/all 104 target tests, graph/contracts, both staging builds and clean artifacts. No lifecycle row, authoritative history preservation, authorization, restore/delete/edit/reassignment, schema/RLS/Sync/provider, app/MCP or migration behavior exists; `EVID-PROJECT-ARCHIVE-001` |
| Define Project archive intent-to-application use case | done | Exactly two target leaves implement a non-Codable exact Account/Project/expected-revision intent and one application use case that composes the existing verified revision/command/receipt semantics, calls `ProjectArchiving` once after construction, preserves cancellation/normalized failure and bounds raw errors. Source `ProjectDetailView` remains characterized under O-024. The source `archive_project` Boolean remains completely target-mapped to the existing `ArchiveProjectCommand` and separate future `RestoreProjectCommand`, but this slice advances only archive; no read/readiness/lifecycle eligibility, restore implementation, MCP wiring, delete, physical history proof, UI, provider/schema/RLS/Sync, migration or production behavior advances. Exact ready commit `bf429472` / run `33755885978` and exact implementation commit `232acf92` / run `33758116150` passed after two independent final reviewers drove exact-shape test and durability-wording corrections; six focused/all 261 tests, full controls, repeatable generation and both staging builds pass; `EVID-PROJECT-ARCHIVE-USE-CASE-001` |
| Define provider-free budget-category reference reads | done | Exactly two target core/test surfaces implement stable Account/category identity, canonical general/itemized/fee kind, lifecycle/system/exclusion/order/revision, already-authorized local readiness, exact visible-count privacy and active/non-system/itemized eligibility. Exact commit `713dcf57` and immutable Actions run `33606006684` passed four focused/all 108 target tests, graph/contracts, both staging builds and clean artifacts. No hidden fee visibility/count, category mutation, Project allocation, physical persistence, schema/RLS/Sync/provider, app/MCP or migration behavior exists; O-026 remains open; `EVID-BUDGET-CATEGORY-REFERENCE-001` |
| Define provider-free Project category configuration reads | done | Exactly two target core/test surfaces implement exact Account/Project/category scope, no-relationship versus enabled-null/zero/positive allocation, incomplete relationship evidence, authorized local readiness/restart, one configuration revision, atomic refusal and one narrow port. Exact commit `40d20efb` and immutable Actions run `33610276267` passed four focused/all 112 target tests, graph/contracts, both staging builds and clean artifacts. No budget arithmetic, financial authorization, category/Project mutation, physical persistence, schema/RLS/Sync/provider, app/MCP or migration behavior exists; O-026 remains open; `EVID-PROJECT-CATEGORY-CONFIGURATION-001` |
| Target Client create/read provider slice | in progress | Local identity, ordinary-name command, Postgres/RPC/RLS, encrypted PowerSync optimistic storage/upload/readback, target app and gated MCP mechanics pass. O-043 gates final Client-name validation/indexability/durable-invalid-input behavior; hosted Auth/Sync proof, migration correlation and broader Client lifecycle remain open; `EVID-CLIENT-CREATION-PROVIDER-001` |
| Target Client rename provider slice | design | Nine automatically discovered comment-only target leaves define the bounded Postgres/RPC/RLS, separate PowerSync command/overlay, FIFO/reconciliation, UInt64, app/MCP and verification shape. Independent review rejected READY because archived rename and same-value saves lacked product authority, restricted-member read expectations contradicted existing RLS/Sync behavior, and `ClientDisplayName` admits values PostgreSQL cannot represent. O-042/O-043 now block READY; no executable rename exists; `EVID-CLIENT-RENAME-PROVIDER-001` |
| Target Project setup/read provider slice | in progress | Local existing-Client setup plus ordinary-name new-Client Project creation, complete allocations, Postgres/RPC/RLS, encrypted PowerSync optimistic aggregate/upload/readback, target app, gated MCP and immutable run `33894323498` pass. O-043 gates only the new-Client name-submission boundary; hosted Auth/Sync proof remains open; `EVID-PROJECT-SETUP-PROVIDER-001` |
| Target Client/Project directory and browse PowerSync slice | implemented | The Account/Principal-bound adapter, detail readers, runtime scope guards and isolated staging browser now compose authoritative plus caller-owned pending Clients/Projects, independent reactive completeness, membership-gated authority/reconciliation across lists and exact details, same-Principal pending isolation, missing-relationship truth, content-bound versions, encrypted restart, cancellation, current Client selection and exact Project detail navigation. Three independent review passes drove correction of directory, runtime, reconciliation, staging-lifetime and exact-detail isolation defects; final corrected-diff review returned executable GO with no P0-P2 and its sole P3 stale count was corrected. Exact implementation `a1b57a37` / immutable run `33918240622` pass 16 focused directory tests, seven Project tests, all 358 target tests, local schema/RLS/RPC checks and both builds. Real hosted Sync/Auth proof remains open, so status stays implemented; archive/text/card policy, MCP list/search, migration and cutover remain excluded; `EVID-CLIENT-PROJECT-DIRECTORY-PROVIDER-001` |
| Target Account discovery and explicit-selection PowerSync slice | implemented | Four target leaves implement the Principal/environment-scoped local Account query, encrypted and path-contained bootstrap runtime, false-empty/readiness/freshness/failure/restart/cancellation coverage and a build-only explicit-selection staging component. Ten focused tests pass; independent review drove six substantive corrections and returned final GO with no remaining P0-P3 finding. Exact READY `5a5f2def` / run `33922033391` and exact implementation `011a9d05` / run `33925008015` pass all three immutable jobs. Existing staging-root wiring, server schema, grants, RLS, Data API and the current broad illustrative Sync YAML are excluded. No workspace activation, Auth/offline lease, pending-work disposal, MCP state, migration, hosted or production behavior exists; `EVID-ACCOUNT-DISCOVERY-PROVIDER-001` |
| Project creation UI replacement | in progress | Isolated target staging app exercises the new provider slice; production-quality `NewProjectView` replacement and complete UX/accessibility tests remain open |
| Project editing: Client-controlled rename/assignment | not started | `EditProjectModal` |
| Project cards/search/pickers use Client relationship | not started | Project list and destination pickers |
| Reports/Invoices preserve Client display snapshots | not started | Report and Invoice renderers |
| Contract setup accepts Client identity | not started | MCP contract setup |
| Audit and review legacy `clientName` clusters | not started | Read-only normalized-name suggestions |
| Backfill reviewed `project.clientId` | not started | No name-only automatic authorization |
| Disable Transfer for unresolved projects | not started | App/MCP plus target handler/RLS/stream authorization guard |

## Workstream 2A — Spaces and Work Queues

| Task | Status | Current surfaces |
|---|---|---|
| Define provider-free direct Space creation operation | done | Exactly two target core/test surfaces implement stable Space identity, exact Project-or-Business-Inventory creation scope, normalized required name and optional notes, zero expected-revision preconditions, canonical restart/refusal, shared operation lifecycle and one narrow port. Exact commit `03b545df` and immutable Actions run `33647113450` passed four focused/all 156 target tests, graph/contracts, both builds and clean artifacts. Checklist/template/media/Item/review/lifecycle/accounting mutation, authorization, physical persistence, schema/RLS/Sync/provider behavior, app/MCP, migration and production remain excluded; O-023/O-026/O-037 stay open; `EVID-SPACE-CREATION-001` |
| Define provider-free Space details update operation | done | Exactly two target core/test surfaces implement complete normalized name/optional-notes replacement, stable Space identity, exact same-Space expected revision, canonical restart/refusal, shared operation lifecycle and one narrow port. Exact commit `1c8c12b4` and immutable Actions run `33654631876` passed four focused/all 160 target tests, graph/contracts, both builds and clean artifacts. Scope/checklist/template/media/Item/review/lifecycle/accounting mutation, authorization, physical persistence, schema/RLS/Sync/provider behavior, app/MCP, migration and production remain excluded; O-023/O-026/O-037 stay open; `EVID-SPACE-DETAILS-UPDATE-001` |
| Define provider-free Space checklist revision operation | done | Exactly two target core/test surfaces implement complete canonical ordered checklist replacement, stable nested identities, checked-state progress, exact same-Space expected revision, canonical restart/refusal, shared operation lifecycle and one narrow port. Exact commit `8131e857` and immutable Actions run `33659853864` passed four focused/all 164 target tests, graph/contracts, both builds and clean artifacts. Scope/details/template/media/Item/review/Space-completion/lifecycle/accounting mutation, authorization, physical persistence, schema/RLS/Sync/provider behavior, app/MCP, migration and production remain excluded; O-023/O-026/O-032/O-037 stay open; `EVID-SPACE-CHECKLIST-REVISION-001` |
| Define Space checklist revision edit-to-application use case | done | Exactly two target leaves implement existing restart-safe SpaceChecklistEditingDraft plus current SpaceCoreDetailsUpdate command derivation, one post-derivation `SpaceChecklistRevising` call, receipt validation, typed presentation/revision failure preservation, Swift cancellation and bounded raw errors. Exact READY commit `6534da33` / run `33785649411` and exact implementation commit `99574328` / immutable run `33788214259` pass. Six focused/all 273 target tests, complete controls, repeatable generation and both staging builds pass; two independent reviewers found and verified corrections to test-only readiness, scope/lifecycle, boundary/length and reciprocal-field proof gaps and returned GO. EditChecklistModal remains `target_mapped`; UI admission/controls, physical persistence, authorization, provider/schema/RLS/Sync, app/MCP, migration and production remain excluded; `EVID-SPACE-CHECKLIST-REVISION-USE-CASE-001` |
| Define direct Space creation form-to-application use case | done | Four conversion surfaces converge current name validation on the canonical target values while only two target-only leaves changed. Caller-supplied raw name/notes become typed intent; the application use case adds exact operation metadata, assembles the verified command, calls `SpaceCreating` exactly once after validation and validates its receipt. Exact implementation commit `c35f1cef` and immutable Actions run `33746648677` passed six focused/all 249 target tests in 55 suites, conversion/target controls, repeatable generation, both staging builds and clean artifacts; promotion commit `880727f7` passed run `33747118216`. No SwiftUI, physical persistence, optimistic row, authorization, provider/schema/RLS/Sync, app/MCP, migration or production behavior exists; `EVID-DIRECT-SPACE-CREATION-USE-CASE-001` |
| Define Space details update form-to-application use case | done | Exactly two target leaves implement caller-supplied Account/Space/revision and raw name/notes, canonical complete-replacement validation, application-owned operation metadata/command dispatch, one post-validation `SpaceDetailsUpdating` call, receipt validation, Swift cancellation and bounded transport failures. Exact implementation commit `f0d7c3fa` and immutable Actions run `33750834849` passed six focused/all 255 target tests in 56 suites, conversion/target controls, repeatable generation, both staging builds and clean artifacts after two independent corrected final reviews. The source modal remains `target_mapped`: initial population, transient UI, dirty/no-op and lifecycle eligibility policy, error/dismissal UX, layout/copy and composition remain outside. No physical persistence, authorization, provider/schema/RLS/Sync, app/MCP, migration or production behavior; `EVID-SPACE-DETAILS-UPDATE-USE-CASE-001` |
| Define provider-free Item-to-Space assignment operation | done | Exactly two target core/test surfaces implement one nonempty canonical same-scope `AssignItemsToSpace` intent with stable destination Space/Item identities, exact Space/Item revisions, deterministic active/revision/scope preconditions, atomic refusal, stable diagnostics, shared operation lifecycle and one narrow port. Exact implementation commit `c5fdf5c7` and immutable run `33672006836` passed four focused/all 176 target tests in 41 suites, graph/contracts, both staging builds and clean artifacts. O-037 stays open because archive is absent; clear assignment, Item scope/accounting mutation, physical persistence, schema/RLS/Sync/provider behavior, app/MCP, migration and production remain excluded; `EVID-ITEM-SPACE-ASSIGNMENT-001` |
| Define Item-to-Space local-destination-to-application use case | done | Exactly two target leaves implement a public transient Account/scope/destination/typed-Item intent and one application boundary joining the verified Space destination directory to the verified assignment operation. It validates Account/scope, resolves only a represented stable SpaceID across all six Project/Inventory × ready/partial/stale combinations, derives its revision from that row, constructs before exactly one assigner call and validates afterward. Missing rows refuse as not represented. Pre-port application failures, operation failures and cancellation remain exact; other port errors—including an impossible application-layer failure—are bounded. Exact READY `d51ea1d3` / run `33827181145` and exact implementation `04331950` / immutable run `33828908233` pass; traceability completed in 11 seconds and isolated target in 6 minutes 32 seconds with all 309 tests and both builds green. Seven focused tests and two corrected-diff reviews also pass. Clear/no-op, Item selection UI/read, archive, media/marker, scope movement, accounting/provenance, persistence, authorization, provider/schema/RLS/Sync, app/MCP, migration, hosted and production behavior stay excluded; `EVID-ITEM-SPACE-ASSIGNMENT-USE-CASE-001` |
| Define provider-free Item Space-assignment clear operation | done | Exactly two target core/test surfaces implement one nonempty canonical same-scope `ClearItemSpaceAssignments` intent with stable Item/current-Space identities, exact Item revisions, deterministic Space-scope plus Item-revision/scope/current-placement preconditions, atomic refusal, marker-relationship closure without media deletion, shared operation lifecycle and one narrow port. Exact implementation commit `f5a7ac75` and immutable run `33677087616` passed four focused/all 180 target tests in 42 suites, graph/contracts, both staging builds and clean artifacts. O-037 stays open because archive is absent; O-023 stays open because references/bytes are not deleted; destination assignment, Item scope/accounting mutation, physical persistence, schema/RLS/Sync/provider behavior, app/MCP, migration and production remain excluded; `EVID-ITEM-SPACE-CLEARING-001` |
| Define Item Space-clear intent-to-application use case | done | Exactly two target leaves implement a public transient Account/scope/typed-Item-revision-current-Space intent and one application boundary above the verified clear operation. It binds exact caller-supplied conflict values through draft/command construction before exactly one clearer call, validates afterward, preserves all 15 typed failures and cancellation, and bounds unknown port errors. Current-Space/scope claims remain untrusted until authoritative apply; stale assigned-looking evidence may dispatch and later conflict. Nil/no-current-Space intent is structurally unrepresentable, empty rejects, and no synthetic no-op receipt exists. Exact READY `8154f8bf` / run `33831367527` and synchronized implemented checkpoint `8181512d` / immutable run `33833543735` pass; traceability completed in 11 seconds and isolated target passed all 316 tests in 65 suites, generated contracts, both builds and clean artifacts. Earlier executable-only `f7ce8bca` / run `33832447988` passed isolated target but failed traceability solely on unsynchronized READY hashes; the synchronized checkpoint corrected that process defect without executable changes. READY review missed a P3 free-text truncation of preserved ID `SWIFT-4D0D546A02D8`; actual manifest/classification/source status and the frozen test scaffold were correct, so no executable behavior was affected. Read/UI eligibility, archive/O-037, attachment references/bytes/O-023, marker mutation, destination/scope/accounting/provenance, persistence, authorization, provider/schema/RLS/Sync, app/MCP, migration, hosted and production behavior stay excluded; `EVID-ITEM-SPACE-CLEARING-USE-CASE-001` |

## Workstream 3 — Global Transaction Taxonomy

| Task | Status | Current dependency |
|---|---|---|
| Define target Transaction taxonomy, scope meaning, and Transfer pair identity | verified | Exact implementation commit `031a240a` and immutable Actions run `33585853504` verify the provider-free Purchase/Return/Transfer set, scope-owner meaning, project-only roles, exact-ID same-Client route, Operation-bound distinct pair identity, canonical restart and stable refusal across all 76 target tests, graph/contracts, both builds and clean artifacts. Amount/line/Item/Invoice/Space/correction/lifecycle semantics, schema/provider, app/MCP and migration remain excluded; `EVID-TRANSACTION-TAXONOMY-001` |
| Define Firebase-source enum migration mapping | not started | Export transformer maps every legacy value with blocker reporting; target app has no Firestore DTO |
| Define target Postgres Transaction type/scope constraints | not started | Purchase/Return scope-relative; Transfer project-only |
| Change target Invoice collection output to Purchase | not started | Supabase command handler and target collection semantics |
| Remove target writes of `paymentToBusiness` | not started | Legacy values are handled only by the source migration mapping |
| Remove target project writes of Sale | not started | Inventory occurrence writer required first |
| Keep inventory Purchase/Return scope-relative | not started | Update validations and language |
| Add Transfer as project-only | blocked | Target Postgres paired Transfer schema/handler |
| Update target filters/cards/search/export/report labels | not started | Target read models plus explicit migration mapping |
| Update agent/MCP write guidance | not started | Cutover coordinated with deployed tools |
| Audit legacy enum distribution and mapping | not started | Read-only before migration |
| Reject retired writes after cutover | not started | Target command version plus Firebase source freeze/stale-client policy |

## Workstream 4 — Unified Item Creation and Accounting Link

| Task | Status | Required behavior |
|---|---|---|
| Define Project Item accounting-section read contracts | verified | Provider-free typed Purchase/occurrence evidence derives ordered Unaccounted For / Accounted For sections, preserves one physical Item identity and Space independence, keeps incomplete absence explicitly unresolved, and survives canonical restart/tamper refusal. Exact implementation commit `92e0b565` passed immutable Actions run `33591275648` with four focused/all 88 target tests, graph/contracts and both staging builds. No Item writer/Link, occurrence persistence, credit settlement, budget effect, provider, current app/MCP or migration is claimed; `EVID-PROJECT-ITEM-ACCOUNTING-001` |
| Merge provisional Quick Add and New Item paths | design | One wizard and one Item writer; former proto fields first; optional details continue |
| Adopt one minimum Item-evidence validation rule | blocked | O-027; current full and Quick Add forms disagree |
| Stop new-version `protoItems` creation | blocked | Real Unaccounted For Item shape plus production compatibility gate |
| Leave legacy proto production behavior unchanged before cutover | existing | Existing Firebase app/collection/rules/indexes remain untouched; migration tooling reads them |
| Unaccounted For / Accounted For projection | design | Transaction/billable destination alone controls section membership; Space remains independent |
| Client-paid Link | blocked | Requires eligible project Purchase and target association schema |
| Business-paid Link | blocked | Optional inventory Purchase, one Item identity, open Item charge, no project Transaction |
| Business-paid Link without selected acquisition | blocked | O-016; never fabricate a vendor Purchase |
| One-Item identity and occurrence reference | blocked | O-007/O-015; Invoicing references the physical Item |
| Duplicate/evidence reconciliation | blocked | O-019; separate from normal Link |
| Import legacy `protoItems` into real target Items | blocked | D-025/P-004 and O-018/O-020; no target proto writer or Firebase app refactor |
| MCP terminology and trusted Link command | not started | Idempotent, account-scoped, same target behavior as app |
| Media/quantity/name/Space preservation | design | Direct Item create or legacy proto migration; one Item stores quantity; explicit copy alone creates distinct identities; no duplicate uploads or lost fields |
| Link concurrency and retry tests | not started | Collection, second Link, Item deletion, project change, stale writer |

## Workstream 5 — Invoicing Sources and Collection

| Task | Status | Required behavior |
|---|---|---|
| Items section backed by exact charge/credit occurrences | blocked | Occurrence schema |
| Expenses section and CRUD | design | O-006 |
| Fees section compatibility | design | Preserve FeeInstallment intent |
| Whole-Invoice-only selection and collection | not started | Remove partial/selected-line collection |
| Created/sent Invoices remain live | design | Recalculation and audit operations |
| Created-Invoice membership commands and exclusivity | design | Stable typed source links, authoritative source revisions, one active Invoice per source |
| Sent-Invoice membership revision/delivery | blocked | O-034; explicit revise/resend versus immutable membership after send |
| One lump-sum Purchase on collection | not started | Target Postgres command is atomic/idempotent |
| Validate actual collection amount | blocked | O-033; safe provisional contract requires exact positive Invoice-total match |
| Attach all frozen collected contents | not started | Items, Expenses, Fees, adjustments |
| Remove collected sources from active Invoicing | not started | Preserve source and Invoice history |
| Credit settlement/refund workflow | blocked | O-003/O-004 |
| Zero-dollar Invoice policy | blocked | O-010 |
| Manual adjustment policy | blocked | O-009 |

## Workstream 6 — Inventory Item Accounting Lifecycle

| Task | Status | Required behavior |
|---|---|---|
| Inventory-to-project sale creates Item charge, not project Transaction | not started | Target Postgres occurrence handler |
| Unpaid project-price edits recalculate charge/live Invoice | not started | Paid freeze and concurrency |
| `RemoveUnpaidItemFromProject` removes open demand | not started | Atomic physical placement/provenance/budget; no Return Transaction because no money moved |
| Live-Invoice physical removal updates/removes exact line | design | O-002/O-010; story-specific command, not generic `ReturnItems` |
| `ReturnPaidItemToInventoryAndCreateCredit` creates deterministic Item credit | blocked | O-003/O-004/O-007; no Return Transaction until cash refund |
| Resale creates a new occurrence | not started | Never reopen paid history |
| Project-origin acquisition uses purchase cost | not started | Preserve origin-aware rules |
| Return-to-source-project uses immutable snapshot | not started | Preserve provenance |
| Cross-Client project sale uses inventory path | not started | Separate from Transfer |
| Correction versus real movement | design | `CorrectPurchase`, `CorrectReturn`, or `ReverseTransfer`; explicit audit evidence |
| Vendor refund follows scope-owner Return | not started | `RecordProjectVendorRefund` versus `RecordInventoryVendorRefund` |

## Workstream 7 — Same-Client Direct Transfer

| Task | Status | Required behavior |
|---|---|---|
| Bulk Item selection from source project | not started | All Items still in source at commit |
| Destination picker filters exact same `clientId` | verified | The provider-free core filters exact active same-Account/same-Client destinations, excludes source/inventory/archive/other-Client rows, preserves source-bound local readiness/fingerprints, and passed deterministic restart/refusal plus exact-commit CI at `6dc7d0c2`. No current picker wiring or Transfer write/effect is claimed; `EVID-TRANSFER-DESTINATION-001` |
| One trusted idempotent Transfer command | blocked | Target Client and Transfer schema/handler |
| Create both linked records atomically | blocked | One Postgres transaction; never expose independent writes |
| Move Item directly between project IDs | not started | No inventory intermediate state |
| Clear or assign destination Space | blocked | O-012 |
| Handle open charge/live Invoice | blocked | O-002 |
| Preserve paid history | design | Never rewrite original Purchase/Invoice |
| Apply approved budget reallocation | design | D-017; exact schema depends on O-015 |
| Support paired correction/reversal | blocked | O-013 |
| Handle later return/credit through Transfer chain | blocked | O-014 |
| Concurrency tests | not started | Collection, repricing, sale, second Transfer, Client change |

## Workstream 8 — Budget and Reporting Authority

| Task | Status | Required behavior |
|---|---|---|
| Define stable budget contribution identity by category/state | design | Direct Transaction allocation, Item occurrence, Expense, Fee/adjustment, collected allocation, and Transfer; Invoice links are non-additive |
| Client-paid segment | design | Direct Purchase allocations + collected frozen allocations + approved Transfers; collection Purchase face amount is evidence, not a second contribution |
| Invoicing/unpaid segment | design | Open Item/Expense/Fee/approved-adjustment signed activity, including live Invoice membership without duplicate value |
| Collection moves segments without changing total | not started | No settlement double count |
| Furnishings owns all Item activity | not started | Additional Requests non-additive overlay |
| Transfer paid/open calculations | design | D-017 confirmed; implementation shape depends on O-015 |
| Negative credit display | blocked | O-005 |
| Implement target Postgres budget authority/projection | not started | Rebuildable from canonical target sources; compare with Firebase source during shadow rehearsal |
| Search/reports/exports use one authority resolver | not started | No per-surface arithmetic |
| Add typed report/export snapshots | design | Readiness, as-of/local/accounting versions, visibility scope, currency, stable row identity/order |
| Add indexed local universal search | design | Authorized Items/Transactions/Spaces/Projects/Clients with deterministic ranking/cursors and scope readiness; no target proto results |
| Replace MCP raw/full projections | design | Named visibility-safe profiles, stable cursors, response budgets and no arbitrary field selection |
| Define Client Summary financial basis | blocked | O-035 |
| Define report receipt delivery | blocked | O-036 |
| Reconciliation and drift alarms | not started | Per-project/category/source evidence |

## Workstream 9 — Receipt Lines and Completeness

| Task | Status | Required behavior |
|---|---|---|
| Define provider-free NonItemReceiptLine and exact reconstruction evidence | verified | Two target-only core/test surfaces implement stable ordered line identity/shape, exact integer-Money increase/decrease/net/reconstructed/variance evidence, order-binding fingerprint, canonical restart and refusal. Exact commit `594aec1e` passed 4 focused/all 84 target tests, graph/contracts, both staging builds and clean artifacts in immutable run `33588870600`. No completion verdict, billing/tax allocation, Transaction writer, schema/provider, current app/MCP or migration is claimed; `EVID-RECEIPT-RECONSTRUCTION-001` |
| Persist and expose NonItemReceiptLine in the target vertical slice | not started | Postgres relationship/checks/indexes, handlers, grants/RLS, Sync, app/MCP and migration land together after applicable gates |
| Update Purchase/Return entry UI | not started | Other receipt lines section |
| Replace subtotal/tax completeness equation | not started | Exact-cent final amount reconstruction |
| Migrate discount/tax/shipping/warranty data | not started | Reviewed line mapping |
| Preserve inventory movement pricing until replaced | not started | Avoid accidental project-price drift |
| Decide project billability of receipt lines | blocked | O-008 |
| Production audit/dry run/reconciliation | not started | Existing audit evidence available |

## Workstream 10 — Platform and Backend Coordination

| Surface | Status | Required coordination |
|---|---|---|
| Backend-neutral iOS/macOS application | design | Domain/read models, typed use cases, capability-aware composition, UI, and offline state without vendor SDK leakage |
| Existing Firebase production app | existing | Remains on its current implementation until hard cutover; no redesign work |
| Firebase migration/cutover tooling | not started | Read-only export, verified backup, final pending-write disposition, maintenance/write freeze, rejected-write recovery, and source retention |
| Supabase Postgres target | in progress | Local spike-prefixed Client and Project/category-allocation tables, indexes, transactional create handlers, least-privilege grants, RLS and immutable operation results pass pgTAP/Data API tests; broader canonical schema, hosted rehearsal and production topology remain open |
| PowerSync target | in progress | Client and Project slices use exact pinned SDK/SQLite dependencies, encrypted per-scope local storage, atomic optimistic aggregates, FIFO upload dispatch, authoritative-overlay reconciliation and draft Sync Streams locally. Real isolated Sync/Auth validation, inventory provenance, media, evolution, scale and failure phases still gate A-004 |
| Supabase Storage target | not started | Private paths, policies, resumable upload, metadata/reference reconciliation |
| Target MCP server | in progress | Gated `create_client` and `create_project` use authenticated context, canonical command bytes and the same Supabase RPC/result validation as the app; server composition, remaining tools, hosted auth and deployment remain open |
| Target background workers | not started | External integrations/media/scheduled reconciliation only; no duplicate database-local accounting authority |
| Reports/search/exports | not started | Target canonical sources and local projections; Firebase source is used only in migration comparison |
| Access controls | in progress | Client/Project membership, capability and category-visibility authorization plus RLS, grants and local negative tests pass; all remaining entities plus real PowerSync stream authorization and adversarial hosted proof remain open |
| Observability | not started | Cross-system operation IDs, sync lag, idempotency conflicts, reconciliation drift, and partial-history readiness |
| Firebase source/export coverage audit | not started | Every collection, embedded shape, Storage reference, and legacy variant is classified for migration; no writer refactor |

No work item may refactor current Firebase repositories behind the new ports.
No target work item exists for v2 Client/occurrence/Invoice/Transfer indexes or
paid-lock rules in Firestore, or for v2 budget/repricing/reconciliation in Cloud
Functions. Any proposed Firebase application implementation violates A-017.

Compatibility sequencing and per-surface hazards are authoritative in the
[Production Compatibility and Rollout Plan](production-compatibility-plan.md).

## Workstream 11 — Migration and Cutover

| Task | Status | Safety requirement |
|---|---|---|
| Inventory production shapes and counts | not started | Read-only, account-scoped |
| Establish corrected budget baseline | not started | Do not trust cached summaries blindly |
| Back up affected Firebase collections and Storage metadata | not started | Verified source backup before every migration/cutover write phase |
| Build target shadow import/projections | not started | Import to Supabase and compare without authority switch or Firebase v2 writers |
| Import Clients and project IDs into target | not started | Human review for ambiguous clusters; durable source correlation |
| Import occurrence/association relationships into target | not started | Preserve acquisition and paid history |
| Audit and import open `protoItems` into target | not started | Preserve media, Space, hints, and exact Link status without accounting side effects |
| Correlate legacy settlement Transactions | not started | Do not invent lump sums without evidence |
| Rehearse migration with dry-run artifacts | not started | Per-row decisions and rollback plan |
| Switch accounting authority | not started | Coordinated app/MCP/Supabase handlers/RLS/PowerSync activation plus Firebase source freeze |
| Freeze/reject legacy Firebase writes | not started | Adopted O-022 hard-cutover procedure after final quiescence; preserve recovery evidence |
| Verify legacy-client quiescence and target isolation | not started | Supabase keeps target reads isolated; final export occurs only after approved source-write freeze procedure |
| Retire frozen legacy proto paths | not started | Only after rollback/evidence-retention window and verified open-proto migration |
| Post-cutover reconcile and monitor | not started | Zero unexplained category/source differences |
| Retire frozen Firebase production system | not started | Only after rollback window, source manifest verification, and target stability |

## Required End-to-End Verification

- Direct client vendor Purchase with physical Items.
- Direct client non-itemized Purchase.
- Inventory acquisition Purchase and vendor Return.
- Minimum-field Item creation writes one real Unaccounted For Item with optional
  Space and no accounting impact.
- Continuing the same wizard adds optional detail without changing Item identity.
- Client-paid Link attaches the Item to the selected project Purchase and is idempotent.
- Business-paid Link with and without a selected inventory Purchase creates one
  Item identity plus one open charge and no project Transaction.
- Duplicate/evidence reconciliation preserves one Item identity, media, and
  audit history.
- Inventory Item charge → price edit → live Invoice → collection Purchase.
- Return before Invoice, from created/sent Invoice, and after payment.
- Paid credit application and cash refund once approved.
- Same-Client Transfer for open, live-Invoice, paid, and mixed batches.
- Cross-Client project sale cannot use Transfer.
- Transfer retry and paired correction.
- Repeated sale/return/Transfer cycles for one Item.
- Inventory history remains explainable offline across repeated
  inventory↔project sale/return/resale cycles and labels incomplete history.
- Budget collection segment swap without total change.
- Approved Transfer project-budget behavior without duplicate contribution.
- Additional Requests subtotal without Furnishings/overall duplication.
- Non-item receipt line reconstruction for Purchase and Return.
- Imported legacy records render and calculate correctly in the target; the
  existing Firebase app remains unchanged before cutover.
- Offline/stale client cannot recreate retired writes after cutover.
- Logout with pending operations/media blocks routine deletion, supports
  sync-then-logout, and requires exact-count confirmation for destructive discard.
- Pre-update client remains functional until the hard-cutover window, cannot see
  target-only shapes, and receives the approved recovery behavior if it attempts
  a Firebase write after the source freeze.

## Release Rule

This program is not “done” when code compiles. Final release requires the
coordinated deployment sequence, production migration evidence, distributed app
builds where applicable, and post-release reconciliation defined by the program
gates above.
