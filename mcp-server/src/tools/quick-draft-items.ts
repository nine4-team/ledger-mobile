import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { type Firestore, FieldValue } from "firebase-admin/firestore";
import { z } from "zod";
import type { AttachmentRef, Item, ProtoItem, Transaction } from "../types.js";
import { getAccountId, getUid } from "../context.js";
import { accountCollection, getDoc, queryDocs } from "../util/query.js";
import { quickDraftItemMatches } from "../util/search.js";
import {
  ProjectionMode,
  ResponseLimitArg,
  asToolResponse,
  capResponse,
  pickFields,
  quickDraftItemSummary,
} from "../util/projections.js";
import { notFound, validation } from "../util/errors.js";
import { withTelemetry } from "../util/telemetry.js";
import {
  quickDraftCaptureContexts,
  quickDraftItemStatuses,
  quickDraftSourceHints,
} from "../util/enums.js";
import { checkTransactionLinkageOnCreate, checkUpdateInvariant } from "./items.js";
import {
  applyItemPriceFloorToCreate,
  applyItemPriceFloorToUpdate,
  normalizedProjectPriceCents,
} from "../util/item-pricing.js";
import { resolveInventoryLabel } from "../util/inventory.js";
import { normalizePrimaryAttachments } from "../util/attachment-primary.js";
import {
  cleanupCopiedItemImages,
  copyAttachmentsToItemNamespace,
  type CopiedItemImages,
} from "../util/item-image-storage.js";
import {
  attachmentStorageUrls,
  imageOperationResult,
  isPathOwnedByItem,
  orderedWithPrimary,
} from "../util/item-images.js";
import { storagePathFromUrl } from "../storage.js";

const QuickDraftStatus = z.enum(quickDraftItemStatuses);
const QuickDraftCaptureContext = z.enum(quickDraftCaptureContexts);
const QuickDraftSourceHint = z.enum(quickDraftSourceHints);

const AttachmentInput = z.object({
  url: z.string(),
  thumbnailUrlSm: z.string().optional(),
  thumbnailUrlMd: z.string().optional(),
  kind: z.string().default("image"),
  fileName: z.string().optional(),
  contentType: z.string().optional(),
  isPrimary: z.boolean().optional(),
});

const ExtractionInput = z.object({
  rawText: z.string().optional(),
  barcodePayloads: z.array(z.string()).optional(),
  skuCandidates: z.array(z.string()).optional(),
  confidence: z.coerce.number().optional(),
}).optional();

function defaultCaptureContext(args: {
  transactionId?: string;
  projectId?: string | null;
}): "project" | "inventory" | "transaction" {
  if (args.transactionId) return "transaction";
  if (args.projectId) return "project";
  return "inventory";
}

function formatQuickDraftItem(draft: ProtoItem & { id: string }) {
  return {
    id: draft.id,
    accountId: draft.accountId ?? null,
    projectId: draft.projectId ?? null,
    intendedProjectId: draft.intendedProjectId ?? null,
    transactionId: draft.transactionId ?? null,
    name: draft.name ?? "",
    captureContext: draft.captureContext ?? defaultCaptureContext(draft),
    status: draft.status ?? "open",
    sourceHint: draft.sourceHint ?? "unknown",
    sku: draft.sku ?? "",
    quantity: draft.quantity ?? 1,
    notes: draft.notes ?? "",
    extracted: draft.extracted ?? null,
    candidateTransactionId: draft.candidateTransactionId ?? null,
    candidateItemId: draft.candidateItemId ?? null,
    convertedItemId: draft.convertedItemId ?? null,
    convertedAt: draft.convertedAt ?? null,
    photoCount: draft.photos?.length ?? 0,
    photos: (draft.photos ?? []).map((ref: AttachmentRef) => ({
      url: ref.url,
      thumbnailUrlSm: ref.thumbnailUrlSm ?? null,
      thumbnailUrlMd: ref.thumbnailUrlMd ?? null,
      kind: ref.kind ?? "image",
      fileName: ref.fileName ?? null,
      contentType: ref.contentType ?? null,
      isPrimary: ref.isPrimary ?? false,
    })),
  };
}

function projectDraft(
  draft: ProtoItem & { id: string },
  mode: "summary" | "full",
  fields: string[] | undefined
): Record<string, unknown> {
  const full = formatQuickDraftItem(draft) as Record<string, unknown>;
  if (fields && fields.length > 0) return pickFields(full, fields);
  return mode === "full"
    ? full
    : (quickDraftItemSummary(draft) as unknown as Record<string, unknown>);
}

function cleanString(value: string | undefined | null): string | undefined {
  const trimmed = value?.trim();
  return trimmed ? trimmed : undefined;
}

