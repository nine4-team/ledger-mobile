# Screen contract: Settings

## Purpose
Provide one place for users to:

- View their profile info (read-only).
- (Admin) manage business profile + presets that other screens depend on.
- (Admin/Owner) invite/manage users.
- (Owner) manage accounts.

This is intentionally a **high-branching** screen; the contract exists to preserve role gating, offline behavior, and consistent “online required” messaging for admin operations.

## Entry points
- From global header navigation: Settings icon/tab.
- Route: `/settings` (web parity). React Native should provide the equivalent “Settings” route.

## Layout
- Page title: “Settings”
- Tabs (top-level):
  - `General` (always visible)
  - `Presets` (always visible, but content is admin-gated)
  - `Troubleshooting` (always visible)
  - `Users` (visible only for owner/admin)
  - `Account` (visible only for owner)

Parity evidence: tab logic is in `src/pages/Settings.tsx` (`activeTab`, `isOwner()`, `isAdmin`).

## General tab

### Profile section (read-only)
- Shows:
  - Full Name
  - Email
  - Role (displayed, with helper copy indicating role changes require an admin)

Parity evidence: `src/pages/Settings.tsx` “Profile Information”.

### Business profile section (admin-only)
- Visible only if `isAdmin === true` (account admin or system owner).
- Editable:
  - Business name (required; Save disabled if blank)
  - Business logo (image file picker; preview shown)
- Save behavior:
  - If a new logo file is selected, upload it first, then update the business profile.
  - Shows a success message (“Business profile saved successfully!”) and auto-clears after ~3s.
  - On error, shows an error banner with the error message.

Validation:
- Logo selection rejects invalid image types and images over 10MB with a clear error message.

Parity evidence:
- Admin gating + save flow: `src/pages/Settings.tsx` (`handleSaveProfile`, `isAdmin`).
- Logo validation: `src/pages/Settings.tsx` (`ImageUploadService.validateImageFile`).

Offline behavior:
- If offline, business profile mutations are **online-required** (do not attempt to queue); show a clear “requires connection” error on Save.
  - Intentional delta: current web parity does not explicitly block Save when offline; RN should be explicit to avoid false success.

## Presets tab (admin-only)
- If user is not admin:
  - Show message: “Presets are only configurable by account administrators.”
- If admin:
  - Show sub-tabs:
    - Budget
    - Vendors
    - Tax
    - Spaces
  - Each sub-tab hosts the corresponding manager component.

Parity evidence: `src/pages/Settings.tsx` (`activePresetTab`, `isAdmin`, manager components).

Offline behavior:
- Presets must be **readable offline** (because transactions/items/spaces depend on these pickers).
- Mutations are **online-required** by default unless/until we explicitly allow offline-queued metadata writes with clear pending/error UX (and server-side enforcement), per `OFFLINE_FIRST_V2_SPEC.md`.

## Users tab (owner/admin)
- Visible for owner or admin.
- Hosts “User Management”:
  - Create invitation link (email + role selector)
  - Show pending invitations and copy invitation link(s)
  - Show team members and their role badges

Parity evidence: `src/components/auth/UserManagement.tsx`.

Offline behavior:
- Invites and user list refresh are **online-required** (do not queue).
- If offline:
  - Show clear “requires connection” error when attempting to create an invite link.
  - Allow viewing last-cached team list if available (optional; depends on metadata caching strategy).

## Account tab (owner only)
- Visible only for owner.
- Hosts “Account Management”:
  - Create new account (requires “account name” + “first user email”)
  - After create, show invitation link with copy affordance
  - List all accounts; show pending invitations per account; expand/collapse and copy

Parity evidence: `src/components/auth/AccountManagement.tsx`.

Offline behavior:
- Account creation is **online-required**.

## Troubleshooting tab (all users)
- Visible to all users.
- Purpose: provide diagnostic tools for offline cache/export and stuck sync operations.

### Offline data export
- Shows a brief note that the export is a dump of local cache and may be incomplete or differ from server state.
- A button triggers a JSON download of local offline cache + queued operations.
  - The payload includes counts and a consistency report for item/transaction references.
  - The file name includes a timestamp and the scoped account id when available.
- Shows:
  - error banner if the export fails
  - success banner with timestamp if the export succeeds
- Includes a warning that the export may contain sensitive data.

### Sync issues manager
- Surfaces stuck operations where an item update can’t sync because the item is missing on the server.
- If no issues:
  - show an “All clear” message
  - provide a “Retry sync” button
- If issues exist:
  - list rows with item label, change type, and error summary
  - allow multi-select (select all)
  - actions:
    - “Recreate” (single or selected) to re-create missing items on the server
    - “Discard” (single or selected) to drop stuck operations and delete the local item
  - show a confirmation dialog before discarding

Parity evidence:
- Troubleshooting tab + entry: `src/pages/Settings.tsx` (`activeTab === 'troubleshooting'`).
- Offline export: `src/components/settings/TroubleshootingTab.tsx`.
- Sync issues manager: `src/components/settings/SyncIssuesManager.tsx`.

Offline behavior:
- Export and sync-issue management are **local-first** and should remain available offline.
- If actions require network, they should queue and apply when connectivity returns; avoid false success messaging.

## Error handling & messaging rules
- All admin/owner mutations should:
  - show “saving/creating” busy state
  - show a clear error banner on failure
  - show a success confirmation that auto-clears after ~3s where applicable
- Clipboard copy should provide confirmation feedback.

## Performance notes
- Avoid any approach that requires “listening to all presets/users/accounts”.
- Treat these as small metadata collections: refresh on enter, allow manual refresh if needed, and rely on Firestore-native offline persistence (and bounded/scoped reads/listeners when appropriate) for eventual consistency, per `OFFLINE_FIRST_V2_SPEC.md`.

