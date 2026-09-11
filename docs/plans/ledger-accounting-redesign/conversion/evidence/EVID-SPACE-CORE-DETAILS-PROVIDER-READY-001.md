# EVID-SPACE-CORE-DETAILS-PROVIDER-READY-001 — Space Core-Details Provider READY Boundary

- Date: 2026-09-05
- Class: reviewed READY design / provider-backed read workflow
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on `firebase`; the Firebase checkout and released app remain unchanged
- Target branch: `codex/supabase-powersync-implementation`
- Delivery base: `42d484cfaba3dfdcce974cc4815ed21f4e3a02da`
- Dossier: `conversion/implementation-slices/space-core-details-powersync-provider.json`
- Claimed scaffolds: `CONFIG-C07E3326B896`, `CONFIG-55809460A27C`, `SWIFT-B762FCFD8525`, `TEST-33D5654E41CA`, `SWIFT-2335BBE3E8FD`, `TEST-FDF70607A5B4`, `SWIFT-C99453DE8B49`, `SWIFT-058F3155F97F`

## Authorized Outcome

An authorized user may select one stable Space in one Account and review its complete core record offline: immutable Project-or-Business-Inventory scope, accepted stored name and optional notes, active or archived lifecycle, exact revision/timestamps, ordered checklist hierarchy, checked state and derived completed/total counts.

This boundary reuses the verified `SpaceCoreDetailsQuerying` contracts and the existing encrypted Account-workspace runtime. It introduces no second domain model, no list/search/card route, and no write or accounting authority.

## Independent Candidate Review

Two independent read-only scouts evaluated the conversion tracker, canonical specs, decision log, residual register, target-query logical-authority crosswalk, existing provider-free dossiers and current physical target code. Both ranked this slice first because:

- `space-core-details-read-contracts` is verified with no blockers;
- `TQUERY-CD97754157F6` / `TACCESS-281F2B9A29AB` is `mapped` with authorization, ordering, pagination, readiness, result and scope reviewed and `unresolvedAxes: []`;
- canonical Space identity, fields, checklist hierarchy and progress already exist in `docs/specs/spaces.md`; and
- the implemented Space destination provider supplies a tested encrypted Space table, active-membership sentinel, exact-scope subscription pattern and close-aware runtime without deciding this detail workflow.

The scouts rejected or deferred Client rename (O-042/O-043), direct Space creation (O-044/O-045/O-046), Project-note writes/search (O-039), Project preferences/broad MCP (O-040), Space archive effects (O-037), physical session ending (A-007/A-016/O-023), Project budget contribution authority, and Item placement mutation without a provider-backed Item source.

## Frozen Physical Design

- Preserve the seven existing `spike_spaces` columns, row bytes, Data API shape, grant, active-only policy and destination streams. Add only a redundant `(account_id,id)` unique parent key required for exact same-Account child foreign keys. Store lossless optional notes and exact timestamp/millisecond evidence in a separate one-to-one `spike_space_core_details` relation with no client grant.
- Store checklists and checklist items as relational children with provider-row identity separate from scoped domain identity. Checklist identity/order is unique inside one Space; item identity/order is unique inside one checklist; order is bounded to the Core `UInt32` range, so the same item ID in different checklists remains valid. Empty Spaces and empty checklists remain valid.
- Store no opaque checklist JSON, derived progress count, percentage or legacy `isComplete` authority.
- Add one exact AccountID/SpaceID on-demand Sync Stream containing base Space, one-to-one core-detail, checklist and item queries. Each query derives signed identity plus active Account membership and verifies the exact parent; subscription parameters only narrow. Owning-Project lifecycle is not a filter, so an existing Space under an archived Project remains readable.
- Include active and archived Space detail without broadening the existing active-only Space destination RLS policy. New child relations receive forced-RLS defense in depth and no public/anon/authenticated Data API grant.
- Reconstruct the complete hierarchy through one sentinel-preserving local observation and the unchanged Core validators. Only a fresh exact-stream completion followed by a causally later full reread can establish completeness.
- Retained encrypted rows begin partial/stale after restart. Membership/selection loss clears rows and completeness; reactivation requires another exact completion. Every row/status/subscription observer drains before database close.
- The AppModel and isolated staging view render typed local truth only. They add no editing, archive, Item, media, review, template, accounting or MCP action.

## READY Scaffolds and Honest Status

All six Swift files contain comments only. The CLI-created migration contains comments only. The pgTAP file has one explicit runner-validity placeholder and no Space assertion. The conversion discovery control was changed only to discover the migration and test deterministically.

Therefore the slice and its eight surfaces are `ready`/`target_mapped`, not implemented. No schema, provider, app behavior or security claim is inferred from the scaffolds.

## Required Implementation Proof

Implementation must prove:

- unchanged seven-column base Space behavior plus its additive composite parent key, separate one-to-one detail schema, exact same-Account relationships, exact millisecond/signed-bigint revision bounds, nested identities/UInt32 order bounds, indexes and least privilege from a clean database;
- no permissive-policy broadening, client writer, RPC, SECURITY DEFINER path or Data API detail surface;
- signed exact-Space Sync configuration for active and archived parents plus complete children;
- Project and Business Inventory scopes, zero children, empty checklists, duplicate item IDs across different checklists and exact canonical reconstruction;
- both row/completion startup orders, causal reread, partial/stale/ready/authoritative-absence truth, encrypted restart, lossless positive signed-bigint-to-UInt64 lifting and fail-closed zero/overflow evidence;
- revocation/selection/runtime clearing, reactivation, malformed/orphan/duplicate/foreign evidence refusal and observer/subscription drainage;
- exhaustive Core-only presentation and noncooperative late-event tests;
- unchanged seven-column active-only Space destination behavior plus an existing Space under an archived Project; and
- full conversion/target controls, all Swift/database tests, deterministic project generation, both staging builds and immutable exact-commit CI.

Real authenticated PowerSync authorization/revocation remains a separate planned obligation. Local configuration and controlled completeness sources cannot advance A-004.

## Safety Boundary

A-003/A-004/A-016 and O-023/O-026/O-037/O-044/O-045/O-046 remain unadvanced. The broad source `SpaceDetailView`, general Space lists/cards/routes, all Space/checklist writers, Space archive behavior, Item placement, media/review, templates, accounting, MCP, hosted Supabase/PowerSync resources, Firebase, source import, production data, migration, release and cutover are excluded.
