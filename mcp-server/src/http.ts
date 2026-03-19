#!/usr/bin/env node
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import express from "express";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { initFirebase } from "./firebase.js";
import { verifyToken, resolveAccountId } from "./auth.js";
import { requestContext } from "./context.js";
import { registerOAuthRoutes, verifyAccessToken } from "./oauth.js";
import { registerProjectTools } from "./tools/projects.js";
import { registerTransactionTools } from "./tools/transactions.js";
import { registerItemTools } from "./tools/items.js";
import { registerSpaceTools } from "./tools/spaces.js";
import { registerBudgetTools } from "./tools/budget.js";
import { registerLineageTools } from "./tools/lineage.js";
import { registerAnalyticsTools } from "./tools/analytics.js";
import { registerResources } from "./resources/index.js";

const db = initFirebase();
const PORT = parseInt(process.env.PORT || "8080", 10);

function createServer(): McpServer {
  const server = new McpServer({
    name: "ledger",
    version: "1.0.0",
  });

  registerProjectTools(server, db);
  registerTransactionTools(server, db);
  registerItemTools(server, db);
  registerSpaceTools(server, db);
  registerBudgetTools(server, db);
  registerLineageTools(server, db);
  registerAnalyticsTools(server, db);
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

  if (authHeader?.startsWith("Bearer ")) {
    const token = authHeader.slice(7);

    // Try our OAuth access token first
    const oauthUser = verifyAccessToken(token);
    if (oauthUser) return oauthUser;

    // Fall back to raw Firebase ID token (for backward compat)
    const uid = await verifyToken(token);
    const accountId = await resolveAccountId(db, uid);
    return { accountId, uid };
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

    console.error(`[ledger-mcp] POST ${req.path} uid=${auth.uid} account=${auth.accountId}`);

    await requestContext.run(auth, async () => {
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
