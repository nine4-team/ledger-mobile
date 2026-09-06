# EVID-CAPABILITY-IDENTITY-001 — Identity, Account Session, and Operation Lifecycle

- Timestamp: 2026-08-31
- Class: static source/spec characterization and capability synthesis
- Repository baseline: `d83c64724fe4e92be27c62f425979bd30fcfc9bb`
  on `dev`; shared worktree was already dirty
- Production reads or mutations: none
- Target implementation/schema changes: none
- Operator: Codex
- Primary artifact: `capability-dossiers/identity-account-session-and-operation-lifecycle.md`

## Sources Reviewed

- iOS Firebase Auth manager, account/member/invite services and models;
- `AccountContext`, root routing and both settings signout paths;
- account discovery tests and service protocols;
- MCP token verification, OAuth, request context, persistent user state and
  account tools;
- account/create/invite Cloud Functions and current Firestore rule findings;
- media upload durability findings relevant to logout/account switching;
- `authentication-offline-access.md`, `financial-access-controls.md`,
  `offline-first.md`; and
- architecture A-007/A-016 plus identity/session/operation ports.

## Method and Result

Static call-site searches were reconciled with current source implementations,
existing tests, specs, architecture decisions and prior backend/query evidence.
The dossier records current behavior, stale-spec corrections, explicit
preserve/correct/improve/redesign/retire/open decisions, a backend-neutral
observable contract, required tests and named blockers.

The stale authentication spec was updated only where authority is clear: Ledger
is offline-first, Firebase currently persists provider state, current signout
does not inspect pending media, and offline authorization duration/provider
choice remain open. No provider choice or product policy was invented.

## Material Findings

- Current account discovery is cache-first but error collapses to an empty list,
  and account activation subscribes broadly before filtering some sensitive data
  only in memory.
- Current routine signout can abandon pending durable media/operations because
  provider signout is directly callable outside a session-ending coordinator.
- MCP OAuth can bind the first returned membership or an environment fallback;
  stdio context can use hardcoded production account/user defaults.
- MCP token payloads omit expiration/revocation evidence, and Admin SDK access
  does not share one enforced financial-access policy with the app.
- Useful behavior to preserve includes stable principal identity, multi-account
  membership, explicit choice, invites, financial scope and visible offline
  state. Firebase mechanics and defects are explicitly excluded from parity.

## Limitations

Production Auth providers, membership variants/orphans, deployed Function use,
and actual account data remain unconfirmed until the read-only profile runs.
This dossier permits target-independent contract/test mapping and a bounded
synthetic lifecycle spike; it does not authorize Auth provider selection,
Supabase schema/RLS, PowerSync Streams, Firebase adapter work or production
migration.
