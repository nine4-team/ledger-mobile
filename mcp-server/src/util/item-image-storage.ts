import { randomUUID } from "node:crypto";
import { posix as path } from "node:path";
import type { AttachmentRef } from "../types.js";
import {
  copyStorageObject,
  deleteFromStorage,
  storagePathFromUrl,
  uploadVerifiedToStorage,
} from "../storage.js";
import { generateThumbnails, thumbnailPath } from "./thumbnail.js";
import { orderedWithPrimary } from "./item-images.js";

export interface ItemImageStorageOps {
  copy: typeof copyStorageObject;
  uploadVerified: typeof uploadVerifiedToStorage;
  remove: typeof deleteFromStorage;
  thumbnails: typeof generateThumbnails;
}

const defaultStorageOps: ItemImageStorageOps = {
  copy: copyStorageObject,
  uploadVerified: uploadVerifiedToStorage,
  remove: deleteFromStorage,
  thumbnails: generateThumbnails,
};

function safeFileName(attachment: AttachmentRef): string {
  const sourcePath = storagePathFromUrl(attachment.url);
  const candidate = attachment.fileName ?? (sourcePath ? path.basename(sourcePath) : "image");
  return candidate.replace(/[^A-Za-z0-9._-]/g, "_") || "image";
}

export interface CopiedItemImages {
  images: AttachmentRef[];
  copiedPaths: string[];
  copiedUrls: string[];
}

/**
 * Copy draft photos into an item's namespace. All Storage work completes and
 * is verified before the caller mutates Firestore. On failure, new objects are
 * cleaned up best-effort and draft/source objects are never touched.
 */
export async function copyAttachmentsToItemNamespace(
  attachments: readonly AttachmentRef[],
  accountId: string,
  itemId: string,
  primarySourceUrl?: string,
  ops: ItemImageStorageOps = defaultStorageOps
): Promise<CopiedItemImages> {
  if (attachments.length === 0) {
    if (primarySourceUrl !== undefined) {
      throw new Error("primaryImageUrl was provided, but the quick draft has no photos.");
    }
    return { images: [], copiedPaths: [], copiedUrls: [] };
  }
  const urls = attachments.map((attachment) => attachment.url);
  if (new Set(urls).size !== urls.length) throw new Error("Draft photos contain duplicate URLs.");
  const selectedPrimary = primarySourceUrl
    ?? attachments.find((attachment) => attachment.isPrimary === true)?.url
    ?? attachments[0].url;
  if (!urls.includes(selectedPrimary)) {
    throw new Error("primaryImageUrl must match one of the quick draft's current photo URLs.");
  }

  const createdUrls: string[] = [];
  const createdPaths: string[] = [];
  const copied: Array<{ sourceUrl: string; attachment: AttachmentRef }> = [];
  try {
    for (const sourceAttachment of attachments) {
      const fileName = `${randomUUID()}-${safeFileName(sourceAttachment)}`;
      const destinationPath = `accounts/${accountId}/items/${itemId}/${fileName}`;
      const full = await ops.copy(sourceAttachment.url, destinationPath);
      createdUrls.push(full.url);
      createdPaths.push(full.path);

      const next: AttachmentRef = {
        ...sourceAttachment,
        url: full.url,
        fileName: sourceAttachment.fileName ?? safeFileName(sourceAttachment),
        contentType: sourceAttachment.contentType ?? full.contentType,
        isPrimary: sourceAttachment.url === selectedPrimary,
      };
      delete next.thumbnailUrlSm;
      delete next.thumbnailUrlMd;

      const thumbnails = await ops.thumbnails(full.data, full.contentType);
      if (thumbnails.sm) {
        const smPath = thumbnailPath(destinationPath, "sm");
        next.thumbnailUrlSm = await ops.uploadVerified(smPath, thumbnails.sm, "image/jpeg");
        createdUrls.push(next.thumbnailUrlSm);
        createdPaths.push(smPath);
      }
      if (thumbnails.md) {
        const mdPath = thumbnailPath(destinationPath, "md");
        next.thumbnailUrlMd = await ops.uploadVerified(mdPath, thumbnails.md, "image/jpeg");
        createdUrls.push(next.thumbnailUrlMd);
        createdPaths.push(mdPath);
      }
      copied.push({ sourceUrl: sourceAttachment.url, attachment: next });
    }
  } catch (error) {
    await Promise.allSettled(createdUrls.map((url) => ops.remove(url)));
    throw error;
  }

  const primaryCopyUrl = copied.find(({ sourceUrl }) => sourceUrl === selectedPrimary)!.attachment.url;
  return {
    images: orderedWithPrimary(copied.map(({ attachment }) => attachment), primaryCopyUrl),
    copiedPaths: createdPaths,
    copiedUrls: createdUrls,
  };
}

export async function cleanupCopiedItemImages(
  copied: CopiedItemImages,
  ops: Pick<ItemImageStorageOps, "remove"> = defaultStorageOps
): Promise<void> {
  await Promise.allSettled(copied.copiedUrls.map((url) => ops.remove(url)));
}
