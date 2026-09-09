import { createHash } from "node:crypto";
import { TargetMCPFailure, validateIdentifier } from "./contractSupport.js";

export type PropertyManagementReportProject = Readonly<{
  accountId: string; projectId: string; name: string; address: string | null; revision: string;
}>;
export type PropertyManagementReportSpace = Readonly<{
  accountId: string; projectId: string; spaceId: string; name: string; revision: string;
}>;
export type PropertyManagementReportItem = Readonly<{
  accountId: string; projectId: string; itemId: string; placementId: string;
  spaceId: string | null; name: string; sku: string | null; itemRevision: string;
  marketValueMinorUnits: string | null; marketValueCurrency: string | null;
}>;
export type ProjectItemAccountingRow = Readonly<{
  evidence: Readonly<{
    accountId: string; projectId: string; clientId: string; itemId: string; spaceId?: string | null;
    clientPaidPurchases: readonly Readonly<{
      id: string; accountId: string; projectId: string; clientId: string; itemId: string; transactionId: string;
      classification: Readonly<{ type: "purchase"; role: "standalone";
        scope: Readonly<{ ownerKind: "project"; accountId: string; projectId: string; clientId: string }> }>;
    }>[];
    billableOccurrences: readonly Readonly<{
      id: string; accountId: string; projectId: string; itemId: string; polarity: "charge" | "credit";
      phase: Readonly<{ kind: "availableToInvoice" | "onLiveInvoice" | "frozenPaid"; invoiceId?: string | null }>;
    }>[];
  }>;
  relationshipAbsenceIsAuthoritative: boolean;
  resolution: "accountedFor" | "unaccountedFor" | "relationshipEvidenceIncomplete";
}>;
export type PropertyManagementReportItemInput = PropertyManagementReportItem & Readonly<{
  accounting?: ProjectItemAccountingRow | null;
}>;
export type AuthoritativePropertyManagementReportProvenance = Readonly<{
  accountId: string; projectId: string; principalId: string; visibilityScopeID: string;
  source: Readonly<{ kind: "authoritative" }>;
  authorityVersion: string; asOf: number; readiness: "ready";
}>;
export type PropertyManagementReportInput = Readonly<{
  project: PropertyManagementReportProject;
  spaces: readonly PropertyManagementReportSpace[];
  items: readonly PropertyManagementReportItemInput[];
  currency: string;
  provenance: AuthoritativePropertyManagementReportProvenance;
}>;
export type PropertyManagementReportTotals = Readonly<{
  itemCount: number; knownMarketValueSubtotalMinorUnits: string; currency: string;
  unknownMarketValueCount: number; totalMarketValueMinorUnits: string | null;
}>;
export type PropertyManagementReportGroup = Readonly<{
  // Swift's synthesized Optional encoding omits this key for No Space.
  spaceId?: string; name: string; rows: readonly PropertyManagementReportItem[];
  totals: PropertyManagementReportTotals;
}>;
export type PropertyManagementReportContent = Readonly<{
  reportKind: "property_management"; project: PropertyManagementReportProject;
  provenance: AuthoritativePropertyManagementReportProvenance; currency: string;
  spaces: readonly PropertyManagementReportSpace[]; groups: readonly PropertyManagementReportGroup[];
  totals: PropertyManagementReportTotals; sourceSetHash: string;
}>;
export type PropertyManagementReportSnapshot = PropertyManagementReportContent & Readonly<{
  reference: Readonly<{
    snapshotID: string; snapshotHash: string; visibilityScopeID: string;
    profileVersion: "property-management-v1"; authorityVersion: string;
  }>;
}>;

