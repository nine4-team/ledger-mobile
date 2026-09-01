# Non-Item Receipt Lines

Status: accepted design direction; implementation and migration pending; no production mutation authorized by this document  
Date: 2026-08-30
Program tracker: [Ledger Accounting Redesign](../ledger-accounting-redesign/README.md)

## Problem

An itemized transaction can contain receipt lines that affect the receipt total
but do not represent physical inventory. Current examples include shipping,
delivery, return protection, warranties, installation labor, discounts,
promotional credits, and return-shipping deductions.

Ledger currently has only two ways to make these amounts participate in
transaction completeness:

1. create an `Item`, which pollutes physical inventory, spaces, item counts,
   item search, pricing automation, and the invoice pool; or
2. use the transaction-level `discount` object, which represents only one
   positive discount magnitude and cannot express additions, multiple source
   lines, or named credits.

The current completeness equation is:

```text
item total - transaction discount = resolved subtotal
```

This schema makes fake items a predictable outcome. The MCP reconciliation
guidance currently recommends adding/removing items when the equation does not
balance.

## Decision

Add an embedded `NonItemReceiptLine` value to `Transaction`. This is not a new
top-level Firestore collection, a new transaction type, or an item subtype.

Product language:

- Model: `NonItemReceiptLine`
- Transaction field: `nonItemReceiptLines`
- UI section: **Other receipt lines**

The word "item" remains reserved for physical, trackable inventory.

## Coordinated revision

This is one accounting-model revision with several inseparable changes:

1. Add embedded non-item receipt lines for every nonphysical amount printed on
   a receipt.
2. Reconcile itemized vendor transactions against the final transaction amount,
   not a pre-tax subtotal.
3. Represent tax and tax refunds as ordinary non-item receipt lines; do not add
   `taxCents`.
4. Replace the special transaction `discount` object with one or more decrease
   lines.
5. Stop requiring or inferring vendor-receipt completeness from
   `subtotalCents` and `taxRatePct`.
6. Replace the percentage tolerance with exact cent arithmetic and, at most, a
   one-cent source-rounding tolerance.
7. Keep generated inventory-movement subtotal and Item tax-rate mechanics
   unchanged until that subsystem receives its own design.

These changes must not be implemented independently. Adding receipt lines while
leaving subtotal-based completeness would preserve the current incentive to
create fake Items. Changing completeness without migrating tax, discounts, and
other receipt lines would make correctly recorded transactions incomplete.

This revision does not change:

- the meaning of `amountCents` as the final transaction amount;
- the rule that `Item` means a physical, trackable object;
- category-driven itemization or Purchase/Return transaction types;
- inventory lineage and historical item membership; or
- whether a vendor cost is billable to a client.

The remaining product decisions are limited to billability, whether a
receipt-authored one-cent discrepancy should use tolerance or an explicit
rounding line, and how transaction-to-Item tax-rate inheritance should work.

## Canonical shape

```swift
enum NonItemReceiptLineEffect: String, Codable {
    case increase
    case decrease
}

struct NonItemReceiptLine: Codable, Hashable, Identifiable {
    var id: String
    var description: String
    var amountCents: Int
    var effect: NonItemReceiptLineEffect
    var quantity: Int?
}

struct Transaction {
    // Existing fields...
    var nonItemReceiptLines: [NonItemReceiptLine]?
}
```

Rules:

- `id` is a stable UUID used for editing, migration, and downstream references.
- `description` preserves the source receipt's wording.
- Array order preserves source receipt order; do not add a separate sort field.
- `amountCents` is a positive line-total magnitude.
- `effect` is relative to the transaction's final amount: `increase` adds and
  `decrease` subtracts. This remains unambiguous for both Purchases and Returns.
- `quantity` is optional source evidence. `amountCents` remains authoritative;
  the model does not require `amountCents == quantity * unit price` because
  receipts can round or adjust at line level.
- Do not add a closed shipping/warranty/discount taxonomy in v1. The source
  description is authoritative, and an early enum would create unnecessary
  classification work.
- Tax is not a special transaction amount. When a receipt includes tax, record
  the printed tax or tax refund as another non-item receipt line. Transactions
  without tax simply have no tax line.
- Empty descriptions, zero/negative magnitudes, and duplicate IDs are invalid.

