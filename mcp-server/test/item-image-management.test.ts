import { describe, expect, it } from "vitest";
import type { AttachmentRef } from "../src/types.js";
import {
  insertAttachment,
  orderedWithPrimary,
  partitionAttachmentStorageObjects,
  removeAttachment,
  reorderAttachments,
} from "../src/util/item-images.js";
import { storagePathFromUrl } from "../src/storage.js";

function storageUrl(path: string): string {
  return `https://firebasestorage.googleapis.com/v0/b/ledger-nine4.firebasestorage.app/o/${encodeURIComponent(path)}?alt=media&token=test`;
}

function images(): AttachmentRef[] {
  return [
    { url: "a", fileName: "a.jpg", isPrimary: true },
    { url: "b", fileName: "b.jpg", contentType: "image/jpeg", isPrimary: false },
    { url: "c", fileName: "c.jpg", thumbnailUrlSm: "c-sm", isPrimary: false },
  ];
}

describe("item image ordering and primary management", () => {
  it("changes primary and moves it to index zero without losing metadata", () => {
    const result = orderedWithPrimary(images(), "c");
    expect(result.map((image) => image.url)).toEqual(["c", "a", "b"]);
    expect(result.filter((image) => image.isPrimary)).toHaveLength(1);
    expect(result[0]).toMatchObject({ url: "c", thumbnailUrlSm: "c-sm", isPrimary: true });
  });

  it("reorders three images, preserving attachment metadata and the existing primary", () => {
    const result = reorderAttachments(images(), ["c", "b", "a"]);
    expect(result.map((image) => image.url)).toEqual(["c", "b", "a"]);
    expect(result.find((image) => image.isPrimary)?.url).toBe("a");
    expect(result[1]).toMatchObject({ fileName: "b.jpg", contentType: "image/jpeg" });
  });

  it("attaches a new image as primary at the requested position", () => {
    const result = insertAttachment(images(), { url: "d", fileName: "d.jpg" }, { isPrimary: true, position: 2 });
    expect(result.map((image) => image.url)).toEqual(["d", "a", "b", "c"]);
    expect(result.filter((image) => image.isPrimary).map((image) => image.url)).toEqual(["d"]);
  });

  it("automatically makes the first attachment primary", () => {
    expect(insertAttachment([], { url: "first" }, { isPrimary: false })).toEqual([
      { url: "first", isPrimary: true },
    ]);
  });

  it("maintains exactly one primary after repeated primary changes", () => {
    let result = images();
    for (const url of ["b", "c", "b", "a", "c"]) {
      result = orderedWithPrimary(result, url);
      expect(result.filter((image) => image.isPrimary)).toHaveLength(1);
      expect(result[0].url).toBe(url);
    }
  });

  it("removes an attachment reference without touching its URL", () => {
    const current = images();
    const result = removeAttachment(current, "a");
    expect(result.removed).toEqual(current[0]);
    expect(result.remaining.map((image) => image.url)).toEqual(["b", "c"]);
    expect(result.remaining.filter((image) => image.isPrimary)).toHaveLength(1);
  });

  it.each([
    [["a", "a", "c"], "duplicate"],
    [["a", "b"], "Missing"],
    [["a", "b", "foreign"], "Foreign"],
  ])("rejects invalid reorder URL sets: %j", (urls, message) => {
    expect(() => reorderAttachments(images(), urls, undefined)).toThrow(message);
  });

  it("rejects a foreign primary URL", () => {
    expect(() => orderedWithPrimary(images(), "foreign")).toThrow("current images");
  });

  it("preserves the primary when attaching without a primary change", () => {
    const result = insertAttachment(images(), { url: "d" }, { position: 0 });
    expect(result.find((image) => image.isPrimary)?.url).toBe("a");
  });
});

describe("item image deletion ownership", () => {
  it("allows deletion of an item-owned full image and thumbnails", () => {
    const attachment = {
      url: storageUrl("accounts/acc/items/item-1/photo.jpg"),
      thumbnailUrlSm: storageUrl("accounts/acc/items/item-1/photo_sm.jpg"),
      thumbnailUrlMd: storageUrl("accounts/acc/items/item-1/photo_md.jpg"),
    };
    const result = partitionAttachmentStorageObjects(attachment, "acc", "item-1", storagePathFromUrl);
    expect(result.external).toEqual([]);
    expect(result.owned.map(({ path }) => path)).toEqual([
      "accounts/acc/items/item-1/photo.jpg",
      "accounts/acc/items/item-1/photo_sm.jpg",
      "accounts/acc/items/item-1/photo_md.jpg",
    ]);
  });

  it("never marks protoItems, another item, or foreign URLs as deletable", () => {
    const protoUrl = storageUrl("accounts/acc/protoItems/draft-1/photo.jpg");
    const otherItemUrl = storageUrl("accounts/acc/items/item-2/photo.jpg");
    const attachment = { url: protoUrl, thumbnailUrlSm: otherItemUrl, thumbnailUrlMd: "https://example.com/shared.jpg" };
    const availableSourceFiles = new Set([protoUrl, otherItemUrl, attachment.thumbnailUrlMd]);
    const result = partitionAttachmentStorageObjects(attachment, "acc", "item-1", storagePathFromUrl);
    for (const { url } of result.owned) availableSourceFiles.delete(url);
    expect(result.owned).toEqual([]);
    expect(result.external).toHaveLength(3);
    expect(availableSourceFiles.has(protoUrl)).toBe(true);
  });
});
