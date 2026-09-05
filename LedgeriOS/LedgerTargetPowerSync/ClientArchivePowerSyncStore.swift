// READY scaffold only — no executable Client archive store exists here.
//
// The implementation will conform to ClientArchiving behind the existing Account-
// bound runtime. Offline acceptance must atomically persist immutable operation
// evidence, one insert-only archive command and one separate local-only Client
// lifecycle overlay; it must never rewrite synchronized Client rows. The overlay
// binds exact Account/Client/Operation/fingerprint, expected/projected revision,
// archived lifecycle and finite local acceptance time.
//
// It must validate `client-archive-<account-digest>-<uuid>` through the shared
// generic identity primitive, resolve exact replay before current-effective-
// revision validation, and admit only a locally represented active Client at the
// exact expected revision. Earlier accepted Client creation and Project setup
// commands referencing that Client stay ahead of archive while queued/applying.
// Rejected Client creation unblocks archive for trusted missing/non-active
// disposition and must not retry forever; its overlay remains until authoritative
// terminal archive evidence removes it. Rejected Project setup no longer blocks
// archive because it created no Project to preserve. Applied prior Project setup remains preserved.
// After archive optimism, Project Setup acceptance must reject stale or current
// new/unaccepted attempts to attach a Project to the effectively archived Client.
// Exact replay of a Project-setup OperationID accepted before archive must resolve
// to its prior receipt before effective-lifecycle validation.
//
// The overlay survives encrypted close/reopen and drives every shared Client
// directory/detail consumer to immediate partial Active-to-Archived evidence.
// Transient failure retains work. Durable rejection removes only the exact
// overlay; applied optimism remains until matching applied evidence plus archived
// authoritative readback at projected revision, or newer authority, permits
// cleanup. Stale readback cannot clear or resurrect optimism.
//
// Archive changes no Client identity/name/creation audit, Project row/ownership,
// currently represented related/history evidence. The SQL mutation boundary must
// stay no-cascade/no-related-write as later tables arrive, with a new preservation
// regression for every added table. Restore/delete/rename/merge/reassignment/cascade/media mutation and a
// second operation lifecycle are prohibited.
