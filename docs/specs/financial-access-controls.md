# Financial Access Controls

> **Target-state notice (2026-08-30):** Transaction visibility rules must migrate
> to the Purchase/Return/Transfer taxonomy in
> [Client Identity and Project Transfers](client-identity-and-project-transfers.md).
> Fee and Expense visibility must follow their Invoicing source records rather
> than legacy Transaction types. The existing rules below describe the current
> schema until that migration.
>
> The visibility intent and no-leak requirements remain target obligations.
> Firestore listeners, rules, Admin SDK filtering and backfill below are source
> implementation evidence, not instructions to build new Firebase behavior.
> Target enforcement must cover Postgres reads/commands, PowerSync downloads,
> protected local data, private media, reports and MCP; hiding UI is insufficient.
> The `paymentToBusiness` classifier must not be recreated in the target.
> How mixed collected Purchases and their frozen allocations inherit Invoice
> confidentiality is unresolved: do not expose hidden Fees through payment
> totals or invent partial-redaction policy. Offline access/revocation follows
> the separately gated authorization policy.
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

The following implementation status is the shipped Firebase baseline only.
It is not a target authorization or rollout plan.

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

## Target Visibility and Management Contract

Preserve full/limited/none financial access and the existing missing-field role
defaults as migration evidence. Restricted Fee/manual-revenue data requires
explicit authorization; unknown or incomplete source classification cannot be
treated as non-revenue. Target classification follows canonical Invoicing
sources and frozen accounting evidence, not `paymentToBusiness`. Ordinary
business-paid Expenses are not automatically company revenue.

Invoices remain whole documents: one hidden protected Fee prevents the
restricted user from opening the Invoice; no partial Invoice redaction is
approved. The complete target visibility matrix—including mixed collected
Purchases, downstream evidence and the existing no-revenue-Invoice question—is
O-060. O-009 separately owns whether/how manual adjustments exist.

The same policy applies before server reads, sync downloads, local projections,
private-media access, search/review, summaries, reports/exports and MCP. No hidden
count, total, Invoice number, category name or financial provenance may leak
through a less-protected path. A partial local working set is not proof that
there is no hidden revenue. Access reductions stop newly unauthorized server
reads/downloads; existing offline caches and retained pending work follow
O-058/A-016, not a promise of immediate disconnected revocation or automatic
destructive cleanup.

Preserve the member directory's name/email and role/access badges; Access sheet
Role and Financial Access controls; Limited-only Fee-category checklist;
derived Invoice explanation; and Save, progress, failure, Cancel and empty
states. A save binds the exact member and observed revision and applies the
approved role/access settings together, not independent partial updates.
Unapproved or stale changes fail visibly without closing the editor as success.

Preserve Invite's email validation, Employee/Admin choices, financial-access
options and Limited checklist; pending invitations with Copy Link and confirmed
Revoke; and send/revoke progress and failures. Do not reproduce the source's
immediate dismiss/silent failed writes. Invitation acceptance inherits only the
intended approved grant and follows the target authentication contract.

O-059 owns who may view/manage members/invites, grant ownership, edit another
Owner/Admin, change their own access, and alter the last Owner; allowed role/
access combinations and online-only versus queued permission changes are not
implied by the old UI or Firestore rules. Keep failures explicit rather than
silently coercing access on role change. Archived Fee IDs must remain
resolvable for history; merely opening or saving a picker must not silently
remove a previously allowed ID. Whether/how those archived grants continue to
authorize historical amounts is part of O-060.

Migration preserves exact member/invite grants and original source evidence,
derives complete visibility classification for imported Fees/Invoices and
frozen accounting references, and reports unresolved classifications for
authorized review. Missing revenue metadata stays full-access-only until
resolved, never inferred public from a missing linked source. Idempotent import
must not broaden a grant or duplicate invitations. No production backfill is
authorized by this spec.

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
- How does a collected Purchase containing both visible costs and hidden Fees
  inherit its Invoice's whole-document visibility, including frozen allocations,
  linked Item provenance, refunds and Transfer/report summaries? The old
  single-category payment classifier does not answer this target question.
- How are existing device caches and retained pending work handled after a
  financial-access reduction? Enforce current server/download permissions, but
  do not invent an offline lease or destructive local-data policy.
