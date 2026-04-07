/**
 * Single source of truth for enum values used across the MCP server.
 *
 * Every tool that accepts or returns one of these values should import
 * from this file rather than hard-coding literals. The schema
 * introspection tool (`describe_schema`) reads from here so the
 * contract can never drift from what tools actually accept.
 */

export const transactionTypes = ["Purchase", "Return", "Sale", "To Inventory"] as const;
export type TransactionType = (typeof transactionTypes)[number];

export const transactionStatuses = ["completed", "pending", "canceled", "returned"] as const;
export type TransactionStatus = (typeof transactionStatuses)[number];

export const reimbursementTypes = ["none", "owed-to-client", "owed-to-company"] as const;
export type ReimbursementType = (typeof reimbursementTypes)[number];

export const ingestionStatuses = ["needs_review", "auto_matched", "confirmed"] as const;
export type IngestionStatus = (typeof ingestionStatuses)[number];

export const itemStatuses = ["to purchase", "purchased", "to return", "returned"] as const;
export type ItemStatus = (typeof itemStatuses)[number];

export const movementKinds = ["sold", "returned", "transferred"] as const;
export type MovementKind = (typeof movementKinds)[number];

export const inventorySaleDirections = [
  "project_to_business",
  "business_to_project",
] as const;
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
    description: "Transaction type. Sale transactions are created via sell_items, not create_transaction.",
  },
  {
    name: "transactionStatus",
    values: transactionStatuses,
    description: "Transaction lifecycle status. Canceled transactions contribute $0 to budget.",
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
    name: "movementKind",
    values: movementKinds,
    description: "Type of lineage movement between transactions/projects.",
  },
  {
    name: "inventorySaleDirection",
    values: inventorySaleDirections,
    description: "Direction of a canonical inventory sale transaction.",
  },
  {
    name: "categoryType",
    values: categoryTypes,
    description: "Budget category classification.",
  },
];
