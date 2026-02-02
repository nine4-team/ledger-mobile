# Execution plan (implementation order) — Firebase Mobile Ledger

This document is the **central “what gets built when” plan** for the Firebase mobile migration.

## Start here (single entry point)

If you only read a handful of docs, read these in order:

- `README.md` (canonical navigation index for this doc set)
- `EXECUTION_PLAN.md` (this file; implementation order)
- `OFFLINE_FIRST_V2_SPEC.md` (canonical architecture constraints)
- `40_features/feature_list.md` (what we’re building)
- `40_features/_authoring/feature_speccing_workflow.md` (how to run feature work)
- `40_features/_authoring/templates/definition_of_done.md` (spec-complete criteria)
- `CHANGELOG.md` (what moved/changed in the doc set)

It answers:
- “What do I need to implement vs what is doc-only?”
- “What order should we build things in to avoid rework and drift?”

This is intentionally different from:
- `ROADMAP.md` (roadmap of the **docs** we plan to write / structure)
- `40_features/feature_list.md` (scope inventory)
- `40_features/_authoring/templates/definition_of_done.md` (spec quality controller)

---

## How to know what you need to implement

### 1) Treat acceptance criteria as the “build list”

For a given feature folder `40_features/<feature>/`:
- **Implement what is required by** `acceptance_criteria.md` (the checklist).
- Use `feature_spec.md` and `ui/screens/*.md` as the detailed behavior/contracts that explain *how* to meet acceptance.

### 2) Cross-cutting feature folders are specs, not code locations

`40_features/_cross_cutting/` contains **shared contracts/specs**. You still implement the actual systems in app code (typically under `src/` and `app/`), but you implement them **once** and reuse them everywhere.

### 3) Doc-only vs code-required (rule of thumb)

- **Doc-only**:
  - prompt packs (`prompt_packs/`)
  - screen contracts (`ui/screens/*.md`) unless they introduce new shared primitives
  - parity evidence notes / links
- **Code-required**:
  - anything in acceptance criteria
  - anything described as “cross-cutting subsystem” (e.g., offline media lifecycle)
  - anything that affects correctness/cost/security (request-doc workflows, permissions, listener scoping, etc.)

---

## Spec authoring vs implementation (two-stage process)

This migration has an explicit two-stage workflow:

1) **Spec authoring (prompt packs → specs)**
   - Use `40_features/_authoring/feature_speccing_workflow.md`.
   - Run the feature-local `prompt_packs/` to produce **spec outputs**:
     `feature_spec.md`, `acceptance_criteria.md`, and any needed `ui/screens/*.md`.
   - Validate “spec complete” using `40_features/_authoring/templates/definition_of_done.md`.

2) **Implementation (acceptance criteria → code)**
   - Build from `acceptance_criteria.md` in the order below.
   - Use feature specs + screen contracts as the detailed behavior source.

Spec authoring is complete for this migration; the checklist below is retained for reference only. The phase sections below it are for **implementation order**.

---

## Legacy web app parity references (read-only context)

Many specs are parity-grounded against the legacy web app. If a spec mentions “web app behavior” but does **not** include a concrete file path, use these pointers to resolve the exact source:

- **Web app repo (parity evidence only)**: `/Users/benjaminmackenzie/Dev/ledger`
- **Cross-cutting UI parity index**: `40_features/_cross_cutting/ui/README.md`
- **Canonical shared UI contracts**: `40_features/_cross_cutting/ui/shared_ui_contracts.md`
- **UI parity inventory matrix**: `40_features/_cross_cutting/ui/ui_parity_inventory_matrix.md`
- **Parity evidence workflow (examples + rules)**: `40_features/_cross_cutting/ui/shared_ui_speccing_workflow.md`
- **Alignment/gap notes**: `20_data/alignment_issues_vs_40_features.md`

If you add or clarify parity evidence while implementing, include a full web app path (and function/component when helpful) in the spec or acceptance criteria.

---

