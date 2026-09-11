import assert from "node:assert/strict";
import test from "node:test";

import { TargetMCPFailure, type TargetMCPRequestContext } from "../src/clientCreation.js";
import {
  createProjectTool,
  makeProjectCreationRPCRequest,
  SupabaseProjectCreationApplier,
  type ProjectCreationApplying,
  type ProjectCreationRPCRequest,
  type ProjectCreationRPCResult,
} from "../src/projectCreation.js";

const context: TargetMCPRequestContext = {
  accountId: "account-primary",
  principalId: "principal-owner",
  accessToken: "user-access-token",
};

const input = {
  operationId: "operation-mcp-project",
  projectId: "project-mcp",
  clientSelection: {
    kind: "new" as const,
    clientId: "client-mcp-project",
    displayName: "MCP Project Client",
  },
  displayName: "  MCP Project  ",
  description: "  Canonical description  ",
  categoryAllocations: [
    { categoryId: "category-furnishings" },
    {
      categoryId: "category-design-fee",
      allocation: { minorUnits: 2500, currency: "EUR" },
    },
    {
      categoryId: "category-zero",
      allocation: { minorUnits: 0, currency: "USD" },
    },
  ],
  projectCreatedAtMilliseconds: 1_788_523_200_000,
};

test("MCP canonicalizes Project setup exactly like the app contract", () => {
  const request = makeProjectCreationRPCRequest(input, context);
  assert.deepEqual(request.categoryAllocations.map((row) => row.categoryId), [
    "category-design-fee",
    "category-furnishings",
    "category-zero",
  ]);
  assert.equal(request.description, "Canonical description");
  assert.equal(request.projectDisplayName, "  MCP Project  ");
  assert.equal(request.fingerprint.length, 64);
  assert.equal(
    request.envelopeJSON,
    '{"accountId":"account-primary","actorPrincipalId":"principal-owner","clientCreatedAt":1788523200000,"contractVersion":"project-create-v1","operationId":"operation-mcp-project","payload":{"categoryAllocations":[{"allocation":{"currency":"EUR","minorUnits":2500},"categoryId":"category-design-fee"},{"categoryId":"category-furnishings"},{"allocation":{"currency":"USD","minorUnits":0},"categoryId":"category-zero"}],"clientSelection":{"clientId":"client-mcp-project","displayName":"MCP Project Client","kind":"new"},"description":"Canonical description","displayName":"  MCP Project  ","projectId":"project-mcp"},"preconditions":[]}',
  );
});

test("Project tool validates exact terminal identity", async () => {
  let observed: ProjectCreationRPCRequest | undefined;
  const applier: ProjectCreationApplying = {
    async apply(request): Promise<ProjectCreationRPCResult> {
      observed = request;
      return {
        operationId: request.operationId,
        accountId: request.accountId,
        commandFingerprint: request.fingerprint,
        subjectId: request.projectId,
        phase: "applied",
        resultCode: "project_created",
        errorCode: null,
      };
    },
  };
  const result = await createProjectTool(input, context, applier);
  assert.equal(result.phase, "applied");
  assert.equal(observed?.clientSelectionKind, "new");
});

test("Project tool rejects duplicate categories and negative money before backend work", async () => {
  let callCount = 0;
  const applier: ProjectCreationApplying = {
    async apply(): Promise<ProjectCreationRPCResult> {
      callCount += 1;
      throw new Error("must not run");
    },
  };
  await assert.rejects(
    createProjectTool({
      ...input,
      categoryAllocations: [
        { categoryId: "category-same" },
        { categoryId: "category-same" },
      ],
    }, context, applier),
    (error) => error instanceof TargetMCPFailure
      && error.code === "project_setup_category_identity_duplicate",
  );
  await assert.rejects(
    createProjectTool({
      ...input,
      categoryAllocations: [{
        categoryId: "category-negative",
        allocation: { minorUnits: -1, currency: "USD" },
      }],
    }, context, applier),
    (error) => error instanceof TargetMCPFailure
      && error.code === "project_setup_category_allocation_negative",
  );
  assert.equal(callCount, 0);
});

test("Supabase Project adapter uses only scoped token and public key", async () => {
  const request = makeProjectCreationRPCRequest(input, context);
  let observedURL: URL | undefined;
  let observedInit: RequestInit | undefined;
  const adapter = new SupabaseProjectCreationApplier(
    new URL("https://target.invalid"),
    "publishable-key",
    async (resource, init) => {
      observedURL = resource instanceof URL ? resource : new URL(String(resource));
      observedInit = init;
      return new Response(JSON.stringify({
        operation_id: request.operationId,
        account_id: request.accountId,
        command_fingerprint: request.fingerprint,
        subject_id: request.projectId,
        phase: "applied",
        result_code: "project_created",
        error_code: null,
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    },
  );

  const result = await adapter.apply(request, context);
  assert.equal(result.phase, "applied");
  assert.equal(observedURL?.pathname, "/rest/v1/rpc/spike_create_project");
  assert.equal((observedInit?.headers as Record<string, string>).apikey, "publishable-key");
  assert.equal(
    (observedInit?.headers as Record<string, string>).Authorization,
    "Bearer user-access-token",
  );
  assert.doesNotMatch(JSON.stringify(observedInit), /service.role/i);
});

test("Supabase Project adapter rejects incoherent terminal state", async () => {
  const request = makeProjectCreationRPCRequest(input, context);
  const adapter = new SupabaseProjectCreationApplier(
    new URL("https://target.invalid"),
    "publishable-key",
    async () => new Response(JSON.stringify({
      operation_id: request.operationId,
      account_id: request.accountId,
      command_fingerprint: request.fingerprint,
      subject_id: request.projectId,
      phase: "applied",
      result_code: null,
      error_code: "impossible",
    }), { status: 200, headers: { "Content-Type": "application/json" } }),
  );
  await assert.rejects(
    adapter.apply(request, context),
    (error) => error instanceof TargetMCPFailure
      && error.code === "project_setup_server_result_mismatch",
  );
});
