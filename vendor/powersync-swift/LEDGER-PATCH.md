# Ledger PowerSync correction

Upstream: https://github.com/powersync-ja/powersync-swift
Version: 1.16.1
Revision: e6c356aea078dff9cf9cb12b3d1aa3f583ddc98b

Copied upstream Package.swift, LICENSE, Sources, Tests and the manifest-required
CustomCheckpointDemo sources. No generated build products or binary downloads
are vendored. Transitive dependencies retain their existing locked versions.

Only two upstream Swift source files are modified (the attachment README also
has its missing final newline normalized):

- `Sources/PowerSync/Utils/MergeItemSequence.swift`: atomically extract the
  continuation/result, then resume after unlocking; keep cancellation terminal.
- `Sources/PowerSync/Implementation/AsyncConnectionPool.swift`: extract the
  update-log reader before canceling it outside the reader mutex.

CI34173547450 captured the consumer task-status/state-mutex lock inversion during
real failed-bootstrap database cleanup. See architecture decision A-022 and
Ledger's PowerSyncSequenceCancellationTests. The target app consumes the same
local LedgerTarget Swift package as tests, which depends on this local SDK.

Remove this copy and restore an exact upstream pin once an upstream fix has been
reviewed and passes the cancellation races, real bootstrap cleanup and full CI.
Do not replace it with an untracked dependency-cache edit or silently refresh
the upstream source. Upstream license is retained in LICENSE.
