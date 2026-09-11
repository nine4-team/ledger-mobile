import { createHash } from "node:crypto";
import {
  canonicalJSON,
  TargetMCPFailure,
  validateIdentifier,
  validateTerminalResult,
  type TargetMCPRequestContext,
} from "./contractSupport.js";

const CONTRACT_VERSION = "project-create-v1";
const CURRENCY = /^[A-Z]{3}$/;

export type ProjectClientSelectionInput =
  | Readonly<{ kind: "existing"; clientId: string }>
  | Readonly<{ kind: "new"; clientId: string; displayName: string }>;

export type ProjectCategoryAllocationInput = Readonly<{
  categoryId: string;
  allocation?: Readonly<{ minorUnits: number; currency: string }>;
}>;

export type CreateProjectToolInput = Readonly<{
  operationId: string;
  projectId: string;
  clientSelection: ProjectClientSelectionInput;
  displayName: string;
  description?: string | null;
  categoryAllocations: readonly ProjectCategoryAllocationInput[];
  projectCreatedAtMilliseconds: number;
}>;

export type ProjectCreationRPCRequest = Readonly<{
  operationId: string;
  accountId: string;
  actorPrincipalId: string;
  contractVersion: typeof CONTRACT_VERSION;
  projectCreatedAtMilliseconds: number;
  projectId: string;
  clientSelectionKind: "existing" | "new";
  clientId: string;
  newClientDisplayName: string | null;
  projectDisplayName: string;
  description: string | null;
  categoryAllocations: readonly ProjectCategoryAllocationInput[];
  fingerprint: string;
  envelopeJSON: string;
}>;

export type ProjectCreationRPCResult = Readonly<{
  operationId: string;
  accountId: string;
  commandFingerprint: string;
  subjectId: string;
  phase: "applied" | "rejected";
  resultCode: string | null;
  errorCode: string | null;
}>;

export interface ProjectCreationApplying {
  apply(
    request: ProjectCreationRPCRequest,
    context: TargetMCPRequestContext,
  ): Promise<ProjectCreationRPCResult>;
}

function canonicalDescription(value: string | null | undefined): string | null {
  if (value === null || value === undefined) return null;
  const canonical = value.trim();
  return canonical.length === 0 ? null : canonical;
}

function canonicalAllocations(
  allocations: readonly ProjectCategoryAllocationInput[],
): readonly ProjectCategoryAllocationInput[] {
  const seen = new Set<string>();
  const result = allocations.map((allocation) => {
    const categoryId = validateIdentifier(
      allocation.categoryId,
      "project_setup_category_identity_invalid",
    );
    if (seen.has(categoryId)) {
      throw new TargetMCPFailure("project_setup_category_identity_duplicate");
    }
    seen.add(categoryId);
    if (allocation.allocation === undefined) return { categoryId };
    if (
      !Number.isSafeInteger(allocation.allocation.minorUnits)
      || allocation.allocation.minorUnits < 0
    ) {
      throw new TargetMCPFailure("project_setup_category_allocation_negative");
    }
    if (!CURRENCY.test(allocation.allocation.currency)) {
      throw new TargetMCPFailure("project_setup_category_currency_invalid");
    }
    return {
      categoryId,
      allocation: {
        minorUnits: allocation.allocation.minorUnits,
        currency: allocation.allocation.currency,
      },
    };
  });
  return result.sort((left, right) => (
    left.categoryId < right.categoryId ? -1 : left.categoryId > right.categoryId ? 1 : 0
  ));
}

