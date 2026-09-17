import { z } from "zod";
import { TargetMCPFailure, validateIdentifier, type TargetMCPRequestContext } from "./contractSupport.js";
import { userCredential } from "./categoryManagement.js";

const id = z.string().refine(value => {
  try { validateIdentifier(value, "budget_invalid"); return true; } catch { return false; }
});
const money = z.string().refine(value => /^-?(0|[1-9][0-9]*)$/.test(value) && value !== "-0"
  && BigInt(value) >= -9223372036854775808n && BigInt(value) <= 9223372036854775807n);
export const projectBudgetInputSchema = z.object({ projectId: id, currency: z.string().regex(/^[A-Z]{3}$/) }).strict();
export type ProjectBudgetInput = z.infer<typeof projectBudgetInputSchema>;
const resultSchema = z.object({ accountId: id, principalId: id, projectId: id, clientId: id,
  currency: z.string().regex(/^[A-Z]{3}$/), isCompleteForProjectBudget: z.literal(false),
  missingCoverage: z.tuple([z.literal("transfers"), z.literal("additional_requests")]),
  categories: z.array(z.object({ id, name: z.string(), kind: z.enum(["general", "itemized", "fee"]),
    excludesFromOverallBudget: z.boolean(), enabled: z.boolean(), allocationMinorUnits: money.nullable(),
    paidMinorUnits: money, unpaidMinorUnits: money, recognizedMinorUnits: money }).strict()),
  overallPaidMinorUnits: money, overallUnpaidMinorUnits: money,
  overallRecognizedMinorUnits: money, overallBudgetMinorUnits: money,
}).strict();
export type ProjectBudgetRead = z.infer<typeof resultSchema>;
export interface ProjectBudgetReading {
  read(input: ProjectBudgetInput, context: TargetMCPRequestContext): Promise<ProjectBudgetRead>;
}
export function validateProjectBudget(value: unknown, input: ProjectBudgetInput, context: TargetMCPRequestContext): ProjectBudgetRead {
  try {
    const request = projectBudgetInputSchema.parse(input), result = resultSchema.parse(value);
    if (result.accountId !== context.accountId || result.principalId !== context.principalId
      || result.projectId !== request.projectId || result.currency !== request.currency
      || new Set(result.categories.map(row => row.id)).size !== result.categories.length) throw new Error();
    let paid = 0n, unpaid = 0n, budget = 0n;
    for (const row of result.categories) {
      if (BigInt(row.paidMinorUnits) + BigInt(row.unpaidMinorUnits) !== BigInt(row.recognizedMinorUnits)
        || (!row.enabled && row.allocationMinorUnits !== null)
        || (row.allocationMinorUnits !== null && BigInt(row.allocationMinorUnits) < 0n)) throw new Error();
      if (!row.excludesFromOverallBudget) {
        paid += BigInt(row.paidMinorUnits); unpaid += BigInt(row.unpaidMinorUnits);
        budget += BigInt(row.allocationMinorUnits ?? "0");
      }
    }
    if (paid !== BigInt(result.overallPaidMinorUnits) || unpaid !== BigInt(result.overallUnpaidMinorUnits)
      || paid + unpaid !== BigInt(result.overallRecognizedMinorUnits) || budget !== BigInt(result.overallBudgetMinorUnits)) throw new Error();
    return result;
  } catch { throw new TargetMCPFailure("budget_server_result_mismatch"); }
}
export class SupabaseProjectBudgetReader implements ProjectBudgetReading {
  readonly #url: URL;
  constructor(url: URL, readonly key: string, readonly fetchImplementation: typeof fetch = fetch) {
    if (!["http:", "https:"].includes(url.protocol) || !url.hostname || url.username || url.password || url.search || url.hash) {
      throw new TargetMCPFailure("budget_configuration_invalid");
    }
    userCredential(key);
    this.#url = new URL(`${url.href.replace(/\/$/, "")}/rest/v1/rpc/spike_read_project_budget`);
  }
  async read(input: ProjectBudgetInput, context: TargetMCPRequestContext): Promise<ProjectBudgetRead> {
    const request = projectBudgetInputSchema.safeParse(input);
    if (!request.success) throw new TargetMCPFailure("budget_invalid");
    userCredential(context.accessToken);
    validateIdentifier(context.accountId, "account_not_authorized");
    validateIdentifier(context.principalId, "account_not_authorized");
    const response = await this.fetchImplementation(this.#url, { method: "POST", redirect: "error",
      signal: AbortSignal.timeout(15_000), headers: { "Content-Type": "application/json", Accept: "application/json",
        apikey: this.key, Authorization: `Bearer ${context.accessToken}` },
      body: JSON.stringify({ p_account_id: context.accountId, p_project_id: request.data.projectId, p_currency: request.data.currency }) });
    if (!response.ok) throw new TargetMCPFailure("budget_request_rejected", response.status);
    let value: unknown;
    try { value = await response.json(); } catch { throw new TargetMCPFailure("budget_server_result_mismatch"); }
    return validateProjectBudget(value, request.data, context);
  }
}
