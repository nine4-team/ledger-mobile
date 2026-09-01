/**
 * Single source of truth for enum values used across the MCP server.
 *
 * Every tool that accepts or returns one of these values should import
 * from this file rather than hard-coding literals. The schema
 * introspection tool (`describe_schema`) reads from here so the
 * contract can never drift from what tools actually accept.
 */

/**
 * Transaction types. Normal user/tool writes use Purchase, Return, and
 * paymentToBusiness. Inventory workflows create Sale. Fee, Expense, and To
 * Inventory are legacy read-compatible values only.
 */
export const writableTransactionTypes = ["Purchase", "Return", "paymentToBusiness"] as const;
export type WritableTransactionType = (typeof writableTransactionTypes)[number];

export const systemTransactionTypes = ["Sale"] as const;
export type SystemTransactionType = (typeof systemTransactionTypes)[number];

export const transactionTypes = [
  ...writableTransactionTypes,
  ...systemTransactionTypes,
] as const;
export type TransactionType = (typeof transactionTypes)[number];

export const legacyTransactionTypes = ["Fee", "Expense", "To Inventory"] as const;

/**
 * Canonical transaction-type values used for behavioral read decisions.
 *
 * Firestore contains both title-case values written by inventory operations
 * and lowercase values written by the app. Normalize casing at read time, but
 * do not trim or rewrite the stored value: whitespace-padded values are invalid
 * until every client decoder supports them consistently.
 */
export type NormalizedTransactionType =
  | "purchase"
  | "return"
  | "sale"
  | "paymentToBusiness"
  | "fee"
  | "expense"
  | "to inventory";

export function normalizeTransactionType(
  value: unknown
): NormalizedTransactionType | null {
  if (typeof value !== "string") return null;

  switch (value.toLowerCase()) {
    case "purchase":
      return "purchase";
    case "return":
      return "return";
    case "sale":
      return "sale";
    case "paymenttobusiness":
    case "payment_to_business":
    case "payment-to-business":
      return "paymentToBusiness";
    case "fee":
      return "fee";
    case "expense":
      return "expense";
    case "to inventory":
      return "to inventory";
    default:
      return null;
  }
}

export function isReturnTransactionType(value: unknown): boolean {
  return normalizeTransactionType(value) === "return";
}

export const transactionStatuses = ["canceled"] as const;
export type TransactionStatus = (typeof transactionStatuses)[number];

export const reimbursementTypes = ["none", "owed-to-client", "owed-to-company"] as const;
export type ReimbursementType = (typeof reimbursementTypes)[number];

export const ingestionStatuses = ["needs_review", "auto_matched", "confirmed"] as const;
export type IngestionStatus = (typeof ingestionStatuses)[number];

export const itemStatuses = ["to purchase", "purchased", "to return", "returned"] as const;
export type ItemStatus = (typeof itemStatuses)[number];

export const quickDraftItemStatuses = ["open", "in_review", "converted"] as const;
export type QuickDraftItemStatus = (typeof quickDraftItemStatuses)[number];

export const quickDraftCaptureContexts = ["project", "inventory", "transaction"] as const;
export type QuickDraftCaptureContext = (typeof quickDraftCaptureContexts)[number];

export const quickDraftAssignmentHints = ["undecided", "client_paid", "business_paid", "from_inventory"] as const;
export type QuickDraftAssignmentHint = (typeof quickDraftAssignmentHints)[number];

export const invoiceStatuses = ["created", "sent", "paid", "canceled"] as const;
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

export const categoryTypes = ["general", "itemized", "fee"] as const;
export type CategoryType = (typeof categoryTypes)[number];

/** Describes an enum for introspection output. */
export interface EnumSpec {
  name: string;
  values: readonly string[];
  description: string;
}

export const ENUMS: EnumSpec[] = [
  {
    name: "transactionTypeForCreate",
    values: writableTransactionTypes,
    description:
      "Allowed type values for normal create_transaction writes. Purchase covers goods/services; " +
      "Return covers refunds/item returns; paymentToBusiness covers manually recorded client payments and requires a fee category. " +
      "Invoice settlement may also create paymentToBusiness rows for the categories represented by collected invoice lines.",
  },
  {
    name: "transactionType",
    values: [...transactionTypes, ...legacyTransactionTypes],
    description:
      "Transaction type for reads/filters. Normal writes use Purchase, Return, or paymentToBusiness; " +
      "inventory workflows create Sale. Invoice collection also creates paymentToBusiness. " +
      "Purchase covers goods and services; itemization is owned by budget category. " +
      "Fee, Expense, and To Inventory are legacy read-compatible values only.",
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
    name: "quickDraftItemStatus",
    values: quickDraftItemStatuses,
    description: "Quick draft item lifecycle status before/after conversion to a real item.",
  },
  {
    name: "quickDraftCaptureContext",
    values: quickDraftCaptureContexts,
    description: "Where a quick draft item was captured: project, inventory, or transaction.",
  },
  {
    name: "quickDraftAssignmentHint",
    values: quickDraftAssignmentHints,
    description: "Reversible capture-time routing hint; confirmed assignment remains authoritative.",
  },
  {
    name: "invoiceStatus",
    values: invoiceStatuses,
    description: "Invoice demand lifecycle. Legacy reads may contain draft (created) or voided (canceled). Paid means collected/settled; transactions record the actual money movement.",
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
    description:
      "Canonical budget category behavior. general means non-itemized project cost, itemized means item rows/audit/inventory routing, and fee means company revenue/payment category.",
  },
];