Examples:

```json
[
  {
    "id": "...",
    "description": "Shipping",
    "amountCents": 3900,
    "effect": "increase"
  },
  {
    "id": "...",
    "description": "Promotional discount",
    "amountCents": 15000,
    "effect": "decrease"
  },
  {
    "id": "...",
    "description": "5 Year Appliance Warranty",
    "quantity": 4,
    "amountCents": 72000,
    "effect": "increase"
  },
  {
    "id": "...",
    "description": "Sales Tax",
    "amountCents": 30878,
    "effect": "increase"
  }
]
```

## Accounting and completeness

Completeness should answer one question: can Ledger reconstruct every cent of
the transaction's final amount from the physical Items and the other receipt
lines?

Define:

```text
increase total = sum(non-item lines where effect == increase)
decrease total = sum(non-item lines where effect == decrease)
receipt-line net = increase total - decrease total
reconstructed total = physical item total + receipt-line net
variance = reconstructed total - amountCents
```

Completeness no longer depends on `subtotalCents`, `taxRatePct`, the order in
which a vendor applied a modifier, or reconstructing the vendor's taxable base.
It uses the receipt's actual line amounts.

For physical Items, retain the existing audit price-basis and historical
membership behavior: sum currently linked Items plus qualifying returned/sold
lineage Items using the same purchase-price versus project-price rules already
used by trusted completeness. This design changes which receipt amounts join
that item total; it does not rewrite inventory lineage.

The current 1% tolerance must not survive this change. A missing $29 BLVD Home
delivery fee fell within that tolerance and was marked complete. Prefer exact
equality, with a maximum one-cent tolerance only where source receipt arithmetic
itself differs by a cent. The audit panel and MCP must always display the exact
residual.

Persist these audit fields:

- `itemsSumCents`
- `nonItemReceiptLineIncreaseCents`
- `nonItemReceiptLineDecreaseCents`
- `nonItemReceiptLineNetCents`
- `reconstructedTotalCents`
- `varianceCents`

Remove `discountCents` after migration. Remove `Transaction.discount` entirely
from the canonical model and all write contracts.

### Tax and subtotal are not completeness inputs

Tax is an ordinary non-item receipt line:

- `Sales Tax`, increase on a Purchase;
- `Tax Refund`, increase in the magnitude of a Return refund; or
- no line when the transaction has no tax.

This avoids making an optional receipt component special and handles multiple
printed tax lines without adding more transaction-level aggregate fields.

The same receipts prove that Ledger should not infer tax from a single subtotal
and rate:

- Wallism includes $39 shipping in its displayed $917.22 subtotal but computes
  $59.28 tax from the $878.22 merchandise amount only.
- Revival Rugs includes $12.99 Returns Protection in the taxable subtotal.
- West Elm includes its $429 shipping fee in the taxed amount.
- Wayfair deducts return shipping after calculating the tax refund.

`taxRatePct` may remain as legacy source metadata, but completeness must not use
it. Vendor meanings of "subtotal" also vary. The current `subtotalCents` field
must therefore stop driving vendor-receipt completeness. Existing vendor values
can remain readable during migration; new vendor receipts do not need to write
one. Generated inventory movements retain their current internal subtotal
semantics until that subsystem is separately redesigned.

### Production receipt reconstructions

```text
BLVD Home
$3,999.96 physical items
+  $139.98 installation
+  $720.00 warranty
-  $150.00 promotion
+   $29.00 delivery
+  $308.78 tax
= $5,047.72 total

Wallism
$878.22 physical items + $39.00 shipping + $59.28 tax = $976.50 total

West Elm
$2,958.40 physical item + $429.00 shipping + $228.65 tax = $3,616.05 total

Wayfair Return
$898.53 merchandise credit + $60.64 tax refund - $106.65 return shipping
= $852.52 reconstructed versus $852.53 printed total
```

The Wayfair source is arithmetically off by one cent. That is evidence for a
cent-level tolerance or an explicit source rounding line, not a percentage
tolerance.

## Current field-interaction audit

Ledger does not currently store a transaction-level `taxCents`. The app's
read-only "Tax Amount" display computes `amountCents - subtotalCents`.

The existing fields currently have these responsibilities:

