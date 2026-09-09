import { TargetMCPFailure } from "./contractSupport.js";
import { propertyReportSupport as v, type PropertyManagementReportProject,
  type PropertyManagementReportSpace, type AuthoritativePropertyManagementReportProvenance,
  type ProjectItemAccountingRow } from "./propertyManagementReport.js";

export type ClientSummaryPhysicalReportClient =
  | Readonly<{ kind: "known"; clientId: string; name: string; revision: string }>
  | Readonly<{ kind: "unavailable"; clientId: string }>;
// Swift's synthesized enum encoding, unlike the Client's explicit encoding.
export type ClientSummaryPhysicalReportCategory =
  | Readonly<{ known: Readonly<{ categoryId: string; name: string }> }>
  | Readonly<{ unavailable: Readonly<Record<string, never>> }>;
export type ClientSummaryPhysicalReportItem = Readonly<{
  accountId: string; projectId: string; itemId: string; placementId: string;
  spaceId: string | null; name: string; sku: string | null;
  category: ClientSummaryPhysicalReportCategory; itemRevision: string;
  accounting: ProjectItemAccountingRow | null;
}>;
export type ClientSummaryPhysicalReportInput = Readonly<{
  project: PropertyManagementReportProject; client: ClientSummaryPhysicalReportClient;
  spaces: readonly PropertyManagementReportSpace[]; items: readonly ClientSummaryPhysicalReportItem[];
  provenance: AuthoritativePropertyManagementReportProvenance;
}>;
export type ClientSummaryPhysicalReportSnapshot = ClientSummaryPhysicalReportInput & Readonly<{
  reportKind: "client_summary_physical"; sourceSetHash: string; accountingEvidenceHash: string;
  reference: Readonly<{ snapshotID: string; snapshotHash: string; visibilityScopeID: string;
    profileVersion: "client-summary-physical-v1"; authorityVersion: string }>;
}>;
function fail(code: string): never { throw new TargetMCPFailure(`client_summary_physical_${code}`); }
// Foundation whitespacesAndNewlines includes NEL and zero-width space; JS trim
// differs on both and on BOM. Preserve original spelling in the report payload.
const edgeWhitespace = /^[\p{White_Space}\u200b]+|[\p{White_Space}\u200b]+$/gu;
function name(value: unknown, category = false): string {
  const original = v.string(value), trimmed = original.replace(edgeWhitespace, "");
  if (!trimmed) fail("invalid_name");
  if (category && (/[\p{Cc}\p{Cf}]/u.test(trimmed)
    || [...new Intl.Segmenter("en", { granularity: "grapheme" }).segment(trimmed)].length > 100)) fail("invalid_name");
  return original;
}
function category(value: unknown): ClientSummaryPhysicalReportCategory {
  const raw = v.record(value);
  if (Object.keys(raw).length !== 1) fail("invalid_category");
  if (Object.hasOwn(raw, "known")) {
    const known = v.record(raw.known);
    return { known: { categoryId: v.id(known.categoryId), name: name(known.name, true) } };
  }
  if (Object.hasOwn(raw, "unavailable")) {
    v.record(raw.unavailable);
    return { unavailable: {} };
  }
  return fail("invalid_category");
}

/** Pure physical projection. The caller must authenticate and obtain a coherent
 * authorized read. Unknown evidence is retained for preview, never promoted. */