const MIN = -(1n << 63n), MAX = (1n << 63n) - 1n, UINT_MAX = (1n << 64n) - 1n;
function fail(code: string): never { throw new TargetMCPFailure(`property_report_${code}`); }
function string(value: unknown): string {
  if (typeof value !== "string") fail("invalid_text");
  // Foundation strings cannot contain unpaired UTF-16 surrogates.
  for (let i = 0; i < value.length; i++) {
    const code = value.charCodeAt(i);
    if (code >= 0xd800 && code <= 0xdbff) {
      const low = value.charCodeAt(++i);
      if (!(low >= 0xdc00 && low <= 0xdfff)) fail("invalid_text");
    } else if (code >= 0xdc00 && code <= 0xdfff) fail("invalid_text");
  }
  return value;
}
function nullableText(value: unknown): string | null { return value === null ? null : string(value); }
function id(value: unknown): string { return validateIdentifier(string(value), "property_report_invalid_identifier"); }
function revision(value: unknown): string {
  if (typeof value !== "string" || !/^[1-9][0-9]*$/.test(value) || value.length > 20 || BigInt(value) > UINT_MAX) fail("invalid_revision");
  return value;
}
function amount(value: unknown): string {
  if (typeof value !== "string" || !/^(0|-[1-9][0-9]*|[1-9][0-9]*)$/.test(value) || value.length > 20) fail("invalid_amount");
  const number = BigInt(value);
  if (number < MIN || number > MAX) fail("invalid_amount");
  return value;
}
function currency(value: unknown): string {
  if (typeof value !== "string" || !/^[A-Z]{3}$/.test(value)) fail("invalid_currency");
  return value;
}
function scope(accountId: unknown, projectId: unknown, project: PropertyManagementReportProject): void {
  if (id(accountId) !== project.accountId || id(projectId) !== project.projectId) fail("scope_mismatch");
}
function unique(set: Set<string>, value: string, code: string): void {
  if (set.has(value)) fail(code);
  set.add(value);
}
function ordered(nameA: string, idA: string, nameB: string, idB: string): number {
  return Buffer.compare(Buffer.from(nameA), Buffer.from(nameB)) || Buffer.compare(Buffer.from(idA), Buffer.from(idB));
}
function record(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) fail("invalid_accounting");
  return value as Record<string, unknown>;
}
/** Decode the same constrained relationships as Swift, rebuilding derived state
 * and optional fields before hashing; a caller-supplied resolution is not proof. */