export function documentedPromotionMergeOverrides(
  existingItem: Item,
  draft: ProtoItem,
  args: {
    name?: string;
    notes?: string;
    quantity?: number;
    sku?: string;
    status?: string;
    source?: string;
    purchasePriceCents?: number;
    projectPriceCents?: number;
    marketValueCents?: number;
    taxRatePct?: number;
    projectId?: string | null;
    transactionId?: string | null;
    budgetCategoryId?: string | null;
    spaceId?: string;
  }
): Record<string, unknown> {
  const updates: Record<string, unknown> = {};
  if (args.name !== undefined) updates.name = cleanString(args.name) ?? "Untitled item";
  if (args.notes !== undefined) updates.notes = args.notes;
  if (args.quantity !== undefined) updates.quantity = args.quantity;
  if (args.sku !== undefined) updates.sku = cleanString(args.sku) ?? "";
  else if (!cleanString(existingItem.sku) && cleanString(draft.sku)) updates.sku = cleanString(draft.sku);
  if (args.status !== undefined) updates.status = args.status;
  if (args.source !== undefined) updates.source = args.source;
  if (args.purchasePriceCents !== undefined) updates.purchasePriceCents = args.purchasePriceCents;
  if (args.projectPriceCents !== undefined) updates.projectPriceCents = args.projectPriceCents;
  if (args.marketValueCents !== undefined) updates.marketValueCents = args.marketValueCents;
  if (args.taxRatePct !== undefined) updates.taxRatePct = args.taxRatePct;
  if (args.projectId !== undefined) updates.projectId = args.projectId;
  if (args.transactionId !== undefined) updates.transactionId = args.transactionId;
  if (args.budgetCategoryId !== undefined) updates.budgetCategoryId = args.budgetCategoryId;
  if (args.spaceId !== undefined) updates.spaceId = args.spaceId;
  return updates;
}

export function mergePromotedAttachments(existing: AttachmentRef[], incoming: AttachmentRef[]): AttachmentRef[] {
  if (incoming.length === 0) return orderedWithPrimary(existing);
  const incomingPrimary = incoming.find((attachment) => attachment.isPrimary)?.url ?? incoming[0].url;
  return orderedWithPrimary([...incoming, ...existing], incomingPrimary);
}

async function validateDraftTransactionLink(
  db: Firestore,
  projectId: string | null,
  transactionId?: string
): Promise<{ message: string; nextAction: string } | null> {
  if (!transactionId) return null;
  const transaction = await getDoc<Transaction>(db, "transactions", transactionId);
  if (!transaction) {
    return {
      message: `Transaction ${transactionId} does not exist.`,
      nextAction: "Choose a transaction returned by list_transactions.",
    };
  }
  if (transaction.projectId && transaction.projectId !== projectId) {
    return {
      message: `Transaction ${transactionId} belongs to project ${transaction.projectId}, not ${projectId ?? "inventory"}.`,
      nextAction: "Choose a transaction in the draft project, or an inventory acquisition Purchase.",
    };
  }
  if (projectId && !transaction.projectId) {
    if (transaction.type?.toLowerCase() !== "purchase") {
      return {
        message: `Inventory transaction ${transactionId} is not a Purchase acquisition.`,
        nextAction: "Choose the vendor Purchase that acquired the inventory item.",
      };
    }
    if (transaction.intendedProjectId && transaction.intendedProjectId !== projectId) {
      return {
        message: `Inventory transaction ${transactionId} is intended for project ${transaction.intendedProjectId}, not ${projectId}.`,
        nextAction: "Choose the intended project or update the acquisition intent first.",
      };
    }
  }
  return null;
}

