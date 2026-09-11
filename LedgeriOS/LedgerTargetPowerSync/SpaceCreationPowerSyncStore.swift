// DRAFT scaffold only: no executable Space-creation store exists here.
//
// The READY implementation may conform to the already-verified SpaceCreating
// port. Offline acceptance must atomically persist one immutable operation, one
// insert-only create_space command, and one separate local-only pending Space in
// the encrypted Principal/Account database. The pending row carries the exact
// caller SpaceID, immutable Project-or-Business-Inventory scope, canonical name
// and notes, projected active lifecycle/revision 1, and caller-owned capture
// evidence; it never overwrites synchronized spike_spaces authority.
//
// Exact replay is idempotent. FIFO upload, durable rejection, applied-result
// waiting, authoritative readback, restart, membership loss, and runtime close
// must preserve the shared operation lifecycle. The existing destination query
// may merge only valid same-scope optimism and must never call it authoritative.
