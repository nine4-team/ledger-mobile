import { describe, expect, test } from "vitest";
import { normalizeSpendAmount } from "../src/util/budget.js";

describe("normalizeSpendAmount", () => {
  test("counts paymentToBusiness as positive received budget activity", () => {
    expect(
      normalizeSpendAmount({
        id: "tx_payment",
        type: "paymentToBusiness",
        amountCents: 25000,
      })
    ).toBe(25000);
  });

  test("keeps canceled paymentToBusiness at zero", () => {
    expect(
      normalizeSpendAmount({
        id: "tx_canceled_payment",
        type: "paymentToBusiness",
        amountCents: 25000,
        status: "canceled",
      })
    ).toBe(0);
  });
});
