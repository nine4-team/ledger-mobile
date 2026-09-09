import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { SupabasePropertyManagementReportReader } from "./propertyManagementReportRead.js";
import { createTargetServer } from "./server.js";
import { SupabaseClientSummaryPhysicalReportReader } from "./clientSummaryPhysicalReportRead.js";

// One local process per user/account. Credentials are supplied by the launching
// host, never tool arguments. No token persistence or service-role fallback.
try {
  const reader = new SupabasePropertyManagementReportReader(
    new URL(process.env.LEDGER_TARGET_SUPABASE_URL ?? ""), process.env.LEDGER_TARGET_PUBLISHABLE_KEY ?? "");
  const context = await reader.resolveContext(process.env.LEDGER_TARGET_ACCOUNT_ID ?? "",
    process.env.LEDGER_TARGET_ACCESS_TOKEN ?? "");
  const clientSummaryReader = new SupabaseClientSummaryPhysicalReportReader(
    new URL(process.env.LEDGER_TARGET_SUPABASE_URL ?? ""), process.env.LEDGER_TARGET_PUBLISHABLE_KEY ?? "");
  const server = createTargetServer(reader, context, clientSummaryReader);
  await server.connect(new StdioServerTransport());
} catch {
  process.stderr.write("Ledger target MCP could not start: check target configuration and user session.\n");
  process.exitCode = 1;
}
