// READY scaffold only — no executable Project archive store exists here.
//
// The implementation will conform to ProjectArchiving behind the existing
// Account-bound runtime. Offline acceptance must atomically persist immutable
// local operation evidence, one insert-only archive command and one separate
// local-only lifecycle overlay; it must never rewrite synchronized Project rows.
// The overlay must bind exact Account/Project/Operation/fingerprint, expected and
// projected revision, archived lifecycle and finite local acceptance time.
//
// It must resolve exact replay before current-effective-revision validation,
// support pending Project creation followed by archive in FIFO order, reject a
// stale/already-archived/out-of-range local base before mutation, survive an
// encrypted close/reopen, and drive existing Project directory/detail reads to
// an immediate partial Active-to-Archived projection. Durable rejection removes
// only the exact overlay and exposes refreshed current evidence for a new-ID
// retry; applied optimism remains until matching applied evidence plus archived
// authoritative readback at the projected revision, or newer authoritative
// revision, permits cleanup. Stale readback cannot clear or resurrect optimism.
//
// Archive changes no Client relationship, Project display/details/creation audit,
// category/allocation, note, attachment/media, Item, Space, Transaction, Invoice
// or accounting/history evidence. Restore/delete/rename/reassign/media mutation
// and a second operation lifecycle are prohibited.
