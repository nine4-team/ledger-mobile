import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { Firestore } from "firebase-admin/firestore";
import { z } from "zod";
import { resolveAllAccounts } from "../auth.js";
import { getAccountId, getActiveAccountId, setActiveAccountId } from "../context.js";
import { USER_UID } from "../config.js";

export function registerAccountTools(server: McpServer, db: Firestore) {
  // ── list_accounts ──────────────────────────────────────────────────────────
  server.tool(
    "list_accounts",
    "List all accounts the current user has access to. Shows which account is currently active.",
    {},
    async () => {
      const uid = process.env.LEDGER_USER_UID || USER_UID;
      const currentAccountId = getAccountId();

      try {
        const accounts = await resolveAllAccounts(db, uid);
        const rows = accounts.map((a) => ({
          id: a.accountId,
          name: a.accountName,
          role: a.role ?? "member",
          active: a.accountId === currentAccountId,
        }));

        return {
          content: [{
            type: "text",
            text: JSON.stringify(rows, null, 2),
          }],
        };
      } catch (error) {
        return {
          content: [{
            type: "text",
            text: `Could not resolve accounts for UID ${uid}. Ensure LEDGER_USER_UID is set and the user has account memberships.`,
          }],
          isError: true,
        };
      }
    }
  );

  // ── switch_account ─────────────────────────────────────────────────────────
  server.tool(
    "switch_account",
    "Switch to a different account. All subsequent queries will use this account. Use list_accounts to see available accounts.",
    {
      accountId: z.string().describe("Account ID to switch to"),
    },
    async ({ accountId }) => {
      const uid = process.env.LEDGER_USER_UID || USER_UID;

      // Verify the user actually has access to this account
      try {
        const accounts = await resolveAllAccounts(db, uid);
        const match = accounts.find((a) => a.accountId === accountId);

        if (!match) {
          return {
            content: [{
              type: "text",
              text: `Access denied. Account ${accountId} is not accessible by this user. Use list_accounts to see available accounts.`,
            }],
            isError: true,
          };
        }

        setActiveAccountId(accountId);

        return {
          content: [{
            type: "text",
            text: `Switched to account "${match.accountName}" (${accountId}). All subsequent queries will use this account.`,
          }],
        };
      } catch (error) {
        return {
          content: [{
            type: "text",
            text: `Could not verify account access: ${error instanceof Error ? error.message : String(error)}`,
          }],
          isError: true,
        };
      }
    }
  );
}
