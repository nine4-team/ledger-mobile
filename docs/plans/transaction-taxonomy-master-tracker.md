# Transaction Taxonomy Master Tracker

Created: 2026-06-29
Last updated: 2026-06-29
Status: active tracker

This is the single checklist for the transaction taxonomy, invoice settlement,
mixed-category cleanup, and returned-paid-item credit work from this session.

Detailed docs remain the source for design and implementation specifics:

- [transaction-taxonomy-system-design-recommendation.md](transaction-taxonomy-system-design-recommendation.md)
- [transaction-taxonomy-execution-plan.md](transaction-taxonomy-execution-plan.md)
- [transaction-taxonomy-migration-impact-audit.md](transaction-taxonomy-migration-impact-audit.md)
- [transaction-taxonomy-open-decisions.md](transaction-taxonomy-open-decisions.md)
- [returned-paid-item-credit-plan.md](returned-paid-item-credit-plan.md)
- [transaction-taxonomy-audit-run-2026-06-29.md](transaction-taxonomy-audit-run-2026-06-29.md)

## Status Key

- `pending` - not started.
- `in progress` - partially implemented or partially documented.
- `blocked` - needs user decision or another prerequisite.
- `review` - output exists and needs human review before writes/commit.
- `done` - complete and verified.

## Current Guardrail

Do not run production migration commits yet.

Safe now:

- code changes,
- spec updates,
- local/unit verification,
- production read-only audits,
- migration dry-runs that do not write.

Not safe yet:

- committing `scripts/migrate-transaction-taxonomy.mjs`,
- committing mixed-category/category repair,
- deleting or rewriting returned-paid-item credit transactions,
- running older migration scripts whose direction conflicts with the new target.

Specifically, do not run `scripts/migrate-transactions-to-fee-expense.mjs` for
this work. It belongs to the old migration direction.

## Locked Decisions

| Area | Decision |
| --- | --- |
| Transaction event types | Target new-write types are `purchase`, `return`, `sale`, `paymentToBusiness`. |
| `expense` | Remove as a long-term transaction type. Project-cost rows become `purchase` plus category semantics. |
| `fee` | Remove as a long-term transaction type. Existing payment rows migrate to `paymentToBusiness`; planned fees are invoice demand. |
| Itemization | Itemization belongs to budget category behavior, not transaction type. |
| Mixed categories | Not an approved product concept. Existing production rows need cleanup. |
| Every transaction category | Every transaction needs `budgetCategoryId`. |
| Manual New Charge category | Required explicitly. No default. |
| Invoice collection | Creates categorized `paymentToBusiness` transaction(s), one per settled budget category. |
| Returned paid item credit | Ordinary draft invoice manual credit lines. No synthetic credit transaction. |
| Returned credit schema | No new invoice purpose, credit reason enum, credited item field, paid invoice field, or paid invoice line field for this pass. |

## Workstream A - Returned Paid Item Credits

Owner doc: [returned-paid-item-credit-plan.md](returned-paid-item-credit-plan.md)

| Task | Status | Notes |
| --- | --- | --- |
| Update plan/specs to final no-new-schema design | done | Completed 2026-06-29. |
| Remove `appendPaidReturnCredits(...)` synthetic transaction write | done | Removed from iOS inventory operations. |
| Add deterministic returned-paid-item credit line ID helper | done | ID derived from paid invoice id, paid invoice line id, and item id. |
| Add credit context resolver from selected items + paid invoices | done | Added near invoice-line calculations. |
| Add invoice batch helper for returned paid item credit draft | done | Writes ordinary draft invoice with manual credit lines. |
| Wire `MoveToInventoryModal` | done | Modal resolves contexts from `accountContext.allInvoices`. |
| Fix direct `TransactionDetailView.returnToInventory()` path | done | Direct path now passes returned paid item credit contexts. |
| Wire inventory service methods to accept credit contexts | done | Replaced `paidInvoiceItemIds` with runtime contexts. |
| Block net-negative invoice collection from `paymentToBusiness` | done | Implemented in iOS and MCP collection paths. |
| Mirror returned-credit behavior in MCP | done | MCP return-to-inventory resolves paid invoice lines and writes draft credit invoices. |
| Add audit script for bad returned-credit transactions | done | Added `scripts/audit-returned-paid-item-credit-transactions.mjs`. |
| Add returned-credit tests | done | Added context resolver, service batch, inventory return, and collection guard tests. |

## Workstream B - Code Taxonomy Harmonization

Owner doc: [transaction-taxonomy-execution-plan.md](transaction-taxonomy-execution-plan.md)

| Task | Status | Notes |
| --- | --- | --- |
| Add/keep `paymentToBusiness` read/write support | in progress | Prior pass touched iOS and MCP; verify after final code changes. |
| Keep legacy read compatibility for `fee`, `expense`, `to inventory` | in progress | Compatibility only, not normal new writes. |
| Remove `fee` and `expense` from normal new-transaction creation | in progress | Verify UI and MCP write paths. |
| Ensure services/non-itemized costs are still `purchase` | in progress | Important: purchase is goods/services, not item-only. |
| Ensure inventory routing requires itemized category + business-paid + actual items | in progress | Prevent sell-from-inventory prompt for non-itemized transaction-only flows. |
| Remove Mixed as a category creation option | in progress | Verify iOS and MCP category tools/prompts. |
| Stop helper/display code from treating Mixed as a valid broad route | pending | Legacy tolerance only until migration. |
| Make itemized audit/completeness category-driven | pending | Must not key solely off `transaction.type == purchase`. |
| Confirm all transaction lists/cards/search render migrated legacy rows | pending | Read compatibility check. |

## Workstream C - Invoicing And Settlement

