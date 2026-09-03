// Frozen implementation boundary for direct-space-creation-use-case-contracts.
//
// Presentation owns caller-supplied raw name/notes form input; the form value
// exposes typed direct-Space intent conversion for immediate validation using
// the verified canonical domain values. A separately named application use
// case receives the raw form input, invokes that same conversion, adds caller-
// supplied operation metadata, constructs the verified CreateSpaceCommand,
// invokes SpaceCreating exactly once after validation, and validates the
// returned receipt without changing its local state.
//
// This leaf must not add SwiftUI, form persistence, templates, checklists,
// media, Items, archive, review, accounting, authorization, provider/schema/
// RLS/Sync, MCP, migration, production, release or cutover behavior.
