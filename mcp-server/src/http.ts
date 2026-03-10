#!/usr/bin/env node
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

// Health check (no auth required)
app.get("/health", (_req, res) => {
  res.json({ status: "ok", server: "ledger-mcp", version: "1.0.0" });
});

// OAuth routes (discovery, registration, authorize, token)
registerOAuthRoutes(app, db);

// MCP endpoint — auth via OAuth token, Firebase ID token, or env-based account ID
app.post("/mcp", async (req, res) => {
  try {
    let accountId: string;
    let uid: string;

    const authHeader = req.headers.authorization;
    const envAccountId = process.env.LEDGER_ACCOUNT_ID;

    if (authHeader?.startsWith("Bearer ")) {
      const token = authHeader.slice(7);

      // Try our OAuth access token first
      const oauthUser = verifyAccessToken(token);
      if (oauthUser) {
        accountId = oauthUser.accountId;
        uid = oauthUser.uid;
      } else {
        // Fall back to raw Firebase ID token (for backward compat)
        uid = await verifyToken(token);
        accountId = await resolveAccountId(db, uid);
      }
    } else if (envAccountId) {
      // Env-based: use configured account ID (single-tenant deployment)
      accountId = envAccountId;
      uid = "env-configured";
    } else {
      const origin = `${req.protocol}://${req.get("host")}`;
      res.setHeader(
        "WWW-Authenticate",
        `Bearer resource_metadata="${origin}/.well-known/oauth-protected-resource"`
      );
      res.status(401).json({ error: "Missing Authorization header and no LEDGER_ACCOUNT_ID configured" });
      return;
    }

    // Run the MCP handler within the request context
    await requestContext.run({ accountId, uid }, async () => {
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

// Handle GET and DELETE for SSE and session management
app.get("/mcp", async (_req, res) => {
  res.status(405).json({ error: "Method not allowed. Use POST for MCP requests." });
});

app.delete("/mcp", async (_req, res) => {
  res.status(405).json({ error: "Session termination not supported in stateless mode." });
});

app.listen(PORT, () => {
  console.error(`[ledger-mcp] HTTP server listening on port ${PORT}`);
});
