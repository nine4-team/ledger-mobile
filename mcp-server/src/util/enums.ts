/**
 * Single source of truth for enum values used across the MCP server.
 *
 * Every tool that accepts or returns one of these values should import
 * from this file rather than hard-coding literals. The schema
 * introspection tool (`describe_schema`) reads from here so the
 * contract can never drift from what tools actually accept.
 */

/**
 * Transaction types. Five canonical values. "Fee" and "Expense" were added in
 * the taxonomy migration — see docs/specs/transaction-type.md. "Purchase" means
 * itemized purchase; non-itemized payments to third parties use "Expense";
 * money the business charges the client uses "Fee".
 *
 * "To Inventory" is legacy — new writes use type: "Return" with
 * source: "Business Inventory" instead. It remains here so queries against
 * historical docs still work.
 */
export const transactionTypes = [
  "Purchase",
  "Return",
  "Sale",
  "Fee",
  "Expense",
  "To Inventory",
] as const;
export type TransactionType = (typeof transactionTypes)[number];

export const transactionStatuses = ["canceled"] as const;
export type TransactionStatus = (typeof transactionStatuses)[number];

export const reimbursementTypes = ["none", "owed-to-client", "owed-to-company"] as const;
export type ReimbursementType = (typeof reimbursementTypes)[number];

export const ingestionStatuses = ["needs_review", "auto_matched", "confirmed"] as const;
export type IngestionStatus = (typeof ingestionStatuses)[number];

export const itemStatuses = ["to purchase", "purchased", "to return", "returned"] as const;
export type ItemStatus = (typeof itemStatuses)[number];

export const invoiceStatuses = ["draft", "sent", "paid", "voided"] as const;
export type InvoiceStatus = (typeof invoiceStatuses)[number];

export const movementKinds = ["sold", "soldToInventory", "returned", "transferred"] as const;
export type MovementKind = (typeof movementKinds)[number];

/**
 * @deprecated Legacy canonical-sale direction. Only present on historical
 * `isCanonicalInventorySale: true` transactions. New per-batch inventory movements
 * derive direction from transaction shape and never set this field. Kept for legacy reads.
 * See docs/specs/canonical-sales.md.
 */
export const inventorySaleDirections = [
  "project_to_business",
  "business_to_project",
] as const;
/** @deprecated See `inventorySaleDirections` comment. */
export type InventorySaleDirection = (typeof inventorySaleDirections)[number];

export const categoryTypes = ["general", "labor", "materials", "fees", "reimbursable"] as const;
export type CategoryType = (typeof categoryTypes)[number];

/** Describes an enum for introspection output. */
export interface EnumSpec {
  name: string;
  values: readonly string[];
  description: string;
}

export const ENUMS: EnumSpec[] = [
  {
    name: "transactionType",
    values: transactionTypes,
    description:
      "Transaction type. 'Purchase' is itemized purchases; 'Expense' is non-itemized third-party " +
      "costs; 'Fee' is money the business charges the client. Inventory movement transactions are created via " +
      "sell_items_from_* or return_items, not create_transaction. 'To Inventory' is legacy — for new writes use 'Return' " +
      "with source: 'Business Inventory'.",
  },
  {
    name: "transactionStatus",
    values: transactionStatuses,
    description: "Transaction lifecycle status. Only 'canceled' is canonical; active transactions omit status. Needs Review is driven by isComplete.",
  },
  {
    name: "reimbursementType",
    values: reimbursementTypes,
    description: "Who owes whom for this transaction.",
  },
  {
    name: "ingestionStatus",
    values: ingestionStatuses,
    description: "Lifecycle of an email-ingested transaction awaiting human triage.",
  },
  {
    name: "itemStatus",
    values: itemStatuses,
    description: "Item lifecycle status.",
  },
  {
    name: "invoiceStatus",
    values: invoiceStatuses,
    description: "Invoice demand lifecycle. Paid means collected/settled; transactions record the actual money movement.",
  },
  {
    name: "movementKind",
    values: movementKinds,
    description: "Type of lineage movement between transactions/projects.",
  },
  {
    name: "inventorySaleDirection",
    values: inventorySaleDirections,
    description:
      "DEPRECATED — legacy canonical-sale direction. Only present on historical " +
      "transactions with isCanonicalInventorySale: true. New per-batch inventory movements never set this field.",
  },
  {
    name: "categoryType",
    values: categoryTypes,
    description: "Budget category classification.",
  },
];
