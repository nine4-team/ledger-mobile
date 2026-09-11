import { createHash } from "node:crypto";
import { TargetMCPFailure, validateIdentifier, type TargetMCPRequestContext } from "./contractSupport.js";
import { buildClientSummaryPhysicalReportSnapshot, type ClientSummaryPhysicalReportInput,
  type ClientSummaryPhysicalReportSnapshot } from "./clientSummaryPhysicalReport.js";
import { credential, validateReportConfiguration } from "./propertyManagementReportRead.js";

/** One authorized database snapshot. Incomplete physical evidence remains
 * explicit; this read grants no export permission or financial completeness. */
export class SupabaseClientSummaryPhysicalReportReader {
  readonly #url: URL;
  constructor(url: URL, private readonly key: string, private readonly fetcher: typeof fetch = fetch) {
    validateReportConfiguration(url, key, "client_summary_physical_configuration_invalid");
    this.#url = new URL("/rest/v1/rpc/spike_read_client_summary_physical_report", url);
  }
  async read(input: Readonly<{ projectId: string }>, context: TargetMCPRequestContext): Promise<ClientSummaryPhysicalReportSnapshot> {
    validateIdentifier(context.accountId, "account_not_authorized");
    validateIdentifier(context.principalId, "account_not_authorized");
    validateIdentifier(input.projectId, "client_summary_physical_invalid_identifier");
    if (!credential(context.accessToken, "authenticated")) throw new TargetMCPFailure("authentication_required");
    let response: Response;
    try {
      response = await this.fetcher(this.#url, { method: "POST", redirect: "error", signal: AbortSignal.timeout(30_000),
        headers: { apikey: this.key, Authorization: `Bearer ${context.accessToken}`, Accept: "application/json",
          "Content-Type": "application/json" },
        body: JSON.stringify({ p_account_id: context.accountId, p_project_id: input.projectId }) });
    } catch { throw new TargetMCPFailure("client_summary_physical_transport_failed"); }
    if (!response.ok) throw new TargetMCPFailure(response.status === 401 ? "authentication_required"
      : response.status === 403 ? "account_not_authorized" : "client_summary_physical_read_failed", response.status);
    try {
      const candidate = await response.json() as ClientSummaryPhysicalReportInput;
      if (candidate.project.accountId !== context.accountId || candidate.project.projectId !== input.projectId
        || candidate.provenance.principalId !== context.principalId
        || candidate.provenance.authorityVersion !== "client-summary-physical-v1"
        || candidate.provenance.visibilityScopeID !== createHash("sha256").update(JSON.stringify([
          context.accountId, context.principalId, input.projectId, "client-summary-physical-v1",
        ])).digest("hex")) throw new Error("scope mismatch");
      return buildClientSummaryPhysicalReportSnapshot(candidate);
    } catch { throw new TargetMCPFailure("client_summary_physical_server_result_mismatch"); }
  }
}
