// DRAFT scaffold only — executable Client rename storage requires O-042/O-043
// approval and a later synchronized READY review.
//
// This leaf will implement ClientRenaming over the encrypted Account-scoped
// PowerSync database. Local acceptance must atomically persist one immutable
// operation, one insert-only rename command and one separate local-only rename
// overlay. It must not mutate a synchronized spike_clients row optimistically.
//
// The overlay/command schema and reconciliation rules are frozen by the slice
// dossier: exact UInt64 revisions are decimal text at transport/local-command
// boundaries; an effective signed-bigint-maximum Client refuses before local
// mutation and an expected revision above that range cannot match local authority;
// pending-create then rename dispatches FIFO; successive offline renames chain
// N->N+1->N+2 from the latest effective local revision; a second stale N command
// is refused; rejection removes only its exact overlay; applied optimism remains
// until authoritative readback; and cleanup is permitted only for a matching
// locally applied operation when authority is newer than the projection, or when
// authority has the same projected revision and exact name. Exact replay must be
// resolved before latest-effective-revision validation so a prior operation can
// replay after a later chained overlay without a false stale refusal.
