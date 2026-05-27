import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { Firestore } from "firebase-admin/firestore";
import { z } from "zod";
import { ENUMS } from "../util/enums.js";
import { asToolResponse } from "../util/projections.js";
import { withTelemetry } from "../util/telemetry.js";

/**
 * Schema introspection. Exposes enum values, key fields, and business
 * rules so the AI doesn't have to guess valid inputs or re-read source.
 * Pay the token cost once via resource cache, or on demand via tool call.
 */

interface EntitySchema {
  name: string;
  description: string;
  requiredOnCreate: string[];
  keyFields: Array<{ name: string; type: string; description: string }>;
  enums: string[];
  notes?: string[];
}

const ENTITIES: Record<string, EntitySchema> = {
  transaction: {
    name: "transaction",
    description:
      "A purchase, return, sale-to-inventory, fee, or expense. Owned by an account; may belong to a project. " +
      "Completeness (`isComplete`) is computed server-side — do not set manually. " +
      "Inventory movement transactions are per-batch and immutable after creation (amountCents, " +
      "itemIds, budgetCategoryId, type, source, projectId are frozen).",
    requiredOnCreate: ["budgetCategoryId", "amountCents", "type", "notes"],
    keyFields: [
      { name: "id", type: "string", description: "Opaque document ID. Store exactly as returned." },
      { name: "projectId", type: "string?", description: "Null = business inventory." },
      { name: "type", type: "enum(transactionType)", description: "Inventory → project uses Purchase; project-originated item → inventory uses Sale; item going home to inventory uses Return." },
      { name: "source", type: "string", description: "Vendor for normal purchases; inventory label for inventory movement transactions." },
      { name: "amountCents", type: "number", description: "Total amount including tax, in cents. FROZEN at creation on inventory movement transactions." },
      { name: "subtotalCents", type: "number?", description: "Pre-tax subtotal in cents." },
      { name: "taxRatePct", type: "number?", description: "Percent, e.g. 8.25." },
      { name: "itemIds", type: "string[]", description: "CANONICAL link: transaction owns the item IDs; never filter items by item.transactionId. FROZEN at creation on inventory movement transactions." },
      { name: "budgetCategoryId", type: "string?", description: "Budget category. FROZEN at creation on inventory movement transactions." },
      { name: "isComplete", type: "boolean", description: "Computed server-side; false means items don't match subtotal within ±1% or missing data." },
      { name: "notes", type: "string", description: "REQUIRED on writes — dated audit note." },
    ],
    enums: ["transactionType", "transactionStatus", "reimbursementType", "ingestionStatus"],
    notes: [
      "Every mutation must include a dated audit note in `notes`.",
      "Canceled transactions contribute $0 to budget calculations.",
      "Inventory movement transaction shape fields (amountCents, itemIds, budgetCategoryId, type, source, projectId) are frozen after creation — enforced by Firestore rules and server-side validation. Only notes, status, and updatedAt are mutable.",
      "Legacy canonical sales (isCanonicalInventorySale == true) are exempt from Sale immutability for backwards compatibility.",
    ],
  },
  item: {
    name: "item",
    description:
      "A single line item (physical good) tracked across projects, inventory, and sales. " +
      "Moved between scopes via sell_items / return_items / move_items_between_projects " +
      "(never manually edit transactionId for moves).",
    requiredOnCreate: ["name", "notes"],
    keyFields: [
      { name: "id", type: "string", description: "Opaque document ID." },
      { name: "projectId", type: "string?", description: "Null = business inventory. MUST be null for inventory items." },
      { name: "spaceId", type: "string?", description: "Optional space within a project." },
      { name: "budgetCategoryId", type: "string?", description: "MUST be null when projectId is null (invariant: items in inventory have no category). Resolved at sell-into-project time." },
      { name: "transactionId", type: "string?", description: "Current owning transaction. NOT authoritative for reverse lookups — use transaction.itemIds." },
      { name: "purchasePriceCents", type: "number?", description: "Pre-tax purchase price in cents." },
      { name: "taxRatePct", type: "number?", description: "Auto-inherited from transaction if omitted on create." },
      { name: "status", type: "enum(itemStatus)", description: "Current lifecycle status." },
    ],
    enums: ["itemStatus"],
    notes: [
      "Invariant: (projectId == null) ↔ (budgetCategoryId == null). Enforced on write.",
      "Items in business inventory have no budget category.",
    ],
  },
  project: {
    name: "project",
    description: "A client project with a budget, items, transactions, and spaces.",
    requiredOnCreate: ["name", "notes"],
    keyFields: [
      { name: "id", type: "string", description: "Opaque document ID." },
      { name: "name", type: "string", description: "Project name." },
      { name: "clientName", type: "string", description: "Client name." },
      { name: "notes", type: "string?", description: "Free-text. May contain receipt-matching hints (card last 4, billing address)." },
      { name: "budgetSummary", type: "object?", description: "Denormalized budget totals; recomputed by Cloud Function." },
    ],
    enums: [],
  },
  invoice: {
    name: "invoice",
    description:
      "A project-scoped demand for money. It is separate from transactions, which record money movement. " +
      "Invoice lines can reference existing items, existing transactions, or manual New Charge demands.",
    requiredOnCreate: ["projectId", "lines"],
    keyFields: [
      { name: "id", type: "string", description: "Opaque document ID." },
      { name: "projectId", type: "string", description: "Project being billed." },
      { name: "status", type: "enum(invoiceStatus)", description: "draft, sent, paid, or voided." },
      { name: "lines", type: "InvoiceLine[]", description: "Authoritative demand lines. sourceType is item, transaction, or manual (New Charge)." },
      { name: "itemIds", type: "string[]", description: "Membership index derived from item lines." },
      { name: "transactionIds", type: "string[]", description: "Membership index derived from transaction lines." },
      { name: "totalCents", type: "number?", description: "Frozen net total once sent. Drafts may recompute from lines." },
    ],
    enums: ["invoiceStatus"],
    notes: [
      "Manual invoice lines are UI-labeled New Charge and do not create transactions by themselves.",
      "Marking an invoice collected creates one normal Fee transaction with settlementInvoiceId; it does not create one transaction per line.",
      "Existing transaction-backed invoice lines remain supported for ad-hoc invoices.",
    ],
  },
  space: {
    name: "space",
    description: "A sub-area inside a project (e.g. 'Living Room').",
    requiredOnCreate: ["name", "projectId", "notes"],
    keyFields: [
      { name: "id", type: "string", description: "Opaque document ID." },
      { name: "projectId", type: "string", description: "Parent project." },
      { name: "name", type: "string", description: "Space name." },
      { name: "checklists", type: "Checklist[]", description: "Optional checklists with items." },
    ],
    enums: [],
  },
  budget: {
    name: "budget",
    description: "Budget categories live at the account level and are enabled per project with an allocation.",
    requiredOnCreate: [],
    keyFields: [
      { name: "budgetCategoryId", type: "string", description: "Account-level preset category." },
      { name: "budgetCents", type: "number", description: "Allocation on a specific project." },
      { name: "excludeFromOverallBudget", type: "boolean", description: "When true, does not count toward project total." },
    ],
    enums: ["categoryType"],
  },
};

