# Payments — Design Spec (Proposed)

**Status:** proposed, not yet implemented. See [../plans/payments-array-migration.md](../plans/payments-array-migration.md) for rollout.

Replaces the single `paymentMethod: string` on Transaction with a `payments: [Payment]` array. A Payment pairs a payment instrument with the amount that went on it. A normal purchase is a list of one. A split-payment purchase (gift card + card, multiple cards, cash + card) is a list of multiple, with amounts summing to the transaction total.

## Why

Today, Transaction.paymentMethod is a single string. There's no way to express that a $370.45 TJX purchase was paid as $36.83 on a gift card plus $333.62 on Amex. Receipts where this matters:

- In-store retail (TJX, HomeGoods, Target) — gift cards are routine.
- Vendor credits and refunds applied at checkout.
- Multi-card purchases (rare but real).

The email-receipt pipeline runs into this on every TJX in-store receipt. Without a structured representation, either the gift-card portion gets dropped or the whole thing is jammed into a free-text string and lost to search/filter.

## Data shape

### Payment

```
Payment {
  method: string         // e.g. "Amex …2008", "Gift Card …3466", "Cash", "Check #1234"
  amountCents: integer   // positive
}
```

No separate `id`. Order in the array carries no meaning — readers should not depend on it.

### Transaction.payments

```
payments: Payment[]      // length >= 1 when set
```

**Invariants:**

- `sum(payments[i].amountCents) == transaction.amountCents`. Validation runs on every write that touches `payments` or `amountCents`.
- `payments` length >= 1 when the field is set. Empty array is invalid; use null/missing instead.
- A Transaction with `amountCents` set should have `payments` set. (Enforced for new writes after Phase 4 below; see migration plan for the transition.)

### Display rules

- **Single-payment transactions** (`payments.length == 1`) display the same as today: one method, e.g. "Amex …2008".
- **Split-payment transactions** display all methods. The default summary string is `"<method1> + <method2> + …"`, e.g. "Gift Card …3466 + Amex …2008". Detail views show the per-method amounts.
- The transaction list, detail view, and reports all use the same display helper so behavior is consistent.

### Search / project matching

The email pipeline matches receipts to projects partly by card last-4 in project notes. Today it reads `paymentMethod`. Under the new shape it reads every `payments[i].method` — any match wins.

This means a $370.45 TJX purchase with a gift card and an Amex matches a project whose notes mention either the gift-card last-4 or the Amex last-4. The gift card is rarely the match signal (gift cards are project-agnostic), but the structure preserves the option.

## Relationship to existing fields

`paymentMethod` (the legacy single string) is retained during the transition. See migration plan. After Phase 4, it is derived from `payments` for backwards-compat read paths and not directly written.

`amountCents` is unchanged in meaning — total of the transaction, always positive. The new constraint is just that `sum(payments) == amountCents`.

`subtotalCents`, `taxRatePct`, `transactionType`, etc. are unaffected.

## Edge cases

- **Refunds (`type: "Return"`).** Same shape. A return to a single card is `payments: [{method: "Amex …2008", amountCents: 8669}]`. A return that was split across the original tenders mirrors the original.
- **Returns to inventory (`type: "Return"`, `source: "Business Inventory"`).** Often have `paymentMethod: null` today (no money moves). `payments` should be null/missing for these too — they're not financial events in the same sense.
- **Cash purchases.** `payments: [{method: "Cash", amountCents: …}]`. No last-4. Unchanged from today.
- **Unknown payment method.** `payments` may be missing entirely. The transaction is still valid; just incomplete. Consistent with how `paymentMethod: null` works today.
- **Editing.** Mutating `payments` after creation is allowed (it's not a frozen field on the immutable transaction types — see [data-model.md §Sale and Return-to-Inventory Immutability](data-model.md)). Edits must preserve the sum invariant.

## What this does NOT change

- The transaction taxonomy (Purchase / Return / Sale / Fee / Expense).
- Any budget calculation. Sums and category totals are still based on `amountCents`.
- The lineage / item / scope model.
- Reports.

The change is local to how a single field on Transaction is shaped.
