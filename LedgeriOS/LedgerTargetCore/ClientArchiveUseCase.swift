// READY contract scaffold only — no executable behavior.
//
// This leaf will own one provider-free application path from transient,
// non-Codable ClientArchiveIntent to the already verified ClientArchiveOperation
// boundary. Intent carries exactly AccountID, ClientID, and
// ExpectedClientRevision. OperationID, PrincipalID, OperationContractVersion,
// and finite capture time are supplied separately to the application use case.
//
// Implementation is frozen to:
// - construct the existing ClientArchiveDraft and ArchiveClientCommand;
// - call ClientArchiving.archive exactly once after construction succeeds;
// - validate the receipt and preserve its exact localState;
// - preserve CancellationError and normalized ClientArchiveFailure;
// - map any other port error to .localAcceptanceFailed.
//
// This boundary does not inspect Client rows, lifecycle, readiness, Projects,
// accounting history, dependencies, or permissions. It does not implement UI,
// hiding/optimistic projection, physical persistence/restart, authorization,
// authoritative audit, restore/delete/merge/rename/reassignment/cascade,
// provider/schema/RLS/Sync behavior, app/MCP wiring, migration, hosted
// resources, deployment, release, cutover, or production authority.
