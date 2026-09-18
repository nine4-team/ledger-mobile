import assert from "node:assert/strict";
import test from "node:test";
import { calculateItemAdjustments, inclusiveItemPriceInput } from "../src/liveItemAdjustments.js";
import { makeItemPriceEditRequest } from "../src/itemPriceEdit.js";

test("unadjusted overflow is invalid and allocated cent breakdowns reconcile", () => {
  const [n,d] = inclusiveItemPriceInput(9223372036854775807n,1n,-1n)!;
  const overflow = calculateItemAdjustments(1n,-1n,[{itemId:"a",numerator:String(n),denominator:String(d)}]);
  assert.equal(overflow.differenceNumerator,null);
  assert.deepEqual(overflow.items[0],{itemId:"a",unadjustedMinorUnits:null,adjustmentsMinorUnits:null,
    projectPriceMinorUnits:null,issue:"arithmeticRange"});
  const inputs = ["a","b"].map(itemId => ({itemId,numerator:"1",denominator:"2"}));
  const result = calculateItemAdjustments(2n,1n,inputs);
  assert.deepEqual(result.items.map(item=>item.unadjustedMinorUnits),["1","0"]);
  assert.deepEqual(result.items.map(item=>item.adjustmentsMinorUnits),["0","1"]);
  for(const item of result.items) assert.equal(BigInt(item.unadjustedMinorUnits!)+BigInt(item.adjustmentsMinorUnits!),BigInt(item.projectPriceMinorUnits!));
  assert.deepEqual(calculateItemAdjustments(2n,1n,[...inputs].reverse()).items.reverse(),result.items);
});

test("near-half-cent values are not rounded by intermediate division", () => {
  const actual = calculateItemAdjustments(2n, 1n, [{ itemId: "a",
    numerator: "49999999999999999999999999999999999998", denominator: "99999999999999999999999999999999999997" }]);
  assert.equal(actual.items[0].adjustmentsMinorUnits, "0");
  assert.equal(actual.items[0].projectPriceMinorUnits, "1");
});

test("whole order base, signed pennies, exact inverse and order independence", () => {
  const partial = calculateItemAdjustments(12000n, 2000n, [{ itemId: "a", numerator: "1000", denominator: "1" }]);
  assert.equal(partial.items[0].adjustmentsMinorUnits, "200");
  assert.equal(partial.isProvisional, true);
  for (const adjustment of [-1n, 1n]) {
    const inputs = ["c", "a", "b"].map(itemId => ({ itemId, numerator: "1", denominator: "1" }));
    const first = calculateItemAdjustments(3n + adjustment, adjustment, inputs);
    const reverse = calculateItemAdjustments(3n + adjustment, adjustment, [...inputs].reverse());
    assert.deepEqual([...first.items].sort((a, b) => a.itemId.localeCompare(b.itemId)),
      [...reverse.items].sort((a, b) => a.itemId.localeCompare(b.itemId)));
    assert.equal(first.items.reduce((sum, item) => sum + BigInt(item.projectPriceMinorUnits!), 0n), 3n + adjustment);
    assert.equal(first.items.reduce((sum, item) => sum + BigInt(item.adjustmentsMinorUnits!), 0n), adjustment);
  }
  for (let total = 1n; total <= 80n; total++) {
    for (const adjustment of [-31n, -1n, 0n, 1n, 13n, 37n].filter(value => value < total)) {
      const requested = total / 2n;
      const inputs = [requested, total - requested].map((price, i) => {
        const [n, d] = inclusiveItemPriceInput(price, total, adjustment)!;
        return { itemId: String(i), numerator: String(n), denominator: String(d) };
      });
      const actual = calculateItemAdjustments(total, adjustment, inputs);
      assert.equal(actual.isBalanced, true);
      assert.deepEqual(actual.items.map(item => item.projectPriceMinorUnits), [String(requested), String(total - requested)]);
    }
  }
});

test("zero/incomplete inputs stay distinct and v3 intent carries input revision", () => {
  assert.equal(inclusiveItemPriceInput(100n, 0n, -20n), null);
  assert.equal(inclusiveItemPriceInput(100n, 20n, 20n), null);
  assert.equal(calculateItemAdjustments(120n, 20n, [{ itemId: "a", numerator: null, denominator: null }]).differenceNumerator, null);
  const request = makeItemPriceEditRequest({ operationUUID: "11111111-2222-3333-4444-555555555555",
    clientCreatedAtMilliseconds: 123, payload: { projectId: "project", itemId: "item", placementId: "placement",
      occurrenceId: "charge", expectedPriceRevision: "1", expectedChargeRevision: "1", transactionId: "order",
      expectedAdjustmentRevision: "4", requestedPriceMinorUnits: "0", reviewedPriceMinorUnits: "0", currency: "USD" } },
  { accountId: "account", principalId: "principal", accessToken: "user-token" });
  const wire = JSON.parse(request.commandJSON);
  assert.equal(wire.contractVersion, "item-live-adjustment-price-edit-v3");
  assert.equal(wire.expectedAdjustmentRevision, "4");
  assert.equal(wire.requestedPriceMinorUnits, "0");
});
