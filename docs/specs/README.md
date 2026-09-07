# System Design Specs

Platform-agnostic design specs documenting business rules, entity relationships, data flows, and invariants. These are the source of truth for how the system works, shared across all client platforms.

The technical structure for the coming redesigned app is defined separately in
the [Ledger Redesign Architecture](../architecture/redesign/README.md). Product
behavior remains authoritative in these specs; the architecture package owns
application boundaries, backend adapters, synchronization, security, and
migration mechanics.

## Spec Index

| Spec | Description |
|------|-------------|
| [invoice-centered-project-accounting.md](invoice-centered-project-accounting.md) | Canonical target Transaction/Invoicing boundary, whole-Invoice collection, Expenses, paid history, and no-double-count budget model |
| [inventory-item-invoicing-lifecycle.md](inventory-item-invoicing-lifecycle.md) | Canonical target Item charge/credit, inventory placement, return, resale, correction, and provenance stories |
| [client-identity-and-project-transfers.md](client-identity-and-project-transfers.md) | Canonical target Client identity, global three-type Transaction taxonomy, and paired same-Client Transfers |
| [projects.md](projects.md) | Canonical target Project identity, Client relationship, optional details, archive-first lifecycle, and offline readiness; Firebase mechanics below the target-state notice remain migration evidence |
| [account-discovery-and-workspace-selection.md](account-discovery-and-workspace-selection.md) | Canonical target Account discovery, explicit workspace selection, remembered-scope validation, and privacy-preserving failure behavior |
| [session-ending-pending-work.md](session-ending-pending-work.md) | Canonical target logout, account-removal, pending-operation, and durable local-work safety behavior |
| [data-model.md](data-model.md) | All entities, relationships, canonical lookups, and validation rules |
| [proto-item-capture.md](proto-item-capture.md) | Canonical target unified Item wizard, accounting Link, and hard-cutover legacy capture import |
| [spaces.md](spaces.md) | Canonical target organizational placement, scoped assignment, template, checklist, and archive behavior |
| [non-item receipt-line design](../plans/non-item-receipt-lines/design.md) | Canonical target physical-Item versus nonphysical receipt completeness model |
| [write-tiers.md](write-tiers.md) | Current Firebase write patterns; superseded for the redesigned target by the architecture package |
| [offline-first.md](offline-first.md) | Offline product requirements plus current Firebase implementation; target mechanics live in the architecture package |
| [authentication-offline-access.md](authentication-offline-access.md) | Returning-device offline access and recovery requirements; identity, unlock and lease choices remain open |
| [financial-access-controls.md](financial-access-controls.md) | Company-revenue confidentiality across UI, sync, local data, reports and MCP; source classifiers must be reconciled with target Invoicing and collected payments |
| [budget-management.md](budget-management.md) | Categories, allocations, progress calculations, sign conventions, and pinning |
| [canonical-sales.md](canonical-sales.md) | Scope transitions, deterministic transaction identity, and the two-hop model |
| [lineage-tracking.md](lineage-tracking.md) | The four edge types, creation rules, and audit trail queries |
| [return-and-sale-tracking.md](return-and-sale-tracking.md) | Return flow, disposition lifecycle, and incomplete return detection |
| [transaction-audit.md](transaction-audit.md) | Completeness calculation, variance analysis, and missing price tracking |
| [vendor-credits.md](vendor-credits.md) | Vendor cancellation credits and other vendor-issued purchase offsets; distinct from physical returns |
| [reassign-vs-sell.md](reassign-vs-sell.md) | Correct/Move (no financial impact) vs Sell (scope change with budget impact) vs Return (vendor or inventory). UI menu labels and visibility rules. |
| [reports.md](reports.md) | Invoice, client summary, and property management report generation |
| [project-closeout-report.md](project-closeout-report.md) | Proposed closeout narrative and explicit release/presentation decisions; canonical financial meanings take precedence |
| [billing-invoicing.md](billing-invoicing.md) | Preserved billing-summary and contract-ingestion capabilities; old settlement shapes/algorithms remain source evidence only |
| [invoice-import.md](invoice-import.md) | PDF/image extraction, vendor parsing, and draft transaction creation |
| [search-results.md](search-results.md) | Offline text/SKU/amount search, contextual detail and selection; mutations use owning workflows |
| [needs-review-tab.md](needs-review-tab.md) | Contextual review and resolution; target reason/grouping policy remains open and legacy proto conversion is migration-only |

The canonical target-state specs above override conflicting future-design
language in current or superseded Firebase-era specs. Confirmed decisions in
the redesign decision log override unresolved or stale text; open decisions
remain blockers rather than implementation guesses.

## Conventions

**What belongs here:** Business rules, entity definitions, data flows, invariants, formulas, sign conventions, and design decisions ("we chose X over Y because Z").

**What does NOT belong here:** Implementation-specific code (TypeScript, Swift), component names, file paths, UI layout details, or framework-specific patterns.

**When to update:** When a design decision changes — new entity relationships, new business rules, changed data flows, new edge cases. Implementation changes (refactoring, new UI components) don't require spec updates unless the underlying system behavior changes.

**When to create a new spec:** When a new system-level concept is introduced that spans multiple features or affects data model invariants.
