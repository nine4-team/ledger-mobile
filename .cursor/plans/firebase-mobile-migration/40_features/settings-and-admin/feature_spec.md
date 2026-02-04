# Feature spec: Settings + admin/owner management

## Summary
`settings-and-admin` is the administrative and configuration hub for an account. It includes:

- Read-only profile view for all users.
- Admin-managed configuration that drives other modules (business profile, presets).
- Admin/owner flows for invitations and user/account management.
- Troubleshooting tools for offline export and stuck sync issues.

This feature is **not collaborative in the realtime sense** (no “live updates” required), but it must be **correct and explicit** about online-required mutations and about offline readability of presets.

## Owned screens
- `Settings` (tabbed screen): see `ui/screens/Settings.md`

## Primary user flows (parity)

### A) View profile + role
- Open Settings → General → Profile section shows name/email/role.

Parity evidence: `src/pages/Settings.tsx`.

### B) (Admin) Update business profile (name + logo)
- Open Settings → General → Business Profile section.
- Edit business name.
- Optionally pick a logo file → preview renders immediately.
- Save:
  - Persist logo as an `AttachmentRef` on `Profile.logo` (see `20_data/data_contracts.md`).
    - While selecting/previewing locally, `logo.url` may be `offline://<mediaId>` (with `kind: "image"`).
    - Upload state (`local_only | uploading | failed | uploaded`) is derived locally (see `40_features/_cross_cutting/offline-media-lifecycle/feature_spec.md`), not stored on the Firestore profile doc.
  - When online, upload the logo (if changed) and update the business profile record to a remote-backed URL.
  - Success banner appears and auto-clears.

Parity evidence:
- UI + save sequencing: `src/pages/Settings.tsx` (`handleSaveProfile`).
- Read/write: `src/contexts/BusinessProfileContext.tsx`, `src/services/businessProfileService.ts`.
- Logo upload + validation: `src/services/imageService.ts`, `src/pages/Settings.tsx` (`validateImageFile`, `uploadBusinessLogo`).

### C) (Admin) Manage presets
Open Settings → Presets → choose one:

- Budget categories:
  - Create/edit category (name required)
  - Archive/unarchive categories
  - Reorder categories by drag
  - Set per-category type (drives behavior):
    - `standard` (default)
    - `itemized` (enables itemization UI + tax inputs)
    - `fee` (enables “fee tracker” received semantics in budgets)
    - Mutual exclusivity: a category cannot be both `fee` and `itemized` because type is a single field
  - Toggle “exclude from overall budget” (default: included)

Account bootstrap requirement (Firebase migration; required):
- When a **new account is created** (or when a new member first joins an account), the system must ensure the account has a **seeded set of budget category presets** sufficient for the core app to function.
- The seeded presets must include **“Furnishings”** as a budget category preset.
- This migrated app has **no category-defaulting concept** used for transaction entry or UI selection.
- The only “what shows up first” behavior for budget progress trackers is driven by **pinned budget categories** (per-user per-project preferences; see `20_data/data_contracts.md` → `ProjectPreferences`).
  - For **every new project**, the system ensures **“Furnishings” is pinned by default**:
    - seed the creator’s `ProjectPreferences` doc at project creation time
    - create other users’ `ProjectPreferences` docs lazily when a UI surface needs it (Projects list preview / Budget tab), if missing

Parity evidence: `src/components/BudgetCategoriesManager.tsx`.

- Vendor defaults:
  - 10 slots; edit a slot (freeform vendor/source name) and save
  - Clear a slot
  - Reorder slots by drag

Parity evidence: `src/components/VendorDefaultsManager.tsx`.

- Space templates:
  - Create/edit template (name required, notes optional)
  - Edit checklists: checklist + items CRUD inside the template editor
  - Archive/unarchive templates
  - Reorder templates by drag

Parity evidence: `src/components/spaces/SpaceTemplatesManager.tsx`.

### D) (Admin/Owner) Invite users, view pending invites, view team roster
- Open Settings → Users.
- Create invitation link (email + role selection).
- Link is copied to clipboard automatically; pending invitations show copy action.
- Team list shows users and role badges.
 - Invitation creation is entitlement-gated (free tier allows a single user per account).

Parity evidence: `src/components/auth/UserManagement.tsx`.

### E) (Owner) Create accounts + manage account-level pending invitations
- Open Settings → Account.
- Create account: provide account name + first user email (admin).
- A new invitation link is shown with a copy button.
- Accounts list shows pending invitations; expands to show invitation links and copy affordances.

