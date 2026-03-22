import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { type Firestore, FieldValue } from "firebase-admin/firestore";
import { z } from "zod";
import type { Transaction, Item, AttachmentRef } from "../types.js";
import { accountCollection, accountPath, queryDocs, getDoc } from "../util/query.js";
import { formatCents, formatDate } from "../util/format.js";
import { uploadToStorage, deleteFromStorage } from "../storage.js";
import { generateThumbnails, thumbnailPath } from "../util/thumbnail.js";
import { transactionMatches } from "../util/search.js";

function txTypeName(tx: Transaction): string {
  return tx.type ?? tx.transactionType ?? "";
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
    date: tx.transactionDate ?? "",
    projectId: tx.projectId ?? null,
    budgetCategoryId: tx.budgetCategoryId ?? null,
    itemCount: tx.itemIds?.length ?? 0,
    notes: tx.notes ?? "",
    isCanceled: tx.isCanceled ?? false,
    isComplete: tx.isComplete ?? null,
    status: tx.status ?? "",
    purchasedBy: tx.purchasedBy ?? "",
    reimbursementType: tx.reimbursementType ?? "",
    receiptEmailed: tx.receiptEmailed ?? null,
  };
}

export function registerTransactionTools(server: McpServer, db: Firestore) {
  // ── list_transactions ──────────────────────────────────────────────────────
  server.tool(
    "list_transactions",
    "List transactions with optional filters. Supports pagination via offset + limit. Returns formatted amounts. Use isComplete: false to find transactions needing audit (app shows 'Needs Review' badge when isComplete is false). To understand WHY a transaction is incomplete, call get_transaction — it returns the audit object (variance numbers) and shows which fields are null (subtotalCents, taxRatePct, items).",
    {
      projectId: z.string().optional().describe("Filter by project ID. Use 'inventory' for business inventory (projectId is null)."),
      budgetCategoryId: z.string().optional().describe("Filter by budget category ID"),
      type: z.string().optional().describe("Filter by transaction type (Purchase, Return, Sale, To Inventory)"),
      purchasedBy: z.string().optional().describe("Filter by purchasedBy value (e.g. 'client-card', 'design-business', 'Client')"),
      source: z.string().optional().describe("Filter by source/vendor name"),
      isComplete: z.boolean().optional().describe("Filter by completeness. false = needs review (missing data or items don't match subtotal). true = complete."),
      reimbursementType: z.string().optional().describe("Filter by reimbursement type"),
      hasItems: z.boolean().optional().describe("Filter by item linkage: true = has itemIds, false = no items linked"),
      limit: z.number().default(50).describe("Max results"),
      offset: z.number().default(0).describe("Number of results to skip (for pagination)"),
    },
    async ({ projectId, budgetCategoryId, type, purchasedBy, source, isComplete, reimbursementType, hasItems, limit, offset }) => {
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
      const rows = transactions.map(formatTransaction);

      return { content: [{ type: "text", text: JSON.stringify(rows, null, 2) }] };
    }
  );

  // ── get_transaction ────────────────────────────────────────────────────────
  server.tool(
    "get_transaction",
    "Get a single transaction with linked items. Returns isComplete (auto-computed by Cloud Function: true when items sum matches pre-tax subtotal within ±1% for itemized categories, always true for non-itemized/canonical). For itemized categories, returns an 'audit' object with resolvedSubtotalCents, itemsSumCents, varianceCents, variancePercent. The app shows a 'Needs Review' badge when isComplete is false — if a user says a transaction 'needs review', that means isComplete is false. Check null fields directly to identify missing data.",
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
        items: items.map((i) => ({
          id: i.id,
          name: i.name ?? i.description ?? "",
          status: i.status ?? "",
          purchasePrice: formatCents(i.purchasePriceCents),
        })),
      };

      return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
    }
  );

  // ── search_transactions ────────────────────────────────────────────────────
  server.tool(
    "search_transactions",
    "Search transactions by source, type, notes, purchasedBy, or amount. Case-insensitive client-side filter. Supports pagination via offset + limit.",
    {
      query: z.string().describe("Search term"),
      projectId: z.string().optional().describe("Scope search to a project"),
      limit: z.number().default(25).describe("Max results"),
      offset: z.number().default(0).describe("Number of results to skip (for pagination)"),
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
    "Create a new transaction. Starts with isComplete: false — auto-updates when completeness criteria are met via Cloud Function.",
    {
      projectId: z.string().optional().describe("Project ID (omit for business inventory)"),
      budgetCategoryId: z.string().describe("Budget category ID"),
      amountCents: z.number().describe("Amount in cents (positive)"),
      type: z.string().default("Purchase").describe("Transaction type: Purchase, Return, Sale, To Inventory"),
      source: z.string().optional().describe("Vendor/source name"),
      transactionDate: z.string().optional().describe("Date string (e.g. '2024-03-15')"),
      notes: z.string().optional().describe("Notes"),
      itemIds: z.array(z.string()).optional().describe("Item IDs to link to this transaction"),
    },
    async ({ projectId, budgetCategoryId, amountCents, type: txType, source, transactionDate, notes, itemIds }) => {
      const data: Record<string, unknown> = {
        budgetCategoryId,
        amountCents,
        type: txType,
        isCanceled: false,
        isComplete: false,
        createdAt: new Date(),
        updatedAt: new Date(),
      };
      if (projectId) data.projectId = projectId;
      if (source) data.source = source;
      if (transactionDate) data.transactionDate = transactionDate;
      if (notes) data.notes = notes;
      if (itemIds?.length) data.itemIds = itemIds;

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
    "Update transaction fields. isComplete recomputes automatically after every write via Cloud Function. For itemized categories, it becomes true when: (1) tax data exists (subtotalCents or taxRatePct is set), (2) items are linked, and (3) linked items' prices sum to within ±1% of the resolved pre-tax subtotal. Cannot be set manually.",
    {
      transactionId: z.string().describe("Transaction document ID"),
      amountCents: z.number().optional().describe("Total amount in cents (including tax)"),
      subtotalCents: z.number().optional().describe("Pre-tax subtotal in cents. Should be <= amountCents. When set with taxRatePct, the system can infer tax amount as amountCents - subtotalCents"),
      taxRatePct: z.number().optional().describe("Tax rate as a percentage (0-100, e.g. 8.25). When set with amountCents, the system infers subtotal as amountCents / (1 + taxRatePct / 100)"),
      type: z.string().optional().describe("Transaction type: Purchase, Return, Sale, To Inventory"),
      status: z.string().optional().describe("Transaction status (e.g. 'returned')"),
      source: z.string().optional().describe("Vendor/source name"),
      notes: z.string().optional().describe("Notes"),
      budgetCategoryId: z.string().optional().describe("Budget category ID"),
      transactionDate: z.string().optional().describe("Date string (e.g. '2024-03-15')"),
      itemIds: z.array(z.string()).optional().describe("Item IDs linked to this transaction (replaces existing list)"),
      projectId: z.string().optional().describe("Project ID — set to reassign transaction to a different project"),
      purchasedBy: z.string().optional().describe("Who made the purchase"),
      reimbursementType: z.string().optional().describe("Reimbursement type"),
      receiptEmailed: z.boolean().optional().describe("Whether a receipt was emailed"),
      paymentMethod: z.string().optional().describe("Payment method (e.g. 'Credit Card', 'Cash', 'Check')"),
    },
    async ({ transactionId, ...fields }) => {
      const updates: Record<string, unknown> = { updatedAt: new Date() };
      for (const [key, value] of Object.entries(fields)) {
        if (value !== undefined) updates[key] = value;
      }

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
        reimbursementType: z.string().optional(),
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
    "Mark a transaction as canceled. Canceled transactions contribute $0 to budget calculations.",
    { transactionId: z.string().describe("Transaction document ID") },
    async ({ transactionId }) => {
      await accountCollection(db, "transactions").doc(transactionId).update({
        isCanceled: true,
        updatedAt: new Date(),
      });
      return { content: [{ type: "text", text: `Canceled transaction ${transactionId}` }] };
    }
  );

  // ── attach_transaction_file ────────────────────────────────────────────────
  server.tool(
    "attach_transaction_file",
    "Attach an image or PDF to a transaction. Uploads to Firebase Storage and appends an AttachmentRef to the transaction's receipt or other images array. For images, generates sm (300px) and md (800px) thumbnails.",
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
