# Current Capability Register

Status: M0 complete; all capability, app-shell, presentation, platform,
operational, and test-support surfaces have reviewed static dossiers and
approved dispositions

This register groups current Swift service/Auth and MCP modules by the outcome
they help deliver. The complete deterministic file/symbol inventory is in
`capability-surfaces.generated.json` and `.md`. Grouping source surfaces is not
approval of a target port, schema, or behavior decision.

## Coverage

- 41 Swift service/Auth files assigned;
- 47 MCP source modules assigned;
- 88 of 88 files in the configured service/MCP scope assigned;
- source hashes, declared names, and lexical coupling/read/write/observation/
  offline signals captured; and
- newly added or unassigned files fail the generated-catalog check.
- all 686 conversion surfaces resolve through their reviewed classification
  batches to `product-authority-crosswalk.json`; the six canonical redesign
  specs are explicitly distinguished from current and historical evidence.

UI callers, models, tests, Functions, data shapes, and migration/operational
tools remain distinct manifest surfaces. Each dossier must link those surfaces
before it can claim capability completeness.

## Dossier Queue

The opportunities below are review hypotheses grounded in the existing static
audits. They are not silent product decisions.

| Capability | Current outcome/evidence boundary | Governing product sources | Improvement/correction questions to resolve | Dossier state |
|---|---|---|---|---|
| Identity, accounts, and invites | Sign-in/session state, multi-account discovery, membership, roles/financial access, invite creation/acceptance, MCP identity exchange | `financial-access-controls.md`, `authentication-offline-access.md`, A-007/A-016 | Explicit account selection; pending-work logout policy; fresh server authority; remove user-editable authorization and non-expiring MCP token risks | [target mapping reviewed](evidence/EVID-M2-IDENTITY-001.md); all eight target-relevant surfaces exactly mapped, provider implementation still gated |
| Settings and reference data | Account/project categories, presets, vendor/Space defaults, preferences | `data-model.md`, `budget-management.md`, target accounting specs | Separate reference configuration from accounting authority; define local scope and conflict behavior; retire legacy defaults only with usage evidence | [target mapping reviewed](evidence/EVID-M2-PROJECT-REFERENCE-001.md); stable reads/preferences/presentation mapped, shared writer surfaces withheld on O-026 |
| Projects and Clients | Project CRUD, notes, project lookup, current free-text Client identity | `client-identity-and-project-transfers.md`, D-003–D-006 | Introduce authoritative Client identity without copying name-based ambiguity; define archive/rename/offline behavior and note ordering | [target mapping reviewed](evidence/EVID-M2-PROJECT-REFERENCE-001.md); stable identity/setup/query/note surfaces mapped, deletion/correction withheld on O-024/O-025 |
| Spaces and review | Space CRUD, assignment/review notes, templates, archive side effects | `spaces.md`, `items.md`, `data-model.md`, inventory specs | Replace failure-suppressed archive cleanup with atomic/repairable semantics; keep Space independent from accounting; define offline review readiness | [target mapping reviewed](evidence/EVID-M2-SPACES-REVIEW-001.md); stable queries/models/typed operations/tests mapped, archive/review-media/work-queue surfaces held |
| Items and quick capture | Item CRUD, tag extraction, current proto capture/promotion, item filters and bulk workflows | `proto-item-capture.md`, `items.md`, D-018–D-025, O-016–O-021/O-027 | One Item identity and writer; retire target proto writer; preserve capture speed/media; make Link an idempotent domain operation rather than CRUD composition | [target mapping reviewed](evidence/EVID-M2-ITEM-CREATION-001.md); 14 stable query/port/bulk/test surfaces mapped, 17 exact schema/validation/import/retention holds remain; O-021 is UI-only |
| Inventory movement and provenance | Project/inventory moves, lineage lookup, purchase intent, source/origin pricing | `inventory-item-invoicing-lifecycle.md`, `inventory-as-store.md`, `lineage-tracking.md`, O-007/O-015/O-038 | Replace ambiguous movement/Return coupling with story-specific commands; ensure repeated history is explainable offline; make provenance authoritative and reconstructible; decide whether shipped destination planning survives without conflicting with Furnishings or one-Item lifecycle | [target mapping reviewed and corrected](evidence/EVID-M2-INVENTORY-TRANSACTION-001.md); stable Inventory/history contracts mapped, planning and decision-sensitive story writers held |
| Transactions, receipts, and corrections | Purchase/Return CRUD, item membership, completeness, attachments, deletion/correction workflows | `invoice-centered-project-accounting.md`, `2026-08-30-correct-transaction-and-its-items.md`, non-item receipt-line design | Enforce three-type scope model; separate cash/refund/correction stories; make completeness and deletion atomic; preserve legacy evidence without target legacy writers | [target mapping reviewed](evidence/EVID-M2-INVENTORY-TRANSACTION-001.md); stable reads/corrections/tests mapped, occurrence/receipt/lifecycle/retention surfaces held on exact decisions |
| Invoicing, collection, and budget | Invoice composition/status/collection, project budget progress, categories and settlement projections | `invoice-centered-project-accounting.md`, `billing-invoicing.md`, `budget-management.md`, O-003–O-010/O-033/O-034 | Whole-Invoice atomic collection; immutable paid membership; one accounting authority; remove double counting and asynchronous derived-state drift; surface rejection/reconciliation | [target mapping reviewed](evidence/EVID-M2-INVOICING-BUDGET-001.md); stable contribution/Invoice/billing/intake/test surfaces mapped, decision-sensitive writers/displays held |
| Media and attachments | Offline pending upload queue, image caching/thumbnails, URL resolution, item/Space/Transaction attachments | `offline-first.md`, `items.md`, current Storage contract | Private target objects; durable encrypted local capture; resumable/idempotent upload; explicit logout/account switch; eliminate globally open/token-URL assumptions and duplicate derivatives | [target mapping reviewed](evidence/EVID-M2-MEDIA-001.md); 15 of 19 target-relevant surfaces mapped, four destructive/reference-removal tools withheld on O-023 and production evidence |
| Reporting, search, and cross-domain queries | MCP resources, analytics, bulk getters, composite workflows and search | `reports.md`, `search-results.md`, target accounting specs | One canonical projection authority; stable cursor ordering; local/remote readiness and financial filtering; prevent broad scans and per-surface arithmetic drift | [target mapping reviewed](evidence/EVID-M2-REPORTING-SEARCH-001.md); named projections/search/lookups/exports/artifacts mapped, report semantics/delivery surfaces held |
| Platform, transport, and legacy persistence | Generic Firestore repository, Firebase environment wiring, MCP transport/context/schema/types/errors/telemetry | architecture A-017 and conversion control plane | Retire vendor-shaped generic repositories from target; keep only migration/export source access; introduce typed ports, stable errors, environment isolation and observability | [target mapping reviewed](evidence/EVID-M2-PLATFORM-001.md); 38 of 41 target-relevant surfaces mapped, three exact spike/product holds remain |
| App shell, shared presentation, and test support | iOS/macOS navigation, Auth/account/member screens, reusable components/theme, Item action/list helpers, camera/document/image behavior and remaining tests | all owning dossiers plus offline/security/verification architecture | Keep presentation pure; use typed snapshots/intents and visible durable operation state; remove view-owned SDK listeners/raw writes, URL identity, obsolete placeholders and superseded accounting tests | [target mapping reviewed](evidence/EVID-M2-APP-SHELL-001.md); all 39 target-relevant replacement/redesign surfaces exactly mapped |