export function makeProjectCreationRPCRequest(
  input: CreateProjectToolInput,
  context: TargetMCPRequestContext,
): ProjectCreationRPCRequest {
  const operationId = validateIdentifier(
    input.operationId,
    "project_setup_operation_id_invalid",
  );
  const accountId = validateIdentifier(context.accountId, "account_not_authorized");
  const actorPrincipalId = validateIdentifier(context.principalId, "account_not_authorized");
  const projectId = validateIdentifier(input.projectId, "project_setup_project_id_invalid");
  const clientId = validateIdentifier(
    input.clientSelection.clientId,
    "project_setup_client_id_invalid",
  );
  if (input.displayName.trim().length === 0) {
    throw new TargetMCPFailure("client_directory_project_name_invalid");
  }
  if (!Number.isSafeInteger(input.projectCreatedAtMilliseconds)) {
    throw new TargetMCPFailure("project_setup_created_at_invalid");
  }
  const projectCreatedAt = new Date(input.projectCreatedAtMilliseconds);
  if (Number.isNaN(projectCreatedAt.valueOf())) {
    throw new TargetMCPFailure("project_setup_created_at_invalid");
  }
  let clientSelection: Record<string, string>;
  let newClientDisplayName: string | null;
  if (input.clientSelection.kind === "existing") {
    clientSelection = { clientId, kind: "existing" };
    newClientDisplayName = null;
  } else if (input.clientSelection.kind === "new") {
    if (input.clientSelection.displayName.trim().length === 0) {
      throw new TargetMCPFailure("client_directory_client_name_invalid");
    }
    clientSelection = {
      clientId,
      displayName: input.clientSelection.displayName,
      kind: "new",
    };
    newClientDisplayName = input.clientSelection.displayName;
  } else {
    throw new TargetMCPFailure("project_setup_client_selection_invalid");
  }

  const description = canonicalDescription(input.description);
  const categoryAllocations = canonicalAllocations(input.categoryAllocations);
  const payload: Record<string, unknown> = {
    categoryAllocations,
    clientSelection,
    displayName: input.displayName,
    projectId,
  };
  if (description !== null) payload.description = description;
  const envelope = {
    accountId,
    actorPrincipalId,
    clientCreatedAt: input.projectCreatedAtMilliseconds,
    contractVersion: CONTRACT_VERSION,
    operationId,
    payload,
    preconditions: [],
  };
  const envelopeJSON = canonicalJSON(
    envelope,
    "project_setup_command_encoding_invalid",
  );
  const fingerprint = createHash("sha256").update(envelopeJSON).digest("hex");

  return {
    operationId,
    accountId,
    actorPrincipalId,
    contractVersion: CONTRACT_VERSION,
    projectCreatedAtMilliseconds: input.projectCreatedAtMilliseconds,
    projectId,
    clientSelectionKind: input.clientSelection.kind,
    clientId,
    newClientDisplayName,
    projectDisplayName: input.displayName,
    description,
    categoryAllocations,
    fingerprint,
    envelopeJSON,
  };
}

export async function createProjectTool(
  input: CreateProjectToolInput,
  context: TargetMCPRequestContext,
  applier: ProjectCreationApplying,
): Promise<ProjectCreationRPCResult> {
  if (context.accessToken.length === 0) {
    throw new TargetMCPFailure("authentication_required");
  }
  const request = makeProjectCreationRPCRequest(input, context);
  const result = await applier.apply(request, context);
  if (
    result.operationId !== request.operationId
    || result.accountId !== request.accountId
    || result.commandFingerprint !== request.fingerprint
    || result.subjectId !== request.projectId
  ) {
    throw new TargetMCPFailure("project_setup_server_result_mismatch");
  }
  validateTerminalResult(
    result.phase,
    result.resultCode,
    result.errorCode,
    "project_setup_server_result_mismatch",
  );
  return result;
}

export class SupabaseProjectCreationApplier implements ProjectCreationApplying {
  readonly #rpcURL: URL;
  readonly #publishableKey: string;
  readonly #fetch: typeof fetch;

  constructor(
    supabaseURL: URL,
    publishableKey: string,
    fetchImplementation: typeof fetch = fetch,
  ) {
    if (!("http:" === supabaseURL.protocol || "https:" === supabaseURL.protocol)
      || publishableKey.length === 0) {
      throw new TargetMCPFailure("project_setup_configuration_invalid");
    }
    this.#rpcURL = new URL("/rest/v1/rpc/spike_create_project", supabaseURL);
    this.#publishableKey = publishableKey;
    this.#fetch = fetchImplementation;
  }

