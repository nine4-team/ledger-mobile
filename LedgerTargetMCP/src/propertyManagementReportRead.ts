import { createHash } from "node:crypto";
import { TargetMCPFailure, validateIdentifier, type TargetMCPRequestContext } from "./contractSupport.js";
import { buildPropertyManagementReportSnapshot, type PropertyManagementReportInput,
  type PropertyManagementReportSnapshot } from "./propertyManagementReport.js";

/** Online-only adapter. The RPC must derive the principal from the verified JWT,
 * enforce current membership/RLS, and return all facts from one database snapshot.
 * The context is supplied by the authenticated host, never by model arguments. */
export class SupabasePropertyManagementReportReader {
  readonly #url: URL;
  readonly #key: string;
  readonly #fetch: typeof fetch;

  constructor(url: URL, publishableKey: string, fetchImplementation: typeof fetch = fetch) {
    validateReportConfiguration(url, publishableKey, "property_report_configuration_invalid");
    this.#url = new URL("/rest/v1/rpc/spike_read_property_management_report", url);
    this.#key = publishableKey;
    this.#fetch = fetchImplementation;
  }

  async read(input: Readonly<{ projectId: string; currency: string }>,
             context: TargetMCPRequestContext): Promise<PropertyManagementReportSnapshot> {
    validateIdentifier(context.accountId, "account_not_authorized");
    validateIdentifier(context.principalId, "account_not_authorized");
    validateIdentifier(input.projectId, "property_report_invalid_identifier");
    if (!/^[A-Z]{3}$/.test(input.currency)) throw new TargetMCPFailure("property_report_invalid_currency");
    if (!credential(context.accessToken, "authenticated")) throw new TargetMCPFailure("authentication_required");
    let response: Response;
    try {
      response = await this.#fetch(this.#url, {
        method: "POST", redirect: "error", signal: AbortSignal.timeout(30_000),
        headers: { apikey: this.#key, Authorization: `Bearer ${context.accessToken}`,
          Accept: "application/json", "Content-Type": "application/json" },
        body: JSON.stringify({ p_account_id: context.accountId, p_project_id: input.projectId,
          p_currency: input.currency }),
      });
    } catch {
      throw new TargetMCPFailure("property_report_transport_failed");
    }
    if (!response.ok) {
      // Never pass through PostgREST bodies, URLs, tokens, or fetch error text.
      throw new TargetMCPFailure(response.status === 401 ? "authentication_required"
        : response.status === 403 ? "account_not_authorized" : "property_report_read_failed", response.status);
    }
    try {
      const facts: unknown = await response.json();
      // The projection validates each consumed field, parents, duplicates, exact
      // amounts and provenance; malformed JS shapes are also caught below.
      const candidate = facts as PropertyManagementReportInput;
      // Bind the response before allowing an incomplete-data result through.
      // A foreign or malformed response must not masquerade as "not ready".
      if (candidate.project.accountId !== context.accountId || candidate.project.projectId !== input.projectId
          || candidate.provenance.principalId !== context.principalId || candidate.currency !== input.currency
          || candidate.provenance.authorityVersion !== "property-management-v1"
          || candidate.provenance.visibilityScopeID !== createHash("sha256").update(JSON.stringify([
            context.accountId, context.principalId, input.projectId, "physical-property-report-v1",
          ])).digest("hex")) {
        throw new Error("scope mismatch");
      }
      return buildPropertyManagementReportSnapshot(candidate);
    } catch (error) {
      if (error instanceof TargetMCPFailure && error.code === "property_report_incomplete_readiness") {
        throw new TargetMCPFailure("property_report_incomplete_readiness");
      }
      throw new TargetMCPFailure("property_report_server_result_mismatch");
    }
  }

  /** RLS exposes only the Principal mapped to this verified user token. Account
   * membership is checked again by each report RPC, not cached at startup. */
  async resolveContext(accountId: string, accessToken: string): Promise<TargetMCPRequestContext> {
    validateIdentifier(accountId, "account_not_authorized");
    if (!credential(accessToken, "authenticated")) throw new TargetMCPFailure("authentication_required");
    try {
      const url = new URL("/rest/v1/spike_principals?select=id&limit=2", this.#url);
      const response = await this.#fetch(url, { redirect: "error", signal: AbortSignal.timeout(30_000),
        headers: { apikey: this.#key, Authorization: `Bearer ${accessToken}`, Accept: "application/json" } });
      if (!response.ok) throw new Error("denied");
      const rows: unknown = await response.json();
      if (!Array.isArray(rows) || rows.length !== 1 || typeof rows[0]?.id !== "string") throw new Error("invalid identity");
      return { accountId, principalId: validateIdentifier(rows[0].id, "authentication_required"), accessToken };
    } catch { throw new TargetMCPFailure("authentication_required"); }
  }
}

/** Reject obvious privileged/malformed credentials before transmission. This is
 * not JWT verification: Supabase verifies signature, expiry and authorization. */
export function credential(value: string, role: "anon" | "authenticated"): boolean {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(value)) return false;
  try {
    const claims = JSON.parse(Buffer.from(value.split(".")[1], "base64url").toString("utf8"));
    return claims !== null && typeof claims === "object" && claims.role === role;
  } catch { return false; }
}

export function validateReportConfiguration(url: URL, publishableKey: string, code: string): void {
  if ((url.protocol !== "https:" && !(url.protocol === "http:"
      && ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname)))
      || url.username || url.password || url.search || url.hash || url.pathname !== "/"
      || (!credential(publishableKey, "anon") && !/^sb_publishable_[A-Za-z0-9_-]+$/.test(publishableKey))) {
    throw new TargetMCPFailure(code);
  }
}
