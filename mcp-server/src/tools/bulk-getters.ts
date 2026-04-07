import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { Firestore } from "firebase-admin/firestore";
import { z } from "zod";
import type { Transaction, Item, Project } from "../types.js";
import { getDocs } from "../util/query.js";
import {
  ProjectionMode,
  transactionSummary,
  itemSummary,
  projectSummary,
  pickFields,
  capResponse,
  asToolResponse,
} from "../util/projections.js";
import { toolError, validation } from "../util/errors.js";
import { withTelemetry } from "../util/telemetry.js";

const MAX_IDS = 50;

const idsSchema = z
  .array(z.string().min(1))
  .min(1)
  .max(MAX_IDS)
  .describe(`Array of document IDs to fetch in a single round-trip. Max ${MAX_IDS}.`);

const commonArgs = {
  ids: idsSchema,
  mode: ProjectionMode.describe(
    "Response shape: 'summary' (compact, default) or 'full' (raw document)."
  ),
  fields: z
    .array(z.string())
    .optional()
    .describe("Optional explicit field list. Overrides `mode` when provided."),
};

function project<T extends Record<string, unknown>>(
  doc: T,
  summary: T,
  mode: "summary" | "full",
  fields: string[] | undefined
): Record<string, unknown> {
  if (fields && fields.length > 0) return pickFields(doc, fields);
  return mode === "full" ? doc : (summary as Record<string, unknown>);
}

export function registerBulkGetterTools(server: McpServer, db: Firestore) {
  // ── get_transactions ───────────────────────────────────────────────────────
  server.tool(
    "get_transactions",
    "[read-only] Fetch multiple transactions by ID in one round-trip. Returns {found, missing}. Prefer this over looping get_transaction when you have a known list of IDs.",
    commonArgs,
    withTelemetry(
      "get_transactions",
      async ({ ids, mode, fields }) => {
        if (ids.length > MAX_IDS) {
          return toolError({
            code: "LIMIT_EXCEEDED",
            message: `Too many IDs: ${ids.length}. Max ${MAX_IDS} per call.`,
            hint: `Split into chunks of ${MAX_IDS} and call again.`,
          });
        }
        const { found, missing } = await getDocs<Transaction>(db, "transactions", ids);
        const projected = found.map((tx) =>
          project(
            tx as unknown as Record<string, unknown>,
            transactionSummary(tx) as unknown as Record<string, unknown>,
            mode,
            fields
          )
        );
        const capped = capResponse(projected);
        return asToolResponse({ ...capped, missing });
      }
    )
  );

  // ── get_items ──────────────────────────────────────────────────────────────
  server.tool(
    "get_items",
    "[read-only] Fetch multiple items by ID in one round-trip. Returns {found, missing}. Prefer this over looping get_item when you have a known list of IDs.",
    commonArgs,
    withTelemetry(
      "get_items",
      async ({ ids, mode, fields }) => {
        if (ids.length > MAX_IDS) {
          return toolError({
            code: "LIMIT_EXCEEDED",
            message: `Too many IDs: ${ids.length}. Max ${MAX_IDS} per call.`,
            hint: `Split into chunks of ${MAX_IDS} and call again.`,
          });
        }
        const { found, missing } = await getDocs<Item>(db, "items", ids);
        const projected = found.map((item) =>
          project(
            item as unknown as Record<string, unknown>,
            itemSummary(item) as unknown as Record<string, unknown>,
            mode,
            fields
          )
        );
        const capped = capResponse(projected);
        return asToolResponse({ ...capped, missing });
      }
    )
  );

  // ── get_projects ───────────────────────────────────────────────────────────
  server.tool(
    "get_projects",
    "[read-only] Fetch multiple projects by ID in one round-trip. Returns {found, missing}.",
    commonArgs,
    withTelemetry(
      "get_projects",
      async ({ ids, mode, fields }) => {
        if (ids.length > MAX_IDS) {
          return validation(
            `Too many IDs: ${ids.length}. Max ${MAX_IDS} per call.`,
            `Split into chunks of ${MAX_IDS} and call again.`
          );
        }
        const { found, missing } = await getDocs<Project>(db, "projects", ids);
        const projected = found.map((p) =>
          project(
            p as unknown as Record<string, unknown>,
            projectSummary(p) as unknown as Record<string, unknown>,
            mode,
            fields
          )
        );
        const capped = capResponse(projected);
        return asToolResponse({ ...capped, missing });
      }
    )
  );
}