export function buildClientSummaryPhysicalReportSnapshot(input: ClientSummaryPhysicalReportInput): ClientSummaryPhysicalReportSnapshot {
  v.record(input); v.record(input.project); v.record(input.provenance);
  const project: PropertyManagementReportProject = { accountId: v.id(input.project.accountId),
    projectId: v.id(input.project.projectId), name: v.string(input.project.name),
    address: v.nullableText(input.project.address), revision: v.revision(input.project.revision) };
  const raw = input.provenance;
  v.scope(raw.accountId, raw.projectId, project);
  if (raw.readiness !== "ready") fail("incomplete_readiness");
  if (raw.source?.kind !== "authoritative" || Object.keys(raw.source).some(key => key !== "kind")
    || "lastSyncedAt" in raw || "localDataVersion" in raw) fail("invalid_source");
  if (typeof raw.visibilityScopeID !== "string" || !/^[a-f0-9]{64}$/.test(raw.visibilityScopeID)) fail("invalid_visibility_scope");
  if (typeof raw.authorityVersion !== "string" || !/^[a-z0-9_.-]{1,64}$/.test(raw.authorityVersion)) fail("invalid_authority_version");
  if (!Number.isSafeInteger(raw.asOf) || raw.asOf <= 0) fail("invalid_timestamp");
  const provenance: AuthoritativePropertyManagementReportProvenance = {
    accountId: project.accountId, projectId: project.projectId, principalId: v.id(raw.principalId),
    visibilityScopeID: raw.visibilityScopeID, source: { kind: "authoritative" },
    authorityVersion: raw.authorityVersion, asOf: raw.asOf, readiness: "ready" };
  const clientRaw = v.record(input.client), clientId = v.id(clientRaw.clientId);
  let client: ClientSummaryPhysicalReportClient;
  if (clientRaw.kind === "known") client = { kind: "known", clientId,
    name: name(clientRaw.name), revision: v.revision(clientRaw.revision) };
  else if (clientRaw.kind === "unavailable") client = { kind: "unavailable", clientId };
  else return fail("invalid_client");
  if (!Array.isArray(input.spaces) || !Array.isArray(input.items)) fail("invalid_rows");
  const spaceIDs = new Set<string>(), itemIDs = new Set<string>(), placementIDs = new Set<string>();
  const spaces = input.spaces.map(row => {
    v.record(row); v.scope(row.accountId, row.projectId, project);
    const spaceId = v.id(row.spaceId); v.unique(spaceIDs, spaceId, "duplicate_space");
    return { accountId: project.accountId, projectId: project.projectId, spaceId,
      name: v.string(row.name), revision: v.revision(row.revision) };
  }).sort((a, b) => v.ordered(a.name, a.spaceId, b.name, b.spaceId));
  const names = new Map<string, string>();
  const items: ClientSummaryPhysicalReportItem[] = input.items.map(row => {
    v.record(row); v.scope(row.accountId, row.projectId, project);
    const itemId = v.id(row.itemId), placementId = v.id(row.placementId);
    v.unique(itemIDs, itemId, "duplicate_item"); v.unique(placementIDs, placementId, "duplicate_placement");
    const spaceId = row.spaceId === null ? null : v.id(row.spaceId);
    if (spaceId !== null && !spaceIDs.has(spaceId)) fail("missing_space");
    const item = { accountId: project.accountId, projectId: project.projectId, itemId, placementId,
      spaceId, name: v.string(row.name), sku: v.nullableText(row.sku), itemRevision: v.revision(row.itemRevision) };
    const accounting = row.accounting == null ? null : v.accounting(row.accounting, item, true);
    if (accounting && accounting.evidence.clientId !== clientId) fail("scope_mismatch");
    const attribution = category(row.category);
    if ("known" in attribution) {
      const { categoryId, name } = attribution.known, previous = names.get(categoryId);
      if (previous !== undefined && previous !== name) fail("conflicting_category");
      names.set(categoryId, name);
    }
    return { ...item, category: attribution, accounting };
  }).sort((a, b) => v.ordered(a.name, a.itemId, b.name, b.itemId));
  // AccountingSource uses synthesized Optional encoding: nil is omitted here,
  // while ClientSummaryPhysicalReportItem explicitly encodes accounting:null.
  const accountingEvidenceHash = v.hash(v.canonical([...items]
    .sort((a, b) => v.ordered("", a.itemId, "", b.itemId))
    .map(item => ({ itemId: item.itemId, ...(item.accounting === null ? {} : { accounting: item.accounting }) }))));
  const reportItems = items.filter(item => item.accounting?.resolution !== "unaccountedFor");
  const source = { project, client, spaces, items: reportItems, accountingEvidenceHash };
  const sourceSetHash = v.hash(v.canonical(source));
  const content = { reportKind: "client_summary_physical" as const, source, provenance, sourceSetHash };
  const snapshotHash = v.hash(v.canonical(content));
  return { reportKind: "client_summary_physical", ...source, provenance, sourceSetHash,
    reference: { snapshotID: snapshotHash.slice(0, 32), snapshotHash,
      visibilityScopeID: provenance.visibilityScopeID, profileVersion: "client-summary-physical-v1",
      authorityVersion: provenance.authorityVersion } };
}
export function isClientSummaryPhysicalReportComplete(snapshot: ClientSummaryPhysicalReportSnapshot): boolean {
  return snapshot.client.kind === "known" && snapshot.items.every(item =>
    item.accounting?.resolution === "accountedFor" && "known" in item.category);
}
export function encodeClientSummaryPhysicalReportSnapshot(snapshot: ClientSummaryPhysicalReportSnapshot): string {
  return v.canonical(snapshot);
}
export function encodeClientSummaryPhysicalReportContent(snapshot: ClientSummaryPhysicalReportSnapshot): string {
  const { project, client, spaces, items, accountingEvidenceHash, provenance, sourceSetHash, reportKind } = snapshot;
  return v.canonical({ reportKind, source: { project, client, spaces, items, accountingEvidenceHash }, provenance, sourceSetHash });
}
