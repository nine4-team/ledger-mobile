# Ledger Accounting Redesign — Program Index

Status: active design and implementation-planning control center
Created: 2026-08-31
Last updated: 2026-08-31

This directory is the central home for the coming Ledger accounting redesign.
The redesign is one coordinated release program containing several product
features and data migrations. It must not be implemented as isolated patches.

Use this file to answer:

- what belongs to the redesign;
- which specs are authoritative;
- what has been decided;
- what remains open;
- what must be implemented and in what dependency order; and
- which older documents are current-system evidence versus superseded plans.

Canonical product behavior remains in the linked specs. This directory owns
cross-feature coordination, status, sequencing, release gates, and decision
tracking.

## Program Files

- [Supabase Conversion Control Plane](conversion/README.md) — durable,
  machine-checked inventory, evidence, milestone gates, and exact resume state
  for the whole-application conversion.
- [Product Authority to Surface Audit](conversion/product-authority-audit.generated.md)
  — generated proof that all conversion surfaces resolve through reviewed
  batches to the new target specs or an explicitly technical authority set;
  current and historical specs are labeled as evidence rather than target
  authority.
- [Vertical Slice Implementation Method](conversion/vertical-slice-implementation-method.md)
  — required, machine-enforced process for tracing exact spec requirements into
  domain contracts, Postgres, RLS, PowerSync, offline behavior, app/MCP,
  migration, tests, evidence and status advancement.
- [Current Firebase Backend Contract](conversion/current-backend-contract.md) —
  static-source characterization of data paths, Auth, rules, Functions,
  Storage/media, privileged side effects, and known security/test drift.
- [Capability Evolution Method](conversion/capability-evolution-method.md) and
  [Current Capability Register](conversion/current-capability-register.md) —
  required preserve/correct/improve/redesign/retire synthesis and the complete
  service/MCP dossier queue before target mapping.
- [Redesign Architecture](../../architecture/redesign/README.md) — technical
  foundation for backend-neutral domain/application contracts, local-first
  data, Supabase/PowerSync, security, migration, and operations. This package
  does not override unresolved product decisions or authorize production
  migration.
- [Product-to-Architecture Traceability](../../architecture/redesign/product-decision-traceability.md)
  — maps every confirmed and open product decision to its architecture owner,
  target implementation surface, verification, and blocker.
- [Decision Log](decision-log.md) — confirmed decisions, derived proposals, and
  unresolved product questions.
- [Product Decision Packets](decision-packets/README.md) — reviewable senior-
  level options, recommendations, consequences, and acceptance tests for exact
  residual blockers; packets are proposals until recorded in the decision log.
- [Implementation Tracker](implementation-tracker.md) — workstreams,
  dependencies, rollout order, verification, and release gates.
- [Item Intake Handoff](item-intake-handoff.md) — raw source messages,
  provisional implementation ownership, constraints, and unresolved migration
  questions for Quick Add and Item linking.
- [Production Compatibility and Rollout Plan](production-compatibility-plan.md)
  — old-client hazards, safe additive changes, authority gates, deployment
  order, rollback, and the baseline-release prerequisite.
- [Isolated Pre-Cutover Testing Plan](pre-cutover-testing-plan.md) — legacy
  Firebase export-fixture tests, dedicated Supabase/PowerSync staging,
  production-snapshot rehearsal, destructive migration testing, and hard
  cutover rehearsal.
- [Supabase/PowerSync Vertical Spike Protocol](vertical-spike-protocol.md) —
  executable synthetic slice, Auth/optimism comparisons, physical offline fault
  matrix, scale/cost measurements, evidence layout, and strict go/no-go rules.
- [Impact Analysis](../invoice-centered-project-accounting/impact-analysis.md) —
  detailed current-code/spec impact research and migration hazards.

## Canonical Target-State Specs

