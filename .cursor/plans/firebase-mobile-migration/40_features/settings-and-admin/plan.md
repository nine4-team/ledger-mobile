## Goal
Produce parity-grade specs for `settings-and-admin`.

## Inputs to review (source of truth)
- Feature map entry: `40_features/feature_list.md` → **Feature 4: Settings + admin/owner management** (`settings-and-admin`)
- Offline architecture: `OFFLINE_FIRST_V2_SPEC.md` (Firestore-native offline persistence + scoped listeners + request-doc workflows)
- Related existing specs:
  - Auth/invite acceptance + protected routing: `40_features/auth-and-invitations/README.md`
  - Shared offline media guardrail: `40_features/_cross_cutting/ui/components/storage_quota_warning.md`

## Owned screens (list)
- `Settings` — contract required? **yes**
  - why: high-branching tabbed screen with role-gated sections, multiple CRUD sub-flows, and media upload (logo).

## Cross-cutting dependencies (link)
- Offline architecture constraints (metadata collections must be readable offline via Firestore-native persistence): `OFFLINE_FIRST_V2_SPEC.md`
- Auth/account context and roles gating: `40_features/auth-and-invitations/README.md`
- Storage quota warning + offline upload gating (shared): `40_features/_cross_cutting/ui/components/storage_quota_warning.md`

## Output files (this work order will produce)
Minimum:
- `README.md`
- `feature_spec.md`
- `acceptance_criteria.md`

Screen contracts (required):
- `ui/screens/Settings.md`

## Prompt packs (copy/paste)
Create `prompt_packs/` with 2–4 slices. Each slice must include:
- exact output files
- source-of-truth code pointers (file paths)
- evidence rule

Recommended slices:
- Slice A: Settings screen contract (tabs + role gating + offline/online behavior)
- Slice B: Presets managers (budget categories, vendor defaults, space templates)
- Slice C: Admin/owner management (user invites + account creation + pending invitations)

## Done when (quality gates)
- Acceptance criteria all have parity evidence or explicit deltas.
- Offline behaviors are explicit (readability offline, mutation policy online vs queued).
- No specs imply large listeners; any freshness uses bounded/scoped reads/listeners and/or explicit refresh (per `OFFLINE_FIRST_V2_SPEC.md`).
- Cross-links are complete.

