# Financial Access Controls — Implementation Plan

**Status:** Partially implemented
**Created:** 2026-06-08
**Spec:** [../specs/financial-access-controls.md](../specs/financial-access-controls.md)
**Related:** [../specs/billing-invoicing.md](../specs/billing-invoicing.md), [billing-invoicing-canonical-implementation.md](billing-invoicing-canonical-implementation.md)

## Summary

Add member-specific financial visibility so an employee can see only approved
company revenue categories, such as Kitchen Fees, without seeing other design
fees, settlement transactions, invoices, reports, or exports that reveal hidden
company revenue.

The spec is the canonical behavior reference. Keep
[../specs/financial-access-controls.md](../specs/financial-access-controls.md)
updated alongside this plan whenever field names, defaults, UI wording, rules,
or scope decisions change.

The first version should be intentionally conservative:

- Owners/admins keep full company financial access by default.
- Employees can be granted full, limited, or no company financial access.
- Limited access means a checklist of allowed fee categories.
- A restricted user can open an invoice only when every fee category on that
  invoice is allowed for that user.
- Redacted invoice views are out of scope for v1.

## Implementation Snapshot — 2026-06-08

Completed:

- Added iOS data model fields for member financial access.
- Added shared iOS `FinancialAccessPolicy`.
- Added Settings -> Users -> member Access sheet.
- Added save path for role/financial access updates.
- Filtered shared account/project transactions, fee categories, and invoices in
  app state.
- Added Firestore rules allowing owner/admin updates to only the access fields.
- Added Swift policy tests and Firestore rules tests.

Still open:

- Replace collection-wide reads with rule-compatible restricted queries or a
  server-mediated read path so hidden fee docs are denied by Firestore rules.
- Write/backfill invoice metadata (`containsCompanyRevenue`, `feeCategoryIds`)
  everywhere invoices are created or changed.
- Apply the same policy to MCP/Admin-SDK tools.

## Goals

- Add an **Access → Financial Access** sub-panel for each account member.
- Let account owners/admins grant an employee access to selected fee categories.
- Prevent restricted users from reading hidden fee transactions or hidden-fee
  invoices through Firestore, not just through UI hiding.
- Keep the mental model simple: role controls broad account authority; financial
  access controls company revenue visibility.
- Make restricted data fail closed when category metadata is missing.

## Non-Goals

- Project-level access controls.
- Field-level redaction inside a single invoice document.
- Client-facing invoice portal permissions.
- Payroll, salary, profitability, or margin permissions beyond fee/invoice
  visibility.
- A general policy engine. Use simple fields and helpers until real complexity
  appears.

## Current State

- Account membership already has `role: owner | admin | user`.
- The current app loads `AccountContext.member` and uses role for some UI gates.
- Firestore rules currently allow every account member to read core account data,
  including all transactions and all invoices.
- Billing, reports, search, review, and exports can reveal fee amounts through
  shared transaction/invoice subscriptions.
- Fee transactions are identifiable as `type == "fee"`.
- Invoice settlement transactions are created as fee transactions with
  `settlementInvoiceId`.
- Invoice documents can contain manual New Charge lines. Some manual lines may
  not currently carry enough category metadata to decide visibility safely.

## Data Model

### Account Member

Stored at `accounts/{accountId}/users/{uid}`.

Add:

```text
companyFinancialAccess: "full" | "limited" | "none"
allowedFeeCategoryIds: string[]
```

Semantics:

- `full`: can read all fee transactions, all invoices, billing summaries, and
  company-revenue reports.
- `limited`: can read fee transactions whose `budgetCategoryId` is in
  `allowedFeeCategoryIds`; can read invoices only when all invoice fee category
  IDs are allowed.
- `none`: cannot read fee transactions or invoices containing company revenue.

Default policy:

- `owner` and `admin`: treat missing `companyFinancialAccess` as `full`.
- `user`: treat missing `companyFinancialAccess` as `none`.
- Missing `allowedFeeCategoryIds` is an empty list.

Do not rely only on role for long-term access. Role is the default; explicit
financial access can override the default.

### Transactions

Existing field:

```text
type: "fee" | "expense" | "purchase" | "return" | "sale"
budgetCategoryId: string?
settlementInvoiceId: string?
```

Rules:

- Non-fee transactions remain readable to account members in v1.
- Fee transactions require company financial access.
- A fee transaction without `budgetCategoryId` is hidden from limited users.
- Settlement transactions are fee transactions and follow the same rule.