## Architectural baseline (do not fight it)

Canonical architecture source:
- `OFFLINE_FIRST_V2_SPEC.md`

Key implications for execution:
- Firestore (native RN SDK) is **canonical** with offline persistence.
- Scoped/bounded listeners are allowed; no unbounded “listen to everything”.
- Multi-doc invariant operations use **request-doc workflows** (Cloud Function applies the transaction).
- SQLite is allowed only as a **derived search index** (index-only; non-authoritative).
  - For **Ledger Mobile**, the derived search index is **required** (search is not optional).

---

## Build order (phased)

### Sub-phases checklist (spec authoring prompt packs — completed, reference only)

This section is intentionally **not invented**: it lists the **actual prompt packs already present** under `40_features/**/prompt_packs/`, grouped into the macro phases below for historical context. No action is required unless a spec gap is discovered.

Conventions:
- Checkboxes are manual (edit this doc as you complete each pack).
- `README.md` entries under `prompt_packs/` are informational; the checklist items are the `chat_*.md` packs.

#### Phase 1 — Auth + account context

- [ ] `40_features/auth-and-invitations/prompt_packs/chat_a_auth_boot_protected_route.md`
- [ ] `40_features/auth-and-invitations/prompt_packs/chat_b_invite_accept_and_callback.md`
- [ ] `40_features/auth-and-invitations/prompt_packs/chat_c_account_context_offline_boot_roles.md`

#### Phase 2 — Cross-cutting runtime primitives

- [ ] `40_features/connectivity-and-sync-status/plan.md` (no prompt packs; ensure spec outputs exist and use acceptance criteria for implementation)
- [ ] `40_features/_cross_cutting/offline-media-lifecycle/prompt_packs/chat_a_local_cache_and_state_machine.md`
- [ ] `40_features/_cross_cutting/offline-media-lifecycle/prompt_packs/chat_b_upload_queue_and_idempotency.md`
- [ ] `40_features/_cross_cutting/offline-media-lifecycle/prompt_packs/chat_c_cleanup_quota_and_bounded_cache.md`
- [ ] `40_features/_cross_cutting/offline-media-lifecycle/prompt_packs/chat_d_tests_and_edge_case_audit.md`

#### Phase 3 — Scope switching + shared module contracts (anti-drift)

- [ ] `40_features/business-inventory/prompt_packs/chat_d_scope_config_object_contract.md`

#### Phase 4 — Core workspaces + shared domain modules

- [ ] `40_features/projects/prompt_packs/chat_a_projects_list_create_and_prereqs.md`
- [ ] `40_features/projects/prompt_packs/chat_b_project_layout_refresh_edit_delete.md`
- [ ] `40_features/projects/prompt_packs/chat_c_projects_offline_collab_entitlements.md`

- [ ] `40_features/project-transactions/prompt_packs/chat_a_transactions_list_filters_export.md`
- [ ] `40_features/project-transactions/prompt_packs/chat_b_transaction_form_create_edit.md`
- [ ] `40_features/project-transactions/prompt_packs/chat_c_transaction_detail_media_items_actions.md`

- [ ] `40_features/spaces/prompt_packs/chat_a_spaces_list_create_edit_delete.md`
- [ ] `40_features/spaces/prompt_packs/chat_b_space_detail_items_checklists.md`
- [ ] `40_features/spaces/prompt_packs/chat_c_space_detail_images_templates_media.md`

- [ ] `40_features/business-inventory/prompt_packs/chat_a_business_inventory_home_tabs_refresh_state.md`
- [ ] `40_features/business-inventory/prompt_packs/chat_b_inventory_items_scope_config_and_bulk_ops.md`
- [ ] `40_features/business-inventory/prompt_packs/chat_c_inventory_transactions_scope_config_and_receipts.md`

