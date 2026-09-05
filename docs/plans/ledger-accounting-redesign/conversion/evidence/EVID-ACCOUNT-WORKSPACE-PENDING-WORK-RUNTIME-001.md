# EVID-ACCOUNT-WORKSPACE-PENDING-WORK-RUNTIME-001 — Account Workspace Pending-Work Runtime

- Status: independently reviewed READY; comments only; executable work prohibited until exact READY CI passes
- Date: 2026-09-04
- Environment: isolated target worktree and disposable local fixtures only
- Production/Firebase impact: none
- Slice: `account-workspace-pending-work-runtime`

## Outcome

This package freezes one bounded technical-control slice: normal Account-workspace
bootstrap will own exactly one verified pending-work query plus one separate
encrypted attachment queue, one protected byte vault and one attachment-capture
store. The composed runtime will expose attachment capture and a fresh pending
summary while ordinary close preserves all databases, bytes and keys.

The package contains no executable runtime composition yet. Only the two new
primary leaves contain comments. Shared implementation surfaces remain
byte-identical until the exact synchronized READY checkpoint passes independent
review and immutable CI.

## Why This Slice Is Next

The pending-work provider is already implemented and verified, but it is not
owned by the runtime users actually open. Its attachment evidence currently has
to be assembled manually in tests. That gap means a future session-ending
coordinator cannot yet obtain one trustworthy summary from the exact stores
accepting the user's offline work.

This slice closes only that composition and lifecycle gap. It does not implement
logout or Account removal. Those later behaviors remain separately gated and
must consume this runtime's evidence without receiving deletion or signout
authority from it.

## Frozen Contract

- Derive distinct opaque contained structured-database, attachment-database and
  media-vault locations from the same validated environment, Principal and
  Account scope before any storage opens.
- Keep the attachment queue in a separate local-only encrypted SQLite database.
  Both SQLite factories receive the exact same workspace SQLCipher key.
- Load or create a separate 32-byte media-encryption key under a distinct
  Keychain identity; its bytes must differ from the SQLCipher key or bootstrap
  refuses before opening storage.
- Construct exactly one `AttachmentLocalByteVault`, one
  `AttachmentCapturePowerSyncStore` and one `PendingWorkPowerSyncQuery` for the
  runtime. Injected factory counters prove one construction each and raw
  database/query/store/vault references cannot escape.
- Make normal and test bootstrap asynchronous. After validated derivation and
  key checks, open structured database, attachment database, then vault. A later
  failure releases any vault and attempts attachment-then-structured database
  close, reporting the primary stage and both bounded cleanup outcomes without
  deleting a database, protected byte or key.
- One `open`/`closing`/terminal-`closed` lease gate covers every existing
  Client/Project mutation, list/detail watch, diagnostic read, capture and fresh
  summary. Close rejects new work, cancels and drains tracked streams, then
  drains finite calls.
- After drainage, close attempts attachment database then structured database
  even if the first fails, releases query/store/vault/database ownership and
  stores one terminal success or bounded two-database failure. Repeated close
  returns exactly that stored outcome and never retries resource access; every
  other post-close call refuses.
- Ordinary close preserves all local evidence. A newly opened runtime for the
  identical scope recovers the same pending evidence.
- Failures remain typed and bounded and never turn unavailable, corrupt,
  orphaned or mismatched evidence into an all-zero summary.

## Frozen Verification

The executable suite must use real encrypted stores to prove:

- clean and all four pending-work classes;
- exactly one lifecycle owner, structured-database factory,
  attachment-database factory, query, store and vault construction with no raw
  database/query/store/vault/key/path escape, plus attachment acceptance through
  the gated runtime port;
- unchanged summary evidence and protected bytes across ordinary close/reopen;
- equal-count evidence replacement advances summary revision;
- every environment, persistence binding, Principal and Account dimension
  isolates database, vault and Keychain identities;
- both database factories receive identical SQLCipher bytes, media receives
  different bytes, equal injected values refuse before open, and independently
  wrong structured-database, attachment-database and media keys refuse;
- invalid scope refuses before storage opens;
- missing, corrupt, orphaned and unavailable attachment evidence fails closed;
- every async bootstrap-stage failure preserves recoverable state, releases the
  vault and attempts both database closes in fixed order;
- Client/Project mutation, list/detail watch, diagnostic-read, capture, summary
  and close interleavings never use a released resource or lose accepted work;
- dual close failure still attempts both closes, releases ownership, stores one
  terminal result and makes repeated close deterministic; and