async function promoteInventoryDraftToProject(
  db: Firestore,
  args: {
    quickDraftItemId: string;
    name?: string;
    projectId: string;
    transactionId: string;
    budgetCategoryId: string;
    spaceId?: string;
    status?: string;
    source?: string;
    sku?: string;
    quantity?: number;
    purchasePriceCents?: number;
    projectPriceCents: number;
    marketValueCents?: number;
    taxRatePct?: number;
    notes?: string;
    primaryImageUrl?: string;
  },
  draft: ProtoItem & { id: string },
  acquisition: Transaction & { id: string }
) {
  const categorySnap = await accountCollection(db, "projects")
    .doc(args.projectId)
    .collection("budgetCategories")
    .doc(args.budgetCategoryId)
    .get();
  if (!categorySnap.exists) {
    return validation(
      `Budget category ${args.budgetCategoryId} is not enabled in project ${args.projectId}.`,
      "Pick a category from get_project_budget_categories before promoting the draft."
    );
  }

  const now = new Date();
  const uid = getUid();
  const inventoryLabel = await resolveInventoryLabel(db);
  const itemRef = accountCollection(db, "items").doc();
  const purchaseRef = accountCollection(db, "transactions").doc();
  const rate = args.taxRatePct ?? acquisition.taxRatePct ?? 0;
  const subtotalCents = args.projectPriceCents;
  const amountCents = rate > 0
    ? Math.round(subtotalCents * (1 + rate / 100))
    : subtotalCents;
  const sku = cleanString(args.sku) ?? cleanString(draft.sku);
  const notes = args.notes !== undefined ? args.notes : draft.notes;

  let copied: CopiedItemImages;
  try {
    copied = await copyAttachmentsToItemNamespace(
      draft.photos ?? [],
      getAccountId(),
      itemRef.id,
      args.primaryImageUrl
    );
  } catch (error) {
    return validation(
      `Could not copy and verify quick-draft photos: ${error instanceof Error ? error.message : String(error)}`,
      "The draft and its source photos were left unchanged. Repair the source file, then retry promotion."
    );
  }

  const itemData: Record<string, unknown> = {
    accountId: getAccountId(),
    name: cleanString(args.name) ?? cleanString(draft.name) ?? sku ?? "Untitled item",
    projectId: args.projectId,
    budgetCategoryId: args.budgetCategoryId,
    transactionId: purchaseRef.id,
    status: args.status ?? "purchased",
    quantity: args.quantity ?? draft.quantity ?? 1,
    images: copied.images,
    source: args.source ?? acquisition.source ?? inventoryLabel,
    currentSource: inventoryLabel,
    projectPriceCents: args.projectPriceCents,
    taxRatePct: rate,
    createdBy: uid,
    updatedBy: uid,
    createdAt: now,
    updatedAt: now,
  };
  if (args.spaceId) itemData.spaceId = args.spaceId;
  if (sku) itemData.sku = sku;
  if (notes) itemData.notes = notes;
  if (args.purchasePriceCents !== undefined) itemData.purchasePriceCents = args.purchasePriceCents;
  applyItemPriceFloorToCreate(itemData, args);
  if (args.marketValueCents !== undefined) itemData.marketValueCents = args.marketValueCents;

  const batch = db.batch();
  batch.set(itemRef, itemData);
  batch.set(purchaseRef, {
    type: "Purchase",
    source: inventoryLabel,
    projectId: args.projectId,
    budgetCategoryId: args.budgetCategoryId,
    amountCents,
    subtotalCents,
    itemIds: [itemRef.id],
    isComplete: true,
    createdAt: now,
    updatedAt: now,
    createdBy: uid,
  });
  batch.update(accountCollection(db, "transactions").doc(args.transactionId), {
    itemIds: FieldValue.arrayRemove(itemRef.id),
    inventoryIntentResolvedAt: now,
    updatedAt: now,
  });
  batch.set(accountCollection(db, "lineageEdges").doc(), {
    accountId: getAccountId(),
    itemId: itemRef.id,
    fromTransactionId: args.transactionId,
    toTransactionId: purchaseRef.id,
    fromProjectId: null,
    toProjectId: args.projectId,
    movementKind: "sold",
    source: "mcp",
    createdAt: now,
    createdBy: uid,
  });
  batch.update(accountCollection(db, "protoItems").doc(args.quickDraftItemId), {
    status: "converted",
    convertedItemId: itemRef.id,
    convertedAt: now,
    convertedBy: uid,
    updatedAt: now,
    updatedBy: uid,
  });
  try {
    await batch.commit();
  } catch (error) {
    await cleanupCopiedItemImages(copied);
    throw error;
  }

  return asToolResponse({
    quickDraftItemId: args.quickDraftItemId,
    acquisitionTransactionId: args.transactionId,
    projectPurchaseTransactionId: purchaseRef.id,
    routedThroughInventory: true,
    status: "converted",
    ...imageOperationResult({
      itemId: itemRef.id,
      images: copied.images,
      storageObjectsCopied: copied.copiedPaths.length > 0,
      storagePathsAffected: copied.copiedPaths,
    }),
  });
}

