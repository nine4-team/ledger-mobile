import type { Transaction } from '../../data/transactionsService';
import type { Item } from '../../data/itemsService';
import {
  computeTransactionCompleteness,
  type CompletenessStatus,
} from '../transactionCompleteness';

function makeTransaction(overrides: Partial<Transaction> = {}): Transaction {
  return { id: 'txn-1', amountCents: 10000, ...overrides };
}

function makeItems(
  prices: (number | null)[],
): Pick<Item, 'purchasePriceCents'>[] {
  return prices.map((p) => ({ purchasePriceCents: p }));
}

describe('computeTransactionCompleteness', () => {
  // ── Subtotal resolution priority (FR-003, D5) ──

  describe('subtotal resolution', () => {
    it('uses explicit subtotalCents when present', () => {
      const result = computeTransactionCompleteness(
        makeTransaction({ subtotalCents: 8000, amountCents: 10000, taxRatePct: 25 }),
        makeItems([8000]),
      );
      expect(result).not.toBeNull();
      expect(result!.transactionSubtotalCents).toBe(8000);
      expect(result!.missingTaxData).toBe(false);
      expect(result!.inferredTax).toBeUndefined();
    });

    it('infers subtotal from amountCents and taxRatePct when subtotalCents is null', () => {
      // amountCents: 10825, taxRatePct: 8.25 → subtotal = round(10825 / 1.0825) = 10000
      const result = computeTransactionCompleteness(
        makeTransaction({ subtotalCents: null, amountCents: 10825, taxRatePct: 8.25 }),
        makeItems([10000]),
      );
      expect(result).not.toBeNull();
      expect(result!.transactionSubtotalCents).toBe(10000);
      expect(result!.inferredTax).toBe(825);
      expect(result!.missingTaxData).toBe(false);
    });

    it('falls back to amountCents when no subtotal or tax rate', () => {
      const result = computeTransactionCompleteness(
        makeTransaction({ subtotalCents: null, amountCents: 5000, taxRatePct: null }),
        makeItems([5000]),
      );
      expect(result).not.toBeNull();
      expect(result!.transactionSubtotalCents).toBe(5000);
      expect(result!.missingTaxData).toBe(true);
      expect(result!.inferredTax).toBeUndefined();
    });

    it('falls back to amountCents when taxRatePct is 0', () => {
      const result = computeTransactionCompleteness(
        makeTransaction({ subtotalCents: null, amountCents: 5000, taxRatePct: 0 }),
        makeItems([5000]),
      );
      expect(result).not.toBeNull();
      expect(result!.transactionSubtotalCents).toBe(5000);
      expect(result!.missingTaxData).toBe(true);
    });

    it('uses Math.round for inferred subtotal to prevent float drift', () => {
      // amountCents: 9999, taxRatePct: 7.5 → subtotal = round(9999 / 1.075) = 9302
      const result = computeTransactionCompleteness(
        makeTransaction({ subtotalCents: null, amountCents: 9999, taxRatePct: 7.5 }),
        makeItems([9302]),
      );
      expect(result).not.toBeNull();
      expect(Number.isInteger(result!.transactionSubtotalCents)).toBe(true);
    });
  });

  // ── Status classification (FR-004, D6) ──

  describe('status classification', () => {
    it('returns "complete" when variance is exactly 0%', () => {
      const result = computeTransactionCompleteness(
        makeTransaction({ subtotalCents: 10000 }),
        makeItems([10000]),
      );
      expect(result!.status).toBe('complete');
    });

    it('returns "complete" when variance is exactly 1%', () => {
      // 1% of 10000 = 100 → items = 9900
      const result = computeTransactionCompleteness(
        makeTransaction({ subtotalCents: 10000 }),
        makeItems([9900]),
      );
      expect(result!.status).toBe('complete');
    });

    it('returns "near" when variance is just over 1%', () => {
      // 1.01% of 10000 = 101 → items = 9899
      const result = computeTransactionCompleteness(
        makeTransaction({ subtotalCents: 10000 }),
        makeItems([9899]),
      );
      expect(result!.status).toBe('near');
    });

    it('returns "near" when variance is exactly 20%', () => {
      // 20% of 10000 = 2000 → items = 8000
      const result = computeTransactionCompleteness(
        makeTransaction({ subtotalCents: 10000 }),
        makeItems([8000]),
      );
      expect(result!.status).toBe('near');
    });

    it('returns "incomplete" when variance exceeds 20%', () => {
      // items = 7999 → variance = 20.01%
      const result = computeTransactionCompleteness(
        makeTransaction({ subtotalCents: 10000 }),
        makeItems([7999]),
      );
      expect(result!.status).toBe('incomplete');
    });

    it('returns "near" at exactly 120% ratio (not over)', () => {
      // ratio = 12000 / 10000 = 1.20 → NOT > 1.20, variance = +20% → near
      const result = computeTransactionCompleteness(
        makeTransaction({ subtotalCents: 10000 }),
        makeItems([12000]),
      );
      expect(result!.status).toBe('near');
    });

    it('returns "over" when ratio exceeds 1.20', () => {
      // ratio = 12001 / 10000 = 1.2001 → over
      const result = computeTransactionCompleteness(
        makeTransaction({ subtotalCents: 10000 }),
        makeItems([12001]),
      );
      expect(result!.status).toBe('over');
    });

    it('returns "incomplete" when items total is 0 (with items)', () => {
      const result = computeTransactionCompleteness(
        makeTransaction({ subtotalCents: 10000 }),
        makeItems([null, null, 0]),
      );
      expect(result!.status).toBe('incomplete');
      expect(result!.completenessRatio).toBe(0);
    });
  });

  // ── Edge cases (FR-009, FR-010) ──

  describe('edge cases', () => {
    it('returns null when all monetary fields are null', () => {
      const result = computeTransactionCompleteness(
        makeTransaction({ amountCents: null, subtotalCents: null }),
        makeItems([1000]),
      );
      expect(result).toBeNull();
    });

    it('returns null when all monetary fields are 0', () => {
      const result = computeTransactionCompleteness(
        makeTransaction({ amountCents: 0, subtotalCents: 0 }),
        makeItems([1000]),
      );
      expect(result).toBeNull();
    });

    it('returns null when amountCents is undefined', () => {
      const result = computeTransactionCompleteness(
        { id: 'txn-1' } as Transaction,
        makeItems([1000]),
      );
      expect(result).toBeNull();
    });

    it('handles empty items array', () => {
      const result = computeTransactionCompleteness(
        makeTransaction({ subtotalCents: 10000 }),
        [],
      );
      expect(result).not.toBeNull();
      expect(result!.itemsNetTotalCents).toBe(0);
      expect(result!.itemsCount).toBe(0);
      expect(result!.itemsMissingPriceCount).toBe(0);
      expect(result!.completenessRatio).toBe(0);
      expect(result!.status).toBe('incomplete');
    });

    it('handles all items with null prices', () => {
      const result = computeTransactionCompleteness(
        makeTransaction({ subtotalCents: 10000 }),
        makeItems([null, null, null]),
      );
      expect(result).not.toBeNull();
      expect(result!.itemsNetTotalCents).toBe(0);
      expect(result!.itemsCount).toBe(3);
      expect(result!.itemsMissingPriceCount).toBe(3);
      expect(result!.status).toBe('incomplete');
    });
  });

  // ── Items total and missing price count (FR-002, FR-007, D12) ──

  describe('items calculation', () => {
    it('sums item prices correctly', () => {
      const result = computeTransactionCompleteness(
        makeTransaction({ subtotalCents: 10000 }),
        makeItems([2500, 3500, 4000]),
      );
      expect(result!.itemsNetTotalCents).toBe(10000);
      expect(result!.itemsCount).toBe(3);
    });

    it('treats null and 0 prices as missing', () => {
      const result = computeTransactionCompleteness(
        makeTransaction({ subtotalCents: 10000 }),
        makeItems([5000, null, 0, 3000]),
      );
      expect(result!.itemsNetTotalCents).toBe(8000);
      expect(result!.itemsMissingPriceCount).toBe(2);
      expect(result!.itemsCount).toBe(4);
    });

    it('handles large item count (100 items)', () => {
      const prices = Array.from({ length: 100 }, () => 100);
      const result = computeTransactionCompleteness(
        makeTransaction({ subtotalCents: 10000 }),
        makeItems(prices),
      );
      expect(result!.itemsNetTotalCents).toBe(10000);
      expect(result!.itemsCount).toBe(100);
      expect(result!.status).toBe('complete');
    });
  });

  // ── Variance calculation ──

  describe('variance', () => {
    it('computes positive variance when items exceed subtotal', () => {
      const result = computeTransactionCompleteness(
        makeTransaction({ subtotalCents: 10000 }),
        makeItems([11000]),
      );
      expect(result!.varianceCents).toBe(1000);
      expect(result!.variancePercent).toBe(10);
    });

    it('computes negative variance when items are under subtotal', () => {
      const result = computeTransactionCompleteness(
        makeTransaction({ subtotalCents: 10000 }),
        makeItems([7000]),
      );
      expect(result!.varianceCents).toBe(-3000);
      expect(result!.variancePercent).toBe(-30);
    });

    it('computes zero variance for exact match', () => {
      const result = computeTransactionCompleteness(
        makeTransaction({ subtotalCents: 5000 }),
        makeItems([5000]),
      );
      expect(result!.varianceCents).toBe(0);
      expect(result!.variancePercent).toBe(0);
    });
  });

  // ── Returned and sold items in completeness ──

  describe('returned and sold items', () => {
    it('includes returned items in itemsNetTotalCents', () => {
      const result = computeTransactionCompleteness(
        makeTransaction({ subtotalCents: 10000 }),
        makeItems([5000]),
        { returned: makeItems([3000]), sold: [] },
      );
      expect(result!.itemsNetTotalCents).toBe(8000);
      expect(result!.itemsCount).toBe(2);
    });

    it('includes sold items in itemsNetTotalCents', () => {
      const result = computeTransactionCompleteness(
        makeTransaction({ subtotalCents: 10000 }),
        makeItems([5000]),
        { returned: [], sold: makeItems([4000]) },
      );
      expect(result!.itemsNetTotalCents).toBe(9000);
      expect(result!.itemsCount).toBe(2);
    });

    it('combines active + returned + sold for completeness ratio', () => {
      // active: 5000, returned: 3000, sold: 2000 = 10000 / 10000 = 1.0
      const result = computeTransactionCompleteness(
        makeTransaction({ subtotalCents: 10000 }),
        makeItems([5000]),
        { returned: makeItems([3000]), sold: makeItems([2000]) },
      );
      expect(result!.completenessRatio).toBe(1);
      expect(result!.status).toBe('complete');
      expect(result!.itemsCount).toBe(3);
    });

    it('backward compatible — omitting movedOutItems matches old behavior', () => {
      const withoutMoved = computeTransactionCompleteness(
        makeTransaction({ subtotalCents: 10000 }),
        makeItems([5000]),
      );
      const withEmptyMoved = computeTransactionCompleteness(
        makeTransaction({ subtotalCents: 10000 }),
        makeItems([5000]),
        { returned: [], sold: [] },
      );
      expect(withoutMoved!.itemsNetTotalCents).toBe(withEmptyMoved!.itemsNetTotalCents);
      expect(withoutMoved!.itemsCount).toBe(withEmptyMoved!.itemsCount);
      expect(withoutMoved!.completenessRatio).toBe(withEmptyMoved!.completenessRatio);
    });

    it('new fields default to 0 when movedOutItems omitted', () => {
      const result = computeTransactionCompleteness(
        makeTransaction({ subtotalCents: 10000 }),
        makeItems([5000]),
      );
      expect(result!.returnedItemsCount).toBe(0);
      expect(result!.returnedItemsTotalCents).toBe(0);
      expect(result!.soldItemsCount).toBe(0);
      expect(result!.soldItemsTotalCents).toBe(0);
    });

    it('populates returnedItemsCount and returnedItemsTotalCents', () => {
      const result = computeTransactionCompleteness(
        makeTransaction({ subtotalCents: 10000 }),
        makeItems([5000]),
        { returned: makeItems([2000, 1000]), sold: [] },
      );
      expect(result!.returnedItemsCount).toBe(2);
      expect(result!.returnedItemsTotalCents).toBe(3000);
    });

    it('populates soldItemsCount and soldItemsTotalCents', () => {
      const result = computeTransactionCompleteness(
        makeTransaction({ subtotalCents: 10000 }),
        makeItems([5000]),
        { returned: [], sold: makeItems([1500, 500]) },
      );
      expect(result!.soldItemsCount).toBe(2);
      expect(result!.soldItemsTotalCents).toBe(2000);
    });

    it('counts missing prices across all categories', () => {
      const result = computeTransactionCompleteness(
        makeTransaction({ subtotalCents: 10000 }),
        makeItems([5000, null]),           // 1 missing in active
        { returned: makeItems([null]), sold: makeItems([0]) },  // 1 missing each
      );
      expect(result!.itemsMissingPriceCount).toBe(3);
      expect(result!.itemsCount).toBe(4);
    });

    it('handles all returned items with null prices', () => {
      const result = computeTransactionCompleteness(
        makeTransaction({ subtotalCents: 10000 }),
        makeItems([5000]),
        { returned: makeItems([null, null]), sold: [] },
      );
      expect(result!.returnedItemsCount).toBe(2);
      expect(result!.returnedItemsTotalCents).toBe(0);
      expect(result!.itemsNetTotalCents).toBe(5000);
    });

    it('status uses combined total — returned items can fill the gap', () => {
      // active: 5000, returned: 5000 → total = 10000 / 10000 = complete
      const result = computeTransactionCompleteness(
        makeTransaction({ subtotalCents: 10000 }),
        makeItems([5000]),
        { returned: makeItems([5000]), sold: [] },
      );
      expect(result!.status).toBe('complete');
    });
  });
});
