import type { Transaction } from './transactionsService';
import type { Item } from './itemsService';
import type { BudgetCategory } from './budgetCategoriesService';
import type { Space } from './spacesService';
import { OWED_TO_COMPANY, OWED_TO_CLIENT, isInvoiceable } from '../constants/reimbursement';

// ---------------------------------------------------------------------------
// Shared currency formatter
// ---------------------------------------------------------------------------

export function formatCents(cents: number): string {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
  }).format(cents / 100);
}

// ---------------------------------------------------------------------------
// Invoice Report
// ---------------------------------------------------------------------------

export type InvoiceLineItem = {
  id: string;
  name: string;
  projectPriceCents: number;
  isMissingPrice: boolean;
};

export type InvoiceLine = {
  transactionId: string;
  title: string;
  date: string | null;
  notes: string | null;
  amountCents: number;
  budgetCategoryName: string | null;
  items: InvoiceLineItem[];
  hasMissingPrices: boolean;
};

export type InvoiceReportData = {
  chargeLines: InvoiceLine[];
  creditLines: InvoiceLine[];
  chargesTotalCents: number;
  creditsTotalCents: number;
  netAmountDueCents: number;
  hasData: boolean;
};

function getTransactionTitle(transaction: Transaction): string {
  if (transaction.isCanonicalInventorySale) {
    if (transaction.inventorySaleDirection === 'business_to_project') {
      return 'Design Business Inventory Sale';
    }
    if (transaction.inventorySaleDirection === 'project_to_business') {
      return 'Design Business Inventory Purchase';
    }
  }
  return transaction.source ?? 'Transaction';
}

function compareDatesAscending(a: string | null | undefined, b: string | null | undefined): number {
  // Null dates sort to the beginning
  if (!a && !b) return 0;
  if (!a) return -1;
  if (!b) return 1;
  return a.localeCompare(b);
}

function buildInvoiceLine(
  transaction: Transaction,
  allItems: Item[],
  categoryMap: Record<string, BudgetCategory>,
): InvoiceLine {
  const linkedItems = allItems.filter((item) => item.transactionId === transaction.id);
  const hasItems = linkedItems.length > 0;

  let amountCents: number;
  const lineItems: InvoiceLineItem[] = [];
  let hasMissingPrices = false;

  if (hasItems) {
    amountCents = 0;
    for (const item of linkedItems) {
      const priceCents = item.projectPriceCents ?? 0;
      const isMissing = !item.projectPriceCents || item.projectPriceCents === 0;
      if (isMissing) {
        hasMissingPrices = true;
      }
      amountCents += priceCents;
      lineItems.push({
        id: item.id,
        name: item.name,
        projectPriceCents: priceCents,
        isMissingPrice: isMissing,
      });
    }
  } else {
    amountCents = transaction.amountCents ?? 0;
  }

  const categoryId = transaction.budgetCategoryId;
  const category = categoryId ? categoryMap[categoryId] : undefined;

  return {
    transactionId: transaction.id,
    title: getTransactionTitle(transaction),
    date: transaction.transactionDate ?? null,
    notes: transaction.notes ?? null,
    amountCents,
    budgetCategoryName: category?.name ?? null,
    items: lineItems,
    hasMissingPrices,
  };
}

export function computeInvoiceData(
  transactions: Transaction[],
  items: Item[],
  categories: Record<string, BudgetCategory>,
): InvoiceReportData {
  const invoiceable = transactions.filter(
    (t) => !t.isCanceled && isInvoiceable(t.reimbursementType),
  );

  const charges = invoiceable
    .filter((t) => t.reimbursementType === OWED_TO_COMPANY)
    .sort((a, b) => compareDatesAscending(a.transactionDate, b.transactionDate));

  const credits = invoiceable
    .filter((t) => t.reimbursementType === OWED_TO_CLIENT)
    .sort((a, b) => compareDatesAscending(a.transactionDate, b.transactionDate));

  const chargeLines = charges.map((t) => buildInvoiceLine(t, items, categories));
  const creditLines = credits.map((t) => buildInvoiceLine(t, items, categories));

  const chargesTotalCents = chargeLines.reduce((sum, line) => sum + line.amountCents, 0);
  const creditsTotalCents = creditLines.reduce((sum, line) => sum + line.amountCents, 0);
  const netAmountDueCents = chargesTotalCents - creditsTotalCents;

  return {
    chargeLines,
    creditLines,
    chargesTotalCents,
    creditsTotalCents,
    netAmountDueCents,
    hasData: invoiceable.length > 0,
  };
}

// ---------------------------------------------------------------------------
// Client Summary Report
// ---------------------------------------------------------------------------

export type CategoryBreakdownEntry = {
  categoryName: string;
  totalCents: number;
};

export type ReceiptLink =
  | { type: 'invoice' }
  | { type: 'receipt-url'; url: string }
  | { type: 'pending-upload' };

export type ClientSummaryItem = {
  id: string;
  name: string;
  source: string | null;
  spaceName: string | null;
  projectPriceCents: number;
  receiptLink: ReceiptLink | null;
};

export type ClientSummaryData = {
  totalSpentCents: number;
  totalMarketValueCents: number;
  totalSavedCents: number;
  categoryBreakdown: CategoryBreakdownEntry[];
  items: ClientSummaryItem[];
  hasData: boolean;
};

