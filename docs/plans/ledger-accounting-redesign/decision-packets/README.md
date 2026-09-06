# Product Decision Packets

Status: proposed recommendations; not product authority
Last reviewed: 2026-09-05

These packets turn exact conversion blockers into reviewable senior-level
choices. They exist so the implementation does not guess product behavior or
copy accidental Firebase mechanics while designing the Supabase/PowerSync
target.

## Authority Boundary

- The canonical specs and `decision-log.md` remain product authority.
- A packet is a proposal until the product decision is explicitly approved and
  recorded in the decision log.
- Conceptual tables, commands, RLS, Sync Streams, migrations, and tests in a
  packet are design consequences, not DDL or implementation authorization.
- A packet cannot approve A-003/A-004. Supabase and PowerSync remain proposed
  until the isolated vertical spike passes.
- No packet authorizes production Firebase reads or mutations, production
  migration, cutover, a Firebase adapter, or a Firebase v2 implementation.

## Required Packet Shape

Every packet must include:

1. the decision requested and mutually exclusive options;
2. the recommended option and why;
3. affected residual blocker IDs and exact surface coverage;
4. confirmed constraints it cannot reopen;
5. domain, schema, command/query, authorization, offline/Sync, migration, and
   reconciliation consequences;
6. concurrency, failure, security, offline, migration, and semantic acceptance
   tests; and
7. an approval checklist that distinguishes what closes from what remains open.

## Closure Workflow

When the user approves a packet:

1. record the approved behavior as a new confirmed decision in
   `decision-log.md` and update the canonical specs;
2. update `docs/architecture/redesign/product-decision-traceability.md` and the
   affected architecture contracts;
3. remap every affected residual surface, retaining any other blocker on that
   surface;
4. regenerate and validate the conversion manifest, coverage, residual queue,
   and evidence; and
5. only then advance the corresponding implementation-tracker row.

The generated residual register is the completeness check. A packet title or
recommendation alone does not reduce the residual count.

## Packet Index

| Decisions | Packet | Recommendation status |
|---|---|---|
| O-007/O-015 | [Item accounting and provenance model](O-007-O-015-item-accounting-and-provenance.md) | Proposed: explicit relational facts plus derived history |
| O-029/O-032 | [Transaction posting and lifecycle](O-029-O-032-transaction-posting-and-lifecycle.md) | Proposed: durable nonfinancial draft, atomic post, append-only lifecycle |
| O-023 | [Attachment reference and retention](O-023-attachment-reference-and-retention.md) | Proposed: detach/supersede, 30-day quarantine, trusted purge |
| O-026 | [Shared reference-data authorization](O-026-shared-reference-data-authorization.md) | Proposed: capability matrix with protected financial/system semantics |
| O-031 | [Item tax and acquisition basis](O-031-item-tax-and-acquisition-basis.md) | Proposed: exact allocated cents plus derived landed-basis readiness |
| O-009/O-034 | [Invoice adjustments and sent revisions](O-009-O-034-invoice-adjustments-and-sent-revisions.md) | Proposed: typed adjustment sources plus immutable delivered revisions |
| O-003/O-004/O-005/O-010 | [Client credit and zero-Invoice model](O-003-O-004-O-005-O-010-client-credit-and-zero-invoice.md) | Proposed: credit balance, offset/cash settlement, signed diverging budget |
| O-008/O-030 | [Receipt-line treatment and rounding](O-008-O-030-receipt-line-treatment-and-rounding.md) | Proposed: exact treatment allocations and explicit one-cent variance line |
| O-006/O-033 | [Expense locks and collection payment](O-006-O-033-expense-locks-and-collection-payment.md) | Proposed: field-state matrix and exact positive payment equality |
| O-035/O-036 | [Client Summary and shared evidence](O-035-O-036-client-summary-and-shared-evidence.md) | Proposed: paid/open/recognized report plus explicit sanitized evidence package |
| O-037 | [Space archive and Item assignment](O-037-space-archive-and-item-assignment.md) | Proposed: archive-only, retained resolvable assignments, explicit move/clear |
| O-038 | [Inventory destination planning](O-038-inventory-destination-planning.md) | Proposed: Item-level Project plans with a non-authoritative Purchase default, no category authority, and explicit lifecycle |
| O-039 | [Project-note text validation](O-039-project-note-text-validation.md) | Proposed: shared app/MCP outer trim, one-character minimum, exact interior text, lossless legacy import |
| O-040 | [Project budget pinning](O-040-project-budget-pinning.md) | Proposed: decide whether pins survive, then explicitly choose typed targets, missing/empty/no-pin defaults, Project-detail/card fallbacks, lifecycle and cleanup; no fallback is approved by the packet itself |
| O-041 | [Vendor-spend report semantics](O-041-vendor-spend-report-semantics.md) | Proposed: per-currency Business Vendor Cash Movement with 1584-paid Purchases/Expenses, Returns to 1584, exact label-snapshot buckets and separate non-cash credit fields |
| O-042/O-043 | [Client rename and display-name boundary](O-042-O-043-client-rename-and-display-name-boundary.md) | Proposed: archived rename plus successful no-change semantics, and one exact 512-byte cross-runtime name-submission contract; neither is approved |
| O-044/O-045/O-046 | [Space creation boundary](O-044-O-045-O-046-space-creation-boundary.md) | Proposed: exact 512-byte name/16-KiB notes contracts, any-active-member create authority, and active Project parent; none is approved |
| O-002/O-011–O-014 | [Transfer edge policy](O-002-O-011-O-014-transfer-edge-policy.md) | Proposed: sent revision, contextual tag/Space, paired reversal, current-Project credit |
| O-016/O-017/O-027 | [Item capture and acquisition readiness](O-016-O-017-O-027-item-capture-and-acquisition-readiness.md) | Proposed: name/photo/note minimum, no persisted hint, explicit unresolved acquisition |
| O-018/O-019/O-020/O-022 | [Proto migration and authority cutover](O-018-O-020-O-022-proto-migration-and-authority-cutover.md) | Proposed: deterministic Item/review mapping and hard freeze/import/reconcile/activate |
| O-024/O-025 | [Project and Client lifecycle](O-024-O-025-project-and-client-lifecycle.md) | Proposed: archive-only Projects, pre-history Client correction, audited Client merge |
| O-028 | [Vendor adjustment and credit balance](O-028-vendor-adjustment-and-credit-balance.md) | Proposed: non-Transaction adjustment, conserved balance, Return only for actual cash |

O-021 is intentionally not a packet or schema gate. It is the UI-only choice
between one expandable screen and two steps; the shared `CreateItem` domain
contract, minimum evidence, offline durability, and migration do not depend on
that presentation experiment.
