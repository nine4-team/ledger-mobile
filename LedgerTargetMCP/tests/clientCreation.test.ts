import assert from "node:assert/strict";
import test from "node:test";

import {
  createClientTool,
  makeClientCreationRPCRequest,
  SupabaseClientCreationApplier,
  TargetMCPFailure,
  type ClientCreationApplying,
  type ClientCreationRPCRequest,
  type ClientCreationRPCResult,
  type TargetMCPRequestContext,
} from "../src/clientCreation.js";

const context: TargetMCPRequestContext = {
  accountId: "account-primary",
  principalId: "principal-owner",
  accessToken: "user-access-token",
};

const input = {
  operationId: "operation-mcp-client",
  clientId: "client-mcp",
  displayName: "MCP Client",
  clientCreatedAtMilliseconds: 1_788_523_200_000,
};

test("MCP and app share the exact canonical Client creation envelope", () => {
  const request = makeClientCreationRPCRequest(input, context);
  assert.equal(
    request.envelopeJSON,
    '{"accountId":"account-primary","actorPrincipalId":"principal-owner","clientCreatedAt":1788523200000,"contractVersion":"client-create-v1","operationId":"operation-mcp-client","payload":{"clientId":"client-mcp","displayName":"MCP Client"},"preconditions":[]}',
  );
  assert.equal(request.fingerprint.length, 64);
  assert.equal(
    request.fingerprint,
    "afbf890c23952707ad3d7612747baba36be779853da9a6f107fde7285cc1cbf8",
  );
  assert.equal(request.accountId, context.accountId);
  assert.equal(request.actorPrincipalId, context.principalId);
});

test("tool validates the authoritative result before reporting completion", async () => {
  let observed: ClientCreationRPCRequest | undefined;
  const applier: ClientCreationApplying = {
    async apply(request): Promise<ClientCreationRPCResult> {
      observed = request;
      return {
        operationId: request.operationId,
        accountId: request.accountId,
        commandFingerprint: request.fingerprint,
        subjectId: request.clientId,
        phase: "applied",
        resultCode: "client_created",
        errorCode: null,
      };
    },
  };
  const result = await createClientTool(input, context, applier);
  assert.equal(result.phase, "applied");
  assert.equal(observed?.accountId, "account-primary");
  assert.equal(observed?.actorPrincipalId, "principal-owner");
});

test("tool refuses malformed identifiers before calling the backend", async () => {
  let callCount = 0;
  const applier: ClientCreationApplying = {
    async apply(): Promise<ClientCreationRPCResult> {
      callCount += 1;
      throw new Error("must not run");
    },
  };
  await assert.rejects(
    createClientTool({ ...input, clientId: " client" }, context, applier),
    (error) => error instanceof TargetMCPFailure
      && error.code === "client_creation_client_id_invalid",
  );
  assert.equal(callCount, 0);
});

test("Supabase adapter forwards only the scoped user token and publishable key", async () => {
  const request = makeClientCreationRPCRequest(input, context);
  let observedURL: URL | undefined;
  let observedInit: RequestInit | undefined;
  const fetchImplementation: typeof fetch = async (resource, init) => {
    observedURL = resource instanceof URL ? resource : new URL(String(resource));
    observedInit = init;
    return new Response(JSON.stringify({
      operation_id: request.operationId,
      account_id: request.accountId,
      command_fingerprint: request.fingerprint,
      subject_id: request.clientId,
      phase: "applied",
      result_code: "client_created",
      error_code: null,
    }), { status: 200, headers: { "Content-Type": "application/json" } });
  };
  const adapter = new SupabaseClientCreationApplier(
    new URL("https://target.invalid"),
    "publishable-key",
    fetchImplementation,
  );
  const result = await adapter.apply(request, context);
  assert.equal(result.phase, "applied");
  assert.equal(observedURL?.pathname, "/rest/v1/rpc/spike_create_client");
  assert.equal((observedInit?.headers as Record<string, string>).apikey, "publishable-key");
  assert.equal(
    (observedInit?.headers as Record<string, string>).Authorization,
    "Bearer user-access-token",
  );
  assert.doesNotMatch(JSON.stringify(observedInit), /service.role/i);
});

test("Supabase adapter refuses malformed terminal state instead of coercing it", async () => {
  const request = makeClientCreationRPCRequest(input, context);
  const adapter = new SupabaseClientCreationApplier(
    new URL("https://target.invalid"),
    "publishable-key",
    async () => new Response(JSON.stringify({
      operation_id: request.operationId,
      account_id: request.accountId,
      command_fingerprint: request.fingerprint,
      subject_id: request.clientId,
      phase: "unknown",
      result_code: null,
      error_code: null,
    }), { status: 200, headers: { "Content-Type": "application/json" } }),
  );
  await assert.rejects(
    adapter.apply(request, context),
    (error) => error instanceof TargetMCPFailure
      && error.code === "client_creation_server_result_mismatch",
  );
});
