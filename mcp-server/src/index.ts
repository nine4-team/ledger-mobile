#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { initFirebase } from "./firebase.js";
import { registerProjectTools } from "./tools/projects.js";
import { registerTransactionTools } from "./tools/transactions.js";
import { registerItemTools } from "./tools/items.js";
import { registerSpaceTools } from "./tools/spaces.js";
import { registerBudgetTools } from "./tools/budget.js";
import { registerLineageTools } from "./tools/lineage.js";
import { registerAnalyticsTools } from "./tools/analytics.js";
import { registerAccountTools } from "./tools/accounts.js";
import { registerInventoryOperationTools } from "./tools/inventory-operations.js";
import { registerResources } from "./resources/index.js";
import { registerBulkGetterTools } from "./tools/bulk-getters.js";
import { registerSchemaTools } from "./tools/schema.js";
import { registerServerInfoTools } from "./tools/server-info.js";
import { registerCompositeTools } from "./tools/composite.js";
import { registerProjectNoteTools } from "./tools/project-notes.js";

const credIdx = process.argv.indexOf("--credentials");
const credentialsPath = credIdx !== -1 ? process.argv[credIdx + 1] : undefined;

const db = initFirebase(credentialsPath);

const server = new McpServer(
  { name: "ledger", version: "1.1.0" },
  {
    instructions:
      "START HERE: Call `server_info` and `describe_schema` (or read ledger://schema) once per session to learn capabilities, enums, and entity rules.\n\n" +
      "IDS: All entity IDs are opaque strings — pass them through exactly as returned. Never truncate.\n\n" +
      "PROJECT NOTES: Use `add_project_note` to write notes to a project. `create_project` and `update_project` also accept a `notes` param that writes to the project's notes subcollection (not the legacy string field). All notes require a dated prefix, e.g. '4/6 — Moved 3 fixtures to Witzenman'. Use `list_project_notes` and `search_project_notes` to read them.\n\n" +
      "SALES AND INVENTORY: Every sell action creates ONE new immutable Sale transaction — no long-lived aggregators. Sale shape fields (amountCents, itemIds, budgetCategoryId, projectId, type, source) are frozen at creation. Items in business inventory (projectId: null) have budgetCategoryId: null — enforced on write. Sales always go business → project; returning items to inventory is a Return transaction via return_items. Project→project moves use move_items_between_projects.\n\n" +
      "TOKEN BUDGET: list_/search_/get_ tools default to `mode: 'summary'` — pass `mode: 'full'` or explicit `fields` only when you need more. Use `get_transactions` / `get_items` / `get_projects` for bulk ID lookups in one round-trip.\n\n" +
      "REPORTS / BULK PULLS: For reports and bulk operations, pass `fields: [...]` to slim each row to exactly what you need (e.g. `fields: ['id', 'name', 'purchasePriceCents']` for a property-management export). A slim projection over hundreds of rows fits comfortably under the default 75KB response cap; full documents do not. If a legitimate report still hits `truncated: true`, raise `responseLimit` (max 200KB) on the same call rather than paginating blindly.\n\n" +
      "PREFER TASK TOOLS: `reconcile_transaction`, `create_transaction_with_items`, `triage_inbox` collapse long primitive chains. `sell_items`, `return_items`, and `move_items_between_projects` support `dryRun: true` — use it before committing.\n\n" +
      "ERRORS: Failures return structured JSON with `{ code, message, hint, retryable }`. Branch on `code`; the `hint` field tells you how to recover.",
  },
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
registerBulkGetterTools(server, db);
registerSchemaTools(server, db);
registerServerInfoTools(server, db);
registerCompositeTools(server, db);
registerProjectNoteTools(server, db);
registerResources(server, db);

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("[ledger-mcp] Server running on stdio");
}

main().catch((error) => {
  console.error("[ledger-mcp] Fatal error:", error);
  process.exit(1);
});
