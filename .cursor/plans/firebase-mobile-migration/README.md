# Firebase Mobile Migration (React Native + Firebase, offline-first)

This folder is the **single source of truth** for migration planning docs. The goal is to keep it **non-redundant** and **easy to navigate** for humans and AI devs.

## Start here (canonical entry point)

- **Workflow for feature specs (the only process doc)**: `40_features/_authoring/feature_speccing_workflow.md`
- **Doc set roadmap (big-picture: what we’re doing + planned doc set / tree)**: `ROADMAP.md`
- **Execution plan (implementation order; what gets done when)**: `EXECUTION_PLAN.md`
- **Connectivity + sync status spec (global sync UX)**: `40_features/connectivity-and-sync-status/README.md`
- **Single canonical feature list**: `40_features/feature_list.md`
- **What moved/was deleted (so nothing feels “mysteriously gone”)**: `CHANGELOG.md`
- **Reusable authoring templates (single home)**: `40_features/_authoring/templates/`
- **Per-feature specs + prompt packs (prompt packs live next to features)**: `40_features/`
- **Non-feature docs live here (created now; currently mostly empty)**:
  - `10_architecture/`
  - `20_data/`
  - `30_app_skeleton/`
  - `50_migration/`
  - `60_testing/`
  - `70_ops/`

## Cross-cutting spec index (linked here for canonicality)

- **Offline media lifecycle (attachments offline cache + uploads + cleanup)**: `40_features/_cross_cutting/offline-media-lifecycle/feature_spec.md`
- **Billing + entitlements (RevenueCat; free tier gating)**: `40_features/_cross_cutting/billing-and-entitlements/feature_spec.md`
- **Code reuse + porting policy (reuse-first; rewrite edges only)**: `40_features/_cross_cutting/code_reuse_and_porting_policy.md`
- **Category-scoped access control (Roles v2)**: `40_features/_cross_cutting/category-scoped-permissions-v2/feature_spec.md`
- **UI style lanes + starter surfaces (import + styling discipline; reusable components)**: `40_features/_cross_cutting/ui/README.md`

## Core architecture invariant (correctness + cost control; do not violate)

Canonical architecture source:
- `OFFLINE_FIRST_V2_SPEC.md`

Non-negotiables (restated plainly):
- **Firestore-native offline persistence** is the baseline (Firestore is canonical).
- **Scoped/bounded listeners only** (never “listen to everything”).
- **Request-doc workflows** for multi-doc invariant correctness (server applies the transaction).
- **SQLite is index-only** (derived search index), not a canonical entity store.
  - For **Ledger Mobile**, the derived search index is **required** because robust item search is a required feature.

## If you’re “steering the boat” (human)

You should only need to do two things:

1) Pick a feature from `40_features/feature_list.md`
2) Copy/paste one of that feature’s prompt packs from `40_features/<feature>/prompt_packs/` into a new AI dev chat

That’s it. You do **not** need to read `40_features/_authoring/feature_speccing_workflow.md` unless you’re creating a new feature folder/prompt packs from scratch.

## Canonicality rule (how you know nothing important is “hidden”)

- If a doc is **important/canonical**, it must be linked in this `README.md`.
- If it’s not linked here, treat it as **non-canonical** (draft, scratch, or obsolete).

## If you’re the AI dev

Follow `40_features/_authoring/feature_speccing_workflow.md`. Do **not** invent a second workflow or add new “toolkits/templates” folders.

## Directory conventions (what lives where)

- **`40_features/<feature>/`**: each feature’s spec set (and any feature-local work order)
  - **`plan.md`**: optional work order for producing/maintaining the feature docs
  - **`prompt_packs/`**: copy/paste prompt packs for separate AI dev chats (keep them feature-local)
- **`40_features/_cross_cutting/`**: shared flows/components/contracts used by multiple features (only create when needed)
- **`40_features/_authoring/templates/`**: the only place reusable authoring templates live (DoD, triage rubric, prompt pack template, etc.)

## What to do next (human-friendly)

1) Pick a feature from `40_features/feature_list.md`.
2) Create (or open) `40_features/<feature>/plan.md` and slice the work into 2–4 prompt packs under `40_features/<feature>/prompt_packs/`.
3) Run one AI dev chat per prompt pack; each chat updates only the files listed in that pack.
4) Merge/cross-link: feature docs should link to any `_cross_cutting` docs they depend on, and to `OFFLINE_FIRST_V2_SPEC.md` for architecture constraints.