  async apply(
    request: ProjectCreationRPCRequest,
    context: TargetMCPRequestContext,
  ): Promise<ProjectCreationRPCResult> {
    if (context.accessToken.length === 0) {
      throw new TargetMCPFailure("authentication_required");
    }
    const createdAt = new Date(request.projectCreatedAtMilliseconds);
    if (Number.isNaN(createdAt.valueOf())) {
      throw new TargetMCPFailure("project_setup_created_at_invalid");
    }
    const response = await this.#fetch(this.#rpcURL, {
      method: "POST",
      headers: {
        Accept: "application/vnd.pgrst.object+json",
        apikey: this.#publishableKey,
        Authorization: `Bearer ${context.accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        p_operation_id: request.operationId,
        p_account_id: request.accountId,
        p_actor_principal_id: request.actorPrincipalId,
        p_contract_version: request.contractVersion,
        p_project_created_at: createdAt.toISOString(),
        p_project_id: request.projectId,
        p_client_selection_kind: request.clientSelectionKind,
        p_client_id: request.clientId,
        p_new_client_display_name: request.newClientDisplayName,
        p_project_display_name: request.projectDisplayName,
        p_description: request.description,
        p_category_allocations: request.categoryAllocations,
        p_fingerprint: request.fingerprint,
        p_envelope_json: request.envelopeJSON,
      }),
    });
    if (!response.ok) {
      throw new TargetMCPFailure("project_setup_request_rejected", response.status);
    }
    const body = await response.json() as Record<string, unknown>;
    validateTerminalResult(
      body.phase,
      body.result_code,
      body.error_code,
      "project_setup_server_result_mismatch",
    );
    return {
      operationId: String(body.operation_id),
      accountId: String(body.account_id),
      commandFingerprint: String(body.command_fingerprint),
      subjectId: String(body.subject_id),
      phase: body.phase,
      resultCode: body.result_code as string | null,
      errorCode: body.error_code as string | null,
    };
  }
}

const clientSelectionSchema = Object.freeze({
  oneOf: [
    {
      type: "object",
      additionalProperties: false,
      required: ["kind", "clientId"],
      properties: {
        kind: { const: "existing" },
        clientId: { type: "string", minLength: 1, maxLength: 128 },
      },
    },
    {
      type: "object",
      additionalProperties: false,
      required: ["kind", "clientId", "displayName"],
      properties: {
        kind: { const: "new" },
        clientId: { type: "string", minLength: 1, maxLength: 128 },
        displayName: { type: "string", minLength: 1 },
      },
    },
  ],
});

export const createProjectToolDefinition = Object.freeze({
  name: "create_project",
  description: "Create one Project, optionally creating its Client, in the current Ledger account.",
  inputSchema: Object.freeze({
    type: "object",
    additionalProperties: false,
    required: [
      "operationId",
      "projectId",
      "clientSelection",
      "displayName",
      "categoryAllocations",
      "projectCreatedAtMilliseconds",
    ],
    properties: Object.freeze({
      operationId: { type: "string", minLength: 1, maxLength: 128 },
      projectId: { type: "string", minLength: 1, maxLength: 128 },
      clientSelection: clientSelectionSchema,
      displayName: { type: "string", minLength: 1 },
      description: { type: ["string", "null"] },
      categoryAllocations: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          required: ["categoryId"],
          properties: {
            categoryId: { type: "string", minLength: 1, maxLength: 128 },
            allocation: {
              type: "object",
              additionalProperties: false,
              required: ["minorUnits", "currency"],
              properties: {
                minorUnits: { type: "integer", minimum: 0 },
                currency: { type: "string", pattern: "^[A-Z]{3}$" },
              },
            },
          },
        },
      },
      projectCreatedAtMilliseconds: { type: "integer" },
    }),
  }),
});