export function registerSchemaTools(server: McpServer, db: Firestore) {
  // Tool form
  server.tool(
    "describe_schema",
    "[read-only] Return enum values, key fields, and business rules for ledger entities. Call this ONCE per session instead of guessing. Omit `entity` for the full manifest.",
    {
      entity: z
        .enum(["transaction", "item", "project", "invoice", "space", "budget"])
        .optional()
        .describe("Which entity to describe. Omit for all."),
    },
    withTelemetry("describe_schema", async ({ entity }) => {
      const entities = entity ? { [entity]: ENTITIES[entity] } : ENTITIES;
      return asToolResponse({
        entities,
        enums: ENUMS,
        conventions: {
          ids: "All entity IDs are opaque strings — store and pass through exactly as returned; never truncate.",
          auditTrail:
            "Every create/update MUST include a dated audit note in `notes`, e.g. '4/6 — moved 3 fixtures to Witzenman'. Calls without one are rejected with a VALIDATION error.",
          money: "All amounts are integer cents. Tax rates are percentages (e.g. 8.25 = 8.25%).",
          linkage: "Transaction → Items is the canonical direction: use transaction.itemIds, not item.transactionId.",
        },
      });
    })
  );

  // Resource form (cached by client)
  server.resource(
    "schema",
    "ledger://schema",
    { description: "Ledger entity schema, enums, and conventions", mimeType: "application/json" },
    async (uri) => ({
      contents: [
        {
          uri: uri.href,
          mimeType: "application/json",
          text: JSON.stringify({ entities: ENTITIES, enums: ENUMS }, null, 2),
        },
      ],
    })
  );
}
