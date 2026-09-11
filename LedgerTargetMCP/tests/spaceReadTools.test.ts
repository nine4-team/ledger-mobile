/*
 DRAFT COMMENT-ONLY TEST SCAFFOLD — space-read-target-mcp

 Keep this leaf non-executable until the sibling Space-list contracts are frozen,
 the two new target-only leaves are discovered/claimed, and the dossier passes
 READY review. Future tests must use recording/failing injected readers and
 deterministic synthetic fixtures only.

 SPACEREADMCP-TEST-001 — exact cross-runtime contract
 - Assert byte-identical request fingerprints and exact scope representation.
 - Assert full 0/1/2^53-1/2^53/Int64.max/Int64.max+1/UInt64.max revision text.
 - Assert timestamps, lifecycle, checklist IDs/order/text/checked progress and
   every stable diagnostic match the frozen Swift fixtures.

 SPACEREADMCP-TEST-002 — authentication and scope refusal before read
 - Missing/blank/invalid bearer context, Principal or Account refuses.
 - Malformed/ambiguous Project-or-Inventory scope, caller-authored Account or
   Principal, cross-scope cursor and changed fingerprint make zero reader calls.

 SPACEREADMCP-TEST-003 — bounded app/MCP output parity
 - Prove 0/1/exact-maximum/+1 rows and all stable ordering tie cases.
 - Reject duplicates, out-of-order rows, invalid continuation, malformed
   identity/lifecycle/revision/time/checklist evidence and unknown result shape.
 - Prove target output has no Item/count/media/review/financial/raw-provider or
   legacy isComplete field, explicitly labels item/media projection unavailable,
   and never substitutes zero counts or empty Item/image arrays.

 SPACEREADMCP-TEST-004 — readiness and restart truth
 - Cover current, partial, stale, retained restart, incomplete, authoritative
   empty, required-update and unavailable results without strengthening truth.
 - An empty row set without exact completeness never renders authoritative empty.

 SPACEREADMCP-TEST-005 — non-enumeration
 - Missing, foreign, revoked, unauthorized and otherwise not-visible detail all
   yield the same not-visible-or-absent code and payload.
 - Not-synchronized remains observably distinct without claiming absence.
 - Neither outcome echoes IDs, row/count evidence or hidden reason.

 SPACEREADMCP-TEST-006 — three-slice list-to-detail story
 - Project and Business Inventory list selection resolves the identical stable
   Space through app and MCP fixtures across active/archived/readiness states.
 - Selection/scope/readiness changes cannot return old-scope detail.

 SPACEREADMCP-TEST-007 — source convergence/status integrity
 - The target tools reuse the sibling query authority instead of source Firebase
   arrays/joins. Source MCPTOOL-24DFA89A8F44 and MCPTOOL-2B45E68B60F7 remain
   target_mapped and are not claimed as new implementation surfaces.
 - No assertion claims current-tool parity, public list_spaces/get_space
   replacement or registration eligibility while Item/media dependencies remain.

 SPACEREADMCP-TEST-008 — privacy/security shape
 - Inspect every success/failure/diagnostic for tokens, endpoints, service keys,
   raw identities/text, hidden counts and excluded provider/Item/media fields.

 SPACEREADMCP-TEST-009 — provider-free isolation
 - Reject provider/SDK/Firebase imports and service-role constructors.
 - Prove the reader is injected and called exactly once only after validation.
 - Prove no registration/shared catalog/package/hosted/production path exists.

 SPACEREADMCP-TEST-010 — synchronized batch gate
 - Require the exact reviewed three-slice diff, generated surface ownership,
   complete target/MCP checks, both staging builds and immutable exact-commit CI.
*/
