# Settings + admin/owner management (Firebase mobile migration feature spec)

This folder defines the parity-grade behavior spec for Ledger’s **Settings** area: business profile, presets, and admin/owner management, grounded in the existing web app and adapted to the React Native + Firebase **offline-first** architecture.

## Scope
- Settings hub (single screen with tabs)
- General tab:
  - View current user profile info (name/email/role)
  - Business profile (admin-gated): update business name + upload/update business logo
- Presets tab (admin-gated):
  - Budget categories manager (create/edit/archive/unarchive, reorder, itemization toggle)
  - Vendor defaults manager (10 slots; edit/clear; reorder)
  - Space templates manager (create/edit/archive/unarchive; reorder; checklists editor)
- Users tab (admin/owner-gated):
  - Create invitation links
  - View pending invitations and copy links
  - View team members and roles
- Account tab (owner-gated):
  - Create a new account (and generate an invitation for the first admin user)
  - View accounts and pending invitations, copy links

## Non-scope (for this feature folder)
- Invitation acceptance (`/invite/:token`) and auth bootstrap — owned by `auth-and-invitations`
- Roles v2 / scoped permissions — net-new planned feature (not in parity scope here)
- Subscription/billing/entitlements — cross-cutting
- Pixel-perfect UI design

## Key docs
- **Feature spec**: `feature_spec.md`
- **Acceptance criteria**: `acceptance_criteria.md`
- **Screen contracts**:
  - `ui/screens/Settings.md`

## Cross-cutting dependencies
- Auth + invitations (acceptance + protected routing): `40_features/auth-and-invitations/README.md`
- Offline architecture constraints (Firestore-native offline persistence + scoped listeners + request-doc workflows): `OFFLINE_FIRST_V2_SPEC.md`
- Storage quota warning + offline upload gating (shared guardrail): `40_features/_cross_cutting/ui/components/storage_quota_warning.md`
- Billing + entitlements (free tier user limit): `40_features/_cross_cutting/billing-and-entitlements/feature_spec.md`

## Parity evidence (web sources)
- Settings screen + tab gating: `src/pages/Settings.tsx`
- Navigation entrypoint: `src/components/layout/Header.tsx`
- Role signals:
  - `src/contexts/AuthContext.tsx` (`isOwner`)
  - `src/contexts/AccountContext.tsx` (`isAdmin`)
- Business profile read/write:
  - `src/contexts/BusinessProfileContext.tsx`
  - `src/services/businessProfileService.ts`
  - `src/services/imageService.ts` (`uploadBusinessLogo`, validation helpers)
- Presets UIs:
  - Budget categories: `src/components/BudgetCategoriesManager.tsx`
  - Vendor defaults: `src/components/VendorDefaultsManager.tsx`
  - Space templates: `src/components/spaces/SpaceTemplatesManager.tsx`
- Admin/owner management:
  - Users: `src/components/auth/UserManagement.tsx`
  - Account: `src/components/auth/AccountManagement.tsx`
  - Invite helpers: `src/services/supabase.ts` (`createUserInvitation`, pending invitations helpers)