| Spec | Authority | Current status |
|---|---|---|
| [Invoice-Centered Project Accounting](../../specs/invoice-centered-project-accounting.md) | Transaction/Invoicing boundary, Invoice collection, Expenses, budgets, and paid-history rules | Approved direction; open edge decisions |
| [Inventory Item Invoicing and Return Lifecycle](../../specs/inventory-item-invoicing-lifecycle.md) | Item charges/credits, sale/return stories, provenance, collection, repeat cycles | Approved direction; open credit/transfer edges |
| [Item Creation and Accounting Link](../../specs/proto-item-capture.md) | Unified Item-creation wizard, Unaccounted For/Accounted For Items, Client-paid and Business-paid Link routes, and proto compatibility | Core UX approved; target writer/schema integration pending |
| [Client Identity and Project Transfers](../../specs/client-identity-and-project-transfers.md) | Client entity, global three-type taxonomy, paired same-Client Transfer | Core and net-zero budget reallocation approved; edge decisions remain |
| [Non-Item Receipt Lines](../non-item-receipt-lines/design.md) | Physical Item versus nonphysical receipt-line completeness | Accepted direction; implementation/migration pending |

## Features in This Redesign

1. **Global Transaction taxonomy** — only Purchase, Return, and Transfer.
   Purchase/Return are interpreted relative to the scope owner; Transfer is
   project-only.
2. **Client identity** — account-scoped Client records and authoritative
   `project.clientId` replace free-text identity.
3. **Direct same-Client Transfers** — bulk Item movement between a Client's
   projects with two linked records and no Business Inventory detour.
4. **Invoice-centered project accounting** — 1584-paid project demand lives in
   Invoicing until the Client pays.
5. **Items, Expenses, and Fees in Invoicing** — distinct source records instead
   of business-paid project Transactions.
6. **Whole-Invoice collection** — one lump-sum Purchase with frozen attached
   contents; no line-level or category-split settlement.
7. **Item charge/credit lifecycle** — live repricing, pre-payment removal,
   post-payment credits, resale, and immutable paid history.
8. **Two-segment project budget progress** — client-paid plus
   invoicing/unpaid, without settlement double counting.
9. **Furnishings and Additional Requests** — Item activity remains Furnishings;
   Additional Requests is a non-additive tag/overlay.
10. **Receipt completeness** — physical Items plus embedded non-item receipt
    lines reconstruct actual purchase/return amounts without fake Items.
11. **Accounting provenance** — acquisition, current placement, open billing,
    Invoice membership, paid membership, sale/return cycles, and corrections
    become distinct relationships.
12. **Unified Item creation and Link** — one wizard puts the familiar lightweight
    capture fields first, can continue into optional detail, and creates real
    Items. Items remain Unaccounted For until connected to a client-paid
    Purchase or an open billable Item charge.
13. **Coordinated migration and hard cutover** — read-only Firebase exports,
    idempotent target imports, reconciliation, a final source write freeze,
    stale-client write recovery, target activation, and rollback controls.

## Related Current-System Specs

These documents are not the target architecture, but they contain shipped
behavior, provenance rules, or migration constraints that implementation must
preserve deliberately:

- [Billing & Invoicing](../../specs/billing-invoicing.md)
- [Inventory Movement Transactions](../../specs/sale-transactions.md)
- [Inventory as a Store](../../specs/inventory-as-store.md)
- [Correct/Move vs Sell vs Return](../../specs/reassign-vs-sell.md)
- [Lineage Tracking](../../specs/lineage-tracking.md)
- [Purchase Handling and Inventory Intent](../../specs/purchase-handling-and-inventory-intent.md)
- [Item and Expense Entry Flow](../../specs/item-entry-flow.md)
- [Budget Management](../../specs/budget-management.md)
- [Data Model](../../specs/data-model.md)
- [Reports](../../specs/reports.md)
- [Financial Access Controls](../../specs/financial-access-controls.md)
- [Returned Paid Item Credit Plan](../returned-paid-item-credit-plan.md)

## Historical or Superseded Planning

Do not implement these as the new redesign:

