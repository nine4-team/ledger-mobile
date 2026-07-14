import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { type Firestore, FieldValue } from "firebase-admin/firestore";
import { z } from "zod";
import type { Transaction, Item, AttachmentRef, LineageEdge, BudgetCategory } from "../types.js";
import { accountCollection, accountPath, queryDocs, getDoc } from "../util/query.js";
import { formatCents, formatDate } from "../util/format.js";
import { uploadToStorage, deleteFromStorage } from "../storage.js";
import { generateThumbnails, thumbnailPath } from "../util/thumbnail.js";
import { transactionMatches } from "../util/search.js";
import {
  ProjectionMode,
  ResponseLimitArg,
  transactionSummary,
  capResponse,
  asToolResponse,
  pickFields,
} from "../util/projections.js";
import { notFound, validation } from "../util/errors.js";
import { appendOrReviseAiAuditLine, tagNotesAsAi } from "../util/notes.js";
import { withTelemetry } from "../util/telemetry.js";
import { DEFAULT_INVENTORY_LABEL, isInventorySource, resolveInventoryLabel } from "../util/inventory.js";
import { resolveCategoryType } from "../util/budget.js";

const DiscountInput = z.object({
  amountCents: z.coerce.number().int().nonnegative().describe("Positive discount amount in cents, applied against the transaction subtotal."),
});

function txTypeName(tx: Transaction): string {
  return tx.type ?? "";
}

async function getBudgetCategory(db: Firestore, budgetCategoryId: string) {
  const ref = db.doc(`${accountPath()}/presets/default/budgetCategories/${budgetCategoryId}`);
  const snap = await ref.get();
  if (!snap.exists) return null;
  return { ...(snap.data() as BudgetCategory), id: snap.id };
}

function isItemizedCategory(category: BudgetCategory): boolean {
  return resolveCategoryType(category) === "itemized";
}

function isFeeCategory(category: BudgetCategory): boolean {
  return resolveCategoryType(category) === "fee";
}

/**
 * Server-side defense matching Firestore rules: per-batch inventory movement
 * transactions have frozen accounting shape fields (amountCents,
 * budgetCategoryId, type, source, projectId). Legacy canonical sales
 * (isCanonicalInventorySale == true) are exempt so cancel_transaction, etc.
 * still work on historical docs.
 *
 * Returns null if the update is allowed, or an error tool-response otherwise.
 */
const FROZEN_MOVEMENT_FIELDS = [
  "amountCents",
  "budgetCategoryId",
  "type",
  "source",
  "projectId",
] as const;

function checkInventoryMovementImmutability(
  existing: Transaction & { id: string },
  updates: Record<string, unknown>
) {
  if (existing.isCanonicalInventorySale === true) return null; // legacy exempt
  const isFrozenMovement =
    existing.type === "Sale" ||
    existing.type === "Return" ||
    (existing.type === "Purchase" &&
      (isInventorySource(existing.source, DEFAULT_INVENTORY_LABEL) ||
        (typeof existing.source === "string" && existing.source.trim().endsWith(" Inventory"))));
  if (!isFrozenMovement) return null;

  const violated = FROZEN_MOVEMENT_FIELDS.filter((f) => f in updates);
  if (violated.length === 0) return null;

  return validation(
    `Inventory movement transaction ${existing.id} has frozen accounting fields; cannot update: ${violated.join(", ")}.`,
    "Per-batch inventory movement transactions are immutable after creation. If the movement needs to be " +
      "corrected, cancel it via cancel_transaction and issue a new one via inventory movement tools. " +
      "Mutable fields include itemIds, notes, status, updatedAt."
  );
}

function formatAttachment(ref: AttachmentRef) {
  return {
    url: ref.url,
    kind: ref.kind ?? "image",
    fileName: ref.fileName ?? null,
    contentType: ref.contentType ?? null,
  };
}

function formatTransaction(tx: Transaction & { id: string }) {
  return {
    id: tx.id,
    type: txTypeName(tx),
    source: tx.source ?? "",
    amount: formatCents(tx.amountCents),
    discount: tx.discount ?? null,
    date: tx.transactionDate ?? "",
    projectId: tx.projectId ?? null,
    budgetCategoryId: tx.budgetCategoryId ?? null,
    itemCount: tx.itemIds?.length ?? 0,
    notes: tx.notes ?? "",
    isCanceled: tx.status === "canceled",
    isComplete: tx.isComplete ?? null,
    status: tx.status ?? "",
    purchasedBy: tx.purchasedBy ?? "",
    reimbursementType: tx.reimbursementType ?? "",
    receiptEmailed: tx.receiptEmailed ?? null,
    ingestionSource: tx.ingestionSource ?? null,
    ingestionStatus: tx.ingestionStatus ?? null,
    ingestionMeta: tx.ingestionMeta ?? null,
  };
}

