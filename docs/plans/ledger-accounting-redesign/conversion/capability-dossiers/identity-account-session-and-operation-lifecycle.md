# Capability Dossier — Identity, Account Session, and Operation Lifecycle

Status: reviewed static characterization; all eight target-relevant surfaces in
the bounded identity/lifecycle batch have complete provider-neutral M2 maps;
identity implementation remains blocked on A-007/A-016 and production profile

## Outcome

An authorized person or MCP client can authenticate, discover only permitted
Ledger accounts, explicitly choose an account, work with an understandable
offline/session state, and end or switch the session without losing accepted
operations or exposing another account's data. Every mutation reports a durable
queued, applied, or rejected outcome rather than equating an SDK call with
business completion.

## Source Surfaces

### iOS/macOS identity and account lifecycle

| Surface ID | Source | Current responsibility |
|---|---|---|
| `SWIFT-C9CE3FC9787D` | `Auth/AuthManager.swift` | Firebase session listener; email/password and Google sign-in; direct provider signout |
| `SWIFT-8E9B2DFCD775` | `Services/AccountMembersService.swift` | Cache-first membership discovery; member listener; role/financial-access update |
| `SWIFT-D22F0D6F71E4` | `Services/AccountsService.swift` | Account read/listener, HTTP account creation, direct account update |
| `SWIFT-FE44BBB4D35B` | `Services/InvitesService.swift` | Direct invite list/create/revoke |
| `SWIFT-2CE194E495FF` | `Services/InviteLinks.swift` | Deep-link parsing and HTTP invite preview/acceptance |
| `SWIFT-C05952F542AD` | `State/AccountContext.swift` | Account discovery/selection, persisted last account, broad account listeners, in-memory financial filtering and deactivation |
| `SWIFT-2D9222A4489A` | `Views/RootView.swift` | Auth/account/invite root routing, offline/upload banners, context teardown on provider state change |
| `SWIFT-3B7DE77EA8E4` | `Views/Settings/AccountView.swift` | Account switch and confirm-then-direct signout |
| `SWIFT-0B9701086073` | `Views/SettingsPlaceholderView.swift` | Unused placeholder/debug settings with direct signout |
| `SWIFT-F84D40FBC375` | `Models/Account.swift` | Firestore-shaped account identity and logo model |
| `SWIFT-BECC3329E3AA` | `Models/AccountMember.swift` | Firestore-shaped principal membership, role, and financial scope |
| `SWIFT-D871AB13C6B1` | `Models/Invite.swift` | Firestore-shaped invitation and proposed access fields |

### MCP and server boundary

| Surface ID | Source | Current responsibility |
|---|---|---|
| `MCPMOD-38F4B8D34053` | `mcp-server/src/auth.ts` | Firebase ID-token verification; first/all membership account resolution |
| `MCPMOD-4938EA5E6169` | `mcp-server/src/oauth.ts` | MCP OAuth/PKCE, Firestore auth codes, HMAC access/refresh tokens |
| `MCPMOD-33934129DB02` | `mcp-server/src/context.ts` | Per-request, runtime, environment, then hardcoded account/user fallback |
| `MCPMOD-3E4E627EC002` | `mcp-server/src/userState.ts` | Firestore persistence of active MCP account per UID |
| `MCPMOD-B6552C94C033` | `mcp-server/src/tools/accounts.ts` | List/switch account tools with membership check |
| `FUNCTION-48B935AA722D` | `createAccountHttp` | Authenticated account/member/default bootstrap |
| `FUNCTION-64DF5B5FA8E6` | `previewInviteHttp` | Public token-based invite preview |
| `FUNCTION-605DE567BE56` | `acceptInviteHttp` | Authenticated invite acceptance and membership creation |
| `FUNCTION-A1F046859D60` / `FUNCTION-6C739413108B` | legacy callable duplicates | Older account creation/invite acceptance transports to retire |

### Evidence and callers

- `TEST-80E13A744139` covers account discovery, remembered selection,
  selection/deactivation, and error cases with mocks.
- `RootView`, `AccountView`, the account toolbar, Users settings, and essentially
  every feature context depend on `currentAccountId` and Firebase user UID.
