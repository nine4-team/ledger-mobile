import type { AttachmentRef } from "../types.js";
import { storagePathFromUrl } from "../storage.js";

export interface ItemImageOperationResult {
  itemId: string;
  images: AttachmentRef[];
  primaryImageUrl: string | null;
  storageObjectsCopied: boolean;
  storageObjectsDeleted: boolean;
  storagePathsAffected: string[];
  warnings: string[];
}

export function attachmentStorageUrls(attachment: AttachmentRef): string[] {
  return [attachment.url, attachment.thumbnailUrlSm, attachment.thumbnailUrlMd]
    .filter((url): url is string => typeof url === "string" && url.length > 0);
}

export function itemStorageNamespace(accountId: string, itemId: string): string {
  return `accounts/${accountId}/items/${itemId}/`;
}

export function isPathOwnedByItem(path: string, accountId: string, itemId: string): boolean {
  return path.startsWith(itemStorageNamespace(accountId, itemId));
}

export function attachmentNamespaceWarnings(
  attachments: readonly AttachmentRef[],
  accountId: string,
  itemId: string
): string[] {
  const external = attachments.flatMap(attachmentStorageUrls).filter((url) => {
    const path = storagePathFromUrl(url);
    return !path || !isPathOwnedByItem(path, accountId, itemId);
  });
  return external.length > 0
    ? [`${external.length} attachment URL(s) point outside this item's Storage namespace; source/shared objects will be preserved.`]
    : [];
}

export function partitionAttachmentStorageObjects(
  attachment: AttachmentRef,
  accountId: string,
  itemId: string,
  pathFromUrl: (url: string) => string | null
): {
  owned: Array<{ url: string; path: string }>;
  external: string[];
} {
  const owned: Array<{ url: string; path: string }> = [];
  const external: string[] = [];
  for (const url of attachmentStorageUrls(attachment)) {
    const path = pathFromUrl(url);
    if (path && isPathOwnedByItem(path, accountId, itemId)) owned.push({ url, path });
    else external.push(url);
  }
  return { owned, external };
}

export function orderedWithPrimary(
  attachments: readonly AttachmentRef[],
  primaryUrl?: string
): AttachmentRef[] {
  if (attachments.length === 0) return [];
  const selectedUrl = primaryUrl
    ?? attachments.find((attachment) => attachment.isPrimary === true)?.url
    ?? attachments[0].url;
  const selectedIndex = attachments.findIndex((attachment) => attachment.url === selectedUrl);
  if (selectedIndex < 0) {
    throw new Error("Primary image URL must be one of the item's current images.");
  }
  const ordered = selectedIndex === 0
    ? [...attachments]
    : [attachments[selectedIndex], ...attachments.slice(0, selectedIndex), ...attachments.slice(selectedIndex + 1)];
  return ordered.map((attachment, index) => ({ ...attachment, isPrimary: index === 0 }));
}

export function reorderAttachments(
  attachments: readonly AttachmentRef[],
  orderedImageUrls: readonly string[],
  primaryImageUrl?: string
): AttachmentRef[] {
  if (new Set(orderedImageUrls).size !== orderedImageUrls.length) {
    throw new Error("orderedImageUrls contains duplicate URLs.");
  }
  const existingUrls = attachments.map((attachment) => attachment.url);
  if (new Set(existingUrls).size !== existingUrls.length) {
    throw new Error("The item contains duplicate image URLs and must be repaired before reordering.");
  }
  const supplied = new Set(orderedImageUrls);
  const existing = new Set(existingUrls);
  const missing = existingUrls.filter((url) => !supplied.has(url));
  const foreign = orderedImageUrls.filter((url) => !existing.has(url));
  if (missing.length > 0 || foreign.length > 0 || orderedImageUrls.length !== existingUrls.length) {
    throw new Error(
      `orderedImageUrls must exactly match the item's current image set. Missing: ${missing.join(", ") || "none"}. Foreign: ${foreign.join(", ") || "none"}.`
    );
  }
  if (primaryImageUrl !== undefined && !existing.has(primaryImageUrl)) {
    throw new Error("primaryImageUrl must be one of the item's current images.");
  }

  const byUrl = new Map(attachments.map((attachment) => [attachment.url, attachment]));
  const ordered = orderedImageUrls.map((url) => ({ ...byUrl.get(url)! }));
  const selectedPrimary = primaryImageUrl
    ?? attachments.find((attachment) => attachment.isPrimary === true)?.url
    ?? ordered[0]?.url;
  return ordered.map((attachment) => ({
    ...attachment,
    isPrimary: attachment.url === selectedPrimary,
  }));
}

export function insertAttachment(
  attachments: readonly AttachmentRef[],
  attachment: AttachmentRef,
  options: { isPrimary?: boolean; position?: number }
): AttachmentRef[] {
  if (attachments.some((current) => current.url === attachment.url)) {
    throw new Error("That image URL is already attached to the item.");
  }
  const position = options.position ?? attachments.length;
  if (!Number.isInteger(position) || position < 0 || position > attachments.length) {
    throw new Error(`position must be an integer from 0 through ${attachments.length}.`);
  }
  const next = [...attachments];
  next.splice(position, 0, { ...attachment, isPrimary: false });
  if (attachments.length === 0 || options.isPrimary === true) {
    return orderedWithPrimary(next, attachment.url);
  }
  return orderedWithPrimary(next);
}

export function removeAttachment(
  attachments: readonly AttachmentRef[],
  imageUrl: string
): { removed: AttachmentRef; remaining: AttachmentRef[] } {
  const index = attachments.findIndex((attachment) => attachment.url === imageUrl);
  if (index < 0) throw new Error("No attachment with that imageUrl exists on the item.");
  const removed = attachments[index];
  const remaining = attachments.filter((_, attachmentIndex) => attachmentIndex !== index);
  return { removed, remaining: orderedWithPrimary(remaining) };
}

export function imageOperationResult(args: {
  itemId: string;
  images: AttachmentRef[];
  storageObjectsCopied?: boolean;
  storageObjectsDeleted?: boolean;
  storagePathsAffected?: string[];
  warnings?: string[];
}): ItemImageOperationResult {
  return {
    itemId: args.itemId,
    images: args.images,
    primaryImageUrl: args.images.find((attachment) => attachment.isPrimary)?.url ?? null,
    storageObjectsCopied: args.storageObjectsCopied ?? false,
    storageObjectsDeleted: args.storageObjectsDeleted ?? false,
    storagePathsAffected: args.storagePathsAffected ?? [],
    warnings: args.warnings ?? [],
  };
}