Optional additive metadata, if needed for simpler readers:

```text
containsCompanyRevenue: true
financialCategoryIds: string[]
```

This is not required if `type` and `budgetCategoryId` are reliable enough for
all fee transactions.

### Invoices

Add denormalized visibility metadata:

```text
feeCategoryIds: string[]
containsCompanyRevenue: boolean
```

Semantics:

- `feeCategoryIds` is the set of fee category IDs represented by invoice lines.
- `containsCompanyRevenue` is true when an invoice includes any company fee or
  manual New Charge that should be protected.
- Missing `feeCategoryIds` on a revenue invoice should fail closed for limited
  users.

Rules:

- `full` can read all invoices.
- `none` can read only invoices where `containsCompanyRevenue != true`.
- `limited` can read invoices only when every ID in `feeCategoryIds` is allowed.
- If `containsCompanyRevenue == true` and `feeCategoryIds` is missing or empty,
  limited users cannot read it.

Manual New Charge lines need category assignment before they can be visible to
limited users. Existing uncategorized manual lines should remain hidden until
categorized or backfilled.

## Access UI

Add a member detail flow under Settings → Users.

Panel layout:

```text
Access
  Role
    Owner
    Admin
    Employee

  Financial Access
    Company financials
      Full access
      Limited access
      No access

    Visible fee categories
      [x] Kitchen Fees
      [ ] Design Fees
      [ ] Procurement Fees
      [ ] Project Management Fees

    Invoice access
      This user can only open invoices where every fee line is in an allowed
      category.
```

UI rules:

- Show the fee-category checklist only when Company financials is Limited.
- The invoice text is derived helper text, not a separate v1 setting.
- Owners should not be allowed to remove their own full financial access in v1.
- Only owners/admins can edit member access. If that is too broad later, narrow
  it to owners only.

Terminology:

- Use **Employee** in UI for the existing `user` role.
- Use **Company financials** for the access setting.
- Use **Visible fee categories** for the category checklist.

## Firestore Rules

Add helper functions:

```text
member(accountId)
memberRole(accountId)
companyFinancialAccess(accountId)
allowedFeeCategoryIds(accountId)
hasFullFinancialAccess(accountId)
canReadFeeCategory(accountId, categoryId)
canReadFeeTransaction(accountId)
canReadInvoice(accountId)
```

Important constraints:

- Rules must enforce confidentiality. UI filtering is only a convenience layer.
- Firestore rules cannot return partial documents. Do not attempt redacted
  invoices in v1.
- Rules can test membership in small arrays, but query shape must remain valid.
  Add rule tests for every query path the app uses.

Potential rule shape:

```text
transactions read:
  account member AND (
    resource.data.type != "fee"
    OR full financial access
    OR limited access AND resource.data.budgetCategoryId in allowedFeeCategoryIds
  )

invoices read:
  account member AND (
    containsCompanyRevenue != true
    OR full financial access
    OR limited access AND invoice feeCategoryIds are all allowed
  )
```

If Firestore rules cannot express "all invoice feeCategoryIds are allowed" with
the final data shape, use a denormalized string visibility key instead:

```text
financialVisibilityKey: "full" | "none" | "feeCategory:<categoryId>" | "mixed"
```

For v1, mixed hidden/visible fee invoices should be unreadable to limited users.

## iOS Reader Changes

Add a central helper, for example `FinancialAccessPolicy`, with pure functions:

```text
canViewCompanyFinancials(member)
canViewFeeCategory(member, categoryId)
canViewTransaction(member, transaction)
canViewInvoice(member, invoice)
visibleTransactions(member, transactions)
visibleInvoices(member, invoices)
```

Use the helper everywhere rather than scattering role checks.

Convert these surfaces:

1. Account-wide subscriptions / state assignment:
   - Filter or avoid assigning hidden transactions and invoices.
   - Be aware that server-side denied reads may require query splitting.
2. Project transaction lists and transaction detail.
3. Billing sub-tab:
   - Hide Create Invoice and invoice rows when access is insufficient.
   - Hide Billing entirely when Company financials is None, unless there are
     non-revenue billing surfaces that remain safe.
4. Billing pipeline and billing summary cards.
5. Reports:
   - Hide invoice report and payable-to-business totals for restricted users.
   - Client summary/property-management reports must not include hidden fee data.