- `MediaUploadQueue` survives restart independently of provider signout and is
  not inspected by either current signout path.
- Current Firestore rules, Functions, MCP Admin access, Storage, and query
  details are characterized in `current-backend-contract.md` and
  `current-query-contract.md`.

## Current Observable Behavior

### App

1. Firebase observes persistent provider state. Root routing shows invite
   signup, sign-in, account selection, or the main application.
2. Email/password and Google credential exchange are supported. Invite signup
   always creates an email/password Firebase user before accepting the invite.
3. Membership discovery queries all `users` subcollections by UID, attempts
   local Firestore cache first, resolves account documents sequentially, and
   sorts the remembered account first then names alphabetically.
4. Selecting an account writes its ID to unencrypted `UserDefaults`, subscribes
   to the account/member and broad Items/protoItems/Transactions/Spaces/
   categories/Projects/Invoices collections, then filters some financial data
   in memory.
5. Discovery failure produces an empty account list. Member disappearance does
   not itself define a durable local revocation/removal policy.
6. Account switching removes listeners and clears in-memory contexts. Signout
   directly signs out Firebase after optional UI confirmation; one unused
   placeholder path has no confirmation. Neither path checks pending operations
   or unuploaded media.
7. The root UI distinguishes loss of network and pending/failed media uploads,
   but ordinary Firestore writes do not expose a uniform queued/applied/rejected
   operation receipt.

### MCP/server

1. HTTP access verifies a Firebase token, then uses account membership. One
   OAuth flow resolves only the first membership returned and may fall back to
   an environment account ID.
2. `list_accounts` resolves every membership and `switch_account` verifies the
   requested account before storing the selected account in memory and root
   `mcpUserState/{uid}` Firestore state.
3. Non-request/stdio context can fall through runtime state, environment values,
   and hardcoded production account/user defaults.
4. OAuth authorization codes are short-lived and one-time in Firestore, but
   issued HMAC access/refresh token payloads omit `exp`; the response advertises
   a one-year access lifetime and there is no observed server-side revocation.
5. Admin SDK data access bypasses Firestore rules. MCP financial-access parity is
   incomplete and current authorization is not one shared app/server policy.

## Product and Spec Reconciliation

| Authority | Assessment |
|---|---|
| `client-identity-and-project-transfers.md` | Canonical target Client records remain Account-scoped business entities; they do not replace Ledger Principal, membership, or authorization identity |
| `authentication-offline-access.md` | Previously stale about whether Ledger should work offline. Updated to reflect the confirmed offline-first target while leaving identity provider, offline lease, unlock and recovery policy open |
| `financial-access-controls.md` | Correctly states that UI filtering is insufficient and MCP/server enforcement is required; its legacy Transaction taxonomy is explicitly transitional |
| `offline-first.md` | Governs durable local availability and visible sync state; must be reconciled with the pending-work logout rule |
| Architecture A-007 | Target identity provider/bridge remains open; blocks provider-specific implementation |
| Architecture A-016 | Offline authorization duration/reauthorization remains open; blocks final local unlock/access contract |
| Architecture ports | `IdentitySessionProviding`, `AccountSessionEnding`, `AccountQuerying`, operation state and environment isolation are the approved technical direction, not a Firebase adapter requirement |

No source behavior or old spec text is treated as product authority merely
because it is implemented.

## Behavior Decisions

| Classification | Decision |
|---|---|
| Preserve | A stable Ledger principal; email/password and federated sign-in outcomes unless A-007 changes supported methods; multi-account membership; explicit account choice; role and financial scope; invite-based onboarding; remembered last account as a convenience; visible offline/sync/media state |
| Correct | Server and download authorization must enforce membership/financial scope; account selection cannot use first query result or hardcoded production fallback; tokens require bounded lifetime/revocation semantics; invite/member administration must use authorized commands; routine signout cannot discard pending work; restricted data cannot be downloaded then hidden only in memory |
| Improve | Account discovery becomes one authorized local read model rather than sequential document fetches; account switching becomes an ordered lifecycle operation; provider errors map to stable app errors; mutation receipts expose queued/applied/rejected; session/authority freshness is visible |
| Redesign | Provider/identity migration, offline unlock mechanism, authorization lease, and recovery method depend on A-007/A-016 and product/security approval |
| Retire | Firebase SDK types from domain/application code; generic Firestore listener handles; root `mcpUserState` as independent authorization state; hardcoded UID/account fallbacks; duplicate callable account/invite transports; unused placeholder settings surface |
| Open | Exact offline lease and forced reauth triggers; Google-origin recovery/linking; cross-platform local unlock; destructive logout copy/policy; admin self-limitation rules; Auth migration/identity correlation |

