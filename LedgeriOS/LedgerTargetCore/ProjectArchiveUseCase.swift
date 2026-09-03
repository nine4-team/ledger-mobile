// READY contract scaffold only — no executable behavior.
//
// This leaf will own one provider-free application path from a transient,
// non-Codable `ProjectArchiveIntent` to the already verified
// `ProjectArchiveOperation` boundary. The intent carries exactly AccountID,
// ProjectID, and ExpectedProjectRevision. Caller-supplied OperationID,
// PrincipalID, OperationContractVersion, and finite capture time are added only
// by the application use case.
//
// Implementation is frozen to:
// - construct the existing ProjectArchiveDraft and ArchiveProjectCommand;
// - call ProjectArchiving exactly once, and only after construction succeeds;
// - validate the returned receipt and preserve its exact localState;
// - preserve CancellationError and normalized ProjectArchiveFailure values;
// - normalize any other port error to .localAcceptanceFailed.
//
// This boundary does not own Project reads/readiness, lifecycle eligibility,
// already-archived/no-op policy, confirmation/dismissal UI, restore/unarchive,
// physical deletion or history preservation, child/accounting mutation,
// persistence, provider/schema/RLS/Sync behavior, app/MCP wiring, migration,
// deployment, release, or production authority.