- [ ] `40_features/inventory-operations-and-lineage/prompt_packs/chat_a_multi_entity_ops_and_idempotency.md`
- [ ] `40_features/inventory-operations-and-lineage/prompt_packs/chat_b_lineage_and_visibility.md`
- [ ] `40_features/inventory-operations-and-lineage/prompt_packs/chat_c_ui_guardrails_and_copy.md`

#### Phase 5 — Secondary modules + outputs

- [ ] `40_features/budget-and-accounting/prompt_packs/chat_a_budget_rollup_math_and_canonical_attribution.md`
- [ ] `40_features/budget-and-accounting/prompt_packs/chat_b_design_fee_identity_and_budget_categories_metadata.md`
- [ ] `40_features/budget-and-accounting/prompt_packs/chat_c_accounting_rollups_and_reports_entrypoints.md`

- [ ] `40_features/reports-and-printing/prompt_packs/chat_a_project_invoice.md`
- [ ] `40_features/reports-and-printing/prompt_packs/chat_b_client_summary.md`
- [ ] `40_features/reports-and-printing/prompt_packs/chat_c_property_management_summary.md`

- [ ] `40_features/invoice-import/prompt_packs/chat_a_screen_contracts_importers.md`
- [ ] `40_features/invoice-import/prompt_packs/chat_b_parsing_and_debug_tooling.md`
- [ ] `40_features/invoice-import/prompt_packs/chat_c_media_background_upload_and_offline_first.md`

#### Phase 6 — Parity knowledge / web-only (do not implement 1:1 in RN)

- [ ] `40_features/pwa-service-worker-and-background-sync/prompt_packs/chat_a_web_parity_inventory.md`
- [ ] `40_features/pwa-service-worker-and-background-sync/prompt_packs/chat_b_mobile_background_policy_and_cost.md`
- [ ] `40_features/pwa-service-worker-and-background-sync/prompt_packs/chat_c_sync_ux_and_error_actions.md`

#### Cross-cutting: entitlements + permissions (schedule when needed)

- [ ] `40_features/_cross_cutting/billing-and-entitlements/prompt_packs/chat_a_data_model_and_entitlements_snapshot.md`
- [ ] `40_features/_cross_cutting/billing-and-entitlements/prompt_packs/chat_b_gated_creates_and_counters.md`
- [ ] `40_features/_cross_cutting/billing-and-entitlements/prompt_packs/chat_c_offline_ux_and_retry_semantics.md`
- [ ] `40_features/_cross_cutting/billing-and-entitlements/prompt_packs/chat_d_tests_and_edge_case_audit.md`

- [ ] `40_features/_cross_cutting/category-scoped-permissions-v2/prompt_packs/chat_a_entitlements_and_server_side_rules.md`
- [ ] `40_features/_cross_cutting/category-scoped-permissions-v2/prompt_packs/chat_b_delta_sync_scoping.md`
- [ ] `40_features/_cross_cutting/category-scoped-permissions-v2/prompt_packs/chat_c_ui_gating_and_redaction.md`
- [ ] `40_features/_cross_cutting/category-scoped-permissions-v2/prompt_packs/chat_d_tests_and_edge_case_audit.md`

### Phase 0 — Hard guardrails + “can ship a dev client”

**Goal**: you can run the app in a native dev client and enforce “no accidental web SDK” regressions.

Prereq: relevant feature specs are “spec complete” per `40_features/_authoring/templates/definition_of_done.md`.

Implement / verify:
- Native Firebase wiring (Auth/Firestore/Functions)
- `npm run check:native-only` passes and is used routinely
- Minimal app boot with navigation shell

Primary references:
- `OFFLINE_FIRST_V2_SPEC.md`
- `30_app_skeleton/app_skeleton_spec.md`

---

### Phase 1 — Auth + account context + protected navigation

**Goal**: a user can sign in, resolve account context, and enter the app safely.

Implement:
- Auth flows + invite acceptance (as scoped by `auth-and-invitations`)
- Account membership resolution and “no access” handling

Primary references:
- `40_features/auth-and-invitations/feature_spec.md`
- `10_architecture/security_model.md`