Parity evidence: `src/components/auth/AccountManagement.tsx`.

### F) Troubleshoot offline data + sync issues
- Open Settings → Troubleshooting.
- Export offline data:
  - downloads a JSON snapshot of local cache + queued operations
  - includes counts and a consistency report for missing item/transaction references
  - shows a success timestamp or error message
  - warns that exported data can be sensitive
- Sync issues manager:
  - lists item update operations that are blocked because the item is missing on the server
  - supports select all, recreate, and discard flows
  - shows a confirmation dialog before discarding
  - includes a “Retry sync” action

Parity evidence:
- `src/components/settings/TroubleshootingTab.tsx`
- `src/components/settings/SyncIssuesManager.tsx`

## Entities touched (conceptual; Firebase mapping)
These are “small metadata” entities that must sync efficiently and be cached locally:

- `Profile` (business name + logo):
  - `accounts/{accountId}/profile/default`
- `budget_categories` (including archive state and optional metadata like itemization enabled)
- `vendor_defaults` (10 slots + ordering)
- `space_templates` (including nested checklists)
- `account_users` / users list
- `invitations` (pending invitations per account)
- Offline cache snapshot + operation queue (local-only; not Firestore-backed)

## Offline behavior (required)

### Reads (must work offline)
- Presets (budget categories, vendor defaults, space templates) must be readable offline because:
  - transaction forms require vendors/categories
  - space creation requires templates

Implementation note:
- This implies these should be read in a **cache-first** way and kept available offline via **Firestore-native offline persistence**, per `OFFLINE_FIRST_V2_SPEC.md`. (No bespoke local “sync engine” is required for this behavior.)

### Writes (policy)
- Admin/owner writes in Settings should be **online-required by default** (business profile update, presets mutation, invites, account creation).
  - Intentional delta: web parity does not always hard-block offline actions; RN should be explicit to avoid “false success” flows.
  - If we later allow offline-queued metadata writes, this spec can be updated to allow queued writes with clear pending/error UX and server-side enforcement, per `OFFLINE_FIRST_V2_SPEC.md`.

### Troubleshooting tools (local-first)
- Offline export and sync-issue actions are **local-first** and should remain usable without a connection.
- Export uses the local cache snapshot; if no cache is available, show a clear error.
- Recreate/discard actions should operate on the local queue; any server writes occur when connectivity resumes.

### App restart / reconnect
- If presets were previously cached:
  - App restart offline should still allow downstream screens to function using cached presets.
- On reconnect:
  - A foreground sync should refresh metadata collections; Settings should reflect updated values on next open (or via manual refresh where present).

## Permissions / role gating (required)
- **Everyone**: can access Settings → General → Profile section.
- **Everyone**: can access Settings → Troubleshooting.
- **Admin (or owner)**:
  - can access Business Profile editor
  - can access Presets editor
  - can access Users tab
- **Owner only**:
  - can access Account tab

Parity evidence:
- Tab visibility: `src/pages/Settings.tsx` (`isOwner()`, `isAdmin`).
- Users / account access checks: `src/components/auth/UserManagement.tsx`, `src/components/auth/AccountManagement.tsx`.

## Error states (required)
- Not authenticated / no account context:
  - Settings should fail closed: show “No account found…” messaging where accountId is required.
- Network offline:
  - For admin/owner write actions: show a clear “requires connection” error.
- Validation errors:
  - Business profile name required
  - Logo file validation (type + size)

## Collaboration / realtime needs
- **No** realtime requirement; eventual consistency is sufficient.
- Do not implement via large listeners. If we need better foreground freshness, prefer bounded/scoped reads/listeners and/or explicit refresh, per `OFFLINE_FIRST_V2_SPEC.md`.

## Dependencies
- Auth + account context (user role, current accountId): `src/contexts/AuthContext.tsx`, `src/contexts/AccountContext.tsx`
- Business profile context/service: `src/contexts/BusinessProfileContext.tsx`, `src/services/businessProfileService.ts`
- Offline prerequisites / metadata readability: `src/services/offlineStore.ts` (web parity reference for “must be readable offline”), and `OFFLINE_FIRST_V2_SPEC.md` (Firestore-native offline persistence baseline for mobile).
- Media upload pipeline: `src/services/imageService.ts`, plus quota guardrail for offline selection:
  - `40_features/_cross_cutting/ui/components/storage_quota_warning.md`