function accounting(value: unknown, item: PropertyManagementReportItem): ProjectItemAccountingRow {
  if (value === undefined || value === null) fail("incomplete_readiness");
  const row = record(value), evidence = record(row.evidence);
  const accountId = id(evidence.accountId), projectId = id(evidence.projectId);
  const clientId = id(evidence.clientId), itemId = id(evidence.itemId);
  const spaceId = evidence.spaceId == null ? null : id(evidence.spaceId);
  if (!Array.isArray(evidence.clientPaidPurchases) || !Array.isArray(evidence.billableOccurrences)
      || typeof row.relationshipAbsenceIsAuthoritative !== "boolean") fail("invalid_accounting");
  function relationshipScope(connection: Record<string, unknown>): void {
    if (id(connection.accountId) !== accountId || id(connection.projectId) !== projectId
        || id(connection.itemId) !== itemId) fail("scope_mismatch");
  }
  const purchaseIDs = new Set<string>(), occurrenceIDs = new Set<string>();
  const clientPaidPurchases = evidence.clientPaidPurchases.map(raw => {
    const connection = record(raw), classification = record(connection.classification);
    const purchaseScope = record(classification.scope);
    relationshipScope(connection);
    if (id(connection.clientId) !== clientId || id(purchaseScope.accountId) !== accountId
        || id(purchaseScope.projectId) !== projectId || id(purchaseScope.clientId) !== clientId) fail("scope_mismatch");
    if (classification.type !== "purchase" || classification.role !== "standalone"
        || purchaseScope.ownerKind !== "project") fail("invalid_accounting");
    const connectionId = id(connection.id);
    unique(purchaseIDs, connectionId, "duplicate_accounting_relationship");
    return { id: connectionId, accountId, projectId, clientId, itemId, transactionId: id(connection.transactionId),
      classification: { type: "purchase" as const, role: "standalone" as const,
        scope: { ownerKind: "project" as const, accountId, projectId, clientId } } };
  });
  const billableOccurrences = evidence.billableOccurrences.map((raw): ProjectItemAccountingRow["evidence"]["billableOccurrences"][number] => {
    const occurrence = record(raw), phase = record(occurrence.phase);
    relationshipScope(occurrence);
    const occurrenceId = id(occurrence.id);
    unique(occurrenceIDs, occurrenceId, "duplicate_accounting_relationship");
    const polarity = occurrence.polarity;
    if (polarity !== "charge" && polarity !== "credit") fail("invalid_accounting");
    const kind = phase.kind, invoiceId = phase.invoiceId == null ? null : id(phase.invoiceId);
    if (kind !== "availableToInvoice" && kind !== "onLiveInvoice" && kind !== "frozenPaid") fail("invalid_accounting");
    if ((kind === "availableToInvoice") !== (invoiceId === null)) fail("invalid_accounting");
    return { id: occurrenceId, accountId, projectId, itemId, polarity,
      phase: { kind, ...(invoiceId === null ? {} : { invoiceId }) } };
  });
  const resolution = clientPaidPurchases.length || billableOccurrences.length ? "accountedFor"
    : row.relationshipAbsenceIsAuthoritative ? "unaccountedFor" : "relationshipEvidenceIncomplete";
  if (row.resolution !== resolution) fail("invalid_accounting");
  if (resolution === "relationshipEvidenceIncomplete") fail("incomplete_readiness");
  if (accountId !== item.accountId || projectId !== item.projectId || itemId !== item.itemId
      || spaceId !== item.spaceId) fail("scope_mismatch");
  return { evidence: { accountId, projectId, clientId, itemId, ...(spaceId === null ? {} : { spaceId }),
    clientPaidPurchases, billableOccurrences }, relationshipAbsenceIsAuthoritative: row.relationshipAbsenceIsAuthoritative, resolution };
}
function summarize(rows: readonly PropertyManagementReportItem[], currency: string): PropertyManagementReportTotals {
  let total = 0n, unknown = 0;
  for (const row of rows) {
    if (row.marketValueMinorUnits === null) unknown++;
    else {
      total += BigInt(row.marketValueMinorUnits);
      // Match Swift checked addition at each step, not just the final sum.
      if (total < MIN || total > MAX) fail("arithmetic_overflow");
    }
  }
  return { itemCount: rows.length, knownMarketValueSubtotalMinorUnits: total.toString(), currency,
    unknownMarketValueCount: unknown, totalMarketValueMinorUnits: unknown === 0 ? total.toString() : null };
}

/** Pure domain projection. Calling this does not authenticate facts or grant
 * access. The online provider must establish membership and a coherent read. */
