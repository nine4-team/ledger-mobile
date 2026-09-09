import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import test from "node:test";
import { accounted } from "./fixtures/propertyManagementAccounting.js";
import {
  buildPropertyManagementReportSnapshot as build,
  encodePropertyManagementReportContent, encodePropertyManagementReportSnapshot as encode,
  type PropertyManagementReportInput, type PropertyManagementReportSnapshot,
} from "../src/propertyManagementReport.js";

const golden = readFileSync(new URL("./fixtures/property-management-report-online.json", import.meta.url), "utf8").trimEnd();
const expected = JSON.parse(golden) as PropertyManagementReportSnapshot;
function input(): PropertyManagementReportInput {
  return structuredClone({ project: expected.project, spaces: expected.spaces,
    items: expected.groups.flatMap(group => group.rows).map(item => ({ ...item, accounting: accounted(item) })),
    currency: expected.currency, provenance: expected.provenance });
}
function one(value: string | null): PropertyManagementReportInput {
  const original = input();
  const item = { ...original.items[0], spaceId: null,
    marketValueMinorUnits: value, marketValueCurrency: value === null ? null : original.currency };
  return { ...original, items: [{ ...item, accounting: accounted(item) }] };
}
function rejects(change: (value: any) => void, code: string): void {
  const candidate = input(); change(candidate);
  assert.throws(() => build(candidate), { code: `property_report_${code}` });
}

test("matches exact Swift canonical snapshot bytes and hashes for authoritative facts", () => {
  const original = input();
  assert.equal(encode(build(original)), golden);
  assert.equal(encode(build({ ...original, spaces: [...original.spaces].reverse(), items: [...original.items].reverse() })), golden);
  const snapshot = build(original);
  assert.equal(createHash("sha256").update(encodePropertyManagementReportContent(snapshot)).digest("hex"), snapshot.reference.snapshotHash);
  assert.deepEqual(snapshot.provenance.source, { kind: "authoritative" });
  assert.ok(!("localDataVersion" in snapshot.provenance));
  assert.ok(!("lastSyncedAt" in snapshot.provenance));
  assert.ok(snapshot.groups.some(group => group.spaceId !== undefined && group.name === "No Space"));
  assert.ok(snapshot.groups.some(group => !Object.hasOwn(group, "spaceId")));
  assert.deepEqual(original, input(), "construction must not mutate caller-owned arrays/rows");
});

test("preserves zero, unknown, signed Int64 bounds and rejects intermediate sum overflow", () => {
  for (const value of ["0", "-1", "9007199254740993", "9223372036854775807", "-9223372036854775808"]) {
    assert.equal(build(one(value)).totals.totalMarketValueMinorUnits, value);
  }
  assert.equal(build(one(null)).totals.totalMarketValueMinorUnits, null);
  assert.equal(build(one(null)).totals.unknownMarketValueCount, 1);
  const base = one("9223372036854775807");
  const row = base.items[0];
  const overflow = { ...base, items: [
    { ...row, itemId: "a", placementId: "pa", name: "a" },
    { ...row, itemId: "b", placementId: "pb", name: "b", marketValueMinorUnits: "1" },
    { ...row, itemId: "c", placementId: "pc", name: "c", marketValueMinorUnits: "-1" },
  ].map(item => ({ ...item, accounting: accounted(item) })) };
  assert.throws(() => build(overflow), { code: "property_report_arithmetic_overflow" });
  for (const value of ["1.5", "01", "-0", "+1", "1e2", "9223372036854775808", "-9223372036854775809"]) {
    assert.throws(() => build(one(value)), { code: "property_report_invalid_amount" });
  }
  const empty = build({ ...input(), items: [] });
  assert.equal(empty.groups.length, 0);
  assert.equal(empty.totals.totalMarketValueMinorUnits, "0");
});

