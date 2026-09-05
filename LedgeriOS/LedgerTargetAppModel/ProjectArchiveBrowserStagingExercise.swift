// READY scaffold only — no executable application model exists here.
//
// The Core-only model will compose the verified ProjectBrowsingStagingExercise
// evidence and ProjectArchiveUseCase. Submission is admitted only from one exact
// current selected active Project detail presentation, including partial/stale or
// cached content that carries a stable ProjectID and locally observed revision;
// waiting, absent, unavailable, uncached failure, mismatched, stale-selection or
// archived evidence makes zero calls. Local evidence never grants authorization.
//
// An archive request first captures a confirmation bound to exact current Account,
// Project, lifecycle and revision evidence. Cancel makes zero calls. Confirm
// revalidates that the current selection still matches every captured field; a
// changed selection, lifecycle or revision invalidates the confirmation rather
// than retargeting it. Only then does one submission identity contain OperationID
// and finite capturedAt. Simultaneous confirms make one call; an ambiguous local-
// acceptance failure retries byte-identical identity/time/intent; queued success
// cannot duplicate. The model observes its
// exact local operation state, shows bounded queued/applying/applied/rejected
// truth, and after rejection/conflict requires refreshed current active evidence
// plus an explicit retry with a new OperationID/revision. It never auto-retries,
// restores, deletes, renames, reassigns or mutates media.
//
// Operation observation and browser observation have independent bounded errors.
// Selection change, stop and restart cancel/join archive observation; generation
// isolation rejects late cooperative or noncooperative values. The model imports
// LedgerTargetCore only and owns no infrastructure or authorization policy.
