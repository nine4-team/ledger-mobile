import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { transactionDetail } from "../src/transactionDetailRead.js";
import { invoiceDisplayMetadataSchema } from "../src/transactionPaymentContents.js";

test("Invoice display metadata preserves optional text and exact timestamp strings", () => {
  const value={invoiceNumber:"  INV-001  ",notes:"First\nSecond",paidAtMilliseconds:"-1"};
  assert.deepEqual(invoiceDisplayMetadataSchema.parse(value),value);
  for(const invalid of ["01","-0","1.5","253402300800000","-62135596800001",1]) {
    assert.equal(invoiceDisplayMetadataSchema.safeParse({paidAtMilliseconds:invalid}).success,false);
  }
  assert.equal(invoiceDisplayMetadataSchema.safeParse({unexpected:"value"}).success,false);
  assert.equal(invoiceDisplayMetadataSchema.safeParse({notes:"bad\0notes"}).success,false);
});

const contents = () => JSON.parse(readFileSync(new URL("./fixtures/payment-contents.json", import.meta.url), "utf8"));
const context = { accountId: "account", principalId: "principal", accessToken: "unused-read-validation" };
function detail(paymentContents = contents()) {
  const value = JSON.parse(readFileSync(new URL("./fixtures/transaction-detail.json", import.meta.url), "utf8"));
  return { ...value, accountId: "account", principalId: "principal", transactionId: "payment",
    scopeKind: "project", projectId: "project", clientId: "client", type: "purchase", origin: "firebase_client_payment",
    category: null, receipt: null, paymentContents };
}
test("shared native fixture preserves closed links, frozen text and exact wire JSON", () => {
  const value = detail(), result = transactionDetail(value, "payment", context);
  assert.deepEqual(result.paymentContents, value.paymentContents);
  assert.equal(result.receipt, null);
  assert.equal(result.paymentContents?.connections.length, 2);
});
test("embedded frozen Int64 amounts never pass through a rounded JS Number", () => {
  for (const raw of ["125.0", "1.25e2", "9007199254740993", "9223372036854775807"]) {
    const value = detail(), invoice = value.paymentContents.invoice, line = invoice.lines[0];
    invoice.total_minor_units = line.signed_amount_minor_units = raw.includes(".") ? "125" : raw;
    line.source_snapshot_json = line.source_snapshot_json.replace('"minorUnits":125', `"minorUnits":${raw}`);
    const result = transactionDetail(value, "payment", context);
    assert.equal(result.paymentContents?.invoice?.lines[0].source_snapshot_json, line.source_snapshot_json);
  }
  const value = detail(), invoice = value.paymentContents.invoice;
  invoice.total_minor_units = invoice.lines[0].signed_amount_minor_units = "9007199254740993";
  invoice.lines[0].source_snapshot_json = invoice.lines[0].source_snapshot_json.replace('"minorUnits":125', '"minorUnits":9007199254740992');
  assert.throws(() => transactionDetail(value, "payment", context), { code: "transaction_detail_server_result_mismatch" });
});
test("wrong scope, duplicate history, malformed source and changed frozen totals are denied", () => {
  for (const change of [
    (v: any) => { v.paymentContents.principalId = "other"; },
    (v: any) => { v.paymentContents.invoice.purchase_id = "other"; },
    (v: any) => { v.paymentContents.invoice.currency = "EUR"; },
    (v: any) => { v.paymentContents.connections.push(v.paymentContents.connections[0]); },
    (v: any) => { v.paymentContents.invoice.total_minor_units = "126"; },
    (v: any) => { v.paymentContents.invoice.lines[0].line_position = 1; },
    (v: any) => { v.paymentContents.invoice.lines[0].item_id = null; },
    (v: any) => { v.paymentContents.items[0].itemId = "foreign"; },
    (v: any) => { v.paymentContents.items.pop(); },
    (v: any) => { v.paymentContents.items.push(v.paymentContents.items[0]); },
    (v: any) => { v.paymentContents.items[0].imageCount = "-1"; },
    (v: any) => { v.paymentContents.invoice.lines[0].source_snapshot_json = '{}'; },
    (v: any) => { v.paymentContents.invoice.lines[0].source_snapshot_json = v.paymentContents.invoice.lines[0].source_snapshot_json.replace('"minorUnits":125', '"minorUnits":125.5'); },
  ]) {
    const value = detail(); change(value);
    assert.throws(() => transactionDetail(value, "payment", context), { code: "transaction_detail_server_result_mismatch" });
  }
});
test("a standalone payment does not invent an Invoice or Item relationships", () => {
  const value = detail({ ...contents(), connections: [], invoice: null, items: [] });
  assert.deepEqual(transactionDetail(value, "payment", context).paymentContents, value.paymentContents);
});
