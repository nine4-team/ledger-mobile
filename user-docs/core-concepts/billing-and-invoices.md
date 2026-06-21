# Billing And Invoices

Billing is where Ledger tracks what should be requested from a client and what has already been collected.

## Transaction Versus Invoice

The key distinction:

- **Transaction**: money actually moved.
- **Invoice**: money is being requested.

Do not create a transaction for a future payment. Use an invoice line for the request, then create or link a transaction when the money is collected.

## Invoice Lines

An invoice can include:

- Items.
- Existing billable transactions.
- Credits.
- Manual New Charges, such as a design fee, retainer, or project management fee.

Invoice lines can be charges or credits, so one invoice can show both money owed to the business and money credited back to the client.

## Invoice Statuses

Invoices can be:

- Draft.
- Sent.
- Paid.
- Voided.

A draft is editable. A sent invoice is the issued version. A paid invoice means the demand has been settled. A voided invoice is withdrawn.

## Billing Pipeline

The project Billing area groups billable records into:

- **Available**: not yet on an invoice.
- **Invoiced**: on a sent invoice.
- **Paid**: on a paid invoice.

## Related

- [Create an Invoice](../workflows/create-an-invoice.md)
- [Invoice Statuses](../reference/invoice-statuses.md)
- [Transactions](transactions.md)
- [Budgets](budgets.md)