Owner docs:

- [billing-invoicing.md](../specs/billing-invoicing.md)
- [transaction-taxonomy-execution-plan.md](transaction-taxonomy-execution-plan.md)

| Task | Status | Notes |
| --- | --- | --- |
| Add `budgetCategoryId` to `InvoiceLine` model/schema | in progress | Prior pass touched iOS and MCP; verify fully. |
| Require category for manual New Charge lines | in progress | No silent default. |
| Resolve categories for item/transaction-sourced lines | in progress | Needed before collection. |
| Block invoice save/collection when selected lines lack category | pending | Especially important for older invoices/manual lines. |
| Group invoice collection by line `budgetCategoryId` | in progress | One `paymentToBusiness` per category. |
| Exclude settlement transactions from billable pools/budget spend | in progress | Verify reports and billing summary. |
| Audit invoice lines missing categories | pending | Use/read `scripts/audit-invoice-line-categories.mjs`. |

## Workstream D - Production Data Audits

Owner doc: [transaction-taxonomy-migration-impact-audit.md](transaction-taxonomy-migration-impact-audit.md)

| Task | Status | Notes |
| --- | --- | --- |
| Re-run transaction taxonomy impact audit | done | Read-only run saved 2026-06-29. |
| Re-run mixed category audit | done | Read-only run saved 2026-06-29. |
| Run invoice-line category audit | done | Read-only run saved 2026-06-29; one Assiist playground line missing category. |
| Add/run returned-credit transaction audit | done | Script added and read-only run found zero candidates. |
| Produce reviewed JSONL/CSV decision files | in progress | Dry-run JSONL exists; still needs human review before write mode. |

## Workstream E - Production Category Cleanup

Owner docs:

- [transaction-taxonomy-open-decisions.md](transaction-taxonomy-open-decisions.md)
- [transaction-taxonomy-execution-plan.md](transaction-taxonomy-execution-plan.md)

| Task | Status | Notes |
| --- | --- | --- |
| Additional Requests decision map | done | BLVD/custom artwork -> Furnishings; install work -> Install Services. |
| Kitchen decision map | done | Deni's Kitchens stays Kitchen. |
| Install decision map | done | Services/supplies/fuel/receiving split documented. |
| Align `Install Services` naming with existing category set | done | Created `Install Services`; left legacy `Install` as non-itemized expense category. |
| Decide whether to rename existing `Install` or create/split categories | done | Created `Install Supplies` and `Install Services`; split transaction targets accordingly. |
| Build category/transaction repair script or write plan | done | Added `scripts/repair-1584-install-category-blockers.mjs`; migration script patched. |
| Dry-run category cleanup | done | Dry-run logs saved before commit. |
| Commit category cleanup | done | Backups saved before category-shape cleanup; commit log saved 2026-06-29. |
| Verify no production Mixed categories remain | done | Post-cleanup audit returned 0 Mixed categories and 0 Mixed transactions. |

## Workstream F - Transaction Data Migration

Owner docs:

- [transaction-taxonomy-execution-plan.md](transaction-taxonomy-execution-plan.md)
- [transaction-taxonomy-migration-impact-audit.md](transaction-taxonomy-migration-impact-audit.md)

| Task | Status | Notes |
| --- | --- | --- |
| Confirm migration script direction matches current target | done | Script supports `--account`; future commits require `--backup`. |
| Dry-run `expense -> purchase` | done | Included in scoped 1584 dry-run. |
| Dry-run historical 1584 `fee -> paymentToBusiness` | done | Included in scoped 1584 dry-run. |
| Dry-run design-fee source cleanup | done | Included in scoped 1584 dry-run. |
| Dry-run `purchasedBy` normalization | done | Included in scoped 1584 dry-run. |
| Dry-run `reimbursementType` normalization | done | Included in scoped 1584 dry-run. |
| Inspect legacy `to inventory` row | done | Remaining row is in Assiist Biz playground dry-run. |
| Review dry-run output with user | done | User approved proceeding after backup. |
| Commit transaction migration | done | 73 scoped 1584 updates committed after backups. |
| Verify no production `expense`/`fee` rows remain except intentional legacy/playground rows | done | Scoped 1584 post-commit dry-run returned 0; all remaining candidates are Assiist Biz playground. |

## Workstream G - Specs And Cleanup

| Task | Status | Notes |
| --- | --- | --- |
| Update returned-paid-item credit specs | done | Completed 2026-06-29. |
| Mark historical credit-transaction rule as superseded | done | Completed in `billing-invoicing-v2.md`. |
| Keep active specs aligned with `paymentToBusiness` taxonomy | done | Active specs updated for category-driven itemization and paymentToBusiness. |
| Mark old migration scripts obsolete where appropriate | done | Old phase plan is paused/corrected; production commit scripts now require explicit backup files. |
| Update MCP schema/docs after implementation | done | System prompts/schema and enum docs aligned with returned paid item credits and taxonomy. |
| Update this tracker after each implementation/migration step | in progress | Updated after 1584 cleanup and code-side taxonomy pass; Assiist playground intentionally skipped. |

## Immediate Next Steps

1. Decide whether Assiist Biz playground should stay excluded permanently or get its own backed-up cleanup.
2. Review and commit the local code/scripts/docs as one or more intentional commits.
3. Run broader regression testing once Firebase auth throttling is quiet.

## Migration Commit Rule

No migration script runs in `--commit` mode until:

- code write paths stop creating `fee`, `expense`, Mixed, and synthetic returned
  credit transactions,
- read compatibility is verified,
- read-only audits have been re-run,
- dry-run output has been reviewed,
- a per-row/category decision log exists for anything ambiguous.
