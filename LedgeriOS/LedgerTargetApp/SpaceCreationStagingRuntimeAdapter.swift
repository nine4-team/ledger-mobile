// DRAFT scaffold only: no executable runtime adapter exists here.
//
// The future adapter may forward one typed create intent and one exact-scope
// destination watch through LedgerOfflineClientRuntime. It must remain a thin
// boundary, retain no second queue or domain policy, and join every observer on
// replacement, cancellation, or workspace close.
