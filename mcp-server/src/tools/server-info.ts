import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { Firestore } from "firebase-admin/firestore";
import { asToolResponse } from "../util/projections.js";
import { withTelemetry } from "../util/telemetry.js";

/**
 * Capability manifest. Lets skills and AI clients detect which
 * optimizations are live on this server build, so they can adapt
 * without hard-coding assumptions.
 */

export const SERVER_VERSION = "1.3.0";

export const SERVER_FEATURES = {
  bulkGetters: true,
  summaryMode: true,
  responseSizeCap: true,
  structuredErrors: true,
  requiredAuditNotes: true,
  dryRun: true,
  transactionDeletionTombstones: true,
  transactionDeletionApproval: "mcp-form-elicitation" as const,
  atomicBatchTransactionDeletion: true,
  compositeTools: true,
  invoiceTools: true,
  invoiceSettlementTransactions: true,
  quickDraftItemTools: true,
  safeItemImageManagement: true,
  quickDraftItemOwnedImages: true,
  schemaIntrospection: true,
  telemetry: true,
  cursorPagination: false,
  searchBackend: "firestore-in-memory" as const,
};

export const SERVER_DEPRECATIONS: Array<{ tool: string; replacement: string; reason: string }> = [];

export function registerServerInfoTools(server: McpServer, db: Firestore) {
  server.tool(
    "server_info",
    "[read-only] Return the MCP server version, feature flags, and deprecations. Call once per session to detect available capabilities.",
    {},
    withTelemetry("server_info", async () =>
      asToolResponse({
        name: "ledger",
        version: SERVER_VERSION,
        features: SERVER_FEATURES,
        deprecations: SERVER_DEPRECATIONS,
        conventions: {
          auditNotes: "Every mutation requires a dated note in `notes`, e.g. '4/6 — short reason'.",
          transactionDeletion:
            "cancel_transaction requires a reason. delete_transaction and delete_transactions are only for fully superseded records, default to dry-run, display the exact scope, require one DELETE MCP form elicitation, and preserve full tombstones. Batches contain 2-20 unique IDs and are all-or-nothing.",
          ids: "Opaque strings; never truncate.",
          money: "Integer cents.",
          transactionTaxonomy:
            "Normal transaction writes use Purchase/Return/paymentToBusiness. paymentToBusiness is Client Payment and requires a fee category with no source/vendor/items/tax/subtotal/discount/purchaser/reimbursement. Sale is inventory-system-created. Fee/Expense/To Inventory are legacy read/filter values only.",
          categoryTaxonomy:
            "Use metadata.categoryType for behavior: general, itemized, fee.",
        },
      })
    )
  );

  server.resource(
    "server-info",
    "ledger://server-info",
    { description: "Server version, capabilities, deprecations", mimeType: "application/json" },
    async (uri) => ({
      contents: [
        {
          uri: uri.href,
          mimeType: "application/json",
          text: JSON.stringify(
            { version: SERVER_VERSION, features: SERVER_FEATURES, deprecations: SERVER_DEPRECATIONS },
            null,
            2
          ),
        },
      ],
    })
  );
}
