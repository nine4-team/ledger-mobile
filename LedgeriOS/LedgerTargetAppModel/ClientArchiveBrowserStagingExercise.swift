// READY scaffold only — no executable application model exists here.
//
// The Core-only model will compose ClientBrowsingStagingExercise evidence with
// ClientArchiveUseCase. Submission is admitted only from one exact currently
// observed active Client detail and its revision. Represented partial/stale or
// cached content may remain usable offline; waiting, absent, unavailable,
// uncached, archived, mismatched or stale-selection evidence makes zero calls.
// Local evidence never grants authorization, and this slice defines no general
// already-archived resubmission or no-op product policy.
//
// One explicit archive action binds a stable submission identity, finite capture
// time and exact Account/Client/revision evidence. Simultaneous submission makes
// one call; ambiguous local-acceptance retry reuses byte-identical evidence;
// queued success cannot duplicate. The model observes its exact local operation
// state and exposes bounded queued/applying/applied/rejected truth. A durable
// rejection removes only matching optimism and requires refreshed current active
// evidence plus a new OperationID for any explicit retry. It never restores,
// deletes, renames, merges, reassigns, cascades or mutates media/history.
//
// Client archive optimism must flow through the shared Client directory so every
// consumer, including Project Setup, immediately stops offering the Client for a
// new Project. Selection change, stop and restart cancel/join archive observation;
// generation isolation rejects late cooperative or noncooperative values. The
// model imports LedgerTargetCore only and owns no infrastructure or authorization.
