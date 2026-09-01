# 1584 Design Non-Item Receipt Line Audit

Date: 2026-08-29  
Mode: production, read-only  
Account: 1584 Design (`1dd4fd75-8eea-4f7a-98e7-bf45b987ae94`)

No production writes were performed.

## Scope

The audit read every project, transaction, item, invoice, lineage edge, space,
and relevant image-checkmark reference in the 1584 Design account. Candidate
classification was restricted to itemized transactions belonging to active
projects.

- Active projects: 5
- Active-project transactions: 361
- Active-project itemized transactions: 341
- Current items on active projects: 1,869
- Item records inspected through current or historical itemized-transaction
  membership: 1,931
- Current items outside that membership: 1

The one uncovered item is a physical Pottery Barn ceramic cutting board with a
SKU, images, and a space. It is not a migration candidate.

Machine-readable evidence:

- `docs/plans/non-item-receipt-line-audit-runs/2026-08-30T01-54-51-509Z.json`
- Re-runnable audit: `scripts/audit-non-item-receipt-lines.mjs`

## Confirmed item migrations

Twelve Item documents across seven transactions should become eight source
receipt lines. The two records initially held for review were confirmed as
installation labor by the attached BLVD Home sales order.

| Project | Transaction | Current Item record(s) | Migration |
| --- | --- | --- | --- |
| Kapcsos Martinique Rental | `RR3j2RNE3QNpFuEB9Gpf` | Wallpaper Mural Shipping — Standard Production + UPS Express, $15.99 | One increase line; delete Item `fduTSyOmn1jVQQS3o7Y0` |
| Kapcsos Martinique Rental | `1SyUrtxu9Yst1DQ1eaWq` | Returns Protection, $12.99 | One increase line; delete Item `InDkO6iTg1A40BeyVvZC` |
| Kapcsos Martinique Rental | `MfbormbscUqJKwt3AN4q` | Wallism shipping for order #373321, $39.00 | One increase line; delete Item `PEQMZT52kZ3v1kAt6UOL` |
| Kapcsos Martinique Rental | `UvQw9Eek9ySNSeRMEsSA` | Mattress Delivery, $50.00 | One increase line; delete Item `7CBgNktZkfxcPFoL9NOe` |
| Kapcsos Martinique Rental | `HbJo3jEOtOy8EyxUFtpq` | Poly & Bark Package Protection, $18.00 | One increase line; delete Item `Nuh25OjUe8YfSPXIEv16` |
| Kapcsos Martinique Rental | `zwKYNGtUIfV3ISY65uN7` | RTC Shipping Fee, $429.00 | One increase line; delete Item `czY0JXyj1mtjO5edytae` |
| Witzenman’s 2nd Home | `cTUXjumZiScFC6vpZiGI` | Four warranty Items at $180 each | One increase line, quantity 4, total $720.00; delete Items `NjTJMz63cQSgGpx7suwR`, `aSajB0JMsgE0HFHkShnb`, `rUdb4QbXqnB6wNYaGaBU`, `KLbq7vcltBVSBTdrbFqk` |
| Witzenman’s 2nd Home | `cTUXjumZiScFC6vpZiGI` | Two install-labor Items at $69.99 each | One increase line, quantity 2, total $139.98; delete Items `uBglJfNpdunGnqmh0TI7`, `M8VgVFymwkREKFZhB43m` |

Four physical Wayfair art Items containing the phrase “frame assembly required”
were initially caught by a broad name heuristic. They were verified as physical
products and excluded. The production report contains only the corrected
classification.

## Legacy discount migration

Twenty active-project transactions contain `transaction.discount`.

- 17 reconcile exactly when the legacy amount becomes one decrease line named
  from source evidence, usually “Discount” or “Promotion.” These can be migrated
  mechanically after backup.
- BLVD Home transaction `cTUXjumZiScFC6vpZiGI` has a $150 discount and also a
  missing $29 delivery-fee increase line. The attached sales order proves both.
- Wayfair Return `ymEm5L40zeCMK4TVveYS` has a 4% merchandise discount ($37.44)
  plus a $106.65 return-shipping deduction. The stored refund evidence proves
  the return-shipping line and a $60.64 Tax Refund line. Migrate the printed
  receipt components rather than copying the discount blindly.
- Wayfair Return `26cB8Kz5JOpUjnqDybu4` has a 4% merchandise discount ($72.52).
  Its amount equation implies a separate $150 return-shipping deduction:
  $1,812.99 - $72.52 + $117.48 tax - $150.00 = $1,707.95. It has no stored
  receipt attachment, so the $150 line should be confirmed against the live
  Wayfair order evidence before the write migration.

The current two Wayfair Returns are incomplete because their gross item subtotal
is stored as `subtotalCents` while `discount` is subtracted again during audit.
They are evidence that the replacement needs enough named receipt lines to
reconstruct the final amount directly, not another aggregate adjustment field.

## Dependency audit

For the 12 confirmed Item documents:

- Invoice references: 0
- Return/sale movement lineage: 0
- Multiple transaction memberships: 0
- Item-owned images: 0
- Visual image-checkmark references: 1

The Wallpaper Mural shipping Item `fduTSyOmn1jVQQS3o7Y0` is referenced by
checkmark `68711B62-D8D9-46B1-9863-997710AB447C` on the first image of space
`ySlAy22ILES3I03nVYgT`. Remove that checkmark during migration; it should not be
repointed to a financial receipt line.

All candidate Items currently have a `spaceId`. Deleting them will correctly
remove nonphysical records from space counts; spaces do not maintain a separate
item-membership array.

## Migration boundary

The write migration should be generated from a reviewed, immutable manifest and
run transaction-by-transaction:

1. Back up each affected Transaction, Item, Space, and invoice dependency result.
2. Add the final `nonItemReceiptLines` array, including printed tax or tax-refund
   lines where evidence supports them.
3. Delete the legacy `discount` field.
4. Remove candidate IDs from `transaction.itemIds` and delete the 12 fake Item
   documents in the same atomic write where Firestore limits allow.
5. Remove the one image checkmark reference.
6. Let the trusted completeness function recompute, then verify exact equations
   and expected item counts from fresh reads.
7. Stop on any dependency drift from this audit; do not partially migrate a
   transaction whose current state changed.

This audit authorizes no production write. It establishes the candidate set and
the source/dependency review required to create the final write manifest.
