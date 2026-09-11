/*
 DRAFT COMMENT-ONLY SCAFFOLD — space-read-target-mcp

 Exact base: 2297e8dbe7f7f0febb7e33b4da0be591d4c82ade
 Source-responsibility context only (never claimed by this leaf):
 - MCPTOOL-24DFA89A8F44 — list_spaces
 - MCPTOOL-2B45E68B60F7 — get_space

 This leaf must remain comment-only until the complete three-slice Space browsing
 batch freezes the sibling Space-list contract/provider and this dossier passes
 READY review with discovered target-only surface IDs.

 Planned bounded API while Item/media dependencies remain unavailable:
 - SpaceListToolInput: explicit Project-or-Business-Inventory scope plus only the
   exact lifecycle/page/cursor controls frozen by the sibling list contract.
 - GetSpaceToolInput: one stable Space ID; Account and Principal come only from
   TargetMCPRequestContext.
 - SpaceReadQuerying: one injected backend-neutral reader with list and detail
   methods. It performs no authorization locally and exposes no provider SDK.
 - listSpaceCoreTool and getSpaceCoreTool: require authenticated user context, construct
   canonical scope-bound requests, invoke the reader once, validate the complete
   returned union, and emit only bounded privacy-safe values.
 - Tool definitions remain exports only; no registration is added in this slice.
 - Every result identifies projectionProfile space_core_only_v1 and explicitly
   marks itemProjection/mediaProjection deferred or not_available. Never emit a
   fabricated zero itemCount, empty items array or empty images array.
 - Public list_spaces/get_space replacement and registration remain blocked until
   authoritative Item/media dependencies exist or canonical authority approves
   these narrower names/semantics as new partial diagnostic tools.

 Required semantic parity:
 - Import the sibling batch's exact request fingerprint, list bound, ordering,
   continuation and readiness contract; do not invent TypeScript alternatives.
 - Mirror the existing bounded Space core-details identity/scope/lifecycle/
   revision/timestamp/checklist semantics, with UInt64 revision transported as
   canonical decimal text and shared fixture vectors against Swift.
 - Preserve partial/stale/incomplete/not-synchronized truth. An empty local read
   is authoritative only with exact completeness evidence.
 - Missing, foreign, revoked, unauthorized and otherwise not-visible detail
   evidence has one non-enumerating not-visible-or-absent outcome. This remains
   distinct from not-synchronized and reveals no row/count/existence reason.
 - Validate Account, Principal, scope, Space, fingerprint, row uniqueness/order,
   page bound/cursor, lifecycle, revision, timestamps and checklist hierarchy
   before returning any content. Never return a partially validated page.

 Forbidden surface:
 - no Account-wide wildcard or the source tool's magic "inventory" string;
 - no raw Firebase/provider document, Item rows/counts, image URL/path,
   attachment/review evidence, financial value, legacy isComplete, arbitrary
   fields or hidden pre-filter counts;
 - no service-role/database/Storage/Firebase credential or provider constructor;
 - no direct Supabase/Data API/PowerSync/network/filesystem/database access;
 - no raw error/provider response, token, endpoint or identity/text logging;
 - no live MCP registration, shared registry/catalog/package edit, hosted call,
   production fallback, source migration, release, activation or cutover.
*/
