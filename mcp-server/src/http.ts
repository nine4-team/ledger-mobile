#!/usr/bin/env node
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import express from "express";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { initFirebase } from "./firebase.js";
import { verifyToken, resolveAccountId } from "./auth.js";
import { requestContext } from "./context.js";
import { getActiveAccountForUid } from "./userState.js";
import { registerOAuthRoutes, verifyAccessToken } from "./oauth.js";
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
import { registerInvoiceTools } from "./tools/invoices.js";

const db = initFirebase();
const PORT = parseInt(process.env.PORT || "8080", 10);

function createServer(): McpServer {
  const server = new McpServer(
    { name: "ledger", version: "1.0.0" },
    {
      instructions:
        "All entity IDs (projects, transactions, items, spaces, budgetCategories) are opaque strings that MUST be stored and used exactly as returned. Never truncate, abbreviate, or shorten IDs.\n\n" +
        "AUDIT TRAIL: Every time you create or update an entity (transaction, item, project, space), include a brief, " +
        "natural note in the `notes` field explaining what you did and why — written as if you're leaving a quick message " +
        "for a teammate. Always prefix with today's date. Example: '4/2 — Moved 3 lighting fixtures from inventory into Witzenman project, client approved selections.' " +
        "If the entity already has notes, append your note on a new line so existing context is preserved. " +
        "This applies to every write operation, not just sales or moves.\n\n" +
        "INVENTORY MOVEMENTS: Inventory → project creates ONE new Purchase transaction; project → inventory acquisition creates ONE Sale transaction; returns to inventory create Return transactions. Accounting shape fields (amountCents, budgetCategoryId, projectId, type, source) are frozen at creation; itemIds tracks current active membership and can change when items leave via returns/sales. Items in business inventory (projectId: null) have budgetCategoryId: null — enforced on write. Inventory ↔ project and project ↔ project movements are split by source/destination: sell_items_from_inventory_to_project, sell_items_from_project_to_inventory, sell_items_from_project_to_project.\n\n" +
        "INVOICING: Invoices are demands for money; transactions are records of money movement. Use invoice lines with sourceType item, transaction, or manual (shown to users as New Charge). Every invoice line needs budgetCategoryId. Marking an invoice collected creates categorized paymentToBusiness transaction(s) linked by settlementInvoiceId. Returned paid item credits are manual invoice credit lines on draft invoices; never create synthetic Credit: returned transactions.",
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
  registerInvoiceTools(server, db);
  registerResources(server, db);

  return server;
}

const app = express();
app.set("trust proxy", true); // Cloud Run runs behind a load balancer
app.use(express.json()); // Parse JSON request bodies for OAuth + MCP endpoints
app.use(express.urlencoded({ extended: false })); // Parse form-urlencoded bodies (OAuth token requests)

// Serve static assets (logo, etc.)
const __dirname = dirname(fileURLToPath(import.meta.url));
app.use(express.static(join(__dirname, "..", "public")));

// Health check (no auth required)
app.get("/health", (_req, res) => {
  res.json({ status: "ok", server: "ledger-mcp", version: "1.0.0" });
});

// OAuth routes (discovery, registration, authorize, token)
registerOAuthRoutes(app, db);

// ---------- Auth helper ----------

/** Authenticate an MCP request. Returns auth context or null (after sending 401). */
async function authenticateRequest(
  req: express.Request,
  res: express.Response
): Promise<{ accountId: string; uid: string } | null> {
  const authHeader = req.headers.authorization;
  const envAccountId = process.env.LEDGER_ACCOUNT_ID;
  const staticBearer = process.env.MCP_STATIC_BEARER;

  if (authHeader?.startsWith("Bearer ")) {
    const token = authHeader.slice(7);

    // Static bearer (for trusted server-to-server callers like managed agents).
    // Constant-time compare; requires LEDGER_ACCOUNT_ID to scope the request.
    if (staticBearer && envAccountId && token.length === staticBearer.length) {
      let diff = 0;
      for (let i = 0; i < token.length; i++) diff |= token.charCodeAt(i) ^ staticBearer.charCodeAt(i);
      if (diff === 0) return { accountId: envAccountId, uid: "static-bearer" };
    }

    // Try our OAuth access token first
    const oauthUser = verifyAccessToken(token);
    if (oauthUser) return oauthUser;

    // Only try Firebase ID token if it has a "kid" header
    // (our JWTs are HS256, Firebase uses RS256 with "kid")
    try {
      const header = JSON.parse(Buffer.from(token.split(".")[0], "base64url").toString());
      if (header.kid) {
        const uid = await verifyToken(token);
        const accountId = await resolveAccountId(db, uid);
        return { accountId, uid };
      }
    } catch { /* malformed token — fall through to rejection */ }

    // Token is our format but signature invalid — return 401 with re-auth hint
    const origin = `${req.protocol}://${req.get("host")}`;
    res.setHeader(
      "WWW-Authenticate",
      `Bearer resource_metadata="${origin}/.well-known/oauth-protected-resource"`
    );
    res.status(401).json({ error: "Invalid or expired access token. Please reconnect." });
    return null;
  }

  if (envAccountId) {
    return { accountId: envAccountId, uid: "env-configured" };
  }

  const origin = `${req.protocol}://${req.get("host")}`;
  res.setHeader(
    "WWW-Authenticate",
    `Bearer resource_metadata="${origin}/.well-known/oauth-protected-resource"`
  );
  res.status(401).json({ error: "Missing Authorization header and no LEDGER_ACCOUNT_ID configured" });
  return null;
}

// ---------- MCP routes (stateless mode) ----------
// Served on both / and /mcp — Claude.ai sends to / despite resource metadata pointing to /mcp.
// Stateless: new McpServer + StreamableHTTPServerTransport per request.
// This is the SDK's documented pattern for serverless (Cloud Run) — no session affinity needed.

const MCP_PATHS = ["/", "/mcp"];

app.post(MCP_PATHS, async (req, res) => {
  try {
    const auth = await authenticateRequest(req, res);
    if (!auth) return; // 401 already sent

    // Per-user active account override (set via switch_account, stored in Firestore).
    // Survives stateless Cloud Run requests and Claude.ai reconnects.
    const override = await getActiveAccountForUid(db, auth.uid);
    const effective = override ? { ...auth, accountId: override } : auth;

    console.error(
      `[ledger-mcp] POST ${req.path} uid=${auth.uid} account=${effective.accountId}` +
        (override ? ` (override of ${auth.accountId})` : "")
    );

    await requestContext.run(effective, async () => {
      const server = createServer();
      const transport = new StreamableHTTPServerTransport({
        sessionIdGenerator: undefined,
      });

      res.on("close", () => {
        transport.close();
        server.close();
      });

      await server.connect(transport);
      await transport.handleRequest(req, res, req.body);
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Internal error";
    console.error("[ledger-mcp] Request error:", message);

    if (!res.headersSent) {
      const status = message.includes("No account membership") ? 403
        : message.includes("Firebase ID token") ? 401
        : 500;
      res.status(status).json({ error: message });
    }
  }
});

// GET and DELETE are not supported in stateless mode (no sessions to stream or terminate)
app.get(MCP_PATHS, (_req, res) => {
  res.status(405).json({ error: "Method not allowed. Use POST for MCP requests." });
});

app.delete(MCP_PATHS, (_req, res) => {
  res.status(405).json({ error: "Session termination not supported in stateless mode." });
});

app.listen(PORT, () => {
  console.error(`[ledger-mcp] HTTP server listening on port ${PORT}`);
});