6. Universal search.
7. Review list / needs-review transactions.
8. Transaction export.
9. MCP-facing local assumptions, if the app exposes user-driven MCP operations.

Empty states:

- Prefer neutral wording such as "No visible invoices" or "You do not have
  access to company financials for this account."
- Do not reveal that hidden fee invoices exist by count or total.

## Writers

Update all invoice write paths to populate `feeCategoryIds` and
`containsCompanyRevenue`:

- iOS invoice creation/update.
- Mark Sent.
- Mark Collected.
- MCP invoice tools.
- Contract setup tooling that creates manual design-fee lines.
- Backfill script for historical invoices.

Update transaction write paths as needed:

- Ensure every new fee transaction has a `budgetCategoryId`.
- If a fee truly has no category, it should be visible only to full-access users.
- Settlement transactions should inherit the fee category from the collected
  invoice line/category when possible.

Manual invoice lines:

- Add category selection for manual New Charge lines, or add a separate
  `feeCategoryId` field on invoice lines.
- Treat uncategorized manual revenue lines as restricted.

## MCP Server

The MCP server currently resolves account membership and role, but uses Admin SDK
data access. That bypasses Firestore rules, so tools need explicit filtering.

Plan:

- Add financial access to the auth/session context.
- Filter `list_transactions`, `get_transaction`, search, analytics, invoices,
  and billing tools using the same policy.
- Mutating tools that create fee transactions or invoices must write visibility
  metadata.
- Tools should never summarize hidden invoice totals or hidden fee categories.

## Backfill

Create an idempotent script:

```text
scripts/backfill-financial-visibility.mjs
```

Tasks:

1. For every invoice, compute `containsCompanyRevenue` and `feeCategoryIds`.
2. For transaction-backed invoice lines, read the source transaction category.
3. For manual lines, use stored line category if present.
4. If a manual revenue line has no category, set `containsCompanyRevenue: true`
   and leave it hidden from limited users until categorized.
5. Produce an audit report:
   - total invoices scanned
   - invoices with company revenue
   - invoices with uncategorized revenue
   - invoices with multiple fee categories
   - fee transactions missing category

Run order:

1. Emulator / seed data.
2. Production dry run.
3. Production write after export/backup.

## Tests

### Firestore Rules

Add tests for:

- Owner can read all transactions and invoices.
- Admin can read all transactions and invoices by default.
- User with missing financial access cannot read fee transactions.
- User with no access cannot read fee transactions or revenue invoices.
- User with limited Kitchen access can read Kitchen fee transactions.
- User with limited Kitchen access cannot read Design fee transactions.
- User with limited Kitchen access can read Kitchen-only invoices.
- User with limited Kitchen access cannot read mixed Kitchen + Design invoices.
- User with limited Kitchen access cannot read uncategorized revenue invoices.
- Non-fee transactions remain readable.
- Queries used by iOS do not fail because of rule/query mismatch.

### iOS Unit Tests

Add tests for `FinancialAccessPolicy`:

- Role defaults.
- Explicit full/limited/none access.
- Missing category fail-closed behavior.
- Invoice visibility across no-revenue, single allowed category, hidden category,
  mixed categories, and missing metadata.

### UI / Integration Smoke Tests

- Employee with Kitchen-only access:
  - Sees Kitchen fees.
  - Does not see other design fees in project transactions, search, review, or
    export.
  - Can open Kitchen-only invoice.
  - Cannot open mixed/hidden-fee invoice.
  - Does not see payable-to-business totals derived from hidden fees.

## Status

| Phase | Status |
|---|---|
| Phase 0 — confirm policy and field names | Draft |
| Phase 1 — additive models and policy helper | Not started |
| Phase 2 — write invoice/transaction visibility metadata | Not started |
| Phase 3 — Firestore rules and rule tests | Not started |
| Phase 4 — iOS Access UI | Not started |
| Phase 5 — iOS reader filtering and hidden states | Not started |
| Phase 6 — MCP filtering and writer updates | Not started |
| Phase 7 — backfill and production audit | Not started |

## Phase 0 — Confirm Policy and Field Names

Decisions to lock before implementation:

1. Final stored field names:
   - `companyFinancialAccess`
   - `allowedFeeCategoryIds`
   - `feeCategoryIds`
   - `containsCompanyRevenue`
2. UI role label:
   - Existing raw `user` displays as **Employee**.
3. Admin default:
   - Recommended: admins default to full company financial access.
