import { isCanonicalInventorySaleTransaction } from '../data/inventoryOperations';

export function getTransactionDisplayName(tx: {
  source?: string | null;
  id?: string | null;
  isCanonicalInventorySale?: boolean | null;
  inventorySaleDirection?: string | null;
}): string {
  if (tx.source?.trim()) {
    return tx.source.trim();
  }

  if (isCanonicalInventorySaleTransaction(tx)) {
    switch (tx.inventorySaleDirection) {
      case 'project_to_business':
        return 'Sale to Inventory';
      case 'business_to_project':
        return 'Purchase from Inventory';
      default:
        return 'Inventory Transfer';
    }
  }

  if (tx.id) {
    return `Transaction ${tx.id.slice(0, 6)}`;
  }

  return 'Untitled Transaction';
}