test("rejects scope, parents, duplicates, malformed revisions/currency and fabricated source evidence", () => {
  rejects(x => x.project.accountId = "foreign", "scope_mismatch");
  rejects(x => x.items[0].projectId = "foreign", "scope_mismatch");
  rejects(x => x.spaces[0].accountId = "foreign", "scope_mismatch");
  rejects(x => x.items[0].spaceId = "missing", "missing_space");
  rejects(x => x.spaces.push(x.spaces[0]), "duplicate_space");
  rejects(x => x.items.push(x.items[0]), "duplicate_item");
  rejects(x => x.items.push({ ...x.items[0], itemId: "new-item" }), "duplicate_placement");
  for (const value of ["0", "01", "-1", "18446744073709551616"]) rejects(x => x.project.revision = value, "invalid_revision");
  rejects(x => { x.items[0].marketValueMinorUnits = "1"; x.items[0].marketValueCurrency = "EUR"; }, "mixed_currency");
  rejects(x => { x.items[0].marketValueMinorUnits = "1"; x.items[0].marketValueCurrency = null; }, "invalid_amount");
  rejects(x => x.currency = "usd", "invalid_currency");
  rejects(x => x.provenance.readiness = "partial", "incomplete_readiness");
  rejects(x => x.provenance.source = { kind: "downloaded" }, "invalid_source");
  rejects(x => x.provenance.source.lastSyncedAt = 1000, "invalid_source");
  rejects(x => x.provenance.localDataVersion = "fake", "invalid_source");
  rejects(x => x.provenance.asOf = Number.MAX_SAFE_INTEGER + 1, "invalid_timestamp");
  rejects(x => x.items[0].name = "\ud800", "invalid_text");
});

test("uses UTF8 byte ordering, not JavaScript UTF16 or locale order, and identity tie breaks", () => {
  const base = one("1"), row = base.items[0];
  const names = ["😀", "\ue000", "é", "A", "A"];
  const items = names.map((name, i) => ({ ...row, name, itemId: `item-${4-i}`, placementId: `placement-${i}` }))
    .map(item => ({ ...item, accounting: accounted(item) }));
  const snapshot = build({ ...base, items });
  assert.deepEqual(snapshot.groups[0].rows.map(row => row.name), ["A", "A", "é", "\ue000", "😀"]);
  assert.deepEqual(snapshot.groups[0].rows.slice(0, 2).map(row => row.itemId), ["item-0", "item-1"]);
});

test("unknown relationship evidence blocks a completed report, including missing legacy evidence", () => {
  rejects(x => delete x.items[0].accounting, "incomplete_readiness");
  rejects(x => x.items[0].accounting = null, "incomplete_readiness");
  rejects(x => {
    x.items[0].accounting.evidence.billableOccurrences = [];
    x.items[0].accounting.relationshipAbsenceIsAuthoritative = false;
    x.items[0].accounting.resolution = "relationshipEvidenceIncomplete";
  }, "incomplete_readiness");
});

test("authoritatively unaccounted items are excluded, with exclusion evidence bound in source hash", () => {
  const original = one("9223372036854775807");
  const source = original.items[0];
  const unaccounted = { ...source, name: "Private item", accounting: {
    ...accounted(source), evidence: { ...accounted(source).evidence, billableOccurrences: [] },
    resolution: "unaccountedFor" as const,
  } };
  const snapshot = build({ ...original, items: [unaccounted] });
  assert.equal(snapshot.groups.length, 0);
  assert.equal(snapshot.totals.itemCount, 0);
  assert.equal(snapshot.totals.totalMarketValueMinorUnits, "0");
  assert.notEqual(snapshot.sourceSetHash, build({ ...original, items: [] }).sourceSetHash);
  assert.ok(!encode(snapshot).includes("Private item"));
  assert.ok(!encode(snapshot).includes("billableOccurrences"));
});

test("excluded Item currency does not invalidate a report", () => {
  const input = one("100");
  const source = input.items[0];
  const item = { ...source, marketValueCurrency: "EUR", accounting: {
    ...accounted(source), evidence: { ...accounted(source).evidence, billableOccurrences: [] },
    resolution: "unaccountedFor" as const,
  } };
  const result = build({ ...input, items: [item] });
  assert.equal(result.totals.itemCount, 0);
  assert.equal(result.totals.totalMarketValueMinorUnits, "0");
});

