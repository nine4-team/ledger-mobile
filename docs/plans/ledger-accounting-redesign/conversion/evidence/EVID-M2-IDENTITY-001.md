# EVID-M2-IDENTITY-001 — Identity, Membership, and Session Target Mapping

- Timestamp: 2026-08-31
- Class: target mapping design evidence
- Repository baseline: `d83c64724fe4e92be27c62f425979bd30fcfc9bb`
  on `dev`; shared worktree was already dirty
- Production reads or mutations: none
- Target implementation/schema/RLS/Sync Stream changes: none
- Operator: Codex
- Mapping batch: `M0-IDENTITY-LIFECYCLE-001`
- Method: `target-mapping-method.md`

## Scope and Result

All eight target-relevant surfaces in the identity/lifecycle batch now map to
exact provider-neutral owners, ports/snapshots/commands/tables, security and
Sync responsibilities, source migration/reconciliation rules, tests and
acceptance outcomes. The placeholder settings and root MCP user-state surfaces
remain deliberately retired; the source Account discovery tests remain
preserved evidence.

## Mapping Decisions

- Account discovery/current membership maps to `AccountQuerying`,
  `AuthorizedAccountListSnapshot`, `MembershipSnapshot` and one
  `WorkspaceCoordinator`, not sequential Firebase document resolution or broad
  listener contexts.
- Root/account presentation maps to explicit identity/workspace/readiness and
  `AccountSessionEnding` state. No view can call provider signout before the
  pending-operation/media policy runs.
- Account/member/invite source models map to `accounts`, `account_members`,
  `member_financial_permissions`, `account_invites`, stable Principals and typed
  snapshots/commands. Roles and financial grants are server authority.
- The invitation contract now explicitly requires one-way token digests,
  one-time expiry/revocation, non-enumerating preview, authenticated Principal
  binding and no secret/Auth-subject download through PowerSync.
- MCP request context and Account selection map to verified Principal and active
  membership on each request/session. Runtime/environment/hardcoded identity
  fallback and independent `mcpUserState` authorization are absent.

Architecture ports, conceptual tables/streams and security guidance were
updated to include member directories and the complete invite lifecycle. A-007,
A-016, O-023 and O-026 remain explicit provider/policy/retention/administration
gates where applicable; they do not change the provider-neutral ownership map.

## Verification

After synchronization, the batch must show eight target-relevant and eight
`target_mapped` surfaces with zero missing target owner/surface, security, Sync,
migration, reconciliation, test or acceptance fields. Conversion/capability/
query checks and M0 remain required. M1 remains blocked only by the canonical
production profile and O-022 cutover evidence.

This evidence proves reviewed target mapping only. It does not choose A-007 or
A-016, create Auth/Supabase/PowerSync infrastructure, access production, migrate
identities, implement RLS/streams, release, or cut over.
