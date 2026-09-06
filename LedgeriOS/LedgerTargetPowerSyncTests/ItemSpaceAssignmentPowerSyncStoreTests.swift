// READY scaffold only: executable tests replace this comment only after the
// Item-to-Space local-durability dossier and exact READY commit pass review/CI.
//
// Required proof covers Project and Business Inventory scope, canonical Item
// order, zero/signed-boundary/UInt64.max revision text, exact encrypted restart,
// replay/rebind/tamper/concurrent-same-ID refusal, a pre-database scope sentinel,
// exact negative/fractional finite client-time replay without integer narrowing,
// provider-time truncation, and invalid provider-time refusal,
// every independently tampered/null required field, injected atomic rollback,
// transaction/read/write/watch failure mapping without partial mutation/emission,
// CancellationError passthrough,
// cancellation on both sides of commit, dedicated watch cancellation/drainage,
// runtime close/post-close refusal, exactly-one queued pending-work count, and
// byte-unchanged ps_crud/upload ordering. Static containment must prove there is
// an exact localOnly table/columns/nullability/implicit-ID/index shape and no
// command deletion or repair API. It must also prove there is
// no Item/Space projection, remote apply, authorization, accounting, media,
// Postgres/RLS/Sync/RPC, UI, MCP, Firebase, migration, production, or cutover work.
// Diagnostics must be executable-proof bounded and reveal no IDs, payloads, SQL,
// paths, credentials, or remote-success claims.