4. Manual fee category:
   - Recommended: manual New Charge lines must carry a fee category before they
     can be visible to limited users.
5. Mixed invoices:
   - Recommended v1 behavior: unreadable to limited users unless every fee
     category is allowed.

**Ship gate:** decisions recorded in this plan.

## Phase 1 — Additive Models and Policy Helper

Scope: no behavior change.

1. Add Swift enum for `CompanyFinancialAccess`.
2. Add fields to `AccountMember`.
3. Add fields to `Invoice`.
4. Add optional fee category metadata to `InvoiceLine` if needed for manual
   line categorization.
5. Add `FinancialAccessPolicy` pure helper.
6. Add unit tests for policy helper.
7. Mirror relevant types in MCP TypeScript.

**Ship gate:** app and MCP build; tests pass; existing data decodes.

## Phase 2 — Visibility Metadata Writers

Scope: new and edited invoices write the metadata needed by rules.

1. Update invoice create/update/mark sent to compute invoice financial metadata.
2. Update mark collected to ensure settlement fee transaction carries a category.
3. Update Create Invoice UI so manual New Charge lines can be categorized.
4. Update MCP invoice tools and contract setup tools.
5. Add focused service tests.

**Ship gate:** newly created invoices have correct visibility metadata.

## Phase 3 — Firestore Rules and Rule Tests

Scope: enforce confidentiality at the data layer.

1. Add member financial access helper functions.
2. Update transaction read rule for fee transactions.
3. Update invoice read rule for revenue invoices.
4. Keep non-fee app data readable to account members.
5. Update `firebase/firestore.test.rules`.
6. Add rule tests for the matrix above.

**Ship gate:** restricted users cannot read hidden data with direct Firestore
reads or app query shapes.

## Phase 4 — Access UI

Scope: owner/admin can configure member access.

1. Add member detail / Access panel under Users.
2. Add Role section.
3. Add Financial Access section.
4. Add fee category checklist for Limited access.
5. Wire writes through an appropriate service or callable function.
6. Prevent unsafe self-lockout.

**Ship gate:** owner/admin can grant Kitchen-only access to an employee.

## Phase 5 — iOS Reader Filtering

Scope: all app surfaces respect the policy and avoid confusing errors.

1. Apply `FinancialAccessPolicy` to account/project transaction state.
2. Apply policy to invoices and billing summaries.
3. Hide or simplify Billing and Reports for restricted users.
4. Filter search, review, and export.
5. Add neutral empty states.
6. Smoke test owner/admin and restricted employee accounts.

**Ship gate:** restricted employee cannot see hidden fees or inferred totals in
normal app usage.

## Phase 6 — MCP Filtering

Scope: MCP tools honor the same member-specific visibility.

1. Extend auth context with financial access.
2. Filter read tools.
3. Update write tools to populate metadata.
4. Add MCP tests where practical.

**Ship gate:** MCP cannot reveal hidden fee data for restricted users.

## Phase 7 — Backfill and Production Audit

Scope: existing data becomes rule-compatible.

1. Build dry-run audit.
2. Categorize or flag uncategorized manual revenue lines.
3. Backfill invoice metadata.
4. Verify all fee transactions have categories or are intentionally full-only.
5. Run production after backup.

**Ship gate:** all production invoices have visibility metadata; restricted
rules can be enabled without breaking legitimate reads.

## Risks

- **Firestore rule/query mismatch.** Broad list queries may fail if rules cannot
  prove every returned document is readable. Mitigation: split queries or store
  query-friendly visibility fields.
- **Mixed invoices.** Users may expect to see the Kitchen part of a mixed
  invoice. V1 blocks the whole invoice; redaction can be a future feature.
- **Uncategorized manual lines.** Missing category data must fail closed, which
  may hide more than expected until backfill/categorization is done.
- **Derived totals.** Even if a hidden transaction is filtered, reports and
  summaries can leak totals. All aggregate paths need review.
- **MCP/Admin SDK bypass.** Firestore rules do not protect Admin SDK reads. MCP
  must apply the same policy explicitly.

## Open Questions

- Should admins always have full company financial access, or can owners limit
  admins too?
- Should `user` be renamed to `employee` in stored data later, or only in UI?
- Should invoices with no company revenue remain visible to users with no
  financial access?
- Should manual New Charge lines require a fee category at creation time, or can
  they be saved as uncategorized and hidden from limited users?
- Do we need per-project fee-category overrides, or are account fee categories
  enough for v1?
