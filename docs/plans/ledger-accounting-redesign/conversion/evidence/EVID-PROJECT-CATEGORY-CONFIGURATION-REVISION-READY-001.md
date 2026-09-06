# EVID-PROJECT-CATEGORY-CONFIGURATION-REVISION-READY-001 — Dedicated Project Category-Configuration Revision

- Timestamp: 2026-09-06
- Class: READY / provider-independent target prerequisite
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on `firebase`; source worktree unchanged
- Target base: `751f0bcf5d516f433e13f616df74d9896412a477`
- Claimed surfaces: `CONFIG-3F4DAB40CF04`, `CONFIG-6EE152848D09`

## Outcome

Three independent audits rejected silently mapping the Core configuration revision to a Project revision or to a derived allocation/content value. Project archive already increments the Project revision without changing allocations; row maxima cannot represent deletion or the empty set; and `LocalDataVersion` already owns content identity.

This READY boundary therefore introduces a dedicated `category_configuration_revision` physically colocated on every Project. It begins at one for empty and nonempty sets, is independent from Project lifecycle/details and allocation-row revisions, and is stored as full-range integral PostgreSQL `numeric` projected to local SQLite as canonical decimal text. A future complete-set writer owns expected-revision comparison, atomic replacement, exactly-one material-change increment and no-op preservation.

## Offline Boundary

A locally accepted new Project stores projected revision text `1` atomically with its pending Project and complete allocation overlay. The value is explicitly optimistic: this foundation neither reconciles pending allocations nor claims server authority. Encrypted restart must preserve it without signed-64 or floating-point conversion.

## Independent Review Corrections

- The proposed Project category provider remains blocked instead of being implemented over ambiguous authority.
- The provider must later distinguish a missing Project from a real Project with zero visible categories.
- O-026 still blocks final category/allocation download authorization. The existing stricter full-versus-ordinary spike is not blessed as product-complete and no RLS/Sync visibility predicate changes in this foundation.
- Six newly discovered provider/app leaves remain comment-only and explicitly blocked until a separate READY review resolves those issues.

## Required Proof

Implementation must prove server type/range/default/backfill, empty/nonempty initialization, archive independence, explicit lossless Sync projection, local pending atomicity/restart, maximum UInt64 text, static rejection of revision conflation, all existing target/Supabase tests and immutable exact-commit CI.

## Safety Boundary

No category configuration writer, provider, AppModel, UI, MCP, final RLS/Sync authorization, Firebase edit, hosted resource, source import, production access, release or cutover is authorized. A-003/A-004/A-015 and O-026 remain unadvanced.
