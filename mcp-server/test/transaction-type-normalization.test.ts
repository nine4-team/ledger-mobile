import { describe, expect, test } from "vitest";
import {
  isReturnTransactionType,
  normalizeTransactionType,
} from "../src/util/enums.js";

describe("normalizeTransactionType", () => {
  test.each([
    ["Return", "return"],
    ["return", "return"],
    ["rEtUrN", "return"],
    ["Purchase", "purchase"],
    ["sale", "sale"],
    ["PaymentToBusiness", "paymentToBusiness"],
  ])("normalizes %j to %j", (value, expected) => {
    expect(normalizeTransactionType(value)).toBe(expected);
  });

  test.each([" RETURN ", "returned", "", null, undefined, 42])(
    "rejects invalid value %j",
    (value) => {
      expect(normalizeTransactionType(value)).toBeNull();
      expect(isReturnTransactionType(value)).toBe(false);
    }
  );

  test.each(["Return", "return", "rEtUrN"])(
    "recognizes return value %j",
    (value) => {
      expect(isReturnTransactionType(value)).toBe(true);
    }
  );
});
