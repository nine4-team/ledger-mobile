import { describe, expect, it } from "vitest";
import {
  checkCreateInvariant,
  checkTransactionLinkageOnCreate,
  checkTransactionLinkageOnUpdate,
  checkUpdateInvariant,
} from "../src/tools/items.js";

describe("item category and transaction invariants", () => {
  it("rejects blank and sentinel categories for project item creation", () => {
    expect(checkCreateInvariant("project-1", undefined)).toContain("real budgetCategoryId");
    expect(checkCreateInvariant("project-1", "uncategorized")).toContain("real budgetCategoryId");
    expect(checkCreateInvariant("project-1", "cat-1")).toBeNull();
  });

  it("rejects every persisted category value in inventory scope", () => {
    expect(checkCreateInvariant(null, "cat-1")).toContain("inventory item");
    expect(checkCreateInvariant(null, "")).toContain("inventory item");
    expect(checkCreateInvariant(null, null)).toBeNull();
    expect(checkUpdateInvariant(
      { projectId: null, budgetCategoryId: null },
      { budgetCategoryId: "uncategorized" }
    )).toContain("business inventory");
  });

  it("keeps new project-item creation strict about transaction linkage", () => {
    expect(checkTransactionLinkageOnCreate("project-1", undefined)).toContain("transactionId");
    expect(checkTransactionLinkageOnCreate("project-1", "tx-1")).toBeNull();
  });

  it("allows an existing project item to enter No Transaction state", () => {
    expect(checkTransactionLinkageOnUpdate(
      { projectId: "project-1", transactionId: "tx-1" },
      { transactionId: null }
    )).toEqual({ kind: "ok" });
  });

  it("still requires a real category after clearing a transaction", () => {
    expect(checkUpdateInvariant(
      { projectId: "project-1", budgetCategoryId: "cat-1" },
      { transactionId: null }
    )).toBeNull();
    expect(checkUpdateInvariant(
      { projectId: "project-1", budgetCategoryId: "cat-1" },
      { transactionId: null, budgetCategoryId: null }
    )).toContain("real budgetCategoryId");
  });
});
