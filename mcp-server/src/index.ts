#!/usr/bin/env node
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { initFirebase } from "./firebase.js";
import { createLedgerServer } from "./server.js";

const credIdx = process.argv.indexOf("--credentials");
const credentialsPath = credIdx !== -1 ? process.argv[credIdx + 1] : undefined;

const db = initFirebase(credentialsPath);

const server = createLedgerServer(db);

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("[ledger-mcp] Server running on stdio");
}

main().catch((error) => {
  console.error("[ledger-mcp] Fatal error:", error);
  process.exit(1);
});
