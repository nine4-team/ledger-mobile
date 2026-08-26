import type { Firestore } from "firebase-admin/firestore";
import { accountPath } from "./query.js";

export const DEFAULT_INVENTORY_LABEL = "Business Inventory";

export function inventoryLabelForAccountName(accountName?: string | null): string {
  const trimmed = (accountName ?? "").trim();
  return trimmed ? `${trimmed} Inventory` : DEFAULT_INVENTORY_LABEL;
}

export async function resolveInventoryLabel(db: Firestore): Promise<string> {
  const snap = await db.doc(accountPath()).get();
  const data = snap.exists ? snap.data() : undefined;
  return inventoryLabelForAccountName(data?.name ?? data?.companyName);
}

export function isInventorySource(source: string | undefined, inventoryLabel: string): boolean {
  const trimmed = (source ?? "").trim();
  return trimmed === inventoryLabel || trimmed === DEFAULT_INVENTORY_LABEL;
}

type TransactionPriceContext = {
  type?: string;
  source?: string;
  projectId?: string | null;
};

/** Historical branded inventory labels are recognized by the reserved suffix. */
export function usesProjectPriceForAudit(transaction: TransactionPriceContext): boolean {
  const type = transaction.type?.trim().toLowerCase();
  return (type === "purchase" || type === "return") &&
    !!transaction.projectId?.trim() &&
    !!transaction.source?.trim().endsWith(" Inventory");
}
