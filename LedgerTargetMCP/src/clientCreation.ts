import { createHash } from "node:crypto";
import {
  canonicalJSON,
  TargetMCPFailure,
  validateIdentifier,
  validateTerminalResult,
  type TargetMCPRequestContext,
} from "./contractSupport.js";

export { TargetMCPFailure, type TargetMCPRequestContext } from "./contractSupport.js";

const CONTRACT_VERSION = "client-create-v1";

export type CreateClientToolInput = Readonly<{
  operationId: string;
  clientId: string;
  displayName: string;
  clientCreatedAtMilliseconds: number;
}>;

export type ClientCreationRPCRequest = Readonly<{
  operationId: string;
  accountId: string;
  actorPrincipalId: string;
  contractVersion: typeof CONTRACT_VERSION;
  clientCreatedAtMilliseconds: number;
  clientId: string;
  displayName: string;
  fingerprint: string;
  envelopeJSON: string;
}>;

export type ClientCreationRPCResult = Readonly<{
  operationId: string;
  accountId: string;
  commandFingerprint: string;
  subjectId: string;
  phase: "applied" | "rejected";
  resultCode: string | null;
  errorCode: string | null;
}>;

export interface ClientCreationApplying {
  apply(
    request: ClientCreationRPCRequest,
    context: TargetMCPRequestContext,
  ): Promise<ClientCreationRPCResult>;
}

export function makeClientCreationRPCRequest(
  input: CreateClientToolInput,
  context: TargetMCPRequestContext,
): ClientCreationRPCRequest {
  const operationId = validateIdentifier(
    input.operationId,
    "client_creation_operation_id_invalid",
  );
  const accountId = validateIdentifier(context.accountId, "account_not_authorized");
  const actorPrincipalId = validateIdentifier(context.principalId, "account_not_authorized");
  const clientId = validateIdentifier(input.clientId, "client_creation_client_id_invalid");
  if (input.displayName.trim().length === 0) {
    throw new TargetMCPFailure("client_directory_client_name_invalid");
  }
  if (!Number.isSafeInteger(input.clientCreatedAtMilliseconds)) {
    throw new TargetMCPFailure("client_creation_created_at_invalid");
  }
  const clientCreatedAt = new Date(input.clientCreatedAtMilliseconds);
  if (Number.isNaN(clientCreatedAt.valueOf())) {
    throw new TargetMCPFailure("client_creation_created_at_invalid");
  }

  const envelope = {
    accountId,
    actorPrincipalId,
    clientCreatedAt: input.clientCreatedAtMilliseconds,
    contractVersion: CONTRACT_VERSION,
    operationId,
    payload: { clientId, displayName: input.displayName },
    preconditions: [],
  };
  const envelopeJSON = canonicalJSON(
    envelope,
    "client_creation_command_encoding_invalid",
  );
  const fingerprint = createHash("sha256").update(envelopeJSON).digest("hex");

  return {
    operationId,
    accountId,
    actorPrincipalId,
    contractVersion: CONTRACT_VERSION,
    clientCreatedAtMilliseconds: input.clientCreatedAtMilliseconds,
    clientId,
    displayName: input.displayName,
    fingerprint,
    envelopeJSON,
  };
}

export async function createClientTool(
  input: CreateClientToolInput,
  context: TargetMCPRequestContext,
  applier: ClientCreationApplying,
): Promise<ClientCreationRPCResult> {
  if (context.accessToken.length === 0) {
    throw new TargetMCPFailure("authentication_required");
  }
  const request = makeClientCreationRPCRequest(input, context);
  const result = await applier.apply(request, context);
  if (
    result.operationId !== request.operationId
    || result.accountId !== request.accountId
    || result.commandFingerprint !== request.fingerprint
    || result.subjectId !== request.clientId
    || !["applied", "rejected"].includes(result.phase)
  ) {
    throw new TargetMCPFailure("client_creation_server_result_mismatch");
  }
  return result;
}

export class SupabaseClientCreationApplier implements ClientCreationApplying {
  readonly #rpcURL: URL;
  readonly #publishableKey: string;
  readonly #fetch: typeof fetch;

  constructor(
    supabaseURL: URL,
    publishableKey: string,
    fetchImplementation: typeof fetch = fetch,
  ) {
    if (!(["http:", "https:"].includes(supabaseURL.protocol)) || publishableKey.length === 0) {
      throw new TargetMCPFailure("client_creation_configuration_invalid");
    }
    this.#rpcURL = new URL("/rest/v1/rpc/spike_create_client", supabaseURL);
    this.#publishableKey = publishableKey;
    this.#fetch = fetchImplementation;
  }

  async apply(
    request: ClientCreationRPCRequest,
    context: TargetMCPRequestContext,
  ): Promise<ClientCreationRPCResult> {
    if (context.accessToken.length === 0) {
      throw new TargetMCPFailure("authentication_required");
    }
    const clientCreatedAt = new Date(request.clientCreatedAtMilliseconds);
    if (Number.isNaN(clientCreatedAt.valueOf())) {
      throw new TargetMCPFailure("client_creation_created_at_invalid");
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
        p_client_created_at: clientCreatedAt.toISOString(),
        p_client_id: request.clientId,
        p_display_name: request.displayName,
        p_fingerprint: request.fingerprint,
        p_envelope_json: request.envelopeJSON,
      }),
    });
    if (!response.ok) {
      throw new TargetMCPFailure("client_creation_request_rejected", response.status);
    }
    const body = await response.json() as Record<string, unknown>;
    const phase = body.phase;
    const resultCode = body.result_code;
    const errorCode = body.error_code;
    validateTerminalResult(
      phase,
      resultCode,
      errorCode,
      "client_creation_server_result_mismatch",
    );
    return {
      operationId: String(body.operation_id),
      accountId: String(body.account_id),
      commandFingerprint: String(body.command_fingerprint),
      subjectId: String(body.subject_id),
      phase,
      resultCode: resultCode as string | null,
      errorCode: errorCode as string | null,
    };
  }
}

export const createClientToolDefinition = Object.freeze({
  name: "create_client",
  description: "Create one stable Client identity in the current Ledger account.",
  inputSchema: Object.freeze({
    type: "object",
    additionalProperties: false,
    required: ["operationId", "clientId", "displayName", "clientCreatedAtMilliseconds"],
    properties: Object.freeze({
      operationId: { type: "string", minLength: 1, maxLength: 128 },
      clientId: { type: "string", minLength: 1, maxLength: 128 },
      displayName: { type: "string", minLength: 1 },
      clientCreatedAtMilliseconds: { type: "integer" },
    }),
  }),
});
