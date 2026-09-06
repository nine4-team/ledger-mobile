// DRAFT SCAFFOLD ONLY — no executable contract.
//
// Proposed frozen boundary: provider-free Space list read and active-list
// presentation for one exact Account + Project-or-Business-Inventory scope.
// Independent READY review must approve the dossier before declarations replace
// these comments.
//
// Planned values and responsibilities:
// - SpaceListRequest: exact AccountID + SpaceCreationScope + versioned fingerprint.
// - SpaceListSourceRow: stable SpaceID, exact Account/scope, SpaceDisplayName,
//   explicit active/archived lifecycle, UInt64 revision and validated complete
//   SpaceChecklistCollection. It contains no Item, media, notes, action or route.
// - SpaceListLocalSnapshot / SpaceListUpdate / SpaceListFailure /
//   SpaceListQuerying: exact request-bound local evidence with bounded failures.
// - ActiveSpaceDirectoryPresentationSnapshot: the only browsing presentation;
//   archived source rows are excluded and never relabeled. There is no archived
//   browser segment in this slice.
// - SpaceDirectoryRowPresentation: stable ID/name, derived checklist completed
//   and total counts, and an explicit unavailable Item-count state. Never render
//   an unavailable count as zero.
// - SpaceBrowsingSelection: binds the exact active row and complete current
//   presentation evidence; validates that unchanged evidence before deriving the
//   existing SpaceCoreDetailsRequest. A found detail must keep Account/Space/scope.
//
// Planned invariants:
// - Reject cross-Account, cross-scope, duplicate-ID, hidden-count, malformed,
//   nonfinite-time, request-rebound and noncanonical encoded evidence.
// - Canonicalize rows by lowercased display name, exact display name, then raw
//   stable SpaceID, matching the verified destination-directory total order.
// - Authoritative active empty requires ready + complete + source-exhaustive.
//   Partial/stale/incomplete/failed empty evidence remains unknown, not empty.
// - Checklist progress is derived only from validated checklist state. Legacy
//   isComplete, percentage, numeric Item count, search and card media are absent.
// - Cached rows are local evidence, never authorization.
//
// Explicit exclusions: mutation, archive/restore effects, archived browsing,
// assigned-Item resolution, media, templates, Items, review, accounting,
// SwiftUI/MCP/runtime wiring, persistence, Postgres, RLS, PowerSync, migration,
// hosted resources, production behavior and cutover.