export function registerQuickDraftItemTools(server: McpServer, db: Firestore) {
  // ── list_quick_draft_items ────────────────────────────────────────────────
  server.tool(
    "list_quick_draft_items",
    "[read-only] List item quick drafts from accounts/{accountId}/protoItems. These are photo-first draft captures that are not real items until promoted. Supports exact-match filters and pagination.",
    {
      projectId: z.string().optional().describe("Filter by project ID. Use 'inventory' for inventory-scope drafts with no project."),
      intendedProjectId: z.string().optional().describe("Filter by intended destination project ID."),
      transactionId: z.string().optional().describe("Filter by linked transaction ID."),
      status: QuickDraftStatus.optional().describe("Filter by draft status."),
      captureContext: QuickDraftCaptureContext.optional().describe("Filter by capture context."),
      sourceHint: QuickDraftSourceHint.optional().describe("Filter by source hint."),
      activeOnly: z.boolean().default(false).describe("When true, only return open/in_review drafts."),
      limit: z.coerce.number().default(50).describe("Max results (ignored when fetchAll is true)."),
      offset: z.coerce.number().default(0).describe("Number of results to skip."),
      fetchAll: z.boolean().default(false).describe("Return all matching drafts subject to the response byte budget."),
      mode: ProjectionMode.describe("'summary' (default) or 'full'."),
      fields: z.array(z.string()).optional().describe("Explicit field list. Overrides mode."),
      responseLimit: ResponseLimitArg,
    },
    withTelemetry("list_quick_draft_items", async ({ projectId, intendedProjectId, transactionId, status, captureContext, sourceHint, activeOnly, limit, offset, fetchAll, mode, fields, responseLimit }) => {
      let query: FirebaseFirestore.Query = accountCollection(db, "protoItems");

      if (projectId === "inventory") query = query.where("projectId", "==", null);
      else if (projectId) query = query.where("projectId", "==", projectId);
      if (intendedProjectId) query = query.where("intendedProjectId", "==", intendedProjectId);
      if (transactionId) query = query.where("transactionId", "==", transactionId);
      if (status) query = query.where("status", "==", status);
      if (captureContext) query = query.where("captureContext", "==", captureContext);
      if (sourceHint) query = query.where("sourceHint", "==", sourceHint);
      if (activeOnly && !status) query = query.where("status", "in", ["open", "in_review"]);

      if (!fetchAll) query = query.offset(offset).limit(limit);
      let drafts = await queryDocs<ProtoItem>(query);
      if (activeOnly && status) {
        drafts = drafts.filter((draft) => draft.status === "open" || draft.status === "in_review");
      }
      const page = fetchAll ? drafts : drafts.slice(0, limit);
      const projected = page.map((draft) => projectDraft(draft, mode, fields));
      return asToolResponse(capResponse(projected, { limitBytes: responseLimit, offset, fetchAll }));
    })
  );

  // ── get_quick_draft_item ─────────────────────────────────────────────────
  server.tool(
    "get_quick_draft_item",
    "[read-only] Get one item quick draft with all details, including photos[].",
    { quickDraftItemId: z.string().describe("Quick draft item document ID from protoItems.") },
    withTelemetry("get_quick_draft_item", async ({ quickDraftItemId }) => {
      const draft = await getDoc<ProtoItem>(db, "protoItems", quickDraftItemId);
      if (!draft) return notFound("Quick draft item", quickDraftItemId, "list_quick_draft_items");
      return asToolResponse(formatQuickDraftItem(draft));
    })
  );

  // ── search_quick_draft_items ─────────────────────────────────────────────
  server.tool(
    "search_quick_draft_items",
    "[read-only] Search item quick drafts by name, notes, SKU, extracted text, barcodes, and SKU candidates.",
    {
      query: z.string().describe("Search term."),
      projectId: z.string().optional().describe("Scope to a project, or 'inventory' for inventory-scope drafts."),
      status: QuickDraftStatus.optional().describe("Optional status filter."),
      activeOnly: z.boolean().default(false).describe("When true, only search open/in_review drafts."),
      limit: z.coerce.number().default(25).describe("Max results."),
      offset: z.coerce.number().default(0).describe("Number of matches to skip."),
      mode: ProjectionMode.describe("'summary' (default) or 'full'."),
      fields: z.array(z.string()).optional().describe("Explicit field list. Overrides mode."),
      responseLimit: ResponseLimitArg,
    },
    withTelemetry("search_quick_draft_items", async ({ query: searchTerm, projectId, status, activeOnly, limit, offset, mode, fields, responseLimit }) => {
      let q: FirebaseFirestore.Query = accountCollection(db, "protoItems");
      if (projectId === "inventory") q = q.where("projectId", "==", null);
      else if (projectId) q = q.where("projectId", "==", projectId);
      if (status) q = q.where("status", "==", status);
      if (activeOnly && !status) q = q.where("status", "in", ["open", "in_review"]);

      let all = await queryDocs<ProtoItem>(q);
      if (activeOnly && status) {
        all = all.filter((draft) => draft.status === "open" || draft.status === "in_review");
      }
      const matched = all
        .filter((draft) => quickDraftItemMatches(draft, searchTerm))
        .slice(offset, offset + limit);
      const projected = matched.map((draft) => projectDraft(draft, mode, fields));
      return asToolResponse(capResponse(projected, { limitBytes: responseLimit, offset }));
    })
  );

  server.tool(
    "audit_legacy_quick_draft_transaction_candidates",
    "[read-only] Audit legacy candidateTransactionId metadata. Candidates are never treated as confirmed; use update_quick_draft_item(transactionId: ...) only after human confirmation.",
    {
      activeOnly: z.boolean().default(true),
      limit: z.coerce.number().int().positive().max(500).default(100),
    },
    withTelemetry("audit_legacy_quick_draft_transaction_candidates", async ({ activeOnly, limit }) => {
      const drafts = await queryDocs<ProtoItem>(accountCollection(db, "protoItems").limit(500));
      const candidates = drafts
        .filter((draft) => Boolean(draft.candidateTransactionId))
        .filter((draft) => !activeOnly || draft.status === "open" || draft.status === "in_review" || draft.status == null)
        .slice(0, limit)
        .map((draft) => ({
          quickDraftItemId: draft.id,
          projectId: draft.projectId ?? null,
          sourceHint: draft.sourceHint ?? "unknown",
          authoritativeTransactionId: draft.transactionId ?? null,
          legacyCandidateTransactionId: draft.candidateTransactionId,
          conflict: Boolean(draft.transactionId && draft.transactionId !== draft.candidateTransactionId),
        }));
      return asToolResponse(candidates);
    })
  );

  // ── create_quick_draft_item ──────────────────────────────────────────────
  server.tool(
    "create_quick_draft_item",
    "[mutating] Create a photo-first item quick draft. This does not create a real item or touch transactions. Quantity remains draft metadata; if a later workflow expands it into separate physical item documents, every unit must preserve the resolved draft/source name exactly, without generated suffixes.",
    {
      projectId: z.string().nullable().optional().describe("Project where the draft was captured. Omit/null for inventory."),
      intendedProjectId: z.string().nullable().optional().describe("Optional intended destination project."),
      transactionId: z.string().optional().describe("Optional linked transaction."),
      name: z.string().optional().describe("Draft item name."),
      captureContext: QuickDraftCaptureContext.optional().describe("Defaults from transactionId/projectId."),
      status: QuickDraftStatus.default("open").describe("Draft lifecycle status."),
      sourceHint: QuickDraftSourceHint.default("unknown").describe("Source hint."),
      photos: z.array(AttachmentInput).default([]).describe("Photo attachment refs."),
      sku: z.string().optional().describe("SKU."),
      quantity: z.coerce.number().int().positive().default(1).describe("Quantity. Expansion into separate item documents must reuse the exact resolved source name for every unit."),
      notes: z.string().optional().describe("Draft notes."),
      extracted: ExtractionInput,
      candidateItemId: z.string().optional().describe("Suggested existing item match."),
    },
    withTelemetry("create_quick_draft_item", async (args) => {
      const now = new Date();
      const uid = getUid();
      const projectId = args.projectId ?? null;
      const linkageError = await validateDraftTransactionLink(db, projectId, args.transactionId);
      if (linkageError) {
        return validation(linkageError.message, linkageError.nextAction);
      }
      const data: Record<string, unknown> = {
        accountId: getAccountId(),
        projectId,
        intendedProjectId: args.intendedProjectId ?? null,
        captureContext: args.captureContext ?? defaultCaptureContext({ transactionId: args.transactionId, projectId }),
        status: args.status,
        sourceHint: args.sourceHint,
        quantity: args.quantity,
        photos: args.photos,
        createdBy: uid,
        updatedBy: uid,
        createdAt: now,
        updatedAt: now,
      };
      for (const key of ["transactionId", "name", "sku", "notes", "extracted", "candidateItemId"] as const) {
        const value = args[key];
        if (value !== undefined) data[key] = value;
      }
      const ref = await accountCollection(db, "protoItems").add(data);
      return asToolResponse({ quickDraftItemId: ref.id, status: args.status });
    })
  );

  // ── update_quick_draft_item ──────────────────────────────────────────────
  server.tool(
    "update_quick_draft_item",
    "[mutating] Update quick draft item metadata. Use promote_quick_draft_item when it is ready to become a real item.",
    {
      quickDraftItemId: z.string().describe("Quick draft item ID."),
      projectId: z.string().nullable().optional().describe("Project ID. Pass null to clear."),
      intendedProjectId: z.string().nullable().optional().describe("Intended project ID. Pass null to clear."),
      transactionId: z.string().nullable().optional().describe("Authoritative transaction the eventual item should initially join. Pass null to clear."),
      name: z.string().nullable().optional().describe("Draft name. Pass null to clear."),
      captureContext: QuickDraftCaptureContext.optional(),
      status: QuickDraftStatus.optional(),
      sourceHint: QuickDraftSourceHint.optional(),
      photos: z.array(AttachmentInput).optional().describe("Replace the photos array."),
      sku: z.string().nullable().optional().describe("SKU. Pass null to clear."),
      quantity: z.coerce.number().int().positive().optional(),
      notes: z.string().nullable().optional().describe("Notes. Pass null to clear."),
      extracted: ExtractionInput,
      candidateItemId: z.string().nullable().optional().describe("Candidate item. Pass null to clear."),
    },
    withTelemetry("update_quick_draft_item", async ({ quickDraftItemId, ...fields }) => {
      const existing = await getDoc<ProtoItem>(db, "protoItems", quickDraftItemId);
      if (!existing) return notFound("Quick draft item", quickDraftItemId, "list_quick_draft_items");

      const effectiveProjectId = fields.projectId === undefined
        ? (existing.projectId ?? null)
        : fields.projectId;
      const effectiveTransactionId = fields.transactionId === undefined
        ? existing.transactionId
        : (fields.transactionId ?? undefined);
      const linkageError = await validateDraftTransactionLink(
        db,
        effectiveProjectId,
        effectiveTransactionId
      );
      if (linkageError) {
        return validation(linkageError.message, linkageError.nextAction);
      }

      const updates: Record<string, unknown> = {
        updatedAt: new Date(),
        updatedBy: getUid(),
      };
      for (const [key, value] of Object.entries(fields)) {
        if (value !== undefined) updates[key] = value;
      }
      await accountCollection(db, "protoItems").doc(quickDraftItemId).update(updates);
      return asToolResponse({ quickDraftItemId, updated: Object.keys(updates).filter((k) => k !== "updatedAt") });
    })
  );

  // ── delete_quick_draft_item ──────────────────────────────────────────────
  server.tool(
    "delete_quick_draft_item",
    "[mutating] Delete one quick draft item document. This does not delete Storage media.",
    { quickDraftItemId: z.string().describe("Quick draft item ID.") },
    withTelemetry("delete_quick_draft_item", async ({ quickDraftItemId }) => {
      const existing = await getDoc<ProtoItem>(db, "protoItems", quickDraftItemId);
      if (!existing) return notFound("Quick draft item", quickDraftItemId, "list_quick_draft_items");
      await accountCollection(db, "protoItems").doc(quickDraftItemId).delete();
      return asToolResponse({ quickDraftItemId, deleted: true });
    })
  );

  // ── mark_quick_draft_item_in_review ──────────────────────────────────────
  server.tool(
    "mark_quick_draft_item_in_review",
    "[mutating] Mark a quick draft item as in_review.",
    { quickDraftItemId: z.string().describe("Quick draft item ID.") },
    withTelemetry("mark_quick_draft_item_in_review", async ({ quickDraftItemId }) => {
      const existing = await getDoc<ProtoItem>(db, "protoItems", quickDraftItemId);
      if (!existing) return notFound("Quick draft item", quickDraftItemId, "list_quick_draft_items");
      await accountCollection(db, "protoItems").doc(quickDraftItemId).update({
        status: "in_review",
        updatedAt: new Date(),
        updatedBy: getUid(),
      });
      return asToolResponse({ quickDraftItemId, status: "in_review" });
    })
  );

  // ── promote_quick_draft_item ─────────────────────────────────────────────
  server.tool(
    "promote_quick_draft_item",
    "[mutating] Promote one quick draft item into a real item, then mark the draft converted. Full-resolution photos are copied and verified in the destination item's Storage namespace, item-owned thumbnails are generated, and draft originals are preserved. The draft primary is used unless primaryImageUrl selects another draft photo. This call creates one real item. If the captured quantity is instead expanded through a multi-document workflow, every physical item must use the same resolved source name exactly, byte-for-byte; never add generated quantity/copy suffixes.",
    {
      quickDraftItemId: z.string().describe("Quick draft item ID."),
      name: z.string().optional().describe("Override item name. Defaults to draft name, SKU, or 'Untitled item'. For quantity-expanded copies, reuse the resolved name exactly unless the user or source evidence supplies distinct names."),
      projectId: z.string().nullable().optional().describe("Override project ID. Omit to use draft projectId. Pass null for inventory."),
      transactionId: z.string().nullable().optional().describe("Override the authoritative transaction ID. Omit to use draft.transactionId. Pass null to clear."),
      budgetCategoryId: z.string().nullable().optional().describe("Budget category. Auto-inherited from transaction when possible. Must be absent/null for inventory."),
      spaceId: z.string().optional().describe("Optional destination space."),
      status: z.string().optional().describe("Real item status. Defaults to purchased for a new item; preserves the existing status on merge when omitted."),
      source: z.string().optional().describe("Vendor/source for the real item."),
      sku: z.string().optional().describe("Override SKU. Defaults to draft SKU."),
      quantity: z.coerce.number().int().positive().optional().describe("Override quantity. Defaults to draft quantity or 1. This field does not authorize encoding quantity or sequence text in the item name."),
      purchasePriceCents: z.coerce.number().optional(),
      projectPriceCents: z.coerce.number().optional(),
      marketValueCents: z.coerce.number().optional(),
      taxRatePct: z.coerce.number().optional().describe("Auto-inherited from transaction when omitted."),
      notes: z.string().optional().describe("Item notes override. A new item defaults to draft notes; a merge preserves existing notes when omitted."),
      primaryImageUrl: z.string().optional().describe("URL of a current quick-draft photo to make primary. Defaults to the draft's primary photo."),
      mergeIntoItemId: z.string().optional().describe("Instead of creating a new item, copy and merge the draft photos into an existing item. Explicit item-field overrides are applied."),
    },
    withTelemetry("promote_quick_draft_item", async (args) => {
      const draft = await getDoc<ProtoItem>(db, "protoItems", args.quickDraftItemId);
      if (!draft) return notFound("Quick draft item", args.quickDraftItemId, "list_quick_draft_items");
      if (draft.status === "converted") {
        return validation(
          `Quick draft item ${args.quickDraftItemId} is already converted.`,
          "Use get_quick_draft_item to inspect convertedItemId.",
          { convertedItemId: draft.convertedItemId }
        );
      }

      const now = new Date();
      const uid = getUid();
      const draftPhotos = normalizePrimaryAttachments(draft.photos ?? []);

      if (args.mergeIntoItemId) {
        const existingItem = await getDoc<Item>(db, "items", args.mergeIntoItemId);
        if (!existingItem) return notFound("Item", args.mergeIntoItemId, "list_items");

        const nextProjectId = args.projectId !== undefined ? args.projectId : (existingItem.projectId ?? null);
        const nextTransactionId = args.transactionId !== undefined ? args.transactionId : (existingItem.transactionId ?? null);
        let destinationTransaction: (Transaction & { id: string }) | null = null;
        if (nextTransactionId) {
          destinationTransaction = await getDoc<Transaction>(db, "transactions", nextTransactionId);
          if (!destinationTransaction) return notFound("Transaction", nextTransactionId, "list_transactions");
          if ((destinationTransaction.projectId ?? null) !== nextProjectId) {
            return validation(
              "Merged item and transaction must belong to the same project.",
              "Choose a transaction in the resulting project or pass transactionId: null."
            );
          }
        }

        const updates: Record<string, unknown> = {
          ...documentedPromotionMergeOverrides(existingItem, draft, args),
          updatedAt: now,
          updatedBy: uid,
        };

        if (!nextProjectId) {
          updates.budgetCategoryId = null;
        } else if (destinationTransaction) {
          const transactionCategory = destinationTransaction.budgetCategoryId?.trim();
          if (!transactionCategory || transactionCategory.toLowerCase() === "uncategorized") {
            return validation("The destination transaction has no real budget category.", "Assign the transaction a category first.");
          }
          if (args.budgetCategoryId !== undefined && args.budgetCategoryId !== transactionCategory) {
            return validation("budgetCategoryId must match the destination transaction category.", "Omit it to inherit the transaction category.");
          }
          updates.budgetCategoryId = transactionCategory;
        } else if (args.budgetCategoryId !== undefined) {
          updates.budgetCategoryId = args.budgetCategoryId;
        }
        const invariantError = checkUpdateInvariant(existingItem, updates);
        if (invariantError) return validation(invariantError, "Provide a real category for project scope, or null for inventory.");

        let copied: CopiedItemImages;
        try {
          copied = await copyAttachmentsToItemNamespace(
            draftPhotos,
            getAccountId(),
            args.mergeIntoItemId,
            args.primaryImageUrl
          );
        } catch (error) {
          return validation(
            `Could not copy and verify quick-draft photos: ${error instanceof Error ? error.message : String(error)}`,
            "No Firestore records changed and the draft source photos were preserved."
          );
        }
        updates.images = mergePromotedAttachments(existingItem.images ?? [], copied.images);
        applyItemPriceFloorToUpdate(existingItem, updates);

        const batch = db.batch();
        batch.update(accountCollection(db, "items").doc(args.mergeIntoItemId), updates);
        const oldTransactionId = existingItem.transactionId ?? null;
        if (args.transactionId !== undefined && oldTransactionId !== nextTransactionId) {
          if (oldTransactionId) {
            batch.update(accountCollection(db, "transactions").doc(oldTransactionId), {
              itemIds: FieldValue.arrayRemove(args.mergeIntoItemId),
              updatedAt: now,
            });
          }
          if (nextTransactionId) {
            batch.update(accountCollection(db, "transactions").doc(nextTransactionId), {
              itemIds: FieldValue.arrayUnion(args.mergeIntoItemId),
              updatedAt: now,
            });
          }
        }
        batch.update(accountCollection(db, "protoItems").doc(args.quickDraftItemId), {
          status: "converted",
          convertedItemId: args.mergeIntoItemId,
          convertedAt: now,
          convertedBy: uid,
          updatedAt: now,
          updatedBy: uid,
        });
        try {
          await batch.commit();
        } catch (error) {
          await cleanupCopiedItemImages(copied);
          throw error;
        }
        const finalImages = updates.images as AttachmentRef[];
        const hasExternalExistingAttachment = (existingItem.images ?? []).flatMap(attachmentStorageUrls).some((url) => {
          const path = storagePathFromUrl(url);
          return !path || !isPathOwnedByItem(path, getAccountId(), args.mergeIntoItemId!);
        });
        return asToolResponse({
          quickDraftItemId: args.quickDraftItemId,
          merged: true,
          status: "converted",
          ...imageOperationResult({
            itemId: args.mergeIntoItemId,
            images: finalImages,
            storageObjectsCopied: copied.copiedPaths.length > 0,
            storagePathsAffected: copied.copiedPaths,
            warnings: hasExternalExistingAttachment
              ? ["The item still has pre-existing attachments outside its own Storage namespace; they were preserved."]
              : [],
          }),
        });
      }

      const resolvedProjectId = args.projectId !== undefined ? args.projectId : (draft.projectId ?? null);
      const resolvedTransactionId =
        args.transactionId !== undefined
          ? (args.transactionId ?? undefined)
          : draft.transactionId;

      let resolvedTransaction: (Transaction & { id: string }) | null = null;
      if (resolvedTransactionId) {
        resolvedTransaction = await getDoc<Transaction>(db, "transactions", resolvedTransactionId);
        if (!resolvedTransaction) {
          return notFound("Transaction", resolvedTransactionId, "list_transactions");
        }
      }

      if (resolvedProjectId && resolvedTransaction?.projectId && resolvedTransaction.projectId !== resolvedProjectId) {
        return validation(
          `Transaction ${resolvedTransactionId} belongs to project ${resolvedTransaction.projectId}, not ${resolvedProjectId}.`,
          "Choose a transaction in the draft's project, or an inventory acquisition transaction."
        );
      }
      if (!resolvedProjectId && resolvedTransaction?.projectId) {
        return validation(
          `Transaction ${resolvedTransactionId} is project-scoped and cannot be attached to an inventory item.`,
          "Clear transactionId or promote the draft into the transaction's project."
        );
      }

      let resolvedTaxRate = args.taxRatePct;
      let resolvedBudgetCategoryId = args.budgetCategoryId ?? undefined;
      if (resolvedTransaction) {
        if (resolvedTaxRate === undefined && resolvedTransaction.taxRatePct != null) resolvedTaxRate = resolvedTransaction.taxRatePct;
        if (resolvedBudgetCategoryId === undefined && resolvedTransaction.budgetCategoryId) {
          resolvedBudgetCategoryId = resolvedTransaction.budgetCategoryId;
        }
      }
      if (!resolvedProjectId) resolvedBudgetCategoryId = undefined;

      if (resolvedProjectId && resolvedTransaction && !resolvedTransaction.projectId) {
        if (resolvedTransaction.type?.toLowerCase() !== "purchase") {
          return validation(
            `Inventory transaction ${resolvedTransactionId} is not a Purchase acquisition.`,
            "Select the vendor Purchase that acquired the inventory item."
          );
        }
        if (resolvedTransaction.intendedProjectId
          && resolvedTransaction.intendedProjectId !== resolvedProjectId) {
          return validation(
            `Inventory transaction ${resolvedTransactionId} is intended for project ${resolvedTransaction.intendedProjectId}, not ${resolvedProjectId}.`,
            "Choose the intended project or update the acquisition intent before promoting the draft."
          );
        }
        const saleCategoryId = args.budgetCategoryId
          ?? resolvedTransaction.intendedBudgetCategoryId;
        if (!saleCategoryId) {
          return validation(
            "A project budget category is required to sell this draft from inventory.",
            "Pass budgetCategoryId or set intendedBudgetCategoryId on the acquisition transaction."
          );
        }
        const projectPriceCents = normalizedProjectPriceCents(
          args.purchasePriceCents,
          args.projectPriceCents
        ) ?? 0;
        if (projectPriceCents <= 0) {
          return validation(
            "A project price or purchase price must be greater than zero for an inventory-to-project sale.",
            "Set projectPriceCents, or set purchasePriceCents so Ledger can initialize the project price."
          );
        }
        return promoteInventoryDraftToProject(db, {
          ...args,
          projectId: resolvedProjectId,
          transactionId: resolvedTransactionId!,
          budgetCategoryId: saleCategoryId,
          projectPriceCents,
        }, draft, resolvedTransaction);
      }

      if (!resolvedProjectId && resolvedBudgetCategoryId) {
        return validation(
          "Cannot promote a quick draft into an inventory item with budgetCategoryId.",
          "Omit budgetCategoryId for inventory, or provide projectId and transactionId for a project item."
        );
      }

      const linkageError = checkTransactionLinkageOnCreate(resolvedProjectId, resolvedTransactionId);
      if (linkageError) {
        return validation(
          linkageError,
          "Pass transactionId alongside projectId, or promote the draft into business inventory with projectId: null."
        );
      }

      const itemRef = accountCollection(db, "items").doc();
      let copied: CopiedItemImages;
      try {
        copied = await copyAttachmentsToItemNamespace(
          draftPhotos,
          getAccountId(),
          itemRef.id,
          args.primaryImageUrl
        );
      } catch (error) {
        return validation(
          `Could not copy and verify quick-draft photos: ${error instanceof Error ? error.message : String(error)}`,
          "No Firestore records changed and the draft source photos were preserved."
        );
      }
      const itemData: Record<string, unknown> = {
        name: cleanString(args.name) ?? cleanString(draft.name) ?? cleanString(draft.sku) ?? "Untitled item",
        status: args.status ?? "purchased",
        quantity: args.quantity ?? draft.quantity ?? 1,
        images: copied.images,
        createdBy: uid,
        updatedBy: uid,
        createdAt: now,
        updatedAt: now,
      };
      if (resolvedProjectId) itemData.projectId = resolvedProjectId;
      if (resolvedTransactionId) itemData.transactionId = resolvedTransactionId;
      if (resolvedBudgetCategoryId) itemData.budgetCategoryId = resolvedBudgetCategoryId;
      if (args.spaceId) itemData.spaceId = args.spaceId;
      if (args.source) itemData.source = args.source;
      const sku = cleanString(args.sku) ?? cleanString(draft.sku);
      if (sku) itemData.sku = sku;
      const notes = args.notes !== undefined ? args.notes : draft.notes;
      if (notes) itemData.notes = notes;
      if (args.purchasePriceCents !== undefined) itemData.purchasePriceCents = args.purchasePriceCents;
      applyItemPriceFloorToCreate(itemData, args);
      if (args.marketValueCents !== undefined) itemData.marketValueCents = args.marketValueCents;
      if (resolvedTaxRate !== undefined) itemData.taxRatePct = resolvedTaxRate;

      const batch = db.batch();
      batch.set(itemRef, itemData);
      if (resolvedTransactionId) {
        batch.update(accountCollection(db, "transactions").doc(resolvedTransactionId), {
          itemIds: FieldValue.arrayUnion(itemRef.id),
          updatedAt: now,
        });
      }
      batch.update(accountCollection(db, "protoItems").doc(args.quickDraftItemId), {
        status: "converted",
        convertedItemId: itemRef.id,
        convertedAt: now,
        convertedBy: uid,
        updatedAt: now,
        updatedBy: uid,
      });
      try {
        await batch.commit();
      } catch (error) {
        await cleanupCopiedItemImages(copied);
        throw error;
      }

      return asToolResponse({
        quickDraftItemId: args.quickDraftItemId,
        merged: false,
        status: "converted",
        ...imageOperationResult({
          itemId: itemRef.id,
          images: copied.images,
          storageObjectsCopied: copied.copiedPaths.length > 0,
          storagePathsAffected: copied.copiedPaths,
        }),
      });
    })
  );
}
