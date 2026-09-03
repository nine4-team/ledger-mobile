// Frozen implementation boundary for the provider-free Space checklist editor.
//
// The implementation must be derived only from the ready
// `space-checklist-editing-presentation-contracts` dossier and its verified
// Space-core-details and checklist-revision dependencies. It prepares and edits
// one safe current or retryable-cached hierarchy, retains raw intermediate text,
// then derives the existing `ReviseSpaceChecklistsCommand` only after semantic-
// base revalidation. Harmless local refresh metadata must not invalidate edits.
//
// This leaf must not add SwiftUI, persistence, authorization, provider, schema,
// RLS, PowerSync, app/MCP, migration, template, media, Item, review, archive,
// accounting, production, release or cutover behavior.
