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
    needsReview: tx.needsReview ?? false,
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
    "List transactions with optional filters. Returns formatted amounts.",
    {
      projectId: z.string().optional().describe("Filter by project ID. Use 'inventory' for business inventory (projectId is null)."),
      budgetCategoryId: z.string().optional().describe("Filter by budget category ID"),
      type: z.string().optional().describe("Filter by transaction type (Purchase, Return, Sale, To Inventory)"),
      purchasedBy: z.string().optional().describe("Filter by purchasedBy value (e.g. 'client-card', 'design-business', 'Client')"),
      source: z.string().optional().describe("Filter by source/vendor name"),
      needsReview: z.boolean().optional().describe("Filter by needsReview flag"),
      reimbursementType: z.string().optional().describe("Filter by reimbursement type"),
      limit: z.number().default(50).describe("Max results"),
    },
    async ({ projectId, budgetCategoryId, type, purchasedBy, source, needsReview, reimbursementType, limit }) => {
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

      if (needsReview !== undefined) {
        query = query.where("needsReview", "==", needsReview);
      }

      if (reimbursementType) {
        query = query.where("reimbursementType", "==", reimbursementType);
      }

      query = query.limit(limit);
      const transactions = await queryDocs<Transaction>(query);
      const rows = transactions.map(formatTransaction);

      return { content: [{ type: "text", text: JSON.stringify(rows, null, 2) }] };
    }
  );

  // ── get_transaction ────────────────────────────────────────────────────────
  server.tool(
    "get_transaction",
    "Get a single transaction with its linked items resolved via itemIds.",
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
    "Search transactions by source, type, notes, purchasedBy, or amount. Case-insensitive client-side filter.",
    {
      query: z.string().describe("Search term"),
      projectId: z.string().optional().describe("Scope search to a project"),
      limit: z.number().default(25).describe("Max results"),
    },
    async ({ query: searchTerm, projectId, limit }) => {
      let q: FirebaseFirestore.Query = accountCollection(db, "transactions");
      if (projectId) q = q.where("projectId", "==", projectId);

      const all = await queryDocs<Transaction>(q);
      const matched = all
        .filter((tx) => transactionMatches(tx, searchTerm))
        .slice(0, limit);

      return { content: [{ type: "text", text: JSON.stringify(matched.map(formatTransaction), null, 2) }] };
    }
  );

  // ── create_transaction ─────────────────────────────────────────────────────
  server.tool(
    "create_transaction",
    "Create a new transaction.",
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
    "Update transaction fields.",
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
      needsReview: z.boolean().optional().describe("Flag transaction for user review"),
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
}
