import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { Firestore } from "firebase-admin/firestore";
import { registerProjectTools } from "./tools/projects.js";
import { registerTransactionTools } from "./tools/transactions.js";
import { registerItemTools } from "./tools/items.js";
import { registerSpaceTools } from "./tools/spaces.js";
import { registerBudgetTools } from "./tools/budget.js";
import { registerLineageTools } from "./tools/lineage.js";
import { registerAnalyticsTools } from "./tools/analytics.js";
import { registerAccountTools } from "./tools/accounts.js";
import { registerInventoryOperationTools } from "./tools/inventory-operations.js";
import { registerPurchaseIntentTools } from "./tools/purchase-intents.js";
import { registerResources } from "./resources/index.js";
import { registerBulkGetterTools } from "./tools/bulk-getters.js";
import { registerSchemaTools } from "./tools/schema.js";
import { registerServerInfoTools } from "./tools/server-info.js";
import { registerCompositeTools } from "./tools/composite.js";
import { registerProjectNoteTools } from "./tools/project-notes.js";
import { registerInvoiceTools } from "./tools/invoices.js";
import { registerQuickDraftItemTools } from "./tools/quick-draft-items.js";

/**
 * Single source of truth for the Ledger MCP server's identity, instructions,
 * and tool registration. Both entrypoints — stdio (index.ts) and HTTP
 * (http.ts) — build their server through createLedgerServer so the tool set
 * and instructions cannot drift between local and remote deployments.
 */

export const SERVER_VERSION = "1.3.0";

export const SERVER_INSTRUCTIONS =
  "START HERE: Call `server_info` and `describe_schema` (or read ledger://schema) once per session to learn capabilities, enums, and entity rules.\n\n" +
  "ITEM COPY NAMES: When one source item, quick draft, or receipt line is expanded into multiple physical item documents, every created document MUST preserve the source `name` exactly, byte-for-byte. Duplicate names are valid because item IDs distinguish physical records. Never append or generate differentiators such as '— unit 2 of 4', 'copy', 'duplicate', '(2)', or any other sequence/quantity suffix. A copy's name may differ only when the user explicitly requests that name or source evidence gives individual units different names. This rule applies to receipt and inventory reconstruction, quick-draft quantity expansion, bulk creation, and every copy/duplication workflow. Inventory movements preserve existing item names and must never rename records automatically.\n\n" +
  "IDS: All entity IDs are opaque strings — pass them through exactly as returned. Never truncate.\n\n" +
  "PROJECT NOTES: Use `add_project_note` to write notes to a project. `create_project` and `update_project` also accept a `notes` param that writes to the project's notes subcollection (not the legacy string field). All notes require a dated prefix, e.g. '4/6 — Moved 3 fixtures to Witzenman'. Use `list_project_notes` and `search_project_notes` to read them.\n\n" +
  "AUDIT TRAIL: Every time you create or update an entity (transaction, item, project, space), include a brief, " +
  "natural note in the `notes` field explaining what you did and why — written as if you're leaving a quick message " +
  "for a teammate. Always prefix with today's date. Example: '4/2 — Moved 3 lighting fixtures from inventory into Witzenman project, client approved selections.' " +
  "If the entity already has notes, append your note on a new line so existing context is preserved. " +
  "This applies to every write operation, not just sales or moves.\n\n" +
  "INVENTORY MOVEMENTS: Inventory → project creates ONE new Purchase transaction; project → inventory acquisition creates ONE Sale transaction; returns to inventory create Return transactions. Structural fields (budgetCategoryId, projectId, type, source) are frozen at creation, and clients cannot edit movement totals directly. When an attached, unpaid sold item is repriced, the trusted server trigger adjusts the project-side Purchase amount/subtotal automatically. itemIds tracks current active membership and can change when items leave via returns/sales. Items in business inventory (projectId: null) have budgetCategoryId: null — enforced on write. Inventory ↔ project and project ↔ project movements are split by source/destination: sell_items_from_inventory_to_project, sell_items_from_project_to_inventory, sell_items_from_project_to_project.\n\n" +
  "TOKEN BUDGET: list_/search_/get_ tools default to `mode: 'summary'` — pass `mode: 'full'` or explicit `fields` only when you need more. Use `get_transactions` / `get_items` / `get_projects` for bulk ID lookups in one round-trip.\n\n" +
  "INVOICING: Invoices are demands for money; transactions are records of money movement. Use item, transaction, or feeInstallment lines for normal source-backed demands; manual is an invoice-only charge or credit. Manual lines automatically use the hidden Other Client Charges & Credits settlement category, while returned paid-item credits retain the original line category. Marking an invoice collected creates categorized paymentToBusiness transaction(s) linked by settlementInvoiceId. Never create synthetic Credit: returned transactions.\n\n" +
  "ITEM QUICK DRAFTS: Quick draft items live in protoItems and are separate from real items. Use list_quick_draft_items, get_quick_draft_item, search_quick_draft_items, create_quick_draft_item, update_quick_draft_item, and promote_quick_draft_item to manage photo-first captures and convert them into real items.\n\n" +
  "ITEM IMAGES: Use set_primary_item_image and reorder_item_images for Storage-free ordering changes. detach_item_image only removes the Firestore reference. delete_item_image is explicitly destructive and deletes objects only when they are owned by the target item's accounts/{accountId}/items/{itemId}/ namespace. Quick-draft promotion copies and verifies photos into that namespace while preserving draft originals.\n\n" +
  "REPORTS / BULK PULLS: For reports and bulk operations, pass `fields: [...]` to slim each row to exactly what you need (e.g. `fields: ['id', 'name', 'purchasePriceCents']` for a property-management export). A slim projection over hundreds of rows fits comfortably under the default 75KB response cap; full documents do not. If a legitimate report still hits `truncated: true`, raise `responseLimit` (max 200KB) on the same call rather than paginating blindly.\n\n" +
  "PREFER TASK TOOLS: `reconcile_transaction`, `create_transaction_with_items`, `triage_inbox` collapse long primitive chains. `sell_items_from_*` and `return_items` support `dryRun: true` — use it before committing.\n\n" +
  "ERRORS: Failures return structured JSON with `{ code, message, hint, retryable }`. Branch on `code`; the `hint` field tells you how to recover.";

export function createLedgerServer(db: Firestore): McpServer {
  const server = new McpServer(
    { name: "ledger", version: SERVER_VERSION },
    { instructions: SERVER_INSTRUCTIONS },
  );

  registerProjectTools(server, db);
  registerTransactionTools(server, db);
  registerItemTools(server, db);
  registerSpaceTools(server, db);
  registerBudgetTools(server, db);
  registerLineageTools(server, db);
  registerAnalyticsTools(server, db);
  registerAccountTools(server, db);
  registerInventoryOperationTools(server, db);
  registerPurchaseIntentTools(server, db);
  registerBulkGetterTools(server, db);
  registerSchemaTools(server, db);
  registerServerInfoTools(server, db);
  registerCompositeTools(server, db);
  registerProjectNoteTools(server, db);
  registerInvoiceTools(server, db);
  registerQuickDraftItemTools(server, db);
  registerResources(server, db);

  return server;
}
