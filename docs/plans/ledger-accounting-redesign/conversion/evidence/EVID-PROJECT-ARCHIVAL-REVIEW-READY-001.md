# EVID-PROJECT-ARCHIVAL-REVIEW-READY-001 — Frozen Delivery Contract

## Outcome

Independent Postgres/RLS/PowerSync/offline and MCP reviews returned GO for one isolated target workflow: select an active or archived Project, read a bounded page from its complete exact-Project note replica offline, archive an active Project through the existing durable archive path, and prove that archival leaves every note identity, content/tombstone, audit field, revision and order unchanged.

This evidence authorizes implementation in the dedicated Supabase worktree only. It does not authorize hosted resources, source import, Firebase changes, production access, deployment, release or cutover. A-003 and A-004 remain proposed.

## Frozen Scope

- One `spike_project_notes` physical authority with a restrictive Account/Project foreign key, structural visible/tombstone and paired-audit constraints, exact millisecond evidence, full UInt64 revision represented as untyped integral `numeric`, and the keyset index `(account_id, project_id, created_at_ms DESC, id DESC)`.
- Explicit authenticated SELECT only, active Account-membership RLS, no direct note mutation grants or policies, and a precision-safe security-invoker read projection/RPC that emits revision as canonical decimal text.
- One on-demand `project_note_history` PowerSync stream for an exact Account/Project. Subscription parameters narrow scope but signed active-membership predicates authorize it. The stream contains the exact Project anchor and the complete authorized note set, including archived Projects, without server-side order, limit, search or lifecycle filtering.
- Local pages are bounded to 1...200 and use strict `(createdAtMilliseconds, noteID)` descending keyset continuation. A page reads `pageSize + 1` locally, returns at most `pageSize`, and reports complete Project history only after a new current-process completion for that exact stream and no extra row.
- Retained encrypted rows after restart are useful but partial/stale until current-process exact-stream completion. Missing membership returns no rows and no completeness. Missing Project after fresh exact completion fails boundedly rather than becoming an authoritative empty history.
- The existing Project browser owns selection, page and observer generations. Selection change immediately clears notes and drains the old watch. Active-to-archived movement of the same stable Project preserves the note watch and note values.
- The gated target MCP exposes only bounded `list_project_notes` transport and the already-canonical `archive_project` operation. Account and Principal come from authenticated request context; transport uses a publishable key plus scoped user bearer and refuses service-role credentials. Online MCP results share scope, order, cursor, content and completeness semantics but never manufacture PowerSync local readiness.
- Existing archive Core/use-case/store/RPC/migration semantics stay unchanged. Preservation tests may exercise them but cannot add restore, delete, rename, reassignment or child mutation behavior.

## Explicit Exclusions

- Project-note create, edit, delete, search or post-archive mutation eligibility; O-039 remains product authority for those writes.
- A capped/evicting note window, tombstone eviction or refill policy. This spike synchronizes complete exact-Project history because no product authority defines safe truncation.
- Project restore, delete, rename, details editing, Client reassignment, preferences, Items, Spaces, accounting or media.
- Firebase adapters or Firebase implementation work.
- Firebase snapshot decoding, migration/import/reconciliation or production data.
- Live MCP tool registration, hosted Supabase/PowerSync authorization claims, release or cutover.

## Change Boundary

The new batch owns exactly the ten surfaces in `M0-PROJECT-ARCHIVAL-REVIEW-001`. Shared changes are limited to the existing PowerSync schema/runtime lifecycle, Project browser composition, isolated staging UI, Sync Stream YAML, target contract catalog and generated projections, local-only test commands, target checks, and conversion tracking.

Frozen unless a separately demonstrated defect requires change: `ProjectNoteData.swift`, Project archive domain/use-case/store/upload/RPC/migration behavior, Firebase sources, production app projects, migration/import tooling and hosted configuration.

The READY baseline is `1e893c6c02dc22a52cb1332e3a98a26c714d5fba`. Rollback is source reversion and disposal of synthetic local target data.

## Risk Review

- Security: independently reviewed membership/RLS/grant/Sync predicates; implementation requires positive and negative tenant tests and no privileged client credential.
- Offline concurrency: independently reviewed selection/page/runtime generations, retained-subscription freshness, revocation, unsubscribe-once and database-close drainage.
- Numeric integrity: PostgreSQL, PowerSync and MCP must preserve UInt64 note and Project revisions without JavaScript or SQLite floating-point conversion.
- Cross-runtime drift: Swift, TypeScript and PostgreSQL fixtures must prove exact note request/cursor semantics and unchanged archive bytes.

## Required Executable Proof

1. Clean local database reset, complete pgTAP suite and zero database-lint findings.
2. Local scoped-user Data API positive and negative matrix for active/archived/tombstoned notes and archive preservation.
3. Encrypted PowerSync tests for scope, 1/200/+1 pagination, timestamp ties, malformed atomic failure, restart freshness, membership loss/reactivation, parent loss, archive preservation and full observer drainage.
4. AppModel tests for selection/page/runtime replacement, false-empty prevention, lifecycle continuity and late-emission rejection.
5. MCP tests for exact query/archive transport, UInt64 boundaries, cursor rebinding, result validation, least privilege, privacy-safe diagnostics and absence of excluded tools/registration.
6. Complete target Swift and MCP suites, target-environment checks, both isolated target builds, exact conversion synchronization, clean artifacts and immutable exact-commit CI.

## Reviewers

- Postgres/RLS/PowerSync design: independent specialist review, GO with complete-history clarification and precision-safe revision projection.
- Offline/app concurrency: independent specialist review, GO with browser-owned lifecycle and exact cancellation/drain requirements.
- MCP/control plane: independent specialist review, GO for a gated umbrella module and NO-GO for live registration or hosted claims.

The integrator remains responsible for implementation, shared-file conflicts, executable verification and correction of all review findings.

Initial READY commit `8acf5310` passed the direct conversion checker and all local target/database suites, but immutable run `33994108306` correctly failed before downstream jobs because the generated M2 residual register had not been refreshed after admitting the ten target surfaces. The follow-up checkpoint regenerates that deterministic artifact; no scope, requirement, executable scaffold or product behavior changed.
