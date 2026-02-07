/**
 * Budget colors utility tests
 *
 * Tests the color threshold logic for budget progress indicators.
 * Standard categories use normal thresholds (green=low, red=high),
 * while fee categories use inverted thresholds (green=high, red=low).
 */

import {
  getBudgetProgressColor,
  getOverflowColor,
  BUDGET_COLORS,
} from '../budgetColors';

describe('budgetColors', () => {
  describe('getBudgetProgressColor - Standard Categories', () => {
    it('should return green for 0-49% spent', () => {
      // Test boundary values
      expect(getBudgetProgressColor(0, false)).toEqual(
        BUDGET_COLORS.standard.green
      );
      expect(getBudgetProgressColor(25, false)).toEqual(
        BUDGET_COLORS.standard.green
      );
      expect(getBudgetProgressColor(49, false)).toEqual(
        BUDGET_COLORS.standard.green
      );
      expect(getBudgetProgressColor(49.9, false)).toEqual(
        BUDGET_COLORS.standard.green
      );
    });

    it('should return yellow for 50-74% spent', () => {
      // Test boundary values
      expect(getBudgetProgressColor(50, false)).toEqual(
        BUDGET_COLORS.standard.yellow
      );
      expect(getBudgetProgressColor(62, false)).toEqual(
        BUDGET_COLORS.standard.yellow
      );
      expect(getBudgetProgressColor(74, false)).toEqual(
        BUDGET_COLORS.standard.yellow
      );
      expect(getBudgetProgressColor(74.9, false)).toEqual(
        BUDGET_COLORS.standard.yellow
      );
    });

    it('should return red for 75%+ spent', () => {
      // Test boundary values
      expect(getBudgetProgressColor(75, false)).toEqual(
        BUDGET_COLORS.standard.red
      );
      expect(getBudgetProgressColor(80, false)).toEqual(
        BUDGET_COLORS.standard.red
      );
      expect(getBudgetProgressColor(100, false)).toEqual(
        BUDGET_COLORS.standard.red
      );
      expect(getBudgetProgressColor(150, false)).toEqual(
        BUDGET_COLORS.standard.red
      );
    });
  });

  describe('getBudgetProgressColor - Fee Categories (Inverted)', () => {
    it('should return red for <50% collected (inverted logic)', () => {
      // For fee categories, low percentage is bad (red)
      expect(getBudgetProgressColor(0, true)).toEqual(BUDGET_COLORS.fee.red);
      expect(getBudgetProgressColor(25, true)).toEqual(BUDGET_COLORS.fee.red);
      expect(getBudgetProgressColor(49, true)).toEqual(BUDGET_COLORS.fee.red);
      expect(getBudgetProgressColor(49.9, true)).toEqual(
        BUDGET_COLORS.fee.red
      );
    });

    it('should return yellow for 50-74% collected (inverted logic)', () => {
      // For fee categories, medium percentage is caution (yellow)
      expect(getBudgetProgressColor(50, true)).toEqual(
        BUDGET_COLORS.fee.yellow
      );
      expect(getBudgetProgressColor(62, true)).toEqual(
        BUDGET_COLORS.fee.yellow
      );
      expect(getBudgetProgressColor(74, true)).toEqual(
        BUDGET_COLORS.fee.yellow
      );
      expect(getBudgetProgressColor(74.9, true)).toEqual(
        BUDGET_COLORS.fee.yellow
      );
    });

    it('should return green for 75%+ collected (inverted logic)', () => {
      // For fee categories, high percentage is good (green)
      expect(getBudgetProgressColor(75, true)).toEqual(
        BUDGET_COLORS.fee.green
      );
      expect(getBudgetProgressColor(80, true)).toEqual(
        BUDGET_COLORS.fee.green
      );
      expect(getBudgetProgressColor(100, true)).toEqual(
        BUDGET_COLORS.fee.green
      );
      expect(getBudgetProgressColor(150, true)).toEqual(
        BUDGET_COLORS.fee.green
      );
    });
  });

  describe('getBudgetProgressColor - Edge Cases', () => {
    it('should handle exact threshold boundaries', () => {
      // Standard category boundaries
      expect(getBudgetProgressColor(50, false)).toEqual(
        BUDGET_COLORS.standard.yellow
      );
      expect(getBudgetProgressColor(75, false)).toEqual(
        BUDGET_COLORS.standard.red
      );

      // Fee category boundaries
      expect(getBudgetProgressColor(50, true)).toEqual(
        BUDGET_COLORS.fee.yellow
      );
      expect(getBudgetProgressColor(75, true)).toEqual(
        BUDGET_COLORS.fee.green
      );
    });

    it('should handle negative percentages', () => {
      // Negative percentages should follow the same logic as 0%
      expect(getBudgetProgressColor(-10, false)).toEqual(
        BUDGET_COLORS.standard.green
      );
      expect(getBudgetProgressColor(-10, true)).toEqual(BUDGET_COLORS.fee.red);
    });

    it('should handle percentages over 100%', () => {
      // Over 100% should still follow the same thresholds
      expect(getBudgetProgressColor(150, false)).toEqual(
        BUDGET_COLORS.standard.red
      );
      expect(getBudgetProgressColor(200, true)).toEqual(
        BUDGET_COLORS.fee.green
      );
    });

    it('should handle decimal percentages', () => {
      // Precise decimal values
      expect(getBudgetProgressColor(49.999, false)).toEqual(
        BUDGET_COLORS.standard.green
      );
      expect(getBudgetProgressColor(50.001, false)).toEqual(
        BUDGET_COLORS.standard.yellow
      );
      expect(getBudgetProgressColor(74.999, false)).toEqual(
        BUDGET_COLORS.standard.yellow
      );
      expect(getBudgetProgressColor(75.001, false)).toEqual(
        BUDGET_COLORS.standard.red
      );
    });
  });

  describe('getOverflowColor', () => {
    it('should return overflow color', () => {
      const color = getOverflowColor();
      expect(color).toEqual(BUDGET_COLORS.standard.overflow);
    });

    it('should return consistent overflow color on multiple calls', () => {
      const color1 = getOverflowColor();
      const color2 = getOverflowColor();
      expect(color1).toEqual(color2);
    });

    it('should return object with bar and text properties', () => {
      const color = getOverflowColor();
      expect(color).toHaveProperty('bar');
      expect(color).toHaveProperty('text');
      expect(typeof color.bar).toBe('string');
      expect(typeof color.text).toBe('string');
    });

    it('should return darker colors for overflow', () => {
      const overflow = getOverflowColor();
      const red = BUDGET_COLORS.standard.red;

      // Overflow should be darker than regular red
      // #991B1B and #7F1D1D are darker than #EF4444 and #DC2626
      expect(overflow.bar).toBe('#991B1B');
      expect(overflow.text).toBe('#7F1D1D');
      expect(overflow).not.toEqual(red);
    });
  });

  describe('BUDGET_COLORS constant', () => {
    it('should have correct structure for standard colors', () => {
      expect(BUDGET_COLORS.standard).toBeDefined();
      expect(BUDGET_COLORS.standard.green).toHaveProperty('bar');
      expect(BUDGET_COLORS.standard.green).toHaveProperty('text');
      expect(BUDGET_COLORS.standard.yellow).toHaveProperty('bar');
      expect(BUDGET_COLORS.standard.yellow).toHaveProperty('text');
      expect(BUDGET_COLORS.standard.red).toHaveProperty('bar');
      expect(BUDGET_COLORS.standard.red).toHaveProperty('text');
      expect(BUDGET_COLORS.standard.overflow).toHaveProperty('bar');
      expect(BUDGET_COLORS.standard.overflow).toHaveProperty('text');
    });

    it('should have correct structure for fee colors', () => {
      expect(BUDGET_COLORS.fee).toBeDefined();
      expect(BUDGET_COLORS.fee.green).toHaveProperty('bar');
      expect(BUDGET_COLORS.fee.green).toHaveProperty('text');
      expect(BUDGET_COLORS.fee.yellow).toHaveProperty('bar');
      expect(BUDGET_COLORS.fee.yellow).toHaveProperty('text');
      expect(BUDGET_COLORS.fee.red).toHaveProperty('bar');
      expect(BUDGET_COLORS.fee.red).toHaveProperty('text');
    });

    it('should use valid hex color codes', () => {
      const hexColorRegex = /^#[0-9A-F]{6}$/i;

      // Test all standard colors
      expect(BUDGET_COLORS.standard.green.bar).toMatch(hexColorRegex);
      expect(BUDGET_COLORS.standard.green.text).toMatch(hexColorRegex);
      expect(BUDGET_COLORS.standard.yellow.bar).toMatch(hexColorRegex);
      expect(BUDGET_COLORS.standard.yellow.text).toMatch(hexColorRegex);
      expect(BUDGET_COLORS.standard.red.bar).toMatch(hexColorRegex);
      expect(BUDGET_COLORS.standard.red.text).toMatch(hexColorRegex);
      expect(BUDGET_COLORS.standard.overflow.bar).toMatch(hexColorRegex);
      expect(BUDGET_COLORS.standard.overflow.text).toMatch(hexColorRegex);

      // Test all fee colors
      expect(BUDGET_COLORS.fee.green.bar).toMatch(hexColorRegex);
      expect(BUDGET_COLORS.fee.green.text).toMatch(hexColorRegex);
      expect(BUDGET_COLORS.fee.yellow.bar).toMatch(hexColorRegex);
      expect(BUDGET_COLORS.fee.yellow.text).toMatch(hexColorRegex);
      expect(BUDGET_COLORS.fee.red.bar).toMatch(hexColorRegex);
      expect(BUDGET_COLORS.fee.red.text).toMatch(hexColorRegex);
    });
  });
});