test("rebuilds resolution and validates typed accounting relationships and exact physical scope", () => {
  rejects(x => x.items[0].accounting.resolution = "unaccountedFor", "invalid_accounting");
  rejects(x => x.items[0].accounting.evidence.billableOccurrences = [], "invalid_accounting");
  for (const field of ["accountId", "projectId", "itemId", "spaceId"]) {
    rejects(x => x.items[0].accounting.evidence[field] = "foreign", "scope_mismatch");
  }
  for (const field of ["accountId", "projectId", "itemId"]) {
    rejects(x => x.items[0].accounting.evidence.billableOccurrences[0][field] = "foreign", "scope_mismatch");
  }
  rejects(x => x.items[0].accounting.evidence.billableOccurrences[0].phase.kind = "onLiveInvoice", "invalid_accounting");
  rejects(x => x.items[0].accounting.evidence.billableOccurrences[0].phase.invoiceId = "invoice", "invalid_accounting");
  rejects(x => x.items[0].accounting.evidence.billableOccurrences[0].polarity = "fake", "invalid_accounting");
  rejects(x => x.items[0].accounting.evidence.billableOccurrences.push(
    x.items[0].accounting.evidence.billableOccurrences[0]), "duplicate_accounting_relationship");
});

test("client-paid purchases and all typed billable phases qualify; classification and client scope are checked", () => {
  const original = one("1"), item = original.items[0], base = accounted(item);
  const purchase = { id: "purchase", accountId: item.accountId, projectId: item.projectId, clientId: "client",
    itemId: item.itemId, transactionId: "transaction", classification: {
      type: "purchase" as const, role: "standalone" as const, scope: {
        ownerKind: "project" as const, accountId: item.accountId, projectId: item.projectId, clientId: "client",
      },
    } };
  const candidate = { ...original, items: [{ ...item, accounting: { ...base,
    evidence: { ...base.evidence, billableOccurrences: [], clientPaidPurchases: [purchase] } } }] };
  assert.equal(build(candidate).totals.itemCount, 1);
  for (const change of [
    (x: any) => x.classification.type = "return",
    (x: any) => x.classification.role = "transferSource",
    (x: any) => x.classification.scope.ownerKind = "businessInventory",
  ]) {
    const invalid = structuredClone(candidate); change(invalid.items[0].accounting.evidence.clientPaidPurchases[0]);
    assert.throws(() => build(invalid), { code: "property_report_invalid_accounting" });
  }
  for (const change of [
    (x: any) => x.clientId = "foreign",
    (x: any) => x.classification.scope.clientId = "foreign",
    (x: any) => x.classification.scope.accountId = "foreign",
    (x: any) => x.classification.scope.projectId = "foreign",
  ]) {
    const invalid = structuredClone(candidate); change(invalid.items[0].accounting.evidence.clientPaidPurchases[0]);
    assert.throws(() => build(invalid), { code: "property_report_scope_mismatch" });
  }
  for (const kind of ["onLiveInvoice", "frozenPaid"] as const) {
    const accounting = { ...base, evidence: { ...base.evidence, billableOccurrences: [{
      ...base.evidence.billableOccurrences[0], polarity: "credit" as const, phase: { kind, invoiceId: "invoice" },
    }] } };
    assert.equal(build({ ...original, items: [{ ...item, accounting }] }).totals.itemCount, 1);
  }
});

test("accounting hash uses validated Swift optional encoding and binds relationship changes", () => {
  const original = one("1"), baseline = build(original);
  const normalized: any = structuredClone(original);
  normalized.items[0].accounting.evidence.spaceId = null;
  normalized.items[0].accounting.evidence.billableOccurrences[0].phase.invoiceId = null;
  normalized.items[0].accounting.ignoredField = "Swift ignores unknown coding keys";
  assert.equal(encode(build(normalized)), encode(baseline));
  normalized.items[0].accounting.evidence.billableOccurrences[0].id = "changed-relationship";
  const changed = build(normalized);
  assert.deepEqual(changed.groups, baseline.groups);
  assert.notEqual(changed.sourceSetHash, baseline.sourceSetHash);
  // A positive qualifying relationship remains sufficient even when absence
  // elsewhere is not authoritative, matching the existing Swift resolution.
  normalized.items[0].accounting.relationshipAbsenceIsAuthoritative = false;
  assert.equal(build(normalized).totals.itemCount, 1);
});