- Cloud Functions completeness requires either `subtotalCents` or
  `taxRatePct`, back-solves a missing subtotal from amount/rate, and compares
  Items minus `discount` against that resolved subtotal.
- New Transaction writes both fields for itemized categories. "No tax" writes
  `subtotalCents == amountCents` and `taxRatePct == 0`.
- The Next Steps checklist incorrectly considers only a positive tax rate
  complete, so a valid no-tax receipt can never satisfy that step.
- The MCP exposes both fields, uses them in reconciliation advice, and copies a
  transaction tax rate onto newly created Items when an Item rate is omitted.
- CSV export exposes both fields as optional columns.
- Budget totals and invoice amounts do not use transaction subtotal or tax
  rate; they use the transaction/item amounts that already exist.

The inventory-movement subsystem is a separate concern and is materially
coupled to the legacy fields:

- `Item.taxRatePct` is used to calculate tax-inclusive internal movement
  amounts from project price.
- Changes to Item price or tax rate trigger trusted repricing of eligible
  Purchase-from-Inventory transactions.
- Those generated movement transactions freeze `amountCents` and
  `subtotalCents` in Firestore rules, and a legacy return path uses the pair as
  an accounting snapshot fallback.
- The two Item tax-amount fields exist in the model but are otherwise dormant
  outside CRUD/model tests.

Production distribution among 326 active-project itemized Purchases/Returns:

- 167 have a positive transaction tax rate;
- 56 have an explicit zero rate;
- 103 have no transaction tax rate;
- 324 have a stored subtotal;
- 100 have `amountCents == subtotalCents`;
- 7 have `amountCents < subtotalCents`, demonstrating that the two fields do
  not universally mean "total equals subtotal plus tax."

### Consequence

Tax does not need special storage for vendor-receipt reconstruction. Store the
printed tax as a `NonItemReceiptLine`, and remove subtotal/rate from receipt
completeness.

Do not simultaneously delete the movement subsystem's subtotal and Item tax
rate behavior. In the first implementation:

1. vendor receipt completeness uses Items + signed non-item receipt lines;
2. generated inventory movements retain their current trusted subtotal and
   Item tax-rate mechanics; and
3. transaction-to-Item tax-rate inheritance must be reviewed separately. A tax
   receipt line must never be automatically allocated across Items or converted
   into an Item rate, because receipts can have mixed tax treatment.

### Short migration compatibility

During the migration window only:

- generated inventory movements continue through their existing trusted path;
- vendor transactions with a present `nonItemReceiptLines` field use final-total
  reconstruction, including when the array is empty; and
- unmigrated legacy vendor transactions may temporarily use the old
  subtotal/discount calculation.

The migration writes `nonItemReceiptLines` explicitly to opt each vendor
transaction into the new equation. This is a short compatibility branch, not a
dual-write model: new writers emit only receipt lines, and the legacy vendor
branch is removed after production verification.

## Lifecycle and inventory behavior

Non-item receipt lines:

- belong to exactly one transaction;
- never appear in `itemIds`;
- never get an `Item` document;
- never receive a space, status, SKU, image gallery, market value, bookmark, or
  inventory lineage;
- do not move when physical items are returned, sold, or reassigned;
- remain on the original receipt transaction as historical financial evidence;
- are not copied automatically across inventory-to-project movements. Partial
  allocation across projects would require an explicit allocation design and
  must not be guessed.

## Billing decision that must remain explicit

Receipt reconciliation and client billing are different concerns. A shipping
charge may be passed through to the client, while a vendor discount may or may
not change the client's agreed price. Therefore a receipt line must not enter
the invoice pool merely because it exists.

Before exposing line creation broadly, choose one of these intentionally:

1. add explicit client-facing pricing/billability to `NonItemReceiptLine`; or
2. keep receipt lines cost-only and require a separate invoice charge/credit.

Do not silently map every `increase` to an invoice charge and every `decrease`
to an invoice credit. The production candidates are not currently on invoices,
so the cleanup migration is not blocked by historical invoice references, but
future behavior must be decided before release.

If receipt lines become directly billable, extend `InvoiceLineSourceType` with
`nonItemReceiptLine`, store both `sourceTransactionId` and the receipt-line ID,
and add a flat receipt-line membership index so individual lines—not whole
itemized transactions—are claimed by invoices.

## Product and code surfaces

### Swift app

