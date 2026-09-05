// READY scaffold only — no executable application model exists here.
//
// The implementation may add one Core-only observable staging model that opens
// an exact SpaceAssignmentDestinationRequest and presents waiting/partial/stale/
// ready/authoritative-empty/failure truth. It may hold one user-selected,
// represented SpaceID as transient presentation state, but selection lifecycle
// beyond the canonical represented-row constraint is not frozen as product
// behavior by this slice. A late event from an older request cannot replace the
// current request's evidence.
//
// This model performs no Item selection and dispatches no Assign/Clear, Space
// create/update/archive, MCP, migration, hosted, release or cutover behavior.
