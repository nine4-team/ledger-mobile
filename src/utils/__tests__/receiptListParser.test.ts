import { parseReceiptList } from '../receiptListParser';

describe('parseReceiptList', () => {
  it('parses a standard receipt line', () => {
    const result = parseReceiptList('53 - ACCENT FURNISH 252972 $129.99 T');
    expect(result.items).toEqual([
      { name: 'ACCENT FURNISH', sku: '252972', priceCents: 12999 },
    ]);
    expect(result.skippedLines).toEqual([]);
  });

  it('parses multiple lines', () => {
    const text = [
      '53 - ACCENT FURNISH 252972 $129.99 T',
      '56 - EVERYDAY Q LIN 092626 $6.99 T',
      '45 - FLORALS 924460 $229.99 T',
    ].join('\n');
    const result = parseReceiptList(text);
    expect(result.items).toHaveLength(3);
    expect(result.items[0]).toEqual({ name: 'ACCENT FURNISH', sku: '252972', priceCents: 12999 });
    expect(result.items[1]).toEqual({ name: 'EVERYDAY Q LIN', sku: '092626', priceCents: 699 });
    expect(result.items[2]).toEqual({ name: 'FLORALS', sku: '924460', priceCents: 22999 });
  });

  it('skips blank lines', () => {
    const text = '53 - ACCENT FURNISH 252972 $129.99 T\n\n\n56 - EVERYDAY Q LIN 092626 $6.99 T';
    const result = parseReceiptList(text);
    expect(result.items).toHaveLength(2);
    expect(result.skippedLines).toEqual([]);
  });

  it('handles duplicate lines as separate items', () => {
    const text = [
      '56 - EVERYDAY Q LIN 092626 $6.99 T',
      '56 - EVERYDAY Q LIN 092626 $6.99 T',
      '56 - EVERYDAY Q LIN 092626 $6.99 T',
    ].join('\n');
    const result = parseReceiptList(text);
    expect(result.items).toHaveLength(3);
    expect(result.items.every((i) => i.name === 'EVERYDAY Q LIN')).toBe(true);
  });

  it('handles line without T suffix', () => {
    const result = parseReceiptList('48 - WALL ART 323272 $45.00');
    expect(result.items).toEqual([
      { name: 'WALL ART', sku: '323272', priceCents: 4500 },
    ]);
  });

  it('handles price without dollar sign', () => {
    const result = parseReceiptList('48 - WALL ART 323272 45.00 T');
    expect(result.items).toEqual([
      { name: 'WALL ART', sku: '323272', priceCents: 4500 },
    ]);
  });

  it('handles price with comma (e.g. $1,299.99)', () => {
    const result = parseReceiptList('45 - FLORALS 924460 $1,299.99 T');
    expect(result.items).toEqual([
      { name: 'FLORALS', sku: '924460', priceCents: 129999 },
    ]);
  });

  it('collects unparseable lines into skippedLines', () => {
    const text = [
      '53 - ACCENT FURNISH 252972 $129.99 T',
      'SUBTOTAL: $500.00',
      'TAX: $41.25',
      '56 - EVERYDAY Q LIN 092626 $6.99 T',
    ].join('\n');
    const result = parseReceiptList(text);
    expect(result.items).toHaveLength(2);
    expect(result.skippedLines).toEqual(['SUBTOTAL: $500.00', 'TAX: $41.25']);
  });

  it('returns empty arrays for empty input', () => {
    expect(parseReceiptList('')).toEqual({ items: [], skippedLines: [] });
  });

  it('returns empty arrays for whitespace-only input', () => {
    expect(parseReceiptList('   \n\n  \n  ')).toEqual({ items: [], skippedLines: [] });
  });

  it('trims leading/trailing whitespace from lines', () => {
    const result = parseReceiptList('  53 - ACCENT FURNISH 252972 $129.99 T  ');
    expect(result.items).toEqual([
      { name: 'ACCENT FURNISH', sku: '252972', priceCents: 12999 },
    ]);
  });

  it('handles the full example receipt from spec', () => {
    const text = `53 - ACCENT FURNISH 252972 $129.99 T
56 - EVERYDAY Q LIN 092626 $6.99 T
56 - EVERYDAY Q LIN 092626 $6.99 T
56 - EVERYDAY Q LIN 092626 $6.99 T
53 - ACCENT FURNISH 256577 $129.99 T
11 - BATH SHOP 278078 $129.99 T
56 - EVERYDAY Q LIN 092626 $6.99 T
56 - EVERYDAY Q LIN 092626 $6.99 T
56 - EVERYDAY Q LIN 092626 $6.99 T
33 - DECORATIVE ACC 348059 $49.99 T
33 - DECORATIVE ACC 348059 $49.99 T`;
    const result = parseReceiptList(text);
    expect(result.items).toHaveLength(11);
    expect(result.skippedLines).toEqual([]);
    // Spot-check first and last
    expect(result.items[0]).toEqual({ name: 'ACCENT FURNISH', sku: '252972', priceCents: 12999 });
    expect(result.items[10]).toEqual({ name: 'DECORATIVE ACC', sku: '348059', priceCents: 4999 });
  });

  it('handles multi-section receipt with blank line separators', () => {
    const text = `63 - ALT/HANGING LI 522327 $29.99 T
45 - FLORALS 904667 $19.99 T

48 - WALL ART 330069 $29.99 T
33 - DECORATIVE ACC 377616 $19.99 T`;
    const result = parseReceiptList(text);
    expect(result.items).toHaveLength(4);
    expect(result.skippedLines).toEqual([]);
  });

  it('handles SKU with leading zeros', () => {
    const result = parseReceiptList('56 - EVERYDAY Q LIN 092626 $6.99 T');
    expect(result.items[0].sku).toBe('092626');
  });
});
