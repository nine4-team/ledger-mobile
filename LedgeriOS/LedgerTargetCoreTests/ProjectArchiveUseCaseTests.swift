// READY verification scaffold only — no executable tests.
//
// The implementation candidate must add reciprocal, provider-free tests that:
// - prove ProjectArchiveIntent contains exactly AccountID, ProjectID, and
//   ExpectedProjectRevision, is non-Codable, and accepts revision zero/max;
// - independently vary every intent and caller metadata field and prove the
//   exact existing draft/command, subject, precondition, and fingerprint;
// - prove one and only one ProjectArchiving call after valid construction;
// - prove invalid non-finite capture time makes zero port calls;
// - preserve every matching OperationReceipt.localState exactly and reject a
//   mismatched receipt without manufacturing success wording;
// - preserve CancellationError, preserve a normalized ProjectArchiveFailure
//   distinct from the fallback, and map a raw port error to
//   ProjectArchiveFailure.localAcceptanceFailed;
// - prove bounded diagnostics and the authorized command shape expose no raw
//   provider error, credential/path, lifecycle toggle, Client, child,
//   accounting, restore, unarchive, or delete field.
//
// These tests must not claim read/readiness, archive eligibility, physical
// durability/history preservation, authoritative apply, UI, provider,
// schema/RLS/Sync, app/MCP, migration, deployment, release, or production.
