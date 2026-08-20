import { describe, expect, test } from "vitest";
import { usesProjectPriceForAudit } from "../src/util/inventory.js";

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

  test("keeps inventory Returns purchase-price based", () => {
    expect(usesProjectPriceForAudit({
      type: "Return",
      projectId: "project-1",
      source: "1584 Design Inventory",
    })).toBe(false);
  });
});
