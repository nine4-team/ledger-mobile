# EVID-SOURCE-BACKEND-001 — Current Firebase Backend Boundary

- Timestamp: 2026-08-31
- Class: source characterization
- Repository baseline: `d83c64724fe4e92be27c62f425979bd30fcfc9bb`
  on `dev`; shared worktree was already dirty
- Environment: local source inspection only
- Production export: not selected; no production reads or mutations performed
- Target environment: not applicable
- Operator: Codex
- Primary artifact: [Current Firebase Backend Contract](../current-backend-contract.md)

## Sources Reviewed

- `firebase/firestore.rules`
- `firebase/firestore.test.rules`
- `firebase/firestore.indexes.json`
- `firebase/storage.rules`
- `firebase/functions/src/index.ts`
- all helper modules in `firebase/functions/src`
- Firebase-related iOS Auth, account, invite, media, repository, and upload
  services and their call sites
- MCP Firebase initialization, Auth, OAuth, Storage, image, query, deletion,
  and account-resolution modules
- Firebase rules tests and media/thumbnail tests
- migration/audit/repair source queries used to reveal server-only and
  collection-group access
- current Firebase README and relevant data/offline/security specifications

## Method

1. Enumerated production rule match paths and compared them with test rules.
2. Enumerated exported Cloud Functions, trigger paths, Admin SDK reads/writes,
   dynamic collection paths, and derived side effects.
3. Traced app Auth/account/invite flows and membership-based account discovery.
4. Traced iOS and MCP media paths, URL variants, thumbnail policy, deletion
   ownership checks, and restart-durable pending upload handling.
5. Reconciled declared rule paths with app, MCP, Functions, migration, and audit
   access to identify paths not protected by ordinary client rules.
6. Searched for call sites before labeling starter/duplicate Functions as
   apparently unused. Production usage remains subject to log/data confirmation.

## Commands

The review used deterministic read-only source searches and extraction,
including:

```bash
rg -n '^export const|onDocument|onCall|onRequest|db\.(doc|collection)' firebase/functions/src
rg -n 'collection\(|document\(|accountCollection\(|FirestoreRepository<' LedgeriOS/LedgeriOS mcp-server/src
rg -n 'createWithQuota|transactionRepricingEvents|transactionDeletionTombstones|_mcp_auth_codes' .
node scripts/supabase-conversion-ledger.mjs sync
node scripts/supabase-conversion-ledger.mjs check
```

## Results

- Every production Firestore rule match surface received a reviewed M0
  disposition and current-behavior description.
- All 18 exported Cloud Functions and five Function modules received reviewed
  M0 characterization.
- Core Auth/account/invite/MCP OAuth and Storage/media/upload-queue surfaces
  received reviewed M0 characterization.
- Server-only paths were added to the explicit contract:
  `transactionRepricingEvents`, `transactionDeletionTombstones`, and
  `_mcp_auth_codes`, plus starter/dynamic quota paths.
- Static review found no active custom-claim authorization.

Material risks recorded in the contract include globally open Storage, Admin
SDK bypass boundaries, account-ID Functions without membership checks,
non-expiring MCP JWT payloads, member-wide invite writes, async derived-state
failure, and production/test rule drift.

## Limitations

This evidence proves static-source characterization only. It does not prove
production collection existence/counts, actual Function invocation frequency,
deployed rule/config parity, Storage object coverage, Auth user/provider shape,
query/index usage, or absence of data written by removed code. Those items
remain blocked pending a versioned read-only production profile.
