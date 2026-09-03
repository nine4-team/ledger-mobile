// Frozen implementation boundary for space-details-update-use-case-contracts.
//
// A transient non-Codable form value will carry exact Account/Space/base-
// revision identity plus caller-supplied raw name and optional notes. Canonical
// intent conversion must reuse SpaceDisplayName and SpaceCreationNotes only.
// A separately named application use case will revalidate the raw input, add
// caller Operation/actor/contract/time, construct the verified complete-
// replacement UpdateSpaceDetailsCommand, invoke SpaceDetailsUpdating exactly
// once after validation, and validate the returned receipt without changing its
// local state. Swift task cancellation remains concurrency control flow;
// unexpected transport failures are normalized at the application boundary.
//
// This leaf must not consume SpaceCoreDetailsUpdate/readiness, choose active or
// archived eligibility, populate/persist form state, suppress no-op submission,
// add SwiftUI/dismissal behavior, change Space scope/lifecycle/checklists/
// templates/Items/review/media/accounting, authorize, or add provider/schema/
// RLS/Sync/MCP/migration/production behavior.
