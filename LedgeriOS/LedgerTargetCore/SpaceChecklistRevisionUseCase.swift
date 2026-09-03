// READY contract scaffold only — no executable behavior.
//
// This leaf will own one provider-free application path from the existing,
// restart-safe SpaceChecklistEditingDraft plus current SpaceCoreDetailsUpdate
// to the already verified SpaceChecklistRevisionOperation boundary.
//
// Implementation is frozen to:
// - ask the draft to derive and revalidate one ReviseSpaceChecklistsCommand;
// - call SpaceChecklistRevising.reviseChecklists exactly once only after
//   command derivation succeeds;
// - validate the receipt and preserve its exact localState;
// - preserve CancellationError, SpaceChecklistEditingFailure, and
//   SpaceChecklistRevisionFailure;
// - map any other port error to SpaceChecklistRevisionFailure.localAcceptanceFailed.
//
// This boundary does not add draft mutations, choose read/edit eligibility,
// implement SwiftUI, or claim physical persistence, optimistic projection,
// authorization, authoritative apply, provider/schema/RLS/Sync behavior,
// app/MCP wiring, migration, hosted resources, deployment, release, cutover,
// or production authority.
