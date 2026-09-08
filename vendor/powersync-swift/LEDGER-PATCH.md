# Ledger PowerSync correction

Upstream: https://github.com/powersync-ja/powersync-swift
Version: 1.16.1
Revision: e6c356aea078dff9cf9cb12b3d1aa3f583ddc98b

Copied upstream Package.swift, LICENSE, Sources, Tests and the manifest-required
CustomCheckpointDemo sources. No generated build products or binary downloads
are vendored. Transitive dependencies retain their existing locked versions.

Only three upstream Swift source files are modified (the attachment README also
has its missing final newline normalized):

- `Sources/PowerSync/Utils/MergeItemSequence.swift`: atomically extract the
  continuation/result, then resume after unlocking; keep cancellation terminal.
- `Sources/PowerSync/Implementation/AsyncConnectionPool.swift`: extract the
  update-log reader before canceling it outside the reader mutex. Also guard
  only `sqlite3_open_v2` against the pinned CSQLite cipher-name shared-buffer
  race; preserve failed-open diagnostics and close allocated failed handles.
- `Sources/PowerSync/Implementation/sync/StreamingSyncClient.swift`: use sorted
  JSON object keys consistently for local subscriptions and streaming requests.
  Unordered dictionary encoding otherwise registers duplicate local stream
  identities on encrypted reopen, losing usable completed-readiness evidence.

CI34173547450 captured the consumer task-status/state-mutex lock inversion during
real failed-bootstrap database cleanup. See architecture decision A-022 and
Ledger's PowerSyncSequenceCancellationTests. The target app consumes the same
local LedgerTarget Swift package as tests, which depends on this local SDK.

Architecture decision A-024 records the separately reproduced concurrent-open
failure (`unknown cipher 'chacha20'`) and the narrow open-only guard. Ledger's
ConcurrentReportDatabaseOpenTests keeps sixteen independent encrypted opens,
schema checks and closes concurrent. Keys, queries and pool lifetimes are not
serialized. Future external CSQLite opens/ATTACH paths need equivalent protection
or an upstream cipher-library fix; the guard covers current Ledger factories.

Architecture decision A-026 records the observed duplicate parameter strings and
the deterministic-encoding fix. PropertyManagementReportPowerSyncQueryTests
exercises repeated SDK subscriptions and encrypted reopen without transport.
This prevents new drift, not recovery of preexisting ambiguous development
metadata; duplicate readiness remains fail-closed. It does not delete local data
or synthesize download completion.

Remove this copy and restore an exact upstream pin once an upstream fix has been
reviewed and passes the cancellation races, concurrent encrypted opening, real
bootstrap cleanup, deterministic stream identity/reopen and full CI.
Do not replace it with an untracked dependency-cache edit or silently refresh
the upstream source. Upstream license is retained in LICENSE.
