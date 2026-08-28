import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { type Firestore, FieldValue } from "firebase-admin/firestore";
import { z } from "zod";
import type { Space, Item } from "../types.js";
import { accountCollection, accountPath, queryDocs, getDoc } from "../util/query.js";
import { uploadToStorage, deleteFromStorage } from "../storage.js";
import { generateThumbnails, thumbnailPath } from "../util/thumbnail.js";
import type { AttachmentRef } from "../types.js";
import { normalizePrimaryAttachments } from "../util/attachment-primary.js";

export function registerSpaceTools(server: McpServer, db: Firestore) {
  // ── list_spaces ────────────────────────────────────────────────────────────
  server.tool(
    "list_spaces",
    "List spaces with item counts. Use projectId='inventory' for business inventory spaces.",
    {
      projectId: z.string().optional().describe("Filter by project ID, or 'inventory' for business inventory"),
    },
    async ({ projectId }) => {
      let query: FirebaseFirestore.Query = accountCollection(db, "spaces");
      if (projectId === "inventory") {
        query = query.where("projectId", "==", null);
      } else if (projectId) {
        query = query.where("projectId", "==", projectId);
      }

      const spaces = await queryDocs<Space>(query);

      // Get item counts per space
      const items = await queryDocs<Item>(accountCollection(db, "items"));
      const itemCountBySpace = new Map<string, number>();
      for (const item of items) {
        if (item.spaceId) {
          itemCountBySpace.set(item.spaceId, (itemCountBySpace.get(item.spaceId) ?? 0) + 1);
        }
      }

      const rows = spaces.map((s) => ({
        id: s.id,
        name: s.name,
        projectId: s.projectId ?? null,
        notes: s.notes ?? "",
        isComplete: s.isComplete === true,
        isArchived: s.isArchived,
        itemCount: itemCountBySpace.get(s.id) ?? 0,
        checklistCount: s.checklists?.length ?? 0,
      }));

      return { content: [{ type: "text", text: JSON.stringify(rows, null, 2) }] };
    }
  );

  // ── get_space ──────────────────────────────────────────────────────────────
  server.tool(
    "get_space",
    "Get a space with its items and checklist progress.",
    { spaceId: z.string().describe("Space document ID") },
    async ({ spaceId }) => {
      const space = await getDoc<Space>(db, "spaces", spaceId);
      if (!space) {
        return { content: [{ type: "text", text: `Space ${spaceId} not found.` }], isError: true };
      }

      // Items in this space
      const items = await queryDocs<Item>(
        accountCollection(db, "items").where("spaceId", "==", spaceId)
      );

      // Checklist progress
      const checklists = (space.checklists ?? []).map((cl) => {
        const total = cl.items.length;
        const checked = cl.items.filter((i) => i.isChecked).length;
        return {
          id: cl.id,
          name: cl.name,
          progress: `${checked}/${total}`,
        };
      });

      const result = {
        id: space.id,
        name: space.name,
        projectId: space.projectId ?? null,
        notes: space.notes ?? "",
        isComplete: space.isComplete === true,
        isArchived: space.isArchived,
        images: space.images ?? [],
        checklists,
        items: items.map((i) => ({
          id: i.id,
          name: i.name ?? i.description ?? "",
          status: i.status ?? "",
        })),
      };

      return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
    }
  );

  // ── create_space ───────────────────────────────────────────────────────────
  server.tool(
    "create_space",
    "Create a new space.",
    {
      name: z.string().describe("Space name"),
      projectId: z.string().optional().describe("Project ID (omit for business inventory)"),
      notes: z.string().optional().describe("Notes"),
    },
    async ({ name, projectId, notes }) => {
      const data: Record<string, unknown> = {
        name,
        isArchived: false,
        createdAt: new Date(),
        updatedAt: new Date(),
      };
      if (projectId) data.projectId = projectId;
      if (notes) data.notes = notes;

      const ref = await accountCollection(db, "spaces").add(data);
      return { content: [{ type: "text", text: `Created space ${ref.id}` }] };
    }
  );

  // ── update_space ───────────────────────────────────────────────────────────
  server.tool(
    "update_space",
    "Update space fields.",
    {
      spaceId: z.string().describe("Space document ID"),
      name: z.string().optional().describe("Space name"),
      notes: z.string().optional().describe("Notes"),
      isComplete: z.boolean().optional().describe("Whether the physical space is fully reconciled with Ledger"),
    },
    async ({ spaceId, ...fields }) => {
      const updates: Record<string, unknown> = { updatedAt: new Date() };
      for (const [key, value] of Object.entries(fields)) {
        if (value !== undefined) updates[key] = value;
      }

      await accountCollection(db, "spaces").doc(spaceId).update(updates);
      return { content: [{ type: "text", text: `Updated space ${spaceId}` }] };
    }
  );

  // ── attach_space_image ─────────────────────────────────────────────────────
  server.tool(
    "attach_space_image",
    "Attach an image or file to a space. Uploads to Firebase Storage and appends an AttachmentRef to the space's images array. For images, generates sm (300px) and md (800px) thumbnails. Returned URLs are public HTTPS download URLs (Firebase Storage token URLs) — fetch directly with curl/WebFetch later, no auth required.",
    {
      spaceId: z.string().describe("Space document ID"),
      fileData: z.string().optional().describe("Base64-encoded file content (provide this OR fileUrl, not both)"),
      fileUrl: z.string().optional().describe("URL to fetch the file from (provide this OR fileData, not both)"),
      fileName: z.string().describe("File name (e.g. 'photo.jpg', 'spec-sheet.pdf')"),
      contentType: z.string().optional().describe("MIME type (e.g. 'image/jpeg', 'image/png', 'application/pdf'). Inferred from response headers when using fileUrl."),
    },
    async ({ spaceId, fileData, fileUrl, fileName, contentType }) => {
      const space = await getDoc<Space>(db, "spaces", spaceId);
      if (!space) {
        return { content: [{ type: "text", text: `Space ${spaceId} not found.` }], isError: true };
      }

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

      const kind = resolvedContentType.startsWith("image/")
        ? "image"
        : resolvedContentType === "application/pdf"
          ? "pdf"
          : "file";

      const storagePath = `${accountPath()}/spaces/${spaceId}/${fileName}`;
      const url = await uploadToStorage(storagePath, data, resolvedContentType);

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

      const isPrimary = !space.images?.length;

      const entry: AttachmentRef = {
        url,
        kind,
        isPrimary,
      };
      if (fileName) entry.fileName = fileName;
      if (resolvedContentType) entry.contentType = resolvedContentType;
      if (thumbnailUrlSm) entry.thumbnailUrlSm = thumbnailUrlSm;
      if (thumbnailUrlMd) entry.thumbnailUrlMd = thumbnailUrlMd;

      try {
        const spaceRef = accountCollection(db, "spaces").doc(spaceId);
        await db.runTransaction(async (firestoreTransaction) => {
          const snapshot = await firestoreTransaction.get(spaceRef);
          const current = (snapshot.data()?.images as AttachmentRef[] | undefined) ?? [];
          firestoreTransaction.update(spaceRef, {
            images: normalizePrimaryAttachments([...current, entry]),
            updatedAt: new Date(),
          });
        });
      } catch (err) {
        await deleteFromStorage(url).catch(() => {});
        if (thumbnailUrlSm) await deleteFromStorage(thumbnailUrlSm).catch(() => {});
        if (thumbnailUrlMd) await deleteFromStorage(thumbnailUrlMd).catch(() => {});
        throw err;
      }

      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            message: `Attached ${fileName} to space ${spaceId}`,
            url,
            kind,
            thumbnailUrlSm: thumbnailUrlSm ?? null,
            thumbnailUrlMd: thumbnailUrlMd ?? null,
          }, null, 2),
        }],
      };
    }
  );

  // ── detach_space_image ─────────────────────────────────────────────────────
  server.tool(
    "detach_space_image",
    "Remove an attachment from a space. Deletes the file and its thumbnails from Firebase Storage and removes the AttachmentRef from the space's images array. If the removed image was primary, promotes the next image.",
    {
      spaceId: z.string().describe("Space document ID"),
      url: z.string().describe("The attachment URL to remove (matches the 'url' field in the AttachmentRef)"),
    },
    async ({ spaceId, url }) => {
      const space = await getDoc<Space>(db, "spaces", spaceId);
      if (!space) {
        return { content: [{ type: "text", text: `Space ${spaceId} not found.` }], isError: true };
      }

      const attachments = space.images;
      const entry = attachments?.find((a) => a.url === url);
      if (!entry) {
        return { content: [{ type: "text", text: "No attachment with that URL found in images." }], isError: true };
      }

      const remaining = normalizePrimaryAttachments(attachments!.filter((a) => a.url !== url));

      await accountCollection(db, "spaces").doc(spaceId).update({
        images: remaining,
        updatedAt: new Date(),
      });

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
          text: `Removed attachment from space ${spaceId}. Deleted from storage: ${deleted.join(", ") || "none (files may have already been removed)"}`,
        }],
      };
    }
  );
}
