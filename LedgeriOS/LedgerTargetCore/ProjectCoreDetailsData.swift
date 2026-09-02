// Ready-gate scaffold for project-core-details-read-contracts.
//
// The implementation must remain a provider-free single-Project core-record
// read. It will bind one exact AccountID and ProjectID request to a deterministic
// versioned fingerprint, validate at most one matching ProjectSummary, and carry
// the exact Project revision observed in that local snapshot as an
// ExpectedProjectRevision. The revision is local conflict-precondition evidence;
// it is distinct from LocalDataVersion and must never be described as currently
// authoritative when the enclosing local evidence is incomplete, partial, or
// stale.
//
// ProjectSummary is reused only after the wrapper verifies that its optional
// description is already canonical under ProjectDescriptionReplacement. An
// archived Project remains a found row, and an active Project may legitimately
// retain an archived Client relationship. Only ready, complete, zero-row local
// evidence may prove authoritative absence.
//
// This boundary must use explicit readiness, completeness, bounded failure, and
// exact-request streaming semantics. It grants no authorization and includes no
// Project children, media, accounting, action capability, persistence, provider,
// Postgres/RLS/PowerSync, app/MCP, migration, hosted-resource, production,
// release, or cutover behavior.
