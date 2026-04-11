import { AsyncLocalStorage } from "node:async_hooks";

export interface RequestContext {
  accountId: string;
  uid: string;
}

export const requestContext = new AsyncLocalStorage<RequestContext>();

/**
 * Active account for stdio mode. Set via the switch_account tool.
 * Takes precedence over the LEDGER_ACCOUNT_ID env var.
 */
let activeAccountId: string | null = null;

export function setActiveAccountId(accountId: string): void {
  activeAccountId = accountId;
}

export function getActiveAccountId(): string | null {
  return activeAccountId;
}

/**
 * Get the current account ID.
 * Priority: HTTP context > runtime switch > env var > dev default.
 */
/**
 * Get the current user UID.
 * Priority: HTTP context (from OAuth) > env var > hardcoded dev default.
 */
export function getUid(): string {
  const ctx = requestContext.getStore();
  if (ctx) return ctx.uid;
  return process.env.LEDGER_USER_UID || "sHuIe2M85WVOf3yzC0t61s3l10e2";
}

export function getAccountId(): string {
  // HTTP mode: per-request context
  const ctx = requestContext.getStore();
  if (ctx) return ctx.accountId;

  // Stdio mode: runtime-selected account (from switch_account tool)
  if (activeAccountId) return activeAccountId;

  // Stdio mode: env var fallback
  const envId = process.env.LEDGER_ACCOUNT_ID;
  if (envId) return envId;

  return "1dd4fd75-8eea-4f7a-98e7-bf45b987ae94"; // dev default
}
