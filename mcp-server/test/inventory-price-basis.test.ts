import { describe, expect, test } from "vitest";
import { usesProjectPriceForAudit } from "../src/util/inventory.js";
import {
  computeProjectOriginAcquisitionTotals,
  computeProjectToInventoryTotals,
} from "../src/tools/inventory-operations.js";

describe("usesProjectPriceForAudit", () => {
  test("uses project price for branded inventory Purchases into a project", () => {
    expect(usesProjectPriceForAudit({
      type: "Purchase",
      projectId: "project-1",
      source: "1584 Design Inventory",
    })).toBe(true);
  });

  test("keeps ordinary vendor Purchases purchase-price based", () => {
    expect(usesProjectPriceForAudit({
      type: "Purchase",
      projectId: "project-1",
      source: "Wayfair",
    })).toBe(false);
  });

  test("uses project price for inventory Returns", () => {
    expect(usesProjectPriceForAudit({
      type: "Return",
      projectId: "project-1",
      source: "1584 Design Inventory",
    })).toBe(true);
  });

  test("keeps project-originated Sales to inventory purchase-price based", () => {
    expect(usesProjectPriceForAudit({
      type: "Sale",
      projectId: "project-1",
      source: "1584 Design Inventory",
    })).toBe(false);
  });
});

describe("computeProjectToInventoryTotals", () => {
  test("reverses an inventory sale at project price rather than supplier cost", () => {
    expect(computeProjectToInventoryTotals([{
      id: "4Bif6MOIMAYlaq84k0HR",
      purchasePriceCents: 699,
      projectPriceCents: 965,
    }])).toEqual({
      subtotalCents: 965,
      amountCents: 965,
      missingTax: ["4Bif6MOIMAYlaq84k0HR"],
    });
  });
});

describe("computeProjectOriginAcquisitionTotals", () => {
  test("does not overpay when malformed project price exceeds purchase cost", () => {
    expect(computeProjectOriginAcquisitionTotals([{
      id: "project-originated-item",
      purchasePriceCents: 1000,
      projectPriceCents: 1500,
      taxRatePct: 10,
    }])).toEqual({
      subtotalCents: 1000,
      amountCents: 1000,
      missingTax: [],
    });
  });
});
