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

const lightStandard = BUDGET_COLORS.light.standard;
const lightFee = BUDGET_COLORS.light.fee;
const darkStandard = BUDGET_COLORS.dark.standard;
const darkFee = BUDGET_COLORS.dark.fee;

describe('budgetColors', () => {
  describe('getBudgetProgressColor - Standard Categories (light)', () => {
    it('should return green for 0-49% spent', () => {
      expect(getBudgetProgressColor(0, false)).toEqual(lightStandard.green);
      expect(getBudgetProgressColor(25, false)).toEqual(lightStandard.green);
      expect(getBudgetProgressColor(49, false)).toEqual(lightStandard.green);
      expect(getBudgetProgressColor(49.9, false)).toEqual(lightStandard.green);
    });

    it('should return yellow for 50-74% spent', () => {
      expect(getBudgetProgressColor(50, false)).toEqual(lightStandard.yellow);
      expect(getBudgetProgressColor(62, false)).toEqual(lightStandard.yellow);
      expect(getBudgetProgressColor(74, false)).toEqual(lightStandard.yellow);
      expect(getBudgetProgressColor(74.9, false)).toEqual(lightStandard.yellow);
    });

    it('should return red for 75%+ spent', () => {
      expect(getBudgetProgressColor(75, false)).toEqual(lightStandard.red);
      expect(getBudgetProgressColor(80, false)).toEqual(lightStandard.red);
      expect(getBudgetProgressColor(100, false)).toEqual(lightStandard.red);
      expect(getBudgetProgressColor(150, false)).toEqual(lightStandard.red);
    });
  });

  describe('getBudgetProgressColor - Fee Categories (light, inverted)', () => {
    it('should return red for <50% collected', () => {
      expect(getBudgetProgressColor(0, true)).toEqual(lightFee.red);
      expect(getBudgetProgressColor(25, true)).toEqual(lightFee.red);
      expect(getBudgetProgressColor(49, true)).toEqual(lightFee.red);
      expect(getBudgetProgressColor(49.9, true)).toEqual(lightFee.red);
    });

    it('should return yellow for 50-74% collected', () => {
      expect(getBudgetProgressColor(50, true)).toEqual(lightFee.yellow);
      expect(getBudgetProgressColor(62, true)).toEqual(lightFee.yellow);
      expect(getBudgetProgressColor(74, true)).toEqual(lightFee.yellow);
      expect(getBudgetProgressColor(74.9, true)).toEqual(lightFee.yellow);
    });

    it('should return green for 75%+ collected', () => {
      expect(getBudgetProgressColor(75, true)).toEqual(lightFee.green);
      expect(getBudgetProgressColor(80, true)).toEqual(lightFee.green);
      expect(getBudgetProgressColor(100, true)).toEqual(lightFee.green);
      expect(getBudgetProgressColor(150, true)).toEqual(lightFee.green);
    });
  });

  describe('getBudgetProgressColor - Dark mode', () => {
    it('should return dark mode colors when isDark is true', () => {
      expect(getBudgetProgressColor(25, false, true)).toEqual(darkStandard.green);
      expect(getBudgetProgressColor(60, false, true)).toEqual(darkStandard.yellow);
      expect(getBudgetProgressColor(80, false, true)).toEqual(darkStandard.red);
    });

    it('should return dark mode fee colors when isDark is true', () => {
      expect(getBudgetProgressColor(25, true, true)).toEqual(darkFee.red);
      expect(getBudgetProgressColor(60, true, true)).toEqual(darkFee.yellow);
      expect(getBudgetProgressColor(80, true, true)).toEqual(darkFee.green);
    });

    it('dark text colors should be brighter than light text colors', () => {
      // Dark mode text colors should be lighter/brighter for readability
      expect(darkStandard.green.text).not.toEqual(lightStandard.green.text);
      expect(darkStandard.red.text).not.toEqual(lightStandard.red.text);
    });
  });

  describe('getBudgetProgressColor - Edge Cases', () => {
    it('should handle exact threshold boundaries', () => {
      expect(getBudgetProgressColor(50, false)).toEqual(lightStandard.yellow);
      expect(getBudgetProgressColor(75, false)).toEqual(lightStandard.red);
      expect(getBudgetProgressColor(50, true)).toEqual(lightFee.yellow);
      expect(getBudgetProgressColor(75, true)).toEqual(lightFee.green);
    });

    it('should handle negative percentages', () => {
      expect(getBudgetProgressColor(-10, false)).toEqual(lightStandard.green);
      expect(getBudgetProgressColor(-10, true)).toEqual(lightFee.red);
    });

    it('should handle percentages over 100%', () => {
      expect(getBudgetProgressColor(150, false)).toEqual(lightStandard.red);
      expect(getBudgetProgressColor(200, true)).toEqual(lightFee.green);
    });

    it('should handle decimal percentages', () => {
      expect(getBudgetProgressColor(49.999, false)).toEqual(lightStandard.green);
      expect(getBudgetProgressColor(50.001, false)).toEqual(lightStandard.yellow);
      expect(getBudgetProgressColor(74.999, false)).toEqual(lightStandard.yellow);
      expect(getBudgetProgressColor(75.001, false)).toEqual(lightStandard.red);
    });
  });

  describe('getOverflowColor', () => {
    it('should return light overflow color by default', () => {
      const color = getOverflowColor();
      expect(color).toEqual(lightStandard.overflow);
    });

    it('should return dark overflow color when isDark is true', () => {
      const color = getOverflowColor(true);
      expect(color).toEqual(darkStandard.overflow);
    });

    it('should return consistent overflow color on multiple calls', () => {
      expect(getOverflowColor()).toEqual(getOverflowColor());
      expect(getOverflowColor(true)).toEqual(getOverflowColor(true));
    });

    it('should return object with bar and text properties', () => {
      const color = getOverflowColor();
      expect(color).toHaveProperty('bar');
      expect(color).toHaveProperty('text');
      expect(typeof color.bar).toBe('string');
      expect(typeof color.text).toBe('string');
    });
  });

  describe('BUDGET_COLORS constant', () => {
    it('should have light and dark themes', () => {
      expect(BUDGET_COLORS.light).toBeDefined();
      expect(BUDGET_COLORS.dark).toBeDefined();
    });

    it('should have correct structure for standard colors', () => {
      for (const mode of ['light', 'dark'] as const) {
        const standard = BUDGET_COLORS[mode].standard;
        expect(standard.green).toHaveProperty('bar');
        expect(standard.green).toHaveProperty('text');
        expect(standard.yellow).toHaveProperty('bar');
        expect(standard.yellow).toHaveProperty('text');
        expect(standard.red).toHaveProperty('bar');
        expect(standard.red).toHaveProperty('text');
        expect(standard.overflow).toHaveProperty('bar');
        expect(standard.overflow).toHaveProperty('text');
      }
    });

    it('should have correct structure for fee colors', () => {
      for (const mode of ['light', 'dark'] as const) {
        const fee = BUDGET_COLORS[mode].fee;
        expect(fee.green).toHaveProperty('bar');
        expect(fee.green).toHaveProperty('text');
        expect(fee.yellow).toHaveProperty('bar');
        expect(fee.yellow).toHaveProperty('text');
        expect(fee.red).toHaveProperty('bar');
        expect(fee.red).toHaveProperty('text');
      }
    });

    it('should use valid hex color codes', () => {
      const hexColorRegex = /^#[0-9A-F]{6}$/i;

      for (const mode of ['light', 'dark'] as const) {
        const standard = BUDGET_COLORS[mode].standard;
        const fee = BUDGET_COLORS[mode].fee;

        expect(standard.green.bar).toMatch(hexColorRegex);
        expect(standard.green.text).toMatch(hexColorRegex);
        expect(standard.yellow.bar).toMatch(hexColorRegex);
        expect(standard.yellow.text).toMatch(hexColorRegex);
        expect(standard.red.bar).toMatch(hexColorRegex);
        expect(standard.red.text).toMatch(hexColorRegex);
        expect(standard.overflow.bar).toMatch(hexColorRegex);
        expect(standard.overflow.text).toMatch(hexColorRegex);

        expect(fee.green.bar).toMatch(hexColorRegex);
        expect(fee.green.text).toMatch(hexColorRegex);
        expect(fee.yellow.bar).toMatch(hexColorRegex);
        expect(fee.yellow.text).toMatch(hexColorRegex);
        expect(fee.red.bar).toMatch(hexColorRegex);
        expect(fee.red.text).toMatch(hexColorRegex);
      }
    });
  });
});