- `Models/Transaction.swift`: replace `Discount` with the new line array and
  remove tax/subtotal fields from completeness inputs.
- Transaction creation and detail: add an **Other receipt lines** editor with
  increase/decrease controls; show the reconciled equation.
- Transaction audit panel and next steps: display physical items separately
  from non-item receipt lines and show exact residuals.
- Item entry: never create or suggest an Item for a nonphysical receipt line.
- Invoice creation, billing summaries, client reports, and financial access:
  implement the explicit billing decision above.
- Transaction export: include a readable line summary and structured fields.
- Amazon/Wayfair invoice parsing: preserve parsed shipping, credits, discounts,
  and other adjustments instead of discarding them after parse summaries.

### Cloud Functions

- Replace the discount subtraction in `computeIsComplete` with signed receipt
  line aggregation.
- Recompute when `nonItemReceiptLines`, `itemIds`, linked item prices, or the
  transaction amount changes.
- Update item-price-trigger audit patching to preserve receipt-line totals.
- Update audit/backfill output fields and tests.

### MCP

- Add the line schema to `Transaction`, `create_transaction`,
  `update_transaction`, and `create_transaction_with_items`.
- Return the lines and their audit totals from transaction readers.
- Replace diagnostic advice that says to add an Item to close a variance.
- Explicitly instruct agents that shipping, protection, warranty, labor,
  discounts, credits, and similar nonphysical receipt lines must never become
  Item documents.
- Allow tax and multiple named increases/decreases as ordinary receipt lines.
- Remove the old `discount` argument and schema documentation after the
  production migration.

### Rules, docs, and tests

- Firestore transaction rules currently allow arbitrary ordinary transaction
  fields, but movement immutability and any future allowlists must account for
  the line array.
- Update the data model, transaction audit/completeness specs, transaction
  creation docs, agent guide, invoice docs, and vendor-credit proposal.
- Add model encoding, equation, MCP validation, migration, import-parser,
  transaction-detail, and invoice-policy tests.

## Interaction with vendor refunds and non-cash credits

D-001/D-007 supersede the older fourth-type Vendor Credit proposal for the
target redesign. Money actually returned by a vendor is recorded as a
scope-relative Return, and non-item receipt lines describe the components of
that Purchase or Return. A cancellation or vendor account credit where the
scope owner has not received money cannot be mislabeled as Return and cannot
introduce a fourth Transaction type; O-028 owns its eventual non-Transaction or
correction representation.

The standalone `adjustmentCents`/`adjustmentExplanation` and legacy `discount`
fields in the older Vendor Credit draft are not target fields. Any approved
vendor-refund command uses `nonItemReceiptLines` for supported signed receipt
components.

## Production migration scope

The migration is broader than deleting the 12 fake Item records and converting
20 legacy discounts. Because tax now participates as a receipt line, every
active-project itemized vendor Purchase/Return must be evaluated for the new
equation.

Among the 326 active-project itemized Purchases/Returns reviewed:

- 217 have `amountCents > subtotalCents` and are likely to need one or more tax
  or other increase lines;
- 100 have equal amount and subtotal and may need an explicit empty array when
  Items already reconstruct the total;
- 7 have amount below subtotal and require receipt-aware decreases rather than
  a derived tax assumption; and
- 2 lack a stored subtotal and require reconstruction from Items and source
  evidence.

Do not mechanically label `amountCents - subtotalCents` as tax for every legacy
transaction. Use that difference only when the receipt or a fully reconciled
legacy equation supports it. The reviewed migration manifest must contain the
complete signed equation for each affected transaction.

## Delivery order

1. Land backward-compatible decoding and the new receipt-line model without
   enabling new writes.
2. Implement and test the new completeness equation, audit output, app editor,
   MCP reads/writes, and migration tooling as one release unit.
3. Decide and implement billability before broad user-facing creation.
4. Generate and review the immutable production manifest, with per-transaction
   backups and complete signed equations.
5. Deploy the short compatibility branch and new writers, then run the
   production migration.
6. Verify every affected equation, item count, checkmark reference, invoice
   dependency, and `isComplete` result from fresh reads.
7. Remove legacy vendor `discount`/subtotal completeness code and documentation
   in the same release window; do not keep a prolonged dual-write period for the
   single production account.
