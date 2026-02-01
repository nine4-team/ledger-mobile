# Billing and entitlements — Acceptance criteria (migration)

Each non-obvious criterion is backed by an **intentional delta** reference to the migration plan, since this is net-new behavior.

## Entitlements snapshot (server-owned)
- [ ] **Canonical path**: entitlement snapshot lives at `accounts/{accountId}/entitlements/current`.
- [ ] **Plan types**: `planType` supports `free` and `pro`.
- [ ] **Limits present**: snapshot includes `limits.maxProjects`, `limits.maxItems`, `limits.maxTransactions`, `limits.maxUsers`.
- [ ] **Server-owned writes**: clients cannot write the snapshot; it is written only by trusted backend/Functions.
- [ ] **Client-readable**: authenticated account members can read the snapshot for UX gating.

## Counters (server-owned stats)
- [ ] **Canonical path**: counters live at `accounts/{accountId}/stats`.
- [ ] **Fields present**: `projectCount`, `itemCount`, `transactionCount`, `userCount` exist and are numbers.
- [ ] **Server-owned updates**: counters are updated only by trusted backend/Functions.

## Gated creates
- [ ] **Create project is server-owned**: direct client creates to `accounts/{accountId}/projects/*` are disallowed when limits are enforced; creation is applied server-side (preferred: request-doc workflow processed by Functions).
- [ ] **Create project enforces limits**:
  - Free tier enforces `projectCount < limits.maxProjects` (with `maxProjects = 1`).
  - Pro tier increases/removes the limit per policy.
- [ ] **Membership/role validated**: server-owned create validates membership per `accounts/{accountId}/members/{uid}` (see `10_architecture/security_model.md`).
- [ ] **Add user is server-owned**: invitation acceptance or membership creation is server-owned and enforces `userCount < limits.maxUsers` (with `maxUsers = 1` in Free).
- [ ] **Request status is visible** (if using request-doc workflow): create requests expose debuggable `status` (`pending | applied | denied | failed`) and error info for UX.

## Offline behavior
- [ ] **Offline allow only when provable**: when offline, gated creates proceed only if cached `entitlements/current` + cached `stats` prove under-limit.
- [ ] **Offline block when unknown/at limit**: when offline and under-limit cannot be proven, the app blocks the operation and instructs the user to connect to verify/upgrade.

## Upgrade retry
- [ ] **Online upgrade CTA**: when blocked online, the UI offers an upgrade CTA.
- [ ] **Retry after entitlement refresh**: after purchase completes (online), the app refreshes entitlement snapshot and retries the blocked operation.

