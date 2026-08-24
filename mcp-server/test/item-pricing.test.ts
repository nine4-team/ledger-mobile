import { describe, expect, it } from "vitest";
import {
  applyItemPriceFloorToCreate,
  applyItemPriceFloorToUpdate,
  effectiveProjectPriceCents,
  normalizedProjectPriceCents,
} from "../src/util/item-pricing.js";

describe("item price floor", () => {
  it("copies purchase price when project price is absent", () => {
    expect(normalizedProjectPriceCents(12500, undefined)).toBe(12500);
    expect(applyItemPriceFloorToCreate({}, { purchasePriceCents: 12500 })).toEqual({
      projectPriceCents: 12500,
    });
  });

  it("raises a lower explicit project price", () => {
    expect(effectiveProjectPriceCents({
      purchasePriceCents: 12500,
      projectPriceCents: 0,
    })).toBe(12500);
  });

  it("preserves higher markup when purchase price falls", () => {
    const updates = applyItemPriceFloorToUpdate(
      { purchasePriceCents: 12500, projectPriceCents: 15000 },
      { purchasePriceCents: 10000 }
    );
    expect(updates.projectPriceCents).toBe(15000);
  });

  it("uses merged state when only purchase price rises", () => {
    const updates = applyItemPriceFloorToUpdate(
      { purchasePriceCents: 12500, projectPriceCents: 15000 },
      { purchasePriceCents: 17500 }
    );
    expect(updates.projectPriceCents).toBe(17500);
  });
});
