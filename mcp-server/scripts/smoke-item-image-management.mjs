#!/usr/bin/env node
import { randomUUID } from "node:crypto";
import sharp from "sharp";
import { getStorage } from "firebase-admin/storage";
import { initFirebase } from "../build/firebase.js";
import { requestContext } from "../build/context.js";
import { registerItemTools } from "../build/tools/items.js";
import { registerQuickDraftItemTools } from "../build/tools/quick-draft-items.js";
import { deleteFromStorage, storagePathFromUrl, uploadToStorage } from "../build/storage.js";

const credentialsPath = process.argv[2] ?? process.env.GOOGLE_APPLICATION_CREDENTIALS;
const accountId = process.env.LEDGER_ACCOUNT_ID;
if (!credentialsPath || !accountId) {
  throw new Error("Usage: LEDGER_ACCOUNT_ID=... node scripts/smoke-item-image-management.mjs /path/to/service-account.json");
}
if (process.env.FIRESTORE_EMULATOR_HOST || process.env.STORAGE_EMULATOR_HOST) {
  throw new Error("This smoke test must verify real Firestore and Storage; emulator variables must be unset.");
}

const db = initFirebase(credentialsPath);
const runId = randomUUID();
const draftId = `mcp-image-smoke-draft-${runId}`;
const sourcePath = `accounts/${accountId}/protoItems/${draftId}/source.jpg`;
const createdItemIds = new Set();
let sourceUrl;

function capture(register) {
  const handlers = new Map();
  register({
    tool(name, _description, _schema, handler) { handlers.set(name, handler); },
    resource() {},
  }, db);
  return handlers;
}

function parse(result) {
  const payload = JSON.parse(result.content[0].text);
  if (result.isError) throw new Error(JSON.stringify(payload));
  return payload;
}

async function exists(url) {
  const path = storagePathFromUrl(url);
  if (!path) return false;
  const [present] = await getStorage().bucket("ledger-nine4.firebasestorage.app").file(path).exists();
  return present;
}

await requestContext.run({ accountId, uid: "mcp-image-smoke" }, async () => {
  try {
    const jpeg = await sharp({
      create: { width: 32, height: 24, channels: 3, background: { r: 40, g: 120, b: 200 } },
    }).jpeg().toBuffer();
    sourceUrl = await uploadToStorage(sourcePath, jpeg, "image/jpeg");
    await db.doc(`accounts/${accountId}/protoItems/${draftId}`).set({
      name: "MCP image management smoke test",
      status: "open",
      projectId: null,
      photos: [{ url: sourceUrl, fileName: "source.jpg", contentType: "image/jpeg", isPrimary: true }],
      createdAt: new Date(),
      updatedAt: new Date(),
    });

    const itemTools = capture(registerItemTools);
    const draftTools = capture(registerQuickDraftItemTools);
    const promoted = parse(await draftTools.get("promote_quick_draft_item")({ quickDraftItemId: draftId }));
    createdItemIds.add(promoted.itemId);
    if (!promoted.storageObjectsCopied || promoted.images.length !== 1) throw new Error("Promotion did not report one copied image.");
    if (!promoted.storagePathsAffected.every((path) => path.startsWith(`accounts/${accountId}/items/${promoted.itemId}/`))) {
      throw new Error("Promotion produced a non-item-owned path.");
    }
    if (!(await exists(sourceUrl))) throw new Error("Promotion removed the quick-draft source file.");
    for (const url of [promoted.images[0].url, promoted.images[0].thumbnailUrlSm, promoted.images[0].thumbnailUrlMd].filter(Boolean)) {
      if (!(await exists(url))) throw new Error(`Promoted item-owned object is missing: ${url}`);
    }

    const attached = parse(await itemTools.get("attach_item_image")({
      itemId: promoted.itemId,
      fileData: jpeg.toString("base64"),
      fileName: "attached.jpg",
      contentType: "image/jpeg",
      isPrimary: true,
      position: 1,
    }));
    if (attached.images[0].fileName !== "attached.jpg" || attached.images.filter((image) => image.isPrimary).length !== 1) {
      throw new Error("Attach-as-primary invariant failed.");
    }
    const attachedImage = attached.images[0];

    const selected = parse(await itemTools.get("set_primary_item_image")({
      itemId: promoted.itemId,
      imageUrl: promoted.images[0].url,
    }));
    if (selected.primaryImageUrl !== promoted.images[0].url || selected.storageObjectsDeleted) {
      throw new Error("Non-destructive primary selection failed.");
    }
    if (!(await exists(attachedImage.url))) throw new Error("Primary selection deleted an attachment.");

    const reordered = parse(await itemTools.get("reorder_item_images")({
      itemId: promoted.itemId,
      orderedImageUrls: [attachedImage.url, promoted.images[0].url],
    }));
    if (reordered.images[0].url !== attachedImage.url || reordered.primaryImageUrl !== promoted.images[0].url) {
      throw new Error("Reorder did not preserve the selected primary.");
    }

    const detached = parse(await itemTools.get("detach_item_image")({
      itemId: promoted.itemId,
      imageUrl: attachedImage.url,
    }));
    if (detached.storageObjectsDeleted || !(await exists(attachedImage.url))) {
      throw new Error("Detach deleted its Storage object.");
    }

    const deleted = parse(await itemTools.get("delete_item_image")({
      itemId: promoted.itemId,
      imageUrl: promoted.images[0].url,
    }));
    if (!deleted.storageObjectsDeleted || await exists(promoted.images[0].url)) {
      throw new Error("Explicit item-owned deletion did not remove the full image.");
    }

    await db.doc(`accounts/${accountId}/items/${promoted.itemId}`).update({
      images: [{ url: sourceUrl, fileName: "shared-source.jpg", contentType: "image/jpeg", isPrimary: true }],
      updatedAt: new Date(),
    });
    const protectedSource = parse(await itemTools.get("delete_item_image")({
      itemId: promoted.itemId,
      imageUrl: sourceUrl,
    }));
    if (protectedSource.storageObjectsDeleted || !(await exists(sourceUrl)) || protectedSource.warnings.length === 0) {
      throw new Error("Foreign/protoItems source deletion safeguard failed.");
    }

    console.log(JSON.stringify({
      ok: true,
      runId,
      itemId: promoted.itemId,
      verified: [
        "promoted item-owned copies and thumbnails",
        "source preservation",
        "attach primary",
        "non-destructive primary and reorder",
        "non-destructive detach",
        "explicit item-owned deletion",
        "protoItems deletion guard",
      ],
    }, null, 2));
  } finally {
    for (const itemId of createdItemIds) {
      await db.doc(`accounts/${accountId}/items/${itemId}`).delete().catch(() => {});
      await getStorage().bucket("ledger-nine4.firebasestorage.app")
        .deleteFiles({ prefix: `accounts/${accountId}/items/${itemId}/` })
        .catch(() => {});
    }
    await db.doc(`accounts/${accountId}/protoItems/${draftId}`).delete().catch(() => {});
    if (sourceUrl) await deleteFromStorage(sourceUrl).catch(() => {});
  }
});
