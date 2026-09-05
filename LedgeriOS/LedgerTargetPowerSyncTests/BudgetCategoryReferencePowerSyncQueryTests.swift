// READY scaffold only — executable tests begin only after this exact
// synchronized READY checkpoint passes independent review and immutable CI.
//
// The frozen suite will use disposable encrypted PowerSync databases and the
// real adapter. It will insert an exact bound Principal/Account membership and
// unordered active, archived, system, ordinary-class and restricted-class
// category rows, then prove the adapter emits every already-materialized row in
// canonical presentation order without making a visibility decision.
//
// Tests will prove exact Account binding before observation, active local
// membership as a non-authoritative scope sentinel, visible count equal to
// emitted rows only, stable query identity, content-bound LocalDataVersion and
// reactive database updates. Cross-Account calls, invalid
// kind/lifecycle/boolean/order/revision/name, duplicate identity/name/order and
// raw database failure must yield no partial snapshot and only bounded
// failures. Missing/inactive/cross-Principal membership instead emits an empty
// incomplete snapshot that cannot be treated as authoritative absence.
//
// The same live iterator must prove scope revocation is reactive: after a ready
// nonempty emission with explicit completeness still true, changing the active
// membership to inactive/revoked and then deleting it immediately emits an
// empty partial snapshot with isCompleteForQuery false. Previously emitted rows
// cannot remain visible, and stale completeness events cannot re-promote either
// transition to ready or authoritative empty.
//
// A separately controlled completeness stream must prove that cached rows and
// PowerSync hasSynced/lastSyncedAt never produce ready evidence on their own;
// false completeness yields partial or stale, explicit current-process true
// plus active membership yields ready, and only that state may represent an
// authoritative empty local subset. Close/reopen resets completeness until new
// evidence is supplied.
//
// Runtime integration tests will prove exactly one query is constructed, the
// public facade binds Account implicitly, category watches share the existing
// close-aware stream lease, close cancels and drains an active watch before
// either database closes, concurrent close rejects new watches, and post-close
// access refuses. Consumer cancellation must drain both database and
// completeness observations without leaking the concrete provider or database.
//
// A reciprocal field/version matrix independently varies Account ID, category
// ID, name, all three kinds, both lifecycles, both system/exclusion booleans,
// presentation order, revision, canonical row membership, scope sentinel,
// completeness and quality. Each literal output field must come from its own
// source column; every content/readiness-axis change must change
// LocalDataVersion, while SQL input order alone must not. QueryFingerprint must
// remain stable across rows/readiness for one Account and change for another.
//
// Existing schema, RLS and Sync tests remain regression dependencies but no
// test may claim final O-026 visibility policy, current hosted authorization,
// successful synchronization, category administration, app/MCP behavior,
// source-backend migration, production access, or cutover.
//
// Shared executable edits are limited to the exact pre-implementation manifest
// tuples frozen by the provider scaffold: SWIFT-548A8A928FAE,
// SWIFT-75CFE285AF37, TEST-8D6A15063B2D, and both target-environment aliases
// CONFIG-81235587F306 / FILE-A6E49E3815F4 at their recorded READY hashes.