export function registerTransactionTools(server: McpServer, db: Firestore) {
  // ── list_transactions ──────────────────────────────────────────────────────
  server.tool(
    "list_transactions",
    "List transactions by EXACT-match structured filters (projectId, type, source, budgetCategoryId, purchasedBy, isComplete, etc.). Supports pagination via offset + limit. Returns formatted amounts.\n\nPicking between this and search_transactions:\n- Exact vendor string, or other structured filters (type, isComplete, ingestionStatus) → list_transactions (here).\n- Partial vendor name, or any keyword that might appear in source or notes → search_transactions.\nDon't enumerate name variants by calling this tool in a loop.\n\nAudit workflow: isComplete: false finds transactions needing audit (app's 'Needs Review' badge); call get_transaction to see WHY (audit variance, null fields, resolved returned/sold items).",
    {
      projectId: z.string().optional().describe("Filter by project ID. Use 'inventory' for business inventory (projectId is null)."),
      budgetCategoryId: z.string().optional().describe("Filter by budget category ID"),
      type: z.string().optional().describe("Filter by transaction type (Purchase, Return, Sale, paymentToBusiness; legacy reads may include Fee, Expense, or To Inventory)."),
      purchasedBy: z.string().optional().describe("Filter by purchasedBy value (e.g. 'client-card', 'design-business', 'Client')"),
      source: z.string().optional().describe("Filter by source/vendor name"),
      isComplete: z.boolean().optional().describe("Filter by completeness. false = needs review (missing data or items don't match subtotal). true = complete."),
      reimbursementType: z.enum(["none", "owed-to-client", "owed-to-company"]).optional().describe("Filter by reimbursement type: 'none', 'owed-to-client', or 'owed-to-company'"),
      ingestionStatus: z.string().optional().describe("Filter by ingestion status: 'needs_review', 'auto_matched', 'confirmed'. Used to find email-ingested transactions pending triage."),
      hasItems: z.boolean().optional().describe("Filter by item linkage: true = has itemIds, false = no items linked"),
      limit: z.coerce.number().default(50).describe("Max results"),
      offset: z.coerce.number().default(0).describe("Number of results to skip (for pagination)"),
      mode: ProjectionMode.describe("Response shape: 'summary' (default, compact) or 'full' (raw document)."),
      fields: z.array(z.string()).optional().describe("Optional explicit field list. Overrides mode."),
      responseLimit: ResponseLimitArg,
    },
    async ({ projectId, budgetCategoryId, type, purchasedBy, source, isComplete, reimbursementType, ingestionStatus, hasItems, limit, offset, mode, fields, responseLimit }) => {
      let query: FirebaseFirestore.Query = accountCollection(db, "transactions");

      if (projectId === "inventory") {
        query = query.where("projectId", "==", null);
      } else if (projectId) {
        query = query.where("projectId", "==", projectId);
      }

      if (budgetCategoryId) {
        query = query.where("budgetCategoryId", "==", budgetCategoryId);
      }

      if (type) {
        query = query.where("type", "==", type);
      }

      if (purchasedBy) {
        query = query.where("purchasedBy", "==", purchasedBy);
      }

      if (source) {
        query = query.where("source", "==", source);
      }

      if (isComplete !== undefined) {
        query = query.where("isComplete", "==", isComplete);
      }

      if (reimbursementType) {
        query = query.where("reimbursementType", "==", reimbursementType);
      }

      if (ingestionStatus) {
        query = query.where("ingestionStatus", "==", ingestionStatus);
      }

      // hasItems requires client-side filtering (Firestore can't query array length)
      let clientFilter: ((tx: Transaction & { id: string }) => boolean) | null = null;
      if (hasItems === true) {
        clientFilter = (tx) => !!tx.itemIds?.length;
      } else if (hasItems === false) {
        clientFilter = (tx) => !tx.itemIds?.length;
      }

      if (clientFilter) {
        query = query.limit(500);
      } else {
        query = query.offset(offset).limit(limit);
      }
      let transactions = await queryDocs<Transaction>(query);
      if (clientFilter) transactions = transactions.filter(clientFilter).slice(offset, offset + limit);

      const projected = transactions.map((tx) => {
        if (fields && fields.length) return pickFields(tx as unknown as Record<string, unknown>, fields);
        return mode === "full" ? (tx as unknown as Record<string, unknown>) : (transactionSummary(tx) as unknown as Record<string, unknown>);
      });
      const capped = capResponse(projected, { limitBytes: responseLimit });
      return asToolResponse(capped);
    }
  );

  // ── get_transaction ────────────────────────────────────────────────────────
  server.tool(
    "get_transaction",
    "Get a single transaction with all linked, returned, and sold items resolved. Returns three item arrays: items (currently linked via itemIds), returnedItems (items that LEFT this transaction via return, resolved from lineage edges — still count toward audit total), soldItems (items that LEFT via sale, resolved from lineage edges — still count toward audit total). Audit object: resolvedSubtotalCents, itemsSumCents (linked + returned + sold), linkedItemsSumCents, returnedItemsSumCents/returnedItemsCount, soldItemsSumCents/soldItemsCount, varianceCents, variancePercent. Diagnostic guidance: if returnedItemsCount > 0 but returnedItems is empty, items may have been deleted or lineage edges are orphaned. isComplete == false means items don't match pre-tax subtotal within ±1% (app shows 'Needs Review' badge). Use get_item_history for full movement history of a specific item. Attachments: receiptImages[].url and otherImages[].url are public HTTPS download URLs (Firebase Storage token URLs, alt=media&token=...) — fetch directly with curl/WebFetch, no auth required. Do NOT use gsutil or gcloud for these.",
    { transactionId: z.string().describe("Transaction document ID") },
    async ({ transactionId }) => {
      const tx = await getDoc<Transaction>(db, "transactions", transactionId);
      if (!tx) {
        return { content: [{ type: "text", text: `Transaction ${transactionId} not found.` }], isError: true };
      }

      // Resolve linked items
      let items: (Item & { id: string })[] = [];
      if (tx.itemIds?.length) {
        const itemPromises = tx.itemIds.map((itemId) =>
          getDoc<Item>(db, "items", itemId)
        );
        const results = await Promise.all(itemPromises);
        items = results.filter((i): i is Item & { id: string } => i !== null);
      }

      // Resolve returned/sold items from lineage edges (only when audit says they exist)
      let returnedItems: (Item & { id: string })[] = [];
      let soldItems: (Item & { id: string })[] = [];

      const hasLineage = (tx.audit?.returnedItemsCount ?? 0) > 0 || (tx.audit?.soldItemsCount ?? 0) > 0;

      if (hasLineage) {
        const edgesCol = accountCollection(db, "lineageEdges");
        const [fromEdges, toEdges] = await Promise.all([
          queryDocs<LineageEdge>(edgesCol.where("fromTransactionId", "==", transactionId)),
          queryDocs<LineageEdge>(edgesCol.where("toTransactionId", "==", transactionId)),
        ]);

        const currentItemIds = new Set(tx.itemIds ?? []);
        const latestByItem = new Map<string, LineageEdge & { id: string }>();

        for (const edge of [...fromEdges, ...toEdges]) {
          if (edge.fromTransactionId !== transactionId) continue;
          if (edge.movementKind !== "returned" && edge.movementKind !== "sold" && edge.movementKind !== "soldToInventory") continue;
          if (!edge.itemId || currentItemIds.has(edge.itemId)) continue;

          const existing = latestByItem.get(edge.itemId);
          if (!existing || (edge.createdAt?.toMillis() ?? 0) > (existing.createdAt?.toMillis() ?? 0)) {
            latestByItem.set(edge.itemId, edge);
          }
        }

        const returnedIds = [...latestByItem.entries()].filter(([, e]) => e.movementKind === "returned").map(([id]) => id);
        const soldIds = [...latestByItem.entries()]
          .filter(([, e]) => e.movementKind === "sold" || e.movementKind === "soldToInventory")
          .map(([id]) => id);

        if (returnedIds.length) {
          const results = await Promise.all(returnedIds.map((id) => getDoc<Item>(db, "items", id)));
          returnedItems = results.filter((i): i is Item & { id: string } => i !== null);
        }
        if (soldIds.length) {
          const results = await Promise.all(soldIds.map((id) => getDoc<Item>(db, "items", id)));
          soldItems = results.filter((i): i is Item & { id: string } => i !== null);
        }
      }

      const formatItem = (i: Item & { id: string }) => ({
        id: i.id,
        name: i.name ?? i.description ?? "",
        status: i.status ?? "",
        purchasePrice: formatCents(i.purchasePriceCents),
        projectPrice: formatCents(i.projectPriceCents),
        taxRatePct: i.taxRatePct ?? null,
      });

      const result = {
        ...formatTransaction(tx),
        subtotalCents: tx.subtotalCents,
        taxRatePct: tx.taxRatePct,
        purchasedBy: tx.purchasedBy ?? "",
        reimbursementType: tx.reimbursementType ?? "",
        paymentMethod: tx.paymentMethod ?? "",
        audit: tx.audit ?? null,
        receiptImages: (tx.receiptImages ?? []).map(formatAttachment),
        otherImages: (tx.otherImages ?? []).map(formatAttachment),
        items: items.map(formatItem),
        returnedItems: returnedItems.map(formatItem),
        soldItems: soldItems.map(formatItem),
      };

      return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
    }
  );

  // ── search_transactions ────────────────────────────────────────────────────
  server.tool(
    "search_transactions",
    "Substring filter across `source`, `type`, `notes`, `purchasedBy`, and `amount`. Case-insensitive.\n\nPicking between this and list_transactions:\n- Partial vendor name, or any keyword that might appear in source or notes → search_transactions (here).\n- Exact vendor string, or other structured filters (type, isComplete, ingestionStatus) → list_transactions.\nA single substring call beats looping list_transactions over a list of name variants.",
    {
      query: z.string().describe("Search term"),
      projectId: z.string().optional().describe("Scope search to a project"),
      limit: z.coerce.number().default(25).describe("Max results"),
      offset: z.coerce.number().default(0).describe("Number of results to skip (for pagination)"),
    },
    async ({ query: searchTerm, projectId, limit, offset }) => {
      let q: FirebaseFirestore.Query = accountCollection(db, "transactions");
      if (projectId) q = q.where("projectId", "==", projectId);

      const all = await queryDocs<Transaction>(q);
      const matched = all
        .filter((tx) => transactionMatches(tx, searchTerm))
        .slice(offset, offset + limit);

      return { content: [{ type: "text", text: JSON.stringify(matched.map(formatTransaction), null, 2) }] };
    }
  );

  // ── create_transaction ─────────────────────────────────────────────────────
  server.tool(
    "create_transaction",
    "[mutating] Create a new transaction. Starts with isComplete: false — auto-updates when completeness criteria are met via Cloud Function.\n\nNOTES CONVENTION: `notes` is the optional user-facing description of the transaction (what it is, what it covers). Plain prose. The createdAt/createdBy audit trail is separate — don't try to record 'what you did' in notes; record WHAT the transaction is.",
    {
      projectId: z.string().optional().describe("Project ID (omit for business inventory). To match a receipt to a project, check the project's notes field — it may contain payment method details (card last 4), billing address, or other identifiers that help determine which project a purchase belongs to."),
      budgetCategoryId: z.string().describe("Budget category ID"),
      amountCents: z.coerce.number().describe("Amount in cents (positive)"),
      type: z.string().default("Purchase").describe("Transaction type for normal writes: Purchase, Return, or paymentToBusiness. Purchase covers goods/services; itemization is owned by budget category. paymentToBusiness records a client payment and requires a fee category. Sale-to-Inventory transactions must be created via sell_items_from_project_to_inventory. Return transactions back to inventory are created automatically by return_items with returnTo: 'inventory'. Fee, Expense, and To Inventory are legacy read-only values."),
      source: z.string().optional().describe("Vendor/source name for purchases/returns. Omit for paymentToBusiness client payments."),
      transactionDate: z.string().optional().describe("Date string (e.g. '2024-03-15')"),
      notes: z.string().optional().describe("Optional prose describing what the transaction is (e.g. 'Home Depot receipt — drywall + paint for guest bath'). Free-form, no required format."),
      itemIds: z.array(z.string()).optional().describe("Item IDs to link to this transaction"),
      subtotalCents: z.coerce.number().optional().describe("Pre-tax subtotal in cents"),
      taxRatePct: z.coerce.number().optional().describe("Tax rate as a percentage (0-100, e.g. 8.25)"),
      discount: DiscountInput.optional().describe("Transaction-level discount object. amountCents is the exact discount applied to the subtotal, stored as a positive cents value."),
      paymentMethod: z.string().optional().describe("Payment method (e.g. 'Credit Card', 'Cash', 'Check')"),
      purchasedBy: z.string().optional().describe("Who made the purchase"),
      reimbursementType: z.enum(["none", "owed-to-client", "owed-to-company"]).optional().describe("Reimbursement type: 'none', 'owed-to-client', or 'owed-to-company'"),
      receiptEmailed: z.boolean().optional().describe("Whether a receipt was emailed"),
      status: z.enum(["canceled"]).optional().describe("Transaction status. Omit for active transactions; only 'canceled' is canonical."),
      ingestionSource: z.string().optional().describe("Origin of transaction: 'email' (auto-ingested) or 'manual'. Omit for manually created transactions."),
      ingestionStatus: z.string().optional().describe("Ingestion lifecycle: 'needs_review' (unmatched), 'auto_matched' (matched but unconfirmed), 'confirmed'. Only set for ingested transactions."),
      ingestionMeta: z.object({
        emailId: z.string().optional(),
        subject: z.string().optional(),
        inbox: z.string().optional(),
        matchConfidence: z.number().optional(),
        matchReason: z.string().optional(),
        orderNumber: z.string().optional(),
        linkedIngestionIds: z.array(z.string()).optional(),
      }).optional().describe("Email ingestion metadata: email ID, subject, inbox, match confidence/reason, order number, linked transaction IDs for split shipments."),
    },
    async ({ projectId, budgetCategoryId, amountCents, type: txType, source, transactionDate, notes, itemIds, subtotalCents, taxRatePct, discount, paymentMethod, purchasedBy, reimbursementType, receiptEmailed, status, ingestionSource, ingestionStatus, ingestionMeta }) => {
      const normalizedTxType = txType === "PaymentToBusiness" ? "paymentToBusiness" : txType;
      if (txType === "Sale") {
        return validation(
          "Cannot create Sale-to-Inventory transactions directly — use sell_items_from_project_to_inventory instead.",
          "Sale-to-Inventory transactions require lineage edges and item scope changes that create_transaction cannot perform."
        );
      }
      if (["Fee", "fee", "Expense", "expense", "To Inventory", "to inventory"].includes(txType)) {
        return validation(
          `${txType} is not a normal create_transaction write type.`,
          "Use Purchase/Return for project cost transactions or paymentToBusiness for client payments. Legacy Fee, Expense, and To Inventory values are read-only."
        );
      }
      const category = await getBudgetCategory(db, budgetCategoryId);
      if (!category) return notFound("Budget category", budgetCategoryId);
      const categoryIsItemized = isItemizedCategory(category);
      const categoryIsFee = isFeeCategory(category);
      if (normalizedTxType === "paymentToBusiness") {
        if (!categoryIsFee) {
          return validation(
            "Client payments require a fee/revenue budget category.",
            "Choose a categoryType == fee category such as Design Fee."
          );
        }
        if (
          source?.trim() ||
          itemIds?.length ||
          subtotalCents !== undefined ||
          taxRatePct !== undefined ||
          discount !== undefined ||
          purchasedBy?.trim() ||
          (reimbursementType !== undefined && reimbursementType !== "none")
        ) {
          return validation(
            "Client payments cannot include vendor/source, items, tax/subtotal, discount, purchaser, or reimbursement fields.",
            "Use amountCents, projectId, budgetCategoryId, transactionDate, paymentMethod, receipt fields, and notes for paymentToBusiness rows."
          );
        }
      } else if (categoryIsFee) {
        return validation(
          "create_transaction cannot write fee-category transactions.",
          "Use paymentToBusiness for client payments, or invoice/manual charge flows for payment demand before money moves."
        );
      }
      if (normalizedTxType === "Return" && !categoryIsItemized) {
        return validation(
          "Return transactions require an itemized budget category.",
          "For service/cost adjustments, use invoice credit lines or an approved non-transaction adjustment flow."
        );
      }
      if (!categoryIsItemized && (itemIds?.length || subtotalCents !== undefined || taxRatePct !== undefined)) {
        return validation(
          "Item IDs and tax/subtotal fields require an itemized budget category.",
          "Use a purchase/return item category for itemized receipts, or omit item/tax fields for non-itemized service purchases."
        );
      }

      const inventoryLabel = await resolveInventoryLabel(db);
      if (normalizedTxType === "Purchase" && projectId && isInventorySource(source, inventoryLabel)) {
        return validation(
          "Project purchases with inventory as the source must route through inventory and create a Purchase-from-inventory movement.",
          "Use create_transaction_with_items when creating new items, or sell_items_from_inventory_to_project for existing inventory items. create_transaction alone cannot create the required item updates and lineage edge."
        );
      }

      const data: Record<string, unknown> = {
        budgetCategoryId,
        amountCents,
        type: normalizedTxType,
        isComplete: false,
        createdAt: new Date(),
        updatedAt: new Date(),
      };
      if (status) data.status = status;
      if (projectId) data.projectId = projectId;
      if (source && normalizedTxType !== "paymentToBusiness") data.source = source;
      if (transactionDate) data.transactionDate = transactionDate;
      if (notes) data.notes = tagNotesAsAi(notes);
      if (itemIds?.length) data.itemIds = itemIds;
      if (subtotalCents !== undefined) data.subtotalCents = subtotalCents;
      if (taxRatePct !== undefined) data.taxRatePct = taxRatePct;
      if (discount !== undefined) data.discount = discount;
      if (paymentMethod) data.paymentMethod = paymentMethod;
      if (purchasedBy) data.purchasedBy = purchasedBy;
      if (reimbursementType && reimbursementType !== "none") data.reimbursementType = reimbursementType;
      if (receiptEmailed !== undefined) data.receiptEmailed = receiptEmailed;
      if (ingestionSource) data.ingestionSource = ingestionSource;
      if (ingestionStatus) data.ingestionStatus = ingestionStatus;
      if (ingestionMeta) data.ingestionMeta = ingestionMeta;

      const ref = await accountCollection(db, "transactions").add(data);

      // Maintain bidirectional link: set transactionId on each linked item
      if (itemIds?.length) {
        const batch = db.batch();
        for (const itemId of itemIds) {
          batch.update(accountCollection(db, "items").doc(itemId), {
            transactionId: ref.id,
            updatedAt: new Date(),
          });
        }
        await batch.commit();
      }

      return { content: [{ type: "text", text: `Created transaction ${ref.id}` }] };
    }
  );

  // ── update_transaction ─────────────────────────────────────────────────────
  server.tool(
    "update_transaction",
    "[mutating] Update transaction fields. isComplete recomputes automatically via Cloud Function.\n\nNOTES CONVENTION: The `notes` field on a transaction is a single string shared between user-authored prose (at the top) and AI-authored audit lines (at the bottom, separated by a blank line). Two ways to edit it:\n  • `notes` — REPLACES the entire notes field. Use only when the user explicitly asks you to rewrite the notes or when consolidating your own prior stale audit lines. Preserve user prose verbatim when you do this.\n  • `aiAuditAppend` — appends a one-line AI audit entry to the bottom of existing notes, tagged '[AI M/D/YYYY] …'. If the last line is already an AI line from today, it's REPLACED (no stacking of stale same-day edits). Use this to record what you did, not to describe what the transaction is.\nMost field edits don't need either — createdAt/updatedAt already record the audit trail. Touch notes only when the content of the notes field itself should change.",
    {
      transactionId: z.string().describe("Transaction document ID"),
      amountCents: z.coerce.number().optional().describe("Total amount in cents (including tax)"),
      subtotalCents: z.coerce.number().optional().describe("Pre-tax subtotal in cents. Should be <= amountCents. When set with taxRatePct, the system can infer tax amount as amountCents - subtotalCents"),
      taxRatePct: z.coerce.number().optional().describe("Tax rate as a percentage (0-100, e.g. 8.25). When set with amountCents, the system infers subtotal as amountCents / (1 + taxRatePct / 100)"),
      discount: DiscountInput.nullable().optional().describe("Transaction-level discount object. Pass null to remove it. amountCents is the exact discount applied to the subtotal, stored as a positive cents value."),
      type: z.string().optional().describe("Transaction type: Purchase or Return for normal edits. Cannot update to/from Sale or paymentToBusiness here. Fee, Expense, and To Inventory are legacy read-only values."),
      status: z.string().optional().describe("Transaction status (e.g. 'returned')"),
      source: z.string().optional().describe("Vendor/source name"),
      notes: z.string().optional().describe("If provided, REPLACES the entire notes field. Pass the full new content. Use `aiAuditAppend` instead if you just want to add a one-line audit entry."),
      aiAuditAppend: z.string().optional().describe("A short one-line audit entry describing what you (AI) just did. Server appends it to the bottom of existing notes with an '[AI M/D/YYYY]' prefix and blank-line separator from user prose. If the last line is already an AI line from today, it is REPLACED rather than stacked. Mutually compatible with `notes` — if both are passed, `notes` is applied first, then `aiAuditAppend`."),
      budgetCategoryId: z.string().optional().describe("Budget category ID"),
      transactionDate: z.string().optional().describe("Date string (e.g. '2024-03-15')"),
      itemIds: z.array(z.string()).optional().describe("Item IDs linked to this transaction (replaces existing list)"),
      projectId: z.string().optional().describe("Project ID — set to reassign transaction to a different project"),
      purchasedBy: z.string().optional().describe("Who made the purchase"),
      reimbursementType: z.enum(["none", "owed-to-client", "owed-to-company"]).optional().describe("Reimbursement type: 'none', 'owed-to-client', or 'owed-to-company'"),
      receiptEmailed: z.boolean().optional().describe("Whether a receipt was emailed"),
      paymentMethod: z.string().optional().describe("Payment method (e.g. 'Credit Card', 'Cash', 'Check')"),
      ingestionStatus: z.string().optional().describe("Update ingestion status: 'confirmed' (user verified), 'needs_review', 'auto_matched'"),
    },
    async ({ transactionId, ...fields }) => {
      const existing = await getDoc<Transaction>(db, "transactions", transactionId);
      if (!existing) return notFound("Transaction", transactionId);

      // Merge notes: `notes` replaces outright; `aiAuditAppend` appends/revises
      // a tagged AI line below whatever notes ends up being after replacement.
      let mergedNotes = existing.notes;
      if (fields.notes !== undefined) mergedNotes = fields.notes;
      if (fields.aiAuditAppend !== undefined) {
        mergedNotes = appendOrReviseAiAuditLine(mergedNotes, fields.aiAuditAppend);
      }

      if (fields.type && ["Sale", "PaymentToBusiness", "paymentToBusiness", "Fee", "fee", "Expense", "expense", "To Inventory", "to inventory"].includes(fields.type)) {
        return validation(
          `${fields.type} cannot be set through update_transaction.`,
          "Use inventory operation tools for Sale, create_transaction/Client Payment for paymentToBusiness, and do not write legacy Fee/Expense/To Inventory values."
        );
      }

      const updates: Record<string, unknown> = { updatedAt: new Date() };
      if (fields.notes !== undefined || fields.aiAuditAppend !== undefined) {
        updates.notes = mergedNotes;
      }
      for (const [key, value] of Object.entries(fields)) {
        if (key === "notes" || key === "aiAuditAppend") continue;
        if (value !== undefined) updates[key] = value;
      }

      // Server-side guard matching Firestore rules — reject writes to frozen
      // shape fields on new per-batch inventory movements. Legacy canonical
      // sales are exempt.
      const immutabilityError = checkInventoryMovementImmutability(existing, updates);
      if (immutabilityError) return immutabilityError;

      await accountCollection(db, "transactions").doc(transactionId).update(updates);
      return { content: [{ type: "text", text: `Updated transaction ${transactionId}` }] };
    }
  );

  // ── bulk_update_transactions ──────────────────────────────────────────────
  server.tool(
    "bulk_update_transactions",
    "Update a field across multiple transactions matching a filter. Uses Firestore batched writes (max 500 per batch). Returns count of updated documents.",
    {
      filter: z.object({
        projectId: z.string().optional().describe("Filter by project ID. Use 'inventory' for null projectId."),
        purchasedBy: z.string().optional().describe("Match transactions with this purchasedBy value"),
        source: z.string().optional().describe("Match transactions with this source"),
        isComplete: z.boolean().optional().describe("Match transactions by completeness. false = needs review."),
        type: z.string().optional().describe("Match transactions with this type"),
      }).describe("Filter criteria — at least one field required"),
      update: z.object({
        purchasedBy: z.string().optional(),
        source: z.string().optional(),
        status: z.string().optional(),
        reimbursementType: z.enum(["none", "owed-to-client", "owed-to-company"]).optional(),
        paymentMethod: z.string().optional(),
        receiptEmailed: z.boolean().optional(),
      }).describe("Fields to set on all matched transactions"),
    },
    async ({ filter, update }) => {
      // Build query from filter
      let query: FirebaseFirestore.Query = accountCollection(db, "transactions");

      if (filter.projectId === "inventory") {
        query = query.where("projectId", "==", null);
      } else if (filter.projectId) {
        query = query.where("projectId", "==", filter.projectId);
      }
      if (filter.purchasedBy) query = query.where("purchasedBy", "==", filter.purchasedBy);
      if (filter.source) query = query.where("source", "==", filter.source);
      if (filter.isComplete !== undefined) query = query.where("isComplete", "==", filter.isComplete);
      if (filter.type) query = query.where("type", "==", filter.type);

      const snapshot = await query.get();
      if (snapshot.empty) {
        return { content: [{ type: "text", text: "No transactions matched the filter. 0 updated." }] };
      }

      // Build update payload
      const updates: Record<string, unknown> = { updatedAt: new Date() };
      for (const [key, value] of Object.entries(update)) {
        if (value !== undefined) updates[key] = value;
      }

      // Inventory movement immutability preflight: reject the whole call if any
      // matched doc is frozen and the update touches a shape field.
      const violations: string[] = [];
      for (const doc of snapshot.docs) {
        const data = doc.data() as Transaction;
        const existing = { ...data, id: doc.id };
        const err = checkInventoryMovementImmutability(existing, updates);
        if (err) violations.push(doc.id);
      }
      if (violations.length > 0) {
        return validation(
          `Bulk update would touch frozen accounting fields on ${violations.length} inventory movement transaction(s): ${violations.slice(0, 3).join(", ")}${violations.length > 3 ? "…" : ""}`,
          "Per-batch inventory movement transactions are immutable after creation. Narrow the filter or drop the frozen field from the update."
        );
      }

      // Batch writes (Firestore max 500 per batch)
      let processed = 0;
      let batch = db.batch();
      let batchCount = 0;

      for (const doc of snapshot.docs) {
        batch.update(doc.ref, updates);
        batchCount++;
        if (batchCount === 500) {
          await batch.commit();
          processed += batchCount;
          batch = db.batch();
          batchCount = 0;
        }
      }
      if (batchCount > 0) {
        await batch.commit();
        processed += batchCount;
      }

      return { content: [{ type: "text", text: `Updated ${processed} transactions.` }] };
    }
  );

  // ── cancel_transaction ─────────────────────────────────────────────────────
  server.tool(
    "cancel_transaction",
    "Mark a transaction as canceled. Canceled transactions contribute $0 to budget calculations. " +
      "Per-batch inventory movement transactions cancel cleanly with just a status flip — no item shuffling, no " +
      "amount recomputation. Legacy canonical sales also cancel via status.",
    { transactionId: z.string().describe("Transaction document ID") },
    async ({ transactionId }) => {
      await accountCollection(db, "transactions").doc(transactionId).update({
        status: "canceled",
        updatedAt: new Date(),
      });
      return { content: [{ type: "text", text: `Canceled transaction ${transactionId}` }] };
    }
  );

  // ── attach_transaction_file ────────────────────────────────────────────────
  server.tool(
    "attach_transaction_file",
    "Attach an image or PDF to a transaction. Uploads to Firebase Storage and appends an AttachmentRef to the transaction's receipt or other images array. For images, generates sm (300px) and md (800px) thumbnails. Returned URLs are public HTTPS download URLs (Firebase Storage token URLs) — fetch directly with curl/WebFetch later, no auth required.",
    {
      transactionId: z.string().describe("Transaction document ID"),
      fileData: z.string().optional().describe("Base64-encoded file content (provide this OR fileUrl, not both)"),
      fileUrl: z.string().optional().describe("URL to fetch the file from (provide this OR fileData, not both)"),
      fileName: z.string().describe("File name (e.g. 'order-summary.pdf', 'receipt.jpg')"),
      contentType: z.string().optional().describe("MIME type (e.g. 'application/pdf', 'image/jpeg', 'image/png'). Inferred from response headers when using fileUrl."),
      category: z.enum(["receipt", "other"]).default("receipt").describe("Target array: 'receipt' → receiptImages, 'other' → otherImages"),
    },
    async ({ transactionId, fileData, fileUrl, fileName, contentType, category }) => {
      const fieldName = category === "receipt" ? "receiptImages" : "otherImages";

      // 1. Validate transaction exists before uploading anything
      const tx = await getDoc<Transaction>(db, "transactions", transactionId);
      if (!tx) {
        return { content: [{ type: "text", text: `Transaction ${transactionId} not found.` }], isError: true };
      }

      // 2. Resolve file data from fileData (base64) or fileUrl
      if (!fileData && !fileUrl) {
        return { content: [{ type: "text", text: "Provide either fileData (base64) or fileUrl, not neither." }], isError: true };
      }
      if (fileData && fileUrl) {
        return { content: [{ type: "text", text: "Provide either fileData (base64) or fileUrl, not both." }], isError: true };
      }

      let data: Buffer;
      let resolvedContentType = contentType;

      if (fileUrl) {
        const res = await fetch(fileUrl);
        if (!res.ok) {
          return { content: [{ type: "text", text: `Failed to fetch file from URL: ${res.status} ${res.statusText}` }], isError: true };
        }
        data = Buffer.from(await res.arrayBuffer());
        if (!resolvedContentType) {
          resolvedContentType = res.headers.get("content-type")?.split(";")[0] ?? "application/octet-stream";
        }
      } else {
        data = Buffer.from(fileData!, "base64");
      }

      if (!resolvedContentType) {
        resolvedContentType = "application/octet-stream";
      }

      const sizeMB = data.length / (1024 * 1024);
      if (sizeMB > 10) {
        return { content: [{ type: "text", text: `File too large (${sizeMB.toFixed(1)}MB). Maximum is 10MB.` }], isError: true };
      }

      // 3. Determine attachment kind
      const kind = resolvedContentType.startsWith("image/")
        ? "image"
        : resolvedContentType === "application/pdf"
          ? "pdf"
          : "file";

      // 4. Upload primary file
      //    Path mirrors iOS: accounts/{accountId}/transactions/{transactionId}/{fileName}
      const storagePath = `${accountPath()}/transactions/${transactionId}/${fileName}`;
      const url = await uploadToStorage(storagePath, data, resolvedContentType);

      // 5. Generate and upload thumbnails for images
      let thumbnailUrlSm: string | undefined;
      let thumbnailUrlMd: string | undefined;

      const thumbs = await generateThumbnails(data, resolvedContentType);
      if (thumbs.sm) {
        thumbnailUrlSm = await uploadToStorage(
          thumbnailPath(storagePath, "sm"), thumbs.sm, "image/jpeg"
        );
      }
      if (thumbs.md) {
        thumbnailUrlMd = await uploadToStorage(
          thumbnailPath(storagePath, "md"), thumbs.md, "image/jpeg"
        );
      }

      // 6. Build AttachmentRef entry (matches iOS MediaUploadQueue.writeBackURL dict format)
      const existingArray = (tx as unknown as Record<string, unknown>)[fieldName] as AttachmentRef[] | undefined;
      const isPrimary = !existingArray?.length;

      const entry: Record<string, unknown> = {
        url,
        kind,
        isPrimary,
      };
      if (fileName) entry.fileName = fileName;
      if (resolvedContentType) entry.contentType = resolvedContentType;
      if (thumbnailUrlSm) entry.thumbnailUrlSm = thumbnailUrlSm;
      if (thumbnailUrlMd) entry.thumbnailUrlMd = thumbnailUrlMd;

      // 7. Append to Firestore array
      try {
        await accountCollection(db, "transactions").doc(transactionId).update({
          [fieldName]: FieldValue.arrayUnion(entry),
          updatedAt: new Date(),
        });
      } catch (err) {
        // Clean up uploaded files on Firestore failure
        await deleteFromStorage(url).catch(() => {});
        if (thumbnailUrlSm) await deleteFromStorage(thumbnailUrlSm).catch(() => {});
        if (thumbnailUrlMd) await deleteFromStorage(thumbnailUrlMd).catch(() => {});
        throw err;
      }

      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            message: `Attached ${fileName} to transaction ${transactionId} (${fieldName})`,
            url,
            kind,
            thumbnailUrlSm: thumbnailUrlSm ?? null,
            thumbnailUrlMd: thumbnailUrlMd ?? null,
          }, null, 2),
        }],
      };
    }
  );

  // ── detach_transaction_file ──────────────────────────────────────────────
  server.tool(
    "detach_transaction_file",
    "Remove an attachment (receipt or other image) from a transaction. Deletes the file and its thumbnails from Firebase Storage and removes the AttachmentRef from the Firestore array.",
    {
      transactionId: z.string().describe("Transaction document ID"),
      url: z.string().describe("The attachment URL to remove (matches the 'url' field in the AttachmentRef)"),
      category: z.enum(["receipt", "other"]).default("receipt").describe("Which array: 'receipt' → receiptImages, 'other' → otherImages"),
    },
    async ({ transactionId, url, category }) => {
      const fieldName = category === "receipt" ? "receiptImages" : "otherImages";

      const tx = await getDoc<Transaction>(db, "transactions", transactionId);
      if (!tx) {
        return { content: [{ type: "text", text: `Transaction ${transactionId} not found.` }], isError: true };
      }

      const attachments = (tx as unknown as Record<string, unknown>)[fieldName] as AttachmentRef[] | undefined;
      const entry = attachments?.find((a) => a.url === url);
      if (!entry) {
        return { content: [{ type: "text", text: `No attachment with that URL found in ${fieldName}.` }], isError: true };
      }

      // Remove from Firestore array
      const remaining = attachments!.filter((a) => a.url !== url);
      await accountCollection(db, "transactions").doc(transactionId).update({
        [fieldName]: remaining,
        updatedAt: new Date(),
      });

      // Delete files from Storage (best-effort — don't fail if storage delete fails)
      const deleted: string[] = [];
      try { await deleteFromStorage(url); deleted.push("primary"); } catch { /* ignore */ }
      if (entry.thumbnailUrlSm) {
        try { await deleteFromStorage(entry.thumbnailUrlSm); deleted.push("thumbnail-sm"); } catch { /* ignore */ }
      }
      if (entry.thumbnailUrlMd) {
        try { await deleteFromStorage(entry.thumbnailUrlMd); deleted.push("thumbnail-md"); } catch { /* ignore */ }
      }

      return {
        content: [{
          type: "text",
          text: `Removed attachment from ${fieldName} on transaction ${transactionId}. Deleted from storage: ${deleted.join(", ") || "none (files may have already been removed)"}`,
        }],
      };
    }
  );
}
