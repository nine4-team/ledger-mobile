# Financial Access Controls
Status: partially implemented
Last updated: 2026-06-08
Implementation plan: [../plans/financial-access-controls.md](../plans/financial-access-controls.md)

## Summary

Financial Access Controls define which account members can see company revenue
inside Ledger. The initial need is flexible fee visibility: an employee may need
to see Kitchen Fees while being blocked from other design fees and company-wide
revenue information.

This spec is the canonical product/data behavior. Keep it updated whenever the
implementation plan, Firestore rules, UI, or data model decisions change.

## Implementation Status

Implemented in the iOS app:

- `AccountMember.companyFinancialAccess`.
- `AccountMember.allowedFeeCategoryIds`.
- Role defaulting: owner/admin default to full access; employee defaults to no
  company financial access.
- Settings -> Users -> member Access sheet with Role and Financial Access.
- Limited-access fee category checklist.
- App-side filtering for account/project transactions, fee categories, invoices,
  search, review, billing summaries, and other surfaces that consume shared
  `AccountContext` / `ProjectContext` data.
- Firestore rules allow owner/admin updates to only the member role and
  financial-access fields.

Still required for full confidentiality:

- Firestore read denial for hidden fee transactions and revenue invoices. The
  current collection-wide listeners need a server/query redesign before
  restricted users can be denied hidden documents at the rules layer without
  breaking subscriptions.
- Invoice visibility metadata writers/backfill for all invoice creation/update
  paths.
- MCP/Admin-SDK financial-access filtering.

## Principles

- Role is not enough. Role controls broad account authority; financial access
  controls company revenue visibility.
- Confidentiality must be enforced by Firestore rules and server-side tools, not
  only by hiding UI.
- Restricted data fails closed. Missing or ambiguous fee category metadata is not
  visible to limited-access users.
- V1 does not support partial/redacted invoice documents. If an invoice contains
  hidden company revenue, a limited user cannot open that invoice.
- Settings should read like business access controls, not database mechanics.

## Roles

Ledger keeps the existing stored roles:

| Stored value | UI label | Meaning |
|---|---|---|
| `owner` | Owner | Account owner. Full authority by default. |
| `admin` | Admin | Account administrator. Full financial access by default unless later constrained. |
| `user` | Employee | Standard team member. No company financial access by default. |

The UI should display `user` as **Employee** in access settings.

## Company Financial Access

Each account member may have a financial access setting:

```text
companyFinancialAccess: "full" | "limited" | "none"
allowedFeeCategoryIds: string[]
```

Defaults when fields are missing:

| Role | Default companyFinancialAccess |
|---|---|
| `owner` | `full` |
| `admin` | `full` |
| `user` | `none` |

Access levels:

| Level | Behavior |
|---|---|
| `full` | Can see all company-revenue transactions, revenue invoices, billing summaries, and company-revenue reports. |
| `limited` | Can see only company-revenue transactions whose revenue category is explicitly allowed. Can open only invoices whose revenue categories are all allowed. |
| `none` | Cannot see company-revenue transactions or invoices containing company revenue. |

`allowedFeeCategoryIds` is used only for Limited access. Missing or empty means
no revenue/fee categories are visible.

## Company Revenue Visibility

A company-revenue transaction is a transaction with:

```text
type == "paymentToBusiness"
AND budgetCategoryId is a revenue/fee category
```

Rules:

- Full financial access can read every company-revenue transaction.
- Limited financial access can read a company-revenue transaction only when
  `budgetCategoryId` is included in `allowedFeeCategoryIds`.
- No financial access cannot read company-revenue transactions.
- A company-revenue transaction without `budgetCategoryId` is invalid under the
  target model; if found in legacy data, it is visible only to full-access users
  until categorized.
- Settlement transactions linked to invoices follow these rules when they carry
  company-revenue categories.

Non-company-revenue transactions remain readable to account members in v1,
subject to the existing account membership rules.

## Invoice Visibility

Invoices need visibility metadata:

```text
containsCompanyRevenue: boolean
feeCategoryIds: string[]
```

Definitions:

- `containsCompanyRevenue` is true when an invoice includes any company fee or
  manual New Charge that should be protected.
- `feeCategoryIds` is the unique set of fee category IDs represented on the
  invoice.

Rules:

- Full financial access can read every invoice.
- No financial access can read only invoices where `containsCompanyRevenue` is
  not true.
- Limited financial access can read a revenue invoice only when every ID in
  `feeCategoryIds` is allowed.
- If `containsCompanyRevenue == true` and `feeCategoryIds` is missing or empty,
  limited users cannot read the invoice.
- Mixed invoices are not partially redacted in v1. If one invoice contains
  Kitchen Fees and hidden Design Fees, a Kitchen-only employee cannot open it.

## Manual New Charge Lines

Manual New Charge invoice lines that represent company revenue need a fee
category before they can be visible to limited users.

Rules:

- New manual revenue lines should require a fee category.
- Historical manual revenue lines without a category are treated as hidden from
  limited users.
- Uncategorized manual revenue lines should appear in backfill/audit reports so
  an owner/admin can categorize them.

## Access UI

The Users area should include a member detail flow with an **Access** panel.

Recommended structure:

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

UI behavior:

- Show **Visible fee categories** only when Company financials is Limited.
- Invoice access is derived helper text in v1, not a separate setting.
- Do not expose implementation terms such as `feeCategoryIds` or
  `containsCompanyRevenue` in the UI.
- Prevent unsafe self-lockout in v1.

## Restricted Surfaces

Financial access must apply consistently to:

- Project transaction lists.
- Transaction detail screens.
- Billing tab and invoice rows.
- Invoice detail screens.
- Billing summaries and payable-to-business totals.
- Reports that include company revenue.
- Universal search.
- Review / needs-review lists.
- Exports.
- MCP tools and any Admin SDK-backed server tools.

No restricted surface should reveal hidden counts, totals, invoice numbers, or
category names in a way that implies hidden company revenue.

## Server and Tooling

Firestore rules enforce client data reads. Any server-side tool that uses Admin
SDK bypasses those rules and must apply the same financial access policy in
application code.

MCP tools must:

- Filter hidden company-revenue transactions and invoices.
- Avoid summarizing hidden totals.
- Write invoice visibility metadata when creating or updating invoices.
- Write required category metadata for manual revenue lines where possible.

## Backfill

Existing invoices and historical fee/payment transactions must be audited before
rules are fully enabled.

Backfill requirements:

- Compute `containsCompanyRevenue` and `feeCategoryIds` for every invoice.
- Identify historical fee/payment transactions missing `budgetCategoryId`.
- Identify manual revenue lines missing fee/revenue category.
- Treat unresolved revenue as full-access-only until categorized.
- Produce a report that owners/admins can use to clean up ambiguous data.

## Open Questions

- Can owners limit admin financial access, or do admins always default to full?
- Should invoices with no company revenue remain visible to employees with no
  company financial access?
- Should stored role `user` eventually be renamed to `employee`, or should this
  remain a UI-only label?
- Is account-level fee category access enough for v1, or do some clients need
  per-project overrides?