## Dossier Review Order

Review in dependency order rather than file order:

1. platform/operation lifecycle and identity/logout;
2. media durability, because disconnected Item capture depends on it;
3. Projects/Clients plus settings/reference boundaries;
4. Item creation and quick capture;
5. Inventory/provenance and Transactions/corrections;
6. Invoicing/collection/budget; and
7. reporting/search/cross-domain projections;
8. Spaces/review and work queues; and
9. app shell/shared presentation/test support plus platform/release/migration
   control as the whole-program closure audit.

This order does not authorize implementation. It produces the observable
contracts and blockers needed for a safe vertical spike and later target
mapping.

## Immediate Next Review

Static capability synthesis is complete. The deterministic whole-manifest audit
found zero unclassified surfaces, missing behavior, missing evidence, missing
batch ownership, source drift, or validation warnings; see
`EVID-M0-COVERAGE-001`.

Proceed capability-by-capability into M2 target mapping. Populate exact target
owner, typed command/query/schema/port surface, RLS/security obligation, Sync
Stream/local-read obligation, source migration rule, and verification owner in
the existing classification batch. Do not mark a surface `target_mapped` when a
named product or spike decision still changes that mapping. M1 remains visibly
blocked only by the canonical production profile and O-022 hard-cutover
freeze/recovery evidence; neither blocker requires Firebase application work.