function resolveItemCategoryId(
  item: Item,
  transactionMap: Map<string, Transaction>,
): string | null {
  if (item.budgetCategoryId) {
    return item.budgetCategoryId;
  }
  if (item.transactionId) {
    const tx = transactionMap.get(item.transactionId);
    if (tx?.budgetCategoryId) {
      return tx.budgetCategoryId;
    }
  }
  return null;
}

function getReceiptLink(
  item: Item,
  transactionMap: Map<string, Transaction>,
): ReceiptLink | null {
  if (!item.transactionId) {
    return null;
  }

  const tx = transactionMap.get(item.transactionId);
  if (!tx) {
    return null;
  }

  // Canonical inventory sale or invoiceable transaction -> link to invoice
  const isCanonical = tx.isCanonicalInventorySale === true;
  const txIsInvoiceable = isInvoiceable(tx.reimbursementType);

  if (isCanonical || txIsInvoiceable) {
    return { type: 'invoice' };
  }

  // Has receipt image with remote URL -> link to receipt
  const receiptUrl = tx.receiptImages?.[0]?.url;
  if (receiptUrl && !receiptUrl.startsWith('offline://')) {
    return { type: 'receipt-url', url: receiptUrl };
  }

  // Has receipt image but local-only -> pending upload notice
  if (receiptUrl && receiptUrl.startsWith('offline://')) {
    return { type: 'pending-upload' };
  }

  // No receipt image -> no link
  return null;
}

function resolveSpaceName(
  spaceId: string | null | undefined,
  spaceMap: Map<string, Space>,
): string | null {
  if (!spaceId) return null;
  const space = spaceMap.get(spaceId);
  return space?.name ?? null;
}

export function computeClientSummaryData(
  items: Item[],
  transactions: Transaction[],
  categories: Record<string, BudgetCategory>,
  spaces?: Space[],
): ClientSummaryData {
  // Build lookup maps for efficient access
  const transactionMap = new Map<string, Transaction>();
  for (const tx of transactions) {
    transactionMap.set(tx.id, tx);
  }

  const spaceMap = new Map<string, Space>();
  if (spaces) {
    for (const space of spaces) {
      spaceMap.set(space.id, space);
    }
  }

  // Summary calculations
  const totalSpentCents = items.reduce(
    (sum, item) => sum + (item.projectPriceCents ?? 0),
    0,
  );

  const totalMarketValueCents = items.reduce(
    (sum, item) => sum + (item.marketValueCents ?? 0),
    0,
  );

  const totalSavedCents = items.reduce((sum, item) => {
    const marketValue = item.marketValueCents ?? 0;
    const projectPrice = item.projectPriceCents ?? 0;
    if (marketValue > 0) {
      return sum + (marketValue - projectPrice);
    }
    return sum;
  }, 0);

  // Category breakdown
  const categoryTotals: Record<string, number> = {};
  for (const item of items) {
    const categoryId = resolveItemCategoryId(item, transactionMap);
    if (categoryId) {
      const category = categories[categoryId];
      const categoryName = category?.name ?? 'Unknown Category';
      categoryTotals[categoryName] = (categoryTotals[categoryName] ?? 0) + (item.projectPriceCents ?? 0);
    }
  }

  const categoryBreakdown: CategoryBreakdownEntry[] = Object.entries(categoryTotals)
    .map(([categoryName, totalCents]) => ({ categoryName, totalCents }))
    .sort((a, b) => a.categoryName.localeCompare(b.categoryName));

  // Item list
  const clientItems: ClientSummaryItem[] = items.map((item) => ({
    id: item.id,
    name: item.name,
    source: item.source ?? null,
    spaceName: resolveSpaceName(item.spaceId, spaceMap),
    projectPriceCents: item.projectPriceCents ?? 0,
    receiptLink: getReceiptLink(item, transactionMap),
  }));

  return {
    totalSpentCents,
    totalMarketValueCents,
    totalSavedCents,
    categoryBreakdown,
    items: clientItems,
    hasData: items.length > 0,
  };
}

// ---------------------------------------------------------------------------
// Property Management Summary Report
// ---------------------------------------------------------------------------

export type PropertyManagementItem = {
  id: string;
  name: string;
  source: string | null;
  sku: string | null;
  spaceName: string | null;
  marketValueCents: number;
  hasNoMarketValue: boolean;
};

export type PropertyManagementData = {
  totalItems: number;
  totalMarketValueCents: number;
  items: PropertyManagementItem[];
  hasData: boolean;
};

export function computePropertyManagementData(
  items: Item[],
  spaces: Space[],
): PropertyManagementData {
  const spaceMap = new Map<string, Space>();
  for (const space of spaces) {
    spaceMap.set(space.id, space);
  }

  const totalMarketValueCents = items.reduce(
    (sum, item) => sum + (item.marketValueCents ?? 0),
    0,
  );

  const propertyItems: PropertyManagementItem[] = items.map((item) => {
    const marketValueCents = item.marketValueCents ?? 0;
    return {
      id: item.id,
      name: item.name,
      source: item.source ?? null,
      sku: item.sku ?? null,
      spaceName: resolveSpaceName(item.spaceId, spaceMap),
      marketValueCents,
      hasNoMarketValue: marketValueCents === 0,
    };
  });

  return {
    totalItems: items.length,
    totalMarketValueCents,
    items: propertyItems,
    hasData: items.length > 0,
  };
}
