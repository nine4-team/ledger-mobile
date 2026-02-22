import {
  resolveSourceCategories,
  resolveDestinationCategories,
  needsSourceCategoryPicker,
  needsDestinationCategoryPicker,
  type ItemForCategoryResolution,
} from '../bulkSaleUtils';

// ---------------------------------------------------------------------------
// resolveSourceCategories (Flow A: Sell to Business)
// ---------------------------------------------------------------------------

describe('resolveSourceCategories', () => {
  it('keeps existing categories, no assignments', () => {
    const items: ItemForCategoryResolution[] = [
      { id: '1', budgetCategoryId: 'catA' },
      { id: '2', budgetCategoryId: 'catB' },
    ];
    const result = resolveSourceCategories(items, null);
    expect(result).toEqual([
      { id: '1', resolvedCategoryId: 'catA', categoryWasAssigned: false },
      { id: '2', resolvedCategoryId: 'catB', categoryWasAssigned: false },
    ]);
  });

  it('assigns fallback to items missing categories', () => {
    const items: ItemForCategoryResolution[] = [
      { id: '1', budgetCategoryId: null },
      { id: '2', budgetCategoryId: undefined },
    ];
    const result = resolveSourceCategories(items, 'fallback');
    expect(result).toEqual([
      { id: '1', resolvedCategoryId: 'fallback', categoryWasAssigned: true },
      { id: '2', resolvedCategoryId: 'fallback', categoryWasAssigned: true },
    ]);
  });

  it('mixed: items with categories keep them, items without get fallback', () => {
    const items: ItemForCategoryResolution[] = [
      { id: '1', budgetCategoryId: 'catA' },
      { id: '2', budgetCategoryId: null },
      { id: '3', budgetCategoryId: 'catB' },
    ];
    const result = resolveSourceCategories(items, 'fallback');
    expect(result).toEqual([
      { id: '1', resolvedCategoryId: 'catA', categoryWasAssigned: false },
      { id: '2', resolvedCategoryId: 'fallback', categoryWasAssigned: true },
      { id: '3', resolvedCategoryId: 'catB', categoryWasAssigned: false },
    ]);
  });

  it('skips items with no category when no fallback provided', () => {
    const items: ItemForCategoryResolution[] = [
      { id: '1', budgetCategoryId: 'catA' },
      { id: '2', budgetCategoryId: null },
    ];
    const result = resolveSourceCategories(items, null);
    expect(result).toEqual([
      { id: '1', resolvedCategoryId: 'catA', categoryWasAssigned: false },
    ]);
  });

  it('handles empty items array', () => {
    expect(resolveSourceCategories([], 'fallback')).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// resolveDestinationCategories (Flow B/C: Sell to Project)
// ---------------------------------------------------------------------------

describe('resolveDestinationCategories', () => {
  const validIds = new Set(['catA', 'catB']);

  it('keeps valid categories', () => {
    const items: ItemForCategoryResolution[] = [
      { id: '1', budgetCategoryId: 'catA' },
      { id: '2', budgetCategoryId: 'catB' },
    ];
    const result = resolveDestinationCategories(items, validIds, null);
    expect(result).toEqual([
      { id: '1', resolvedCategoryId: 'catA', categoryWasAssigned: false },
      { id: '2', resolvedCategoryId: 'catB', categoryWasAssigned: false },
    ]);
  });

  it('assigns fallback to items with invalid categories', () => {
    const items: ItemForCategoryResolution[] = [
      { id: '1', budgetCategoryId: 'catX' },
      { id: '2', budgetCategoryId: 'catY' },
    ];
    const result = resolveDestinationCategories(items, validIds, 'catA');
    expect(result).toEqual([
      { id: '1', resolvedCategoryId: 'catA', categoryWasAssigned: true },
      { id: '2', resolvedCategoryId: 'catA', categoryWasAssigned: true },
    ]);
  });

  it('assigns fallback to items with missing categories', () => {
    const items: ItemForCategoryResolution[] = [
      { id: '1', budgetCategoryId: null },
      { id: '2', budgetCategoryId: undefined },
    ];
    const result = resolveDestinationCategories(items, validIds, 'catB');
    expect(result).toEqual([
      { id: '1', resolvedCategoryId: 'catB', categoryWasAssigned: true },
      { id: '2', resolvedCategoryId: 'catB', categoryWasAssigned: true },
    ]);
  });

  it('mixed: valid keep theirs, invalid/missing get fallback', () => {
    const items: ItemForCategoryResolution[] = [
      { id: '1', budgetCategoryId: 'catA' },
      { id: '2', budgetCategoryId: 'catX' },
      { id: '3', budgetCategoryId: null },
      { id: '4', budgetCategoryId: 'catB' },
    ];
    const result = resolveDestinationCategories(items, validIds, 'catA');
    expect(result).toEqual([
      { id: '1', resolvedCategoryId: 'catA', categoryWasAssigned: false },
      { id: '2', resolvedCategoryId: 'catA', categoryWasAssigned: true },
      { id: '3', resolvedCategoryId: 'catA', categoryWasAssigned: true },
      { id: '4', resolvedCategoryId: 'catB', categoryWasAssigned: false },
    ]);
  });

  it('skips unresolvable items when no fallback provided', () => {
    const items: ItemForCategoryResolution[] = [
      { id: '1', budgetCategoryId: 'catA' },
      { id: '2', budgetCategoryId: 'catX' },
      { id: '3', budgetCategoryId: null },
    ];
    const result = resolveDestinationCategories(items, validIds, null);
    expect(result).toEqual([
      { id: '1', resolvedCategoryId: 'catA', categoryWasAssigned: false },
    ]);
  });

  it('handles empty items array', () => {
    expect(resolveDestinationCategories([], validIds, 'catA')).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// needsSourceCategoryPicker
// ---------------------------------------------------------------------------

describe('needsSourceCategoryPicker', () => {
  it('returns false when all items have categories', () => {
    const items: ItemForCategoryResolution[] = [
      { id: '1', budgetCategoryId: 'catA' },
      { id: '2', budgetCategoryId: 'catB' },
    ];
    expect(needsSourceCategoryPicker(items)).toBe(false);
  });

  it('returns true when one item is missing a category', () => {
    const items: ItemForCategoryResolution[] = [
      { id: '1', budgetCategoryId: 'catA' },
      { id: '2', budgetCategoryId: null },
    ];
    expect(needsSourceCategoryPicker(items)).toBe(true);
  });

  it('returns true for undefined budgetCategoryId', () => {
    const items: ItemForCategoryResolution[] = [{ id: '1' }];
    expect(needsSourceCategoryPicker(items)).toBe(true);
  });

  it('returns false for empty array', () => {
    expect(needsSourceCategoryPicker([])).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// needsDestinationCategoryPicker
// ---------------------------------------------------------------------------

describe('needsDestinationCategoryPicker', () => {
  const validIds = new Set(['catA', 'catB']);

  it('returns false when all items have valid categories', () => {
    const items: ItemForCategoryResolution[] = [
      { id: '1', budgetCategoryId: 'catA' },
      { id: '2', budgetCategoryId: 'catB' },
    ];
    expect(needsDestinationCategoryPicker(items, validIds)).toBe(false);
  });

  it('returns true when one item has an invalid category', () => {
    const items: ItemForCategoryResolution[] = [
      { id: '1', budgetCategoryId: 'catA' },
      { id: '2', budgetCategoryId: 'catX' },
    ];
    expect(needsDestinationCategoryPicker(items, validIds)).toBe(true);
  });

  it('returns true when one item has no category', () => {
    const items: ItemForCategoryResolution[] = [
      { id: '1', budgetCategoryId: 'catA' },
      { id: '2', budgetCategoryId: null },
    ];
    expect(needsDestinationCategoryPicker(items, validIds)).toBe(true);
  });

  it('returns false for empty array', () => {
    expect(needsDestinationCategoryPicker([], validIds)).toBe(false);
  });
});
