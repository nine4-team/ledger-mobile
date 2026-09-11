# EVID-CLIENT-CREATION-PROVIDER-001 — Client Creation Supabase/PowerSync Slice

- Timestamp: 2026-09-04
- Class: local implementation evidence / Client creation provider slice
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the Firebase worktree and released app remain unchanged
- Target branch: `codex/supabase-powersync-implementation`
- Slice dossier:
  `conversion/implementation-slices/client-creation-supabase-powersync-vertical-spike.json`
- Implementation introduced: `df423c1603ac6c1d3f45892d0856d5253995269e`
- Cumulative immutable verification: Project-provider checkpoint
  `e57b874d4c75f7f833f77221df794cafa0c0d72c` / Actions run `33894323498`

## Proven Local Behavior

The isolated target can accept one ordinary-name Client creation while offline,
atomically persist its operation, optimistic Client and upload command in an
encrypted per-Principal/Account PowerSync database, render it as partial across
restart, upload the canonical command through a scoped-user RPC, apply it in a
trusted Postgres transaction, and reconcile the overlay after authoritative
readback. Exact OperationID replay is idempotent, changed replay refuses,
cross-Account access is hidden, restricted mutation and direct table writes are
denied, and app/MCP ordinary-name command bytes and fingerprints match.

The cumulative immutable run includes the Client pgTAP and local Data API/RLS
checks, nine Client PowerSync tests, five Client MCP tests, strict TypeScript,
all target Swift tests, generated contracts, conversion controls and both
staging builds. Later exact run `33902466636` also passed the same Client
provider checks while verifying attachment durability.

## O-043 Correction

This evidence does **not** prove a final Client display-name submission rule.
The current Swift, JavaScript and PostgreSQL validators disagree on whitespace,
controls, NUL and size; the current stored/read value also shares the submission
type. The ordinary-name fixture proves transport/fingerprint parity only. Until
O-043 is approved and its shared vectors pass, this slice cannot be promoted and
must not claim:

- cross-runtime Client-name acceptance parity;
- bounded Client-name indexability;
- rejection before local Operation/overlay creation; or
- a durable terminal result for every invalid name a current client can accept.

The stable identity, Account scoping, replay, RLS, encrypted offline queue and
authoritative readback mechanics remain valid and reusable. O-043 affects
Client creation and the new-Client Project-setup branch, not existing-Client
Project setup.

## Open Gates

- O-043 approval and exact Swift/MCP/Postgres/migration validation fixtures;
- a distinct new-submission conversion versus lossless stored/imported read
  representation;
- real isolated hosted Auth and PowerSync upload/readback;
- permanent-authorization-loss queue policy; and
- migration, production and cutover authorization.

No Firebase implementation, production data, hosted target resource, migration,
deployment, release or cutover was changed or used.
