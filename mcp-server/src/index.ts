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

const credIdx = process.argv.indexOf("--credentials");
const credentialsPath = credIdx !== -1 ? process.argv[credIdx + 1] : undefined;

const db = initFirebase(credentialsPath);

const server = new McpServer(
  { name: "ledger", version: "1.0.0" },
  {
    instructions:
      "All entity IDs (projects, transactions, items, spaces, budgetCategories) are opaque strings that MUST be stored and used exactly as returned. Never truncate, abbreviate, or shorten IDs.\n\n" +
      "AUDIT TRAIL: Every time you create or update an entity (transaction, item, project, space), include a brief, " +
      "natural note in the `notes` field explaining what you did and why — written as if you're leaving a quick message " +
      "for a teammate. Example: 'Moved 3 lighting fixtures from inventory into Witzenman project — client approved selections on 4/2.' " +
      "If the entity already has notes, append your note on a new line so existing context is preserved. " +
      "This applies to every write operation, not just sales or moves.",
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
