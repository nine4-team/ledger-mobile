# System Design Specs

Platform-agnostic design specs documenting business rules, entity relationships, data flows, and invariants. These are the source of truth for how the system works, shared across all client platforms.

## Spec Index

| Spec | Description |
|------|-------------|
| [data-model.md](data-model.md) | All entities, relationships, canonical lookups, and validation rules |
| [write-tiers.md](write-tiers.md) | The four write patterns (fire-and-forget, request-doc, callable, trigger) and when to use each |
| [offline-first.md](offline-first.md) | Offline architecture, sync status, and attachment lifecycle |
| [budget-management.md](budget-management.md) | Categories, allocations, progress calculations, sign conventions, and pinning |
| [canonical-sales.md](canonical-sales.md) | Scope transitions, deterministic transaction identity, and the two-hop model |
| [lineage-tracking.md](lineage-tracking.md) | The four edge types, creation rules, and audit trail queries |
| [return-and-sale-tracking.md](return-and-sale-tracking.md) | Return flow, disposition lifecycle, and incomplete return detection |
| [transaction-audit.md](transaction-audit.md) | Completeness calculation, variance analysis, and missing price tracking |
| [spaces.md](spaces.md) | Organization, scoping, templates, and checklists |
| [reassign-vs-sell.md](reassign-vs-sell.md) | When to reassign (no financial impact) vs sell (scope change with budget impact) |
| [reports.md](reports.md) | Invoice, client summary, and property management report generation |
| [invoice-import.md](invoice-import.md) | PDF/image extraction, vendor parsing, and draft transaction creation |
| [project-lifecycle.md](project-lifecycle.md) | Project CRUD, archiving, budget allocation, and data scope |

## Conventions

**What belongs here:** Business rules, entity definitions, data flows, invariants, formulas, sign conventions, and design decisions ("we chose X over Y because Z").

**What does NOT belong here:** Implementation-specific code (TypeScript, Swift), component names, file paths, UI layout details, or framework-specific patterns.

**When to update:** When a design decision changes — new entity relationships, new business rules, changed data flows, new edge cases. Implementation changes (refactoring, new UI components) don't require spec updates unless the underlying system behavior changes.

**When to create a new spec:** When a new system-level concept is introduced that spans multiple features or affects data model invariants.