---

### Phase 2 — Cross-cutting runtime primitives (reused everywhere)

**Goal**: build the shared “platform” pieces before domain modules so features don’t implement their own versions.

Implement:
- **Scoped listener lifecycle plumbing** (attach/detach on background/resume; bounded scope IDs)
  - Source: `src/data/listenerManager.ts`, `src/data/useScopedListeners.ts`, `src/data/LISTENER_SCOPING.md`
- **Global sync UX** (connectivity banner, pending/failed surfacing, retry affordances)
  - Source: `40_features/connectivity-and-sync-status/feature_spec.md`
- **Request-doc framework** (client helper + rules + Cloud Function pattern)
  - Source: `OFFLINE_FIRST_V2_SPEC.md` (request-doc section) + feature specs that require multi-doc invariants
- **Offline media lifecycle** (local cache, placeholder states, upload queue, cleanup)
  - Source: `40_features/_cross_cutting/offline-media-lifecycle/feature_spec.md`
- **Derived offline search index (SQLite/FTS; index-only, required for this product)**
  - Source: `OFFLINE_FIRST_V2_SPEC.md` (Offline “Item Search Index” module)
  - Product requirements: feature specs under `project-items/`, `business-inventory/`, and any search-heavy lists

---

### Phase 3 — Scope switching + shared module contracts (anti-drift foundation)

**Goal**: guarantee “project vs inventory” does not fork implementations.

Implement:
- Shared Items + Transactions module shape + `ScopeConfig` contract consumption (no implicit `projectId`)
  - Source: `40_features/_cross_cutting/ui/shared_items_and_transactions_modules.md`
- Scope switching + listener scoping behavior
  - Source: `40_features/_cross_cutting/scope-switching-and-sync-lifecycle/feature_spec.md`
- List state persistence keyed by scope (`listStateKey`)
  - Source: `40_features/_cross_cutting/ui/shared_items_and_transactions_modules.md`
  - Source: `40_features/navigation-stack-and-context-links/feature_spec.md`

---

### Phase 4 — Core workspaces + shared domain modules

**Goal**: implement the core reusable modules once, then compose them in each workspace shell.

Implement (recommended order):
- Projects workspace shell
- Shared Items module (list/detail/form + bulk actions + images)
- Shared Transactions module (list/detail/form + receipts + export/share)
- Spaces module (CRUD + checklists + media)
- Business Inventory workspace shell (composes shared modules with `scope: 'inventory'`)
- Inventory operations + lineage (request-doc / server-owned invariants)

Primary references:
- `40_features/projects/…`
- `40_features/project-items/…`
- `40_features/project-transactions/…`
- `40_features/spaces/…`
- `40_features/business-inventory/…`
- `40_features/inventory-operations-and-lineage/…`

---

### Phase 5 — Secondary modules + outputs

Implement:
- Budget + accounting rollups
- Reports + share/print surfaces
- Invoice import

Primary references:
- `40_features/budget-and-accounting/…`
- `40_features/reports-and-printing/…`
- `40_features/invoice-import/…`

---

### Phase 6 — Migration tooling + verification + ops

Implement:
- Migration scripts/runbook + verification checklist
- Emulator + 2-device test plan (offline + queued writes + media + request-doc)
- Observability + cost guardrails (listener counts, reads/writes, storage egress, crash-free)

Primary references:
- `50_migration/README.md` (and planned docs under `50_migration/` per `ROADMAP.md`)
- `60_testing/README.md` (and planned `test_plan.md`)
- `70_ops/observability_and_cost_guardrails.md`

---

## “What’s missing?” quick test

If you’re unsure whether something needs implementation, ask:
- Is it in any feature’s `acceptance_criteria.md`? If yes: implement.
- Is it a cross-cutting subsystem needed by 2+ features (media, request-doc, list state, scope config)? If yes: implement once, early.
- Is it only parity evidence or an authoring prompt pack? If yes: doc-only.