export function buildPropertyManagementReportSnapshot(input: PropertyManagementReportInput): PropertyManagementReportSnapshot {
  const project: PropertyManagementReportProject = {
    accountId: id(input.project.accountId), projectId: id(input.project.projectId),
    name: string(input.project.name), address: nullableText(input.project.address), revision: revision(input.project.revision),
  };
  const code = currency(input.currency), source = input.provenance;
  scope(source.accountId, source.projectId, project);
  if (source.readiness !== "ready") fail("incomplete_readiness");
  if (source.source?.kind !== "authoritative" || Object.keys(source.source).some(key => key !== "kind")
      || "lastSyncedAt" in source || "localDataVersion" in source) fail("invalid_source");
  if (typeof source.visibilityScopeID !== "string" || !/^[a-f0-9]{64}$/.test(source.visibilityScopeID)) fail("invalid_visibility_scope");
  if (typeof source.authorityVersion !== "string" || !/^[a-z0-9_.-]{1,64}$/.test(source.authorityVersion)) fail("invalid_authority_version");
  if (!Number.isSafeInteger(source.asOf) || source.asOf <= 0) fail("invalid_timestamp");
  const provenance: AuthoritativePropertyManagementReportProvenance = {
    accountId: project.accountId, projectId: project.projectId, principalId: id(source.principalId),
    visibilityScopeID: source.visibilityScopeID, source: { kind: "authoritative" },
    authorityVersion: source.authorityVersion, asOf: source.asOf, readiness: "ready",
  };
  if (!Array.isArray(input.spaces) || !Array.isArray(input.items)) fail("invalid_rows");
  const spaceIDs = new Set<string>(), itemIDs = new Set<string>(), placementIDs = new Set<string>();
  const spaces: PropertyManagementReportSpace[] = input.spaces.map(row => {
    scope(row.accountId, row.projectId, project);
    const spaceId = id(row.spaceId);
    unique(spaceIDs, spaceId, "duplicate_space");
    return { accountId: project.accountId, projectId: project.projectId, spaceId,
      name: string(row.name), revision: revision(row.revision) };
  }).sort((a, b) => ordered(a.name, a.spaceId, b.name, b.spaceId));
  const accountingRows = new Map<string, ProjectItemAccountingRow>();
  const items: PropertyManagementReportItem[] = input.items.map(row => {
    scope(row.accountId, row.projectId, project);
    const itemId = id(row.itemId), placementId = id(row.placementId);
    unique(itemIDs, itemId, "duplicate_item"); unique(placementIDs, placementId, "duplicate_placement");
    const spaceId = row.spaceId === null ? null : id(row.spaceId);
    if (spaceId !== null && !spaceIDs.has(spaceId)) fail("missing_space");
    const value = row.marketValueMinorUnits === null ? null : amount(row.marketValueMinorUnits);
    const valueCurrency = row.marketValueCurrency === null ? null : currency(row.marketValueCurrency);
    if ((value === null) !== (valueCurrency === null)) fail("invalid_amount");
    const item = { accountId: project.accountId, projectId: project.projectId, itemId, placementId, spaceId,
      name: string(row.name), sku: nullableText(row.sku), itemRevision: revision(row.itemRevision),
      marketValueMinorUnits: value, marketValueCurrency: valueCurrency };
    const eligibility = accounting(row.accounting, item);
    if (eligibility.resolution === "accountedFor" && valueCurrency !== null && valueCurrency !== code) fail("mixed_currency");
    accountingRows.set(itemId, eligibility);
    return item;
  }).filter(item => accountingRows.get(item.itemId)!.resolution === "accountedFor")
    .sort((a, b) => ordered(a.name, a.itemId, b.name, b.itemId));
  const groups: PropertyManagementReportGroup[] = [];
  for (const space of spaces) {
    const rows = items.filter(item => item.spaceId === space.spaceId);
    if (rows.length) groups.push({ spaceId: space.spaceId, name: space.name, rows, totals: summarize(rows, code) });
  }
  const unplaced = items.filter(item => item.spaceId === null);
  if (unplaced.length) groups.push({ name: "No Space", rows: unplaced, totals: summarize(unplaced, code) });
  const content: PropertyManagementReportContent = {
    reportKind: "property_management", project, provenance, currency: code, spaces, groups,
    totals: summarize(items, code), sourceSetHash: hash(canonical({ project, spaces, items,
      accountingEvidenceHash: hash(canonical([...accountingRows.entries()]
        .sort(([a], [b]) => ordered("", a, "", b)).map(([, row]) => row))) })),
  };
  const snapshotHash = hash(canonical(content));
  return { ...content, reference: { snapshotID: snapshotHash.slice(0, 32), snapshotHash,
    visibilityScopeID: provenance.visibilityScopeID, profileVersion: "property-management-v1",
    authorityVersion: provenance.authorityVersion } };
}

export function encodePropertyManagementReportSnapshot(snapshot: PropertyManagementReportSnapshot): string {
  return canonical(snapshot);
}
export function encodePropertyManagementReportContent(snapshot: PropertyManagementReportSnapshot): string {
  const { reference: _, ...content } = snapshot;
  return canonical(content);
}
function hash(bytes: string): string { return createHash("sha256").update(bytes, "utf8").digest("hex"); }
// All schema keys are ASCII. Match JSONEncoder.sortedKeys + withoutEscapingSlashes;
// existing contractSupport.canonicalJSON deliberately uses different slash rules.
function canonical(value: unknown): string {
  if (value === null || typeof value === "string" || typeof value === "boolean") return JSON.stringify(value);
  if (typeof value === "number" && Number.isSafeInteger(value)) return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (typeof value === "object" && value !== null) {
    const record = value as Record<string, unknown>;
    return `{${Object.keys(record).sort().map(key => `${JSON.stringify(key)}:${canonical(record[key])}`).join(",")}}`;
  }
  fail("encoding_invalid");
}
