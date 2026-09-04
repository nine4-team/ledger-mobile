# EVID-ATTACHMENT-DURABILITY-PROVIDER-001 — Attachment Local Durability Provider


- Timestamp: 2026-09-04
- Class: local implementation evidence / protected attachment-byte durability
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the Firebase worktree and released app remain unchanged
- Target branch: `codex/supabase-powersync-implementation`
- Slice dossier:
  `conversion/implementation-slices/attachment-local-byte-durability-provider.json`
- Verification state: implementation and deterministic local verification pass;
  immutable exact-commit CI and physical/hosted media rehearsal remain pending

## Outcome

The isolated target can now accept captured attachment bytes without a network
and return the existing backend-neutral durability receipt only after encrypted
bytes and exact queue evidence are durable and independently reverified. Raw
bytes remain outside structured PowerSync rows, `ps_crud`, the shared runtime
schema, remote upload handling, and Sync Streams.

The provider uses an isolated SQLCipher PowerSync database physically bound to
one validated environment, Principal, Account, and local-data namespace. Its
local-only queue retains exact pending, missing, or corrupt evidence. The byte
vault uses a distinct injected 256-bit media key, AES-GCM authenticated metadata,
opaque scoped object names, directory-descriptor-relative file operations,
exclusive promotion, bounded reads, platform protection/backup exclusion, and
a staging/final orphan inventory. It exposes no delete, discard, eviction,
cleanup, remote-success, or retention action while O-023 remains open.

## Local Verification

- `swift test --package-path LedgeriOS --filter AttachmentDurabilityProviderTests`
  passes all 10 attachment tests.
- `npm run target:powersync:test` passes 19 tests across the Client and
  attachment suites; the attachment type name is deliberately selected by the
  real `LedgerPowerSync` CI filter.
- Tests cover restart recovery, every injected staging/queue interruption,
  missing and truncated ciphertext, an intact ciphertext under the wrong key,
  count/digest/NULL metadata mutation, exact and changed concurrent replay,
  scope-database rebinding refusal, mutated scope-column visibility, SQLCipher
  raw-file marker absence, empty `ps_crud`, shared-schema absence, hardlink and
  symlink rejection, invalid namespace/object identities, repeated orphan
  inventories, stable pending order, and non-consuming verified reads.
- `git diff --check` passes.

## Independent Review Corrections

The first independent review rejected the initial green candidate and the root
corrected all cited proof and implementation gaps:

- path-based initialization and promotion were replaced with no-follow
  directory descriptors plus `openat`, atomic exclusive `renameatx_np`,
  `fstatat`, descriptor-relative enumeration, and descriptor `fsync` for
  byte-bearing operations;
- newly created root and nested directory entries are synchronized through
  their parent descriptors before a capture can be accepted;
- ciphertext size is checked before allocation and reads are bounded;
- the encrypted local database is bound to one exact validated scope so mutable
  row scope columns cannot hide accepted work or expose it to a forged scope;
- wrong-key, truncation, independent count/digest/NULL mutation, and concurrent
  changed-payload, parent, and capture-time rebinding cases now execute rather
  than being implied;
- the normal PowerSync CI filter now includes the attachment suite;
- raw SQLCipher evidence checks known inserted metadata markers, not only bytes;
  and
- deterministic checkpoint tests no longer claim to be physical ENOSPC,
  permission, process-kill, or power-loss evidence.

## Explicit Open Gates

- Immutable CI on the synchronized implementation commit is still required
  before promotion from `implemented` to `verified`.
- A-003/A-004 remain proposed. This does not prove a hosted PowerSync stream,
  Supabase Storage policy, Auth strategy, upload completion, physical-device
  data protection, low-storage handling, process-kill/power-loss durability, or
  the seven-day media soak required by SPIKE-MED-001.
- O-023 still owns retention, detach, delete, discard, cleanup, and logout
  behavior. None is implemented or inferred here.

No Firebase implementation, source data, hosted target resource, production
credential, migration, deployment, release, or cutover was changed or used.
Concurrent mutation of the app-private root path by a process that has already
bypassed the operating-system sandbox remains outside this deterministic local
proof; byte creation, promotion, reads, and orphan enumeration remain pinned to
the opened directory descriptors and fail closed if path-based platform
protection metadata can no longer be applied.