- [Project–Inventory Net Ledger Research](../inventory-project-net-ledger/report-source.md) — superseded one-Transaction-per-project proposal.
- [June Transaction Taxonomy Master Tracker](../transaction-taxonomy-master-tracker.md) — historical record of the `sale`/`paymentToBusiness` migration now being replaced.
- [June Transaction Taxonomy Open Decisions](../transaction-taxonomy-open-decisions.md) — historical decisions for the prior taxonomy.
- [June Transaction Taxonomy Recommendation](../transaction-taxonomy-system-design-recommendation.md) — superseded `sale`/`paymentToBusiness` target.
- [June Transaction Taxonomy Execution Plan](../transaction-taxonomy-execution-plan.md) — historical implementation/migration record.
- [June Transaction Taxonomy Impact Audit](../transaction-taxonomy-migration-impact-audit.md) — evidence only; its proposed target is superseded.
- [Earlier Transaction Type Migration](../transaction-type-migration.md) — paused and superseded migration direction.
- [Invoice Transaction Redesign Draft](../../specs/invoice-transaction-redesign-draft.md) — superseded July design.
- [Invoice Redesign Change Plan](../../specs/invoice-redesign-change-plan.md) — superseded companion plan.
- [Billing & Invoicing v2](../../specs/billing-invoicing-v2.md) — historical shipped model.

Historical production audits and migrations remain evidence. “Superseded” means
their proposed future design is not authority; it does not mean deleting their
audit trail or undoing verified production repairs blindly.

## Program Status

| Area | Status |
|---|---|
| Central product model | In progress; core boundary approved |
| Global Purchase/Return/Transfer taxonomy | Confirmed 2026-08-31 |
| Client identity and Transfer eligibility | Confirmed |
| Transfer budget reallocation | Confirmed 2026-08-31 |
| Unified Item wizard and Unaccounted For/Accounted For model | Confirmed 2026-08-31 |
| Item Link target writer/schema | Design; depends on occurrence and Invoicing sources |
| Legacy proto-item compatibility | Existing Firebase behavior remains functional until hard cutover; the target version never creates proto items |
| Production compatibility audit | Initial code/rules/Functions/MCP/branch audit complete; release gates documented |
| Isolated staging and migration rehearsal | Required; current repository has emulator support but no cloud staging configuration |
| Transfer Invoice/tag/Space/correction edges | Needs product confirmation |
| Open-decision design | Sixteen proposed packets cover all 35 product blockers and all 157 product-dependent residual surfaces; O-021 is UI-only; no packet is approved yet |
| Paid-credit/refund closure | Proposed combined packet; needs product approval |
| Target data schema | Not finalized |
| Symbol-level implementation plan | Scaffolded; expands after open decisions |
| Application implementation | Not started as this program |
| Production migration | Not authorized |
| Release/cutover | Not scheduled |

## Implementation Guardrail

No broad enum replacement, destructive schema cleanup, production migration, or
authority cutover is authorized merely because these documents exist.

Safe before the design gate closes:

- specs and decision work;
- read-only production audits;
- target-only prototypes in isolated Supabase/PowerSync environments;
- symbol-level planning and tests that describe the target; and
- reconciliation tooling that does not mutate production.

Implementation begins from [Implementation Tracker](implementation-tracker.md),
not from an older individual plan. Production writes require reviewed dry runs,
backups, compatibility verification, and an explicit cutover phase.

## Definition of Program Completion

The redesign is complete only when:

- all target writers use the global three-value taxonomy;
- every active project has authoritative Client identity;
- same-Client Transfer is atomic and cannot cross Clients;
- project Transactions, Invoicing, Invoices, Items, Expenses, Fees, and budgets
  obey one reconciled accounting model;
- Unaccounted For Items can be linked through either approved payer route without
  duplicating the physical Item or manufacturing a project movement
  Transaction;
- paid history and repeated Item cycles remain auditable;
- iOS, MCP, Functions, rules, reports, search, exports, and production data agree;
- stale clients cannot recreate retired shapes;
- migration reconciliation reports zero unexplained differences; and
- release, rollback, and post-release monitoring have been completed.
