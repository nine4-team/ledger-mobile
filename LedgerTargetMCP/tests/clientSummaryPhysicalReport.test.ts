import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import test from "node:test";
import { buildClientSummaryPhysicalReportSnapshot as build,
  encodeClientSummaryPhysicalReportSnapshot as encode,
  encodeClientSummaryPhysicalReportContent as content,
  isClientSummaryPhysicalReportComplete as complete,
  type ClientSummaryPhysicalReportInput } from "../src/clientSummaryPhysicalReport.js";

function input(): ClientSummaryPhysicalReportInput {
  return { project: { accountId: "account", projectId: "project", name: "Home", address: null, revision: "1" },
    client: { kind: "known", clientId: "client", name: "Client", revision: "9007199254740993" },
    spaces: [{ accountId: "account", projectId: "project", spaceId: "space", name: "No Space", revision: "1" }],
    items: [2, 1].map(index => ({ accountId: "account", projectId: "project", itemId: `item-${index}`,
      placementId: `placement-${index}`, spaceId: index === 1 ? "space" : null,
      name: "Chair", sku: null, itemRevision: "1", category: { known: { categoryId: "category", name: "Furnishings" } },
      accounting: { evidence: { accountId: "account", projectId: "project", clientId: "client",
        itemId: `item-${index}`, spaceId: index === 1 ? "space" : null, clientPaidPurchases: [],
        billableOccurrences: [{ id: `charge-${index}`, accountId: "account", projectId: "project",
          itemId: `item-${index}`, polarity: "charge", phase: { kind: "availableToInvoice" } }] },
        relationshipAbsenceIsAuthoritative: true, resolution: "accountedFor" } })),
    provenance: { accountId: "account", projectId: "project", principalId: "principal",
      visibilityScopeID: createHash("sha256").update("scope").digest("hex"), source: { kind: "authoritative" },
      authorityVersion: "authority1", asOf: 1_800_000_000_000, readiness: "ready" } };
}
function changed(change: (value: any) => void): ClientSummaryPhysicalReportInput {
  const value = input(); change(value); return value;
}
test("complete and incomplete reports match actual Swift canonical bytes and every hash", () => {
  const lines = readFileSync(new URL("./fixtures/client-summary-physical-online.jsonl", import.meta.url), "utf8")
    .trimEnd().split("\n");
  assert.equal(lines.length, 2);
  for (const [index, line] of lines.entries()) {
    const native = JSON.parse(line);
    const { project, client, spaces, items, provenance } = native;
    const rebuilt = build({ project, client, spaces, items: [...items].reverse(), provenance });
    assert.equal(encode(rebuilt), line);
    assert.equal(complete(rebuilt), index === 0);
  }
});
test("physical serialization follows Swift enum/null/revision encoding and stable identity", () => {
  const original = input(), snapshot = build(original);
  assert.ok(complete(snapshot));
  assert.deepEqual(snapshot.items.map(item => item.itemId), ["item-1", "item-2"]);
  assert.equal(encode(snapshot), encode(build({ ...original, items: [...original.items].reverse() })));
  assert.deepEqual(original, input());
  assert.equal(snapshot.reference.snapshotHash, createHash("sha256").update(content(snapshot)).digest("hex"));
  assert.equal(snapshot.reference.snapshotID, snapshot.reference.snapshotHash.slice(0, 32));
  assert.equal(snapshot.reference.profileVersion, "client-summary-physical-v1");
  const bytes = encode(snapshot);
  assert.ok(bytes.includes('"category":{"known":{"categoryId":"category","name":"Furnishings"}}'));
  assert.ok(bytes.includes('"revision":"9007199254740993"'));
  assert.ok(bytes.includes('"spaceId":null') && bytes.includes('"sku":null'));
  assert.ok(!Object.hasOwn(snapshot, "isComplete"));
  for (const forbidden of ["marketValue", "budget", "receipt", "totalSpent", "minorUnits"]) assert.ok(!bytes.includes(forbidden));
});
test("Client/category rename and exact Client revision affect physical source identity", () => {
  const base = build(input());
  for (const change of [
    (x: any) => { x.client.name = "Renamed Client"; },
    (x: any) => { x.client.revision = "9007199254740994"; },
    (x: any) => { for (const item of x.items) item.category.known.name = "Renamed category"; },
  ]) assert.notEqual(build(changed(change)).sourceSetHash, base.sourceSetHash);
});
test("incomplete Client, category, absent and explicitly unknown accounting stay preview-only", () => {
  for (const change of [
    (x: any) => { x.client = { kind: "unavailable", clientId: "client" }; },
    (x: any) => { x.items[0].category = { unavailable: {} }; },
    (x: any) => { x.items[0].accounting = null; },
    (x: any) => { x.items[0].accounting.evidence.billableOccurrences = [];
      x.items[0].accounting.relationshipAbsenceIsAuthoritative = false;
      x.items[0].accounting.resolution = "relationshipEvidenceIncomplete"; },
  ]) { const snapshot = build(changed(change)); assert.equal(snapshot.items.length, 2); assert.equal(complete(snapshot), false); }
  const snapshot = build(changed(x => { x.items[0].accounting = null; }));
  assert.ok(encode(snapshot).includes('"accounting":null'));
});
test("proven Unaccounted Items are excluded while exclusion evidence remains identity-bound", () => {
  const candidate = changed(x => { x.items[0].accounting.evidence.billableOccurrences = [];
    x.items[0].accounting.resolution = "unaccountedFor"; });
  const snapshot = build(candidate);
  assert.ok(complete(snapshot));
  assert.deepEqual(snapshot.items.map(item => item.itemId), ["item-1"]);
  assert.ok(!encode(snapshot).includes("item-2"));
  const withoutExcluded = build({ ...candidate, items: candidate.items.slice(1) });
  assert.deepEqual(snapshot.items, withoutExcluded.items);
  assert.notEqual(snapshot.accountingEvidenceHash, withoutExcluded.accountingEvidenceHash);
  assert.notEqual(snapshot.sourceSetHash, withoutExcluded.sourceSetHash);
  assert.ok(complete(build({ ...candidate, items: [] })));
});
test("rejects wrong scope, duplicate identities, missing parents and forged classification/resolution", () => {
  for (const change of [
    (x: any) => { x.project.accountId = "foreign"; },
    (x: any) => { x.items[0].accounting.evidence.clientId = "foreign"; },
    (x: any) => { x.items[0].accounting.evidence.billableOccurrences[0].projectId = "foreign"; },
    (x: any) => { x.items[0].accounting.evidence.spaceId = "space"; },
    (x: any) => { x.items[0].accounting.resolution = "unaccountedFor"; },
    (x: any) => { x.items[0].accounting.evidence.billableOccurrences[0].phase.kind = "frozenPaid"; },
    (x: any) => { x.items.push(x.items[0]); },
    (x: any) => { x.items[0].placementId = x.items[1].placementId; },
    (x: any) => { x.spaces = []; },
    (x: any) => { x.items[0].category.known.name = "Other category name"; },
  ]) assert.throws(() => build(changed(change)));
});
test("rejects invalid exact revisions, names, source, times and malformed shapes", () => {
  for (const change of [
    (x: any) => { x.client.revision = "18446744073709551616"; },
    (x: any) => { x.items[0].itemRevision = "01"; },
    (x: any) => { x.client.name = "\u0085\u200b "; },
    (x: any) => { x.items[0].category.known.name = "a\nb"; },
    (x: any) => { x.items[0].category.known.name = "a".repeat(101); },
    (x: any) => { x.items[0].name = "\ud800"; },
    (x: any) => { x.provenance.source = { kind: "downloaded" }; },
    (x: any) => { x.provenance.readiness = "partial"; },
    (x: any) => { x.provenance.asOf = Number.MAX_SAFE_INTEGER + 1; },
    (x: any) => { x.provenance.localDataVersion = "invented"; },
    (x: any) => { x.client = null; },
    (x: any) => { x.items[0].category = { known: {}, unavailable: {} }; },
  ]) assert.throws(() => build(changed(change)));
});
