// READY verification scaffold only — no executable tests.
//
// The implementation candidate must add reciprocal provider-free tests that:
// - prove ClientArchiveIntent contains exactly AccountID, ClientID, and
//   ExpectedClientRevision, is non-Codable, and accepts revision zero/UInt64.max;
// - vary every intent/caller field independently and prove its exact owning
//   ClientArchiveDraft/ArchiveClientCommand field and derived evidence;
// - prove exactly one ClientArchiving.archive call after valid construction and
//   zero calls after non-finite capture time;
// - preserve every matching OperationReceipt.localState and reject mismatch;
// - preserve CancellationError and normalized ClientArchiveFailure while
//   mapping a raw port error to .localAcceptanceFailed;
// - prove exact command shape and bounded diagnostics exclude lifecycle Boolean,
//   delete/restore/merge/rename, Project list/cascade, accounting/history
//   mutation, UI state, provider details, credentials, and production identity.
//
// Tests must not claim Client lookup/lifecycle eligibility, physical durability,
// actual hiding/projection, authorization, dependency/history preservation,
// authoritative audit, schema/RLS/Sync, app/MCP, migration, hosted resources,
// deployment, release, cutover, or production behavior.
