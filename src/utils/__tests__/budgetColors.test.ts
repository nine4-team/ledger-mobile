/**
 * Budget colors utility tests
 *
 * All budget bars use a single brand color (BUDGET_BAR_COLOR).
 * Only overflow retains a distinct color for over-budget emphasis.
 */

import {
  BUDGET_BAR_COLOR,
  getOverflowColor,
} from '../budgetColors';

describe('budgetColors', () => {
  describe('BUDGET_BAR_COLOR', () => {
    it('should be the brand color hex', () => {
      expect(BUDGET_BAR_COLOR).toBe('#987e55');
    });

    it('should be a valid hex color', () => {
      expect(BUDGET_BAR_COLOR).toMatch(/^#[0-9A-Fa-f]{6}$/);
    });
  });

  describe('getOverflowColor', () => {
    it('should return light overflow color by default', () => {
      const color = getOverflowColor();
      expect(color).toEqual({ bar: '#DC2626', text: '#DC2626' });
    });

    it('should return dark overflow color when isDark is true', () => {
      const color = getOverflowColor(true);
      expect(color).toEqual({ bar: '#F87171', text: '#F87171' });
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

    it('should use the same color for bar and text so they match', () => {
      expect(getOverflowColor().bar).toEqual(getOverflowColor().text);
      expect(getOverflowColor(true).bar).toEqual(getOverflowColor(true).text);
    });
  });
});