## Target Observable Contract — Backend Neutral

This is sufficient for port/test design but not target schema design:

1. `observeSession` emits a Ledger principal or signed-out state without provider
   types.
2. `watchAuthorizedAccounts` exposes only accounts currently authorized for the
   principal; cached results are labeled by authority/readiness state.
3. Selecting an account requires an ID from that authorized set and atomically
   changes local working scope without mixing prior-account rows or operations.
4. Membership/financial access is enforced before download and at every server
   command/query boundary. Local filtering is UX only.
5. Invite preview reveals only approved minimal fields; create/revoke/accept are
   authorized, idempotent operations with stable results.
6. An offline-capable operation returns a durable receipt and remains observable
   as queued, applied, or rejected across restart and session refresh.
7. Routine logout with pending operations/media does not delete them. The user
   may sync first or explicitly confirm a destructive local removal that shows
   exact pending counts and scope. Account switch cannot upload queued work under
   another account.
8. A disconnected local unlock never implies fresh server authorization. The UI
   exposes stale/limited authority according to the approved lease.
9. MCP explicitly binds each request/session to an authorized account and uses
   the same capability/financial policy and domain operations as the app.
10. Production and staging issuer, account, database, sync and Storage identities
    cannot be mixed at composition or request boundaries.

## Required Tests

### Deterministic contract tests

- persistent session maps to the same Principal ID without SDK leakage;
- zero, one, and multiple authorized accounts; stable explicit selection;
- stale remembered account is not selected after membership loss;
- account switch cancels old observations and prevents row/operation leakage;
- discovery failure distinguishes cached/stale/unavailable from no membership;
- invite preview/create/revoke/accept authorization and idempotency;
- MCP account switch rejects nonmembership and never falls back to another
  account;
- expired/revoked token and stale membership deny server commands;
- limited/no financial access yields no hidden rows, counts, totals, names or
  provenance locally or through MCP; and
- every failure maps to a stable application/domain error.

### Offline and lifecycle tests

- prior authorized user opens approved cached data without network;
- process death preserves queued operation/media and its account/principal;
- routine logout with pending work blocks or offers sync-first;
- destructive removal requires exact-count confirmation and removes database,
  queue, media, signed URLs and keys only after confirmation;
- account switch with pending work follows the approved disposition and never
  uploads into the new account;
- reconnect applies, rejects or conflicts each operation once; and
- authorization expiry/revocation produces the approved limited/locked state
  without corrupting or silently deleting local work.

### Migration/security tests

- Firebase UID/member/account/invite correlation has zero unexplained required
  identities or explicit quarantine decisions;
- target tokens and sessions have bounded expiry/revocation behavior;
- cross-tenant, guessed-account, stale-token and service-credential negative
  tests fail closed; and
- no production identity or data is reachable from isolated staging.

## Dossier Outcome

- **Ready for target-independent mapping:** Principal/session values, explicit
  account selection semantics, pending-work session-ending policy, stable
  operation lifecycle, error taxonomy and contract/failure adapters.
- **Ready for a bounded spike:** local encrypted database/key lifecycle,
  offline unlock/readiness, account-switch isolation and queued-operation
  persistence using synthetic identities/data.
- **Blocked for provider/schema implementation:** A-007, A-016, final product
  copy/policy, and the canonical production Auth/member/data profile.

No Firebase adapter, Supabase table, RLS policy or PowerSync Stream is authorized
by this dossier alone.
