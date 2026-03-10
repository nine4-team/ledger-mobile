import { AsyncLocalStorage } from "node:async_hooks";

export interface RequestContext {
  accountId: string;
  uid: string;
}

export const requestContext = new AsyncLocalStorage<RequestContext>();

/**
 * Get the current account ID.
 * In HTTP mode: from AsyncLocalStorage (set per-request after auth).
 * In stdio mode: from env var (set at startup).
 */
export function getAccountId(): string {
  const ctx = requestContext.getStore();
  if (ctx) return ctx.accountId;

  // Fallback for stdio mode
  const envId = process.env.LEDGER_ACCOUNT_ID;
  if (envId) return envId;

  return "1dd4fd75-8eea-4f7a-98e7-bf45b987ae94"; // dev default
}
