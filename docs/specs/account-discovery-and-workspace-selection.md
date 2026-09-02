# Account Discovery and Workspace Selection

Status: [new — canonical target]
Last updated: 2026-09-02

## Purpose

Ledger users and MCP clients may belong to zero, one, or many Accounts. After
Ledger has established a stable Principal, the application must show only the
Account summaries available to that Principal and require an explicit Account
choice before establishing a working scope.

This spec owns the provider-independent discovery and selection-intent
contract. It does not choose an identity provider, define the offline-access
lease, grant membership, or activate an Account database.

## Authorized Account Discovery

- The discovery snapshot is bound to exactly one compiled target environment
  and one stable Ledger Principal.
- Each row contains a stable Account ID and visibility-safe nonblank display
  name. Role, financial permission, Auth subject, invite data, logo bytes,
  attachment references, tokens, and provider metadata are outside this
  summary.
- Stable Account ID is identity. Duplicate display names are valid and remain
  distinct; duplicate Account IDs are invalid.
- The local snapshot reports whether it is complete and whether its data is
  ready, partial, or stale, together with a stable local-data version and
  finite observation time. “Authorized” describes the last synchronized
  membership projection represented by that snapshot; it is not a claim of
  fresh server authorization.
- A complete ready snapshot containing zero rows means the Principal has no
  visible Account membership in that projection. Loading, partial, stale,
  unavailable, and failed discovery must not be presented as the same state as
  authoritative empty.
- Account rows have deterministic presentation order. An available remembered
  Account may be placed first as a convenience; a missing remembered ID is
  ignored. Remaining rows sort by normalized display value and stable Account
  ID so equal names remain deterministic.

## Explicit Workspace Selection

- Zero, one, and multiple Account results all require an explicit selection.
  Discovery, ordering, and remembered state never create a selection intent by
  themselves.
- A selection intent may name only an Account ID present in the exact
  environment-, Principal-, and snapshot-version-bound list the caller was
  shown. Unknown, removed, cross-environment, cross-Principal, or changed-list
  selection evidence fails closed through one non-enumerating unavailable
  outcome.
- The intent records local workspace choice only. It is not a server command,
  an authorization claim, a membership mutation, or a server-side “active
  account” record.
- Before opening protected local data or issuing a server query/command, a
  later workspace-activation coordinator must independently enforce the
  approved authorization-freshness/offline-lease policy and current server
  membership when online.
- App and MCP may share this selection contract, but MCP selection remains
  bounded request/session context. Ledger does not recreate root
  `mcpUserState`, hardcoded Account fallbacks, or first-membership selection.

## Remembered Selection

Remembering the last selected Account is optional convenience state scoped to
the exact environment and Principal. It may affect ordering only while that ID
is present in the current visible snapshot. It never grants access, bypasses
explicit choice, or survives as independent authorization after membership
loss.

## Failure and Privacy Contract

- Public failures use stable bounded Ledger codes and do not reveal whether an
  arbitrary Account ID exists.
- A discovery failure may retain a clearly labeled partial or stale cached
  snapshot, but it must not fabricate a complete empty result.
- Malformed names, duplicate identities, invalid times, invalid local-read
  evidence, scope rebinding, snapshot tampering, and unlisted selection fail
  atomically.
- This contract contains no provider object, credential, service endpoint,
  database path, Storage path, membership secret, financial value, or source
  Firebase DTO.

## Deliberate Non-Goals and Open Gates

This contract does not decide or implement:

- A-007 identity-provider selection or issuer/subject correlation;
- A-016 offline authorization duration, local unlock, or revocation policy;
- membership, role, financial-access, invite, or Account-creation operations;
- Account-logo attachment behavior or O-023 retention;
- encrypted database/key lifecycle, stream startup/shutdown, pending-work
  disposition during an actual Account switch, or physical offline behavior;
- Postgres schema, RLS, PowerSync Sync Streams, Supabase/Auth adapters, app UI,
  MCP transport, Firebase migration, hosted resources, production access, or
  cutover.

## Acceptance Examples

- Complete ready zero/one/many snapshots remain distinguishable and restart
  with the same environment, Principal, Account identities, readiness, version,
  time, and deterministic order.
- Equal display names are allowed and ordered by stable Account ID.
- A remembered Account that remains visible sorts first but is not selected.
- A stale remembered Account disappears without being activated or revealing
  whether the Account still exists.
- Explicit selection of a visible Account produces one exact scoped intent;
  unknown, rebound, or changed-snapshot selection produces only the bounded
  unavailable result.
- Provider/query failure never becomes a false authoritative-empty snapshot or
  a successful selection.

