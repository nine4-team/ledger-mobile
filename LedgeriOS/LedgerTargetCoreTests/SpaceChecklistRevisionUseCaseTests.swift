// READY verification scaffold only — no executable tests.
//
// The implementation candidate must add reciprocal provider-free tests that:
// - prove the same existing draft successfully derives and dispatches one
//   complete ordered replacement from both ready-complete current evidence and
//   retryable ready-complete cached evidence, including nonsemantic refreshes
//   of version, as-of, name, notes, and audit timestamps with an unchanged
//   Account/Space/scope/lifecycle/revision/hierarchy semantic base;
// - preserve stable nested IDs, normalized names/text, checked state, duplicate
//   text, empty collections, zero-item checklists, and boundary revisions on
//   both admissible readiness paths, with exactly one port call per path;
// - preserve every LocalOperationState after exactly one reviser call;
// - vary command metadata and checklist semantic fields independently and prove
//   their exact owning command fields and derived evidence;
// - prove noneditable/incomplete or changed semantic-base evidence, invalid raw
//   checklist content, and nonfinite capture time fail before any port call;
// - reject receipt mismatch after one call;
// - preserve CancellationError, SpaceChecklistEditingFailure, and
//   SpaceChecklistRevisionFailure while mapping a raw port error narrowly;
// - prove bounded diagnostics/encoded command exclude Space details/scope/
//   lifecycle, templates, media, Item placement, review, completion, accounting,
//   provider details, credentials, and production identity.
//
// Tests must not claim SwiftUI integration, physical durability/restart beyond
// the existing value contracts, optimistic projection, authorization,
// authoritative apply, schema/RLS/Sync, app/MCP, migration, hosted resources,
// release, cutover, or production behavior.