- the public surface contains no destructive cleanup, synchronization,
  provider signout, workspace switch, backend selection or
  `AccountSessionEnding` conformance.

## Exact READY Hashes

Primary comment-only leaves:

- `LedgeriOS/LedgerTargetPowerSync/AccountWorkspacePendingWorkRuntime.swift` —
  `82dfbbfc0c06fbebfa79772f743df9251c7e5b6a4f4d95c4036c34549d5779ba`
- `LedgeriOS/LedgerTargetPowerSyncTests/AccountWorkspacePendingWorkRuntimeTests.swift` —
  `c0329cbe6612853c777405b553a8526b9e5be690af4e8f1c80c9a1b7f41d7133`

Expected affected/shared implementation surfaces, frozen at READY:

- `LedgerOfflineClientRuntime.swift` —
  `ff86a0126707ff116529582644e93c91c938fd4c4a1ac4261f1264ef919ad565`
- `LedgerWorkspaceRuntimeIsolation.swift` —
  `bf6add0067554cea32f839a5a4e6b5ba25dad79462a491a85d37704cd6d61846`
- `LedgerPowerSyncKeychain.swift` —
  `2bc574009ea52d64053c9cd58888395bab8de1bdfa67c9f002f65067f5b2bd80`
- `LedgerWorkspaceRuntimeIsolationTests.swift` —
  `765099c482cdce38e9bedd4e15e193c0142988d32c82cbdde855e0612b800d8c`
- `LedgerTargetStagingApp.swift` —
  `8252ab4867633b994ab6d89b2aaca68111256bb486188abe673ad1c10edddfed`
- `ClientProjectDirectoryPowerSyncQueryTests.swift` —
  `df7189029ceefcf3fa0a630bf2ffd0de5fc1f4d1d7c50a66690495c5c0c2927b`
- `scripts/check-target-environment.mjs` —
  `299220043f59cdaee6c4c3022631cf009a258eae0e6feeb6bb5f594eb626f5fd`

Verified dependencies whose primary ownership remains unchanged:

- `PendingWorkPowerSyncQuery.swift` —
  `036ea69b475795f04ce5820f4884969cd02461948a9ac40e9ac13f86d3d11bf1`
- `AttachmentCapturePowerSyncStore.swift` —
  `349110050cd2ed4b8b8fbca8393ab8e13599e79ce5d523f9e200725e20458850`
- `AttachmentLocalByteVault.swift` —
  `9581e01d5087e2fa39f12906c8022bf5e5db21e076a16db454bf4340c4829dcb`
- `PendingWorkPowerSyncQueryTests.swift` —
  `31edc5a70e6711b69ae36746ab9409815c8af547351a689f64cf5da6b01b801f`
- `AttachmentDurabilityProviderTests.swift` —
  `c4964bc23dd67aebf6e9eb6425f668ebfb3aa7f103db6237759405aae27185d1`

Any executable change before the synchronized READY commit and immutable CI
pass invalidates this checkpoint.

## Independent READY Review

The initial review returned NO-GO. The corrected candidate now:

- replaces the stale durable next action that would have repeated completed
  workspace-isolation and pending-provider work;
- freezes asynchronous construction and every partial-open cleanup outcome;
- gates all existing finite runtime calls and list/detail streams, not only
  attachment capture and pending summary;
- separates canonical pending-summary outcomes from technical composition and
  key-design authority;
- defines exact open/closing/terminal-closed behavior, close order, dual-failure
  handling, ownership release and repeated-close results;
- requires value-level SQLCipher/media-key separation and independent wrong-key
  cases; and
- adds executable construction-count for both database factories and every
  composed dependency, complete non-escape/forbidden-API checks, plus
  exact hashes for every currently known constructor/call-site surface.

The final corrected-diff review returned GO with no P0-P3 finding. It confirmed
all fourteen recorded primary/shared/dependency hashes, both comment-only
leaves, reciprocal verification, complete known call sites and the hard
boundary. Conversion checking and `git diff --check` also passed independently.

## Hard Boundary

This runtime is not `AccountSessionEnding`. It cannot synchronize or resolve an
operation, verify an upload, sign out a provider, switch an Account, delete or
clean a queue/database/key/file, choose retention, access hosted services,
migrate Firebase state or authorize production cutover.

A-003 and A-004 remain proposed. A-007, A-016 and O-023 remain unadvanced. The
Supabase architecture remains a target implementation direction, not production
migration authorization.
